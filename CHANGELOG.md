# Changelog

Version history for the AQuA2 lane pipeline. Versions are git tags; the
orchestrator (`powershell/Run-Pipeline.ps1`) also carries an inline changelog in
its `.DESCRIPTION` block. Dates are when known.

The compiled workers (`aqua_lane.exe`, `cfu_lane.exe`) are versioned separately
by their `mcc` build date (see the `LANE_VERSION` / banner string printed at the
top of each worker's log, and the `_AQuA2.mat` `opts` struct for per-recording
parameters).

---

## Unreleased — targeting v0.10.0

Optional **Phase 0 input prep** (start from LIF, or trim TIFFs) folded into the
orchestrator, plus **MP4 movie generation** in Consolidate, a named-**preset**
library with a **GUI launcher**, and a dependency **provisioner**. Merged to
`main` (available via `git pull`); **not tagged yet** — holding the tag until a
full instance run exercises Phase 0 extraction and the movie step end-to-end.

- **Phase 0 — start from LIF files, or trim existing TIFFs (optional).**
  `Run-Pipeline.ps1` can now run the LIF→TIFF extract/trim step itself (a headless
  Bio-Formats port of `LIF_Extract_and_Trim.ijm`) before Split, or trim/Hz-label an
  existing TIFF folder — then feed the result into Split→Detect→CFU→Consolidate.
  Fully backward-compatible: with no `-LIFSource` and no `-TrimMode`, runs start from
  TIFFs exactly as before. New params: `-LIFSource`, `-DetectOn`, `-SaveUntrimmed`,
  `-TrimMode`/`-TrimStartSec`/`-TrimAmount`/`-TrimUnit`, `-HzLabel`/`-HzDecimals`,
  `-RatePolicy`, `-SkipTileScans`, `-ExtractDryRun`, `-FijiExe`. Headless decode
  validated on the instance (real 9-series LIF, correct measured Hz + trim). Engine:
  `fiji-macros/lif_extract_headless.py` (config via `LIF_EXTRACT_CONFIG` env var).
- **Movies — MP4 of each AQuA2 overlay, in Consolidate.** Each recording's
  `<stem>_AQuA2_Movie.tif` (a multi-frame TIFF, **not** a GIF) becomes
  `for_upload\Movies\<stem>_AQuA2_Movie.mp4`. ffmpeg can't read multi-page TIFF
  (it decodes only the first page), so the path is **Fiji (stack → lossless PNG AVI) →
  ffmpeg (AVI → H.264 MP4)**. Quality is high by default and tunable:
  `-MovieCrf` (default **17**, visually transparent; lower = higher fidelity),
  `-MovieLossless` (qp 0 + yuv444p, mathematically lossless — larger, needs VLC to
  play), `-MovieAviCompression` (PNG|Uncompressed|JPEG, default PNG), `-MovieFps`
  (default 20), `-SkipMovies`, `-FfmpegExe`. **Optional + non-fatal**: if Fiji or
  ffmpeg is missing (or there are no movies), the step warns and skips; the run still
  succeeds. Slow — reads ~900 MB TIFFs sequentially. Engine:
  `fiji-macros/movies_to_avi.py`. Validated end-to-end on the instance (893 MB /
  1200-frame movie → 3.8 MB crf-17 MP4, frame count preserved).
- **Consolidate `input_TIFFs/` mirrors the original LIF tree.** When a run extracted
  from LIF, `for_upload\input_TIFFs\` reproduces the source subfolder structure and
  includes **both** the UNTRIMMED and TRIMMED sets (hardlinked). TIFF-start runs keep
  the flat layout.
- **Fixed: headless Fiji launch dropped `--run`.** `Start-Process` with a single
  joined-string `ArgumentList` (`"--headless --run <path>"`) made the new Fiji
  (Jaunch) launcher reject `--run` ("Ignoring invalid argument: --run") so the engine
  never ran. Both launch sites (Phase 0 extract, Movies) now pass `ArgumentList` as an
  **array** (`'--headless','--run',$engine`). See Pitfalls §17.
- **Default `-OutputRoot`** is now `<Documents>\AQuA2_runs` (was mandatory), to keep
  run data off the crowded `C:\` root.
- **Preset library + GUI launcher.** Save a named detection-parameter set with
  `Save-Preset.ps1 -Name <n>` → `cfg/presets/<n>.csv`, reuse with
  `-ParamPreset <n>`. `New-Run.ps1` is a WinForms GUI: Browse buttons for folders, an
  editable grid showing the **entire** `parameters_for_batch.csv`, trim controls, and
  a "Save as preset" button. The parameters actually used are always written into each
  run's output (`for_upload` → S3), so provenance travels with the data — committing a
  preset is optional (only to share it across instances).
- **Dependency provisioner.** `setup/Install-Dependencies.ps1` installs Fiji, ffmpeg,
  R + Rtools45, RStudio, and the R packages (`setup/install_deps.R`). Idempotent, has
  `-DryRun`. See [`02_INFRASTRUCTURE_SETUP.md`](docs/02_INFRASTRUCTURE_SETUP.md).

## v0.9.1 — 2026-07-14

Orchestrator correctness fixes, all surfaced by the first full-scale real-data run
(292 ASO TIFFs, 10 detection lanes / 7 CFU lanes on r7a.8xlarge). The run completed
cleanly (292/292 detection + CFU, 0 failures) — these fixes remove false alarms and
restore the auto-skip safety net; none were data-loss bugs in that run.

- **Per-lane stall detection no longer false-fires.**
  - *Detection:* the per-lane completion counter ([Run-Pipeline.ps1](powershell/Run-Pipeline.ps1))
    and `Find-StuckFile` enumerated lane TIFFs with `Get-ChildItem -Include *.tif,*.tiff`
    but **no `-Recurse`** — PowerShell's `-Include` matches nothing without `-Recurse`
    (or a `\*` path), so the per-lane count was pinned at 0 for every lane. The stall
    clock therefore never advanced and fired `[STALL WARN]` → `[ESCALATED]` →
    `[AUTO-SKIP]` on all lanes even while the run progressed normally; `Find-StuckFile`
    returned `$null`, making auto-skip a silent no-op (the safety net was non-functional).
    Added `-Recurse` at both sites (matching the completeness gate's proven idiom).
  - *CFU:* the CFU per-lane counter had a **different** root cause — it *did* use
    `-Recurse`, but CFU lanes are directory **junctions** (see `Build-CFU-Lanes.ps1`) and
    `-Recurse` does not reliably descend through junction reparse points (behavior varies
    by PowerShell version), so its count was also pinned at 0. Now it lists each junction
    as a top-level child dir and reads the `_AQuA2.mat` through **direct access**, which
    resolves the junction reliably. This matters more on the CFU side because the CFU
    auto-skip is destructive (kills the worker, no auto-restart) — with the counter fixed,
    it can only fire on a genuine hang.
- **Splitter can now recurse into nested input subfolders.** `Split-IntoLanes.ps1` gains
  an opt-in `-Recurse` with a **hard duplicate-filename collision guard** (lane files are
  addressed by filename alone, so same-named files in different subfolders would collide —
  the script now errors and lists them instead of silently dropping). `Run-Pipeline.ps1`
  gains `-RecurseInput`, which drives **both** the splitter and the pre-flight input count
  so they always agree. Previously the pre-flight always recursed while Split took top-level
  only, so nested inputs reported N files but Split moved 0 and Detection then died mid-run.
- **Cosmetic:** the post-CFU "Junctions ready: N lane folders" tally filtered with `^lane`,
  which never matches `cfu_laneNN`, so it always printed 0. Fixed to `^cfu_lane`.

---

## v0.9.0 — 2026-07-01

New Fiji input-prep tooling. (The orchestrator `Run-Pipeline.ps1` is unchanged since v0.8.5.)

- **New consolidated Fiji tool `fiji-macros/LIF_Extract_and_Trim.ijm`.** One interactive
  macro that takes raw acquisitions to detection-ready TIFFs: `.lif` (or existing TIFFs) →
  raw (UNTRIMMED) + trimmed copies, with the **measured acquisition rate appended to every
  output filename** (`_1.55Hz`, end-anchored) so the downstream R parser can read it. Folds
  in `LIF_Extractor.ijm` (recurse/resume/rate-policy/TileScan) and `TrimTIF_Frames.ijm`
  (keep-final-N, now one of several flexible trim modes), and adds a dry-run preflight +
  confirmation. **Pixel data is never modified** (Hz lives only in the filename — the
  outputs must feed AQuA2 bit-exact); visible timestamp burning stays in the separate,
  post-detection `AQUA2_Movie_Timestamp.ijm`.
  - **Validated on a real 31-series LIF** (assembloid calcium data). Hz + trim math verified
    against real Bio-Formats metadata across all series: filenames labelled correctly
    (`_5.00Hz` and `_18.06Hz` — the file has mixed rates), trim windows exact (60.0 s kept at
    both rates). Via the Bio-Formats **API** (headless), a full series was extracted and the
    TIFF round-trip confirmed **bit-exact (max pixel diff 0 across all 601 frames)** with the
    frame interval preserved — i.e. raw data is not altered. Surfaced and **hardened a latent
    edge case** (also in the old v3.0 extractor): a recording shorter than the trim-start
    computed an invalid `Make Substack` range; the trimmed copy is now skipped with
    `[WARN-LEN]`.
  - Caveat: the interactive Bio-Formats *importer plugin* cannot run **headless** (a
    JVM `VerifyError` in its dialog code, reproduced on three Fiji builds incl. a fresh
    install — a headless-only limitation, not a corrupt install); it works normally in the
    Fiji GUI, which is how the macro is used and how v3.0 runs in production. `LIF_Extractor.ijm`
    and `TrimTIF_Frames.ijm` are marked **superseded** but retained as proven fallbacks pending
    a user GUI confirmation run; they'll be removed in a follow-up. `docs/08` Step 1 and
    `fiji-macros/README.md` point at the new tool.

## v0.8.5 — 2026-07-01

Docs only (no code/behavior change):
- **AWS pricing reconciled to broad ranges.** `docs/08`'s outlier figures (r7a.8xlarge
  "$1.70", r7a.24xlarge "$5") now match the rest of the docs; operator-facing "pick an
  instance" tables (`docs/08`, `docs/09`) use rounded broad values (~$0.5/$1/$2/$3/$6/hr).
  `docs/03` is now the single cost reference with a **≈ $0.06/vCPU-hr** heuristic and a link
  to the AWS pricing calculator; other docs defer to it. Verify current rates before a run.
- Fixed a stray "CFU is memory-bound" in `docs/08`'s cost table (now I/O-bound, consistent
  with `docs/02`/`docs/03`).
- README states the intended update model explicitly: the AMI ships this repo cloned, and the
  instance `git pull`s it before each run (you push from elsewhere; the instance only pulls).

## v0.8.4 — 2026-07-01

- **`Launch-CFU-Lanes.ps1`**: the default `-LogDir` now derives from `-LaneRoot`
  (`<LaneRoot>\_logs`) instead of a fixed `C:\...\CFU_lanes\_logs`, so standalone CFU
  runs on distinct lane roots no longer overwrite each other's logs — resolving the
  `docs/06` Pitfall #7 footgun for standalone use (the orchestrator already passed
  `-LogDir` explicitly). `docs/06` and `docs/08` updated accordingly.
- Consistency sweep: folded the former `Unreleased` docs block into the v0.8.3 entry
  below (it shipped in the v0.8.3 tag), and verified no remaining version/path/marker
  drift, broken internal links, tabs, or trailing whitespace across the repo.

## v0.8.3 — 2026-07-01

Diagnosability: make it fast to pinpoint *why* a run misbehaved.

- **New read-only triage script `powershell/Get-PipelineStatus.ps1`.** One command →
  counts + mismatches (inputs vs detection vs CFU), failures grouped by error signature,
  stalled/quarantined files, lanes that died at startup (`.err` with content), orphaned
  worker processes, free disk, phase-marker consistency (incl. `PHASE_detect_INCOMPLETE`),
  and the nCFU distribution. Works on any project, including finished/archived runs. Exits
  0 clean / 1 if any issue category triggered.
- **Failures grouped by normalized error signature** in `failures_summary_<phase>.md`, so
  "12 files: Index exceeds array bounds" (systemic) is distinguishable from one-offs.
- **End-of-run "ISSUES DETECTED" block** (console + `RUN_SUMMARY.md`) covering count
  mismatches, per-file failures, stalls, startup `.err` files, and detection incompleteness
  — problems are stated explicitly instead of inferred from raw counts. Points at
  `Get-PipelineStatus.ps1` for full triage.
- **Config sanity pre-flight** on `parameters_for_batch.csv` (frameRate plausible, maxSize /
  spatialRes present) to catch misconfiguration before a long run.

**Documentation consistency (same release):**
- `docs/02`: pinned the MATLAB Runtime / compiler version to **R2026a (Update 2)** — the
  version the current `.exe`s were built with — instead of the stale "R2024a+"; added a
  pricing disclaimer matching `docs/08`.
- Reconciled the **CFU bottleneck** description: `docs/08` called it "memory-bound" while
  `docs/03`/`docs/02` call it disk/throughput-bound. Harmonized toward the authoritative
  `docs/03` framing (loads/rewrites multi-GB `.mat` files → EBS-throughput bound; per-lane
  RAM scales with result size), keeping the "run fewer lanes" guidance and the large-result
  OOM caveat.
- Removed stale "v0.8 work-stealing" references in `docs/09` (never shipped); pointed the
  recompile examples at the real `ftsGlo2` fix / CFU-threshold changes.
- Added orchestrator cross-references to `docs/06` pitfalls #1 (stall auto-skip) and #7
  (orchestrator passes `-LogDir`, so the log-collision pitfall is standalone-only).

## v0.8.2 — 2026-07-01

Observability + a small correctness follow-up to the completeness gate. Added CI.

**Orchestrator (`Run-Pipeline.ps1`):**
- An **incomplete detection no longer writes a `PHASE_detect_COMPLETE` marker** — it
  writes `PHASE_detect_INCOMPLETE.txt` and clears any stale COMPLETE marker. Previously
  a partial run left a COMPLETE marker, so the next run's plan summary showed it as
  "PREVIOUSLY COMPLETED."
- **Consolidate prints periodic progress** (every 100 stems) so a large run isn't
  silent for minutes during hardlinking.

**Scripts:**
- `Launch-Lanes-Exe.ps1` now reports **actual free disk on C:** instead of the hardcoded
  "you have ~1 TB" claim.

**CI:**
- Added `.github/workflows/ci.yml`: parses every `.ps1` with the PowerShell AST parser
  (fails on syntax errors — the check that can't run on a non-Windows dev machine) and
  runs PSScriptAnalyzer informationally. Guards the orchestration layer on every push/PR.

## v0.8.1 — 2026-06-29

Orchestrator correctness fixes and a documentation pass. No new phases.

**Orchestrator (`Run-Pipeline.ps1`):**
- **Completeness gate now covers Consolidate and Upload.** v0.8.0 refused CFU on
  an incomplete detection but still consolidated (and could upload) the partial
  `PreCFU` set, re-opening the "partial looks complete" hole. Both phases now
  no-op with a clear error when detection did not finish for all real inputs in
  this run.
- **CFU stall auto-skip message corrected.** It kills the worker and writes a
  `_STALLED_` marker (no file move, no auto-restart — CFU lanes are junctions).
  The previous message described detection behavior.
- **Upload reports the actual number of files synced** (counted from the real
  `aws s3 sync` output via `Tee-Object`) instead of echoing the dry-run
  prediction.
- **Post-CFU completeness check** warns prominently when `_res_cfu.mat` count is
  below the `_AQuA2.mat` input count (detection had a bounded auto-relaunch for
  this; CFU previously exited silently when a worker died).
- `RUN_SUMMARY.md` phase table now lists the Consolidate phase, and the stale
  `.DESCRIPTION` default-phase comments were corrected (Consolidate defaults ON).

**Docs / repo:**
- Added this `CHANGELOG.md` and a top-level `LICENSE` (MIT) — the README
  asserted MIT and linked to a file that did not exist.
- Bumped version strings across `README.md`, `docs/04`, and `docs/09` from
  v0.7.4 to v0.8.1; documented the completeness gate.
- Fixed the `POST` vs `PostCFU` naming error in the docs: the live CFU
  intermediate is `<projectRoot>\POST\`; only the consolidated copy is
  `for_upload\PostCFU\`. (One doc cleanup command would have failed to delete the
  real intermediate.)
- Corrected stale audit filenames in docs (`PHASE_<name>_COMPLETE.txt`,
  `per_file_status_detection.csv`) and CFU log path (`CFU_lanes\_logs\`).
- Removed the nonexistent `aqua_cmd_batch_lane.m` from the README file list.
- Folded `docs/08_OPERATIONS_PLAYBOOK_v07_supplement.md` into this changelog and
  `docs/08`; the standalone supplement (which carried a "merge me later" TODO)
  was removed.
- Generalized lab-internal anecdotes in the operations docs.

**Known issue flagged (not yet fixed here):** `matlab/aqua_lane.m` mislabels
global channel-2 features as channel 1 (`ftsGlo2.channel = 1` should be `2`).
Affects dual-channel runs with `detectGlo` ON; requires an `mcc` recompile to
take effect.

## v0.8.0 — 2026-06-15

- **Detection-completeness gate (correctness).** Detection no longer reports
  COMPLETE just because all workers exited. It compares real-input count
  (excluding macOS `._` AppleDouble sidecars) to `_AQuA2.mat` output count,
  auto-relaunches lane workers if outputs < inputs (bounded by
  `-MaxDetectRelaunch`, default 3; completed files skipped on relaunch), and
  refuses to proceed to CFU if still short. Root cause: the `DGvsCA_C4and8858`
  incident, where a `._` stub killed each lane and the run reported fail 0 /
  COMPLETE at 50%.
- **AppleDouble (`._*`) files excluded everywhere** — lane TIFF count,
  completeness check, `input_TIFFs` consolidation. `Split-IntoLanes.ps1` and
  `aqua_lane.m` also drop them at the source.
- **Consolidate defaults ON** (`-Consolidate $true`) so every run leaves a clean
  `for_upload/` with `parameters_for_batch_USED.csv` and `RUN_SUMMARY.md` copied
  in for provenance.
- **New `-Cleanup` switch** (default OFF, destructive): after a VERIFIED
  consolidate (counts must match sources), removes intermediates (`lanes/`,
  `CFU_lanes/`, `PreCFU/`, `POST/`) using junction-aware deletion and renames
  `for_upload/` → `<ProjectName>_AQuA2/`.

## v0.7.4 — June 2026

- **CRITICAL fix:** the per-lane completion counter checked the wrong path
  (`PreCFU/<stem>/...` instead of the worker's actual
  `PreCFU/laneNN_results/<stem>_AQuA2.mat`), so the counter was always 0 and
  stall detection fired false positives — and at 60 min would have quarantined
  completed files and restarted exited workers. Fixed with a recursive
  name-match against real output paths.
- **Three-stage stall thresholds:** WARN at `-StallWarnMin` (default 30),
  ESCALATE at `-StallEscalateMin` (default 45, red banner), AUTO-SKIP at
  `-StallAutoSkipMin` (default 60). (Earlier v0.7 used a single 15-min warn.)

## v0.7.3 — June 2026

- `Show-CSVValues` parses the real multi-column `parameters_for_batch.csv`
  (`Import-Csv`); `detectGlo` gets a prominent ON/OFF marker in the plan summary.

## v0.7.2 — June 2026

- PreCFU consolidation gathers ALL accessory files per stem via a `<stem>*`
  filter (CSVs, curves, movie, `_Glo_*`).

## v0.7.1 — June 2026

- PreCFU consolidation uses per-stem subfolders and hardlinks (not copies).

## v0.7.0 — June 2026

- **`-ProjectName` now REQUIRED.** Project dir = `<OutputRoot>/<ProjectName>/`;
  all data + audit live there.
- **`-CFU` defaults ON** — standard invocation runs Split + Detect + CFU.
- **New Consolidate phase** building `for_upload/` (`input_TIFFs/`, `PreCFU/`,
  `PostCFU/`); Upload phase syncs it to S3.
- **Per-run audit subfolder** `_logs/run_<timestamp>[_<RunName>]/` with the full
  manifest, summary, per-file status, stall log, and failure copies.
- **Stall detection** introduced; phase-complete markers dual-written
  (top-level for resume, per-run for history); Split warns that it MOVES files.
- `ConfigCSV` resolution simplified to `-ConfigCSV` or the default (no
  auto-detect / prompts).

## v0.6.3 and earlier

See git history (`git log`, tags `v0.1`–`v0.6.3`). The pre-v0.7 workflow ran the
individual scripts by hand: `Split-IntoLanes.ps1` → `Launch-Lanes-Exe.ps1` →
`Build-CFU-Lanes.ps1` → `Launch-CFU-Lanes.ps1` → `Consolidate-Template.ps1` →
`aws s3 sync`. These scripts still exist for debugging (see `docs/04` Appendix Z
and `docs/08` Option B).

---

## Migration notes

### v0.7 → v0.8

- **Defaults changed:** Consolidate now defaults ON. A routine run leaves a clean
  `for_upload/`; pass `-Consolidate $false` to skip it.
- **The completeness gate can now block phases.** If detection finishes short of
  the real input count, CFU / Consolidate / Upload refuse to run (v0.8.0 blocked
  CFU; v0.8.1 also blocks Consolidate and Upload). Re-run `-Detect` after fixing
  the offending input(s).
- macOS `._` AppleDouble sidecars are excluded everywhere; if you previously
  worked around them manually, that is no longer needed.

### v0.6.x → v0.7

- **`-ProjectName` is now REQUIRED.** Outputs without `<ProjectName>` nesting
  won't auto-resume. To continue using a v0.6.x output at `C:\smoke\out\...`,
  pass `-OutputRoot C:\smoke -ProjectName out` (project name `out` reproduces the
  old nesting).
- Disk overhead from Consolidate is small: `.mat` files are copied/hardlinked,
  TIFFs are hardlinked (effectively zero extra disk).
