# Consolidate-hCO-v2.ps1
# Flatten the lane structure: move every <stem>_results folder out of its
# hCO_v2\laneNN_results\ wrapper into one parent folder, then remove the
# now-empty lane wrappers. MOVE (not copy) --- no extra disk used.
#
# Before:  hCO_v2\laneNN_results\<stem>_results\(_AQuA2.mat, _Ch1.csv, _Movie.tif, ...)
# After:   PreCFU_hCO\<stem>_results\(...)
#
# Usage (dry run): .\Consolidate-hCO-v2.ps1
#        (execute): .\Consolidate-hCO-v2.ps1 -Execute

param(
    [string]$Src    = 'C:\Users\Administrator\Documents\hCO_v2',
    [string]$Dest   = 'C:\Users\Administrator\Documents\PreCFU_hCO',
    [switch]$Execute
)

# 1) find every per-recording result folder (the <stem>_results dirs that hold an _AQuA2.mat)
$matFolders = Get-ChildItem $Src -Recurse -Filter *_AQuA2.mat -File |
    Where-Object { $_.Name -notlike '*_res_cfu.mat' } |
    ForEach-Object { $_.DirectoryName } |
    Sort-Object -Unique

"Recording folders found: $($matFolders.Count)"
if ($matFolders.Count -eq 0) { Write-Error "No _AQuA2.mat under $Src"; return }

# 2) collision check --- leaf folder names must be unique before moving into one parent
$leaves = $matFolders | ForEach-Object { Split-Path $_ -Leaf }
$dupes  = $leaves | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dupes) {
    "ERROR: $($dupes.Count) duplicate folder names --- moving would collide:"
    $dupes | ForEach-Object { "  $($_.Name)  x$($_.Count)" } | Select-Object -First 10
    "Aborting. Resolve duplicates before consolidating."
    return
}
"Folder-name collisions: 0  (safe to consolidate)"

# 3) preview / execute
if (-not $Execute) {
    "`n(dry run) Would move $($matFolders.Count) folders into $Dest"
    "First 5 moves:"
    $matFolders | Select-Object -First 5 | ForEach-Object {
        "  $_  ->  $Dest\$(Split-Path $_ -Leaf)"
    }
    "`nRe-run with -Execute to perform the moves."
    return
}

if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }

$moved = 0; $failed = 0
foreach ($f in $matFolders) {
    $leaf = Split-Path $f -Leaf
    $target = Join-Path $Dest $leaf
    if (Test-Path $target) { Write-Warning "skip (exists): $leaf"; $failed++; continue }
    try {
        Move-Item -LiteralPath $f -Destination $target -ErrorAction Stop
        $moved++
    } catch {
        Write-Warning "FAILED to move $leaf : $($_.Exception.Message)"; $failed++
    }
}
"`nMoved: $moved   Failed/skipped: $failed"

# 4) remove the now-empty laneNN_results wrappers
$emptyWrappers = Get-ChildItem $Src -Directory | Where-Object {
    @(Get-ChildItem $_.FullName -Recurse -File).Count -eq 0
}
foreach ($w in $emptyWrappers) { Remove-Item $w.FullName -Recurse -Force }
"Removed $($emptyWrappers.Count) empty lane wrapper folders."

# 5) verify
$final = (Get-ChildItem $Dest -Directory).Count
"Result: $Dest now holds $final recording folders (want 1191)."
"Remaining non-empty items under $Src (should be _lane_logs only, if anything):"
Get-ChildItem $Src -Directory | ForEach-Object {
    $n = @(Get-ChildItem $_.FullName -Recurse -File).Count
    if ($n -gt 0) { "  $($_.Name): $n files" }
}

