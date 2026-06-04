<#
.SYNOPSIS
  Launch K headless MATLAB processes in parallel, one per lane, each running aqua_cmd_batch_lane.

.DESCRIPTION
  For each lane folder (lane01..laneK under -LaneRoot), starts a hidden MATLAB that runs:
      cd('<AquaDir>'); startup; pIn='<lane>/'; pOut='<lane>_results/'; aqua_cmd_batch_lane
  Each process is independent; all K run concurrently. Per-lane console output goes to a logfile.

  REQUIREMENTS:
    * aqua_cmd_batch_lane.m must be copied INTO -AquaDir (next to startup.m), so startup puts it on path.
    * The instance must have at least  K * ~30 GB  of RAM (each lane peaks ~27 GB).
    * Your tuned parameters_for_batch.csv must be in AQuA2\cfg\ with values in the File1 column
      (the lane script reads File1 for every file) and the frame-rate row set to 0.05.

  RESUME: if a run is interrupted, just run this launcher again - each lane skips files already done.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Launch-Lanes.ps1 -Lanes 18
#>

[CmdletBinding()]
param(
    [string]$LaneRoot    = "C:\Users\Administrator\Documents\hCO_lanes",
    [string]$ResultsRoot = "C:\Users\Administrator\Documents\hCO_lanes",
    [string]$AquaDir     = "C:\Users\Administrator\Documents\AQuA2",
    [string]$MatlabExe   = "matlab",          # full path if not on PATH, e.g. C:\Program Files\MATLAB\R2024a\bin\matlab.exe
    [Parameter(Mandatory=$true)][int]$Lanes,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $AquaDir)) { Write-Error "AquaDir not found: $AquaDir"; return }
if (-not (Test-Path -LiteralPath (Join-Path $AquaDir 'aqua_cmd_batch_lane.m'))) {
    Write-Error "aqua_cmd_batch_lane.m is not in $AquaDir - copy it there first."; return
}

$logDir = Join-Path $ResultsRoot "_lane_logs"
if (-not $WhatIfOnly -and -not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# forward slashes keep MATLAB string literals clean on Windows
function S([string]$p){ ($p -replace '\\','/').TrimEnd('/') }
$aquaS = S $AquaDir

Write-Host "`nLaunching $Lanes lane(s).  RAM needed ~= $([math]::Round($Lanes*30)) GB.  Logs: $logDir`n"

$started = @()
for ($i=1; $i -le $Lanes; $i++) {
    $tag   = "lane{0:D2}" -f $i
    $pIn   = (S (Join-Path $LaneRoot $tag)) + "/"
    $pOut  = (S (Join-Path $ResultsRoot ($tag + "_results"))) + "/"
    if (-not (Test-Path -LiteralPath (Join-Path $LaneRoot $tag))) { Write-Warning "$tag folder missing - skipping"; continue }

    $stmt = "cd('$aquaS'); startup; pIn='$pIn'; pOut='$pOut'; aqua_cmd_batch_lane;"
    $log  = Join-Path $logDir "$tag.log"
    $args = @('-batch', $stmt, '-logfile', $log, '-nosplash')

    if ($WhatIfOnly) {
        Write-Host "[would launch] $tag"
        Write-Host "    $MatlabExe -batch `"$stmt`" -logfile $log`n"
        continue
    }
    $p = Start-Process -FilePath $MatlabExe -ArgumentList $args -WindowStyle Hidden -PassThru
    $started += [pscustomobject]@{ Lane=$tag; PID=$p.Id; Log=$log }
    Write-Host ("started {0}  (PID {1})" -f $tag, $p.Id)
    Start-Sleep -Seconds 3   # small stagger so disk reads don't all spike at once
}

if ($WhatIfOnly) { Write-Host "`n(WhatIfOnly: nothing launched.)"; return }

Write-Host "`n$($started.Count) lane(s) running. Monitor with:"
Write-Host "    Get-Process matlab | Measure-Object   # how many still alive"
Write-Host "    Get-Content '$logDir\lane01.log' -Tail 20 -Wait   # follow a lane"
Write-Host "    Get-Process matlab | Sort PeakWorkingSet64 -Desc | Select -First 1 @{n='PeakGB';e={[math]::Round(`$_.PeakWorkingSet64/1GB,1)}}"
Write-Host "`nRe-run this launcher after any interruption - completed files are skipped automatically."
