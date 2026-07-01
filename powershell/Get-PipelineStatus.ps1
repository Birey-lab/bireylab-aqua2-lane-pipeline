<#
.SYNOPSIS
  Read-only health / triage report for an AQuA2 pipeline project.

.DESCRIPTION
  Prints a one-screen diagnosis for a <OutputRoot>\<ProjectName> project directory:
  counts + mismatches (inputs vs detection vs CFU), failures grouped by error
  signature, stalled/quarantined files, lanes that died at startup (.err with
  content), orphaned worker processes, free disk, phase-marker consistency, and
  the nCFU distribution. It reads only -- it never writes, moves, or deletes.

  Works on any project, including finished or archived runs: point it at the
  project root and read the report. Useful both mid-run (in a second window) and
  after the fact when a downstream surprise sends you looking for the cause.

.PARAMETER ProjectRoot
  The project directory (e.g. D:\runs\my_dataset) -- i.e. <OutputRoot>\<ProjectName>,
  the folder containing lanes\, PreCFU\, POST\, CFU_lanes\, for_upload\, _logs\.

.EXAMPLE
  .\Get-PipelineStatus.ps1 -ProjectRoot D:\runs\my_dataset

.NOTES
  Exit code: 0 if no issues detected, 1 if any issue category triggered
  (handy for scripting; harmless when run interactively).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    Write-Error "ProjectRoot not found: $ProjectRoot"
    return
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$paths = @{
    lanes      = Join-Path $ProjectRoot 'lanes'
    PreCFU     = Join-Path $ProjectRoot 'PreCFU'
    POST       = Join-Path $ProjectRoot 'POST'
    CFU_lanes  = Join-Path $ProjectRoot 'CFU_lanes'
    for_upload = Join-Path $ProjectRoot 'for_upload'
    logs       = Join-Path $ProjectRoot '_logs'
}

function Hdr($t)  { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Line($k,$v) { Write-Host ("  {0,-26} {1}" -f $k, $v) }
function WarnL($t) { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function BadL($t)  { Write-Host "  [X]  $t" -ForegroundColor Red }
function GoodL($t) { Write-Host "  [OK] $t" -ForegroundColor Green }

function Get-ErrorSignature {
    # Reduce an _ERROR.txt to a normalized one-line signature (matches the
    # orchestrator's grouping). Handles cfu_lane's "Error: <msg>" and aqua_lane's
    # getReport() output.
    param([string]$ErrorFilePath)
    try { $lines = Get-Content $ErrorFilePath -TotalCount 40 -ErrorAction Stop } catch { return 'unreadable error file' }
    $msg = $null
    foreach ($l in $lines) { if ($l -match '^\s*Error:\s*(.+)$') { $msg = $Matches[1]; break } }
    if (-not $msg) {
        foreach ($l in $lines) {
            $t = $l.Trim()
            if ($t -and $t -notmatch '^(FILE|File):' -and $t -notmatch '^Time:' -and $t -notmatch '^Error using' -and $t -notmatch '^at ') { $msg = $t; break }
        }
    }
    if (-not $msg) { $msg = 'unknown error' }
    $sig = $msg -replace "'[^']*'", 'X' -replace '"[^"]*"', 'X'
    $sig = $sig -replace '[A-Za-z]:\\[^\s]*', 'PATH' -replace '\d+', '#'
    $sig = ($sig -replace '\s+', ' ').Trim()
    if ($sig.Length -gt 100) { $sig = $sig.Substring(0, 100) }
    return $sig
}

$issues = New-Object System.Collections.Generic.List[string]

Write-Host ""
Write-Host "AQuA2 pipeline status" -ForegroundColor Cyan
Write-Host "  $ProjectRoot"

if (-not (Test-Path $paths.PreCFU) -and -not (Test-Path $paths.lanes) -and -not (Test-Path $paths.for_upload)) {
    WarnL "No lanes\, PreCFU\, or for_upload\ here -- is this the right project root (<OutputRoot>\<ProjectName>)?"
}

# ---------- Counts + mismatches ----------
$realInputs = @(Get-ChildItem $paths.lanes -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike '._*' -and $_.Directory.FullName -notmatch '\\_stalled(\\|$)' }).Count
$inputSource = 'lanes\'
if ($realInputs -eq 0 -and (Test-Path (Join-Path $paths.for_upload 'input_TIFFs'))) {
    $realInputs = @(Get-ChildItem (Join-Path $paths.for_upload 'input_TIFFs') -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '._*' }).Count
    $inputSource = 'for_upload\input_TIFFs\'
}
$detected = @(Get-ChildItem $paths.PreCFU -Recurse -Filter '*_AQuA2.mat' -File -ErrorAction SilentlyContinue |
              Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' }).Count
$cfu = @(Get-ChildItem $paths.POST -Recurse -Filter '*_res_cfu.mat' -File -ErrorAction SilentlyContinue |
         Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' }).Count

Hdr "Counts"
Line "Input TIFFs ($inputSource)" $realInputs
Line "Detection (_AQuA2.mat)"     $detected
Line "CFU (_res_cfu.mat)"         $cfu
if ($realInputs -gt 0 -and $detected -lt $realInputs) {
    BadL ("Detection short by {0} of {1}." -f ($realInputs - $detected), $realInputs); [void]$issues.Add('detection<inputs')
} elseif ($realInputs -gt 0) { GoodL "Detection count matches inputs." }
if ($detected -gt 0 -and $cfu -lt $detected) {
    BadL ("CFU short by {0} of {1}." -f ($detected - $cfu), $detected); [void]$issues.Add('cfu<detected')
} elseif ($detected -gt 0) { GoodL "CFU count matches detection." }

# ---------- Live workers ----------
Hdr "Live workers"
$workers = @(Get-Process aqua_lane, cfu_lane -ErrorAction SilentlyContinue)
if ($workers.Count -gt 0) {
    WarnL ("{0} worker process(es) still running:" -f $workers.Count)
    $workers | ForEach-Object { Line ("PID {0}" -f $_.Id) $_.Name }
} else { GoodL "No aqua_lane/cfu_lane processes running." }

# ---------- Failures grouped by signature ----------
Hdr "Failures (grouped by error signature)"
$errFiles = @()
$errFiles += @(Get-ChildItem $paths.PreCFU -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue)
$errFiles += @(Get-ChildItem $paths.POST   -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue)
if ($errFiles.Count -eq 0) { GoodL "No _ERROR.txt files." }
else {
    [void]$issues.Add('failures')
    BadL ("{0} failed file(s):" -f $errFiles.Count)
    $errFiles | Group-Object { Get-ErrorSignature $_.FullName } | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("    {0,4}x  {1}" -f $_.Count, $_.Name) -ForegroundColor Red
    }
}

# ---------- Stalled / quarantined ----------
Hdr "Stalled / quarantined"
$stalledTIFFs = @(Get-ChildItem $paths.lanes -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.FullName -match '\\_stalled(\\|$)' })
$stalledCFU   = @(Get-ChildItem $paths.CFU_lanes -Recurse -File -Filter '_STALLED_*.txt' -ErrorAction SilentlyContinue)
if ($stalledTIFFs.Count -eq 0 -and $stalledCFU.Count -eq 0) { GoodL "No stalled files or CFU stall markers." }
else {
    if ($stalledTIFFs.Count -gt 0) {
        WarnL ("{0} detection file(s) quarantined in _stalled\:" -f $stalledTIFFs.Count)
        $stalledTIFFs | ForEach-Object { Line "" $_.FullName }
        [void]$issues.Add('stalled_tiffs')
    }
    if ($stalledCFU.Count -gt 0) {
        WarnL ("{0} CFU stall marker(s) (_STALLED_*.txt)." -f $stalledCFU.Count)
        [void]$issues.Add('stalled_cfu')
    }
}

# ---------- Lane startup errors (.err with content) ----------
Hdr "Lane startup errors (.err with content)"
$errLogs = @()
$errLogs += @(Get-ChildItem (Join-Path $paths.PreCFU '_lane_logs') -Filter *.err -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
$errLogs += @(Get-ChildItem (Join-Path $paths.CFU_lanes '_logs')   -Filter *.err -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
if ($errLogs.Count -eq 0) { GoodL "No lane .err files with content." }
else {
    [void]$issues.Add('lane_err')
    BadL ("{0} lane .err file(s) have content (worker may have failed at startup):" -f $errLogs.Count)
    $errLogs | ForEach-Object { Line "" ("{0} ({1} bytes)" -f $_.FullName, $_.Length) }
}

# ---------- Phase markers / state ----------
Hdr "Phase markers"
foreach ($m in 'split','detect','cfu','consolidate','upload') {
    $mk = Join-Path $paths.logs ("PHASE_{0}_COMPLETE.txt" -f $m)
    if (Test-Path $mk) { Line ("PHASE_{0}_COMPLETE" -f $m) ((Get-Item $mk).LastWriteTime.ToString('yyyy-MM-dd HH:mm')) }
}
$incMk = Join-Path $paths.logs 'PHASE_detect_INCOMPLETE.txt'
if (Test-Path $incMk) {
    BadL ("PHASE_detect_INCOMPLETE present ({0}) -- last detection did not finish for all inputs." -f (Get-Item $incMk).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    [void]$issues.Add('detect_incomplete')
}

# ---------- Disk ----------
Hdr "Disk"
try {
    $drive = (Get-Item $ProjectRoot).PSDrive.Name
    $free = [math]::Round((Get-PSDrive $drive).Free / 1GB, 1)
    Line ("{0}: free" -f $drive) ("{0} GB" -f $free)
} catch { WarnL "Could not read free disk space." }

# ---------- nCFU distribution ----------
Hdr "nCFU distribution (from CFU lane logs)"
$cfuLogDir = Join-Path $paths.CFU_lanes '_logs'
if (Test-Path $cfuLogDir) {
    $ncfu = @(Select-String -Path (Join-Path $cfuLogDir '*.log') -Pattern 'nCFU=(\d+)' -ErrorAction SilentlyContinue |
              ForEach-Object { [int]$_.Matches.Groups[1].Value })
    if ($ncfu.Count -gt 0) {
        $stats = $ncfu | Measure-Object -Average -Minimum -Maximum
        $zeros = @($ncfu | Where-Object { $_ -eq 0 }).Count
        Line "files reporting nCFU" $stats.Count
        Line "min / mean / max" ("{0} / {1:N1} / {2}" -f $stats.Minimum, $stats.Average, $stats.Maximum)
        Line "files with nCFU=0" $zeros
        if (($zeros / [double]$stats.Count) -gt 0.3) {
            WarnL "Over 30% of files have zero CFUs -- check CFU parameters or whether the prep is genuinely quiet."
        }
    } else { Line "nCFU lines found" 0 }
} else { Line "CFU log dir" "(none)" }

# ---------- Verdict ----------
Hdr "Verdict"
if ($issues.Count -eq 0) {
    GoodL "No issues detected."
    exit 0
} else {
    BadL ("{0} issue categor(ies) flagged above -- see the sections marked [X]/[!]." -f $issues.Count)
    exit 1
}
