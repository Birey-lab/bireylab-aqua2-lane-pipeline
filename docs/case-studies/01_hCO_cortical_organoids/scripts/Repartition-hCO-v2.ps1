# Repartition-hCO-v2.ps1
# Gather ALL hCO input TIFFs from the existing hCO_lanes tree (laneNN\ + sprintNN\
# input folders) and symlink them into 32 fresh balanced lane folders for the
# maxSize=50000 re-run. No copying — symlinks point at the original TIFFs.
#
# Usage (dry run): .\Repartition-hCO-v2.ps1
#        (execute): .\Repartition-hCO-v2.ps1 -Execute

param(
    [string]$SrcRoot  = 'C:\Users\Administrator\Documents\hCO_lanes',
    [string]$LaneRoot = 'C:\Users\Administrator\Documents\hCO_v2_in',
    [int]   $Lanes    = 32,
    [switch]$Execute
)

# 1) gather every hCO INPUT tiff (exclude _Movie.tif outputs; only real recordings)
#    Source folders are the input lanes/sprints (NOT the *_results output folders).
$tifs = Get-ChildItem $SrcRoot -Recurse -Filter *.tif -File |
        Where-Object {
            $_.Name -like '*_hCO_*' -and
            $_.Name -notlike '*_Movie.tif' -and
            $_.DirectoryName -notlike '*_results'      # skip output folders
        }

# de-dup by filename (a recording should appear once across all input folders)
$byName = $tifs | Group-Object Name
$dups = $byName | Where-Object { $_.Count -gt 1 }
if ($dups) {
    "WARNING: $($dups.Count) filenames appear in more than one input folder:"
    $dups | ForEach-Object { "  $($_.Name)  x$($_.Count)" } | Select-Object -First 10
    "  (will link only the FIRST occurrence of each)"
}
$items = $byName | ForEach-Object {
    $f = $_.Group[0]
    [pscustomobject]@{ Name = $f.Name; Path = $f.FullName; Size = $f.Length }
}
"Unique hCO input TIFFs: $($items.Count)"
if ($items.Count -eq 0) { Write-Error "No hCO input TIFFs found under $SrcRoot"; return }

# 2) greedy size-balanced bin-packing into $Lanes
$bins = @{}; $load = @{}
1..$Lanes | ForEach-Object { $bins[$_] = New-Object System.Collections.ArrayList; $load[$_] = [double]0 }
foreach ($it in ($items | Sort-Object Size -Descending)) {
    $min = 1; for ($k=2; $k -le $Lanes; $k++) { if ($load[$k] -lt $load[$min]) { $min = $k } }
    [void]$bins[$min].Add($it); $load[$min] += $it.Size
}

"`nPlanned lanes:"
$total = 0
1..$Lanes | ForEach-Object {
    $total += $bins[$_].Count
    "{0,-8} files={1,4}  ~{2,7:N1} GB" -f ("lane{0:D2}" -f $_), $bins[$_].Count, ($load[$_]/1GB)
}
"TOTAL files placed: $total"

if (-not $Execute) {
    "`n(dry run) re-run with -Execute to create $LaneRoot with $Lanes symlink folders."
    return
}

# 3) create lane folders of symlinks
if (-not (Test-Path $LaneRoot)) { New-Item -ItemType Directory -Path $LaneRoot | Out-Null }
1..$Lanes | ForEach-Object {
    $lane = Join-Path $LaneRoot ("lane{0:D2}" -f $_)
    if (Test-Path $lane) { Remove-Item $lane -Recurse -Force }   # clears old symlinks only (never targets)
    New-Item -ItemType Directory -Path $lane | Out-Null
    foreach ($it in $bins[$_]) {
        $link = Join-Path $lane $it.Name
        cmd /c mklink "`"$link`"" "`"$($it.Path)`"" | Out-Null
    }
    "  built lane{0:D2}: {1} symlinks" -f $_, $bins[$_].Count
}
"`nDone. $LaneRoot has $Lanes lane folders of symlinks -> original TIFFs (no data copied)."
"Launch with:"
"  .\Launch-Lanes-Exe.ps1 -LaneRoot '$LaneRoot' -ResultsRoot 'C:\Users\Administrator\Documents\hCO_v2' -Lanes $Lanes -WhatIfOnly"
