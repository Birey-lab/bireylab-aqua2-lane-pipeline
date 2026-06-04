# Consolidate-Assembloids-20x.ps1
# Flatten the assembloid detection results:
#   FROM:  Assembloids_20x_v1\laneNN_results\<stem>_AQuA2.mat (+ csv/xlsx/movie all directly in lane folder)
#          Assembloids_20x_v1\<stem>_results\<stem>_AQuA2.mat (+ siblings, the 12 redist ones)
#   TO:    PreCFU_Assembloids_20x\<stem>_results\<stem>_AQuA2.mat (+ all siblings, one folder per recording)
# Groups files by recording stem and MOVEs them (no extra disk).

param(
    [string]$Src    = 'C:\Users\Administrator\Documents\Assembloids_20x_v1',
    [string]$Dest   = 'C:\Users\Administrator\Documents\PreCFU_Assembloids_20x',
    [switch]$Execute
)

# 1) find every _AQuA2.mat -> that defines a recording stem
$mats = Get-ChildItem $Src -Recurse -Filter *_AQuA2.mat -File
"Detection .mat files found: $($mats.Count)"
if ($mats.Count -eq 0) { Write-Error "No _AQuA2.mat under $Src"; return }

# 2) build stem list + collision check
$stems = $mats | ForEach-Object { ($_.BaseName -replace '_AQuA2$','') } | Sort-Object -Unique
"Unique recording stems: $($stems.Count)"
if ($stems.Count -ne $mats.Count) {
    "WARNING: stem count != .mat count - possible duplicates. Inspect before -Execute."
    return
}

# 3) for each stem, find every file sharing that stem (the .mat + _Ch1.csv + _curves.xlsx + _Glo_Ch1.xlsx + _Movie.tif)
#    NOTE: the stem is a prefix unique enough that no two recordings share it.
$plan = foreach ($m in $mats) {
    $stem = $m.BaseName -replace '_AQuA2$',''
    $laneFolder = $m.Directory.FullName
    # find all files starting with this stem in that folder
    $siblings = Get-ChildItem $laneFolder -File -Filter "$stem*"
    [pscustomobject]@{
        Stem = $stem
        Source = $laneFolder
        Files = $siblings
        TargetFolder = (Join-Path $Dest ($stem + '_results'))
    }
}

# 4) preview / execute
if (-not $Execute) {
    "(dry run) Would create $($plan.Count) <stem>_results folders under $Dest"
    "First 3 plans:"
    $plan | Select-Object -First 3 | ForEach-Object {
        "  $($_.Stem) :  $($_.Files.Count) files  from  $($_.Source)"
        $_.Files | Select-Object -First 5 | ForEach-Object { "      $($_.Name)" }
    }
    "Re-run with -Execute to perform the moves."
    return
}

if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }

$moved = 0; $failed = 0
foreach ($p in $plan) {
    if (-not (Test-Path $p.TargetFolder)) {
        New-Item -ItemType Directory -Path $p.TargetFolder -Force | Out-Null
    }
    foreach ($f in $p.Files) {
        try {
            Move-Item -LiteralPath $f.FullName -Destination $p.TargetFolder -Force -ErrorAction Stop
            $moved++
        } catch {
            Write-Warning "FAILED $($f.Name) -> $($p.TargetFolder) : $($_.Exception.Message)"
            $failed++
        }
    }
}
"`nFiles moved: $moved   Failed: $failed"

# 5) remove now-empty laneNN_results wrappers under Src (only empty dirs)
$emptyWrappers = Get-ChildItem $Src -Directory | Where-Object {
    @(Get-ChildItem $_.FullName -Recurse -File).Count -eq 0
}
foreach ($w in $emptyWrappers) { Remove-Item $w.FullName -Recurse -Force }
"Removed $($emptyWrappers.Count) empty wrapper folders under $Src"

# 6) verify
$finalFolders = (Get-ChildItem $Dest -Directory).Count
$finalMats    = (Get-ChildItem $Dest -Recurse -Filter *_AQuA2.mat).Count
"Result: $Dest holds $finalFolders folders and $finalMats _AQuA2.mat files (want 1012/1012)"
"Remaining non-empty items under $Src (should be just leftover logs or empty):"
Get-ChildItem $Src -Directory | ForEach-Object {
    $n = @(Get-ChildItem $_.FullName -Recurse -File).Count
    if ($n -gt 0) { "  $($_.Name): $n files" }
}

