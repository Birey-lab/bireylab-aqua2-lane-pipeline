<#
.SYNOPSIS
    End-to-end AQuA2 pipeline orchestrator with explicit per-phase toggles.

.DESCRIPTION
    Runs any subset of the pipeline phases on a folder of TIFFs:
      Phase 0 - Auto-size detection lanes (if -Lanes not specified)
      Phase 1 - Split TIFFs into balanced lane folders   (-Split,  default ON)
      Phase 2 - Detection (parallel aqua_lane.exe)       (-Detect, default ON)
      Phase 3 - CFU build + run                          (-CFU,    default OFF)
      Phase 4 - S3 upload                                (-Upload, default OFF)

    The default ON-ON-OFF-OFF gives a natural checkpoint after detection:
    inspect results, verify file counts, adjust CFU lane count if needed,
    THEN re-run with -CFU $true to continue. Avoids accidentally committing
    hours of compute to CFU on a broken detection run.

    Pre-flight checks run BEFORE any heavy work. Pre-flight summary prints
    the plan with checkmarks and requires confirmation (skip with -Force).

    Real-time progress prints every 60 seconds during long phases, with a
    detailed snapshot every 5 minutes.

    Individual scripts (Split-IntoLanes.ps1, Launch-Lanes-Exe.ps1, etc.)
    still work standalone for step-by-step users.

.PARAMETER InputTIFFs
    Folder containing TIFFs to process. Required if -Split is true.

.PARAMETER OutputRoot
    Root for all pipeline outputs. Subfolders created automatically:
      <OutputRoot>/lanes/      detection lane staging
      <OutputRoot>/PreCFU/     detection outputs (_AQuA2.mat)
      <OutputRoot>/CFU_lanes/  CFU lane junctions
      <OutputRoot>/POST/       CFU outputs (_res_cfu.mat)
      <OutputRoot>/_logs/      pipeline logs

.PARAMETER Split
    Run Phase 1 (split TIFFs into lanes). Default: $true.

.PARAMETER Detect
    Run Phase 2 (detection). Default: $true.

.PARAMETER CFU
    Run Phase 3 (CFU build + run, combined). Default: $false.

.PARAMETER Upload
    Run Phase 4 (S3 sync). Default: $false. Requires -S3Prefix.

.PARAMETER Lanes
    Detection lane count. If 0 (default), runs Auto-Size-Lanes.ps1 first.

.PARAMETER CFULanes
    CFU lane count. If 0 (default), uses floor(Lanes * 0.75).

.PARAMETER ConfigCSV
    Path to a parameters_for_batch.csv to use for THIS dataset. If specified,
    the orchestrator backs up the existing default and copies this CSV into
    C:\AQuA2\cfg\parameters_for_batch.csv before launching detection.
    If omitted, uses whatever is already at the default location.

.PARAMETER S3Prefix
    Required if -Upload $true. Destination like s3://bucket/prefix/

.PARAMETER MinFreeDiskGB
    Abort detection if free disk drops below this on C:\. Default: 50.

.PARAMETER Force
    Skip the pre-flight "Proceed?" confirmation prompt.

.PARAMETER WhatIfMode
    Show plan + pre-flight without executing anything.

.PARAMETER PollEverySec
    Seconds between one-line status updates. Default: 60.

.PARAMETER DetailEverySec
    Seconds between detailed snapshots. Default: 300.

.PARAMETER ScriptsDir
    Folder containing the other pipeline scripts. Default: this script's folder.

.EXAMPLE
    # Default: split + detection only, stop and let user inspect
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS

.EXAMPLE
    # With custom parameter CSV
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS `
                       -ConfigCSV C:\NewDS\my_params.csv

.EXAMPLE
    # Continue to CFU after reviewing detection results
    .\Run-Pipeline.ps1 -OutputRoot C:\NewDS -Split $false -Detect $false -CFU $true

.EXAMPLE
    # Full end-to-end including upload, no confirmation prompt
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS `
                       -CFU $true -Upload $true `
                       -S3Prefix s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/NewDS/ `
                       -Force
#>

[CmdletBinding()]
param(
    [string]$InputTIFFs,
    [Parameter(Mandatory=$true)] [string]$OutputRoot,

    # --- Phase toggles (default ON ON OFF OFF) ---
    [bool]$Split  = $true,
    [bool]$Detect = $true,
    [bool]$CFU    = $false,
    [bool]$Upload = $false,

    # --- Detection parameters ---
    [int]$Lanes = 0,
    [string]$ConfigCSV = '',

    # --- CFU parameters ---
    [int]$CFULanes = 0,

    # --- Upload ---
    [string]$S3Prefix = '',

    # --- Safety / behavior ---
    [int]$MinFreeDiskGB = 50,
    [int]$PollEverySec = 60,
    [int]$DetailEverySec = 300,
    [switch]$Force,
    [switch]$WhatIfMode,

    [string]$ScriptsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# ==========================================================
# Output helpers
# ==========================================================
function Hdr($txt) {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host (" $txt") -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
}
function Phase($num, $name) {
    Write-Host ""
    Write-Host ("[PHASE {0}] {1}" -f $num, $name) -ForegroundColor Green
    Write-Host ("  Started: {0}" -f (Get-Date -Format 'HH:mm:ss'))
    Write-Host ""
}
function PhaseEnd($num, $name, $start, $extra) {
    $dur = (Get-Date) - $start
    Write-Host ""
    Write-Host ("[PHASE {0} COMPLETE] {1}" -f $num, $name) -ForegroundColor Green
    Write-Host ("  Duration: {0:hh\:mm\:ss}" -f $dur)
    if ($extra) { Write-Host "  $extra" }
}
function Note($txt)  { Write-Host "  $txt" }
function OK2($txt)   { Write-Host "  [OK]   $txt" -ForegroundColor Green }
function Warn2($txt) { Write-Host "  [WARN] $txt" -ForegroundColor Yellow }
function Err2($txt)  { Write-Host "  [ERR]  $txt" -ForegroundColor Red }
function Get-FreeGB { [math]::Round((Get-PSDrive C).Free / 1GB, 1) }
function Get-AvailRAMGB {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    } catch { return -1 }
}

# ==========================================================
# Audit-trail helpers
# ==========================================================
function Save-ParametersInUse {
    # Copy active parameters_for_batch.csv into _logs/
    $activeCSV = "C:\AQuA2\cfg\parameters_for_batch.csv"
    $dest = Join-Path $paths['logs'] "parameters_for_batch_USED.csv"
    if (Test-Path $activeCSV) {
        Copy-Item $activeCSV $dest -Force
        OK2 ("audit: archived active parameters_for_batch.csv -> {0}" -f $dest)
    } else {
        Warn2 "audit: no parameters_for_batch.csv found at C:\AQuA2\cfg\ to archive"
    }
}

function Save-CFUBakedParameters {
    $bakedSrc = "C:\AQuA2\cfg\cfu_parameters_BAKED.txt"
    $dest = Join-Path $paths['logs'] "cfu_parameters_BAKED.txt"
    if (Test-Path $bakedSrc) {
        Copy-Item $bakedSrc $dest -Force
        OK2 ("audit: archived CFU baked-parameters reference -> {0}" -f $dest)
    } else {
        Warn2 "audit: cfu_parameters_BAKED.txt not found at C:\AQuA2\cfg\."
        Warn2 "       CFU thresholds in use will NOT be captured in the audit trail."
        Warn2 "       Install it on the AMI from the repo (config/cfu_parameters_BAKED.txt)."
    }
}

function Write-PerFileStatus {
    param(
        [string]$Phase,
        [string]$ResultsDir,
        [string]$OkPattern,
        [string]$FailDir
    )
    $rows = New-Object System.Collections.ArrayList
    $okFiles = Get-ChildItem $ResultsDir -Recurse -Filter $OkPattern -File -ErrorAction SilentlyContinue
    foreach ($f in $okFiles) {
        [void]$rows.Add([pscustomobject]@{
            file         = $f.Name
            phase        = $Phase
            status       = 'OK'
            completed    = $f.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            size_bytes   = $f.Length
            location     = $f.DirectoryName
        })
    }
    # _ERROR.txt files (under _failures/ folders or alongside outputs)
    $failFiles = Get-ChildItem $ResultsDir -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue
    foreach ($f in $failFiles) {
        [void]$rows.Add([pscustomobject]@{
            file         = ($f.Name -replace '_ERROR\.txt$','')
            phase        = $Phase
            status       = 'FAIL'
            completed    = $f.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            size_bytes   = $f.Length
            location     = $f.DirectoryName
        })
    }
    $dest = Join-Path $paths['logs'] ("per_file_status_{0}.csv" -f $Phase)
    if ($rows.Count -gt 0) {
        $rows | Export-Csv -Path $dest -NoTypeInformation
        OK2 ("audit: per-file status CSV -> {0} ({1} files)" -f $dest, $rows.Count)
    } else {
        Warn2 ("audit: no result files found for $Phase phase")
    }
}

function Write-RunManifest {
    param(
        [datetime]$Started,
        [datetime]$Completed,
        [hashtable]$Counts
    )
    $exeAqua = "C:\AQuA2\compiled\aqua_lane.exe"
    $exeCfu  = "C:\AQuA2\compiled\cfu_lane.exe"

    $manifest = [ordered]@{
        run_id           = $Started.ToString('yyyyMMdd_HHmmss')
        started          = $Started.ToString('yyyy-MM-ddTHH:mm:ss')
        completed        = $Completed.ToString('yyyy-MM-ddTHH:mm:ss')
        wall_clock       = ('{0:hh\:mm\:ss}' -f ($Completed - $Started))
        output_root      = $OutputRoot
        input_tiffs      = $InputTIFFs
        phases_run       = @(@(
            if ($Split)  { 'split' },
            if ($Detect) { 'detect' },
            if ($CFU)    { 'cfu' },
            if ($Upload) { 'upload' }
        ) | Where-Object { $_ })
        detection_lanes  = $Lanes
        cfu_lanes        = $CFULanes
        config_csv       = if ($ConfigCSV) { $ConfigCSV } else { '(default at C:\AQuA2\cfg\parameters_for_batch.csv)' }
        s3_prefix        = $S3Prefix
        workers          = [ordered]@{
            aqua_lane = if (Test-Path $exeAqua) { [ordered]@{
                path = $exeAqua
                size_bytes = (Get-Item $exeAqua).Length
                modified = (Get-Item $exeAqua).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            } } else { '(not found)' }
            cfu_lane = if (Test-Path $exeCfu) { [ordered]@{
                path = $exeCfu
                size_bytes = (Get-Item $exeCfu).Length
                modified = (Get-Item $exeCfu).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            } } else { '(not found)' }
        }
        instance         = [ordered]@{
            instance_type = $script:instanceType
            vCPUs         = $cpu
            ram_GB        = $ramGB
        }
        counts           = $Counts
    }

    $dest = Join-Path $paths['logs'] "run_manifest.json"
    $manifest | ConvertTo-Json -Depth 6 | Out-File $dest -Encoding UTF8
    OK2 ("audit: machine-readable manifest -> {0}" -f $dest)
}

function Write-RunSummary {
    param(
        [datetime]$Started,
        [datetime]$Completed,
        [hashtable]$Counts
    )
    $wall = '{0:hh\:mm\:ss}' -f ($Completed - $Started)
    $boxX = '[X]'
    $boxE = '[ ]'
    $rows = @(
        ('{0} Split TIFFs into lanes'      -f ($(if ($Split)  { $boxX } else { $boxE })))
        ('{0} Detection (aqua_lane.exe)'   -f ($(if ($Detect) { $boxX } else { $boxE })))
        ('{0} CFU (build + run)'           -f ($(if ($CFU)    { $boxX } else { $boxE })))
        ('{0} S3 upload'                   -f ($(if ($Upload) { $boxX } else { $boxE })))
    )

    $md = @"
# Pipeline Run Summary

**Run ID:** $($Started.ToString('yyyyMMdd_HHmmss'))
**Started:** $($Started.ToString('yyyy-MM-dd HH:mm:ss'))
**Completed:** $($Completed.ToString('yyyy-MM-dd HH:mm:ss'))
**Wall-clock:** $wall

## Phases run

$($rows -join "`n")

## Configuration

**Detection parameters CSV:** see ``parameters_for_batch_USED.csv`` in this folder.
$(if ($ConfigCSV) { "Source: ``$ConfigCSV``" } else { "Source: default at ``C:\AQuA2\cfg\parameters_for_batch.csv`` (no override)" })

**CFU clustering parameters:** see ``cfu_parameters_BAKED.txt`` in this folder.
These are compiled into ``cfu_lane.exe``. To change, edit ``C:\AQuA2\cfu_lane.m``, recompile, and update the BAKED file.

## Compute

- Instance type:      $script:instanceType
- Logical CPUs:       $cpu
- Total RAM:          $ramGB GB
- Detection lanes:    $Lanes
- CFU lanes:          $CFULanes

## Workers

| Worker | Path | Size | Compiled |
|---|---|---|---|
| ``aqua_lane.exe`` | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { 'C:\AQuA2\compiled\aqua_lane.exe' } else { '(not present)' }) | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { '{0:N0} bytes' -f (Get-Item 'C:\AQuA2\compiled\aqua_lane.exe').Length } else { '-' }) | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { (Get-Item 'C:\AQuA2\compiled\aqua_lane.exe').LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }) |
| ``cfu_lane.exe`` | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { 'C:\AQuA2\compiled\cfu_lane.exe' } else { '(not present)' }) | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { '{0:N0} bytes' -f (Get-Item 'C:\AQuA2\compiled\cfu_lane.exe').Length } else { '-' }) | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { (Get-Item 'C:\AQuA2\compiled\cfu_lane.exe').LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }) |

## Results

| Metric | Value |
|---|---|
| Input TIFFs | $($Counts['input_count']) |
| Detection succeeded | $($Counts['detection_ok']) |
| Detection failed | $($Counts['detection_fail']) |
| CFU succeeded | $($Counts['cfu_ok']) |
| CFU failed | $($Counts['cfu_fail']) |

## Files in this folder

- ``pipeline_<timestamp>.log`` — full orchestrator transcript (verbose)
- ``parameters_for_batch_USED.csv`` — the parameter CSV in effect for THIS run's detection
- ``cfu_parameters_BAKED.txt`` — what's compiled into the cfu_lane.exe used
- ``per_file_status_detection.csv`` — file-by-file detection results
- ``per_file_status_cfu.csv`` — file-by-file CFU results
- ``run_manifest.json`` — machine-readable summary (for programmatic comparison across runs)
- ``RUN_SUMMARY.md`` — this file

## To go deeper

- Per-lane detection logs: ``$($paths['lanes'])\_logs\lane<N>.log``
- Per-lane CFU logs: ``$($paths['CFU_lanes'])\_logs\cfu_lane<N>.log``
- Per-file failure details: ``$($paths['PreCFU'])\<stem>\_failures\<name>_ERROR.txt`` (detection) and ``$($paths['POST'])\_failures\<name>_ERROR.txt`` (CFU)
- Authoritative per-file parameters: ``opts`` struct inside each ``_AQuA2.mat`` file
"@

    $dest = Join-Path $paths['logs'] "RUN_SUMMARY.md"
    $md | Out-File $dest -Encoding UTF8
    OK2 ("audit: human-readable summary -> {0}" -f $dest)
}

$pipelineStart = Get-Date

# ==========================================================
# Resolve / create paths
# ==========================================================
if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$paths = @{
    'lanes'      = Join-Path $OutputRoot 'lanes'
    'PreCFU'     = Join-Path $OutputRoot 'PreCFU'
    'CFU_lanes'  = Join-Path $OutputRoot 'CFU_lanes'
    'POST'       = Join-Path $OutputRoot 'POST'
    'logs'       = Join-Path $OutputRoot '_logs'
}
foreach ($p in $paths.Values) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

$masterLog = Join-Path $paths['logs'] ("pipeline_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $masterLog -Append | Out-Null

# ==========================================================
# Header
# ==========================================================
Hdr "AQuA2 Pipeline Orchestrator"
Note ("Started:           {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Input TIFFs:       {0}" -f $InputTIFFs)
Note ("Output root:       {0}" -f $OutputRoot)
Note ("Master log:        {0}" -f $masterLog)

# ==========================================================
# Pre-flight checks
# ==========================================================
Hdr "Pre-flight checks"
$checksFailed = 0

# --- 1. Companion scripts exist ---
$companionScripts = @{
    'Auto-Size-Lanes.ps1'    = ($Lanes -le 0)
    'Split-IntoLanes.ps1'    = $Split
    'Launch-Lanes-Exe.ps1'   = $Detect
    'Build-CFU-Lanes.ps1'    = $CFU
    'Launch-CFU-Lanes.ps1'   = $CFU
}
foreach ($s in $companionScripts.GetEnumerator()) {
    if (-not $s.Value) { continue }
    $p = Join-Path $ScriptsDir $s.Key
    if (Test-Path $p) {
        OK2 ("script found: {0}" -f $s.Key)
    } else {
        Err2 ("script MISSING: {0} (expected at {1})" -f $s.Key, $p)
        $checksFailed++
    }
}

# --- 2. Worker exes ---
$workerExes = @{
    'aqua_lane.exe' = $Detect
    'cfu_lane.exe'  = $CFU
}
foreach ($e in $workerExes.GetEnumerator()) {
    if (-not $e.Value) { continue }
    $p = "C:\AQuA2\compiled\$($e.Key)"
    if (Test-Path $p) {
        OK2 ("worker exe found: {0}" -f $e.Key)
    } else {
        Err2 ("worker exe MISSING: {0} (expected at {1})" -f $e.Key, $p)
        $checksFailed++
    }
}

# --- 3. Input TIFFs ---
$inputCount = 0
$inputSizeGB = 0
if ($Split) {
    if (-not $InputTIFFs -or -not (Test-Path $InputTIFFs)) {
        Err2 "InputTIFFs folder missing or not specified (required for -Split)"
        $checksFailed++
    } else {
        $tifFiles = Get-ChildItem -Path $InputTIFFs -Recurse -Include *.tif,*.tiff -File
        $inputCount = $tifFiles.Count
        $inputSizeGB = [math]::Round(($tifFiles | Measure-Object Length -Sum).Sum / 1GB, 2)
        if ($inputCount -eq 0) {
            Err2 "InputTIFFs contains no .tif/.tiff files"
            $checksFailed++
        } else {
            OK2 ("input TIFFs: {0} files, {1} GB total" -f $inputCount, $inputSizeGB)
        }
    }
}

# --- 4. Detection prerequisites ---
if ($Detect -and -not $Split) {
    $laneDirs = Get-ChildItem $paths['lanes'] -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^lane' }
    if (-not $laneDirs -or $laneDirs.Count -eq 0) {
        Err2 ("Detect enabled but no lane folders found under {0}" -f $paths['lanes'])
        Err2 "Either set -Split `$true, or populate lanes manually first."
        $checksFailed++
    } else {
        OK2 ("existing lane folders found: {0}" -f $laneDirs.Count)
    }
}

# --- 5. CFU prerequisites ---
if ($CFU -and -not $Detect) {
    $matCount = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
    if ($matCount -eq 0) {
        Err2 ("CFU enabled but no _AQuA2.mat files under {0}" -f $paths['PreCFU'])
        Err2 "Either set -Detect `$true, or populate PreCFU manually first."
        $checksFailed++
    } else {
        OK2 ("existing detection results: {0} _AQuA2.mat files" -f $matCount)
    }
}

# --- 6. Upload prerequisites ---
if ($Upload) {
    if (-not $S3Prefix) {
        Err2 "-Upload requested but -S3Prefix not provided"
        $checksFailed++
    } elseif ($S3Prefix -notmatch '^s3://') {
        Err2 "-S3Prefix must start with s3:// (got: $S3Prefix)"
        $checksFailed++
    } else {
        try {
            $null = & aws sts get-caller-identity 2>&1
            if ($LASTEXITCODE -eq 0) {
                OK2 "AWS credentials work (sts get-caller-identity succeeded)"
            } else {
                Err2 "AWS CLI failed sts get-caller-identity. Check IAM role / credentials."
                $checksFailed++
            }
        } catch {
            Err2 "AWS CLI not available on PATH"
            $checksFailed++
        }
    }
}

# --- 7. Custom ConfigCSV ---
if ($ConfigCSV) {
    if (-not (Test-Path $ConfigCSV)) {
        Err2 ("Custom -ConfigCSV not found: {0}" -f $ConfigCSV)
        $checksFailed++
    } else {
        $csvLines = (Get-Content $ConfigCSV | Measure-Object -Line).Lines
        OK2 ("custom config CSV: {0} ({1} lines)" -f $ConfigCSV, $csvLines)
    }
}

# --- 8. Disk space ---
$freeNow = Get-FreeGB
$estNeed = if ($inputSizeGB -gt 0) { [math]::Round($inputSizeGB * 5, 0) } else { -1 }
if ($freeNow -lt $MinFreeDiskGB) {
    Err2 ("disk free ({0} GB) below abort threshold ({1} GB)" -f $freeNow, $MinFreeDiskGB)
    $checksFailed++
} elseif ($estNeed -gt 0 -and $freeNow -lt $estNeed) {
    Warn2 ("disk free ({0} GB) below estimated need ({1} GB). May fill mid-run." -f $freeNow, $estNeed)
} else {
    if ($estNeed -gt 0) {
        OK2 ("disk: {0} GB free, ~{1} GB estimated need" -f $freeNow, $estNeed)
    } else {
        OK2 ("disk: {0} GB free" -f $freeNow)
    }
}

# --- 9. Instance capacity (informational) ---
$cpu = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$script:instanceType = "(unknown)"
try {
    $token = Invoke-WebRequest -UseBasicParsing -Method PUT `
        -Uri "http://169.254.169.254/latest/api/token" `
        -Headers @{'X-aws-ec2-metadata-token-ttl-seconds'='60'} `
        -TimeoutSec 3 -ErrorAction Stop | Select-Object -ExpandProperty Content
    $script:instanceType = (Invoke-WebRequest -UseBasicParsing -Headers @{'X-aws-ec2-metadata-token'=$token} `
        -Uri "http://169.254.169.254/latest/meta-data/instance-type" -TimeoutSec 3).Content
} catch { }
OK2 ("instance: {0} ({1} vCPU, {2} GB RAM)" -f $script:instanceType, $cpu, $ramGB)

# --- Abort if any failed ---
if ($checksFailed -gt 0) {
    Write-Host ""
    Stop-Transcript | Out-Null
    Write-Error "$checksFailed pre-flight check(s) failed. Fix and re-run."
}

# ==========================================================
# Plan summary
# ==========================================================
Hdr "Plan summary"

$phaseList = @(
    @{ name='Split TIFFs into lanes';        on=$Split  },
    @{ name='Detection (aqua_lane.exe)';     on=$Detect },
    @{ name='CFU (build junctions + run)';   on=$CFU    },
    @{ name='S3 upload';                     on=$Upload }
)
foreach ($p in $phaseList) {
    $sym = if ($p.on) { '[X]' } else { '[ ]' }
    $col = if ($p.on) { 'Green' } else { 'DarkGray' }
    Write-Host ("  {0} {1}" -f $sym, $p.name) -ForegroundColor $col
}
Write-Host ""

if ($Lanes -le 0) {
    Note "Detection lanes:    will auto-size (probe largest input TIFF)"
} else {
    Note ("Detection lanes:    {0}" -f $Lanes)
}
if ($CFULanes -le 0) {
    Note "CFU lanes:          auto-derive (~0.75x detection lanes)"
} else {
    Note ("CFU lanes:          {0}" -f $CFULanes)
}
if ($ConfigCSV) {
    Note ("Config CSV:         {0}" -f $ConfigCSV)
    Note "                    (will be copied to C:\AQuA2\cfg\parameters_for_batch.csv; existing backed up first)"
} else {
    Note "Config CSV:         existing C:\AQuA2\cfg\parameters_for_batch.csv (unchanged)"
}
if ($Upload -and $S3Prefix) {
    Note ("S3 destination:     {0}" -f $S3Prefix)
}
Write-Host ""
Note ("Free disk:          {0} GB" -f $freeNow)
if ($estNeed -gt 0) {
    Note ("Estimated need:     {0} GB (input x 5)" -f $estNeed)
}
Write-Host ""
Note "To cancel mid-run:"
Note "  Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Stop-Process -Force"
Write-Host ""

if ($WhatIfMode) {
    Write-Host "DRY RUN MODE - nothing will execute. Exiting." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    return
}

if (-not $Force) {
    $resp = Read-Host "Proceed? [Y/n]"
    if ($resp -and $resp -notmatch '^[Yy]') {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        return
    }
}

# ==========================================================
# Phase 0: Auto-size
# ==========================================================
if (($Split -or $Detect) -and $Lanes -le 0) {
    Phase 0 "Auto-size lanes"
    $autoSizer = Join-Path $ScriptsDir 'Auto-Size-Lanes.ps1'
    $sizeStart = Get-Date
    Note "Profiling the largest TIFF (5-15 min)..."
    $rawOut = & $autoSizer -ProbeFolder $InputTIFFs 2>&1
    foreach ($l in $rawOut) { Write-Host $l }
    $line = $rawOut | Where-Object { $_ -match '===>\s*Recommended lanes:\s*(\d+)' } | Select-Object -First 1
    if ($line) {
        $null = $line -match '===>\s*Recommended lanes:\s*(\d+)'
        $Lanes = [int]$Matches[1]
        Note ("Auto-Size recommended: {0} detection lanes (probe took {1:N1} min)" -f $Lanes, ((Get-Date)-$sizeStart).TotalMinutes)
    } else {
        Warn2 "Could not parse Auto-Size output. Falling back to CPU-only default."
        $Lanes = [math]::Min([math]::Floor($cpu / 3), 32)
        Note ("Using {0} detection lanes (CPU-only default)." -f $Lanes)
    }
}
if ($CFULanes -le 0) {
    $CFULanes = [math]::Max([math]::Floor($Lanes * 0.75), 1)
}

# ==========================================================
# Phase 1: Split
# ==========================================================
if ($Split) {
    Phase 1 ("Split {0} TIFFs into {1} lanes" -f $inputCount, $Lanes)
    $start = Get-Date
    $splitter = Join-Path $ScriptsDir 'Split-IntoLanes.ps1'
    & $splitter -Source $InputTIFFs -LaneRoot $paths['lanes'] -Lanes $Lanes -Execute
    $laneFolders = Get-ChildItem $paths['lanes'] -Directory | Where-Object { $_.Name -match '^lane' }
    Note ("Created {0} lane folders" -f $laneFolders.Count)
    PhaseEnd 1 "Split" $start $null
}

# ==========================================================
# Phase 2: Detection
# ==========================================================
if ($Detect) {
    # Swap config CSV if requested
    if ($ConfigCSV) {
        $defaultCSV = "C:\AQuA2\cfg\parameters_for_batch.csv"
        if (Test-Path $defaultCSV) {
            $backup = "$defaultCSV.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $defaultCSV $backup
            Note ("Backed up existing default CSV to {0}" -f $backup)
        }
        Copy-Item $ConfigCSV $defaultCSV -Force
        Note ("Active config CSV: {0}" -f $defaultCSV)
    }

    # Archive the active CSV into _logs/ BEFORE detection starts
    Save-ParametersInUse

    Phase 2 ("Detection ({0} parallel workers)" -f $Lanes)
    $start = Get-Date
    $launcher = Join-Path $ScriptsDir 'Launch-Lanes-Exe.ps1'

    $tifCount = (Get-ChildItem -Path $paths['lanes'] -Recurse -Include *.tif,*.tiff -File).Count
    Note ("Total TIFFs across lanes: {0}" -f $tifCount)
    Note "Launching detection in background job..."

    $job = Start-Job -ScriptBlock {
        param($scriptPath, $laneRoot, $resultsRoot, $lanes)
        & $scriptPath -LaneRoot $laneRoot -ResultsRoot $resultsRoot -Lanes $lanes
    } -ArgumentList $launcher, $paths['lanes'], $paths['PreCFU'], $Lanes

    $lastDetail = Get-Date
    $throughputWindow = New-Object System.Collections.Queue
    $aborted = $false

    while ($job.State -eq 'Running') {
        Start-Sleep -Seconds $PollEverySec

        $completed = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
        $failures  = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
        $free      = Get-FreeGB
        $availRAM  = Get-AvailRAMGB
        $elapsed   = (Get-Date) - $start

        $throughputWindow.Enqueue([pscustomobject]@{ t = Get-Date; c = $completed })
        while ($throughputWindow.Count -gt 5) { [void]$throughputWindow.Dequeue() }
        $tw = @($throughputWindow)
        if ($tw.Count -ge 2) {
            $delta = $tw[-1].c - $tw[0].c
            $dtMin = ($tw[-1].t - $tw[0].t).TotalMinutes
            $rate = if ($dtMin -gt 0) { $delta / $dtMin } else { 0 }
        } else { $rate = 0 }

        $remaining = $tifCount - $completed
        $etaMin = if ($rate -gt 0.01) { [math]::Round($remaining / $rate, 0) } else { -1 }
        $etaStr = if ($etaMin -ge 0) { "{0,5:N0}m" -f $etaMin } else { "  ???" }
        $pct = if ($tifCount -gt 0) { ($completed / $tifCount) * 100 } else { 0 }

        Write-Host (
            "  [{0}] {1,4}/{2,-4} {3,5:N1}% | {4,5:N1} f/min | ETA {5} | RAM {6,5:N1}GB | Disk {7,5:N0}GB | fail {8}" `
            -f (Get-Date -Format 'HH:mm:ss'), $completed, $tifCount, $pct, $rate, $etaStr, $availRAM, $free, $failures
        )

        if ($free -lt $MinFreeDiskGB) {
            Err2 ("Free disk ({0} GB) below threshold ({1} GB). Aborting." -f $free, $MinFreeDiskGB)
            Err2 "To kill remaining workers manually:"
            Err2 "  Get-Process aqua_lane | Stop-Process -Force"
            Stop-Job $job
            $aborted = $true
            break
        }

        if (((Get-Date) - $lastDetail).TotalSeconds -ge $DetailEverySec) {
            $lastDetail = Get-Date
            Write-Host ""
            Write-Host ("  --- Detailed snapshot @ {0} ---" -f (Get-Date -Format 'HH:mm:ss'))
            Write-Host ("  Elapsed: {0:hh\:mm\:ss}" -f $elapsed)
            Write-Host ("  Throughput (recent window): {0:N1} files/min" -f $rate)
            if ($etaMin -ge 0) {
                $eta = (Get-Date).AddMinutes($etaMin)
                Write-Host ("  ETA: {0} min (~{1})" -f $etaMin, $eta.ToString('HH:mm'))
            }
            if ($failures -gt 0) {
                Write-Host "  Recent failures (last 3):"
                Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File |
                    Sort-Object LastWriteTime -Desc | Select-Object -First 3 |
                    ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
            }
            Write-Host ""
        }
    }

    try { Receive-Job $job -ErrorAction SilentlyContinue | Out-Null } catch {}
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    if ($aborted) {
        Stop-Transcript | Out-Null
        Write-Error "Detection aborted due to disk space. Free up disk, then re-run with -Split `$false -Detect `$true."
    }

    $finalDone = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File).Count
    $finalFail = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File).Count
    PhaseEnd 2 "Detection" $start ("Files: $finalDone OK, $finalFail failed (of $tifCount input)")

    # Per-file audit CSV for detection
    Write-PerFileStatus -Phase 'detection' -ResultsDir $paths['PreCFU'] -OkPattern '*_AQuA2.mat' -FailDir $null
}

# ==========================================================
# Phase 3: CFU (build + run, combined)
# ==========================================================
if ($CFU) {
    Phase 3 ("CFU build + run ({0} parallel workers)" -f $CFULanes)
    $start = Get-Date

    # Archive the CFU baked-parameters reference into _logs/
    Save-CFUBakedParameters

    # --- 3a: junctions ---
    $builder = Join-Path $ScriptsDir 'Build-CFU-Lanes.ps1'
    $matCount = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File).Count
    Note ("Detection .mat files: {0}" -f $matCount)
    Note "Building CFU lane junctions..."
    & $builder -Root $paths['PreCFU'] -LaneRoot $paths['CFU_lanes'] -Lanes $CFULanes -Execute
    $cfuLaneFolders = Get-ChildItem $paths['CFU_lanes'] -Directory | Where-Object { $_.Name -match '^lane' }
    Note ("Junctions ready: {0} lane folders" -f $cfuLaneFolders.Count)

    # --- 3b: clustering ---
    $cfuLauncher = Join-Path $ScriptsDir 'Launch-CFU-Lanes.ps1'
    $cfuLogDir = Join-Path $paths['CFU_lanes'] '_logs'
    Note "Launching CFU in background job..."

    $job = Start-Job -ScriptBlock {
        param($scriptPath, $laneRoot, $post, $logDir, $lanes)
        & $scriptPath -LaneRoot $laneRoot -Post $post -LogDir $logDir -Lanes $lanes
    } -ArgumentList $cfuLauncher, $paths['CFU_lanes'], $paths['POST'], $cfuLogDir, $CFULanes

    $throughputWindow = New-Object System.Collections.Queue
    while ($job.State -eq 'Running') {
        Start-Sleep -Seconds $PollEverySec
        $completed = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue).Count
        $failures  = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
        $free = Get-FreeGB
        $availRAM = Get-AvailRAMGB

        $throughputWindow.Enqueue([pscustomobject]@{ t = Get-Date; c = $completed })
        while ($throughputWindow.Count -gt 5) { [void]$throughputWindow.Dequeue() }
        $tw = @($throughputWindow)
        if ($tw.Count -ge 2) {
            $delta = $tw[-1].c - $tw[0].c
            $dtMin = ($tw[-1].t - $tw[0].t).TotalMinutes
            $rate = if ($dtMin -gt 0) { $delta / $dtMin } else { 0 }
        } else { $rate = 0 }

        $remaining = $matCount - $completed
        $etaMin = if ($rate -gt 0.01) { [math]::Round($remaining / $rate, 0) } else { -1 }
        $etaStr = if ($etaMin -ge 0) { "{0,5:N0}m" -f $etaMin } else { "  ???" }
        $pct = if ($matCount -gt 0) { ($completed / $matCount) * 100 } else { 0 }

        Write-Host (
            "  [{0}] {1,4}/{2,-4} {3,5:N1}% | {4,5:N1} f/min | ETA {5} | RAM {6,5:N1}GB | Disk {7,5:N0}GB | fail {8}" `
            -f (Get-Date -Format 'HH:mm:ss'), $completed, $matCount, $pct, $rate, $etaStr, $availRAM, $free, $failures
        )
    }
    try { Receive-Job $job -ErrorAction SilentlyContinue | Out-Null } catch {}
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    $finalDone = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File).Count
    $finalFail = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File).Count
    PhaseEnd 3 "CFU" $start ("Files: $finalDone OK, $finalFail failed (of $matCount input)")

    # Per-file audit CSV for CFU
    Write-PerFileStatus -Phase 'cfu' -ResultsDir $paths['POST'] -OkPattern '*_res_cfu.mat' -FailDir $null
}

# ==========================================================
# Phase 4: S3 upload
# ==========================================================
if ($Upload) {
    Phase 4 ("S3 upload to {0}" -f $S3Prefix)
    $start = Get-Date
    Note "Running dry-run first..."
    $dry = & aws s3 sync $OutputRoot $S3Prefix --dryrun 2>&1
    $dryCount = ($dry | Where-Object { $_ -match '^\(dryrun\) upload' }).Count
    Note ("Dry-run: {0} files would be uploaded." -f $dryCount)
    Note "Proceeding with real upload..."
    & aws s3 sync $OutputRoot $S3Prefix
    PhaseEnd 4 "S3 upload" $start $null
}

# ==========================================================
# Final summary
# ==========================================================
$completedAt = Get-Date
$total = $completedAt - $pipelineStart

# Collect counts for audit
$counts = @{
    input_count    = $inputCount
    detection_ok   = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter '*_AQuA2.mat' -File -ErrorAction SilentlyContinue).Count
    detection_fail = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue).Count
    cfu_ok         = (Get-ChildItem $paths['POST']   -Recurse -Filter '*_res_cfu.mat' -File -ErrorAction SilentlyContinue).Count
    cfu_fail       = (Get-ChildItem $paths['POST']   -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue).Count
}

# Write machine-readable + human-readable summaries
Hdr "Writing audit trail"
Write-RunManifest -Started $pipelineStart -Completed $completedAt -Counts $counts
Write-RunSummary  -Started $pipelineStart -Completed $completedAt -Counts $counts

Hdr "PIPELINE COMPLETE"
Note ("Total wall-clock:   {0:hh\:mm\:ss}" -f $total)
Note ("Output root:        {0}" -f $OutputRoot)
Note ("  Detection (.mat): {0} files" -f $counts['detection_ok'])
Note ("  CFU (_res_cfu):   {0} files" -f $counts['cfu_ok'])
Note ("Master log:         {0}" -f $masterLog)
Note ""
Note "Audit trail saved to $($paths['logs']):"
Note "  - RUN_SUMMARY.md                 (human-readable)"
Note "  - run_manifest.json              (machine-readable)"
Note "  - parameters_for_batch_USED.csv  (detection parameter CSV in effect)"
if ($CFU) {
    Note "  - cfu_parameters_BAKED.txt       (CFU thresholds compiled into cfu_lane.exe)"
    Note "  - per_file_status_cfu.csv        (CFU file-by-file)"
}
if ($Detect) {
    Note "  - per_file_status_detection.csv  (detection file-by-file)"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
if ($Detect -and -not $CFU) {
    Write-Host "  1. Verify detection looks right:"
    Write-Host ("       Get-ChildItem {0} -Recurse -Filter '*_AQuA2.mat' | Measure-Object" -f $paths['PreCFU'])
    Write-Host ("       Check {0}\<lane>\_failures\ if any" -f $paths['lanes'])
    Write-Host ""
    Write-Host "  2. When ready for CFU:"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -Split `$false -Detect `$false -CFU `$true" -f $OutputRoot)
    Write-Host ""
}
if ($CFU -and -not $Upload) {
    Write-Host "  1. R analysis:"
    Write-Host "       Open r\AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R in RStudio."
    Write-Host "       Edit frame_interval, filename regex, scope filters (docs/08_OPERATIONS_PLAYBOOK.md sec 1.4)."
    Write-Host "       Run; check pairing_and_parse_audit.csv before trusting results."
    Write-Host ""
    Write-Host "  2. S3 upload (when ready):"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -Split `$false -Detect `$false -CFU `$false -Upload `$true -S3Prefix s3://..." -f $OutputRoot)
    Write-Host ""
}
if ($Upload) {
    Write-Host "  All phases complete. Outputs uploaded to:" -ForegroundColor Green
    Write-Host ("    {0}" -f $S3Prefix)
    Write-Host ""
    Write-Host "  (Optional) Terminate instance once you've confirmed S3 has everything."
    Write-Host "    See docs/07_TEARDOWN_CHECKLIST.md"
    Write-Host ""
}

Stop-Transcript | Out-Null
