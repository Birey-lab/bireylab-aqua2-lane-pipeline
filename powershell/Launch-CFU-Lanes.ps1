<#
.SYNOPSIS
  Launch parallel CFU clustering workers, one per CFU lane.

.DESCRIPTION
  For each laneNN/ subfolder under -LaneRoot, spawns one cfu_lane.exe process.
  cfu_lane.exe:
    - Recursively finds <stem>_AQuA2.mat files in its lane
    - Runs CFU clustering on each
    - Bakes cfuInfo1/2/cfuRelation/cfuGroupInfo into the original .mat
      (in-place rewrite, atomic temp-and-rename, preserves fts1)
    - Writes a standalone <stem>_AQuA2_res_cfu.mat to -Post

  KNOWN ISSUE: this launcher writes logs to
    C:\Users\Administrator\Documents\CFU_lanes\_logs\
  regardless of -LaneRoot. Rename old logs before each new run to preserve
  them. See docs/06_PITFALLS_AND_RECOVERY.md Pitfall 7.

.PARAMETER LaneRoot
  Folder containing CFU laneNN/ subfolders (typically junctions, created by
  Build-CFU-Lanes.ps1).

.PARAMETER Post
  Destination folder for the standalone <stem>_AQuA2_res_cfu.mat files.

.PARAMETER ExePath
  Path to cfu_lane.exe. Default: C:\AQuA2\compiled\cfu_lane.exe

.EXAMPLE
  .\Launch-CFU-Lanes.ps1 -LaneRoot C:\data\my_CFU_lanes -Post C:\data\my_POST
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$LaneRoot,
  [Parameter(Mandatory)] [string]$Post,
  [string]$ExePath = "C:\AQuA2\compiled\cfu_lane.exe"
)

if (-not (Test-Path $ExePath)) {
  Write-Error "Worker executable not found: $ExePath"
  exit 1
}
if (-not (Test-Path $LaneRoot)) {
  Write-Error "LaneRoot not found: $LaneRoot"
  exit 1
}

$null = New-Item -ItemType Directory -Path $Post -Force

# Known issue: hardcoded log path
$logDir = "C:\Users\Administrator\Documents\CFU_lanes\_logs"
$null = New-Item -ItemType Directory -Path $logDir -Force

if ((Get-ChildItem $logDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
  Write-Warning "Log directory is not empty. Old logs may be overwritten."
  Write-Warning "Consider renaming first: Rename-Item $logDir ${logDir}_OLD"
  Write-Host ""
}

$laneDirs = Get-ChildItem $LaneRoot -Directory | Where-Object { $_.Name -like 'lane*' } | Sort-Object Name
if ($laneDirs.Count -eq 0) {
  Write-Error "No laneNN folders found under $LaneRoot"
  exit 1
}

Write-Host ""
Write-Host ("Launching {0} CFU lanes..." -f $laneDirs.Count)
Write-Host ("Worker:  {0}" -f $ExePath)
Write-Host ("Post:    {0}" -f $Post)
Write-Host ("Logs:    {0}" -f $logDir)
Write-Host ""

foreach ($lane in $laneDirs) {
  $laneName = $lane.Name
  $laneIn   = $lane.FullName
  $log      = Join-Path $logDir ($laneName + ".log")
  $err      = Join-Path $logDir ($laneName + ".err")

  $cmd = "`"$ExePath`" `"$laneIn`" `"$Post`" > `"$log`" 2> `"$err`""
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -PassThru -WindowStyle Hidden
  Write-Host ("  started {0} (PID {1})" -f $laneName, $p.Id)
}

Write-Host ""
Write-Host "All CFU lanes launched. Monitor with:"
Write-Host ("  Get-Process cfu_lane | Measure-Object | Select -Expand Count")
Write-Host ("  Get-ChildItem $Post -Filter *_res_cfu.mat | Measure-Object | Select -Expand Count")
