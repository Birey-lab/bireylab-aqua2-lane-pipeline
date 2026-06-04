<#
.SYNOPSIS
    Profile one TIFF through aqua_lane.exe and recommend a lane count
    for parallel detection on the current instance.

.DESCRIPTION
    Runs aqua_lane.exe on a single representative TIFF, samples the
    process's RAM usage every few seconds (ignoring MATLAB Runtime
    warmup), and combines the result with the instance's CPU/RAM specs
    to recommend how many parallel lanes to run.

    Pick the LARGEST file in your dataset as the probe. Largest file =
    best proxy for peak demand. The script can pick it for you if you
    pass -ProbeFolder.

.PARAMETER ProbeTif
    Path to a single .tif/.tiff file to profile.

.PARAMETER ProbeFolder
    Path to a folder of TIFFs; the largest will be auto-picked as probe.

.PARAMETER ExePath
    Path to aqua_lane.exe (default: C:\AQuA2\compiled\aqua_lane.exe).

.PARAMETER SafetyFactor
    Multiplier applied to observed peak RAM to leave headroom (default 1.5).
    Bump to 2.0+ if you've seen OOM crashes in similar runs.

.PARAMETER SampleSec
    How often (seconds) to poll the process for RAM (default 5).

.PARAMETER WarmupSec
    Seconds of samples to ignore at start (MCR warmup transient; default 30).

.PARAMETER MaxLanes
    Hard cap on recommended lanes (default 32).

.EXAMPLE
    .\Auto-Size-Lanes.ps1 -ProbeFolder C:\Users\Administrator\Documents\AllTIFFs

.EXAMPLE
    .\Auto-Size-Lanes.ps1 -ProbeTif C:\probe\biggest.tif -SafetyFactor 2.0
#>

[CmdletBinding(DefaultParameterSetName='ByFile')]
param(
    [Parameter(ParameterSetName='ByFile', Mandatory=$true)]
    [string]$ProbeTif,

    [Parameter(ParameterSetName='ByFolder', Mandatory=$true)]
    [string]$ProbeFolder,

    [string]$ExePath = "C:\AQuA2\compiled\aqua_lane.exe",

    [double]$SafetyFactor = 1.5,

    [int]$SampleSec = 5,

    [int]$WarmupSec = 30,

    [int]$MaxLanes = 32
)

$ErrorActionPreference = 'Stop'

# ---------- Sanity checks ----------
if (-not (Test-Path $ExePath)) {
    Write-Error "aqua_lane.exe not found at $ExePath. Pass -ExePath or fix the path."
}

if ($PSCmdlet.ParameterSetName -eq 'ByFolder') {
    if (-not (Test-Path $ProbeFolder)) {
        Write-Error "Probe folder not found: $ProbeFolder"
    }
    $largest = Get-ChildItem -Path $ProbeFolder -Recurse -Include *.tif,*.tiff -File |
               Sort-Object Length -Descending | Select-Object -First 1
    if (-not $largest) {
        Write-Error "No .tif/.tiff files found under $ProbeFolder"
    }
    $ProbeTif = $largest.FullName
    Write-Host ("Auto-picked largest TIFF: {0} ({1:N1} MB)" -f $ProbeTif, ($largest.Length/1MB))
}

if (-not (Test-Path $ProbeTif)) {
    Write-Error "Probe TIFF not found: $ProbeTif"
}

# ---------- Instance capacity ----------
$sys = Get-CimInstance Win32_ComputerSystem
$cpu = $sys.NumberOfLogicalProcessors
$ramGB = [math]::Round($sys.TotalPhysicalMemory / 1GB, 1)

$instanceType = "(unknown)"
try {
    $token = Invoke-WebRequest -UseBasicParsing -Method PUT `
        -Uri "http://169.254.169.254/latest/api/token" `
        -Headers @{'X-aws-ec2-metadata-token-ttl-seconds'='60'} `
        -TimeoutSec 3 -ErrorAction Stop | Select-Object -ExpandProperty Content
    $instanceType = (Invoke-WebRequest -UseBasicParsing `
        -Headers @{'X-aws-ec2-metadata-token' = $token} `
        -Uri "http://169.254.169.254/latest/meta-data/instance-type" `
        -TimeoutSec 3).Content
} catch {
    # not on EC2 or IMDS blocked
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Auto-Size-Lanes: Profile + Recommendation" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host ("Instance type:     {0}" -f $instanceType)
Write-Host ("Logical CPUs:      {0}" -f $cpu)
Write-Host ("Total RAM:         {0} GB" -f $ramGB)
Write-Host ("Probe file:        {0}" -f $ProbeTif)
$probeSize = (Get-Item $ProbeTif).Length / 1MB
Write-Host ("Probe size:        {0:N1} MB" -f $probeSize)
Write-Host ("Safety factor:     {0}x" -f $SafetyFactor)
Write-Host ""

# ---------- Prepare scratch ----------
$scratch = Join-Path $env:TEMP "autosize_$(Get-Date -Format 'yyyyMMddHHmmss')"
$probeIn  = Join-Path $scratch "in"
$probeOut = Join-Path $scratch "out"
New-Item -ItemType Directory -Path $probeIn  -Force | Out-Null
New-Item -ItemType Directory -Path $probeOut -Force | Out-Null
Copy-Item $ProbeTif (Join-Path $probeIn (Split-Path $ProbeTif -Leaf))

# ---------- Profile ----------
Write-Host "Starting probe (output streaming below)..." -ForegroundColor Yellow
Write-Host ("Will ignore the first {0}s of RAM samples to skip MCR warmup." -f $WarmupSec)
Write-Host ""

$proc = Start-Process -FilePath $ExePath `
    -ArgumentList "`"$probeIn`"", "`"$probeOut`"" `
    -PassThru -NoNewWindow

$startTime = Get-Date
$peakRAM_GB = 0
$samples = 0
$warmupSkipped = 0

while (-not $proc.HasExited) {
    Start-Sleep -Seconds $SampleSec
    try {
        $p = Get-Process -Id $proc.Id -ErrorAction Stop
        $curGB = [math]::Round($p.WorkingSet64 / 1GB, 2)
        $elapsedSec = ((Get-Date) - $startTime).TotalSeconds

        if ($elapsedSec -lt $WarmupSec) {
            $warmupSkipped++
            Write-Host ("  [warmup t={0,4:N0}s] RAM = {1:N2} GB (ignored)" -f $elapsedSec, $curGB)
        } else {
            $samples++
            if ($curGB -gt $peakRAM_GB) { $peakRAM_GB = $curGB }
            Write-Host ("  [steady t={0,4:N0}s] RAM = {1:N2} GB   peak = {2:N2} GB" -f $elapsedSec, $curGB, $peakRAM_GB)
        }
    } catch {
        # Process may have exited between HasExited check and Get-Process
    }
}

$elapsed = (Get-Date) - $startTime
$elapsedMin = [math]::Round($elapsed.TotalMinutes, 2)

# ---------- Compute recommendation ----------
if ($peakRAM_GB -le 0) {
    Write-Host ""
    Write-Warning "No steady-state RAM samples captured. The probe finished too fast (or before warmup ended)."
    Write-Warning "Falling back to CPU-only recommendation."
    $ramPerLane = 0
    $maxByRAM = $MaxLanes  # no constraint from RAM
} else {
    $ramPerLane = [math]::Round($peakRAM_GB * $SafetyFactor, 2)
    $maxByRAM = [math]::Floor($ramGB / $ramPerLane)
}
$maxByCPU = [math]::Floor($cpu / 3)
$recommendedLanes = [math]::Min([math]::Min($maxByRAM, $maxByCPU), $MaxLanes)
if ($recommendedLanes -lt 1) { $recommendedLanes = 1 }

# Which constraint binds?
$binding = if ($recommendedLanes -eq $maxByCPU) {
    "CPU (need ~3 vCPU per worker)"
} elseif ($recommendedLanes -eq $maxByRAM) {
    "RAM (per-file demand x safety)"
} else {
    "user-imposed cap (MaxLanes=$MaxLanes)"
}

# ---------- Report ----------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " RESULTS" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ("Wall-clock for probe:           {0:N1} min" -f $elapsedMin)
Write-Host ("Peak RAM (steady-state):        {0:N2} GB" -f $peakRAM_GB)
Write-Host ("Steady-state samples:           {0}  (warmup skipped: {1})" -f $samples, $warmupSkipped)
if ($peakRAM_GB -gt 0) {
    Write-Host ("Per-lane budget with {0}x safety: {1:N2} GB" -f $SafetyFactor, $ramPerLane)
}
Write-Host ""
Write-Host ("RAM-limited lane count:         {0}" -f $maxByRAM)
Write-Host ("CPU-limited lane count:         {0}" -f $maxByCPU)
Write-Host ("Hard cap (MaxLanes):            {0}" -f $MaxLanes)
Write-Host ""
Write-Host ("===> Recommended lanes:          {0}" -f $recommendedLanes) -ForegroundColor Green
Write-Host ("===> Binding constraint:         {0}" -f $binding) -ForegroundColor Green
Write-Host ""

# Write recommendation to a well-known file so Run-Pipeline.ps1 can read it
# reliably (parsing Write-Host stdout is unreliable across PowerShell host types).
$recommendationFile = Join-Path $env:TEMP "autosize_recommendation.txt"
$recommendedLanes | Out-File -FilePath $recommendationFile -Encoding ASCII -NoNewline
Write-Host ("(recommendation written to {0})" -f $recommendationFile)
Write-Host ""

# ---------- Suggested commands ----------
Write-Host "Suggested next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  # Detection (use recommended lanes)" -ForegroundColor Yellow
Write-Host ("  .\Split-IntoLanes.ps1 -Source <TIFFs> -LaneRoot <lanes> -Lanes {0} -Execute" -f $recommendedLanes)
Write-Host ("  .\Launch-Lanes-Exe.ps1 -LaneRoot <lanes> -ResultsRoot <PreCFU> -Lanes {0}" -f $recommendedLanes)
Write-Host ""
$cfuLanes = [math]::Max([math]::Floor($recommendedLanes * 0.75), 1)
Write-Host "  # CFU (memory-bound; rule of thumb ~75% of detection lanes)" -ForegroundColor Yellow
Write-Host ("  .\Build-CFU-Lanes.ps1 -Root <PreCFU> -LaneRoot <CFU_lanes> -Lanes {0} -Execute" -f $cfuLanes)
Write-Host ("  .\Launch-CFU-Lanes.ps1 -LaneRoot <CFU_lanes> -Post <POST> -LogDir <CFU_lanes>\_logs -Lanes {0}" -f $cfuLanes)
Write-Host ""

# IO warning
Write-Host "Disk IO check:" -ForegroundColor Yellow
Write-Host ("  {0} lanes simultaneously reading TIFFs may saturate gp3 default 125 MB/s." -f $recommendedLanes)
Write-Host "  If CPU utilization stays below 80% with all lanes running, the bottleneck is IO."
Write-Host "  Bump gp3 throughput in AWS Console (Volumes -> Modify -> Throughput) to 250-500 MB/s."
Write-Host ""

# Save concise summary
$summaryPath = Join-Path $env:TEMP "autosize_summary_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
@"
Auto-Size-Lanes summary
=======================
Date:            $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Instance type:   $instanceType
Logical CPUs:    $cpu
Total RAM:       $ramGB GB
Probe file:      $ProbeTif
Probe size:      $([math]::Round($probeSize,1)) MB
Wall-clock:      $elapsedMin min
Peak RAM:        $peakRAM_GB GB
Safety factor:   ${SafetyFactor}x
Per-lane RAM:    $ramPerLane GB
RAM-limited:     $maxByRAM
CPU-limited:     $maxByCPU
Recommendation:  $recommendedLanes lanes (detection), $cfuLanes lanes (CFU)
Binding:         $binding
"@ | Out-File $summaryPath -Encoding UTF8

Write-Host ("Summary saved to: {0}" -f $summaryPath)
Write-Host ""

# ---------- Cleanup ----------
try {
    Remove-Item $scratch -Recurse -Force -ErrorAction Stop
    Write-Host "(Scratch folder cleaned up.)"
} catch {
    Write-Warning "Could not clean up scratch folder at $scratch. Delete manually when convenient."
}
