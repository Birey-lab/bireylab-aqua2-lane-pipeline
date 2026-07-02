# 09 — AMI Quick Launch (v0.9.0 fast path)

This is the **recommended entry point** for new users with access to the pre-built lab AMI `Windows2025-AQuA2-Pipeline-v3` (`ami-03473aa6f1cc13fbc`, us-east-1). It bypasses the manual infrastructure setup ([`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md)) and most of the multi-script operations ceremony ([`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) — retained for advanced/debugging use) by leveraging the `Run-Pipeline.ps1` orchestrator (v0.9.0+).

If you don't have AMI access yet, or need to build a new AMI from scratch, fall back to docs 02 → 04 in order.

---

## Contents

- [A. Who this is for and what you get](#a-who-this-is-for-and-what-you-get)
- [B. Launch an instance from the AMI](#b-launch-an-instance-from-the-ami)
- [C. First-time verification](#c-first-time-verification)
- [D. Get your TIFFs onto the instance](#d-get-your-tiffs-onto-the-instance)
- [E. Run the pipeline (one command)](#e-run-the-pipeline-one-command)
- [F. Monitor a running job](#f-monitor-a-running-job)
- [G. Recover from interruption or failure](#g-recover-from-interruption-or-failure)
- [H. Sync results to S3](#h-sync-results-to-s3)
- [I. Tear down](#i-tear-down)
- [J. When NOT to use this path](#j-when-not-to-use-this-path)

---

## A. Who this is for and what you get

### A.1 — Audience

You're a lab member or collaborator who:

- Has access to the BireyLab AWS account (or your own with the AMI shared in)
- Has TIFFs (or LIFs that you'll convert locally with Fiji macros)
- Wants to run AQuA2 detection + CFU + S3 backup with minimal infrastructure overhead

### A.2 — What the AMI ships with

The AMI `Windows2025-AQuA2-Pipeline-v3` (`ami-03473aa6f1cc13fbc`, built 2026-06-15) is a Windows Server 2025 image with everything pre-installed and on PATH. Unlike the earlier `v2-Clean` image, v3 was sysprepped so **each instance launched from it gets its own unique Administrator password** (retrieve it via EC2 console → Connect → RDP client → Get password, decrypt with your key pair). Do not use `v2-Clean`: every instance from it shared one baked-in password.

| Component | Location | Notes |
|---|---|---|
| MATLAB R2026a Update 2 | `C:\Program Files\MATLAB\R2026a\` | 11 toolboxes incl. Curve Fitting (required by AQuA2 `fitoptions`) |
| AQuA2 + lab wrappers | `C:\AQuA2\` | Source `.m` files + compiled `.exe` workers |
| Compiled detection worker | `C:\AQuA2\compiled\aqua_lane.exe` | ~4.8 MB |
| Compiled CFU worker | `C:\AQuA2\compiled\cfu_lane.exe` | ~4.8 MB |
| AQuA2 parameter CSV | `C:\AQuA2\cfg\parameters_for_batch.csv` | Detection params (edit before running) |
| CFU parameters (documented) | `C:\AQuA2\cfg\cfu_parameters_BAKED.txt` | CFU params are compiled into the .exe — edit `.m` + recompile to change |
| R 4.5.1 | `C:\R\` (`bin` on PATH) | rhdf5, tidyverse, dplyr, tidyr, readr, lme4, ggplot2 pre-installed |
| Fiji | `C:\Fiji\fiji-windows-x64.exe` | With macros: `TrimTIF_Frames.ijm`, `LIF_Extractor.ijm`, `AQUA2_Movie_Timestamp.ijm` |
| AWS CLI v2 | `C:\Program Files\Amazon\AWSCLIV2\` | For S3 sync |
| Git | `C:\Program Files\Git\` | For pulling orchestrator updates |
| Orchestrator repo | `C:\Users\Administrator\Documents\pipeline-repo\` | This repo, cloned. Run `git pull` to get latest. |

You do **not** need to install anything to start a typical run.

### A.3 — What the AMI does NOT give you

- **Your data.** TIFFs (or LIFs to convert) you bring yourself.
- **An IAM role.** Attached at instance launch — see [§B.2](#b2--required-iam-role).
- **A MATLAB license at runtime.** None needed — the workers are compiled and run on the free MATLAB Runtime. (A MATLAB license IS needed to *recompile* the workers — e.g., to apply the `ftsGlo2` channel fix or change CFU thresholds; that's a maintainer task.)
- **R script automation.** Run R scripts manually post-pipeline; see [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md).

---

## B. Launch an instance from the AMI

### B.1 — Pick the right instance size

The `Run-Pipeline.ps1` orchestrator's Auto-Size phase probes your largest input TIFF and chooses a safe lane count automatically. You only need to pick the instance type. Rough sizing:

| Dataset size | Instance type | vCPU | RAM | ~$/hr (approx.) | Typical wall-clock |
|---|---|---|---|---|---|
| <30 files (smoke test, 5x assembloids) | `r7i.2xlarge` | 8 | 64 GB | ~$0.5 | 1-2 hours |
| 30-100 files (small to medium) | `r7a.4xlarge` | 16 | 128 GB | ~$1 | 1-3 hours |
| 100-500 files (medium) | `r7a.12xlarge` | 48 | 384 GB | ~$3 | 2-5 hours |
| 500-1500 files (large 20x runs) | `r7a.24xlarge` | 96 | 768 GB | ~$6 | 6-20 hours |

Empirical rule from prior runs: detection on a 20x TIFF takes 15-30 min on one core, with peak RAM ~12-15 GB per lane. Instance RAM ÷ 15 GB ≈ max safe lane count. The Auto-Size phase doesn't exceed this.

For deeper sizing methodology (probe protocol on a 5-file subset before committing to a 1000-file run), see [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md).

### B.2 — Required IAM role

The instance MUST be launched with an IAM role that grants S3 access. The lab role is `EC2toS3Full` (full read/write to all `bireylab-*` buckets).

If you don't see this role in your launch dropdown:

- You're in the wrong AWS account (lab AMI lives in the BireyLab account; ask Arvin)
- The role exists but isn't attached to your IAM permissions; ask Arvin for `iam:PassRole` on `EC2toS3Full`

You can attach the role post-launch via EC2 console → Actions → Security → Modify IAM role, but it's cleaner at launch.

### B.3 — Launch checklist

AWS Console → EC2 → AMIs → search `Windows2025-AQuA2-Pipeline-v3` → **Launch instance from AMI**:

- **Name**: `<your-initials>-aqua2-<dataset-name>-<date>` (e.g., `ab-aqua2-foxp1-2026-06-15`)
- **Instance type**: from [§B.1](#b1--pick-the-right-instance-size)
- **Key pair**: your existing lab key pair (or generate a new one; save the `.pem` to `~/.ssh/`)
- **Network settings**:
  - **Security group**: allow RDP (port 3389) from your IP only (`My IP` in console)
  - Default VPC and subnet are fine
- **Storage**: AMI default is 250 GB. For datasets >500 GB on disk (large 20x runs), bump to 500-1000 GB. Volumes can be expanded after launch but not shrunk.
- **Advanced details** → **IAM instance profile**: `EC2toS3Full`
- **User data**: leave blank

Click **Launch instance**. Wait ~2 min for status to go from "pending" to "running".

### B.4 — Connect via RDP

The instance has a public DNS name (visible in EC2 console). Connect:

**Mac**: install Microsoft Remote Desktop from the App Store. Add PC:
- **PC name**: public DNS or public IP from EC2 console
- **User account**: `Administrator`
- **Password**: in EC2 console → select instance → **Connect** → **RDP client** → **Get password**, upload your private key (`.pem`) to decrypt, copy the password

**Windows**: built-in Remote Desktop Connection works the same way.

Click Connect. Accept any certificate warning. You should see a Windows desktop.

---

## C. First-time verification

Open PowerShell on the EC2 instance (Start menu → PowerShell). Run these checks one time after every fresh launch:

```powershell
# Pull latest orchestrator
cd C:\Users\Administrator\Documents\pipeline-repo
git pull
git describe --tags
# Should show v0.9.0 or later

# Tool checks (all should return paths, not errors)
where.exe matlab
where.exe Rscript
where.exe aws
where.exe git
(Get-Item C:\AQuA2\compiled\aqua_lane.exe).LastWriteTime
(Get-Item C:\AQuA2\compiled\cfu_lane.exe).LastWriteTime

# Verify IAM role attached + S3 reachable
aws sts get-caller-identity
aws s3 ls s3://bireylab-arvin-us-east-2/ | Select-Object -First 5

# Disk check
Get-Volume C | Select-Object @{N='UsedGB';E={[math]::Round(($_.Size-$_.SizeRemaining)/1GB,1)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,1)}}
```

If any of these fail, see [§J](#j-when-not-to-use-this-path) for fallback paths.

---

## D. Get your TIFFs onto the instance

Three options, pick whichever fits your situation.

### D.1 — Option A: pull from S3 (recommended if TIFFs are already in S3)

```powershell
mkdir D:\incoming_tiffs
aws s3 sync `
    s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/CalciumImagingTIFFs/hCO/d100/your_dataset/TRIMMED/ `
    D:\incoming_tiffs\
```

If the source bucket is in `us-east-2` and the EC2 is in `us-east-1`, you pay $0.02/GB cross-region egress (a 100 GB transfer = $2). Minor for one-time pulls; meaningful for repeated transfers.

### D.2 — Option B: upload from your Mac first, then pull

```bash
# On Mac
aws s3 cp ~/data/my_dataset/TRIMMED/ s3://bireylab-arvin-us-east-2/temp/upload_2026-06-15/ --recursive
```

```powershell
# On EC2
aws s3 sync s3://bireylab-arvin-us-east-2/temp/upload_2026-06-15/ D:\incoming_tiffs\
```

### D.3 — Option C: zip-and-upload via RDP file sharing (small datasets only)

Mac Microsoft Remote Desktop supports drive redirection. Configure the connection to share a local folder, then in the EC2 file explorer copy from `\\tsclient\<your_folder>\` to `D:\incoming_tiffs\`. Slow for >5 GB; useful for one-off small jobs.

### D.4 — Verify

```powershell
$count = (Get-ChildItem D:\incoming_tiffs -Filter *.tif).Count
$totalGB = [math]::Round(((Get-ChildItem D:\incoming_tiffs -Filter *.tif | Measure-Object -Property Length -Sum).Sum / 1GB), 2)
"Input TIFFs: $count files, $totalGB GB total"
```

If `count` is 0, recheck the source path.

---

## E. Run the pipeline (one command)

This is where the orchestrator (v0.8+) dramatically simplifies vs the manual workflow in [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md).

### E.1 — Edit detection parameters (if needed)

Open `C:\AQuA2\cfg\parameters_for_batch.csv` in Notepad. The **File1** column is the active preset. Critical rows to check:

| Variable | Typical | Notes |
|---|---|---|
| `frameRate` | 0.05 (20 Hz) or 0.1 (10 Hz) | seconds/frame. **NOT** auto-detected from filename. |
| `spatialRes` | 1.3 (20x) or 2.6 (10x) | µm/pixel. Verify on your microscope. |
| `maxSize` | varies by dataset | hCO/FOXP1 commonly use 400; assembloids may use 50000. **Document your choice** in the run README. |
| `detectGlo` | 0 (off) | Set to 1 if you want global signal outputs (adds 2 files per recording). |

Other parameters: leave at AQuA2 defaults unless you know what you're changing.

> **Why not auto-set `frameRate` from the filename?** The filenames encode acquisition rate (e.g., `_19.08Hz.tif`), but the parameter CSV is global across all files in a run. If your dataset has mixed frame rates, run them as separate batches.

### E.2 — Dry-run preview (always do this first)

```powershell
cd C:\Users\Administrator\Documents\pipeline-repo\powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs "D:\incoming_tiffs" `
    -WhatIfMode
```

The dry-run prints:

- Input file count and total size
- Auto-sized lane count
- Disk space available vs needed
- **Active parameter values** (with `detectGlo` highlighted yellow=OFF / green=ON)
- 3-stage stall thresholds (warn 30 min / escalate 45 min / auto-skip 60 min)
- Resume status (any files already done from a previous run)

Read it carefully. Especially: confirm `detectGlo` is the value you want, confirm `maxSize` and `frameRate` look right, confirm the disk has enough room (a rough guide: total input size × 5 = peak disk usage with all outputs).

### E.3 — Full pipeline including S3 upload

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs "D:\incoming_tiffs" `
    -Upload $true `
    -S3Prefix "s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/"
```

`-Upload $true` automatically enables Consolidate (Phase 4) because Upload depends on the consolidated `for_upload/` folder structure.

You'll see a confirmation prompt (`Proceed? [Y/n]`). Press **Y** to run, anything else to abort. To skip the prompt for automated runs, add `-Force`.

### E.4 — Run subset of phases

If you only want detection (e.g., to do CFU and upload later):

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs "D:\incoming_tiffs" `
    -CFU $false `
    -Consolidate $false `
    -Upload $false
```

To re-do just CFU without re-running detection:

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -Split $false `
    -Detect $false `
    -CFU $true `
    -Consolidate $false
```

(The `-Split $false` is important on re-runs: Split MOVES files, so re-splitting an already-split dataset would be destructive.)

### E.5 — What happens during a run

The orchestrator drives 5 phases:

1. **Auto-Size** (if `-Lanes` not specified): probes largest TIFF to determine safe lane count
2. **Split**: moves TIFFs from `InputTIFFs` into `<projectRoot>\lanes\laneNN\` folders (size-balanced)
3. **Detect**: launches N `aqua_lane.exe` workers in parallel, each processes its lane's TIFFs, outputs to `<projectRoot>\PreCFU\laneNN_results\<stem>_AQuA2.mat`
4. **CFU**: launches M `cfu_lane.exe` workers (~0.75 × N by default), bakes CFU data into the `.mat` files and writes standalone `_res_cfu.mat` to `<projectRoot>\POST\`
5. **Consolidate**: creates `<projectRoot>\for_upload\` with `input_TIFFs/`, `PreCFU/`, `PostCFU/` subfolders using **hardlinks** (zero extra disk cost, even for multi-GB `.mat` files). The consolidated `PostCFU/` here is the flat copy of `POST/`.
6. **Upload**: `aws s3 sync` of `for_upload/` to the specified S3 prefix

> **Completeness gate (v0.8+).** Detection won't report "done" while real inputs remain unprocessed: it auto-relaunches workers (up to `-MaxDetectRelaunch`, default 3) and, if still short, marks the run incomplete and refuses to run CFU, Consolidate, and Upload. So an interrupted/half-detected run can't be silently packaged or uploaded as if complete.

Every run creates an audit subfolder `<projectRoot>\_logs\run_<timestamp>\` containing:

- `pipeline.log` — full transcript
- `RUN_SUMMARY.md` — human-readable summary
- `run_manifest.json` — machine-readable manifest
- `parameters_for_batch_USED.csv` — archived copy of the AQuA2 params at runtime
- `cfu_parameters_BAKED.txt` — documented CFU params
- `PHASE_<name>_COMPLETE.txt` — per-phase completion markers (`split`, `detect`, `cfu`, `consolidate`, `upload`)
- `per_file_status_detection.csv` / `per_file_status_cfu.csv` — per-file OK/FAIL status
- `failures/` — per-file `_ERROR.txt` for any failures
- `stall_log.txt` — all WARN, ESCALATED, AUTO-SKIP events

This is **essential for reproducibility**. If a downstream analysis produces unexpected results, the audit folder tells you exactly which orchestrator version, which parameter values, and which compiled worker (.exe LastWriteTime) produced the data.

---

## F. Monitor a running job

The orchestrator prints status every 60 seconds:

```
[20:15:25]   23/100   23.0% |  4.5 f/min | ETA 0:17:12 | workers 32/32 | RAM 312.8GB | Disk  198GB | fail 0
```

And a detailed snapshot every 5 minutes showing per-lane progress + log tails:

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
    ...
```

### F.1 — Three-stage stall detection (v0.8.1)

If a lane stops making progress, the orchestrator escalates through three stages:

- **30 min** no progress: yellow `[STALL WARN]` with the lane's last 5 log lines
- **45 min** no progress: red `[STALL ESCALATED]` banner with last 10 log lines + manual intervention instructions (PID to kill manually if you want to skip earlier than 60 min)
- **60 min** no progress (with `-StallPolicy auto-skip` default): `[STALL AUTO-SKIP]` — moves the stuck TIFF to `<lane>\_stalled\`, kills the stuck worker, restarts the lane on remaining files

To customize:

```powershell
# More aggressive (smaller files, less patience)
.\Run-Pipeline.ps1 ... -StallWarnMin 15 -StallEscalateMin 25 -StallAutoSkipMin 40

# More patient (very large files; legitimate slow processing)
.\Run-Pipeline.ps1 ... -StallWarnMin 45 -StallEscalateMin 75 -StallAutoSkipMin 120

# Warnings only, never auto-skip (manual control)
.\Run-Pipeline.ps1 ... -StallPolicy warn-only
```

### F.2 — Watch a specific lane's log

In a separate PowerShell window (don't touch the orchestrator's window):

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"
Get-Content "$proj\PreCFU\_lane_logs\lane14.log" -Tail 30 -Wait
```

Ctrl+C to stop watching (won't affect the run).

### F.3 — Quick status from another window

```powershell
$proj = "D:\runs\my_dataset_2026-06-15"
$inputs = (Get-ChildItem "$proj\lanes" -Recurse -Filter *.tif | Where-Object { $_.Directory.FullName -notmatch '_stalled' }).Count
$detected = (Get-ChildItem "$proj\PreCFU" -Recurse -Filter *_AQuA2.mat).Count
$cfu = (Get-ChildItem "$proj\POST" -Recurse -Filter *_res_cfu.mat -ErrorAction SilentlyContinue).Count
$alive = (Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Measure-Object).Count
"Input: $inputs | Detected: $detected | CFU: $cfu | Workers alive: $alive"
```

---

## G. Recover from interruption or failure

### G.1 — Resume after any interruption

The orchestrator has per-file resume guards. After a network blip, accidental Ctrl+C, instance restart, or stall auto-skip, **re-run the same command**:

```powershell
.\Run-Pipeline.ps1 `
    -OutputRoot "D:\runs" `
    -ProjectName "my_dataset_2026-06-15" `
    -InputTIFFs "D:\incoming_tiffs" `
    -Upload $true `
    -S3Prefix "s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/"
```

Files with existing `.mat` outputs are skipped automatically. The plan summary will show how many files are already done.

**Note**: on resume, `-Split` is ignored if lane folders already exist (the orchestrator derives lane count from existing folders, not InputTIFFs).

### G.2 — Cancel a run mid-flight

In a separate PowerShell window:

```powershell
Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Stop-Process -Force
```

The orchestrator's polling loop will detect zero workers and exit cleanly. State on disk is preserved; re-run to resume.

### G.3 — A single file fails repeatedly

Check `<projectRoot>\_logs\run_<ts>\failures\<stem>_ERROR.txt` for the MATLAB error. Common causes:

- Corrupt TIFF — re-export from Fiji
- TIFF too short (<50 frames) — trim wasn't applied
- Out-of-memory — usually means the file is unusually large; relaunch with a bigger instance, or process the file solo with lower `maxSize`
- Anomalously high event count — AQuA2's feature extraction can exceed memory on extreme event counts (a very active or noisy recording); process it solo with a lower `maxSize`, or exclude and document it

To exclude a problem file and continue, just move it out of the input folder and re-run. Document the exclusion in your run README.

### G.4 — Detailed pitfall guide

For comprehensive recovery patterns beyond what's covered here (corrupted .mat files, network drops mid-S3-sync, instance reboots during long runs, etc.), see [`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md).

---

## H. Sync results to S3

If you ran with `-Upload $true`, this happened automatically. If you ran without Upload (e.g., to inspect locally first), do it manually after the run completes:

### H.1 — Dry-run first

```powershell
aws s3 sync `
    D:\runs\my_dataset_2026-06-15\for_upload\ `
    s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/ `
    --dryrun
```

Review what would be uploaded. Catch any typos in the destination path.

### H.2 — Actual sync

```powershell
aws s3 sync `
    D:\runs\my_dataset_2026-06-15\for_upload\ `
    s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/
```

### H.3 — Verify upload

```powershell
aws s3 ls `
    s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/ `
    --recursive --summarize | Select-Object -Last 2
```

Expected: total object count = N input files × (4-6 output files per recording, depending on `detectGlo`) + 1 README.

> **Tip**: before the big sync, downsize the instance to `r7i.2xlarge`. S3 sync is network-bound, not CPU-bound — paying $6/hr for an idle r7a.24xlarge during a 2-hour upload is wasteful. See [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) Part E.

### H.4 — Write a run README to S3

Document parameters and any caveats. Recommended pattern:

```powershell
$readme = @"
my_dataset_2026-06-15 — AQuA2 Detection + CFU Outputs
======================================================
N recordings: $((Get-ChildItem D:\runs\my_dataset_2026-06-15\PreCFU -Recurse -Filter *_AQuA2.mat).Count)
Magnification: 20x | Donors: <list> | Conditions: <list>

PIPELINE:
  Orchestrator: $(git -C C:\Users\Administrator\Documents\pipeline-repo describe --tags)
  AMI: Windows2025-AQuA2-Pipeline-v3 (ami-03473aa6f1cc13fbc, 2026-06-15)
  Worker .exe: aqua_lane.exe ($(Get-Item C:\AQuA2\compiled\aqua_lane.exe).LastWriteTime), cfu_lane.exe ($(Get-Item C:\AQuA2\compiled\cfu_lane.exe).LastWriteTime)

DETECTION PARAMETERS (active File1 column of parameters_for_batch.csv):
  [paste output of dry-run plan summary here, or reference the archived parameters_for_batch_USED.csv]

EXCLUDED FILES (if any):
  <stem>  -  <reason>

Produced: $(Get-Date -Format 'yyyy-MM-dd')
"@

$readme | Set-Content D:\runs\my_dataset_2026-06-15\README.txt

aws s3 cp D:\runs\my_dataset_2026-06-15\README.txt `
    s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/README.txt
```

---

## I. Tear down

After S3 sync is verified, you have three options for the instance:

### I.1 — Stop (preserves data, $0.025/GB-month for EBS only)

```
EC2 Console → Instances → select → Instance state → Stop instance
```

Local disk preserved. Restart later (Instance state → Start). Useful if you'll run more jobs against the same dataset soon. EBS storage cost ~$25/month per 250 GB.

### I.2 — Terminate (destroys local data, no ongoing cost)

```
EC2 Console → Instances → select → Instance state → Terminate instance
```

Local disk destroyed. The AMI remains; spin up a fresh instance for the next project. **Recommended after each project** unless you have a specific reason to keep the instance around (e.g., interactive R analysis on the EC2).

Before terminating, double-check:

```powershell
# (1) Everything you need is in S3
aws s3 ls s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/ --recursive | Measure-Object -Property Length -Sum
# vs local:
(Get-ChildItem D:\runs\my_dataset_2026-06-15\for_upload -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB

# (2) Audit folder is in S3 too (or at least somewhere safe)
aws s3 cp D:\runs\my_dataset_2026-06-15\_logs\ s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset_2026-06-15/_audit/ --recursive
```

For a comprehensive teardown checklist (audit logs, R results, intermediate artifacts), see [`07_TEARDOWN_CHECKLIST.md`](07_TEARDOWN_CHECKLIST.md).

### I.3 — Downsize then keep running (long upload, big future job, etc.)

If you'll be doing more work soon but the current job is done, downsize before idling:

```
EC2 Console → Instances → Stop → wait → Actions → Instance settings → Change instance type → r7i.2xlarge → Start
```

---

## J. When NOT to use this path

This quick-launch path covers ~90% of routine runs. Fall back to the deeper docs when:

### J.1 — You need to rebuild the AMI

Reasons: new MATLAB version, new R packages, recompiled `.exe` workers (e.g., applying the `ftsGlo2` channel fix or changed CFU thresholds), AMI bit-rot. See [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) for the from-scratch install procedure.

### J.2 — You're sizing an unfamiliar dataset

The Auto-Size phase makes a single-file probe. For mixed datasets (some giant files, some small), or to validate cost estimates before committing to a 24-hour r7a.24xlarge run, use the probe protocol in [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md).

### J.3 — You need to debug the manual workflow

If a phase fails in a way the orchestrator can't recover from (e.g., a corrupt .mat that's flagged as "stuck" but actually causes downstream failures), it can be useful to run the individual scripts manually to isolate the bug. [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) walks through each script standalone.

### J.4 — You're writing R analysis scripts against new data

Pipeline produces `.mat` outputs; R reads them via `rhdf5`. See [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md) for `.mat` schema and example scripts.

### J.5 — You hit a pitfall not covered here

[`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md) — comprehensive list of failure modes observed in real runs.

---

## Next steps

- Run your first job → [`E. Run the pipeline`](#e-run-the-pipeline-one-command)
- Set up R analysis on results → [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md)
- Working through a known-tricky failure mode → [`06_PITFALLS_AND_RECOVERY.md`](06_PITFALLS_AND_RECOVERY.md)
- Wrapping up after a successful run → [`07_TEARDOWN_CHECKLIST.md`](07_TEARDOWN_CHECKLIST.md)
