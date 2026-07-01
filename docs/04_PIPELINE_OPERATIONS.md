# 04 — Pipeline Operations

The day-to-day procedure for running the pipeline on a sized instance. Assumes you've completed [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) and [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) — that is, your instance is provisioned and (if needed) sized for your data.

**As of orchestrator v0.8.5 (July 2026)**, the entire pipeline is driven by a single PowerShell script — `powershell/Run-Pipeline.ps1` — that handles all five phases (Split → Detect → CFU → Consolidate → Upload), per-run audit trails, three-stage stall detection, resume guards, and a detection-completeness gate. This document is structured around that orchestrator. See [`../CHANGELOG.md`](../CHANGELOG.md) for what changed between versions.

If you need to run the underlying scripts manually (debugging an opaque failure, redistributing pathological files, or testing with non-standard inputs), see [Appendix Z](#appendix-z-manual-workflow-pre-v07-or-debugging) for the manual workflow. For >95% of routine runs, **you only need sections A–E**.

---

## Contents

- [A. Pre-flight](#a-pre-flight)
- [B. The orchestrator at a glance](#b-the-orchestrator-at-a-glance)
- [C. Set parameters](#c-set-parameters)
- [D. Dry-run preview (always do this first)](#d-dry-run-preview-always-do-this-first)
- [E. Run the pipeline](#e-run-the-pipeline)
- [F. Monitor a running job](#f-monitor-a-running-job)
- [G. Three-stage stall detection](#g-three-stage-stall-detection)
- [H. Resume after interruption](#h-resume-after-interruption)
- [I. Recovering from failures](#i-recovering-from-failures)
- [J. The per-run audit trail](#j-the-per-run-audit-trail)
- [K. Verifying completion](#k-verifying-completion)
- [L. S3 sync (if not using -Upload)](#l-s3-sync-if-not-using--upload)
- [M. Cleanup and teardown](#m-cleanup-and-teardown)
- [Appendix Z: manual workflow (pre-v0.7, or debugging)](#appendix-z-manual-workflow-pre-v07-or-debugging)

---

## A. Pre-flight

### A.1 — One-time per session setup

Open PowerShell on the EC2 instance. Set execution policy for this window (allows running the orchestrator script without re-signing):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Tune AWS CLI for fast parallel transfers (one-time per instance, persists):

```powershell
aws configure set default.s3.max_concurrent_requests 40
aws configure set default.s3.max_queue_size 10000
```

### A.2 — Pull the latest orchestrator

```powershell
cd C:\Users\Administrator\Documents\pipeline-repo
git pull
git describe --tags
# Should show v0.8.5 or later
```

### A.3 — Verify the stack

```powershell
# Worker exes present and recent
Test-Path C:\AQuA2\compiled\aqua_lane.exe
Test-Path C:\AQuA2\compiled\cfu_lane.exe
(Get-Item C:\AQuA2\compiled\aqua_lane.exe).LastWriteTime
(Get-Item C:\AQuA2\compiled\cfu_lane.exe).LastWriteTime

# AQuA2 parameter CSV present
Test-Path C:\AQuA2\cfg\parameters_for_batch.csv

# AWS auth via IAM role
aws sts get-caller-identity   # should return your account ID and assumed-role ARN

# Free disk
Get-Volume C | Select-Object @{N='UsedGB';E={[math]::Round(($_.Size-$_.SizeRemaining)/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,1)}}
```

If any check fails, see [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) Part H.

### A.4 — Confirm the input TIFFs are accessible

Before launching the orchestrator, place your input TIFFs in a single directory. Most users either:

- Pull from S3:

  ```powershell
  mkdir D:\incoming_tiffs
  aws s3 sync s3://<your-bucket>/CalciumImagingTIFFs/<dataset>/TRIMMED/ D:\incoming_tiffs\
  ```

- Already have TIFFs on the EBS volume from a previous step.

Quick count:

```powershell
$count = (Get-ChildItem D:\incoming_tiffs -Filter *.tif).Count
$totalGB = [math]::Round(((Get-ChildItem D:\incoming_tiffs -Filter *.tif | Measure-Object -Property Length -Sum).Sum / 1GB), 2)
"Input TIFFs: $count files, $totalGB GB total"
```

---

## B. The orchestrator at a glance

`Run-Pipeline.ps1` drives five sequential phases. Each can be toggled on/off independently. **By default (v0.8+), Split + Detect + CFU + Consolidate run; only Upload is off.** Consolidate defaults ON so every run leaves a clean `for_upload/` ready for S3; it no-ops harmlessly if CFU produced nothing. To stop after detection for manual inspection, pass `-CFU $false` (which leaves Consolidate with nothing to do).

> **Completeness gate (v0.8).** If detection finishes with fewer `_AQuA2.mat` outputs than real inputs (`._` AppleDouble sidecars excluded), the orchestrator auto-relaunches the lane workers up to `-MaxDetectRelaunch` times (default 3; completed files are skipped). If it is still short, the run is marked `detectionIncomplete` and **CFU, Consolidate, and Upload all refuse to run** — a partial dataset is never packaged or published as if complete. Fix the offending input(s) and re-run `-Detect`.

| # | Phase | What it does | Output |
|---|---|---|---|
| 0 | **Auto-Size** (implicit) | Probes the largest input TIFF; computes safe lane count for the instance's RAM. Skipped if `-Lanes` is explicitly set. | (selects lane count) |
| 1 | **Split** | Moves TIFFs from `-InputTIFFs` into `<projectRoot>\lanes\laneNN\` folders, size-balanced. | `<projectRoot>\lanes\laneNN\*.tif` |
| 2 | **Detect** | Launches N `aqua_lane.exe` workers in parallel, each processes its lane's TIFFs. | `<projectRoot>\PreCFU\laneNN_results\<stem>_AQuA2.mat` (+ siblings) |
| 3 | **CFU** | Launches M `cfu_lane.exe` workers (~0.75 × N by default) over detected `.mat` files via NTFS junctions. Bakes CFU fields into the original `.mat` AND writes a standalone `_res_cfu.mat`. | `<projectRoot>\POST\<stem>_AQuA2_res_cfu.mat` |
| 4 | **Consolidate** | Builds `<projectRoot>\for_upload\` with `input_TIFFs/`, `PreCFU/` (per-stem), `PostCFU/` (flat). Uses **NTFS hardlinks** — zero extra disk cost. | `<projectRoot>\for_upload\` |
| 5 | **Upload** | `aws s3 sync` of `for_upload/` to the S3 prefix you specify. | (files in S3) |

> **What `Run-Pipeline.ps1` replaced.** Pre-v0.7, you ran `Split-IntoLanes.ps1` → `Launch-Lanes-Exe.ps1` → `Build-CFU-Lanes.ps1` → `Launch-CFU-Lanes.ps1` → `Consolidate-Template.ps1` → `aws s3 sync` by hand, with manual stuck-lane recovery between phases. v0.7+ collapses all of this into one command with built-in resume, audit trails, and stall handling (and, from v0.8, a detection-completeness gate). The old scripts still exist in `powershell/` for the cases in [Appendix Z](#appendix-z-manual-workflow-pre-v07-or-debugging).

### Project root layout

Everything for a given run lives under `<OutputRoot>\<ProjectName>\`:

```
D:\runs\my_dataset_2026-06-15\          ← projectRoot
├── lanes\                              ← phase 1 output (TIFFs moved here)
│   ├── lane01\
│   ├── lane02\
│   └── ...
├── PreCFU\                             ← phase 2 output
│   ├── lane01_results\
│   │   ├── <stem1>_AQuA2.mat
│   │   ├── <stem1>_AQuA2_Ch1.csv
│   │   ├── <stem1>_AQuA2_Ch1_curves.xlsx
│   │   ├── <stem1>_AQuA2_Movie.tif
│   │   └── (with detectGlo=1: also _Glo_Ch1.xlsx, _Glo_Ch1_curves.xlsx)
│   ├── lane02_results\
│   └── _lane_logs\
│       ├── lane01.log
│       └── lane01.err
├── CFU_lanes\                          ← phase 3 NTFS junctions into PreCFU
│   └── _logs\
│       └── cfu_lane01.log
├── POST\                               ← phase 3 output (flat)
│   ├── <stem1>_AQuA2_res_cfu.mat
│   ├── <stem2>_AQuA2_res_cfu.mat
│   └── ...
├── for_upload\                         ← phase 4 output (hardlinks; PostCFU\ here is the consolidated copy of POST\)
│   ├── input_TIFFs\                    ← flat
│   ├── PreCFU\                         ← per-stem subfolders
│   └── PostCFU\                        ← flat
└── _logs\                              ← per-run audit
    └── run_20260615_140532\
        ├── pipeline.log
        ├── RUN_SUMMARY.md
        ├── run_manifest.json
        ├── parameters_for_batch_USED.csv
        ├── cfu_parameters_BAKED.txt
        ├── PHASE_split_COMPLETE.txt
        ├── PHASE_detect_COMPLETE.txt
        ├── PHASE_cfu_COMPLETE.txt
        ├── PHASE_consolidate_COMPLETE.txt
        ├── per_file_status_detection.csv
        ├── per_file_status_cfu.csv
        ├── stall_log.txt
        ├── failures_summary_detection.md
        └── failures\
            └── detection\<stem>_ERROR.txt (one per failed file)
```

---

## C. Set parameters

The orchestrator does not modify parameters — it reads them from the AQuA2 CSV at runtime. **Edit the CSV before launching**.

### C.1 — Edit `parameters_for_batch.csv`

Open `C:\AQuA2\cfg\parameters_for_batch.csv` in Notepad. The format is multi-column: rows are parameters, columns `File1`...`File12` are preset slots. **The active preset is `File1`.** All other columns are alternative presets you can swap in by editing the script (rarely needed).

Critical rows to confirm before every run:

| Variable | Typical | Notes |
|---|---|---|
| `frameRate` | `0.05` for 20 Hz, `0.1` for 10 Hz | seconds/frame. **NOT** auto-detected from filename. If your dataset mixes frame rates, run as separate batches. |
| `spatialRes` | `1.3` for 20x, `2.6` for 10x | µm/pixel. Verify on your microscope. |
| `maxSize` | varies by dataset | hCO/FOXP1 typically 400; assembloids typically 50000. **Document your choice** in the run README so the S3 prefix naming and the data tell the same story. |
| `detectGlo` | `0` (off) | Set to `1` to compute global signal events. Adds 2 extra output files per recording (`_Glo_Ch1.xlsx`, `_Glo_Ch1_curves.xlsx`). |

Other parameters: leave at AQuA2 defaults (`minSize=20`, `thrARScl=2`, `minDur=3`, `sourceSensitivity=9`, `regMaskGap=1`, etc.) unless you have a specific reason to change them.

> **Why not different parameters per file?** The pipeline applies the same File1 column to every file in a batch. If a subset needs different parameters, run them as a separate batch with a different `-ProjectName`. Mixed parameters within a single run are a documentation and reproducibility hazard.

### C.2 — Check CFU parameters (rarely changed)

CFU parameters are **compiled into `cfu_lane.exe`**, not read from a CSV. Current values are documented at `C:\AQuA2\cfg\cfu_parameters_BAKED.txt`:

```
overlapThr1 = 0.5    overlapThr2 = 0.5
minNumEvt1 = 3       minNumEvt2 = 3
maxDist = 10
pValueThr = 1e-5
cfuNumThr = 3
```

Changing these requires editing `C:\AQuA2\cfu_lane.m`, recompiling `cfu_lane.exe`, **and** updating `cfu_parameters_BAKED.txt`. This is a maintainer task — see the comment block at the top of `cfu_parameters_BAKED.txt`.

---

## D. Dry-run preview (always do this first)

Before launching anything that will run for hours, do a dry-run preview. The orchestrator's `-WhatIfMode` flag prints the full plan summary and exits without executing.

```powershell
cd C:\Users\Administrator\Documents\pipeline-repo\powershell

.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs  "D:\incoming_tiffs" `
    -WhatIfMode
```

You'll see:

- **Project paths**: where outputs and logs will land
- **Pre-flight check results**: are the scripts and `.exe`s where they should be, is disk sufficient, etc.
- **Plan summary**: which phases will run, input file count, lane count (auto-sized or specified)
- **Resume context**: how many `.mat` files already exist in `PreCFU` and `POST` (these will be skipped by per-file guards)
- **Active parameter values** from `parameters_for_batch.csv` — specifically the File1 column, with `detectGlo` highlighted yellow (OFF) or green (ON)
- **Stall thresholds**: 30 min warn / 45 min escalate / 60 min auto-skip (defaults)
- **Free disk**

Read this carefully. The most common errors caught at this stage:

- Wrong `detectGlo` value (yellow when you wanted green or vice versa)
- Wrong `frameRate` (defaults to a value that doesn't match your data)
- Insufficient disk space for projected outputs

Fix issues, then re-run dry-run until it looks right.

---

## E. Run the pipeline

After a clean dry-run, drop the `-WhatIfMode` flag:

### E.1 — Full pipeline including S3 upload (most common)

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs  "D:\incoming_tiffs" `
    -Upload      $true `
    -S3Prefix    "s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/"
```

`-Upload $true` auto-enables Consolidate (`-Consolidate $true`) because the upload reads from `for_upload/`.

You'll see a confirmation prompt: `Proceed? [Y/n]`. Press **Y** to launch. To skip the prompt for unattended runs, add `-Force`.

### E.2 — Pipeline without S3 upload

If you want to inspect outputs locally before uploading:

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs  "D:\incoming_tiffs"
# Defaults: Split=$true, Detect=$true, CFU=$true, Consolidate=$false, Upload=$false
```

### E.3 — Run a subset of phases

Each phase has an explicit on/off flag (`-Split`, `-Detect`, `-CFU`, `-Consolidate`, `-Upload`). Use these to re-do or skip phases.

Detection only (skip CFU and everything after):

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs  "D:\incoming_tiffs" `
    -CFU         $false
```

Re-run CFU only (e.g., after fixing CFU parameters and recompiling `cfu_lane.exe`):

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -Split       $false `
    -Detect      $false `
    -CFU         $true `
    -Consolidate $false
```

> **Important about `-Split`**: this phase MOVES files from `-InputTIFFs` into lane folders. **On resume runs, always set `-Split $false`** — re-splitting an already-split tree is destructive. The orchestrator derives the lane count from existing folders when Split is off.

### E.4 — Run a subset of files (after a failure)

The orchestrator's per-file resume guards make subset-runs automatic: just re-run the same command, and files with existing `.mat` outputs are skipped. No need to manually move "done" files aside.

To process only specific files: move the un-wanted ones out of `D:\incoming_tiffs\` before running, OR run a fresh project with a different `-ProjectName`.

### E.5 — Common parameter combinations

| Scenario | Flags |
|---|---|
| First run on a fresh dataset, upload to S3 | (defaults) + `-Upload $true -S3Prefix "..."` |
| First run, inspect locally before uploading | (defaults), then later `aws s3 sync` manually |
| Resume after stall/crash | Same exact command as before. Resume guards handle it. |
| Re-do CFU only | `-Split $false -Detect $false` |
| Re-do Consolidate + Upload only | `-Split $false -Detect $false -CFU $false -Consolidate $true -Upload $true -S3Prefix "..."` |
| Dry-run preview | Add `-WhatIfMode` |
| Skip the proceed prompt | Add `-Force` |

---

## F. Monitor a running job

### F.1 — Status line every 60 seconds

```
[20:15:25]   23/100   23.0% |  4.5 f/min | ETA 0:17:12 | workers 32/32 | RAM 312.8GB | Disk  198GB | fail 0
```

Reads left to right: timestamp, files done/total, percent, throughput (recent window), ETA, workers alive, RAM in use, free disk, fail count.

### F.2 — Detailed snapshot every 5 minutes

```
--- Detailed snapshot @ 20:22:26 ---
Elapsed: 00:10:15
Throughput (recent window): 2.3 files/min
Workers alive: 31/32
Per-lane progress:
  lane01: 3 (0.2 min since last completion) [ALIVE]
    | Elapsed time is 21.127850 seconds.
    | Refining
  lane02: 4 (1.1 min since last completion) [ALIVE]
    | Active region detection...
  lane03: 2 (5.2 min since last completion) [ALIVE]
    | Spatial segmentation...
  ...
```

The `[ALIVE]` / `[gone ]` marker shows whether each lane's worker process is still running. A completed lane normally has `[gone ]` and a "minutes since last completion" matching how long ago it finished.

### F.3 — Watch a specific lane's log live

In a **separate** PowerShell window (don't touch the orchestrator's window):

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"
Get-Content "$proj\PreCFU\_lane_logs\lane14.log" -Tail 30 -Wait
```

Ctrl+C to stop watching (won't affect the run).

### F.4 — Quick external status from another window

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"
$inputs   = (Get-ChildItem "$proj\lanes" -Recurse -Filter *.tif | Where-Object { $_.Directory.FullName -notmatch '_stalled' }).Count
$detected = (Get-ChildItem "$proj\PreCFU" -Recurse -Filter *_AQuA2.mat).Count
$cfu      = (Get-ChildItem "$proj\POST" -Recurse -Filter *_res_cfu.mat -ErrorAction SilentlyContinue).Count
$alive    = (Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Measure-Object).Count
"Input: $inputs | Detected: $detected | CFU: $cfu | Workers alive: $alive"
```

### F.5 — Free disk during a run

```powershell
Get-PSDrive C, D | Select Name, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```

If free disk on the volume holding `<projectRoot>` drops below `-MinFreeDiskGB` (default 50 GB), the orchestrator aborts the current phase. Move data off the instance or expand the volume.

---

## G. Three-stage stall detection

If a lane stops making progress on its current file, the orchestrator escalates through three stages. Defaults are warn=30 / escalate=45 / auto-skip=60 minutes.

### Stage 1: WARN (yellow)

At 30 min of no progress for a lane:

```
[WARN] [STALL WARN] lane14 (PID 9876) has made no progress for 30.0 min
[WARN]   Last lines from lane14 log:
[WARN]     Watershed grow
[WARN]     Elapsed time is 234.715128 seconds.
[WARN]     Majority
```

Heads-up only — no destructive action. You can intervene manually if you want to abort the file earlier than 60 min:

```powershell
Stop-Process -Id 9876 -Force
```

### Stage 2: ESCALATE (red)

At 45 min:

```
================================================================
 [STALL ESCALATED] lane14 (PID 9876) stalled 45.2 min
================================================================
  Last 10 lines from lane14 log:
    ...
  Auto-skip will fire in 14.8 more minutes (at 60 min total)
  To intervene manually:
    Stop-Process -Id 9876 -Force
```

Still no destructive action. Last chance to inspect and decide before auto-skip.

### Stage 3: AUTO-SKIP (default policy)

At 60 min:

```
[WARN] [STALL AUTO-SKIP] lane14 stalled for 60.1 min -- moving stuck file aside and restarting
```

The orchestrator:

1. Finds the stuck TIFF (the one in `lanes\lane14\` without a matching `_AQuA2.mat` anywhere in `PreCFU\`)
2. Moves it to `lanes\lane14\_stalled\<stem>.tif`
3. Writes a marker to `<projectRoot>\_logs\run_<ts>\stall_log.txt`
4. Kills the worker
5. Relaunches a new worker on the remaining files in the lane

### Customizing the thresholds

```powershell
# Tighter (smaller files, lower patience)
.\Run-Pipeline.ps1 ... -StallWarnMin 15 -StallEscalateMin 25 -StallAutoSkipMin 40

# More patient (very large files, slow but legitimate processing)
.\Run-Pipeline.ps1 ... -StallWarnMin 45 -StallEscalateMin 75 -StallAutoSkipMin 120

# Warn only, never auto-skip (manual control)
.\Run-Pipeline.ps1 ... -StallPolicy warn-only
```

### Handling stalled files after a run

After the run, check for stalled files:

```powershell
Get-ChildItem "<projectRoot>\lanes\*\_stalled" -Filter *.tif -Recurse -ErrorAction SilentlyContinue
Get-Content "<projectRoot>\_logs\run_*\stall_log.txt" -ErrorAction SilentlyContinue
```

Decisions:

- **Try lower `maxSize`**: move the stalled file to a fresh InputTIFFs folder, edit the CSV to a smaller `maxSize` (e.g., 2000), run a single-file batch. Document the parameter difference in your README.
- **Exclude**: leave the file in `_stalled\`, document the exclusion. With N >> 1, a single exclusion rarely affects statistics.

---

## H. Resume after interruption

Anything that interrupts a run — Ctrl+C, network drop, instance reboot, auto-skip — is safe. Re-run the same command:

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot  "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs  "D:\incoming_tiffs" `
    -Split       $false `
    -Upload      $true `
    -S3Prefix    "s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/"
```

**Always set `-Split $false` on resume** — see [E.3](#e3--run-a-subset-of-phases).

The dry-run-style plan summary at the top of each run shows:

```
Detection .mat files:  64  (will be skipped by per-file resume guard)
CFU .mat files:        62  (will be skipped by per-file resume guard)
```

So you can see exactly where you're resuming from.

A new audit subfolder `_logs\run_<new_timestamp>\` is created for each resume — old audit folders are not modified. To reconstruct the full history of a project, list `_logs\run_*\RUN_SUMMARY.md` in order.

---

## I. Recovering from failures

### I.1 — A single file fails

If a file throws a MATLAB exception, the worker writes `<projectRoot>\_logs\run_<ts>\failures\<stem>_ERROR.txt` with the full stack trace and moves on. The orchestrator counts it in the `fail` column of the status line.

Open the `_ERROR.txt` to diagnose. Common causes:

- **Corrupt TIFF** — re-export from Fiji.
- **TIFF too short (<50 frames)** — trim wasn't applied; rerun the trim macro.
- **Out-of-memory** — the file is unusually large; either process it solo on a bigger instance, or lower `maxSize` for that file in a single-file batch.
- **Anomalously high event count** — AQuA2's feature extraction can run out of memory on pathological event counts (a very active or very noisy recording). These typically surface as a stalled lane that auto-skips, or an OOM `_ERROR.txt`; flag the file for manual review and consider a lower `maxSize` for it.
- **Bad cfg path** — the worker can't find `parameters_for_batch.csv`. Confirm it's at `C:\AQuA2\cfg\` and the orchestrator's `-ConfigCSV` resolves to it.

### I.2 — An entire lane errors out at startup

If `<projectRoot>\PreCFU\_lane_logs\laneNN.err` has content (`Length > 0`), the lane's worker failed before processing any file. Open the `.err` to see the error. Common causes:

- Path with spaces/quoting issue in the launcher
- MATLAB Runtime not installed (or wrong version)
- Permission denied on output folder

After fixing, re-run the same orchestrator command — the lane's resume guards handle the relaunch.

### I.3 — Many files fail with the same error

Usually a parameter problem. Check the archived `parameters_for_batch_USED.csv` in the audit folder against what you intended. If `maxSize` is wrong, fix the CSV and re-run; the resume guards skip already-done files.

### I.4 — Detailed pitfall guide

For comprehensive recovery patterns (corrupted `.mat`, network drops mid-S3-sync, instance reboots during long runs, Bug class 9 / "instant return" S3 sync, etc.), see [`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md).

---

## J. The per-run audit trail

Every run creates `<projectRoot>\_logs\run_<timestamp>\` with the following files. These are your **single source of truth** for what happened, with what parameters, on what code version.

| File | Contents |
|---|---|
| `pipeline.log` | Full orchestrator transcript (everything printed to the console) |
| `RUN_SUMMARY.md` | Human-readable summary: phases run, durations, file counts, failures |
| `run_manifest.json` | Machine-readable manifest: orchestrator version, worker .exe LastWriteTime, parameter checksums, timing |
| `parameters_for_batch_USED.csv` | Exact copy of the AQuA2 CSV active at runtime |
| `cfu_parameters_BAKED.txt` | Documented CFU parameters compiled into `cfu_lane.exe` |
| `PHASE_<name>_COMPLETE.txt` | One marker per completed phase (`split`, `detect`, `cfu`, `consolidate`, `upload`), with timestamp |
| `per_file_status_detection.csv` | One row per file: status (OK/FAIL), size, completion time, location |
| `per_file_status_cfu.csv` | Same for CFU phase |
| `stall_log.txt` | All WARN/ESCALATED/AUTO-SKIP events with timestamps |
| `failures\<stem>_ERROR.txt` | One file per failure with full error trace |

**Keep these.** When the audit folder is uploaded to S3 alongside the data, future analysis can always recover which parameters produced which `.mat`. Without it, a downstream surprise (unexpected event counts, missing fields, etc.) is much harder to debug.

The orchestrator does not delete old run folders. After many runs, prune the oldest:

```powershell
# Keep the 5 newest run folders, delete the rest
Get-ChildItem "<projectRoot>\_logs" -Directory -Filter "run_*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 5 |
    Remove-Item -Recurse -Force
```

---

## K. Verifying completion

When the orchestrator says "All phases complete":

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"

# Counts should align (modulo any documented exclusions)
$inputs  = (Get-ChildItem "$proj\lanes" -Recurse -Filter *.tif | Where-Object { $_.Directory.FullName -notmatch '_stalled' }).Count
$detected = (Get-ChildItem "$proj\PreCFU" -Recurse -Filter *_AQuA2.mat).Count
$cfu      = (Get-ChildItem "$proj\POST" -Recurse -Filter *_res_cfu.mat).Count
"Inputs: $inputs   Detected: $detected   CFU: $cfu"

# No workers still running
(Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Measure-Object).Count   # want 0

# Lane .err files have no content (fatal lane-level errors)
Get-ChildItem "$proj\PreCFU\_lane_logs" -Filter *.err | Where-Object {$_.Length -gt 0}

# No _ERROR.txt files (per-file failures)
Get-ChildItem "$proj\_logs\run_*\failures" -ErrorAction SilentlyContinue
```

If `detected < inputs`: check `failures\` and `_stalled\` to account for the gap. (From v0.8, detection won't report complete in this state — it auto-relaunches and, if still short, blocks CFU/Consolidate/Upload.)
If `cfu < detected`: usually means the CFU phase didn't finish (a worker died on a bad `.mat`). From v0.8.1 the orchestrator prints a prominent **"CFU INCOMPLETE"** warning at the end of the CFU phase in this case. Check `POST\_failures\*_ERROR.txt` and any `_STALLED_*.txt` markers under `CFU_lanes\`, then re-run with `-Split $false -Detect $false -CFU $true` (the resume guard skips completed files).

Sanity-check the nCFU distribution (quick proxy for run quality):

```powershell
Select-String -Path "$proj\CFU_lanes\_logs\*.log" -Pattern 'nCFU=(\d+)' |
  ForEach-Object { [int]($_.Matches.Groups[1].Value) } |
  Measure-Object -Average -Maximum -Minimum

Select-String -Path "$proj\CFU_lanes\_logs\*.log" -Pattern 'nCFU=0\b' |
  Measure-Object | Select -Expand Count
```

Compare against the case studies in `docs/case-studies/` for what's normal for your sample type. High zero-CFU rates often mean overly strict CFU parameters or a genuinely quiet preparation.

---

## L. S3 sync (if not using -Upload)

If you ran the orchestrator without `-Upload $true`, do the sync manually after verification.

### L.1 — Downsize the instance first

S3 sync is network-bound, not CPU-bound. An idle r7a.24xlarge during a 2-hour upload wastes ~$12. Downsize to r7i.2xlarge — see [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) Part E.

### L.2 — Dry-run

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"
$dest = "s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/"

aws s3 sync "$proj\for_upload\" $dest --dryrun | Measure-Object
```

If the dry-run reports zero files, something's wrong (`for_upload\` may not have been built — re-run with `-Consolidate $true -Split $false -Detect $false -CFU $false`).

### L.3 — Actual sync

```powershell
aws s3 sync "$proj\for_upload\" $dest --storage-class STANDARD
```

For very large transfers, use `s5cmd` (faster):

```powershell
# Install if missing:
# Invoke-WebRequest https://github.com/peak/s5cmd/releases/latest/download/s5cmd_Windows-64bit.zip -OutFile s5cmd.zip
# Expand-Archive s5cmd.zip -DestinationPath C:\tools\s5cmd
# $env:Path += ";C:\tools\s5cmd"

s5cmd --numworkers 32 sync "$proj\for_upload\" $dest
```

### L.4 — Upload the audit folder too

```powershell
aws s3 sync "$proj\_logs\" "$dest/_audit/" --storage-class STANDARD
```

Future-you and collaborators will thank present-you for this.

### L.5 — Write a per-dataset README in S3

```powershell
$readme = @"
$($proj.Split('\')[-1]) - AQuA2 Detection + CFU Outputs
======================================================
N recordings (detected): $(Get-ChildItem "$proj\PreCFU" -Recurse -Filter *_AQuA2.mat | Measure-Object | Select -Expand Count)
Magnification: 20x | Donors: <list> | Conditions: <list>

PIPELINE:
  Orchestrator: $(git -C C:\Users\Administrator\Documents\pipeline-repo describe --tags)
  AMI: Windows2025-AQuA2-Pipeline-v3 (ami-03473aa6f1cc13fbc, 2026-06-15)
  Worker exes: $(Get-Item C:\AQuA2\compiled\aqua_lane.exe | Select-Object -ExpandProperty LastWriteTime) / $(Get-Item C:\AQuA2\compiled\cfu_lane.exe | Select-Object -ExpandProperty LastWriteTime)

DETECTION PARAMETERS:
  (see archived parameters_for_batch_USED.csv in /_audit/)
  maxSize     = <value>
  frameRate   = <value>
  spatialRes  = <value>
  detectGlo   = <0|1>

EXCLUDED FILES (if any):
  <stem>  -  <reason>

Produced: $(Get-Date -Format 'yyyy-MM-dd')
"@

$readme | Set-Content "$proj\README.txt"
aws s3 cp "$proj\README.txt" "$dest/README.txt"
```

### L.6 — Verify the upload

```powershell
aws s3 ls $dest --recursive --summarize | Select-Object -Last 2
(aws s3 ls $dest --recursive | Select-String '_AQuA2\.mat').Count
(aws s3 ls $dest --recursive | Select-String '_res_cfu\.mat').Count
```

Expected counts: detected from [Section K](#k-verifying-completion).

If the sync command returned instantly and verify shows zero — see [`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md) Pitfall 9 ("instant return" pattern).

---

## M. Cleanup and teardown

After verifying S3 has everything:

### M.1 — Free EBS space (if you want to keep the instance)

Safe to delete once S3 sync is verified:

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"

# Detection intermediate (.mat files; you have hardlinked copies in for_upload\ and they're in S3)
# But wait — these ARE the same files as in for_upload\ (hardlinks). Deleting from one location
# only removes that name; data persists if any hardlink still exists. So delete BOTH:
Remove-Item "$proj\PreCFU" -Recurse -Force
Remove-Item "$proj\POST" -Recurse -Force
Remove-Item "$proj\for_upload" -Recurse -Force

# Lane TIFFs (you have them in S3 source)
Remove-Item "$proj\lanes" -Recurse -Force

# Keep _logs/ for now (small)
```

**Do not delete `D:\incoming_tiffs\`** if you didn't sync those to S3 already — they're the source data.

### M.2 — Stop or terminate the instance

For a full teardown checklist (when to keep which files, what to grab before deletion), see [`07_TEARDOWN_CHECKLIST.md`](07_TEARDOWN_CHECKLIST.md).

Quick decision tree:

- **More work on this dataset in the next few days** → Stop the instance (keeps EBS at ~$25/250GB/month, no compute cost)
- **Project complete, AMI exists for next time** → Terminate (no ongoing cost; spin up from AMI for next project)
- **Will run more, need to downsize for a long upload** → Stop, change instance type, Start (see Sizing Guide Part E)

---

## N. Next: R analysis

The data is ready. Continue to [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md) for `.mat` schema, `rhdf5` integration patterns, and the canonical R scripts.

---

## Appendix Z: manual workflow (pre-v0.7, or debugging)

The `Run-Pipeline.ps1` orchestrator wraps these underlying scripts, all of which still exist in `powershell/` and can be called directly when:

- You need to isolate a specific phase for debugging (e.g., reproduce a Build-CFU junction failure)
- You're running on an instance without the orchestrator pulled (legacy instances)
- You need to do a redistribution recovery for a stuck lane that the auto-skip logic can't handle

The manual sequence is:

1. **`powershell\Split-IntoLanes.ps1`** — moves TIFFs from a source folder into N size-balanced lane folders
2. **`powershell\Launch-Lanes-Exe.ps1`** — launches N `aqua_lane.exe` workers, one per lane
3. **`powershell\Build-CFU-Lanes.ps1`** — creates NTFS junctions pointing to per-recording `_results/` folders, grouped into CFU lanes
4. **`powershell\Launch-CFU-Lanes.ps1`** — launches M `cfu_lane.exe` workers
5. **`powershell\Consolidate-Template.ps1`** — flattens detection output into a clean `<stem>_results/` per-recording structure
6. **`aws s3 sync`** — manual upload

Each script accepts `-WhatIfMode` style dry-runs and prints help when run with no arguments. Read the source before invoking; argument names changed between v0.6 and v0.7 series.

**Pathological-file isolation** (when one lane stays alive >>others, can't auto-skip cleanly):

1. Kill all workers: `Stop-Process -Name aqua_lane -Force`
2. List pending TIFFs in the stuck lane (no matching `_AQuA2.mat`):

   ```powershell
   $laneIn  = "<projectRoot>\lanes\lane14"
   $laneOut = "<projectRoot>\PreCFU\lane14_results"
   $done    = Get-ChildItem $laneOut -Recurse -Filter *_AQuA2.mat -ErrorAction SilentlyContinue |
              ForEach-Object { $_.BaseName -replace '_AQuA2$','' }
   $pending = Get-ChildItem $laneIn -Filter *.tif | Where-Object { ($_.BaseName) -notin $done }
   "pending: $($pending.Count)"
   $pending | Select-Object Name
   ```
3. Copy each pending file into its own mini-lane:

   ```powershell
   $redRoot = "<projectRoot>\redist_in"
   Remove-Item $redRoot -Recurse -Force -ErrorAction SilentlyContinue
   $N = $pending.Count
   1..$N | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $redRoot ("lane{0:D2}" -f $_)) -Force | Out-Null }
   $i = 0
   foreach ($f in $pending) {
       Copy-Item $f.FullName (Join-Path $redRoot ("lane{0:D2}" -f ($i+1)))
       $i++
   }
   ```
4. Run with the orchestrator pointed at the redist folder:

   ```powershell
   .\Run-Pipeline.ps1 `
       -OutputRoot "<projectRoot>" `
       -ProjectName "redist" `
       -InputTIFFs  "<projectRoot>\redist_in" `
       -Split       $false `
       -Lanes       $N
   ```
5. By elimination, whichever lane stays alive longest after the others complete is the pathological one — that names the bad file.

This is the same logic as B.4 in the pre-v0.7 docs, adapted to the orchestrator. The three-stage stall detection [§G](#g-three-stage-stall-detection) handles most pathological cases automatically; manual redistribution is the escape hatch when even auto-skip isn't enough.
