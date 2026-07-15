# 06 — Pitfalls and Recovery

Issues encountered while running this pipeline on real data, with diagnostics and fixes. If something breaks during a future run, search here first.

These are documented in (roughly) decreasing severity. The first half are setup/config issues that can break a run silently; the back half are operational gotchas with obvious symptoms.

---

## 1. `maxSize` parameter mixing across files

**Symptom:** event counts and CFU counts differ unexpectedly across files in the "same" run.

**Cause:** AQuA2's `maxSize` parameter caps active-region size. At `maxSize=inf` (default), hyperactive recordings can hang in spatial segmentation. A common reflex is to re-run the failing files at lower `maxSize` (e.g., 2000) while leaving others at the original setting. This produces a dataset with **mixed parameters across files** — event sizes are no longer directly comparable.

**Fix:**
- **Pick a uniform value** before launching. `maxSize=50000` is a reasonable starting point: high enough that most files don't hit it, low enough to converge on the majority of hyperactive cases.
- If a few files still hang at the uniform value, **isolate and exclude** them rather than re-running at different `maxSize`. A single excluded recording at large N is usually statistically negligible; mixed parameters across the dataset is a real confound.
- If you have to use mixed parameters for legitimate reasons (e.g., trying to recover an otherwise unusable recording), **document explicitly** which files used which value, in a README that travels with the data.

**Related:** the probe protocol (Sizing Guide Part C) catches per-file RAM spikes early so you can address pathological files before the full run.

**Orchestrator note (v0.7+):** `Run-Pipeline.ps1`'s three-stage stall detection auto-quarantines a hyperactive file that hangs a lane (moves it to `_stalled\` and restarts the lane), and the end-of-run banner lists every stalled file. That mitigates the "one bad file hangs the run" case without mixing parameters — you still decide afterward whether to exclude it or re-run it solo at a lower `maxSize`.

---

## 2. `Start-Process -WindowStyle Hidden` mangles `matlab -batch` arguments

**Symptom:** MATLAB launched via `Start-Process -WindowStyle Hidden` runs but with corrupted argument strings — wrong files processed, missing parameters, no errors logged.

**Cause:** PowerShell's `Start-Process -WindowStyle Hidden` silently mishandles quote-containing argument strings when passed to MATLAB's `-batch` mode. Quotes get stripped or misescaped.

**Fix:** wrap the MATLAB invocation in `cmd /c` instead:

```powershell
$cmd = "matlab -batch ""my_function('arg1', 'arg2')"" > $log 2>&1"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -WindowStyle Hidden
```

The `cmd /c` wrapper handles quote-escaping correctly.

**Important scope:** this bug **specifically affects `matlab -batch`**, not arbitrary executables. The compiled `aqua_lane.exe` and `cfu_lane.exe` workers take their arguments cleanly — `Start-Process -WindowStyle Hidden -ArgumentList @("\"$pin\"", "\"$pout\"")` works fine for them. That's how the real `Launch-Lanes-Exe.ps1` and `Launch-CFU-Lanes.ps1` in this repo invoke the workers.

If you ever go back to raw `matlab -batch` (e.g., for a debugging session before compilation), remember the `cmd /c` wrap. For compiled exes, no wrapping needed.

---

## 3. Lane crash from a single bad TIFF (uncaught error)

**Symptom:** a lane process exits prematurely with all its remaining files unprocessed. Sometimes multiple lanes fail this way silently. No obvious error in the lane's log.

**Cause:** in earlier, non-guarded versions of the lane scripts, an uncaught error on any file in the lane's loop would kill the whole process. One bad file → all subsequent files in that lane lost.

**Fix:** wrap each file's processing in `try/catch`. On error, write `<stem>_ERROR.txt` to the output folder, log the message, and **continue with the next file**. This is built into the compiled `aqua_lane.exe` (banner reads `resume+per-file-guard=ON`) and `cfu_lane.exe`.

If you recompile from `.m` source, preserve the per-file `try/catch` — losing it reintroduces this failure mode.

**Recovery if you hit this in an older script version:** re-run the launcher. Resume guard skips completed files. Lanes that lost mid-run get a clean restart from where they left off.

---

## 4. AQuA2 CSV parameters mapped positionally, not by name

**Symptom:** parameters from `parameters_for_batch.csv` not applied as expected. Files processed with what looks like default values.

**Cause:** AQuA2's batch parameter reader walks the CSV by row index in some code paths, not by parameter-name lookup. If you add or reorder rows, downstream code may pick up the wrong values.

**Fix:**
- **Don't reorder rows** in `parameters_for_batch.csv` unless you're sure the consumer doesn't care
- Edit existing rows' value columns; don't insert new rows
- After editing, verify the values were read correctly by checking the log of a single-file probe run

The compiled `aqua_lane.exe` reads parameters by name from the CSV (more robust), so this is mostly a legacy/raw-script concern. But if you ever use raw `aqua_cmd_batch.m`, be aware.

---

## 5. R's `hdf5r` package is broken for MATLAB v7.3 files

**Symptom:** in R, reading AQuA2 `.mat` files via `hdf5r` returns empty data, NULLs, or crashes. Cell arrays especially produce nonsense.

**Cause:** `hdf5r` version 1.3.12's `H5R` (HDF5 reference) dereferencing has bugs that affect HDF5 files written by MATLAB v7.3. The bug appears to be specific to how MATLAB lays out object references in cell arrays.

**Fix:** use **`rhdf5`** from Bioconductor instead. It handles MATLAB v7.3 correctly.

```r
if (!require("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rhdf5")

library(rhdf5)
h <- H5Fopen("file_AQuA2.mat")
data <- h5read(h, "/some/field")
H5Fclose(h)
```

For cell-array dereferencing: `H5Rdereference(ref, h5loc)`. See [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md) Part C for the full pattern.

---

## 6. Cell-array orientation detection in R

**Symptom:** `cfuInfo1` reads OK on some files but returns garbage on others. CFU counts are wrong. `cfuGroupInfo` produces nonsense group assignments.

**Cause:** MATLAB cell arrays stored as HDF5 don't carry unambiguous orientation metadata. A 1×N cell of scalar references can structurally resemble a single scalar with a coincidental reference. Cell-array readers can guess wrong.

**Fix:** verify orientation using the **`cfuInfo1` ID convention** — real entries have IDs that are consecutive integers `1..Ncells`:

```r
is_real_cell_array <- all(sapply(seq_along(parsed), function(i) parsed[[i]]$id == i))
```

If `is_real_cell_array` is TRUE, you got the right orientation. If FALSE, swap and try again.

**Also:** route `cfuGroupInfo` through the **same cell-array reader** as `cfuInfo1`/`cfuInfo2`. Treating it as a flat list returns wrong group structure.

---

## 7. The CFU launcher's default log path is the same every run

**Symptom:** running a new CFU batch overwrites logs from a previous batch. Lane logs `_logs\cfu_lane01.log` through `_logs\cfu_laneNN.log` no longer reflect what you think they do.

**Cause (older script copies):** early versions hardcoded the `-LogDir` **default** to `C:\Users\Administrator\Documents\CFU_lanes\_logs\` regardless of the `-LaneRoot` you passed, so without an explicit `-LogDir`, sequential runs overwrote the earlier batch's logs at the same lane numbers. Current scripts fix this (see **Fixed** below).

**Fix (either):**

*Option A — pass `-LogDir` explicitly each run:*
```powershell
.\Launch-CFU-Lanes.ps1 -LaneRoot ... -Post ... -LogDir "...\CFU_lanes\_logs_<dataset-name>"
```

*Option B — rename old logs before launching a new batch:*
```powershell
Rename-Item C:\Users\Administrator\Documents\CFU_lanes\_logs C:\Users\Administrator\Documents\CFU_lanes\_logs_<previous-dataset>
```

The Option A pattern is cleaner if you remember it. Option B is a safety net if you don't.

**Orchestrator note (v0.7+):** `Run-Pipeline.ps1` always passes `-LogDir` explicitly (`<projectRoot>\CFU_lanes\_logs`), so per-project runs have always had isolated logs — this pitfall only ever affected standalone `Launch-CFU-Lanes.ps1` calls.

**Fixed:** `Launch-CFU-Lanes.ps1` now defaults `-LogDir` to `<LaneRoot>\_logs`, so each standalone CFU batch on a distinct `-LaneRoot` writes to its own log location automatically. The only remaining way to collide is to reuse the *same* `-LaneRoot` for two batches — in that case still pass `-LogDir` explicitly (Option A) or rename the old logs first (Option B).

---

## 8. Folder name collisions on `Move-Item`

**Symptom:** trying to merge two result trees (e.g., main run + redistribution from stuck-lane recovery) fails with "Cannot create a file when that file already exists" because both trees have folders named `lane01_results`, `lane02_results`, etc.

**Cause:** both detection runs use lane-numbered output folders. The numbers collide.

**Fix:** don't move the **lane wrappers** (`laneNN_results`) — those collide. Move the **per-recording subfolders** (`<stem>_results`) instead, which are uniquely named by recording stem.

If the source tree doesn't have stem-named subfolders (i.e., files are directly inside `laneNN_results`), promote them to stem-named folders during the move:

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
```

This creates uniquely-named `<stem>_results/` folders that can't collide. CFU's recursive glob handles either layout fine.

---

## 9. AWS `s3 sync` "instant return" — false alarm vs. real failure

**Symptom:** `aws s3 sync` returns to the prompt instantly. Did it succeed or fail?

**Cause:** `aws s3 sync` returns instantly when there's nothing to do (everything already synced). This **looks identical** to the failure mode where it silently doesn't transfer anything (e.g., due to a syntax issue, missing source path, or auth problem).

**Fix:** always **verify by counting after**, never trust the fast return alone:
```powershell
aws s3 ls "<s3-path>" --recursive --summarize | Select-Object -Last 2
(aws s3 ls "<s3-path>" --recursive | Select-String '_AQuA2\.mat').Count
```
- If the count matches your local count → it was already synced (success)
- If the count is 0 or much lower than local → it didn't transfer; investigate and re-run

**Bonus tip:** use **single-line commands**, no backtick line-continuations. Backticks have caused syncs to silently misparse and no-op in some PowerShell environments.

---

## 10. PowerShell scripts with non-ASCII characters

**Symptom:** PowerShell fails to parse a script with cryptic syntax errors. The script looks fine when you open it.

**Cause:** the script contains Unicode characters — em-dash (`—`), smart quotes (`"`, `"`), non-breaking spaces — usually introduced when text was copied from rich-text sources, Mac apps, or websites. PowerShell handles these inconsistently across versions.

**Fix:** strip non-ASCII before running:
```powershell
(Get-Content C:\path\to\script.ps1 -Raw) -replace '[^\x00-\x7F]','-' | Set-Content C:\path\to\script.ps1 -Encoding ASCII
```

This replaces any non-ASCII character with a hyphen. Functional content (logic, commands, paths) is unaffected since they're ASCII; only the offending Unicode glyphs change.

Always save PowerShell scripts as **ASCII or UTF-8 without BOM**, not as Mac-Roman or UTF-16.

---

## 11. PowerShell prompt pasted into a command

**Symptom:** running a command produces "positional parameter not found" or similar. The command looked correct when you pasted it.

**Cause:** copying commands from session transcripts (or any output that shows the prompt) sometimes includes the `PS C:\...>` prompt prefix. Pasting the prompt at the start of the line confuses PowerShell — it tries to interpret `PS` as a cmdlet name.

**Fix:** when copying from transcripts or documentation, **paste into a plain text editor first**, strip the prompt prefix, then paste into PowerShell. Or use a triple-clicked single-line selection to avoid grabbing the prompt.

---

## 12. Stale PIDs after killing and relaunching

**Symptom:** `Stop-Process -Id <PID>` fails with "Cannot find a process" even though processes are visible in Task Manager.

**Cause:** after `Stop-Process` and a relaunch, new processes have **new PIDs**. A PID you noted earlier is now stale.

**Fix:** kill by **name**, not by PID:
```powershell
Stop-Process -Name aqua_lane -Force
Stop-Process -Name cfu_lane -Force
```

PowerShell will print "Cannot find a process with the name 'aqua_lane'" if none are running — that's the **success** signal (no workers alive), not a failure. To confirm:
```powershell
Get-Process aqua_lane -ErrorAction SilentlyContinue | Measure-Object | Select -Expand Count   # want 0
```

---

## 13. `_failures/` folder appears empty but exists

**Symptom:** after CFU completion, a `_failures/` folder exists under POST, even though there were no errors.

**Cause:** the compiled `cfu_lane.exe` pre-creates `_failures/` as a place to put `_ERROR.txt` files if any occur. If no files fail, the folder stays empty.

**Fix:** not a bug; ignore the empty folder. Check whether it has content:
```powershell
Get-ChildItem "<POST-dir>\_failures" -Force -ErrorAction SilentlyContinue | Measure-Object | Select -Expand Count
```
- 0 → no failures, ignore
- >0 → read the `_ERROR.txt` files to diagnose

---

## 14. Filename Hz encoding: nominal vs. measured

**Symptom:** event times computed from frame indices and `frameRate` are slightly off — by a few percent — from what acquisition software reports.

**Cause:** some filename conventions include both a **nominal** acquisition rate (mid-name, e.g., `20Hz`) and an **actual measured** rate (end-anchored, e.g., `19.23Hz`). The actual rate is what the microscope achieved; the nominal is what was requested. They differ slightly due to acquisition overhead.

**Fix:**
- **For temporal calculations:** parse the end-anchored measured Hz from the filename and use `1 / measured_Hz` as the per-file frame interval.
- **For the AQuA2 parameter CSV:** use the **nominal** value (`frameRate = 1/nominal_Hz`) for cross-dataset consistency, since detection is fairly insensitive to small Hz differences. AQuA2 doesn't need exact temporal precision.
- Be **explicit and consistent** about which you're using. Pick one and document in the run README.

---

## 15. Source TIFF deletion is irreversible

**Symptom:** after deleting local source TIFFs to free disk space, you realize you need to re-run detection (changed parameters, missing files, etc.). Re-downloading from S3 takes hours.

**Cause:** there's no undo for local file deletion. Once the TIFFs are gone, re-detection requires re-downloading from S3.

**Fix:** **only delete source TIFFs when**:
1. Detection has completed and outputs are verified
2. CFU has completed
3. Both PRE and POST folders are backed up to S3 (verified by count)
4. You're confident you won't re-run detection on these files

Even then, consider keeping source TIFFs locally until you've completed R analysis. They're large, but cheap to keep relative to the inconvenience of re-downloading.

**Re-run-from-S3 procedure if you do need them back:**
```powershell
aws s3 sync "s3://<bucket>/CalciumImagingTIFFs/<dataset>/" "C:\Users\Administrator\Documents\<dataset>_source\"
```

---

## 16. Input TIFFs in nested subfolders (Split moves 0, run dies)

**Symptom:** the pre-flight reports the right input count, but Split creates lanes with no files and Detection then fails (or the completeness gate blocks the run). Your TIFFs are spread across subfolders (e.g. `ASOs\Inhibitory\...`, `ASOs\Excitatory\...`) rather than sitting directly in one folder.

**Cause:** by default `Split-IntoLanes.ps1` reads the **top level only** of `-InputTIFFs`. Before v0.9.1 the orchestrator's pre-flight counted *recursively* while Split did not, so nested inputs showed N files at pre-flight but Split moved 0. (v0.9.1 makes the two consistent, so the mismatch now surfaces immediately instead of mid-run.)

**Fix — pick one:**
- **Recurse (v0.9.1+):** pass `-RecurseInput` to `Run-Pipeline.ps1` (or `-Recurse` to `Split-IntoLanes.ps1` directly). This pulls TIFFs from all nested subfolders. **Filenames must be unique across subfolders** — lane files are addressed by name alone, so the splitter **hard-errors and lists any duplicates** rather than silently dropping them. If you have collisions, give them unique names first (e.g. prefix by group).
- **Flatten manually:** move/copy everything into one folder before launching, adding a group prefix to avoid name clashes:
  ```powershell
  Get-ChildItem C:\CalciumData\ASOs -Recurse -Filter *.tif | ForEach-Object {
      $grp = ($_.Directory.FullName -split '\\')[-2]   # e.g. Inhibitory / Excitatory
      Copy-Item $_.FullName (Join-Path C:\CalciumData\AllTIFFs ("{0}_{1}" -f $grp, $_.Name))
  }
  ```

**Default is unchanged:** if your inputs are already flat in one folder, you don't need either flag.

---

## 17. Headless Fiji: `--run` args must be an array, not a joined string

**Symptom:** a Phase 0 LIF/TIFF extraction or the Movies step produces no output; the Fiji console shows `[WARNING] Ignoring invalid argument: --run` and no engine log is written.

**Cause:** the current Fiji launcher (Jaunch) rejects `--run` when `Start-Process` is given a **single joined-string** `-ArgumentList`, e.g. `"--headless --run `"$engine`""`. The flag is dropped and the Jython engine never runs. (The earlier LIF validation used the `&` call operator, which passes each token separately and honored `--run`; the switch to `Start-Process` reintroduced the bug until it was caught on the instance.)

**Fix (already in v0.10):** both launch sites pass `-ArgumentList` as a PowerShell **array** — one token per element — which quotes each correctly:

```powershell
# BROKEN: launcher drops --run
Start-Process -FilePath $Fiji -ArgumentList "--headless --run `"$engine`"" -Wait ...
# CORRECT:
Start-Process -FilePath $Fiji -ArgumentList '--headless','--run',$engine -Wait ...
```

Also note: this launcher rejects `--console` too (`Ignoring invalid argument`), so it is intentionally omitted. If you write your own headless-Fiji helper, use the array form and verify the engine's own log reached its `TOTALS` line — Fiji can exit 0 even when the Jython script never ran or threw.

---

## 18. AQuA2 movies are multi-frame TIFF; ffmpeg reads only the first frame

**Symptom:** the old movie step found nothing (it searched for `*.gif`, which AQuA2 never writes), or a direct `ffmpeg -i <stem>_AQuA2_Movie.tif out.mp4` produced a **1-frame** video from an ~900 MB source.

**Cause:** the AQuA2 overlay movie is `<stem>_AQuA2_Movie.tif` — a **multi-page (multi-frame) TIFF stack**. ffmpeg's TIFF demuxer decodes only the **first page**, so it can't transcode these directly (verified: `ffprobe -count_frames` reports 1).

**Fix (v0.10 Movies step):** convert in two hops — **Fiji** opens the stack and writes a lossless PNG **AVI**, then **ffmpeg** transcodes the AVI (which it reads fully) to H.264 MP4. Frame counts are preserved end-to-end (1200-in → 1200-out on the validated sample). Non-fatal: skips with a warning if Fiji or ffmpeg is missing. See [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) §E.7.

**Related playback gotcha:** `-MovieLossless` encodes `yuv444p` (H.264 High 4:4:4), which **won't play in Windows Movies & TV / the built-in Media Player** — only VLC and similar. That's why the default is `-MovieCrf 17` with `yuv420p` (universally playable and visually indistinguishable for these overlays). Don't default to lossless just because "higher is better" — the movies would fail to open for most viewers.

---

## 19. Changed detection parameters don't re-apply to already-processed files

**Symptom:** you edit `parameters_for_batch.csv` (e.g. bump `maxSize`), re-run the pipeline on the same `-ProjectName`, and the outputs still reflect the **old** parameters for files that were processed before.

**Cause — this is by design, and it's the "AQuA2 references the original" behavior to be aware of.** The compiled worker reads the File1 column of the CSV *fresh from disk, per file* ([aqua_lane.m:81](../matlab/aqua_lane.m)) and **bakes the resulting `opts` struct into `<stem>_AQuA2.mat`** ([aqua_lane.m:390](../matlab/aqua_lane.m)). Its **resume guard skips any file that already has a `.mat`** ([aqua_lane.m:72-78](../matlab/aqua_lane.m)) — the whole point being cheap restarts. So on a re-run, completed files are skipped and retain the parameters baked in when they were first processed; only not-yet-done files pick up the new CSV.

**What is *not* affected:** a genuinely fresh run (new `-ProjectName` or empty output) always applies the current CSV to every file. And the "run without CFU, then add CFU later" resume re-runs **CFU/Consolidate**, not detection — so detection parameters aren't re-evaluated there and nothing is stale.

**Fix — to force new detection parameters onto an already-done file, pick one:**
- Delete that recording's `_results` folder (or its `_AQuA2.mat`) under `PreCFU\laneNN_results\`, then re-run with `-Detect $true -Split $false`. The resume guard no longer sees a `.mat`, so it reprocesses with the new params.
- Or run a fresh project with a different `-ProjectName` (cleanest when re-parameterizing the whole dataset).

**Verify what was actually applied** — read the baked `res.opts` back out of a finished `.mat` and diff it against the CSV the run used:

```powershell
Rscript <repo>\tools\verify_applied_params.R "<...>_AQuA2.mat" "<run>\parameters_for_batch_USED.csv"
```

`PASS` = the CSV's params are what's baked in. `FAIL` on `frameRate`/`maxSize`/`minSize`/`spatialRes` = that `.mat` predates your CSV change (resume-skipped). The script uses R's `hdf5r` (the `.mat` is HDF5/v7.3); if `hdf5r` chokes on a file, the same fields read from Python: `h5py.File(mat)['res/opts/maxSize'][()]`.

---

## General recovery principles

When something goes wrong:

1. **Don't kill running processes immediately.** Diagnose first (CPU climbing? disk activity?). The pipeline is designed to be safe to interrupt, but stopping mid-stride costs you the partial work.

2. **Resume guard is your friend.** Re-running any launcher skips completed files. You can interrupt and resume freely.

3. **Logs are your forensic record.** Lane logs (`_lane_logs\laneNN.log` and `.err`) capture what each lane did. Save them before any cleanup; they're tiny and invaluable for post-mortems.

4. **Verify after every major step.** Count files, check sizes, confirm S3 contents. The pipeline gives you partial-failure modes that don't always announce themselves clearly.

5. **A clean restart is often the right answer.** If you're chasing a weird intermittent issue, stop everything, snapshot the current state, restart cleanly. Faster than debugging.
