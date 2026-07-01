# Changelog

Version history for the AQuA2 lane pipeline. Versions are git tags; the
orchestrator (`powershell/Run-Pipeline.ps1`) also carries an inline changelog in
its `.DESCRIPTION` block. Dates are when known.

The compiled workers (`aqua_lane.exe`, `cfu_lane.exe`) are versioned separately
by their `mcc` build date (see the `LANE_VERSION` / banner string printed at the
top of each worker's log, and the `_AQuA2.mat` `opts` struct for per-recording
parameters).

---

## Unreleased

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
