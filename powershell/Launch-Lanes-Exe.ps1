<#
.SYNOPSIS
  Launch K copies of the COMPILED aqua_lane.exe in parallel, one per lane.
  No MATLAB, no -batch, no license checkout, no Emory login.

.DESCRIPTION
  Each lane runs:  aqua_lane.exe "<laneNN>" "<laneNN_results>"
  The exe reads parameters_for_batch.csv from C:\AQuA2\cfg at runtime (baked into aqua_lane.m),
  so you can re-tune the CSV without recompiling. Per-lane stdout/stderr go to _lane_logs\laneNN.log.

  REQUIREMENTS:
    * aqua_lane.exe built with mcc (see build steps) at -ExePath.
    * MATLAB Runtime (R2026a) installed on this instance.
    * The 32-way re-split already done (lane01..lane32 under -LaneRoot).

  RESUME: re-run after any interruption - finished files are skipped by the resume guard.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Launch-Lanes-Exe.ps1 -Lanes 32
#>

[CmdletBinding()]
param(
    [string]$LaneRoot    = "C:\Users\Administrator\Documents\hCO_lanes",
    [string]$ResultsRoot = "C:\Users\Administrator\Documents\hCO_lanes",
    [string]$ExePath     = "C:\AQuA2\compiled\aqua_lane.exe",
    [Parameter(Mandatory=$true)][int]$Lanes,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Error "Compiled exe not found: $ExePath  (build it with mcc first)"; return
}

$logDir = Join-Path $ResultsRoot "_lane_logs"
if (-not $WhatIfOnly -and -not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Write-Host "`nLaunching $Lanes lane(s) from: $ExePath"
Write-Host "Measured ~12 GB/lane -> ~$([math]::Round($Lanes*15)) GB budgeted (you have ~1 TB).  Logs: $logDir`n"

$started = @()
for ($i=1; $i -le $Lanes; $i++) {
    $tag  = "lane{0:D2}" -f $i
    $pIn  = Join-Path $LaneRoot $tag                       # no trailing slash; exe normalizes
    $pOut = Join-Path $ResultsRoot ($tag + "_results")
    if (-not (Test-Path -LiteralPath $pIn)) { Write-Warning "$tag folder missing - skipping"; continue }

    $log = Join-Path $logDir "$tag.log"
    $err = Join-Path $logDir "$tag.err"

    if ($WhatIfOnly) {
        Write-Host "[would launch] $tag :  `"$ExePath`" `"$pIn`" `"$pOut`""
        continue
    }
    $p = Start-Process -FilePath $ExePath -ArgumentList "`"$pIn`"", "`"$pOut`"" `
            -RedirectStandardOutput $log -RedirectStandardError $err `
            -WindowStyle Hidden -PassThru
    $started += [pscustomobject]@{ Lane=$tag; PID=$p.Id }
    Write-Host ("started {0}  (PID {1})" -f $tag, $p.Id)
    Start-Sleep -Seconds 2
}

if ($WhatIfOnly) { Write-Host "`n(WhatIfOnly: nothing launched.)"; return }

Write-Host "`n$($started.Count) lane(s) running (no MATLAB license used). Monitor with:"
Write-Host "    Get-Process aqua_lane | Measure-Object        # how many still alive"
Write-Host "    Get-Content '$logDir\lane01.log' -Tail 20 -Wait"
Write-Host "    Get-Content '$logDir\lane01.err' -Tail 20      # errors for a lane, if any"
Write-Host "`nRe-run this launcher after any interruption - completed files are skipped."
