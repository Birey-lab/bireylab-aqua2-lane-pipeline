<#
.SYNOPSIS
  Split the TIFFs of a folder into K size-balanced lane folders for parallel AQuA2.

.DESCRIPTION
  Scans -Source (TOP LEVEL only by default, so existing subfolders like Donors2and3 are ignored),
  then distributes the files across K lanes (lane01..laneK) using greedy bin-packing by file size,
  so every lane gets roughly equal total GB -> roughly equal wall-clock.

  -Recurse (v0.9.1): also pull TIFFs from nested subfolders. Because lane files are addressed by
  filename alone, duplicate leaf names across different subfolders would collide in a lane; when
  -Recurse is set this script HARD-ERRORS on any duplicate filename instead of silently skipping,
  so nested inputs must have unique names (flatten/prefix first if not).

  DRY RUN by default. Add -Execute to actually move. MOVE on the same NTFS drive is instant and
  needs no extra space (use -Copy to copy instead). Re-run safe.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Split-IntoLanes.ps1 -Lanes 18
  powershell -ExecutionPolicy Bypass -File .\Split-IntoLanes.ps1 -Lanes 18 -Execute
  powershell -ExecutionPolicy Bypass -File .\Split-IntoLanes.ps1 -Lanes 18 -Recurse -Execute
#>

[CmdletBinding()]
param(
    [string]$Source   = "C:\Users\Administrator\Documents\hCO_AllTIFFs",
    [string]$LaneRoot = "C:\Users\Administrator\Documents\hCO_lanes",
    [Parameter(Mandatory=$true)][int]$Lanes,
    [switch]$Copy,
    [switch]$Recurse,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Source)) { Write-Error "Source not found: $Source"; return }
if ($Lanes -lt 1) { Write-Error "Lanes must be >= 1"; return }

$verb = if ($Copy) { 'COPY' } else { 'MOVE' }
$mode = if ($Execute) { "EXECUTE ($verb)" } else { "DRY RUN" }
$depth = if ($Recurse) { 'RECURSE (nested subfolders)' } else { 'top-level only' }
Write-Host "`n==================================================================="
Write-Host " Split into $Lanes lanes   Source: $Source"
Write-Host " Lane root: $LaneRoot    Mode: $mode    Scan: $depth"
Write-Host "===================================================================`n"

# TIFFs to distribute. Top-level only by default; -Recurse also pulls from nested subfolders.
# v0.8: exclude macOS AppleDouble sidecars ("._name.tif"): they carry a .tif extension
# but are tiny resource-fork stubs, not images. If one reaches a lane the TIFF reader
# throws a fatal "Unable to open TIFF file" that can take the lane worker down.
$scan = if ($Recurse) { Get-ChildItem -LiteralPath $Source -File -Recurse } else { Get-ChildItem -LiteralPath $Source -File }
$files = $scan |
         Where-Object { ($_.Extension -ieq '.tif' -or $_.Extension -ieq '.tiff') -and ($_.Name -notlike '._*') } |
         Sort-Object Length -Descending     # largest first for good greedy balance
$scope = if ($Recurse) { "recursively under" } else { "top-level in" }
if (-not $files) { Write-Warning "No .tif/.tiff found $scope $Source"; return }

$appleDouble = @($scan | Where-Object { $_.Name -like '._*' })
if ($appleDouble.Count -gt 0) {
    Write-Warning ("Ignored {0} macOS AppleDouble (._*) file(s). Strip at upload with: aws s3 sync <src> <dst> --exclude '._*'" -f $appleDouble.Count)
}

# Lane files are addressed by filename alone, so duplicate leaf names (possible only with
# -Recurse across subfolders) would collide in a lane. Fail loudly rather than silently drop.
if ($Recurse) {
    $dupes = $files | Group-Object Name | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        Write-Host "`nDUPLICATE FILENAMES across subfolders (would collide in a lane):" -ForegroundColor Red
        foreach ($d in $dupes) {
            Write-Host ("  {0}  ({1} copies):" -f $d.Name, $d.Count) -ForegroundColor Red
            foreach ($f in $d.Group) { Write-Host ("     {0}" -f $f.FullName) -ForegroundColor Red }
        }
        Write-Error ("{0} duplicate filename(s) under -Recurse. Give them unique names (e.g. prefix by subfolder) and re-run." -f $dupes.Count)
        return
    }
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
