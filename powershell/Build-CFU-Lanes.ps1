# Build-CFU-Lanes.ps1
# Partition all *_AQuA2.mat result-folders into K balanced CFU lane folders
# using directory JUNCTIONS (no copying of multi-GB files).
#
# Each cfu_laneNN\ contains junctions -> the real <stem>_results folders.
# cfu_lane.exe globs cfu_laneNN\**\*_AQuA2.mat and processes only its share,
# reading/writing the real files THROUGH the junction.
#
# Usage (dry run): .\Build-CFU-Lanes.ps1 -Lanes 20
#        (execute): .\Build-CFU-Lanes.ps1 -Lanes 20 -Execute

param(
    [string]$Root      = 'C:\Users\Administrator\Documents\hCO_lanes',
    [string]$LaneRoot  = 'C:\Users\Administrator\Documents\CFU_lanes',
    [int]   $Lanes     = 20,
    [switch]$Execute
)

# 1) find every _AQuA2.mat and its containing folder, with size (for balancing)
$mats = Get-ChildItem $Root -Recurse -Filter *_AQuA2.mat -File |
        Where-Object { $_.Name -notlike '*_res_cfu.mat' }
"Found $($mats.Count) _AQuA2.mat files."
if ($mats.Count -eq 0) { Write-Error "No _AQuA2.mat files under $Root"; return }

# each item = the folder that holds one _AQuA2.mat, plus that file's size
$items = $mats | ForEach-Object {
    [pscustomobject]@{ Dir = $_.DirectoryName; Size = $_.Length; Leaf = (Split-Path $_.DirectoryName -Leaf) }
}

# guard: a result-folder should hold exactly one _AQuA2.mat; warn if not
$multi = $items | Group-Object Dir | Where-Object { $_.Count -gt 1 }
if ($multi) { "WARNING: $($multi.Count) folders contain >1 _AQuA2.mat (will still link the folder once)." }
$items = $items | Sort-Object Dir -Unique:$false | Group-Object Dir | ForEach-Object {
    [pscustomobject]@{ Dir = $_.Name; Size = ($_.Group | Measure-Object Size -Sum).Sum; Leaf = (Split-Path $_.Name -Leaf) }
}
"Unique result-folders: $($items.Count)"

# 1b) GUARD: refuse OVERLAPPING result-folders. If one target folder is an ancestor
# of another (e.g. a stray flat laneNN_results\<stem>_AQuA2.mat sitting ABOVE nested
# <stem>_results from a different/mixed run), junctioning both exposes the same
# recordings through two CFU lanes -> two cfu_lane workers write the same .mat ->
# ".mat.tmp is currently in use / appears to be corrupt". That is the mixed/residue
# signature; fail loudly instead of silently double-processing and corrupting data.
$dirSet = @{}
foreach ($it in $items) { $dirSet[$it.Dir.TrimEnd('\').ToLowerInvariant()] = $it.Dir }
$overlaps = New-Object System.Collections.ArrayList
foreach ($it in $items) {
    $p = Split-Path ($it.Dir.TrimEnd('\')) -Parent
    while ($p) {
        if ($dirSet.ContainsKey($p.ToLowerInvariant())) {
            [void]$overlaps.Add([pscustomobject]@{ Parent = $dirSet[$p.ToLowerInvariant()]; Child = $it.Dir })
            break
        }
        $up = Split-Path $p -Parent
        if ([string]::IsNullOrEmpty($up) -or $up -eq $p) { break }
        $p = $up
    }
}
if ($overlaps.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: $($overlaps.Count) overlapping result-folder(s) -- one result-folder contains" -ForegroundColor Red
    Write-Host "another. This is the signature of a MIXED/contaminated PreCFU tree (usually a stray" -ForegroundColor Red
    Write-Host "flat *_AQuA2.mat from a previous run sitting above nested <stem>_results). Junctioning" -ForegroundColor Red
    Write-Host "both would double-process recordings and corrupt output. Remove the stray flat .mat(s)" -ForegroundColor Red
    Write-Host "or use a clean project, then retry." -ForegroundColor Red
    $overlaps | Select-Object -First 15 | ForEach-Object {
        Write-Host ("  parent: {0}" -f $_.Parent) -ForegroundColor Yellow
        Write-Host ("   child: {0}" -f $_.Child) -ForegroundColor Yellow
    }
    if ($overlaps.Count -gt 15) { Write-Host ("  ... and $($overlaps.Count - 15) more") -ForegroundColor Yellow }
    throw "Build-CFU-Lanes: overlapping result-folders detected; refusing to build (would corrupt data)."
}

# 2) greedy size-balanced bin-packing into $Lanes bins
$bins = @{}; $load = @{}
1..$Lanes | ForEach-Object { $bins[$_] = New-Object System.Collections.ArrayList; $load[$_] = [double]0 }
foreach ($it in ($items | Sort-Object Size -Descending)) {
    $min = 1; for ($k=2; $k -le $Lanes; $k++) { if ($load[$k] -lt $load[$min]) { $min = $k } }
    [void]$bins[$min].Add($it); $load[$min] += $it.Size
}

"`nPlanned lanes:"
1..$Lanes | ForEach-Object {
    "{0,-10} files={1,4}  ~{2,7:N1} GB" -f "cfu_lane$_", $bins[$_].Count, ($load[$_]/1GB)
}

if (-not $Execute) {
    "`n(dry run) re-run with -Execute to create $LaneRoot with $Lanes junction folders."
    return
}

# 3) create lane folders of junctions
if (-not (Test-Path $LaneRoot)) { New-Item -ItemType Directory -Path $LaneRoot | Out-Null }
1..$Lanes | ForEach-Object {
    $lane = Join-Path $LaneRoot ("cfu_lane{0:D2}" -f $_)
    if (Test-Path $lane) { Remove-Item $lane -Recurse -Force }   # clears old junctions only (not targets)
    New-Item -ItemType Directory -Path $lane | Out-Null
    foreach ($it in $bins[$_]) {
        $link = Join-Path $lane $it.Leaf
        # mklink /J makes a directory junction; deleting it later never touches the target
        cmd /c mklink /J "`"$link`"" "`"$($it.Dir)`"" | Out-Null
    }
    "  built cfu_lane{0:D2}: {1} junctions" -f $_, $bins[$_].Count
}
"`nDone. Lane folders under $LaneRoot. Junctions point to real result folders (no data copied)."
"NOTE: deleting CFU_lanes later removes only the junctions, never your _AQuA2.mat files."
