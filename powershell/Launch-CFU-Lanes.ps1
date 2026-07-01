# Launch-CFU-Lanes.ps1
# Start one cfu_lane.exe per cfu_laneNN folder. All lanes write standalone
# _res_cfu.mat into the common POST folder; the in-place _AQuA2.mat rewrite
# happens through each lane's junctions (atomic temp+rename inside the exe).
#
# Usage: .\Launch-CFU-Lanes.ps1                 (uses defaults: 20 lanes)
#        .\Launch-CFU-Lanes.ps1 -WhatIfOnly     (print plan, launch nothing)

param(
    [string]$LaneRoot = 'C:\Users\Administrator\Documents\CFU_lanes',
    [string]$Post     = 'C:\Users\Administrator\Documents\POST',
    [string]$ExePath  = 'C:\AQuA2\compiled\cfu_lane.exe',
    # Default derives from -LaneRoot so distinct lane roots get distinct logs
    # (avoids the old fixed-default collision; see docs/06 Pitfall #7).
    [string]$LogDir   = (Join-Path $LaneRoot '_logs'),
    [switch]$WhatIfOnly
)

if (-not (Test-Path $ExePath)) { Write-Error "Exe not found: $ExePath"; return }
if (-not (Test-Path $Post))    { New-Item -ItemType Directory -Path $Post   | Out-Null }
if (-not (Test-Path $LogDir))  { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$lanes = Get-ChildItem $LaneRoot -Directory | Where-Object { $_.Name -match '^cfu_lane\d+$' } | Sort-Object Name
"Found $($lanes.Count) lane folders. POST output -> $Post"

$n = 0
foreach ($lane in $lanes) {
    $pin = $lane.FullName
    $tag = $lane.Name
    "  launch $tag  ->  $ExePath `"$pin`" `"$Post`""
    if ($WhatIfOnly) { continue }
    Start-Process -FilePath $ExePath `
        -ArgumentList @("`"$pin`"", "`"$Post`"") `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $LogDir ($tag + '.log')) `
        -RedirectStandardError  (Join-Path $LogDir ($tag + '.err'))
    $n++
    Start-Sleep -Seconds 2     # stagger MCR spin-up
}
if ($WhatIfOnly) { "`n(what-if) nothing launched." } else { "`nLaunched $n CFU lanes. Monitor: Get-Process cfu_lane | Measure-Object" }
