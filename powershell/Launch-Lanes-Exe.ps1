<#
.SYNOPSIS
  Launch N parallel AQuA2 detection workers, one per lane folder.

.DESCRIPTION
  For each laneNN/ subfolder under -LaneRoot, spawns one aqua_lane.exe process
  in the background. Each worker reads C:\AQuA2\cfg\parameters_for_batch.csv
  for parameters, processes its TIFFs sequentially, and writes outputs to
  -ResultsRoot\laneNN_results\.

  Per-file try/catch is built into aqua_lane.exe (banner reads
  "resume+per-file-guard=ON") — a single bad TIFF won't kill the lane.

  Resume guard: re-running this script after an interruption skips files
  whose <stem>_AQuA2.mat already exists.

.PARAMETER LaneRoot
  Folder containing laneNN/ subfolders (typically created by Split-IntoLanes.ps1).

.PARAMETER ResultsRoot
  Destination root; per-lane subfolders laneNN_results/ will be created here.

.PARAMETER ExePath
  Path to aqua_lane.exe. Default: C:\AQuA2\compiled\aqua_lane.exe

.PARAMETER Lanes
  Number of lanes to launch. Should match the number of laneNN/ folders under LaneRoot.

.EXAMPLE
  .\Launch-Lanes-Exe.ps1 -LaneRoot C:\data\my_lanes -ResultsRoot C:\data\my_results -Lanes 32
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$LaneRoot,
  [Parameter(Mandatory)] [string]$ResultsRoot,
  [string]$ExePath = "C:\AQuA2\compiled\aqua_lane.exe",
  [Parameter(Mandatory)] [int]$Lanes
)

if (-not (Test-Path $ExePath)) {
  Write-Error "Worker executable not found: $ExePath"
  exit 1
}
if (-not (Test-Path $LaneRoot)) {
  Write-Error "LaneRoot not found: $LaneRoot"
  exit 1
}

$null = New-Item -ItemType Directory -Path $ResultsRoot -Force
$logDir = Join-Path $ResultsRoot "_lane_logs"
$null = New-Item -ItemType Directory -Path $logDir -Force

Write-Host ""
Write-Host ("Launching {0} lanes..." -f $Lanes)
Write-Host ("Worker:  {0}" -f $ExePath)
Write-Host ("Logs:    {0}" -f $logDir)
Write-Host ""

for ($i = 1; $i -le $Lanes; $i++) {
  $laneName  = "lane{0:D2}" -f $i
  $laneIn    = Join-Path $LaneRoot $laneName
  $laneOut   = Join-Path $ResultsRoot ($laneName + "_results")
  $log       = Join-Path $logDir ($laneName + ".log")
  $err       = Join-Path $logDir ($laneName + ".err")

  if (-not (Test-Path $laneIn)) {
    Write-Warning ("  {0}: input folder not found ({1}) - skipping" -f $laneName, $laneIn)
    continue
  }

  $null = New-Item -ItemType Directory -Path $laneOut -Force

  # Use cmd /c wrapper to avoid PowerShell argument-mangling issues
  # (see docs/06_PITFALLS_AND_RECOVERY.md Pitfall 2)
  $cmd = "`"$ExePath`" `"$laneIn`" `"$laneOut`" > `"$log`" 2> `"$err`""
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -PassThru -WindowStyle Hidden
  Write-Host ("  started {0} (PID {1})" -f $laneName, $p.Id)
}

Write-Host ""
Write-Host "All lanes launched. Monitor with:"
Write-Host ("  Get-Process aqua_lane | Measure-Object | Select -Expand Count")
Write-Host ("  Get-ChildItem $ResultsRoot -Recurse -Filter *_AQuA2.mat | Measure-Object | Select -Expand Count")
