# Operations Playbook -- v0.7 Supplement

This supplement documents v0.7 changes. Merge into `08_OPERATIONS_PLAYBOOK.md`
as appropriate during the next docs pass.

## Required parameters in v0.7

`-OutputRoot` AND `-ProjectName` are now BOTH required.

- `-OutputRoot` is the **parent directory** for all projects (e.g., `D:\analyses`)
- `-ProjectName` is the **project folder name** (e.g., `foxp1_full_2026_06`)
- Actual data + audit live at `<OutputRoot>/<ProjectName>/`

Example:
```
.\Run-Pipeline.ps1 -InputTIFFs E:\data\raw_tiffs -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06
```

This creates `D:\analyses\foxp1_full_2026_06\` and populates it.

## What changed in v0.7

### Defaults

- `-CFU` defaults to `$true`. Standard invocation runs Split + Detect + CFU
  in one command. Set `-CFU $false` to skip.
- `-Consolidate` defaults to `$false`, but auto-enables to `$true` when
  `-Upload $true` is set.
- `-Upload` defaults to `$false`.

### Directory layout

```
<OutputRoot>/<ProjectName>/
  _logs/                              <- AUDIT
    PHASE_*_COMPLETE.txt              <- top-level: latest markers (resume detection)
    run_<timestamp>[_<RunName>]/      <- per-run subfolder with everything else
      pipeline.log
      RUN_SUMMARY.md
      run_manifest.json
      parameters_for_batch_USED.csv
      cfu_parameters_BAKED.txt
      per_file_status_detection.csv
      per_file_status_cfu.csv
      PHASE_*_COMPLETE.txt            <- per-run historical copies
      stall_log.txt
      failures_summary_*.md
      failures/<phase>/<name>_ERROR.txt
  lanes/                              <- INTERMEDIATE: lane-organized TIFFs
  PreCFU/                             <- INTERMEDIATE: per-stem _AQuA2.mat folders
  CFU_lanes/                          <- INTERMEDIATE: NTFS junctions
  POST/                               <- INTERMEDIATE: per-stem _res_cfu.mat folders
  for_upload/                         <- FLAT S3-READY OUTPUTS (after Consolidate)
    input_TIFFs/                      <- all source TIFFs flat (hardlinked)
    PreCFU/                           <- per-stem subfolders with _AQuA2.mat
    PostCFU/                          <- all _res_cfu.mat in one flat folder
```

Use `-RunName "rerun_relaxed_params"` to label a run with a human-readable
suffix; it's sanitized into the audit folder name.

### Stall detection (NEW)

Each lane is tracked for progress. A "stall" is no completion in a lane for
`-StallWarnMin` minutes (default 15).

**At warn threshold:**
- Prints `[STALL WARN]` line with PID, elapsed stall minutes
- Prints last 5 lines of that lane's log
- Continues polling (no destructive action)

**At auto-skip threshold** (`StallAutoSkipMin`, default 60 min):
- For **detection** lanes: identifies the stuck TIFF (file in lane folder
  without matching `_AQuA2.mat`), moves to `<lane>/_stalled/`, kills the
  lane's worker, IMMEDIATELY restarts a fresh worker on the same lane.
  The new worker's resume-guard skips done files and the quarantined one,
  continues with the next pending file. No files in the lane are abandoned.
- For **CFU** lanes: writes a marker file `_STALLED_<stem>.txt` and kills
  the worker, but does NOT auto-restart (CFU lanes use NTFS junctions so
  file-quarantine semantics differ). User inspects and re-runs.

Override:
- `-StallPolicy warn-only` - warnings only, no auto-action
- `-StallWarnMin 10 -StallAutoSkipMin 90` - custom thresholds

### Stalled-files visual indication

At end of run, if any files were stalled-and-skipped, the orchestrator prints
a yellow-highlighted block listing every stalled file by path. This banner
is the primary visual cue (the run technically succeeded so there's no
exit-code failure).

### Consolidate phase (NEW; Phase 4)

Creates `<projectRoot>/for_upload/` with a flat S3-ready layout:

- **input_TIFFs/**: hardlinks to ALL source TIFFs from lane folders.
  Hardlinks avoid disk doubling. Falls back to Copy-Item if hardlinks fail.
  Excludes `_stalled/` subfolders.
- **PreCFU/**: copies of per-stem subfolders with `_AQuA2.mat` files.
  Excludes `_lane_logs/`, `_failures/`.
- **PostCFU/**: flat directory with ALL `_res_cfu.mat` files (no subfolders).

Triggered automatically by `-Upload $true`, or manually by `-Consolidate $true`.
Idempotent: existing destination files aren't re-linked.

### Phase 5: S3 upload

Sources from `<projectRoot>/for_upload/` if it exists; falls back to
`<projectRoot>/` otherwise. Dry-run first, then real `aws s3 sync`.

### ConfigCSV: simplified

Auto-detect / prompt logic from earlier drafts is REMOVED:
- If `-ConfigCSV <path>` is passed, use it (copies to default location at
  detection start, backing up existing).
- Else use the default at `C:\AQuA2\cfg\parameters_for_batch.csv`.
- No auto-detect, no prompts.

Plan summary still parses the active CSV and displays key values
(frameRate, spatialRes, maxSize, thrARScl, sourceSensitivity, smoXY, smoT)
for sanity-check before pressing Y. Read-only and safe.

### Stale failure counting

Detection and CFU snapshot `_ERROR.txt` count at phase start. Displayed
"fail N" counter shows only NEW failures from this run.

### Phase markers dual-written

- Top-level `_logs/PHASE_*.txt`: updated by latest run, used for resume
  detection across runs
- Per-run `_logs/run_X/PHASE_*.txt`: historical record per run

### Phase 1 (Split) move warning

Plan summary explicitly warns that Split MOVES files (originals removed
from InputTIFFs). Copy InputTIFFs to a backup location if originals must
be preserved.

## Recovery scenarios

### A worker stalls and auto-skip kicks in

What you'll see in the console:

```
[STALL WARN] lane02 (PID 7564) has made no progress for 15.1 min
  Last lines from lane02 log:
    SE 437
    Feature extraction...
    (no further output)
...
(45 min later)
[STALL AUTO-SKIP] lane02 stalled for 60.2 min -- moving stuck file aside and restarting
Stall auto-skip: lane02 stuck on <stem>.tif
Killing stuck worker PID 7564...
Moved <stem>.tif -> <lane>\_stalled\
Restarted worker on lane02: new PID 22184
```

At end of run, yellow STALLED FILES banner lists all quarantined files.

What to do later:
1. Look at `<runAuditDir>/stall_log.txt` for the full record
2. Inspect `<lane>/_stalled/<stem>.tif` - the quarantined file
3. Read the lane log around the stall point: `Get-Content <PreCFU>/_lane_logs/lane02.log -Tail 100`
4. Try the file alone with relaxed parameters, mark as known-bad, or
   move back to the lane folder and re-run

### A worker hard-fails (not stall)

Worker writes `_ERROR.txt`, continues to next file. Error captured in:
- `<PreCFU>/<stem>/_failures/<stem>_ERROR.txt` (original)
- `<runAuditDir>/failures/detection/<stem>_ERROR.txt` (audit copy)
- `<runAuditDir>/failures_summary_detection.md` (consolidated summary)

### Mid-run cancel

```
Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Stop-Process -Force
```

Orchestrator detects zero workers and exits cleanly. Partial results
preserved. Re-run with phase toggles to resume.

## Common invocations

### Full pipeline, no upload
```
.\Run-Pipeline.ps1 -InputTIFFs E:\raw -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06
```

### Full pipeline + S3 upload (Consolidate auto-triggers)
```
.\Run-Pipeline.ps1 -InputTIFFs E:\raw -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06 -Upload $true -S3Prefix s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/foxp1_full_2026_06/
```

### Resume CFU on already-detected outputs
```
.\Run-Pipeline.ps1 -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06 -Split $false -Detect $false -CFU $true
```

### Consolidate-only (build for_upload/ for inspection)
```
.\Run-Pipeline.ps1 -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06 -Split $false -Detect $false -CFU $false -Consolidate $true
```

### Upload already-consolidated project
```
.\Run-Pipeline.ps1 -OutputRoot D:\analyses -ProjectName foxp1_full_2026_06 -Split $false -Detect $false -CFU $false -Upload $true -S3Prefix s3://...
```

## Migration from v0.6.x

- `-ProjectName` is now REQUIRED.
- Existing outputs without ProjectName nesting won't auto-resume. To
  continue using a v0.6.x output at `C:\smoke\out\...`, pass
  `-OutputRoot C:\smoke -ProjectName out` (project name "out" produces
  the same nesting as before).
- Disk overhead from Consolidate is ~small for .mat files (copied) and
  effectively zero for TIFFs (hardlinked). Expect ~few GB extra for
  typical project.
