# Operations Playbook

A practical checklist for running the AQuA2 pipeline end-to-end without learning every gotcha the hard way. This is the document to read **before** kicking off a new dataset, and the document to consult when something goes sideways mid-run.

If you've never run the pipeline before, read [01_OVERVIEW.md](01_OVERVIEW.md) first for what the pipeline does. This doc is about how to operate it well.

---

## 1. Pre-flight checklist (before ANY run)

Don't skip these. Each one of them, somewhere in the project's history, was the thing that cost half a day.

### 1.1 — Disk space

Detection produces **3-5× the input TIFF size** (raw stacks + movies + feature tables + CSVs). A 1 TB input dataset produces 3-5 TB of output. CFU output is small (~100 MB total) but adds on top.

Before launching:

```powershell
Get-PSDrive C | Select @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```

Required free: **roughly 5× the input dataset size**. If you don't have that, either downsize the input set, expand the EBS volume (in AWS Console: Volumes → Modify), or stream outputs to S3 incrementally (slower, more complex).

### 1.2 — S3 bucket sanity

Confirm you're pointing at the right bucket. The lab has both `bireylab-arvin` (legacy) and `bireylab-arvin-us-east-2` (canonical). Active analysis lives in the latter:

```powershell
aws s3 ls s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/
```

If you see `AQuA2_Outputs/`, `ARCHIVE/`, `CalciumImagingTIFFs/`, `R_Analysis_Results/` — you're in the right place.

### 1.3 — Parameter selection

Open `C:\AQuA2\cfg\parameters_for_batch.csv` and confirm every row matches what you want for THIS dataset. Critical fields:

| Parameter | What happens if wrong |
|---|---|
| `frameRate` | Every event timing in the dataset is wrong by the ratio |
| `spatialRes` | Pixel-to-micron conversion wrong → event areas wrong |
| `maxSize` | Too low: events truncated, hyperactive files hang. Too high: runaway memory on hot files |
| `thrARScl` | Too low: too many events including noise. Too high: real events missed |
| `sourceSensitivity` | CFU clustering threshold; wrong value → wrong number of CFUs |

**Document chosen values per dataset.** The orchestrator does this automatically — every run writes the following audit files to `<OutputRoot>\_logs\`:

| File | What it captures |
|---|---|
| `RUN_SUMMARY.md` | Human-readable run report: phases, parameters, results, where to find more |
| `run_manifest.json` | Machine-readable version of the same (good for cross-run comparisons) |
| `parameters_for_batch_USED.csv` | Exact detection parameter CSV in effect for this run |
| `cfu_parameters_BAKED.txt` | CFU thresholds compiled into the `cfu_lane.exe` that ran |
| `per_file_status_detection.csv` | OK/FAIL/timestamp for every TIFF that detection touched |
| `per_file_status_cfu.csv` | OK/FAIL/timestamp for every file that CFU touched |
| `pipeline_<timestamp>.log` | Full orchestrator transcript (verbose) |

If you're using the orchestrator: the audit trail is automatic. If you're running scripts manually, **drop a `README.md` in the dataset's output folder noting the parameters you used**. The `opts` struct inside each `_AQuA2.mat` is the deepest authoritative record but is not discoverable without code.

### 1.4 — R script preparation

If you're going to run the R analysis, **open the R script you'll use and update**:

1. `frame_interval` — must match the **actual** acquisition rate of this dataset (`1 / Hz`). **Don't leave the previous dataset's value.** This is the single most-common R script mistake.
2. **Filename-parsing regex** — must match this dataset's filename convention. The script silently drops files that don't match. Run the script's `pairing_and_parse_audit.csv` check first.
3. **Scope filters** (`INCLUDE_DONORS`, `INCLUDE_CONDITIONS`, etc.) — set to match your target groups, or `NULL` for all.
4. **`META_COLS`** — set columns that don't exist for this dataset to `NA`.

### 1.5 — Instance sizing

> **Pricing note.** Dollar figures in this doc are rough, on-demand, us-east-1/us-east-2, as of mid-2026, and are illustrative only — they have drifted and are not consistent across every doc. Always confirm the current rate in the [AWS pricing page](https://aws.amazon.com/ec2/pricing/on-demand/) (or with Spot) before committing to a long run.

| Dataset size | Recommended instance |
|---|---|
| < 100 TIFFs, exploratory | r7i.2xlarge (8 vCPU, 64 GB, ~$0.5/hr) |
| 100-500 TIFFs | r7a.8xlarge (32 vCPU, 256 GB, ~$2/hr) |
| 500-2000 TIFFs (production) | r7a.24xlarge (96 vCPU, 768 GB, ~$6/hr) |
| > 2000 TIFFs | r7a.48xlarge or split into multiple machines |

Downsizing after detection is OK if CFU and R analysis are smaller workloads. Detection is the bottleneck — size for that.

### 1.6 — Cost estimate

Rough rule: `total_cost ≈ (instance_$/hr) × (TIFFs / 30)` for 32-lane detection on r7a.24xlarge. Check before launching:
- 100 TIFFs × ~$6/hr / 30 ≈ $20
- 1000 TIFFs × ~$6/hr / 30 ≈ $200
- 2000 TIFFs × ~$6/hr / 30 ≈ $400

Plus a few dollars for CFU and R phases. Plus S3 storage on the back end (typically $0.023/GB/month for outputs).

### 1.7 — Auto-size lane count (recommended, ~10 min)

Instead of guessing how many lanes the instance can handle, profile one file and let the math tell you. Run [`Auto-Size-Lanes.ps1`](../powershell/Auto-Size-Lanes.ps1):

```powershell
.\Auto-Size-Lanes.ps1 -ProbeFolder C:\path\to\AllTIFFs
```

This:
- Picks the LARGEST TIFF in the folder (best proxy for peak demand)
- Runs it through `aqua_lane.exe` once while sampling RAM every 5 sec
- Skips the first 30 sec of samples (MATLAB Runtime warmup)
- Reports peak RAM, recommends N lanes given instance specs + a safety factor
- Tells you whether the binding constraint is RAM, CPU, or the hard cap
- Suggests the next commands (`Split-IntoLanes`, `Launch-Lanes-Exe`, `Build-CFU-Lanes`, `Launch-CFU-Lanes`) with the recommended N already filled in

Takes 5-15 minutes for the profile + a few seconds of math.

If you just want to see instance specs without profiling, run [`Get-Instance-Capacity.ps1`](../powershell/Get-Instance-Capacity.ps1) — same instance specs, no profiling, returns immediately.

**When to bump the safety factor** (default `-SafetyFactor 1.5`):
- If you've seen OOM crashes on this dataset type before → bump to 2.0
- If the dataset has unusually variable file sizes/activity → bump to 2.0
- If the probe file you picked isn't representative of the largest/hottest files → bump to 2.0

---

## 2. The smoke test (mandatory for any new dataset)

**Before launching a 24-hour run, run ONE file through the entire pipeline.** Total: 10-15 minutes of your time. Catches ~90% of configuration errors.

The smoke test:

```powershell
mkdir C:\smoke\tiffs
copy C:\path\to\one_file.tif C:\smoke\tiffs\

& "C:\AQuA2\compiled\aqua_lane.exe" "C:\smoke\tiffs" "C:\smoke\detection_out"
ls C:\smoke\detection_out\one_file\
```

You should see: `one_file_AQuA2.mat`, `one_file_movie.avi`, `one_file_features.csv`, `one_file_features.xlsx`. If anything is missing, **stop and debug**. Don't proceed to the 1000-file run.

Then CFU:

```powershell
& "C:\AQuA2\compiled\cfu_lane.exe" "C:\smoke\detection_out" "C:\smoke\cfu_post"
ls C:\smoke\cfu_post\
```

You should see `one_file_res_cfu.mat`. The original `_AQuA2.mat` should now also have CFU fields baked in.

Then the R script (just open it in RStudio and run a few lines to confirm `rhdf5::H5Rdereference` can read the `.mat` file). Don't run the full script for a single file; just confirm `.mat` reading works.

If all three succeed: the configuration is good. Launch the real run.

---

## 3. Pipeline step notes

The pipeline can be run two ways:

**Option A — One command (recommended for typical use)**: [`Run-Pipeline.ps1`](../powershell/Run-Pipeline.ps1) orchestrates the pipeline with explicit per-phase toggles (`-Split`, `-Detect`, `-CFU`, `-Consolidate`, `-Upload`) and a pre-flight summary that requires user confirmation. `-OutputRoot` and `-ProjectName` are both required; all data + audit live under `<OutputRoot>\<ProjectName>\`.

```powershell
.\Run-Pipeline.ps1 -InputTIFFs C:\Datasets\NewDS\AllTIFFs -OutputRoot C:\Datasets -ProjectName NewDS
```

**By default (v0.8+), Split + Detect + CFU + Consolidate all run; only Upload is off.** A routine run therefore leaves a clean `for_upload/` ready for S3. To stop after detection for manual inspection, pass `-CFU $false`. The old "stop after detection" safety behavior is now handled by the v0.8 completeness gate instead of a default checkpoint — see [`../CHANGELOG.md`](../CHANGELOG.md) and [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) §B.

For datasets that need custom parameters, pass `-ConfigCSV path\to\my_params.csv` and the orchestrator backs up the existing default CSV before swapping in yours.

Progress prints every 60 seconds (one-liner: files done, throughput, ETA, RAM, disk free, failure count) with a detailed snapshot every 5 minutes. Skip the confirmation prompt with `-Force`.

**Option B — Step-by-step (legacy / debugging)**: invoke the individual scripts in sequence. This is the pre-v0.7 manual workflow, retained for isolating a single phase when debugging or for legacy instances without the orchestrator. For routine runs use Option A. Note that the orchestrator uses the `<ProjectName>`-nested layout (`PreCFU/`, `POST/`, `CFU_lanes/`, `for_upload/`); the standalone scripts below take explicit paths and predate that convention, so don't mix outputs from the two.

Either way, what each step does:

### Step 1 — `.lif` to TIFF (Fiji)

Run [`LIF_Extractor.ijm`](../fiji-macros/LIF_Extractor.ijm) in Fiji. Defaults to BireyLab standard: 60s trim @ 15s start, sibling output, warn-on-rate-mismatch.

**Read the extraction log** at `<root>/extraction_log_<timestamp>.txt`. Look for:
- `[FAIL]` — corrupt `.lif` files that need investigation
- `[WARN-RATE]` — series with a different acquisition rate than the rest of the dataset (mixed rates may or may not be a problem for your analysis)
- `[SKIP-NOFI]` — series with no frame interval metadata (typically diagnostic snapshots, OK to skip)

**Count outputs vs expected**:
```powershell
(Get-ChildItem C:\path\to\extracted -Recurse -Filter *.tif | Where-Object { $_.Directory -match "UNTRIMMED|TRIMMED" }).Count
```
Match this against your manifest. If short, find why.

### Step 2 — Consolidate TIFFs

Put all the TIFFs you want detected into ONE directory. If the LIF Extractor wrote them sibling-to-LIF, you'll need to flatten:
```powershell
Get-ChildItem C:\path\to\extracted -Recurse -Filter *.tif | Where-Object { $_.Directory -match "TRIMMED$" } | Copy-Item -Destination C:\AllTIFFs\
```

If filenames could collide across folders, prefix them with their parent path during the copy.

### Step 3 — Split into lanes

Run [`Split-IntoLanes.ps1`](../powershell/Split-IntoLanes.ps1) (start with `-DryRun`, eyeball the plan, then add `-Execute`).

The script size-balances files across lanes greedily. **Don't manually split by alphabet** — file sizes are uneven, and you'd bottleneck on whichever lane got the biggest files. Let the script do it.

**Lane count:** if you ran `Auto-Size-Lanes.ps1` in Step 1.7, use its recommendation. Otherwise the rule of thumb is `min(32, ⌊vCPUs/3⌋)` — leaves enough headroom for the MATLAB Runtime overhead per worker. On r7a.24xlarge (96 vCPU), 32 lanes works.

### Step 4 — Launch detection

```powershell
.\Launch-Lanes-Exe.ps1 -LaneRoot C:\path\to\lanes -ResultsRoot C:\path\to\PreCFU -Lanes 32
```

**Don't launch a second simultaneous batch on the same instance.** The 32 lane workers each use ~10-20 GB RAM under load; doubling them OOMs.

**Monitor**: open Task Manager → Performance → confirm CPU is pegged near 100% and RAM is stable. If RAM creeps up past 90%, kill some lanes (`Stop-Process aqua_lane`) — the resume-safety means re-running picks them back up later.

**Per-lane logs** at `<LaneRoot>\_logs\lane01.log` ... `lane<N>.log`. Tail one to confirm progress:
```powershell
Get-Content C:\path\to\lanes\_logs\lane01.log -Tail 20 -Wait
```

### Step 5 — Verify detection completeness

After detection finishes, count `_AQuA2.mat` files vs input TIFFs:

```powershell
(Get-ChildItem C:\path\to\PreCFU -Recurse -Filter *_AQuA2.mat).Count
```

If less than the input count, find which files failed. Grep the lane logs:
```powershell
Get-ChildItem C:\path\to\lanes\_logs\*.log | Select-String "Error|FAIL"
```

Common failures and their causes are in [06_PITFALLS_AND_RECOVERY.md](06_PITFALLS_AND_RECOVERY.md).

### Step 6 — Build CFU lanes

CFU loads and rewrites multi-GB `.mat` files, so it is I/O-heavy, not CPU-heavy. **Use fewer parallel workers** than for detection — typically 16-28 lanes on a machine where detection ran 32 lanes — because concurrent large writes saturate EBS throughput, and per-lane RAM scales with result size (see [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) B.2).

```powershell
.\Build-CFU-Lanes.ps1 -Root C:\path\to\PreCFU -LaneRoot C:\path\to\CFU_lanes -Lanes 28 -DryRun
.\Build-CFU-Lanes.ps1 -Root C:\path\to\PreCFU -LaneRoot C:\path\to\CFU_lanes -Lanes 28 -Execute
```

This creates **NTFS junctions** to the existing detection results — no data is copied.

### Step 7 — Launch CFU

```powershell
.\Launch-CFU-Lanes.ps1 -LaneRoot C:\path\to\CFU_lanes -Post C:\path\to\POST -LogDir C:\path\to\CFU_lanes\_logs -Lanes 28
```

Passing `-LogDir` is optional now — the current script defaults it to `<LaneRoot>\_logs`, so distinct lane roots get distinct logs. Only if you reuse the *same* `-LaneRoot` for two batches do you need to pass `-LogDir` (or rename the old logs) to avoid overwriting them. See [Pitfall #7](06_PITFALLS_AND_RECOVERY.md).

CFU is fast — usually minutes to a couple hours, not days.

### Step 8 — Consolidate CFU outputs

After CFU, you have two sets of files:
- `<dataset>/PreCFU/<stem>/<stem>_AQuA2.mat` — detection outputs (now with CFU fields baked in)
- `<dataset>/POST/<stem>_res_cfu.mat` — standalone CFU outputs

R analysis reads from both. **Move them to known locations** before running R.

### Step 9 — R analysis

Open the R script in RStudio (or run via `Rscript`). **Audit first**. The script writes `pairing_and_parse_audit.csv` to the output dir. **Open it before trusting the rest of the analysis.** Look for files that didn't parse, files where the regex captured the wrong fields, files where the pair (PreCFU + PostCFU) wasn't found.

If the audit shows N parsed files when you expected N+M: stop, fix the regex, rerun.

### Step 10 — S3 upload

```powershell
aws s3 sync C:\path\to\dataset s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/<your-prefix>/ --dryrun
```

**Always dry-run first.** Look at the file list. If it looks right:
```powershell
aws s3 sync C:\path\to\dataset s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/<your-prefix>/
```

For large datasets (TBs), use `s5cmd --numworkers 32` instead — 10-30× faster than `aws s3 cp`.

---

## 4. Recovery: when things go sideways

### Resume after a crash (the orchestrator died mid-run)

The pipeline is resume-safe at the per-file level. The workers themselves (`aqua_lane.exe`, `cfu_lane.exe`) skip any file whose output already exists, so re-running a phase just processes the not-yet-done files.

**Step 1: check for orphaned workers from the previous run.**

```powershell
Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue
```

If anything is listed, you have a choice:

- **Let them finish.** They continue writing outputs to the right paths. When they're done, re-run the orchestrator and it'll see the completed files and skip them. Best when the workers are making clear progress.
- **Kill them and start fresh.** Use:
   ```powershell
   Get-Process aqua_lane,cfu_lane | Stop-Process -Force
   ```
   Then re-run the orchestrator. The half-finished file (if any) gets re-attempted.

`Run-Pipeline.ps1` will REFUSE to start if it detects live workers. This is intentional — it prevents you from launching new workers on top of orphans (race conditions, log overwrites, corrupted outputs).

**Step 2: re-run the orchestrator with appropriate toggles.**

If the crash was during detection, and split had completed:
```powershell
.\Run-Pipeline.ps1 -OutputRoot C:\NewDS -Split $false -Detect $true
```

The orchestrator will print at start of Phase 2:
```
Already processed (resume): 850 files
Remaining to process:       341 files
(workers' per-file resume guard will skip the already-done ones)
```

Same idea for CFU crashes — re-run with `-CFU $true` and the existing `_res_cfu.mat` files get skipped.

### Phase-complete markers

`Run-Pipeline.ps1` writes a marker file to `<OutputRoot>/_logs/` after each successful phase:

- `PHASE_split_COMPLETE.txt`
- `PHASE_detect_COMPLETE.txt`
- `PHASE_cfu_COMPLETE.txt`
- `PHASE_consolidate_COMPLETE.txt`
- `PHASE_upload_COMPLETE.txt`

If you re-run with a phase toggle ON and its marker exists, the plan summary will warn you:

```
  [X] Detection (aqua_lane.exe)  (PREVIOUSLY COMPLETED 2026-06-04 14:30 -- will re-run; per-file resume guard skips done files)
```

So you can decide at the confirm prompt whether to proceed (re-runs harmlessly thanks to resume guard) or back out and re-launch with the toggle off.

### Other failure modes

### A single file failed during detection

`aqua_lane.exe` has per-file try/catch. The failed file is logged in the lane log with a stack trace. **Re-launching the same lane picks up un-completed files** thanks to the resume-on-existing-`_AQuA2.mat`-guard.

If a file fails repeatedly with the same error: it's either corrupt or has parameter values that won't converge (e.g., a hyperactive recording at high `maxSize`). Options:
- Move the file out of the lane folder; re-run; deal with it separately later
- Re-run JUST that file with a different parameter set (override `parameters_for_batch.csv` for that lane)
- Accept the loss; document the exclusion

### A whole lane crashed (the .exe process died)

Resume-safe. Just re-run `Launch-Lanes-Exe.ps1` with the same args. Completed files are skipped; the failed lane picks back up.

### CFU step ran out of memory

On datasets with very large `.mat` results, many concurrent CFU lanes can exhaust RAM. Symptoms: machine swap-thrashing, lane processes dying with no error. Reduce CFU lane count:
```powershell
.\Launch-CFU-Lanes.ps1 -LaneRoot ... -Post ... -Lanes 16
```

CFU is fast once it runs, so even halving the lanes typically still finishes in an hour or two.

### EBS volume filled up mid-run

Free up space first (often: clear `_logs` from prior runs, prune temp files). If still tight, expand the EBS volume in AWS Console (Volumes → Modify → increase size). Volume expansion is online (no reboot); Windows sees the new space after `diskpart` extend or in newer Windows automatically.

### R script audits show parse failures

**Read the audit CSV.** Each row tells you exactly which file didn't parse. Common causes:
- Filename has a space, dash, or character the regex doesn't expect → adjust regex
- Filename pattern differs from the dataset the script was last used for → adjust regex
- File is genuinely from a different dataset that shouldn't be in this folder → move it out

After fixing the regex, re-source the script and re-check the audit. Iterate until the audit shows 100% parse rate.

---

## 5. Cost-conscious operation

| Stage | Instance size you really need | Hourly cost (approx) |
|---|---|---|
| LIF extraction (Fiji) | Any. Fiji uses 1-2 cores. | ~$0.5/hr on r7i.2xlarge is plenty |
| TIFF consolidation + lane split | Any. Pure file IO. | Same |
| Detection (the bottleneck) | Big. 32-96 cores, 128-768 GB RAM. | ~$2-$6/hr |
| CFU clustering | Medium. I/O-bound, ~16-28 cores. | ~$2/hr is enough |
| R analysis | Small. Single-threaded for most ops. | ~$0.5/hr is fine |
| S3 upload | Any. Network-bound. | Same |

**Practical strategy**: launch the big instance for detection only. Stop the instance the moment detection is done (snapshot first if you want to come back). Resume on a smaller instance for CFU + R + upload.

Even with stop+resize, the EBS volume retains all your data. Cost difference: 24h on r7a.24xlarge ($120) vs 24h on r7i.2xlarge ($13). Adds up over a year.

---

## 6. Quick gotcha reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `aqua_lane.exe` prints banner, then errors on "directory not found" | Path argument has trailing whitespace or wrong slash | Check the PS1 launcher's path-building |
| Detection takes 10× longer per file than expected | `maxSize` too high; hyperactive recording running away | Look at `_logs/lane<N>.log` for which file; lower `maxSize` for that file |
| All lanes are running but CPU is at 30%, not 100% | IO bottleneck (TIFFs on slow disk) | Move data to gp3 with throughput ≥250 MB/s, or to a local NVMe |
| `cfu_lane.exe` finishes but `_res_cfu.mat` files are missing | Either CFU didn't actually run (check log) or output went to wrong path | Confirm `-Post` argument in launcher matches what you expect |
| R script reads `.mat` files and gets `NULL` for every field | `rhdf5` is failing silently. Often = R using `hdf5r` not `rhdf5` | `library(rhdf5)` explicitly, check `H5Rdereference` works |
| Lane logs show files completed but `_AQuA2.mat` files are missing | The `_failures/` subfolder has them — they crashed during save | Read `_failures\<name>_ERROR.txt` for the cause |
| You re-ran CFU and lost the previous batch's logs | Old fixed `-LogDir` default (Pitfall #7; fixed — default now derives from `-LaneRoot`) | Update the script, or pass `-LogDir` explicitly if reusing a lane root |
| Half-baked outputs in S3 from a failed run | Bad upload; partial sync | `aws s3 rm s3://... --recursive` the bad prefix, re-upload after fixing |

---

## 7. Before terminating an instance

Final checklist:

1. **All outputs synced to S3?** `aws s3 ls s3://...` to confirm
2. **Logs preserved?** `_logs/` folders to S3 if you'll want to debug later
3. **Parameter records saved?** Per-dataset `README.md` with parameter choices
4. **Need to take an AMI of this configuration?** If so, AMI before terminate
5. **EBS volume deletion**: by default, root volume deletes with instance. Check "delete on termination" checkbox before clicking Terminate if you want to be sure

Once verified: terminate. Hourly billing stops the moment state goes to `shutting-down`.
