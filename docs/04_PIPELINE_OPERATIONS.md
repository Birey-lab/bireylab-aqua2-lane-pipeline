# 04 — Pipeline Operations

The day-to-day procedure for running the pipeline on a sized instance. Assumes you've completed [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) and [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) — that is, your instance is provisioned and sized for your data.

This document walks through the four operational stages: **Detection** → **CFU clustering** → **Consolidation** → **S3 backup**. Plus monitoring and recovery during each.

---

## A. Before you launch anything

### A.1 — Settings and credentials

Set PowerShell execution policy for the session (allows running unsigned scripts in this window only):
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Tune AWS CLI for fast parallel transfers (one-time per instance, persists):
```powershell
aws configure set default.s3.max_concurrent_requests 40
aws configure set default.s3.max_queue_size 10000
```

Verify the toolkit is in place:
```powershell
Test-Path C:\AQuA2\compiled\aqua_lane.exe
Test-Path C:\AQuA2\compiled\cfu_lane.exe
Test-Path C:\AQuA2\cfg\parameters_for_batch.csv
aws sts get-caller-identity   # AWS auth works
```

### A.2 — Set parameters

Edit `C:\AQuA2\cfg\parameters_for_batch.csv` to match your dataset. Critical rows:

| Row | What to set |
|---|---|
| `maxSize` | Active-region size cap. Start at **50000** for cross-comparability; lower (e.g. 2000) only if hyperactive files hang at higher values |
| `spatialRes` | µm per pixel. **1.3** for 20x typical objective on common rigs; **2.6** for 10x; verify on your microscope |
| `frameRate` | Seconds per frame. **0.05** for 20 Hz; **0.1** for 10 Hz; etc. |

Other rows (`minSize`, `thrARScl`, `minDur`, `sourceSensitivity`, etc.) — leave at defaults unless you have a specific reason to change them, since the defaults are AQuA2-recommended for typical calcium-imaging data.

**The parameter CSV is read by all lanes.** Changes apply to every file in the run. If different files need different parameters, run them as separate batches.

### A.3 — Where TIFFs need to be

Have your source TIFFs available locally. Either:
- Already on the EBS volume from a previous step
- Pulled from S3: `aws s3 sync s3://<bucket>/<source-path>/ C:\Users\Administrator\Documents\<dataset>_source\`

The pipeline doesn't care about the source location — what matters is that you can point `Split-IntoLanes.ps1` at a single folder containing all the TIFFs.

---

## B. Stage 1: Detection

### B.1 — Split TIFFs into lanes

The launcher needs a parent folder containing `laneNN/` subfolders, each holding some of the TIFFs. `Split-IntoLanes.ps1` does this:

```powershell
cd C:\Users\Administrator\Documents\pipeline-repo

powershell -ExecutionPolicy Bypass -File .\powershell\Split-IntoLanes.ps1 `
    -Source     "C:\Users\Administrator\Documents\<dataset>_source" `
    -LaneRoot   "C:\Users\Administrator\Documents\<dataset>_lanes" `
    -Lanes      32 `
    -Execute
```

Without `-Execute`, the script prints a dry-run plan showing how many files would go to each lane, with no actual movement. Run that first to confirm it looks right, then add `-Execute`.

The split is size-balanced (greedy bin-packing by file size), so heavy files get distributed rather than concentrated in one lane.

**Verify the split:**
```powershell
Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_lanes" -Directory | ForEach-Object {
  [pscustomobject]@{ Lane=$_.Name; Files=(Get-ChildItem $_.FullName -Filter *.tif).Count }
} | Format-Table -Auto

"Total TIFFs: " + (Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_lanes" -Recurse -Filter *.tif).Count
```

### B.2 — Launch detection

```powershell
powershell -ExecutionPolicy Bypass -File .\powershell\Launch-Lanes-Exe.ps1 `
    -LaneRoot     "C:\Users\Administrator\Documents\<dataset>_lanes" `
    -ResultsRoot  "C:\Users\Administrator\Documents\<dataset>_v1" `
    -ExePath      "C:\AQuA2\compiled\aqua_lane.exe" `
    -Lanes        32
```

The launcher prints `started laneNN (PID xxxx)` for each lane, then exits, leaving 32 `aqua_lane.exe` processes running in the background.

Output goes to `<dataset>_v1\laneNN_results\<stem>_AQuA2.mat` (plus CSV/XLSX/movie siblings) for each recording. Lane logs go to `<dataset>_v1\_lane_logs\laneNN.log` and `.err`.

### B.3 — Monitor

**Quick status snapshot:**
```powershell
$rr = "C:\Users\Administrator\Documents\<dataset>_v1"
$done  = (Get-ChildItem $rr -Recurse -Filter *_AQuA2.mat).Count
$alive = (Get-Process aqua_lane -ErrorAction SilentlyContinue | Measure-Object).Count
$errs  = (Get-ChildItem "$rr\_lane_logs" -Filter *.err -ErrorAction SilentlyContinue | Where-Object {$_.Length -gt 0} | Measure-Object).Count
"Done: $done   |   Lanes alive: $alive   |   Lane-fatal .err files: $errs"
```

**Per-lane progress table:**
```powershell
Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_v1" -Directory |
  Where-Object { $_.Name -like 'lane*_results' } |
  ForEach-Object {
    [pscustomobject]@{
      Lane = $_.Name
      Done = (Get-ChildItem $_.FullName -Recurse -Filter *_AQuA2.mat).Count
    }
  } | Sort-Object Lane | Format-Table -Auto
```

**Watch one lane's log live:**
```powershell
Get-Content "C:\Users\Administrator\Documents\<dataset>_v1\_lane_logs\lane14.log" -Tail 30 -Wait
```
Ctrl+C to stop watching.

**Free disk:**
```powershell
Get-PSDrive C | Select @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```

### B.4 — Recovering from a stuck lane

Sometimes one lane gets stuck on a single pathological file — the SE counter freezes for many minutes, CPU keeps climbing, no progress.

**Diagnostic** (don't kill yet):
```powershell
Get-Process aqua_lane | Select-Object Id, CPU, @{n='RAM_GB';e={[math]::Round($_.WorkingSet64/1GB,1)}}
# wait 2 min, run again
```
If CPU climbs but log SE counter stays frozen for 10+ minutes, it's a pathological loop — not slow-but-working.

**Isolation strategy:**
1. `Stop-Process -Name aqua_lane -Force` (kills the stuck lane; the others have already finished, this targets the survivor)
2. List pending files in the stuck lane (input TIFFs without matching `_AQuA2.mat`):
   ```powershell
   $laneIn  = "C:\Users\Administrator\Documents\<dataset>_lanes\lane14"
   $laneOut = "C:\Users\Administrator\Documents\<dataset>_v1\lane14_results"
   $done    = Get-ChildItem $laneOut -Recurse -Filter *_AQuA2.mat | ForEach-Object { $_.BaseName -replace '_AQuA2$','' }
   $pending = Get-ChildItem $laneIn -Filter *.tif | Where-Object { ($_.BaseName) -notin $done }
   "pending: $($pending.Count)"
   $pending | Select-Object Name
   ```
3. Copy each pending TIFF into its own mini-lane folder (one file per lane):
   ```powershell
   $redRoot = "C:\Users\Administrator\Documents\<dataset>_redist_in"
   Remove-Item $redRoot -Recurse -Force -ErrorAction SilentlyContinue
   $N = $pending.Count
   1..$N | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $redRoot ("lane{0:D2}" -f $_)) -Force | Out-Null }
   $i = 0
   foreach ($f in $pending) {
     Copy-Item $f.FullName (Join-Path $redRoot ("lane{0:D2}" -f ($i+1)))
     $i++
   }
   ```
4. Launch the mini-batch to a separate results root:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\powershell\Launch-Lanes-Exe.ps1 `
       -LaneRoot     "C:\Users\Administrator\Documents\<dataset>_redist_in" `
       -ResultsRoot  "C:\Users\Administrator\Documents\<dataset>_redist_out" `
       -ExePath      "C:\AQuA2\compiled\aqua_lane.exe" `
       -Lanes        $N
   ```
5. The good files finish in parallel. Whichever lane stays alive after the others complete is the pathological one — by elimination, that names the bad file.

**Once identified, decide:**
- **Lower `maxSize`** for that file (e.g., 2000) and run it solo — introduces a mixed-parameter footnote, document carefully
- **Exclude** it — keeps uniform parameters, N drops by 1

Trade-off: a single excluded file at large N rarely affects statistics; mixed `maxSize` is a real confound. Often excluding is the cleaner choice.

### B.5 — Completion check

When detection finishes:
```powershell
(Get-Process aqua_lane -ErrorAction SilentlyContinue | Measure-Object).Count   # want 0

(Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_v1" -Recurse -Filter *_AQuA2.mat).Count   # want N

Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_v1\_lane_logs" -Filter *.err |
  Where-Object {$_.Length -gt 0} | Select Name, Length   # want no output

Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_v1" -Recurse -Filter *_ERROR.txt | Select FullName   # want no output
```
All four should be: **0 processes, N .mat files, no .err with content, no `_ERROR.txt` files**.

If you redistributed (Section B.4), merge the redist results into the main tree. The redist output uses `laneNN_results` names that collide with the main tree's `laneNN_results`, so move the per-recording files into uniquely-named `<stem>_results/` folders:
```powershell
$dest = "C:\Users\Administrator\Documents\<dataset>_v1"
Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_redist_out" -Recurse -Filter *_AQuA2.mat | ForEach-Object {
  $stem = $_.BaseName -replace '_AQuA2$',''
  $target = Join-Path $dest ($stem + "_results")
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Get-ChildItem $_.Directory.FullName -Filter "$stem*" | ForEach-Object {
    Move-Item $_.FullName $target -Force
  }
}
(Get-ChildItem $dest -Recurse -Filter *_AQuA2.mat).Count   # should now equal N (full count)
```

---

## C. Stage 2: CFU clustering

### C.1 — Rename old CFU logs (if any)

The CFU launcher writes logs to a fixed path (`C:\Users\Administrator\Documents\CFU_lanes\_logs\`) regardless of `-LaneRoot`. Before running a new CFU batch, rename any previous run's logs to preserve them:
```powershell
$oldLogs = "C:\Users\Administrator\Documents\CFU_lanes\_logs"
if (Test-Path $oldLogs) {
  Rename-Item $oldLogs "C:\Users\Administrator\Documents\CFU_lanes\_logs_<previous-dataset>"
}
```

### C.2 — Build CFU lanes (junction-based, no data copying)

```powershell
powershell -ExecutionPolicy Bypass -File .\powershell\Build-CFU-Lanes.ps1 `
    -Root       "C:\Users\Administrator\Documents\<dataset>_v1" `
    -LaneRoot   "C:\Users\Administrator\Documents\<dataset>_CFU_lanes" `
    -Lanes      28 `
    -Execute
```

`Build-CFU-Lanes.ps1` recursively globs all `_AQuA2.mat` under `-Root`, then creates 28 lane folders each containing NTFS **junctions** (Windows symlinks for directories) pointing back at the original `<stem>_results/` folders. No data is copied — junctions resolve at runtime.

**Why 28 lanes (vs 32 for detection):** CFU compute is trivial; the bottleneck is EBS write throughput. 28 lanes saturate EBS without thrashing; 32 is fine too.

**Why override `-Root`:** the script's default may point at an old dataset's path. **Always explicitly set `-Root`** to your current dataset's detection output tree.

### C.3 — Launch CFU

```powershell
powershell -ExecutionPolicy Bypass -File .\powershell\Launch-CFU-Lanes.ps1 `
    -LaneRoot  "C:\Users\Administrator\Documents\<dataset>_CFU_lanes" `
    -Post      "C:\Users\Administrator\Documents\<dataset>_POST"
```

Each lane runs `cfu_lane.exe`, which:
1. Loads each `<stem>_AQuA2.mat`
2. Runs CFU clustering
3. **Bakes** `cfuInfo1`, `cfuInfo2`, `cfuRelation`, `cfuGroupInfo` into the `.mat` file (in-place rewrite, atomic temp-and-rename, preserves `fts1`)
4. Writes a **standalone** `<stem>_AQuA2_res_cfu.mat` to the POST folder

So after CFU, each recording has CFU data in *two* places — baked into its original `.mat` and as a separate `_res_cfu.mat`. R analysis typically reads the standalone (`POST/`) for CFU info plus reaches into the original (`PreCFU/`) for `fts1` event timing.

### C.4 — Monitor CFU

CFU is fast (minutes for hundreds of files). Use the same monitoring patterns as detection, substituting `cfu_lane` for `aqua_lane` and the POST folder for the results folder:

```powershell
Get-Process cfu_lane -ErrorAction SilentlyContinue | Measure-Object | Select -Expand Count

(Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_POST" -Filter *_res_cfu.mat).Count
```

### C.5 — Verify completion and pull nCFU distribution

```powershell
# completion checks
(Get-Process cfu_lane -ErrorAction SilentlyContinue | Measure-Object).Count   # want 0
(Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_POST" -Filter *_res_cfu.mat).Count   # want N
(Get-ChildItem "C:\Users\Administrator\Documents\<dataset>_POST\_failures" -Force -ErrorAction SilentlyContinue | Measure-Object).Count   # want 0

# sanity check: nCFU distribution from the lane logs
Select-String -Path 'C:\Users\Administrator\Documents\CFU_lanes\_logs\*.log' -Pattern 'nCFU=(\d+)' |
  ForEach-Object { [int]($_.Matches.Groups[1].Value) } |
  Measure-Object -Average -Maximum -Minimum

Select-String -Path 'C:\Users\Administrator\Documents\CFU_lanes\_logs\*.log' -Pattern 'nCFU=0\b' |
  Measure-Object | Select -Expand Count
```

The nCFU distribution gives you a quick sense of recording activity (mean, max, count of zero-CFU files). High zero-rates may indicate a quiet preparation or overly strict parameters; the case studies have examples for comparison.

### C.6 — Tear down CFU junctions

Once CFU is done, the junctions are no longer needed (data is in POST + baked into the original `.mat`):
```powershell
Remove-Item "C:\Users\Administrator\Documents\<dataset>_CFU_lanes" -Recurse -Force
```
This removes only the junctions, never your actual data. (NTFS junctions are pointers; removing them does not affect what they point to.)

---

## D. Stage 3: Consolidation

The detection output has files mixed in `laneNN_results/` folders, plus any from redistribution in `<stem>_results/` folders. Consolidate everything into a clean per-recording `<stem>_results/` structure for S3 upload:

```powershell
powershell -ExecutionPolicy Bypass -File .\powershell\Consolidate-Template.ps1 `
    -Src    "C:\Users\Administrator\Documents\<dataset>_v1" `
    -Dest   "C:\Users\Administrator\Documents\PreCFU_<dataset>"
```

Without `-Execute`, the script previews what it would do. Verify the count looks right, then run with `-Execute`:
```powershell
powershell -ExecutionPolicy Bypass -File .\powershell\Consolidate-Template.ps1 `
    -Src    "C:\Users\Administrator\Documents\<dataset>_v1" `
    -Dest   "C:\Users\Administrator\Documents\PreCFU_<dataset>" `
    -Execute
```

After consolidation:
```
PreCFU_<dataset>/
├── <stem1>_results/
│   ├── <stem1>_AQuA2.mat
│   ├── <stem1>_AQuA2_Ch1.csv
│   ├── <stem1>_AQuA2_curves.xlsx
│   └── <stem1>_Movie.tif
├── <stem2>_results/
│   ├── ...
└── ... (N folders, one per recording)
```

The POST folder (`<dataset>_POST/`) is already flat with `_res_cfu.mat` files — no consolidation needed there.

---

## E. Stage 4: S3 backup

**Before the big sync, downsize the instance** to r7i.2xlarge — see [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) Part E. Saves ~90% on hourly cost during the long network-bound upload.

### E.1 — Write READMEs documenting the run

Two READMEs, one per S3 folder, capturing parameters and any caveats. Use the template at [`README_template.txt`](README_template.txt). For example:

```powershell
@"
<DATASET> Calcium Imaging - AQuA2 Detection Outputs
====================================================
N recordings: <N>  (<X> excluded - see below if applicable)
Magnification: <20x|10x|5x>  |  Donors: <list>  |  Conditions: <list>

DETECTION PARAMETERS:
  maxSize     = <value> px
  minSize     = 20 px
  thrARScl    = 2
  minDur      = 3
  sourceSensitivity = 9
  detectGlo   = 1, gloDur = 20
  frameRate   = <value> s/frame
  spatialRes  = <value> um/px

EXCLUDED FILES (if any):
  <stem>  -  <reason>

Produced: $(Get-Date -Format 'yyyy-MM-dd')
"@ | Set-Content C:\Users\Administrator\Documents\README_<dataset>.txt
```

### E.2 — Sync detection results to S3

**Single-line command, no backticks**, with the appropriate storage class:
```powershell
aws s3 sync C:\Users\Administrator\Documents\PreCFU_<dataset> "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>_MaxSize<value>/" --storage-class STANDARD
```
Upload the README into the same prefix:
```powershell
aws s3 cp C:\Users\Administrator\Documents\README_<dataset>.txt "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>_MaxSize<value>/README.txt" --storage-class STANDARD
```

### E.3 — Sync CFU standalones to S3

```powershell
aws s3 sync C:\Users\Administrator\Documents\<dataset>_POST "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>_MaxSize<value>_CFU/" --storage-class STANDARD

aws s3 cp C:\Users\Administrator\Documents\README_<dataset>_CFU.txt "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>_MaxSize<value>_CFU/README.txt" --storage-class STANDARD
```

### E.4 — Verify uploads

**After every sync, count what landed:**
```powershell
aws s3 ls "s3://<bucket>/<path>/" --recursive --summarize | Select-Object -Last 2
(aws s3 ls "s3://<bucket>/<path>/" --recursive | Select-String '_AQuA2\.mat').Count
(aws s3 ls "s3://<bucket>/<path>/" --recursive | Select-String '_Movie\.tif').Count
```

Expected:
- **Total Objects:** ~ N × (5-6 files per recording) + 1 README for detection; ~ N + 1 for CFU
- **Total Size:** matches local (within rounding)
- **`_AQuA2.mat` count:** exactly N
- **`_Movie.tif` count:** N (if movies are on)

If the sync returns instantly and the verify shows zero or low counts → re-run. See [`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md) Pitfall 9 for the "instant return" pattern.

---

## F. Resume and recovery patterns

**Resume after any interruption** (network blip, accidental Ctrl+C, instance restart): re-run the same launcher. Resume guards skip already-completed files automatically. Safe to run multiple times.

**Kill all workers cleanly:**
```powershell
Stop-Process -Name aqua_lane -Force      # detection
Stop-Process -Name cfu_lane -Force       # CFU
```
Always kill by **name**, not by PID — PIDs change after relaunches.

**Diagnosing slow vs. stuck:**
```powershell
# climbing CPU = working; flat = deadlocked or finished
Get-Process aqua_lane | Select Id, CPU, @{n='RAM_GB';e={[math]::Round($_.WorkingSet64/1GB,1)}}
# wait 2 min, run again
```

**A file's output is growing or its timestamp updating:** the worker is actively writing → not stuck.

**A lane's `.err` file has content:** that lane hit a fatal error at startup (not a per-file issue). Look at the contents to diagnose.

**A `<stem>_ERROR.txt` exists in the results:** the per-file guard caught a bad file but kept the lane running. Read the file for the error, decide whether to fix-and-rerun or exclude.

---

## G. After everything is in S3

You can optionally delete local copies to reclaim EBS space:

**Safe to delete after S3 verification:**
- Detection output (`<dataset>_v1/` after consolidating to PreCFU and uploading)
- Lane folders (`<dataset>_lanes/` — TIFFs are in S3 source already, and detection won't re-run without these specific files)
- Redist folders (`<dataset>_redist_in/`, `<dataset>_redist_out/`)
- CFU junctions (already removed in Section C.6)

**Always keep locally** until R analysis is fully done:
- `PreCFU_<dataset>/` (R reads the `_Ch1.csv` files recursively from here)
- `<dataset>_POST/` (R reads the `_res_cfu.mat` files from here)

**Source TIFFs:** delete only if you're certain detection won't re-run, *and* you've verified them in S3. Source deletion is irreversible without re-downloading from S3.

```powershell
# only after verifying S3 backup:
Remove-Item "C:\Users\Administrator\Documents\<dataset>_v1" -Recurse -Force
Remove-Item "C:\Users\Administrator\Documents\<dataset>_lanes" -Recurse -Force
```

Free space check:
```powershell
Get-PSDrive C | Select @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```

---

## Next: R analysis

Now the data is ready for statistical analysis. Continue to [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md) for the R integration patterns.
