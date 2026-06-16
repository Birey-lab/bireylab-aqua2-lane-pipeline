<#
.SYNOPSIS
  Split the top-level TIFFs of a flat folder into K size-balanced lane folders for parallel AQuA2.

.DESCRIPTION
  Scans -Source (TOP LEVEL only, so existing subfolders like Donors2and3 are ignored), then
  distributes the files across K lanes (lane01..laneK) using greedy bin-packing by file size,
  so every lane gets roughly equal total GB -> roughly equal wall-clock.

  DRY RUN by default. Add -Execute to actually move. MOVE on the same NTFS drive is instant and
  needs no extra space (use -Copy to copy instead). Re-run safe.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Split-IntoLanes.ps1 -Lanes 18
  powershell -ExecutionPolicy Bypass -File .\Split-IntoLanes.ps1 -Lanes 18 -Execute
#>

[CmdletBinding()]
param(
    [string]$Source   = "C:\Users\Administrator\Documents\hCO_AllTIFFs",
    [string]$LaneRoot = "C:\Users\Administrator\Documents\hCO_lanes",
    [Parameter(Mandatory=$true)][int]$Lanes,
    [switch]$Copy,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Source)) { Write-Error "Source not found: $Source"; return }
if ($Lanes -lt 1) { Write-Error "Lanes must be >= 1"; return }

$verb = if ($Copy) { 'COPY' } else { 'MOVE' }
$mode = if ($Execute) { "EXECUTE ($verb)" } else { "DRY RUN" }
Write-Host "`n==================================================================="
Write-Host " Split into $Lanes lanes   Source: $Source"
Write-Host " Lane root: $LaneRoot    Mode: $mode"
Write-Host "===================================================================`n"

# Top-level TIFFs only.
# v0.8: exclude macOS AppleDouble sidecars ("._name.tif"): they carry a .tif extension
# but are tiny resource-fork stubs, not images. If one reaches a lane the TIFF reader
# throws a fatal "Unable to open TIFF file" that can take the lane worker down.
$files = Get-ChildItem -LiteralPath $Source -File |
         Where-Object { ($_.Extension -ieq '.tif' -or $_.Extension -ieq '.tiff') -and ($_.Name -notlike '._*') } |
         Sort-Object Length -Descending     # largest first for good greedy balance
if (-not $files) { Write-Warning "No top-level .tif/.tiff in $Source"; return }

$appleDouble = @(Get-ChildItem -LiteralPath $Source -File | Where-Object { $_.Name -like '._*' })
if ($appleDouble.Count -gt 0) {
    Write-Warning ("Ignored {0} macOS AppleDouble (._*) file(s). Strip at upload with: aws s3 sync <src> <dst> --exclude '._*'" -f $appleDouble.Count)
}

# Greedy bin-packing: assign each file to the lane with the smallest running total
$laneBytes = New-Object 'long[]' $Lanes
$assign = @{}   # file -> lane index (0-based)
foreach ($f in $files) {
    $min = 0
    for ($i=1; $i -lt $Lanes; $i++) { if ($laneBytes[$i] -lt $laneBytes[$min]) { $min = $i } }
    $assign[$f.FullName] = $min
    $laneBytes[$min] += $f.Length
}

# Report
Write-Host ("Files: {0}    Total: {1} GB`n" -f $files.Count, [math]::Round((($files|Measure-Object Length -Sum).Sum)/1GB,2))
Write-Host ("{0,-8} {1,7} {2,12}" -f 'Lane','Files','Size(GB)')
Write-Host ("{0,-8} {1,7} {2,12}" -f '----','-----','--------')
for ($i=0; $i -lt $Lanes; $i++) {
    $cnt = ($assign.Values | Where-Object { $_ -eq $i }).Count
    Write-Host ("lane{0:D2}  {1,7} {2,12}" -f ($i+1), $cnt, [math]::Round($laneBytes[$i]/1GB,2))
}
Write-Host ""

if (-not $Execute) {
    Write-Host "DRY RUN - nothing moved. Re-run with -Execute." -ForegroundColor Cyan
    return
}

# Execute
$done=0; $skipped=0; $failed=0
foreach ($f in $files) {
    $laneDir = Join-Path $LaneRoot ("lane{0:D2}" -f ($assign[$f.FullName]+1))
    if (-not (Test-Path -LiteralPath $laneDir)) { New-Item -ItemType Directory -Path $laneDir -Force | Out-Null }
    $target = Join-Path $laneDir $f.Name
    try {
        if (Test-Path -LiteralPath $target) { $skipped++; continue }
        if ($Copy) { Copy-Item -LiteralPath $f.FullName -Destination $target }
        else       { Move-Item -LiteralPath $f.FullName -Destination $target }
        $done++
    } catch { Write-Warning "FAILED: $($f.Name) -> $($_.Exception.Message)"; $failed++ }
}
Write-Host "`nDone. $verb`d $done | Skipped $skipped | Failed $failed" -ForegroundColor Green
Write-Host "Lanes are under: $LaneRoot"
