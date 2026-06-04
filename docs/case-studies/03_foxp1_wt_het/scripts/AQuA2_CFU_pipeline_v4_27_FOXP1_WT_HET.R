# ============================================================================
# AQuA2 CFU ANALYSIS PIPELINE (FOXP1 WT/HET organoids) -- v4.27
#   [forked from LindaDGvsCA v2.0; consolidates hCO release stages v1-v3 + perf]
# ----------------------------------------------------------------------------
# MASTER CHANGELOG
# v4.27 (2026-05-31)
#   Adapts the pipeline to the FOXP1 WT vs HET organoid dataset (Carol /
#   bireylab), a SIMPLER design than the assembloid build: one factor of
#   interest (genotype WT/HET) and one sampling-unit factor (Organoid; the
#   V1/V2/V3 views are pseudoreplicate fields of one organoid).  30 recordings
#   total (17 WT, 14 HET... see note) across 11 organoids (WT1-6, HET1-5).
#     - PATHS repointed at the FOXP1 lane outputs on the EC2 box:
#         csv_dir / companion_mat_dir = .../CarolDataPOGZ_lanes/   (PRE _AQuA2.mat
#                                       discovered recursively in lane##_results)
#         mat_dir   = .../CarolDataPOGZ_lanes/_CFU_POST/   (POST _res_cfu.mat)
#         out_dir   = .../CarolDataPOGZ_lanes/RESULTS_FOXP1/
#       Mac CalciumTesting test paths retained, commented.
#     - parse_stem REWRITTEN for the FOXP1 convention FOXP1<GENO><ORG>_<VIEW>_
#         <rate>Hz (e.g. FOXP1WT4_1_1.55Hz).  Emits Genotype (WT/HET, also
#         copied into Condition so all existing Condition-based grouping/PART P/
#         modeling work unchanged), Organoid, View, and SampleID = Genotype+
#         Organoid (e.g. "WT4", the organoid-level unit).  Donor / AgeDay /
#         Timepoint / CondTimepoint / Mag / Promoter are NA by construction
#         (no such tokens in these filenames).  Validated: 0 parse failures on
#         all 30 filenames.
#     - SCOPE FILTERS: INCLUDE_CONDITIONS = c("WT","HET"); INCLUDE_DONORS /
#         INCLUDE_TIMEPOINTS / INCLUDE_PROMOTERS = NULL.  (Leaving the
#         assembloid donor/timepoint filters in place would have silently
#         dropped EVERY FOXP1 file -- the exact hazard the v4.25 notes flag.)
#     - GROUPING_VARS = c("Condition")  (WT vs HET only); META_COLS trimmed to
#         the columns that exist for this dataset.
#     - frame_interval = 0.645 s/frame (1.55 Hz), NOT 0.05 s/frame.  Every
#         temporal metric depends on this; it MUST match the acquisition rate.
#     - NEW organoid-level aggregation written right after the per-cell summary:
#         <AnalysisName>_per_organoid_summary.csv      (mean of each metric per
#                                                       organoid; n_cells/n_views)
#         <AnalysisName>_organoid_WT_vs_HET_stats.csv   (Wilcoxon on organoid
#                                                       means + Cohen's d + BH).
#       This is the statistically honest WT-vs-HET test (biological n = 11
#       organoids), complementing the cell-level summary (which pools views).
#     - write_prism_exports made genotype-aware: single Combined cohort with WT
#         and HET columns (no donor cohorts, no C/G/L->Control/GoF/LoF map,
#         which would have produced empty files here).
#     - FAST_MODE = FALSE and TEST_MODE = FALSE: all 30 files, all outputs.
#   NOTE: the supplied file list contained 31 paths; FOXP1WT6_3 appeared to be
#   listed twice -> 30 unique recordings.  Confirm the true count on disk.
#
# v4.26 (2026-05-29)
#   Adds promoter awareness for assembloid filenames carrying CAMK2A / DLX
#   (or other) tokens, so CAMK2A and DLX populations can be tracked
#   separately rather than silently lumped.  v4.25 parse_stem was regex-
#   based and skipped the promoter token without error or column; this
#   build captures it explicitly.
#     - PROMOTER_TOKENS constant (case-insensitive vector of recognised
#         promoter names: CAMK2A, CAMKIIA, DLX, GFAP, SYN, SYN1, VGLUT1,
#         VGLUT2, CAG, EF1A, TRE).  Extend as needed.
#     - parse_stem -> new "Promoter" column (uppercased; NA if no recognised
#         token); also added to META_COLS so PART P / modeling can use it.
#     - INCLUDE_PROMOTERS scope filter (NULL = keep all).
#     - Startup tally: Promoter x Condition table + a "no recognised
#         promoter token" count, mirroring the existing parse audits.
#     - PRISM_BY_PROMOTER toggle (default TRUE).  When ON, write_prism_exports
#         adds per-promoter cohort folders alongside the existing mixed ones:
#             PRISM/Donor1/, Donor4/, Combined/             (promoter-mixed)
#             PRISM/Donor1_CAMK2A/, Donor1_DLX/, ...
#             PRISM/Donor4_CAMK2A/, Donor4_DLX/, ...
#             PRISM/Combined_CAMK2A/, Combined_DLX/, ...
#         Only promoters actually present in the data become folders.
#   No behavioural change for the hCO build (filenames carry no promoter
#   token, so Promoter = NA and PRISM export reverts to its v4.23/v4.25
#   3-cohort behaviour).
#
# v4.25 (2026-05-28)
#   Repoints paths at the Assembloids 20x dataset on the Windows / EC2 box:
#     csv_dir            = C:/Users/Administrator/Documents/PreCFU_Assembloids_20x/
#     mat_dir            = C:/Users/Administrator/Documents/Assembloids_POST/
#     companion_mat_dir  = C:/Users/Administrator/Documents/PreCFU_Assembloids_20x/
#     out_dir            = C:/Users/Administrator/Documents/RESULTS_Assembloids/
#     AnalysisName       = "Assembloids_20x"
#   Mac CalciumTesting paths + older hCO Windows paths kept as commented
#   alternatives in the same block.  No other behaviour change vs v4.24:
#   FAST_MODE, the three INCLUDE_* scope filters, and the PRISM-friendly
#   export are all on by default.  TEST_MODE remains TRUE for the first
#   sanity pass (10 stratified recordings) -- flip to FALSE for the full run
#   once the pairing audit looks right.
#   IMPORTANT VALIDATION STEPS for the new dataset:
#     1) Open RESULTS_Assembloids/pairing_and_parse_audit.csv and confirm
#        Donor / Condition / Timepoint columns parse as expected.  If
#        assembloid filenames use a different convention than hCO, the
#        parse_stem function may need tweaking.
#     2) If INCLUDE_DONORS / INCLUDE_CONDITIONS / INCLUDE_TIMEPOINTS labels
#        differ for assembloids, update them or set to NULL (no filter) --
#        otherwise the scope filter could silently drop everything.
#     3) Confirm Part A scans the Assembloids_POST folder and discovers MAT
#        files; the "[v4.13] rhdf5 self-test" banner should print OK.
#
# v4.24 (2026-05-28)
#   Removes the BASELINE_ACTIVE_ONLY toggle + is_baseline_active() hook + the
#   filter-application block introduced (as a placeholder) in v4.23.  The
#   dataset is Baseline Active by definition for this work, so no recording-
#   level filter is needed -- the placeholder was dead config.  The three
#   INCLUDE_* scope filters (donor / condition / timepoint) remain.  No
#   behavioural change vs. v4.23 with BASELINE_ACTIVE_ONLY = FALSE (its
#   default).
#
# v4.23 (2026-05-28)
#   Adds FAST_MODE, scope filters, and a PRISM-friendly wide export.  Goal:
#   run quickly when the only thing wanted is the per-cell metrics in a form
#   you can drop straight into GraphPad PRISM.
#     - FAST_MODE master toggle (default TRUE) flips three skip toggles:
#         SKIP_PARTB_VIS, SKIP_PARTA2, SKIP_MODELING_AND_PARTP, plus
#         PLOT_EVERYTHING <- FALSE.  Each gates by emptying the relevant
#         iteration vector (mat_files_vis / csv_files / GROUPING_VARS), so
#         the existing loops simply iterate zero times -- no block wrapping.
#     - Scope filters applied to the paired recording table AFTER the
#         pairing audit is written: INCLUDE_DONORS, INCLUDE_CONDITIONS,
#         INCLUDE_TIMEPOINTS (NULL = no filter for that field) + a
#         BASELINE_ACTIVE_ONLY toggle backed by an is_baseline_active()
#         hook -- PLACEHOLDER: the discriminator (filename token, etc.) is
#         not known yet, so the function currently returns TRUE for
#         everything; wire it in when defined.
#     - write_prism_exports() runs immediately after Part A writes the
#         per-cell summary.  For each numeric metric it produces a
#         wide-format CSV (columns Control / GoF / LoF, rows = cell
#         observations, padded with NA) under
#             <out_dir>/PRISM/{Donor1,Donor4,Combined}/<metric>.csv
#         -- drop straight into a PRISM Column Table.  Condition codes
#         C/G/L are mapped to Control/GoF/LoF for the column headers.
#   Numerical outputs unchanged when FAST_MODE = FALSE.
#   NOTE: this build keeps the Mac-local CalciumTesting paths active.
#
# v4.22 (2026-05-28)
#   Makes a dirty R session (re-source without Session > Restart R) NON-FATAL,
#   fixing the recurring "object '.v49_muffle_patterns' not found" crash at
#   package loading.  v4.21 added an in-handler guard, but that could not help:
#   the crash occurs DURING package loading, before this run installs its own
#   (guarded) handler, so the handler that fires is the OLD unguarded one still
#   registered from the previous source.  FIX: define harmless stubs for the
#   objects any stale handler looks up (.v49_muffle_patterns = character(0),
#   .v49_muffled_counts = list(), .v48_log_write = no-op) BEFORE the first
#   package load.  A stale handler firing during loading now finds them and
#   does nothing instead of erroring; the real definitions later overwrite the
#   stubs.  Keeps the v4.21 in-handler guard too (belt and suspenders).
#   Restarting R is still the clean reset, but no longer required to load.
#   NOTE: this build keeps the Mac-local CalciumTesting paths active.
#
# v4.21 (2026-05-28)
#   Hardens the diagnostic calling-handlers against stale-session crashes.
#   SYMPTOM: sourcing failed at package loading with
#   "Error in (function (w) : object '.v49_muffle_patterns' not found".
#   CAUSE: globalCallingHandlers persist in an R session independently of the
#   workspace.  Re-sourcing (or clearing the workspace) WITHOUT Session >
#   Restart R leaves the previous run's warning/message handlers registered.
#   On the next source they fire during package loading -- before this run has
#   re-defined .v49_muffle_patterns / .v48_log_write -- and the handler errors
#   on the missing object.  (Immediate user workaround: Restart R, then
#   source.)  FIX: both handlers now no-op (let the condition pass through)
#   when their infrastructure isn't present, so a stale handler can no longer
#   crash loading.  No change to normal in-run muffling/logging behaviour.
#   NOTE: this build keeps the Mac-local CalciumTesting paths active.
#
# v4.20 (2026-05-28)
#   Fixes spurious "CFU N - no valid event indices" skips in the per-CFU
#   feature panel (integrate_event_windows_per_cfu, Part B vis loop only).
#   ROOT CAUSE: a unit mismatch.  ev_idx (event indices from cfuInfo col 2)
#   were range-checked with `ev_idx <= Nglob`, but Nglob is the dF/F TRACE
#   LENGTH (number of frames, from col 6) -- it was repurposed from the event
#   count in a past fix (the old length(tBegin) returned integer(0) on the new
#   MAT format).  So event indices were bounded by a frame count; for active
#   recordings with MORE events than frames, the highest-numbered (valid)
#   events were rejected and CFUs built from them were dropped from the panel.
#   This affected the per-CFU feature PANEL only -- not the per-cell summary,
#   per-event summary, or modeling/PART P (separate event paths), so no
#   analysed data was affected.
#   FIX: when fts is loaded (ev_idx indexes the per-event arrays) bound ev_idx
#   by length(fts_vecs$tBegin) (= n_events); keep the Nglob (frame) bound only
#   for the fts-absent fallback, where ev_idx is used as a frame position.
#
# v4.19 (2026-05-28)
#   Fixes the CFU relationship-graph step failing on EVERY file in the Part B
#   vis loop with "cannot coerce class 'igraph' to a data.frame".
#   ROOT CAUSE: namespace masking.  Both igraph and dplyr/tibble export
#   as_data_frame().  igraph is attached (line ~1003) after dplyr, but dplyr
#   is RE-attached later (lines ~4026/4453/4961), pushing it back to the
#   front of the search path and re-masking igraph::as_data_frame.  By the
#   vis loop the bare as_data_frame(g, what="edges") resolved to dplyr's
#   version, which can't coerce an igraph -> base coercion error.  The graph
#   built fine (graph_from_data_frame/degree/etc. don't collide); only this
#   call failed, and the v4.11 per-file tryCatch caught it, so feature panels
#   and group-waveform plots were still produced -- only the per-file
#   relationship network plot + *_cfu_relation_nodes.csv were lost.
#   FIX: qualify the call as igraph::as_data_frame(g, what="edges").  Immune
#   to attach order.  (Only unqualified as_data_frame in the script.)
#
# v4.18 (2026-05-28)
#   Adds OPTIONAL process-level parallel SHARDING (toggleable; default OFF =
#   identical to v4.17).  rhdf5 is not thread-safe, so parallelism is across
#   independent OS processes, never threads.
#     - New config: SHARDING_ENABLED / SHARD_STAGE / SHARD_COUNT / SHARD_INDEX,
#       overridable via `Rscript script.R <stage> <count> <index>` (no args =>
#       defaults => single-process, e.g. when sourced in RStudio).
#     - process stage: pairs table filtered to a 1/N slice by row index (so a
#       recording is handled by exactly one shard across Part A/A2/B); per-cell
#       summary, per-event summary, checkpoint and diagnostics are shard-
#       suffixed; modeling/PART P disabled (GROUPING_VARS emptied).  Per-file
#       PNGs go to the shared out_dir (per-recording names => no collisions).
#     - aggregate stage: pairs emptied so no per-file work runs (Part A's write
#       is already guarded by res_i>0, so nothing is clobbered); a merge block
#       concatenates the shard per-cell/per-event CSVs into the master
#       summaries before the modeling section reads out_csv; modeling + PART P
#       then run once on the full dataset.
#     - Companion launcher Run-Sharded.ps1 spawns N process shards, waits, then
#       runs the single aggregate pass.
#   No change to any single-process behaviour or numerical output.  MUST be
#   validated with a small 2-shard dry run before trusting on the full set.
#
# v4.17 (2026-05-28)
#   Adds a third timepoint bin D100 = days 91-109, filling the gap that
#   previously sent d100 recordings to Timepoint=NA.  Bins are now
#   contiguous over 60-140: D80 (60-90), D100 (91-109), D120 (110-140).
#   D80/D120 remain the primary cohorts; D100 is tracked separately because
#   only some files/conditions have it.  Only days < 60 or > 140 are now
#   unbinned.  No other logic change (assign_timepoint already iterated the
#   bin list generically).
#
# v4.16 (2026-05-28)
#   (1) DEVELOPMENTAL TIMEPOINT.  Adds a Timepoint factor binned from the
#   parsed AgeDay (d<NN> token): ~D80 = days 60-90, ~D120 = days 110-140
#   (inclusive), via TIMEPOINT_BINS + assign_timepoint().  parse_stem() now
#   emits Timepoint and a crossed CondTimepoint (e.g. "C_D80"); both are
#   added to META_COLS (so they propagate to the per-cell and per-event
#   tables) and to GROUPING_VARS (so PART P + modeling also run by Timepoint
#   and CondTimepoint).  The pairing step prints a Timepoint x Condition
#   table and warns about recordings whose day falls outside all windows.
#   IMPORTANT: d100 sits in the 91-109 GAP between the two windows, so d100
#   recordings get Timepoint=NA and are EXCLUDED from Timepoint analyses.
#   d100 is present in the data -- widen a window or add a bin in
#   TIMEPOINT_BINS if those should be included.
#
#   (2) MIXED MAGNIFICATION caught.  The dataset is not all-20x; it contains
#   10x recordings too (e.g. 1L_d80_10x).  Added "10X" = 5.2 um/px to
#   UM_PER_PIXEL_BY_MAG (PENDING CONFIRMATION -- geometric ~2x of the 20x
#   2.6; verify against the scope/camera spec).  Reverted the convenience
#   global to a plain default placeholder and documented that, for a
#   mixed-mag dataset, um_per_pixel MUST be resolved per-file from each
#   file's Mag when it is eventually wired into a spatial computation -- it
#   is still unused/calibration-only as of this version.
#
# v4.15 (2026-05-28)
#   Spatial calibration fix.  um_per_pixel was a flat 1.3, which is the
#   wrong value for these 20x recordings -- the correct figure is 2.6 um/px
#   at 20x on this rig.  Replaced the single constant with a
#   magnification-keyed lookup (UM_PER_PIXEL_BY_MAG, currently {20X: 2.6})
#   plus resolve_um_per_pixel(mag); the convenience global um_per_pixel now
#   resolves to 2.6 for this all-20x dataset.
#   IMPORTANT: as of this version um_per_pixel is still not consumed by any
#   spatial computation -- footprints/maps remain in pixel units -- so this
#   change is calibration-only and does not alter any current output.  It
#   sets the right value for when spatial metrics are wired in (footprint
#   area in um^2, spatial-map axes in um).
#
# v4.14 (2026-05-28)
#   Environment switch to the Windows EC2 instance + a latent-variable fix.
#
#   (1) PATHS.  csv_dir / mat_dir / out_dir switched to the C:/Users/
#   Administrator/Documents/... production layout (Mac paths retained,
#   commented, for easy switch-back).
#
#   (2) companion_mat_dir IS NOW USED.  It was defined as `<- mat_dir` but
#   never referenced; PRE-companion (_AQuA2.mat, the fts source) discovery
#   actually scanned csv_dir in two places.  Per the correct data layout
#   the fts companions live in PreCFU_hCO, not POST, so companion_mat_dir
#   now points there AND both discovery sites (the pre_all scan and the
#   get_pre_companion fallback) use companion_mat_dir instead of csv_dir.
#   For this layout (companion_mat_dir == the PreCFU dir == csv_dir) the
#   behaviour is unchanged, but the variable is no longer a decorative lie
#   and companions can live in a separate folder if ever needed.
#
#   (3) TEST_MODE left TRUE on purpose for one validation pass on the new
#   instance (new paths, v4.12 deps, v4.13 self-test all unproven there).
#   Flip to FALSE for the full 1,191-file run after the test pass is clean.
#
#   (4) SAMPLING-UNIT NOTE.  Documented (at the modeling section) that
#   V1/V5/V10 are views of the SAME organoid, so the current cell-level
#   grouping pseudoreplicates for inferential stats.  No behavioural change;
#   flagged for a later decision on organoid-level aggregation / mixed models.
#
# v4.13 (2026-05-28)
#   Fixes a false-abort in the rhdf5 self-test that surfaced when TEST_MODE
#   was switched off for the full 1,191-file run.
#
#   SYMPTOM: "❌ rhdf5 self-test FAILED: no applicable method for `@` applied
#   to an object of class 'integer'", aborting before any file processed.
#
#   ROOT CAUSE: the self-test (a) tested only mat_files[1] and (b) called
#   H5Rdereference(refs[1], fid) with no type guard.  When TEST_MODE is off,
#   the sorted full file list starts at "..._V1_..." ("V1" string-sorts
#   before "V10"), a different first file than the TEST_MODE subset began
#   with.  That file's cfuInfo1 is not a reference array (it comes back as a
#   plain integer array -- e.g. a recording with 0/1 CFUs), so refs[1] is an
#   integer and rhdf5 internally does ref@ID, throwing the `@` error.  The
#   MAIN reader (.rhdf5_read_cell_array) already guards exactly this with
#   inherits(refs,"H5Ref") and skips such files gracefully; the self-test
#   simply lacked the same guard -- and, being a hard stop(), aborted all
#   1,191 files on the strength of one quirky file that the run itself
#   (with v4.11 per-file tryCatch) would have skipped without issue.
#
#   FIX: rhdf5_self_test() now (1) takes the whole candidate vector instead
#   of a single file, (2) guards with inherits(refs,"H5Ref") before any
#   dereference, (3) passes as soon as ONE reference-typed cfuInfo1
#   dereferences to data, (4) only fails/aborts if it finds >=3
#   reference-typed files and none dereferences (the genuine broken-rhdf5
#   signal), and (5) otherwise proceeds with a warning rather than gating
#   the batch.  No change to the main read path; this is self-test only.
#
# v4.12 (2026-05-28)
#   Two fixes prompted by a full-dataset (1,191 recordings) run setup:
#
#   (1) INCOMPLETE DEPENDENCY LIST.  The pre-v4.12 install block listed most
#   but not all required CRAN packages.  Five were used in the code but
#   never installed: stringr (PART P), cowplot and gridExtra (plot
#   helpers), tibble (per-event assembly), and shiny (manual annotator).
#   On a machine that happened to have them via other installs this was
#   invisible; on a fresh instance the run would crash partway through at
#   the first library(stringr) / cowplot:: / gridExtra:: call.  v4.12 adds
#   all five, splits the install into explicit CRAN vs Bioconductor lists,
#   adds an INSTALL_MISSING_DEPS flag (TRUE = auto-install missing; FALSE =
#   hard-error with the exact install command), and prints what it installs.
#
#   (2) RUN-CONFIG VISIBILITY.  After a report of "set TEST_MODE=FALSE but
#   still saw the TEST_MODE message," v4.12 echoes the effective run
#   configuration at startup -- TEST_MODE, TEST_N, PLOT_EVERYTHING,
#   CHECKPOINT_RESUME, GC_EVERY_N_FILES, and the IO paths -- so the active
#   mode is never ambiguous.  NB: the "TEST_MODE on" message was already
#   correctly gated by if(isTRUE(TEST_MODE)); it cannot print when
#   TEST_MODE is FALSE.  Seeing it after setting FALSE means an older file
#   was sourced, the edit wasn't saved, or only part of the script was
#   re-run (stale TEST_MODE in the session).  The startup echo makes that
#   immediately obvious.
#
# v4.11.1 (2026-05-28)
#   Documentation-only patch.  No logic or output changes vs v4.11.  Adds
#   a Table of Contents and a complete Outputs Manifest near the top of the
#   script so a maintainer can find any section or any output without having
#   to read the whole file, and adds short docstring-style explanations to
#   each major section banner (PART A, PART A2, PART B, PART P, modeling
#   pass, final summary).  Run-time behaviour and on-disk artifacts are
#   byte-for-byte identical to v4.11.
#
# v4.11 (2026-05-28)
#   Production-scale hardening pass for runs on hundreds-to-thousands of
#   recordings (target: AWS r7a.24xlarge or similar).  The pipeline was
#   correct as of v4.10 but had three production risks: a single
#   corrupted file would crash the entire multi-hour run, there was no
#   way to resume after a crash, and the per-CFU plot output would
#   balloon to tens of thousands of PNGs at scale.  Five changes:
#
#   (1) PER-FILE TRYCATCH IN PART A AND THE PER-EVENT LOOP.  The vis loop
#   already had per-file error isolation (v4.7).  The Part A main loop
#   (~line 3106) and the per-event consolidation loop (~line 3808) did
#   not -- any uncaught error in 1 of N files killed the whole run.  Both
#   loop bodies are now wrapped in tryCatch with an error path that
#   records the failure in the diagnostic accumulator and `next`s to the
#   following file.  Verified `next` works inside tryCatch so the
#   existing flow-control next statements (for legitimate skips) don't
#   need to be touched.
#
#   (2) CHECKPOINT / RESUME.  Each successful Part A file appends its
#   prefix to <out_dir>/<analysis_name>_checkpoint.txt.  On startup, if
#   CHECKPOINT_RESUME is TRUE and that file exists, prefixes in it are
#   skipped.  Set CHECKPOINT_RESUME=FALSE (or delete the checkpoint file)
#   to force a clean restart.  Skips are recorded as `status="skipped_ckpt"`
#   in the JSON so a resumed run's diagnostic is still complete.
#
#   (3) PERIODIC GC.  R doesn't aggressively garbage-collect, so transient
#   spatial map matrices, ggplot grob objects, and HDF5 read buffers can
#   accumulate over hundreds of files.  Now calls gc(verbose=FALSE) every
#   GC_EVERY_N_FILES files (default 25) in Part A, per-event, and the
#   vis loop.  Cheap insurance; one gc() pass takes <100ms on a 1GB
#   working set.
#
#   (4) PLOT_EVERYTHING knob.  Default TRUE preserves the v4.10 output
#   set.  Set to FALSE for scale runs: skips the per-CFU spatial pattern
#   plots and per-CFU peak-aligned waveforms, which are the dominant
#   source of PNG count (one per CFU per file = thousands of files at
#   scale).  Summary/group/relationship plots still emit so you can spot-
#   check.  At 2000 input files, this is the difference between ~30 GB
#   of PNGs and ~1 GB.
#
#   (5) Per-file output now includes any error message in the JSON
#   accumulator, so a 2000-file run can be triaged from a single JSON
#   to see which files failed and why.  Look for status="error" or
#   status="skipped_ckpt" entries.
#
#   Not in v4.11: in-process parallelism via future/multicore.  For the
#   r7a.24xlarge target, the cleanest path is shell-level parallelism --
#   split the file list, launch K copies of the script with different
#   out_dir / analysis_name, post-merge.  Each instance maintains its
#   own diagnostic JSON.  In-R parallelism with rhdf5 + ggplot2 is fragile
#   (rhdf5 isn't thread-safe across workers, the global accumulators need
#   gathering, and ggplot2 has had memory-leak regressions on multicore);
#   not worth introducing without explicit demand.
#
# v4.10 (2026-05-27)
#   Cleanup pass after v4.9 ran successfully end-to-end on hCO_Donors1and4.
#   The pipeline itself is healthy (0 ggsave failures, all 10 vis files
#   completed, modeling counts correct).  Remaining issues are cosmetic
#   noise that the muffle filter doesn't yet cover:
#
#   (1) ggsignif stat_signif failures.  402 "Computation failed in
#   `stat_signif()`" warnings made it through the v4.9 filter.  These come
#   from PART P where ggsignif tries to compute pairwise significance
#   brackets for the Kruskal-Wallis dot/box/violin plots.  When a feature
#   has degenerate data within a group (zero variance, one non-NA value),
#   the underlying test fails and ggsignif emits this warning -- but the
#   Kruskal-Wallis and Dunn p-values themselves still compute correctly
#   via FSA::dunnTest, so the actual statistics are fine.  The 1003
#   "longer object length is not a multiple" recycling warnings (already
#   muffled in v4.9) are mostly downstream of these same failures.
#   Fix: add "Computation failed in.*stat_signif" to the muffle list.
#
#   (2) Diagnostic version string.  The v4.8 diagnostic apparatus
#   hardcoded "v4.8" in the JSON file name, the `version` field, and the
#   "[v4.8] Diagnostic log written:" messages.  v4.9 didn't update these,
#   so a v4.9 run wrote diagnostics_v4.8_<ts>.json.  v4.10 introduces a
#   SCRIPT_VERSION constant near the top of the script that drives all
#   user-facing version strings, so future bumps need to change exactly
#   one line.  Internal variable names (.v48_log_con, .v48_part_a_files,
#   etc.) are kept as-is to avoid churn -- those are just identifiers.
#
#   (3) "pushing duplicate `message` handler on top of the stack" notice.
#   Fired by R's globalCallingHandlers when the script is re-sourced in
#   the same R session (the previous run's handlers are still registered;
#   ours replace them).  Cosmetic but visible at the top of every re-run
#   log.  This notice is a *message*, not a warning, so options(warn=-1)
#   does not apply.  suppressMessages() cannot be used either because it
#   sets up a calling-handler context internally, and
#   globalCallingHandlers() refuses to run while any calling handler is on
#   the stack.  Fix: a small .v410_install_handlers() helper wraps the
#   registration in sink(nullfile(), type="message") -- this redirects
#   stderr writes to /dev/null at the connection level (no handler context)
#   for the single globalCallingHandlers() call, then pops the sink via
#   on.exit().  Safe with RStudio's own message sink: we pop only the
#   sink we pushed.  The same helper is used for the cleanup no-op
#   registration at script end.
#
# v4.9 (2026-05-27)
#   Three fixes after v4.8 run in RStudio revealed real bugs in the
#   diagnostic apparatus introduced by v4.8:
#
#   (1) DUPLICATED CONSOLE OUTPUT.  v4.8 used sink(con, type="output",
#   split=TRUE) AND globalCallingHandlers(message=...) together.  In
#   RStudio, R's stderr (where message() writes) is routed through the
#   stdout stream into the console, where the split=TRUE sink catches it
#   and writes a SECOND copy to the log file -- and the console displays
#   it twice as well.  print() output was unaffected because it travels
#   only through stdout, not stderr.
#   Fix: drop sink() entirely.  Keep only globalCallingHandlers for
#   message + warning.  Trade-off: print()/cat()/auto-printed-table
#   output no longer appears in the log file, but those facts (DonorCond
#   table, modeling class counts) are captured structurally in the JSON
#   summary, which is what a maintainer actually needs to triage a run.
#
#   (2) WARNING SPAM.  Three classes of harmless-but-noisy warnings were
#   already firing in v4.7 / v4.8 but were silently batched by R's deferred
#   warning queue ("There were 50 or more warnings"):
#     - "An open HDF5 file handle exists" from rhdf5::h5read() not closing
#       its file handle between calls.  Cosmetic; rhdf5 still reads
#       correctly.
#     - "Ignoring unknown parameters: `label.size`" from
#       annotate("label", label.size=...) in .add_waveform_annotations.
#       Newer ggplot2 versions don't forward label.size through annotate();
#       the label still renders, just with a default border thickness.
#     - "Removed N rows containing missing values" -- standard ggplot NA
#       removal from filtered traces.
#     - "longer object length is not a multiple of shorter object length" --
#       harmless recycling in plot helpers; present since v3.0.
#   v4.8's globalCallingHandlers fires immediately on each warning, so the
#   user now sees every one inline -- which is worse than the batched
#   behaviour they replaced.
#   Fix: warning handler now classifies each warning against a NOISE
#   PATTERN list; matches are muffled (not displayed, not logged) but
#   tallied so the count appears in the JSON summary as
#   `muffled_warning_counts`.  Real warnings still propagate normally.
#
#   (3) RSTUDIO HANG AT SCRIPT END.  After diagnostic JSON write, the
#   cleanup ran
#     while (sink.number(type="message") > 0) sink(type="message")
#     while (sink.number() > 0)                  sink()
#   RStudio installs its own message sink to capture R messages for its
#   console display; calling sink() from the user side does NOT pop that
#   sink (it's owned by RStudio), but it ALSO does not error -- it just
#   silently does nothing.  sink.number() still reports >0, so the loop
#   never exits.  try(silent=TRUE) does not catch infinite loops.  The
#   user-visible symptom: diagnostic summary prints, then the script
#   appears to keep running forever.
#   Fix: drop the cleanup loop entirely.  v4.9 never opens a sink, so
#   there's nothing to pop.  Handlers are replaced with no-ops at script
#   end to stop them firing on subsequent interactive prompts in the same
#   session (globalCallingHandlers persists until explicitly replaced).
#
# v4.8 (2026-05-27)
#   Two changes after v4.7 run on hCO_Donors1and4 (TEST_MODE=TRUE) revealed
#   the remaining failure mode and showed we need a better way to report
#   diagnostics to maintainers:
#
#   (1) SPATIAL MAP VIEWPORT ERROR -- root cause found and fixed.  v4.7
#   wrapped every Part B ggsave in tryCatch with a per-plot tag, which
#   revealed that the ONLY remaining failure was save_cfu_spatial_png():
#   every CFU's "SpatialPattern.png" and every combined "SpatialPresence" /
#   "SummedWeights" PNG failed with the grid viewport error, while every
#   other plot type (overlaid/faceted/heatmap/raster/single-CFU/peak-aligned/
#   relationship graph/group waveforms) saved correctly.
#   Tracing the data flow:
#     .rhdf5_deref_one() called rhdf5::H5Dread(did) -> v, then returned
#       `as.numeric(as.vector(v))`
#   `as.vector()` strips the dim attribute, so a 502x502 spatial matrix
#   comes back as a 252,004-length flat numeric vector with no dims.  The
#   caller (.rhdf5_read_cell_array -> cfuList[i,3][[1]] -> to_numeric_matrix)
#   then reshapes any non-2D input as Ncells x 1 -- a degenerate column
#   vector that geom_raster + coord_fixed cannot render, producing
#     Error in grid.Call.graphics(C_setviewport, vp, TRUE):
#       non-finite location and/or size for viewport
#   Locally reproduced: an Nx1 or 1x1 matrix in save_cfu_spatial_png reliably
#   throws this error; 1xN and proper 2D matrices succeed.
#   Fix: preserve dim attributes for 2D arrays in .rhdf5_deref_one().
#   Other downstream consumers (to_numeric_vec for traces/IDs/events) already
#   handle both flat-vector and 2D-array inputs, so the change is backward-
#   compatible end-to-end.
#
#   (2) DIAGNOSTIC ARTIFACTS.  Console logs are bulky to paste back when
#   debugging a long run; the user needs a single self-contained file to
#   share with maintainers.  Added:
#     - Full-run log: console output is tee'd to RESULTS/diagnostics_v4.8_
#       <timestamp>.log.  message() and warning() use globalCallingHandlers
#       (R >= 4.0); print/cat use sink(type="output", split=TRUE).
#     - Structured JSON summary: RESULTS/diagnostics_v4.8_<timestamp>.json
#       written at the very end of the script, capturing the facts a
#       maintainer would need to triage a run without the full log:
#         * R / platform / package versions
#         * TEST_MODE config + actual DonorCond distribution after pick
#         * Per-file Part A summary (cells added, skip reasons)
#         * Per-file Part B summary (ggsave failures grouped by tag/file)
#         * Modeling target class counts per grouping
#     - .safe_ggsave() now also appends each failure to a global accumulator
#       (.v48_ggsave_failures) that feeds the JSON summary.
#   These outputs are written even if the script aborts partway through
#   (sink and accumulator are flushed by an at-exit handler), so the user
#   can share the partial log instead of restarting from scratch.
#
# v4.7 (2026-05-27)
#   Four fixes after v4.6 run on hCO_Donors1and4 (TEST_MODE=TRUE, TEST_N=10)
#   exposed three additional real bugs and one latent defect:
#
#   (1) TEST_MODE FILE DUPLICATION (CRITICAL).  Run log shows the first file
#   (1C_V10) being processed twice in BOTH Part A (per-cell aggregation) AND
#   the per-event pass, and the modeling target shows 1C with 41 cells = 12
#   (V10) + 12 (V10 AGAIN) + 17 (V11), and 4C/4G/4L only 1 file each instead
#   of the expected balance.  Root cause: classic R footgun -- when the
#   stratified picker reaches a group with only one remaining index in
#   `avail`, the call `sample(avail, 1)` triggers sample()'s "convenience"
#   behaviour where a length-1 first argument is treated as `n` and a random
#   integer in 1:avail is returned instead of avail itself.  Verified:
#     > set.seed(1); sample(c(11), 1)
#     [1] 9   # not 11!
#   That stray integer collides with another group's index, the inner loop
#   re-picks the same file in a later pass, and `usable[sort(pick), ]` ends
#   up with duplicate rows.  Fix: guard with `if (length(avail) == 1) avail
#   else sample(avail, 1)`.  Also added a deduplication safety net after the
#   pick loop so any future indexing bug cannot leak duplicates downstream.
#
#   (2) Rise/Decay COLUMN NAME MISMATCH (latent since v1.3).
#   compute_one_event_metrics() emits `Rise10_90_sec` and `Decay90_10_sec`
#   (no underscore between digits and number), but .add_waveform_annotations,
#   plot_cfu_annotated_overlay, and plot_cfu_peak_aligned_overlay all read
#   `Rise_10_90_sec` / `Decay_90_10_sec` (with underscores).  Effect: those
#   mean() calls on a non-existent column return NA with the warning
#   "argument is not numeric or logical", which (a) silently disables the
#   rise/decay bracket annotations on every per-CFU waveform PNG and (b)
#   contributes ~50% of the "There were 50 or more warnings" output noise.
#   Same bug existed in v3.0 and earlier -- never noticed because warnings
#   were tolerable and brackets were not the primary deliverable.  Fix: use
#   the canonical names (Rise10_90_sec / Decay90_10_sec) at every read site
#   AND every write site so the columns line up end-to-end.  The gsub() block
#   in plot_cfu_event_feature_panel() that mapped one form to the other is
#   now a no-op but is preserved for backward-compat with any old CSVs the
#   user might re-run feature panels on.
#
#   (3) VIEWPORT ERROR in Part B (FATAL on first vis file).  Run aborted with
#     Error in grid.Call.graphics(C_setviewport, vp, TRUE):
#       non-finite location and/or size for viewport
#   immediately after the "skipping group outputs" message on 1C_V10.  This
#   is a grid-level rendering error from ggsave triggered by a non-finite
#   coordinate or limit somewhere in the plot.  Without a reproducible local
#   environment I could not pinpoint the exact culprit, so v4.7 takes a
#   defensive approach:
#     - Each ggsave in the Part B vis loop is wrapped in tryCatch with an
#       informative message identifying WHICH plot failed for WHICH file.
#       Subsequent plots in the same file are still attempted; subsequent
#       files are still attempted.  No more silent termination of a long
#       batch on a single bad plot.
#     - plot_overlaid_dff0 / plot_faceted_dff0 z-scoring rewritten with
#       explicit NA / single-value / zero-variance handling so dplyr can no
#       longer evaluate `if (NA > 0)` and error out before plot construction.
#     - .add_waveform_annotations now bails early if mean_df is empty, all-y
#       non-finite, or x_max/y_max are non-finite; same for the label x/y
#       computation.  Returns the input plot unchanged on degenerate input.
#   Outcome: the run will not crash on the first vis file even if some plot
#   has degenerate data; the user will see a per-plot error message
#   pinpointing which file/plot combination has the issue, and can pull just
#   that one apart in a follow-up.
#
#   (4) `dim(NULL)` SKIP in per-event pass.  v4.6 used `dim(cfuList)` then
#   tested `length(dims) != 2` to detect missing cfuInfo.  When cfuInfo1 is
#   absent (e.g. 1G_V10 in the test run), get_cfuinfo() returns NULL and
#   dim(NULL) is NULL -- length 0, so the check correctly says "Unexpected
#   cfuInfo dims".  Cosmetic: also test `is.null(cfuList)` first and print a
#   clearer "cfuInfo missing" message matching Part A's wording, so the user
#   doesn't see two different messages for the same condition.
#
# v4.6 (2026-05-27)
#   Three fixes after v4.5 run revealed real bugs:
#
#   (1) ORIENTATION DETECTION for cell arrays.  Different POST .mat files have
#   different HDF5 dims for cfuInfo1 ([12,9], [4,9], [54,9], [19,9], ...) and
#   the rigid "nfields=dims[1], ncells=dims[2]" rule + "transpose if <6 fields"
#   heuristic from v4.5 misread several files:
#     - File 1L_V10 (dims=[4,9]): cell 2 reported events=252004 (= 502*502 =
#       a spatial-pattern matrix being read as the events vector).
#     - File 4C_V10 (dims=[54,9]): all 9 "cells" reported duration=0.05s (the
#       file actually has ~54 cells × ~9 fields, not 9 cells × 54 fields).
#     - File 4L_V10 (dims=[19,9]): all 9 "cells" reported duration=12600s.
#     - File 1G_V1  (dims=[2,9]):  cell 1 reported duration=12600s (= reading
#       a 252,000-element spatial pattern as dFF0; real layout is 2 cells × 9).
#   Fix: smart auto-detect.  MATLAB writes cell arrays column-major, so the
#   leading refs of cfuInfo1 are field 1 = IDs = integer scalars whose VALUES
#   are 1, 2, 3, ..., Ncells.  Find the longest prefix where ref[i] is a
#   length-1 scalar with value == i.  This distinguishes IDs from coincidental
#   single-event scalars (an event frame index of 137 will not match position
#   3, so the prefix correctly stops at the last true ID).
#   From that candidate prefix, walk DOWN looking for the largest k where
#   total_refs %% k == 0 AND nfields=total/k is in a plausible range [2, 200].
#   That k is ncells; nfields = total / k.  Falls back to the dims interpretation
#   only if the auto-detect produces no usable candidate.  Removes the
#   aggressive transpose-if-thin rule that was double-rotating file 1L_V10.
#
#   (2) cfuGroupInfo ROUTING.  v4.5 returned cfuGroupInfo as a flat R list,
#   but Part B's group loop accesses grp[gi, 1][[1]] which needs a 2D
#   list-matrix.  This crashed every visualization run with "incorrect
#   number of dimensions" on the first file.  Fix: route cfuGroupInfo
#   through .rhdf5_read_cell_array() the same way cfuInfo1/cfuInfo2 go, so
#   it comes back as [Ngroups × 4] matching the orig.R expectation.
#
#   (3) .h5_safe_exists RESTORED.  v4.5 removed the hdf5r-based safe-exists
#   helper, but integrate_event_windows_per_cfu() and the Part B vis loop
#   still call it when opening PRE companion files for fts vectors (tBegin,
#   tEnd, dffMaxFrame).  Those PRE companion reads are plain numeric paths
#   (no H5R refs) and were always handled fine by hdf5r; only their existence-
#   check helper went missing.  Restored as a thin hdf5r exists() wrapper so
#   the v3.0/v2.1 fts reads work again; falls back to symmetric half-window
#   if any PRE companion lacks fts as before.
#
#   Added [v4.6] per-file log line:
#     [v4.6] cfuInfo1: auto (scalar-ID prefix=N); ncells=K, nfields=F; resolved X/Y refs
#   Tells you at runtime which detection branch fired and the resulting shape.
#
# v4.5 (2026-05-27)
#   HDF5 backend swapped: hdf5r -> rhdf5 (Bioconductor).
#
#   The v4.4 address-mapping attempt resolved 0/N refs because the H5R "raw"
#   bytes that hdf5r exposes via $ref are NOT haddr_t file offsets — every
#   hdf5r H5R accessor ($ref / $get_ref() / $get_obj_type() / $dereference())
#   either returns garbage or calls the deprecated H5Rdereference2, which
#   fails on this libhdf5 + MATLAB-file combination. Confirmed empirically
#   over diagnostics v2..v8.
#
#   rhdf5 2.52.1 reads the same file successfully:
#     - rhdf5::h5read(path, "cfuInfo1") returns an H5Ref S4 object holding all
#       108 references (9 cells * 12 fields) packed into the @val raw slot.
#     - rhdf5::H5Rdereference(ref[i], fid) returns a real H5IdComponent id;
#       rhdf5::H5Dread(did) then yields the target numeric data.
#     - HDF5 row-major linear order on the [Nfields, Ncells] dataset maps
#       i -> (field = ((i-1) %/% Ncells) + 1, cell = ((i-1) %% Ncells) + 1).
#
#   This version drops the broken hdf5r read paths from read_mat_smart() and
#   .h5_to_mat_list, replacing them with rhdf5-based equivalents:
#     .rhdf5_path_exists(), .rhdf5_dims(), .rhdf5_deref_one(),
#     .rhdf5_read_cell_array(), .rhdf5_read_numeric(), .rhdf5_read_fts(),
#     .h5_to_mat_list_rhdf5(), rhdf5_self_test().
#   read_mat_smart() still tries R.matlab::readMat() first (handles v5/v6),
#   then falls through to the rhdf5 path on v7.3 errors.
#
#   Adds an rhdf5_self_test() call right before the PRE/POST main loop:
#   it dereferences refs[1] from the first POST .mat file and confirms it
#   produces non-empty numeric data. If the self-test fails the script
#   aborts with a clear message, saving the user from a 1000+ file run
#   that silently emits empty cells.
#
#   pkgs list adds rhdf5 (installed automatically via BiocManager).
#   hdf5r is kept loaded if available (used for non-essential checks) but
#   no longer required for reads.
#
# v4.4 (2026-05-27)
#   .h5_read_cell_array: bypass H5R dereference entirely (address-mapping).
#
#   ROOT CAUSE FROM DIAGNOSTIC v2:
#   On hdf5r 1.3.12 linked against libhdf5 1.14.5, the H5R dereference path
#   (used internally by *every* dereference API: h5f$ref_obj(), ref$dereference(),
#   bulk H5R_OBJECT$dereference()) calls the deprecated C function
#   H5Rdereference2, which fails with "unable to open object by token" for
#   files written by newer MATLAB versions that use the modern reference
#   format.  This affects the entire hCO POST .mat cfu file set.
#
#   The bug has actually existed since LindaDGvsCA v2.0 (orig.R line 924 calls
#   the nonexistent h5f$ref_obj method), but the HDF5 path was never reached
#   in the original pipeline -- LindaDGvsCA .mat files were saved as v5/v6
#   (not HDF5), so R.matlab::readMat() handled them and the HDF5 fallback at
#   read_mat_smart() never ran.  The hCO files are v7.3 (HDF5), forcing the
#   fallback and exposing the latent bug for the first time.
#
#   WORKAROUND (this version):
#   The raw 8 bytes of each H5R encode a file address (little-endian uint64).
#   Each #refs#/<name> member has the same address available via
#   h5f$obj_info_by_name("#refs#/<name>")$addr.  So we:
#     1. Walk #refs# once, build a byte_address -> member_name map.
#     2. For each ref in cfuInfo1, decode the 8 raw bytes -> address ->
#        look up the member name in the map.
#     3. Read #refs#/<name>[] directly (works -- proven in TEST 3).
#   This never calls $dereference / $ref_obj / H5Rdereference2.  Other
#   readers (.h5_read_numeric_matrix, .h5_read_fts on PRE companions) use
#   direct path access already and were never affected.
#
#   Added per-file [v4.4] log line showing how many cfuInfo1 cells/fields
#   were mapped from the #refs# address table, so reading-vs-not-reading is
#   visible at runtime instead of silently producing empty cells.
#
# v4.3 (2026-05-27)
#   .h5_read_cell_array dereferencing fix. v4.2 fixed the SUBSCRIPT bug
#   (refs[[ ]] -> refs[ ]) so the H5R subset was correct, but the very next
#   step called h5f$ref_obj(ref) -- and ref_obj IS NOT A METHOD on H5File in
#   hdf5r 1.3.12. Every call threw "attempt to apply non-function", was
#   swallowed by tryCatch, and every cell silently became numeric(0).
#   Symptom: "MAT OK: 9 cells found" followed by "Cell N: no events -> skip"
#   for every cell of every file.  Confirmed via diagnostic script that did
#   side-by-side comparisons of all candidate hdf5r APIs.
#   Fix:
#     - Replace h5f$ref_obj(ref) with the documented hdf5r 1.3.x API:
#       ref_subset$dereference(object = h5f) returns a list of H5D/H5G
#       targets, one per ref in the subset. Take [[1]] for a 1-element subset.
#     - Per-element dereference + tryCatch, not bulk. The diagnostic showed
#       bulk refs_all$dereference(object = h) fails on the first invalid ref
#       (MATLAB writes empty cells as "canonical empty array" placeholders
#       that hdf5r can't open). Per-element isolates the failure to that one
#       cell, which becomes numeric(0); valid cells return real data.
#     - Same fix applied to legacy .h5_deref_numeric helper.
#     - All other v4.1/v4.2 hardening (.h5_safe_exists, ds$read for 2D refs,
#       numeric-matrix fallback, ncol>=2 guard, dedup'd header) preserved.
#   Confirmed against the AQuA2 documentation (uploaded by user): cfuInfo is
#   nCFU x 6+ cell array with field 2 = event indices, field 6 = dF/F0 trace,
#   which is exactly what downstream code (cfuMat[cell_idx, 2 or 6]) expects.
# v4.2 (2026-05-27)
#   .h5_read_cell_array indexing fix. v4.1 correctly switched ds[] -> ds$read()
#   for 2D H5T_REFERENCE datasets, but then used DOUBLE-BRACKET subsetting
#   (refs[[c, r]] / refs[[i]]) on the returned object. ds$read() on a reference
#   dataset returns an H5R_OBJECT (R6 class, environment-based), which rejects
#   [[ ]] subscripts with either "incorrect number of subscripts" or "wrong
#   arguments for subsetting an environment" depending on whether dim() is set.
#   That made every flat POST file fail with "cfuInfo/cfuInfo1 missing -> skip"
#   even though cfuInfo1 was being successfully read.  Fix:
#     - Use SINGLE-BRACKET indexing refs[h5_row, h5_col] (or refs[i] for 1D).
#       H5R_OBJECT supports this and returns a 1-element H5R_OBJECT subset.
#     - Added per-element dataset slab read ds[h5_row, h5_col] as a fallback
#       in case ds$read() ever returns something unusable.
#     - Refactored: dimension naming now uses explicit nfields/ncells so the
#       HDF5 <-> MATLAB transposition (HDF5 stores [Nfields, Ncells]) is
#       impossible to get wrong.
#     - 1D / safety-transpose / dtype-check paths unchanged from v4.1.
# v4.1 (2026-05-27)
#   HDF5 reader hardening (POST .mat files are flat: cfuInfo1/cfuRelation/etc
#   sit at top level; no `res/` group). Three real bugs in v4.0 fixed:
#     - .h5_to_mat_list called h5f$exists("res/...") on every file; that
#       *throws* on hdf5r 1.3.12 + libhdf5 1.14.5 when the parent path is
#       missing, so every flat POST file produced "HDF5 parse error" and was
#       skipped. Wrapped via new .h5_safe_exists() so a missing path returns
#       FALSE cleanly. res/ candidates are still attempted for compatibility.
#     - .h5_read_cell_array used ds[] which fails for 2D H5T_REFERENCE
#       datasets on this hdf5r version with "Number of arguments not equal to
#       number of dimensions". Switched to ds$read() with a ds[,] fallback.
#     - cfuRelation is a plain F64 matrix, not a cell array of refs; reading
#       it as a cell array produced empty/malformed results. Added
#       .h5_read_numeric_matrix() and route cfuRelation through it (cell-array
#       path kept as a fallback for older formats). cfuGroupInfo tries cell
#       array first, then numeric.
#     - Added a safety transpose for cfuInfo* when the result comes out with
#       <6 cols but >=6 rows (cfuInfo always has 6+ fields).
#     - 1D-vector branch: for cfuInfo* with >=6 elements, treat as 1-cell row.
#     - Same .h5_safe_exists() guard extended to inline .h5read_vec / .h5rv
#       helpers and the four-candidate fts_root resolvers in
#       integrate_event_windows_per_cfu() and the Part B vis loop, so PRE
#       companion reads also survive missing res/ groups without throwing.
#     - Part A: guard cfuMat for ncol >= 2 before indexing field 2 (event ids);
#       a degenerate file (e.g. 1G_V10 with 1 detected event) used to print
#       "MAT OK: 2 cells found" then crash on "subscript out of bounds". Such
#       files now skip cleanly with a clear message.
# v4.0 (2026-05-27)
#   Integration (was staged v1/v2/v3, now consolidated):
#     - v1 structural: removed the _AQuA2 prefix-strip that broke matching when
#       both CSV and POST carry _AQuA2; HDF5-safe MAT reads in Parts A & A2
#       (read_mat_smart replaces readMat); PRE<->CSV<->POST pairing table with
#       pairing_and_parse_audit.csv; position-independent filename parser
#       (Donor/Condition/DonorCond/AgeDay/Mag/NominalHz/EffectiveHz/Tissue/
#       Organoid/Video); stratified TEST_MODE.
#     - v2 grouping: PART P + modeling run once per GROUPING_VARS entry
#       (Condition pooled; DonorCond 6-way) into Plots_<g>/ and Modeling_<g>/;
#       META columns excluded from feature sets; ggsignif ylim rng[15]->rng[2].
#     - v3 HDF5 hardening: cfuInfo1/fts1/cfuGroupInfo/cfuRelation readers try
#       both top-level and res/ nesting (auto-detect); Part B reuses the
#       paired+TEST_MODE file list.
#   Performance:
#     - PRE-companion .mat lookup is O(1) via pre_mat_index (replaces recursive
#       list.files per file, both call sites).
#     - Each PRE companion's fts windows read once per recording and passed into
#       integrate_event_windows_per_cfu() (was opened twice).
#     - Row accumulation via data.table::rbindlist(fill=TRUE) (Parts A & A2).
#   Assembloid:
#     - parser tissue token broadened (hCO/ASSY/ASMB/ASM/assembloid/organoid);
#       literal matched token stored in the Tissue column.
#   Config: I/O paths set to local Mac test drive (production EC2 paths kept as
#       comments); confirm Donor x Condition in the console/audit on first run.
# (The archival "PRIOR LINEAGE" block below documents the LindaDGvsCA history.)
# ============================================================================

# ============================ AQuA2 CFU ANALYSIS PIPELINE v2.0 (FLAT OUTPUT LAYOUT) ============================
# ============================================================================
# TABLE OF CONTENTS                                              [v4.11.1]
# ============================================================================
# Source order, approximate line numbers (drift slightly per edit):
#
#   §1  Master changelog                                            1
#   §2  Pipeline overview (PRE+POST integration, network bursts)  498
#   §3  Library loads                                             610
#   §4  Global parameters (TEST_MODE, GROUPING_VARS, png_dpi,     670
#                          burst clustering knobs, plotting theme)
#   §5  Global ggplot theme                                       790
#   §6  v4.11 scaling knobs (GC_EVERY_N_FILES, CHECKPOINT_RESUME, 651
#                            PLOT_EVERYTHING)
#   §7  Output directory layout (flat tree under out_dir)         810
#   §8  Helper functions (stem parser, PRE-companion lookup,      895
#                         numeric/matrix coercion, IEI metrics)
#   §9  Plotting helpers (per-CFU overlay, group waveforms,      1135
#                         spatial PNG writer, feature panel)
#   §10 Group waveform data builder                              1405
#   §11 Event-coincidence (network burst) helpers                1430
#   §12 IEI metrics                                              1545
#   §13 MAT-v7.3 readers via rhdf5 + hdf5r                       1510
#   §14 rhdf5 self-test                                          1815
#   §15 Diagnostic apparatus (log + JSON; v4.8/4.9/4.10)         2890
#   §16 v4.11 checkpoint + gc helpers                            3000
#   §17 PART A: file listing and PRE/POST pairing                3160
#   §18 PART A: per-cell aggregation main loop                   3230
#   §19 PART P: distribution plots + Kruskal-Wallis + Dunn       3390
#   §20 Modeling pass: random forest feature importance          3590
#   §21 PART A2: per-cell per-event consolidation                3965
#   §22 PART B: manual group annotator (Shiny launcher)          4125
#   §23 PART B: per-file visualization loop                      4360
#   §24 Consolidated manual + group CSV writes                   5020
#   §25 Final summary + diagnostic JSON write                    5060
#
# ============================================================================
# OUTPUTS MANIFEST                                               [v4.11.1]
# ============================================================================
# All paths relative to `out_dir`.  Each input file is identified by its
# <prefix>, derived from the .mat filename by stripping "_res_cfu.mat" and
# (for CSVs) "_Ch[0-9]+".  Example prefix:
#   "1C_d100_20x_20Hz_hCO_ORG1_V10_19.05Hz_AQuA2"
#
# Items tagged [per CFU] multiply by the number of detected CFUs in the
# input MAT (typically 1-60, mean ~14 in test data).  Items tagged
# [PLOT_EVERYTHING] are v4.11 gates: emitted only when the global flag is
# TRUE (default).  Disable for scale runs to cut PNG count ~10x.
#
# ---- PER-ANALYSIS (one of each, regardless of N files) -------------------
#   <AnalysisName>_per_cell_summary.csv
#                                  Part A consolidated: one row per CFU
#                                  cell across all files.  Columns: File,
#                                  CellID, NumberOfEvents, DurationOfVideo,
#                                  FrequencyHz, MeanIEI_sec, IEI_CV, plus
#                                  per-variable means from the CSV (~37
#                                  feature columns).
#   per_cell_per_event_summary.csv Part A2 consolidated: one row per CFU
#                                  per event (no averaging).  Adds EventID
#                                  and t_event_sec columns.  Much larger
#                                  than the per-cell summary.
#   <AnalysisName>_checkpoint.txt  [v4.11] Resume state.  One processed
#                                  prefix per line.  Delete to redo, or
#                                  set CHECKPOINT_RESUME=FALSE.
#   diagnostics_<SCRIPT_VERSION>_<ts>.json
#                                  Structured run summary: versions, IO
#                                  paths, per-file statuses, modeling
#                                  class counts, muffled warning counts,
#                                  scaling knob values.  Primary triage
#                                  artifact for a long run.
#   diagnostics_<SCRIPT_VERSION>_<ts>.log
#                                  Free-form message + warning log.
#                                  Contains console messages with no
#                                  duplication and non-muffled warnings.
#   CFU_Groups/CSVs/cfu_groups_membership.csv
#                                  Combined CFU-to-group mapping across
#                                  all files that had cfuGroupInfo.
#   CFU_Groups/CSVs/group_event_bursts.csv
#                                  Detected network-burst events per
#                                  group, across all files (automatic).
#   CFU_Groups/CSVs/group_event_bursts_manual.csv
#                                  Same but for Shiny-annotated bursts
#                                  (only present if manual annotation was
#                                  performed during the run).
#   Modeling_<target>/             [per GROUPING_VARS entry, default 2:
#                                  "Condition" and "DonorCond"]
#     <target>_feature_importance.csv     -- RF importance scores
#     <target>_feature_importance.png     -- top-N bar chart
#     <target>_confusion_matrix.png       -- if classification
#     <target>_oob_error.txt              -- holdout / OOB summary
#   PerCellPerEvent/Modeling_<target>/    -- modeling on the per-event
#                                            table (richer feature set)
#   PART_P_<grouping>/             [Kruskal-Wallis + Dunn dist plots]
#     <feature>__<grouping>__violin.png   -- per-feature distributions
#     <feature>__<grouping>__box.png
#     <feature>__<grouping>__dot.png
#     PART_P_<grouping>_summary.csv       -- KW + Dunn results table
#
# ---- PER INPUT FILE (each MAT/CSV pair produces) -------------------------
#   PART A:   (no per-file files; rows go into the consolidated CSVs above)
#
#   PART A2:  PerCellPerEvent/<prefix>_per_cell_per_event.csv
#                                  Per-file split of the per-event table.
#
#   PART B vis loop (default settings):
#     [combined per-file spatial summary, always emitted]
#     CFU_SpatialPatterns/PerFile/<prefix>_CFU_All_SpatialPresence.png
#                                  Binary union of all CFU footprints.
#     CFU_SpatialPatterns/PerFile/<prefix>_CFU_All_SpatialSum.png
#                                  Weighted sum of all CFU footprints.
#
#     [event-sequence raster, one per file]
#     CFU_EventSequence_Rasters/<prefix>_CFU_EventSequence_Raster_Onsets.png
#                                  All events as ticks, x = time (s),
#                                  y = CFU index.  Hierarchical ordering.
#
#     [per-CFU spatial maps] [per CFU] [PLOT_EVERYTHING]
#     CFU_SpatialPatterns/PerCFU/<prefix>_CFU<N>_SpatialPattern.png
#                                  Per-CFU weighted footprint.
#
#     [pairwise relationships, one per file]
#     CFU_Relationships/CSVs/<prefix>_relationship_table.csv
#                                  Lag table (cfuRelation) -- pairwise
#                                  optimal lag + correlation + p-values.
#     CFU_Relationships/Graphs/<prefix>_relationship_graph.png
#                                  Directed graph of significant edges
#                                  (BH-adjusted, raw-p fallback).
#
#     [groups, only if cfuGroupInfo present in MAT]
#     CFU_Groups/CSVs/<prefix>_groups_membership.csv
#                                  This file's CFU-to-group assignments.
#     CFU_Groups/CSVs/<prefix>_group_event_bursts.csv
#                                  Detected network bursts in this file.
#     CFU_Groups/Waveforms/Raw/<prefix>_Group<G>_Raw.png         (one per group)
#                                  Mean group dF/F0 timecourse, raw time.
#     CFU_Groups/Waveforms/Aligned/<prefix>_Group<G>_Aligned.png (one per group)
#                                  Mean group dF/F0 aligned to burst peak.
#
#     [dF/F0 weighted-average timecourses]
#     WeightedAvg_dFF0/CSVs/<prefix>_*.csv                       Underlying data
#     WeightedAvg_dFF0/Timecourses_Faceted/<prefix>_*.png        Per-CFU panels
#     WeightedAvg_dFF0/Timecourses_Overlaid/<prefix>_*.png       All-CFU overlay
#     WeightedAvg_dFF0/Timecourses_Heatmaps/Raw/<prefix>_*.png   CFU x time
#     WeightedAvg_dFF0/Timecourses_Heatmaps/Norm/<prefix>_*.png  Z-scored
#     WeightedAvg_dFF0/SingleCFUs/<prefix>_CFU<N>.png  [per CFU] Single trace.
#
#     [non-dF/F0 sibling tree, same structure]
#     WeightedAvg_non_dFF0/...    Same files, raw rather than dF/F0.
#
#     [event-window features and annotated overlays]
#     WeightedAvg_dFF0/EventWindows/FeaturePanels/<prefix>_CFUEventFeaturePanel.png
#                                  Summary panel: amplitude / duration /
#                                  rise / decay distributions, per file.
#     WeightedAvg_dFF0/EventWindows/Annotated/Overlay/<prefix>_CFU<N>_PeakAligned.png
#                                  [per CFU] [PLOT_EVERYTHING]  Peak-aligned
#                                  overlay with rise10-90/decay90-10 annotations.
#     WeightedAvg_dFF0/EventWindows/Overlays/<prefix>_CFU<N>_EventOverlay.png
#                                  [per CFU] [PLOT_EVERYTHING]  Legacy plain
#                                  event overlay (backward compat).
#     WeightedAvg_dFF0/EventWindows/PerCFU/<prefix>_*.csv
#                                  Per-event feature metrics: rise, decay,
#                                  AUC, amplitude.
#
# ---- ROUGH VOLUME ESTIMATES -----------------------------------------------
# Per file with PLOT_EVERYTHING=TRUE: ~25 PNGs + ~5 CSVs, ~3-8 MB on disk.
# Per file with PLOT_EVERYTHING=FALSE: ~6 PNGs + ~5 CSVs, ~1-2 MB on disk.
# A 2000-file run at PLOT_EVERYTHING=TRUE is ~50K PNGs and ~10-15 GB.
# At PLOT_EVERYTHING=FALSE, ~12K PNGs and ~2-4 GB.
# ============================================================================

# ============================ AQuA2 CFU ANALYSIS PIPELINE v2.0 (FLAT OUTPUT LAYOUT) ============================
# PRE + POST integration, per-cell summary with frequency + IEI metrics (MeanIEI_sec, IEI_CV)
# POST-CFU visualizations, Directed interaction networks (cfuRelation)
# Group-specific waveform plots (cfuGroupInfo) saved to flat folders (no per-file subfolders)
# Event-centric network burst estimation per group using RAW event times (no delay compensation)
# Consolidated group CSVs with ID1..IDk columns
# Vertical-line overlays of detected group bursts on BOTH Raw and Aligned plots
# Shiny-based manual annotations stored in flat folders:
#   - Bundles:   RESULTS/CFU_Groups/Manual/Waveforms/Bundles
#   - CSVs:      RESULTS/CFU_Groups/Manual/Waveforms/Annotations/<prefix>_manual_group_events.csv
# Manual waveform plots show only manual markers; automatic plots show only automatic markers.
# Spatial maps saved flat (per-CFU and combined per-file presence/sum).
#
# ── PRIOR LINEAGE (LindaDGvsCA) -- archival ──────────────────────────────────────────────────────────────────────────────────────────────────
# v2.0  (2026-04-21) — CONSOLIDATED RELEASE. All v1.x fixes and features merged.
#                       FIX: fts tBegin/tEnd read directly via hdf5r from PRE companion
#                         (.mat v7.3 HDF5); bypasses read_mat_smart() which fails to parse
#                         HDF5 object references in fts1/curve. Path construction corrected
#                         to csv_dir/<VideoID>_results/<prefix>.mat.
#                       FIX: integrate_event_windows_per_cfu() accepts mat_path parameter
#                         so companion PRE file is correctly located at call time.
#                       FIX: cfuRelation graph uses raw-p fallback when BH-adjusted edges
#                         are empty (n_pairs < 10 skips BH entirely).
#                       REMOVED: dir_dff0_annot_perevent (PerEvent folder) — was created
#                         but never written to; now fully removed.
# v1.0  (original)   — Initial pipeline. integrate_event_windows_per_cfu() used
#                       res$fts1$curve$tBegin/tEnd to get Nglob and event windows.
# v1.1  (2026-04-19) — FIX: integrate_event_windows_per_cfu() rewritten.
#                       ROOT CAUSE: new-format _res_cfu.mat files contain no fts/fts1 field.
#                       res$fts1$curve$tBegin returned integer(0) → Nglob = 0 → ALL events
#                       dropped by ev_idx <= Nglob guard → zero event windows generated.
#                       CHANGE 1: Nglob now derived from cfuInfo1 col-6 dFF0 trace length
#                                 (always present in every MAT format version).
#                       CHANGE 2: event_starts/event_ends built as (ev_idx ± half_win)
#                                 clipped to [1, Nglob], replacing tBeg[ev_idx]/tEnd[ev_idx].
#                       NEW PARAM: event_window_sec added to GLOBAL PARAMETERS (default 2.0 s).
#                       All downstream helpers (slice_cfu_event_windows_exact, metrics, plots)
#                       are UNCHANGED — they only consume event_starts / event_ends vectors.
# v1.2  (2026-04-19) — NEW: Per-CFU waveform feature panel plots added.
#                       NEW FUNCTION: plot_cfu_event_feature_panel()
#                         Reads the per-file _CFUEventMetrics.csv written by
#                         integrate_event_windows_per_cfu() and produces a multi-metric
#                         violin + jitter panel (Amplitude, FWHM, AUC, Rise 10-90,
#                         Decay 90-10, Tau) grouped and coloured by CFU_ID.
#                         Saved to: WeightedAvg_dFF0/EventWindows/FeaturePanels/
#                       NEW DIR:   dir_dff0_events_features added to output path tree.
#                       NEW CALL:  plot_cfu_event_feature_panel() called automatically
#                         at the end of the visualization loop (after integrate_event_windows).
#                       NEW TOGGLE: make_feature_panels (default TRUE) in GLOBAL PARAMETERS.
# v3.0  (2026-04-24) — FIX 1: plot_single_cfu now draws grey per-event window traces
#                              behind the black mean timecourse; ev_times always extracted.
#                       FIX 2: mat_prefixes strips _AQuA2 suffix so DG and all non-CA
#                              conditions match correctly and appear in ID1 plots.
#                       FIX 3: cfuRelation adds final fallback (all directed pairs) so
#                              relationship graphs are never empty when pairs exist.
# v2.1  (2026-04-23) — FIX: PRE companion .mat now discovered via recursive list.files()
#                       instead of hardcoded csv_dir/<folder>_results/<name>.mat path.
#                       Previously silently fell back to symmetric half-window whenever
#                       the PRE subfolder structure did not match the assumed convention.
#                       Now consistent with how csv_files/mat_files are found at startup.
# v1.7  (2026-04-21) — FIX: cfuRelation graph now uses raw-p fallback when BH-corrected
#                       edges are empty (critical for small pair counts, e.g. 1-3 pairs
#                       where BH inflates all p_adj to 1.0). Skip BH entirely when
#                       n_pairs < 10. sig criterion corrected to <= rel_alpha (was <).
#                       Graph title and console messages now reflect BH vs raw-p threshold.
# v1.6  (2026-04-19) — FIX: MAT v7.3 (HDF5) support. read_mat_smart() replaces readMat()
#                       in the vis loop. Tries readMat() first (v5/v6); on v7.3 HDF5 error,
#                       opens via hdf5r and converts cfuInfo1 cell array + fts1 curve vectors
#                       into a plain R list identical in structure to readMat() output.
#                       True per-event tBegin/tEnd windows now work for all MAT versions.
#                       Removed: pre_mat_dir, pre_res, PRE file loading.
# v1.5  (2026-04-19) — FIX: cfuRelation shape-invalid warning now only fires when cfuRelation
#                       exists but has wrong dimensions; absent cfuRelation is silently skipped.
# v1.4  (2026-04-19) — REDESIGN: Event window extraction and overlay plot overhauled.
#                       CHANGE 1: True per-event duration from res$fts1$curve$tBegin/tEnd
#                         (or res$fts$curve$tBegin/tEnd) replaces fixed symmetric ±half_win.
#                         Graceful fallback to half_win if fts fields absent/empty.
#                         Each event window now runs from its actual AQuA2-detected onset
#                         to its actual AQuA2-detected offset — no truncation, no padding.
#                       CHANGE 2: Peak-aligned overlay plot.
#                         All individual event traces are shifted so t_peak = 0 on a shared
#                         x-axis.  The mean waveform is computed on this aligned grid.
#                         All bracket/arrow annotations are placed on the aligned mean trace.
#                         One PNG per CFU (not per event).  Per-event PNGs removed.
#                       NEW HELPER: .get_fts_vectors() — extracts tBegin/tEnd/tPeak vectors
#                         from res robustly, trying fts1 then fts then returning NULL.
#                       NEW HELPER: .align_to_peak() — resamples a variable-length event
#                         trace to a common time grid centred on its own peak.
#                       UPDATED: slice_cfu_event_windows_exact() now accepts optional
#                         per_event_tbegin / per_event_tend integer vectors for true-duration
#                         extraction, falling back to the symmetric half_win approach.
#                       REMOVED: per-event annotated PNG loop; PerEvent folder also removed.
#                         created for backward compat but nothing is written to it).
# v1.3  (2026-04-19) — NEW: Fully annotated per-CFU waveform figures.
#                       REPLACED: plot_cfu_event_overlay() and plot_cfu_event_single()
#                         Both replaced with richer annotated versions.
#                       NEW FUNCTION: plot_cfu_annotated_overlay()
#                         Overlaid individual event traces (transparent grey) + mean trace
#                         (black).  Annotated with bracket/segment annotations drawn
#                         directly on the mean waveform:
#                           - Amplitude arrow (baseline → peak)
#                           - FWHM double-headed bracket at half-max
#                           - Rise 10-90% bracket on rising phase
#                           - Decay 90-10% bracket on falling phase
#                           - AUC shaded region under mean trace
#                           - τ (1/e) decay marker
#                         Text label box in upper-right corner with all 7 metrics
#                         + n events.  Saved as one PNG per CFU per file.
#                       NEW FUNCTION: plot_cfu_annotated_single()
#                         Same annotations for a single event trace.
#                       NEW DIRS:
#                         EventWindows/Annotated/Overlay  — one PNG per CFU
#                         EventWindows/Annotated/PerEvent — one PNG per CFU per event
#                       NEW TOGGLE: make_annotated_waveforms (default TRUE)
#                       OLD plot_cfu_event_overlay / plot_cfu_event_single kept as
#                         legacy stubs (called only if make_annotated_waveforms FALSE).
# ───────────────────────────────────────────────────────────────────────────────────────────────────────────
# ========================================================================================================

# ============================================================================
# DEPENDENCY BOOTSTRAP  [v4.12]                                          §3
# ----------------------------------------------------------------------------
# Runs before anything else.  On a fresh machine (e.g. a new EC2 instance)
# this installs every required package: CRAN packages via install.packages,
# and rhdf5 via Bioconductor (it is NOT on CRAN).  When everything is
# already present the checks are instant no-ops, so it is safe to leave in
# for every run.  Set INSTALL_MISSING_DEPS <- FALSE to make a missing
# package a hard error (with the exact install command printed) instead of
# auto-installing -- useful if you want to control installs explicitly on
# a shared/production machine.
INSTALL_MISSING_DEPS <- TRUE

# [v4.22] STALE-HANDLER STUBS -- must come BEFORE any package loads.
# globalCallingHandlers persist across re-sources within one R session.  If a
# previous run's diagnostic warning/message handler is still registered when
# this script is re-sourced, it fires during package loading -- BEFORE the real
# handler infrastructure is rebuilt (defined ~line 3530) and before this run
# even installs its own handler -- and crashes with "object
# '.v49_muffle_patterns' not found" (or '.v48_log_write').  v4.21's in-handler
# guard cannot help, because the handler that fires is the OLD registered one,
# not this version's.  The robust fix: define harmless stubs for everything a
# stale handler could look up, HERE, before the first package load.  The real
# definitions later in the script overwrite these.  (Session > Restart R also
# clears stale handlers; these stubs make a dirty session non-fatal anyway.)
.v49_muffle_patterns <- character(0)               # empty -> stale handler muffles nothing
.v49_muffled_counts  <- list()
.v48_log_write       <- function(...) invisible(NULL)  # no-op until the real logger is set up

# CRAN packages.  [v4.12] Added stringr, cowplot, gridExtra, tibble, shiny
# -- these were used in the code (PART P, plot helpers, manual annotator)
# but were missing from the pre-v4.12 install list, so a fresh machine
# would crash partway through.
pkgs <- c(
  "readr", "dplyr", "ggplot2", "tidyr", "scales", "stringr", "tibble",
  "R.matlab", "hdf5r", "igraph", "ggrepel", "jsonlite",
  "glmnet", "ranger", "FSelectorRcpp", "randomForest",
  "RColorBrewer", "patchwork", "cowplot", "gridExtra",  # [v1.2] panels; [v4.12] cowplot/gridExtra
  "zoo", "ggpubr", "FSA", "ggsignif", "data.table",     # zoo: AUC; ggpubr/FSA/ggsignif: PART P; data.table: fast rbind
  "shiny"                                                # manual group-event annotator (interactive only)
)
# Bioconductor packages (installed via BiocManager, not install.packages).
bioc_pkgs <- c("rhdf5")  # [v4.5] v7.3 .mat backend; hdf5r 1.3.12 H5R deref is broken

# Resolve and (optionally) install anything missing.
.missing_cran <- setdiff(pkgs,      rownames(installed.packages()))
.missing_bioc <- setdiff(bioc_pkgs, rownames(installed.packages()))
if (length(.missing_cran) || length(.missing_bioc)) {
  if (isTRUE(INSTALL_MISSING_DEPS)) {
    if (length(.missing_cran)) {
      message("[deps] Installing missing CRAN packages: ",
              paste(.missing_cran, collapse = ", "))
      install.packages(.missing_cran)
    }
    if (length(.missing_bioc)) {
      if (!requireNamespace("BiocManager", quietly = TRUE))
        install.packages("BiocManager")
      message("[deps] Installing missing Bioconductor packages: ",
              paste(.missing_bioc, collapse = ", "))
      BiocManager::install(.missing_bioc, ask = FALSE, update = FALSE)
    }
  } else {
    stop("Missing required packages and INSTALL_MISSING_DEPS is FALSE.\n",
         if (length(.missing_cran))
           paste0("  CRAN: install.packages(c(",
                  paste(sprintf('\"%s\"', .missing_cran), collapse = ", "), "))\n"),
         if (length(.missing_bioc))
           paste0("  Bioc: BiocManager::install(c(",
                  paste(sprintf('\"%s\"', .missing_bioc), collapse = ", "), "))\n"))
  }
}

# Load quietly
suppressPackageStartupMessages({
  lapply(pkgs, library, character.only = TRUE)
})

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(tidyr)
  library(scales)
  library(R.matlab)
  if (requireNamespace("hdf5r", quietly = TRUE)) library(hdf5r)
  if (requireNamespace("rhdf5", quietly = TRUE)) library(rhdf5)  # [v4.5]
  library(igraph)
  library(ggrepel)
  library(jsonlite)
  library(grid) # for unit()
  library(glmnet)
  library(ranger)
  library(FSelectorRcpp)
  library(randomForest)
  library(RColorBrewer)  # [v1.2]
  library(patchwork)     # [v1.2]
})

# [v4.10] Single source of truth for the script version, used in diagnostic
# file naming, the JSON `version` field, and user-facing log messages.
# Bumping this on each release keeps the diagnostic artifacts correctly
# labelled without having to grep-and-replace the version across the file.
SCRIPT_VERSION <- "v4.27"

# [v4.11] Production-scale knobs.
#   GC_EVERY_N_FILES   -- call gc() every N files in Part A / per-event /
#                         vis loops.  Bounds memory growth over long runs.
#                         0 disables.
#   CHECKPOINT_RESUME  -- if TRUE and <out_dir>/<analysis_name>_checkpoint.txt
#                         exists, prefixes listed there are skipped.  Set
#                         FALSE (or delete the checkpoint file) to redo.
#   PLOT_EVERYTHING    -- TRUE = v4.10 behaviour (every per-CFU plot).
#                         FALSE = scale-friendly: skip per-CFU spatial maps
#                         and per-CFU peak-aligned waveforms.  Summary,
#                         group, and relationship plots still emit.  At
#                         ~2000 files this saves ~30x on PNG output volume.
GC_EVERY_N_FILES  <- 25L
CHECKPOINT_RESUME <- TRUE
PLOT_EVERYTHING   <- TRUE

# [v4.18] PARALLEL SHARDING (process-level).  rhdf5 is NOT thread-safe, so we
# parallelize across independent OS PROCESSES, never threads.  TOGGLEABLE:
# with SHARDING_ENABLED = FALSE this is byte-for-byte the v4.17 single-process
# pipeline (and that is also what happens when the script is sourced in
# RStudio with no command-line args).
#   Workflow when ON (see companion launcher Run-Sharded.ps1):
#     STAGE 1 -- launch SHARD_COUNT processes, each SHARD_STAGE="process" with a
#       distinct SHARD_INDEX (1..N).  Each handles its 1/N slice of recordings,
#       running the full per-file work (Part A/A2/B incl. ALL plots) and writing
#       shard-suffixed per-cell/per-event CSVs + its own checkpoint.  Per-file
#       PNGs go to the shared out_dir (filenames are per-recording, so shards
#       never collide).  Modeling/PART P is skipped in this stage.
#     STAGE 2 -- after all shards finish, run ONE process SHARD_STAGE="aggregate":
#       it does NO per-file work; it merges the shard CSVs into the master
#       summaries and runs modeling + PART P once on the full dataset.
# Sharding by row index of the (sorted, paired) recording table => a given
# recording is handled by exactly one shard across Part A / A2 / B.
SHARDING_ENABLED <- FALSE      # master toggle; FALSE = identical to v4.17
SHARD_STAGE      <- "process"  # "process" | "aggregate"  (ignored when disabled)
SHARD_COUNT      <- 8L         # number of parallel shard processes
SHARD_INDEX      <- 1L         # 1..SHARD_COUNT: which shard THIS process runs
# Launcher override: `Rscript script.R <stage> <count> <index>` turns sharding
# on and sets the three values.  No args (e.g. RStudio source) => defaults above.
local({
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 3L && a[1] %in% c("process", "aggregate")) {
    SHARDING_ENABLED <<- TRUE
    SHARD_STAGE      <<- a[1]
    SHARD_COUNT      <<- as.integer(a[2])
    SHARD_INDEX      <<- as.integer(a[3])
  }
})
.shard_active_process <- isTRUE(SHARDING_ENABLED) && identical(SHARD_STAGE, "process") && SHARD_COUNT > 1L
.shard_sfx <- if (.shard_active_process) sprintf("_shard%02d", SHARD_INDEX) else ""

# [v4.23] FAST MODE / SCOPE FILTERS / PRISM EXPORT --------------------------
# FAST_MODE is a single master toggle that flips the script into a
# "CSV-only, skip the slow visualisations" configuration.  When TRUE the
# per-file vis loop (Part B), the per-event summary (Part A2), and the RF
# modeling + PART P group plots are all skipped, leaving Part A's
# per_cell_summary CSV as the primary output -- plus the new PRISM-friendly
# wide-format export below.  Override individual SKIP_* toggles AFTER
# FAST_MODE if you need a mix.
FAST_MODE <- FALSE   # [v4.27] FALSE = all outputs (Part B vis, Part A2 per-event, modeling + PART P). Dataset is only 30 files, so full output is cheap.
if (isTRUE(FAST_MODE)) {
  SKIP_PARTB_VIS          <- TRUE   # skip the per-file visualization loop entirely
  SKIP_PARTA2             <- TRUE   # skip the per-event summary loop (Part A2)
  SKIP_MODELING_AND_PARTP <- TRUE   # skip RF modeling + PART P distribution plots
  PLOT_EVERYTHING         <- FALSE  # per-CFU plots off (only relevant if Part B runs)
} else {
  SKIP_PARTB_VIS          <- FALSE
  SKIP_PARTA2             <- FALSE
  SKIP_MODELING_AND_PARTP <- FALSE
}

# Recording-level scope filters, applied to the paired table AFTER pairing.
# NULL = keep all values for that field.
# [v4.27] FOXP1 dataset: the only meaningful scope factor is genotype (WT/HET),
# carried in Condition.  Donor / Timepoint / Promoter do not exist in these
# filenames, so their filters are set NULL -- leaving them as the assembloid
# values (e.g. INCLUDE_DONORS=c("1","4")) would silently drop EVERY FOXP1
# recording, exactly the failure the v4.25 notes warn about.
INCLUDE_DONORS      <- NULL                       # [v4.27] no donor token in FOXP1 names
INCLUDE_CONDITIONS  <- c("WT", "HET")             # [v4.27] genotype = condition
INCLUDE_TIMEPOINTS  <- NULL                       # [v4.27] no age/timepoint token
INCLUDE_PROMOTERS   <- NULL                       # [v4.26] NULL = keep all

# [v4.26] Known promoter tokens recognised by parse_stem (case-insensitive
# match against the underscore-split filename tokens).  Add to this vector
# to teach the parser about additional promoters; the matched token is
# uppercased before being stored.  Anything not in this list is silently
# ignored at parse time (Promoter stays NA), which is the safe default.
PROMOTER_TOKENS <- c("CAMK2A", "CAMKIIA", "DLX", "GFAP", "SYN", "SYN1",
                     "VGLUT1", "VGLUT2", "CAG", "EF1A", "TRE")

# PRISM-friendly export: for each numeric metric in per_cell_summary, write a
# wide-format CSV (columns = Control / GoF / LoF, rows = cell observations)
# under <out_dir>/PRISM/<cohort>/.  Cohorts: Donor1, Donor4, Combined.
# Designed to drop straight into a GraphPad PRISM Column Table.
PRISM_EXPORT <- TRUE
# [v4.26] When TRUE, ALSO write per-promoter cohorts (e.g. Donor1_CAMK2A,
# Combined_DLX) alongside the promoter-mixed cohorts above.  Only the
# promoter values actually present in the data become folders.
PRISM_BY_PROMOTER <- TRUE
write_prism_exports <- function(per_cell_csv_path, out_root, df = NULL) {
  if (is.null(df)) {
    if (!file.exists(per_cell_csv_path)) {
      message("[v4.23] PRISM export skipped: per-cell summary not found at ", per_cell_csv_path)
      return(invisible(NULL))
    }
    df <- data.table::fread(per_cell_csv_path)
  }
  df <- as.data.frame(df)
  # [v4.27] FOXP1 build: cohorts are genotype (WT/HET), not donor/condition.
  # The per-cell summary carries Condition = genotype (WT/HET) and a Genotype
  # column; there is no Donor.  Require Condition (= genotype) only.
  if (!("Condition" %in% names(df))) {
    message("[v4.27] PRISM export skipped: per-cell summary lacks Condition column.")
    return(invisible(NULL))
  }
  # WT/HET are already the PRISM column labels; identity map.
  cond_map <- c("WT" = "WT", "HET" = "HET")
  df$.CondLabel <- cond_map[as.character(df$Condition)]
  # Identify metric columns: numeric & not metadata / ID-style
  meta <- c("File","Donor","Condition","Genotype","DonorCond",".CondLabel","AgeDay",
            "Timepoint","CondTimepoint","Mag","NominalHz","EffectiveHz","Tissue",
            "Promoter","Organoid","View","SampleID","Video","CFU_ID",
            paste0("ID", 1:20))
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  metric_cols <- setdiff(num_cols, meta)
  if (length(metric_cols) == 0L) {
    message("[v4.23] PRISM export: no numeric metric columns found.")
    return(invisible(NULL))
  }
  # [v4.27] Single cohort for FOXP1 (no donor split).  Two PRISM columns:
  # WT and HET, cells as rows, NA-padded -- drop straight into a Column Table.
  cohorts <- list(Combined = df)
  cond_order <- c("WT", "HET")
  prism_root <- file.path(out_root, "PRISM")
  dir.create(prism_root, recursive = TRUE, showWarnings = FALSE)
  total <- 0L
  for (chn in names(cohorts)) {
    sub <- cohorts[[chn]]
    if (nrow(sub) == 0L) {
      message(sprintf("[v4.23] PRISM: cohort %s has 0 rows; skipping.", chn)); next
    }
    cohort_dir <- file.path(prism_root, chn)
    dir.create(cohort_dir, recursive = TRUE, showWarnings = FALSE)
    n_cohort <- 0L
    for (m in metric_cols) {
      vals_by_cond <- split(sub[[m]], sub$.CondLabel)
      vals_by_cond <- vals_by_cond[cond_order[cond_order %in% names(vals_by_cond)]]
      if (length(vals_by_cond) == 0L) next
      maxN <- max(vapply(vals_by_cond, length, integer(1)))
      out_df <- as.data.frame(
        lapply(vals_by_cond, function(v) c(v, rep(NA_real_, maxN - length(v)))),
        stringsAsFactors = FALSE, check.names = FALSE)
      fn_safe <- gsub("[^A-Za-z0-9._-]+", "_", m)
      data.table::fwrite(out_df, file.path(cohort_dir, paste0(fn_safe, ".csv")))
      n_cohort <- n_cohort + 1L
    }
    message(sprintf("[v4.23] PRISM: %s -> %d metric CSV(s) in %s",
                    chn, n_cohort, cohort_dir))
    total <- total + n_cohort
  }
  message(sprintf("[v4.23] PRISM export complete: %d CSV(s) under %s",
                  total, prism_root))
  invisible(prism_root)
}

AnalysisName <- "FOXP1_WT_HET"

# --------------------------------------- GLOBAL PARAMETERS ---------------------------------------
# §4 -- Run-time configuration knobs.  Edit these before sourcing the
# script to control inputs, output paths, and behaviour.
#   AnalysisName / csv_dir / mat_dir / out_dir
#                          Identify the run and locate inputs/outputs.
#   TEST_MODE / TEST_N / TEST_SEED
#                          When TEST_MODE=TRUE, processes a stratified
#                          random subset of TEST_N recordings (seed-
#                          reproducible) rather than all available.
#                          Keep on for development; flip off for the
#                          full run.
#   GROUPING_VARS          Columns the modeling/PART P pass uses as
#                          targets, one pass per entry (default
#                          c("Condition","DonorCond")).
#   GC_EVERY_N_FILES / CHECKPOINT_RESUME / PLOT_EVERYTHING  [v4.11]
#                          Scale-run knobs documented above.
#   png_dpi, label_size, plot themes, event-coincidence clustering
#   thresholds, and burst-detection parameters are all set here.
# I/O
# [v4.25 Windows / Assembloids 20x build] active paths point at the Assembloids
# dataset on the EC2 instance; Mac CalciumTesting test paths retained below,
# commented, for switch-back, and the hCO Windows paths kept as historical.
# [v4.27 FOXP1 WT/HET build] active paths point at the FOXP1 dataset on the EC2
# instance.  The lane pipeline wrote PRE companions (_AQuA2.mat) into each
# lane##_results folder and POST standalone _res_cfu.mat into _CFU_POST.  For
# this analysis both the POST results and the PRE companions are discovered by
# recursive scan, so csv_dir / companion_mat_dir point at the lanes root (which
# CONTAINS all lane##_results folders) and mat_dir points at _CFU_POST.
csv_dir <- "C:/Users/Administrator/Desktop/CarolDataPOGZ_lanes/"        # [v4.27] PRE CSVs + _AQuA2.mat companions live in lane##_results (recursive)
# csv_dir <- "/Volumes/Arvin2TBsd/CalciumTesting/PreCFU_hCO/"           # [v4.20] local test (Mac)
mat_dir   <- "C:/Users/Administrator/Desktop/CarolDataPOGZ_lanes/_CFU_POST/"   # [v4.27] POST _res_cfu.mat (CFU outputs) for FOXP1
# mat_dir <- "/Volumes/Arvin2TBsd/CalciumTesting/POST/"                 # [v4.20] local test (Mac)
companion_mat_dir <- "C:/Users/Administrator/Desktop/CarolDataPOGZ_lanes/"     # [v4.27] fts source = _AQuA2.mat files in lane##_results (recursive)
# companion_mat_dir <- "/Volumes/Arvin2TBsd/CalciumTesting/PreCFU_hCO/" # [v4.20] local test (Mac)
out_dir <- "C:/Users/Administrator/Desktop/CarolDataPOGZ_lanes/RESULTS_FOXP1/" # [v4.27] dedicated results tree for FOXP1 WT/HET
# out_dir <- "/Volumes/Arvin2TBsd/CalciumTesting/RESULTS/"              # [v4.20] local test (Mac)

# -- [hCO] TEST MODE + GROUPING (added) ---------------------------------------
# [v4.14] Kept TRUE deliberately for ONE validation pass on the Windows
# instance -- confirms the new C:/ paths resolve, v4.12 deps install, the
# v4.13 self-test passes on the real first file, and a handful of files
# process end-to-end with a clean diagnostics JSON.  Once that run looks
# good, set this to FALSE for the full 1,191-file run.  (The startup
# "RUN CONFIG" banner echoes this value so you can confirm which mode you're
# actually in.)
TEST_MODE <- FALSE     # [v4.27] FALSE = all 30 FOXP1 recordings (small dataset; no subset needed)
TEST_N    <- 10L       # recordings to sample when TEST_MODE = TRUE
TEST_SEED <- 1L        # reproducible sample
# [v4.27] FOXP1 dataset has ONE factor of interest (genotype WT vs HET, carried
# in Condition) and a sampling-unit factor (Organoid; Views are pseudoreplicate
# fields of one organoid).  Group by Condition only.  Donor / Timepoint /
# CondTimepoint are not meaningful here (no donor or age token in the
# filenames) and are dropped so PART P / modeling don't run empty passes.
GROUPING_VARS <- c("Condition")   # [v4.27] WT vs HET
META_COLS <- c("Condition","Genotype","Organoid","View","SampleID","EffectiveHz")

# [v4.16] DEVELOPMENTAL TIMEPOINT BINNING ------------------------------------
# Filenames carry an age token (d80, d100, d121, ...), parsed as AgeDay.
# Group recordings into developmental timepoints by day window.  Ranges are
# inclusive and contiguous (no gaps between 60 and 140):
#   ~D80  = 60-90, ~D100 = 91-109, ~D120 = 110-140.
# D80 and D120 are the primary cohorts; D100 ("~day 100ish") is tracked
# separately per [v4.17] since only some files/conditions have it.
#
# NOTE [v4.17]: days OUTSIDE all three windows (i.e. < 60 or > 140) get
# Timepoint = NA ("unbinned") and are dropped from Timepoint / CondTimepoint
# grouped analyses.  The pairing step prints an unbinned tally so any such
# stragglers are visible.  Edit TIMEPOINT_BINS to change windows; tighten
# D100 (e.g. 95-105) if you want a stricter "100ish" and don't mind
# reintroducing small gaps.
TIMEPOINT_BINS <- list(
  D80  = c(60,  90),    # ~day 80  cohort (primary)
  D100 = c(91,  109),   # ~day 100 cohort (fills the 91-109 gap; tracked separately)
  D120 = c(110, 140)    # ~day 120 cohort (primary)
)
assign_timepoint <- function(age_day) {
  if (is.null(age_day) || length(age_day) == 0L) return(NA_character_)
  d <- suppressWarnings(as.numeric(age_day))[1]
  if (!is.finite(d)) return(NA_character_)
  for (nm in names(TIMEPOINT_BINS)) {
    rng <- TIMEPOINT_BINS[[nm]]
    if (d >= rng[1] && d <= rng[2]) return(nm)
  }
  NA_character_   # outside all windows -> unbinned
}

# Temporal & spatial resolution
# [v4.27] FOXP1 recordings are acquired at 1.55 Hz -> 0.645 s/frame (NOT the
# 0.05 s/frame / 20 Hz used for the assembloid build).  Every temporal metric
# (event duration, IEI, rise/decay times in seconds) scales with this, so it
# MUST match the acquisition rate of this dataset.  All 30 files are 1.55 Hz
# (EffectiveHz token), so a single global value is correct here.
frame_interval <- 0.645  # seconds per frame (1 / 1.55 Hz)
frame_rate     <- 1 / frame_interval

# [v4.15] Spatial calibration (um per pixel), magnification-dependent.
# [v4.16] The dataset is MIXED magnification -- it contains 10x AND 20x
# recordings (e.g. 1L_d80_10x, 4G_d80_10x alongside the 20x files).  20x =
# 2.6 um/px on this rig; 10x covers ~2x the field per pixel, so ~5.2 um/px
# (geometric expectation -- CONFIRM against your microscope/camera spec, as
# binning can change it).  Keyed on the parsed Mag token (uppercased, e.g.
# "20X"/"10X").  resolve_um_per_pixel() falls back to UM_PER_PIXEL_DEFAULT
# for any unrecognized/missing mag.
UM_PER_PIXEL_BY_MAG  <- c("20X" = 2.6, "10X" = 5.2)   # [v4.16] 10X value PENDING CONFIRMATION
UM_PER_PIXEL_DEFAULT <- 2.6   # used when Mag is absent/unrecognized
resolve_um_per_pixel <- function(mag) {
  if (is.null(mag) || length(mag) == 0L || is.na(mag)) return(UM_PER_PIXEL_DEFAULT)
  key <- toupper(as.character(mag))
  if (key %in% names(UM_PER_PIXEL_BY_MAG)) unname(UM_PER_PIXEL_BY_MAG[[key]])
  else UM_PER_PIXEL_DEFAULT
}
# NOTE [v4.16]: because the dataset is mixed-mag, there is NO single correct
# um_per_pixel for the whole run -- it must be resolved PER FILE from that
# file's Mag (resolve_um_per_pixel(meta$Mag)) wherever it eventually gets
# wired into a spatial computation.  The global below is only a default
# placeholder; do not use it as a blanket scale factor across files.
# As of this version nothing consumes um_per_pixel yet (maps/footprints are
# still in pixel units), so this remains calibration-only.
um_per_pixel <- UM_PER_PIXEL_DEFAULT   # [v4.16] placeholder default; resolve per-file when wired in

# Plotting + export
png_dpi <- 300
save_long_csv <- TRUE

# PRE/POST waveform & heatmap toggles
make_overlaid_lines <- TRUE
make_faceted_lines  <- TRUE
make_heatmap        <- TRUE
make_raster         <- TRUE
make_single_cfu     <- TRUE
use_z_for_lines     <- TRUE
single_cfu_show_event_lines <- FALSE  # toggle single-CFU vertical event markers


# Spatial color scaling for spatial maps
spatial_use_filewide_scale <- TRUE
spatial_upper_quantile     <- 0.99

# Relationship graph settings (cfuRelation)
rel_make_graphs      <- TRUE
rel_alpha            <- 0.05
rel_drop_zero_delays <- TRUE
rel_epsilon_sec      <- frame_interval/2
rel_trim_delay_q     <- 0.99
rel_max_label_nodes  <- 10

# Group waveform plotting (cfuGroupInfo)
grp_plot_waveforms      <- TRUE
grp_wave_use_dff0       <- TRUE   # TRUE: use col 6 dF/F0; FALSE: use col 5 non-dF/F0
grp_wave_zscore_per_cfu <- TRUE   # z-score each CFU trace to compare shapes
grp_wave_alpha          <- 0.7
grp_wave_lwd            <- 0.5
grp_wave_mean_lwd       <- 0.9

# -------- Event-coincidence clustering (network bursts) --------
grp_burst_enable            <- TRUE
grp_burst_tau_sec           <- 2
grp_burst_refractory_sec    <- 0.8
grp_burst_min_fraction      <- 0.6
grp_burst_min_participating <- NA

# -------- Visual overlay on BOTH plots (detected group bursts from RAW-time clustering) --------
grp_burst_overlay_enable   <- TRUE
grp_burst_marker_color     <- "#222222"
grp_burst_marker_alpha     <- 0.7
grp_burst_marker_lwd       <- 0.6
grp_burst_overlay_subtitle <- "Vertical lines = raw-time clustered group events"

make_event_windows      <- TRUE
event_use_dff0          <- TRUE     # Use dF/F0 (col 6); FALSE = non-dF/F0 (col 5)
event_pre_sec           <- 0        # [v1.0 legacy - no longer used by integrate_event_windows_per_cfu]
event_post_sec          <- 0        # [v1.0 legacy - no longer used by integrate_event_windows_per_cfu]
event_baseline_sec      <- 1.0      # Baseline window (seconds) for baseline subtraction per window
event_zscore_per_window <- FALSE    # Whether to z-score each event window

# [v1.1 NEW] Half-window size for event extraction (replaces tBeg/tEnd lookup from fts1).
# Total window centred on onset = 2 * event_window_sec worth of frames.
# If migrating from v1.0: set to (event_pre_sec + event_post_sec) / 2.
event_window_sec <- 2.0

# [v1.2 NEW] Per-CFU event feature panel plots (violin + jitter per metric).
# Reads _CFUEventMetrics.csv and plots Amplitude, FWHM, AUC, Rise, Decay, Tau per CFU.
make_feature_panels          <- TRUE
feature_panel_min_events     <- 2L    # Min events per CFU to include in panel
feature_panel_point_alpha    <- 0.55  # Jitter point transparency
feature_panel_point_size     <- 1.2   # Jitter point size
feature_panel_violin_alpha   <- 0.35  # Violin fill transparency

# [v1.3 NEW] Annotated waveform figures (per-CFU overlay + per-event single)
make_annotated_waveforms       <- TRUE   # Master toggle
annot_individual_alpha         <- 0.25   # Transparency of individual grey traces
annot_individual_lwd           <- 0.35   # Line width of individual grey traces
annot_mean_lwd                 <- 1.4    # Line width of mean black trace
annot_auc_fill                 <- "#4393C3"  # AUC shaded fill colour
annot_auc_alpha                <- 0.18   # AUC shaded fill transparency
annot_bracket_color            <- "#222222"  # Bracket/arrow annotation colour
annot_bracket_lwd              <- 0.55   # Bracket line width
annot_label_size               <- 3.0    # Text annotation size (pts)

# [v1.4 NEW] Peak-aligned overlay parameters
annot_peak_align               <- TRUE   # Align all events to their own peak (t_peak = 0)
annot_align_pre_sec            <- 1.0    # Seconds to show before peak on aligned axis
annot_align_post_sec           <- 3.0    # Seconds to show after  peak on aligned axis
annot_align_interp_dt          <- NULL   # Resampling interval (NULL = use frame_interval)
# [v1.4] True-duration extraction: use res$fts1/fts tBegin/tEnd per event
#   TRUE  = use actual AQuA2 event start/end (variable duration per event)
#   FALSE = fall back to symmetric ±event_window_sec half-window (v1.1 behaviour)
event_use_true_duration        <- TRUE


# --------------------------------------- GLOBAL THEME ---------------------------------------
theme_set(theme_minimal(base_size = 12, base_family = "Arial"))
theme_axes_black <- function(base_size = 12, base_family = "Arial") {
  theme(
    text = element_text(family = base_family, size = base_size, color = "black"),
    panel.grid = element_blank(),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    panel.border = element_blank(),
    axis.line = element_line(color = "black", linewidth = 0.4),
    axis.ticks = element_line(color = "black", linewidth = 0.4),
    axis.title = element_text(color = "black", size = base_size),
    axis.text = element_text(color = "black", size = base_size * 0.85),
    plot.title = element_text(color = "black", hjust = 0, face = "plain", size = base_size * 1.1),
    legend.title = element_text(color = "black", size = base_size * 0.9),
    legend.text  = element_text(color = "black", size = base_size * 0.85)
  )
}

# --------------------------------------- OUTPUT PATHS (FLAT LAYOUT) ---------------------------------------
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(out_dir)) stop("Failed to create output directory: ", out_dir)
if (file.access(out_dir, 2) != 0) stop("Output directory is not writable: ", out_dir)

out_csv <- file.path(out_dir, paste0(AnalysisName, "_per_cell_summary", .shard_sfx, ".csv"))  # [v4.18] shard-suffixed in process stage
setwd(out_dir)

# dF/F0 tree
dir_dff0_root      <- file.path(out_dir, "WeightedAvg_dFF0")
dir_dff0_csv       <- file.path(dir_dff0_root, "CSVs")
dir_dff0_overlaid  <- file.path(dir_dff0_root, "Timecourses_Overlaid")
dir_dff0_faceted   <- file.path(dir_dff0_root, "Timecourses_Faceted")
dir_dff0_heat_root <- file.path(dir_dff0_root, "Timecourses_Heatmaps")
dir_dff0_heat_raw  <- file.path(dir_dff0_heat_root, "Raw")
dir_dff0_heat_norm <- file.path(dir_dff0_heat_root, "Norm")
dir_dff0_singlecfu <- file.path(dir_dff0_root, "SingleCFUs")

# non-dF/F0 tree
dir_nond_root      <- file.path(out_dir, "WeightedAvg_non_dFF0")
dir_nond_csv       <- file.path(dir_nond_root, "CSVs")
dir_nond_overlaid  <- file.path(dir_nond_root, "Timecourses_Overlaid")
dir_nond_faceted   <- file.path(dir_nond_root, "Timecourses_Faceted")
dir_nond_heat_root <- file.path(dir_nond_root, "Timecourses_Heatmaps")
dir_nond_heat_raw  <- file.path(dir_nond_heat_root, "Raw")
dir_nond_singlecfu <- file.path(dir_nond_root, "SingleCFUs")

# Others
dir_spatial_root <- file.path(out_dir, "CFU_SpatialPatterns")
dir_raster_root  <- file.path(out_dir, "CFU_EventSequence_Rasters")

# Relationships
dir_rel_root   <- file.path(out_dir, "CFU_Relationships")
dir_rel_csv    <- file.path(dir_rel_root, "CSVs")
dir_rel_graphs <- file.path(dir_rel_root, "Graphs")

# Groups (flat outputs)
dir_grp_root          <- file.path(out_dir, "CFU_Groups")
dir_grp_csv           <- file.path(dir_grp_root, "CSVs")
dir_grp_wave          <- file.path(dir_grp_root, "Waveforms")
dir_grp_wave_aligned  <- file.path(dir_grp_wave, "Aligned")
dir_grp_wave_raw      <- file.path(dir_grp_wave, "Raw")

# Manual (flat outputs)
dir_grp_manual_root    <- file.path(dir_grp_root, "Manual")
dir_grp_manual_wave    <- file.path(dir_grp_manual_root, "Waveforms")
dir_grp_manual_aligned <- file.path(dir_grp_manual_wave, "Aligned")
dir_grp_manual_raw     <- file.path(dir_grp_manual_wave, "Raw")
dir_grp_manual_bundles <- file.path(dir_grp_manual_wave, "Bundles")
dir_grp_manual_csvs    <- file.path(dir_grp_manual_wave, "Annotations")

# CFU spatial (flat per-file and per-CFU)
dir_spatial_perfile <- file.path(dir_spatial_root, "PerFile")
dir_spatial_percfu  <- file.path(dir_spatial_root, "PerCFU")

# New EventWindows folders
dir_dff0_events_root     <- file.path(dir_dff0_root, "EventWindows")
dir_dff0_events_overlay  <- file.path(dir_dff0_events_root, "Overlays")
dir_dff0_events_percfu   <- file.path(dir_dff0_events_root, "PerCFU")
dir_dff0_events_features      <- file.path(dir_dff0_events_root, "FeaturePanels")   # [v1.2]
dir_dff0_annot_root           <- file.path(dir_dff0_events_root, "Annotated")          # [v1.3]
dir_dff0_annot_overlay        <- file.path(dir_dff0_annot_root,  "Overlay")             # [v1.3]

invisible(lapply(
  c(dir_dff0_events_root, dir_dff0_events_overlay,
    dir_dff0_events_percfu, dir_dff0_events_features,
    dir_dff0_annot_root, dir_dff0_annot_overlay),  # [v1.3]
  function(d) if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
))

# Create output dirs
invisible(lapply(
  c(dir_dff0_root, dir_dff0_csv, dir_dff0_overlaid, dir_dff0_faceted,
    dir_dff0_heat_root, dir_dff0_heat_raw, dir_dff0_heat_norm, dir_dff0_singlecfu,
    dir_nond_root, dir_nond_csv, dir_nond_overlaid, dir_nond_faceted,
    dir_nond_heat_root, dir_nond_heat_raw, dir_nond_singlecfu,
    dir_spatial_root, dir_spatial_perfile, dir_spatial_percfu, dir_raster_root,
    dir_rel_root, dir_rel_csv, dir_rel_graphs,
    dir_grp_root, dir_grp_csv, dir_grp_wave, dir_grp_wave_aligned, dir_grp_wave_raw,
    dir_grp_manual_root, dir_grp_manual_wave, dir_grp_manual_aligned, dir_grp_manual_raw,
    dir_grp_manual_bundles, dir_grp_manual_csvs),
  function(d) if (!dir.exists(d)) dir.create(d, recursive = TRUE)
))

# --------------------------------------- HELPERS ---------------------------------------
# §8 -- Small utility functions shared across the pipeline:
#   parse_stems()          File-stem parser.  Extracts Donor / Condition /
#                          Concentration / Magnification / SamplingRate /
#                          Tissue / Organoid / VideoID from the conventional
#                          AQuA2 filename pattern.  Position-independent
#                          and validated against current naming.
#   pre_mat_index()        O(1) PRE-companion .mat lookup table.  Replaces
#                          the original recursive list.files() per file.
#   to_numeric_vec() / to_numeric_matrix()
#                          Robust coercion of cell-array contents to
#                          plain R vectors/matrices.  Handles the various
#                          shapes MATLAB writes (lists of arrays, single
#                          scalars in 1x1 matrices, NULL).
#   calc_iei_stats()       Inter-event-interval mean and CV from a
#                          numeric vector of event times.
#   Plus internal log helpers used by the diagnostic apparatus.
to_numeric_vec <- function(x) {
  if (is.null(x)) return(numeric(0))
  if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
  if (is.array(x) || is.matrix(x)) x <- as.vector(x)
  x <- suppressWarnings(as.numeric(x))
  x[is.finite(x)]
}

# --- [v4.27 FOXP1] stem parser for the FOXP1 WT/HET naming convention --------
# Filenames look like:  FOXP1WT4_1_1.55Hz   /   FOXP1HET2_3_1.55Hz
#   token 1 : FOXP1<GENO><ORG>   -> Genotype (WT|HET) + Organoid number
#   token 2 : <VIEW>             -> bare integer = field/view of that organoid
#   token 3 : <rate>Hz           -> EffectiveHz (1.55)
# Genotype is mapped onto the pipeline's Condition column (so all the existing
# Condition-based grouping, PART P, and modeling work unchanged), with a
# dedicated Genotype column kept too for clarity.  SampleID = Genotype+Organoid
# (e.g. "WT4") is the ORGANOID-level sampling unit; Views are pseudoreplicates
# pooled within a SampleID.  No donor / age / promoter / magnification tokens
# exist in this dataset, so those columns are NA by construction.
parse_stem <- function(stem) {
  toks <- strsplit(stem, "_", fixed = TRUE)[[1]]
  toks <- toks[nzchar(toks)]

  # First token carries genotype + organoid, e.g. FOXP1WT4 or FOXP1HET2.
  geno <- NA_character_; org <- NA_integer_
  gtok <- toks[grepl("^FOXP1(WT|HET)[0-9]+$", toks, ignore.case = TRUE)]
  if (length(gtok)) {
    g <- toupper(gtok[1])
    geno <- sub("^FOXP1(WT|HET)[0-9]+$", "\\1", g)            # WT | HET
    org  <- suppressWarnings(as.integer(sub("^FOXP1(?:WT|HET)([0-9]+)$", "\\1", g)))
  }

  # View = the bare-integer token (the field number).  Take the first standalone
  # integer token that is NOT part of the genotype token and NOT a Hz value.
  int_toks <- toks[grepl("^[0-9]+$", toks)]
  view <- if (length(int_toks)) suppressWarnings(as.integer(int_toks[1])) else NA_integer_

  # Acquisition rate token, e.g. 1.55Hz.
  hz_tok <- toks[grepl("^[0-9.]+[Hh][Zz]$", toks)]
  hz_val <- suppressWarnings(as.numeric(sub("[Hh][Zz]$", "", hz_tok)))
  hz_val <- hz_val[is.finite(hz_val)]

  sample_id <- if (!is.na(geno) && !is.na(org)) paste0(geno, org) else NA_character_

  data.frame(
    Donor         = NA_character_,                 # [v4.27] no donor in FOXP1 names
    Condition     = geno,                          # [v4.27] genotype drives Condition (WT/HET)
    Genotype      = geno,                          # [v4.27] explicit copy for clarity
    DonorCond     = NA_character_,
    AgeDay        = NA_real_,
    Timepoint     = NA_character_,
    CondTimepoint = NA_character_,
    Mag           = NA_character_,
    NominalHz     = NA_real_,
    EffectiveHz   = if (length(hz_val)) hz_val[1] else NA_real_,
    Tissue        = "Organoid",
    Promoter      = NA_character_,
    Organoid      = org,                           # [v4.27] organoid number (sampling unit w/ Genotype)
    View          = view,                          # [v4.27] field/view = pseudoreplicate within organoid
    SampleID      = sample_id,                     # [v4.27] organoid-level unit, e.g. "WT4"
    Video         = view,                          # keep legacy Video column = View for any downstream refs
    stringsAsFactors = FALSE
  )
}
parse_stems <- function(stems) do.call(rbind, lapply(stems, parse_stem))

# --- [hCO v1] regex-safe O(1) PRE-companion lookup --------------------------
get_pre_companion <- function(stem_aqua2) {
  if (exists("pre_mat_index", inherits = TRUE)) {
    p <- pre_mat_index[[stem_aqua2]]
    if (!is.null(p) && !is.na(p) && file.exists(p)) return(p)
  }
  esc <- gsub("([][{}().^$*+?\\\\|])", "\\\\\\1", stem_aqua2)   # escape "." in 19.23Hz
  hit <- list.files(companion_mat_dir, pattern = paste0("^", esc, "\\.mat$"),  # [v4.14] was csv_dir
                    full.names = TRUE, recursive = TRUE)
  if (length(hit)) hit[1] else NULL
}

get_cfuinfo <- function(m) {
  if ("cfuInfo1" %in% names(m)) return(m$cfuInfo1)
  if ("cfuInfo"  %in% names(m)) return(m$cfuInfo)
  NULL
}
get_cfu_relation  <- function(m) if ("cfuRelation"  %in% names(m)) m$cfuRelation else NULL
get_cfu_groupinfo <- function(m) if ("cfuGroupInfo" %in% names(m)) m$cfuGroupInfo else NULL

to_binary_sequence <- function(x, nT) {
  if (is.null(x)) return(numeric(0))
  if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
  if (is.array(x) || is.matrix(x)) x <- as.vector(x)
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0) return(numeric(0))
  if (all(x %in% c(0,1)) && length(x) == nT) return(as.numeric(x))
  idx <- unique(round(x)); idx <- idx[idx >= 1 & idx <= nT]
  if (length(idx) == 0) return(numeric(0))
  y <- numeric(nT); y[idx] <- 1; y
}

to_numeric_matrix <- function(x) {
  if (is.null(x)) return(matrix(numeric(0), 0, 0))
  if (is.list(x)) x <- x[[1]]
  if (is.array(x) && length(dim(x)) == 2) {
    m <- suppressWarnings(matrix(as.numeric(x), nrow = nrow(x), ncol = ncol(x)))
    m[!is.finite(m)] <- 0; return(m)
  }
  if (is.matrix(x)) {
    m <- suppressWarnings(matrix(as.numeric(x), nrow = nrow(x), ncol = ncol(x)))
    m[!is.finite(m)] <- 0; return(m)
  }
  v <- suppressWarnings(as.numeric(x)); v[!is.finite(v)] <- 0
  matrix(v, nrow = length(v), ncol = 1)
}

# Safe JSON to character helper
safe_json <- function(x, auto_unbox = FALSE) {
  as.character(jsonlite::toJSON(x, auto_unbox = auto_unbox))
}

# [v4.7] Safe wrapper around ggplot2::ggsave used throughout Part B.
#
# Why this exists:
#   The v4.6 run died on the first vis file with
#     Error in grid.Call.graphics(C_setviewport, vp, TRUE):
#       non-finite location and/or size for viewport
#   which is raised by grid during PNG rendering (NOT during ggplot build),
#   and which aborts the entire batch on a single bad plot.  By wrapping
#   every Part B ggsave in tryCatch we (a) keep the loop going through the
#   remaining plots / files and (b) print a clear message identifying which
#   plot/file combination is the actual culprit so it can be debugged in
#   isolation instead of being deduced from a stack-less grid error.
#
# Behaviour:
#   - On success: writes the PNG, returns TRUE invisibly, prints nothing.
#   - On error:   prints a single-line "[v4.7] ggsave FAILED ..." message
#                 with the tag, file path, and error text; returns FALSE.
#   - If `plot` is NULL it skips (with a one-line note) instead of erroring.
#
# Parameters:
#   filepath: full path to the output PNG
#   plot:     ggplot object (or NULL)
#   tag:      short identifier for the failing site (e.g. "OverlaidDFF0")
#             -- printed verbatim in the error message
#   ...:      passed through to ggsave (width, height, dpi)
.safe_ggsave <- function(filepath, plot, tag = "ggsave", ...) {
  if (is.null(plot)) {
    message(sprintf("[v4.7] %s: plot is NULL, skipping %s", tag, basename(filepath)))
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    suppressWarnings(ggplot2::ggsave(filepath, plot = plot, ...))
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    message(sprintf("[v4.7] ggsave FAILED [%s] for %s: %s",
                    tag, basename(filepath), msg))
    # [v4.8] Also push into the diagnostic accumulator so the JSON summary
    # written at script end has a structured count of failures per tag.
    if (exists(".v48_ggsave_failures", envir = .GlobalEnv)) {
      .GlobalEnv$.v48_ggsave_failures[[length(.GlobalEnv$.v48_ggsave_failures) + 1L]] <-
        list(tag = tag, file = basename(filepath), path = filepath, message = msg)
    }
    FALSE
  })
  invisible(isTRUE(ok))
}

# Spatial maps saver (no scalebar) and perform Flip Vertical + Rotate Right
save_cfu_spatial_png <- function(spmat, out_png, title = NULL,
                                 upper_limit = NULL, upper_quantile = 0.99,
                                 width_in = 5, height_in = 5, dpi = 300) {
  if (!is.matrix(spmat) || any(dim(spmat) == 0)) return(invisible(FALSE))
  nr <- nrow(spmat); nc <- ncol(spmat)
  df <- expand.grid(r = seq_len(nr), c = seq_len(nc))
  df$value <- as.numeric(spmat); df$value[!is.finite(df$value)] <- 0
  
  # Map matrix to image-like coordinates:
  # - x = c (columns, left->right)
  # - y = nr - r + 1 (rows flipped so row 1 is at the top)
  gg <- ggplot(df, aes(x = c, y = nr - r + 1, fill = value)) +
    geom_raster() +
    coord_fixed(expand = FALSE) +
    scale_x_continuous(limits = c(1, nc), expand = c(0,0)) +
    scale_y_continuous(limits = c(1, nr), expand = c(0,0)) +
    scale_fill_gradientn(colors = c("#000004", "#2C105C", "#711F81", "#B73779", "#F1605D", "#FDB42F", "#FCFFA4"),
                         limits = c(0, if (is.null(upper_limit)) {
                           nz <- df$value[df$value > 0]
                           up <- if (length(nz)) as.numeric(stats::quantile(nz, probs = upper_quantile, na.rm = TRUE, type = 7)) else 1
                           if (!is.finite(up) || up <= 0) 1 else up
                         } else upper_limit),
                         oob = scales::squish, name = "Weight") +
    theme_void(base_size = 12, base_family = "Arial") +
    theme(legend.position = "right",
          legend.title = element_text(size = 10, family = "Arial", color = "black"),
          legend.text  = element_text(size = 9,  family = "Arial", color = "black"),
          plot.title   = element_text(family = "Arial", color = "black", hjust = 0),
          plot.margin = ggplot2::margin(5, 5, 5, 5, unit = "pt"))
  if (!is.null(title)) gg <- gg + ggtitle(title)
  # [v4.7] Route through .safe_ggsave so a spatial-map viewport error doesn't
  # abort the Part B loop.
  .safe_ggsave(out_png, plot = gg,
               tag = paste0("SpatialMap/", basename(out_png)),
               width = width_in, height = height_in, dpi = dpi)
  invisible(TRUE)
}


# Combine all CFU spatial patterns for a file into one map (presence + sum)
combine_cfu_spatial_patterns <- function(cfuList, binarize = TRUE) {
  nCFU <- nrow(cfuList)
  mats <- vector("list", nCFU)
  for (i in seq_len(nCFU)) {
    sp_cell <- tryCatch(cfuList[i, 3][[1]], error = function(e) NULL)
    sp_mat  <- to_numeric_matrix(sp_cell)
    if (is.matrix(sp_mat) && all(dim(sp_mat) > 0)) {
      mats[[i]] <- sp_mat
    } else {
      mats[[i]] <- NULL
    }
  }
  mats <- Filter(Negate(is.null), mats)
  if (!length(mats)) return(NULL)
  dims_str <- vapply(mats, function(m) paste(dim(m), collapse="x"), character(1))
  common_dim <- names(sort(table(dims_str), decreasing = TRUE))[1]
  mats <- mats[dims_str == common_dim]
  if (!length(mats)) return(NULL)
  arr <- array(unlist(mats), dim = c(dim(mats[[1]]), length(mats)))
  if (isTRUE(binarize)) {
    pres <- apply(arr, c(1,2), function(v) as.numeric(any(is.finite(v) & v > 0)))
    sum_mat <- apply(arr, c(1,2), function(v) { v[!is.finite(v)] <- 0; sum(v) })
    return(list(presence = pres, sum = sum_mat))
  } else {
    sum_mat <- apply(arr, c(1,2), function(v) { v[!is.finite(v)] <- 0; sum(v) })
    return(list(presence = NULL, sum = sum_mat))
  }
}

get_event_times_from_ev_idx <- function(cfuList, cfu_id, frame_interval) {
  # Map CFU_ID to row; prefer explicit ID in col 1, fallback to row index
  ids <- tryCatch(
    as.integer(sapply(seq_len(nrow(cfuList)), function(i) to_numeric_vec(cfuList[i,1][[1]])[1])),
    error = function(e) integer(0)
  )
  row_i <- if (length(ids)) which(ids == as.integer(cfu_id)) else integer(0)
  if (!length(row_i)) row_i <- as.integer(cfu_id)
  row_i <- row_i[1]
  # Use EVENT INDICES (col 2), exactly as in the per-event pass
  raw_ev_cell <- tryCatch(cfuList[row_i, 2][[1]], error = function(e) NULL)
  ev_idx <- as.integer(unlist(raw_ev_cell))
  ev_idx <- ev_idx[is.finite(ev_idx)]
  if (!length(ev_idx)) return(numeric(0))
  as.numeric(ev_idx) * frame_interval
}

# --------------------------------------- PLOTTING HELPERS ---------------------------------------
# §9 -- Functions that build the various PNG outputs.  All go through
# .safe_ggsave (defined in §15) so a single failed plot doesn't abort
# the per-file iteration.  Major functions:
#   plot_cfu_peak_aligned_overlay()  Per-CFU event-overlay with rise10-90
#                                    and decay90-10 bracket annotations.
#   plot_cfu_event_overlay_legacy()  Backward-compat plain overlay.
#   save_cfu_spatial_png()           Per-CFU and combined spatial maps
#                                    via geom_raster + coord_fixed.
#                                    Robust against degenerate input dims.
#   combine_cfu_spatial_patterns()   Sums + binarises per-CFU footprints
#                                    into per-file presence/sum maps.
#   plot_cfu_feature_panel()         Per-file summary panel of amplitude,
#                                    duration, rise, decay distributions.
#   plot_group_waveform_*()          Per-group raw and aligned waveform
#                                    timecourses with burst markers.
# [v4.7] Safe per-group z-score helper.  The old inline form
#   `if (sd(dFF0, na.rm=TRUE) > 0) (...) else 0`
# blows up in dplyr::mutate when sd() returns NA (group has only 1 finite
# value, or all NA), because R then tries to evaluate `if (NA > 0)` and
# throws "missing value where TRUE/FALSE needed".  This function:
#   - returns 0 for groups with <2 finite values, NA sd, or sd == 0
#   - returns the z-scored vector otherwise
#   - never lets a non-finite leak through to coord_cartesian -- non-finite
#     inputs map to NA in the output, which is filtered out by the
#     downstream `is.finite(y)` guard
.safe_zscore <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  ok <- is.finite(v)
  if (sum(ok) < 2L) return(rep(0, length(v)))
  s <- stats::sd(v, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(0, length(v)))
  m <- mean(v, na.rm = TRUE)
  out <- (v - m) / s
  out[!is.finite(out)] <- NA_real_
  out
}

plot_overlaid_dff0 <- function(df_file, file_id, use_z = TRUE) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  if (use_z) {
    # [v4.7] Replaced inline `if (sd(...) > 0)` with .safe_zscore() to avoid
    # `if (NA > 0)` errors on degenerate groups (single finite value, all-NA).
    d <- d %>% dplyr::group_by(CFU_ID) %>%
      dplyr::mutate(y = .safe_zscore(dFF0)) %>%
      dplyr::ungroup()
    ylab <- "Weighted average dF/F0 (z-scored within CFU)"
  } else {
    d <- dplyr::mutate(d, y = dFF0)
    ylab <- "Weighted average dF/F0"
  }
  d <- d %>% dplyr::filter(is.finite(y), is.finite(t_sec))
  if (nrow(d) == 0) {
    # [v4.7] Placeholder plot instead of an empty ggplot so the caller's
    # tryCatch sees a sensible result rather than a viewport error.
    return(ggplot2::ggplot() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = paste0("No finite y for ", file_id),
                               size = 4) +
             ggplot2::labs(title = paste0("CFU weighted average dF/F0 (", file_id, ") -- empty"),
                           x = "Time (s)", y = ylab) +
             theme_axes_black())
  }
  ggplot2::ggplot(d, ggplot2::aes(x = t_sec, y = y, group = CFU_ID, color = CFU_ID)) +
    ggplot2::geom_line(alpha = 0.7, linewidth = 0.4, show.legend = FALSE) +
    ggplot2::labs(title = paste0("CFU weighted average dF/F0 timecourses (", file_id, ")"),
                  x = "Time (s)", y = ylab) +
    theme_axes_black()
}

plot_overlaid_nondff0 <- function(df_file, file_id) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  ggplot2::ggplot(d %>% dplyr::filter(is.finite(non_dFF0)), ggplot2::aes(x = t_sec, y = non_dFF0, group = CFU_ID, color = CFU_ID)) +
    ggplot2::geom_line(alpha = 0.7, linewidth = 0.4, show.legend = FALSE) +
    ggplot2::labs(title = paste0("CFU weighted average (non-dF/F0) – ", file_id),
                  x = "Time (s)", y = "Weighted average (non-dF/F0)") +
    theme_axes_black()
}

plot_faceted_dff0 <- function(df_file, file_id, use_z = TRUE, ncol = 6) {
  d <- df_file
  if (use_z) {
    # [v4.7] Use .safe_zscore() instead of inline `if (sd(...) > 0)`.
    d <- d %>% group_by(CFU_ID) %>% mutate(y = .safe_zscore(dFF0)) %>% ungroup()
    ylab <- "Weighted average dF/F0 (z-scored within CFU)"
  } else { d <- mutate(d, y = dFF0); ylab <- "Weighted average dF/F0" }
  d <- d %>% dplyr::filter(is.finite(y), is.finite(t_sec))
  if (nrow(d) == 0) {
    return(ggplot2::ggplot() +
             ggplot2::annotate("text", x = 0, y = 0,
                               label = paste0("No finite y for ", file_id),
                               size = 4) +
             ggplot2::labs(title = paste0("CFU weighted average dF/F0 by CFU (", file_id, ") -- empty"),
                           x = "Time (s)", y = ylab) +
             theme_axes_black())
  }
  ggplot(d, aes(x = t_sec, y = y)) +
    geom_line(color = "black", linewidth = 0.3) +
    facet_wrap(~ CFU_ID, scales = "free_y", ncol = ncol) +
    labs(title = paste0("CFU weighted average dF/F0 timecourses by CFU (", file_id, ")"),
         x = "Time (s)", y = ylab) +
    theme_axes_black()
}

plot_faceted_nondff0 <- function(df_file, file_id, ncol = 6) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  ggplot2::ggplot(d %>% dplyr::filter(is.finite(non_dFF0)),
                  ggplot2::aes(x = t_sec, y = non_dFF0)) +
    ggplot2::geom_line(color = "black", linewidth = 0.3) +
    ggplot2::facet_wrap(~ CFU_ID, scales = "free_y", ncol = ncol) +
    ggplot2::labs(title = paste0("CFU weighted average (non-dF/F0) by CFU – ", file_id),
                  x = "Time (s)", y = "Weighted average (non-dF/F0)") +
    theme_axes_black()
}

plot_group_waveforms <- function(d_long, file_id, group_id, apply_shift = TRUE,
                                 use_dff0 = TRUE, alpha = 0.7, lwd = 0.5, mean_lwd = 0.9) {
  if (nrow(d_long) == 0) return(NULL)
  label_y <- if (use_dff0) "dF/F0 (z)" else "Non-dF/F0 (z)"
  title_str <- paste0("Group ", group_id, " waveforms – ", file_id,
                      if (apply_shift) " (aligned by relative delays)" else " (raw time)")
  mean_df <- d_long %>% dplyr::filter(is.finite(y)) %>% group_by(t_sec) %>% summarize(y = mean(y, na.rm = TRUE), .groups = "drop")
  ggplot(d_long %>% dplyr::filter(is.finite(y)), aes(x = t_sec, y = y, group = CFU_ID, color = CFU_ID)) +
    geom_line(alpha = alpha, linewidth = lwd, show.legend = TRUE) +
    geom_line(data = mean_df, aes(x = t_sec, y = y), inherit.aes = FALSE,
              color = "black", linewidth = mean_lwd, alpha = 0.9) +
    labs(title = title_str, x = "Time (s)", y = label_y, color = "CFU") +
    theme_axes_black()
}

plot_heatmap_dff0_raw <- function(df_file, file_id) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  ggplot2::ggplot(d %>% dplyr::filter(is.finite(dFF0)),
                  ggplot2::aes(x = t_sec, y = CFU_ID, fill = dFF0)) +
    ggplot2::geom_tile(height = 0.95, width = 0.95) +
    ggplot2::scale_fill_gradientn(colors = c("#000004","#2C105C","#711F81","#B73779","#F1605D","#FDB42F","#FCFFA4"),
                                  name = "dF/F0") +
    ggplot2::labs(title = paste0("CFU-by-time heatmap (Raw dF/F0) – ", file_id),
                  x = "Time (s)", y = "CFU ID") +
    theme_axes_black()
}

plot_heatmap_dff0_norm <- function(df_file, file_id) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  d <- d %>%
    dplyr::group_by(CFU_ID) %>%
    dplyr::mutate(
      dFF0_min = min(dFF0, na.rm = TRUE),
      dFF0_max = max(dFF0, na.rm = TRUE),
      dFF0_rng = ifelse(is.finite(dFF0_max - dFF0_min) & (dFF0_max - dFF0_min) > 0, dFF0_max - dFF0_min, 1),
      dFF0_01  = (dFF0 - dFF0_min) / dFF0_rng
    ) %>%
    dplyr::ungroup()
  ggplot2::ggplot(d %>% dplyr::filter(is.finite(dFF0_01)),
                  ggplot2::aes(x = t_sec, y = CFU_ID, fill = dFF0_01)) +
    ggplot2::geom_tile(height = 0.95, width = 0.95) +
    ggplot2::scale_fill_gradientn(colors = c("#000004","#2C105C","#711F81","#B73779","#F1605D","#FDB42F","#FCFFA4"),
                                  name = "dF/F0", limits = c(0,1)) +
    ggplot2::labs(title = paste0("CFU-by-time heatmap (Normalized dF/F0) – ", file_id),
                  x = "Time (s)", y = "CFU ID") +
    theme_axes_black()
}

plot_heatmap_nondff0_raw <- function(df_file, file_id) {
  d <- df_file
  d$CFU_ID <- as.factor(d$CFU_ID)
  ggplot2::ggplot(d %>% dplyr::filter(is.finite(non_dFF0)),
                  ggplot2::aes(x = t_sec, y = CFU_ID, fill = non_dFF0)) +
    ggplot2::geom_tile(height = 0.95, width = 0.95) +
    ggplot2::scale_fill_gradientn(colors = c("#000004","#2C105C","#711F81","#B73779","#F1605D","#FDB42F","#FCFFA4"),
                                  name = "non-dF/F0") +
    ggplot2::labs(title = paste0("CFU-by-time heatmap – weighted average (non-dF/F0) – ", file_id),
                  x = "Time (s)", y = "CFU ID") +
    theme_axes_black()
}



# ------- Safe hierarchical order of CFUs by timecourse similarity -------
compute_cfu_order_by_timecourse <- function(df_long, value_col = "dFF0",
                                            method = c("euclidean_z","corr"),
                                            min_non_na_per_row = 3L) {
  method <- match.arg(method)
  # Current overall order fallback
  all_ids <- as.character(unique(df_long$CFU_ID))
  
  d <- df_long %>%
    dplyr::filter(is.finite(.data[[value_col]])) %>%
    dplyr::select(CFU_ID, t_index, value = dplyr::all_of(value_col))
  
  if (nrow(d) == 0) return(all_ids)
  
  # wide matrix: rows = CFU_ID, cols = t_index
  wide <- tidyr::pivot_wider(d, names_from = t_index, values_from = value)
  if (nrow(wide) == 0 || ncol(wide) < 2) return(all_ids)
  
  mat <- as.matrix(wide[,-1, drop = FALSE])
  rownames(mat) <- as.character(wide$CFU_ID)
  
  # Keep rows with at least min_non_na_per_row finite points
  keep <- rowSums(is.finite(mat)) >= min_non_na_per_row
  if (!any(keep)) return(all_ids)
  mat <- mat[keep, , drop = FALSE]
  
  # If only one CFU remains, return fallback preserving it first
  if (nrow(mat) < 2) {
    ord_ids <- rownames(mat)
    extra <- setdiff(all_ids, ord_ids)
    return(c(ord_ids, extra))
  }
  
  if (method == "euclidean_z") {
    # z-score per row; protect zero-variance rows
    mat <- t(scale(t(mat)))
    mat[!is.finite(mat)] <- 0
    # After z, ensure at least some variability remains
    row_sd <- apply(mat, 1, function(x) sd(x, na.rm = TRUE))
    keep2 <- is.finite(row_sd) & row_sd > 0
    if (sum(keep2) >= 2) {
      mat <- mat[keep2, , drop = FALSE]
    } else {
      # if degenerate post-z, fall back to unscaled with NA->0
      mat <- as.matrix(mat)
    }
    dd <- dist(mat, method = "euclidean")
  } else {
    # Correlation distance with pairwise completeness
    C <- suppressWarnings(cor(t(mat), use = "pairwise.complete.obs"))
    # Replace NA correlations (e.g., zero-variance pairs) with 0 to avoid NA distances
    C[!is.finite(C)] <- 0
    # If only one valid row remains, bail out
    if (nrow(C) < 2) {
      ord_ids <- rownames(mat)
      extra <- setdiff(all_ids, ord_ids)
      return(c(ord_ids, extra))
    }
    dd <- as.dist(1 - C)
  }
  
  # Final safety: dd must represent >=2 objects
  nobj <- attr(dd, "Size")
  if (is.null(nobj) || is.na(nobj) || nobj < 2) {
    ord_ids <- rownames(mat)
    extra <- setdiff(all_ids, ord_ids)
    return(c(ord_ids, extra))
  }
  
  hc <- hclust(dd, method = "average")
  ord_ids <- rownames(mat)[hc$order]
  extra <- setdiff(all_ids, ord_ids)
  c(ord_ids, extra)
}



add_burst_lines_to_group_plot <- function(p, burst_times_sec,
                                          color = "#B73779",
                                          alpha = 0.7,
                                          lwd = 0.6) {
  if (is.null(burst_times_sec) || !length(burst_times_sec)) return(p)
  p + geom_vline(xintercept = burst_times_sec,
                 color = color, alpha = alpha, linewidth = lwd)
}

# Event-sequence raster: onset binary per CFU over time
plot_raster_occ <- function(df_file, file_id) {
  d <- df_file
  if (!("OccBin" %in% names(d))) return(NULL)
  d$CFU_ID <- as.factor(d$CFU_ID)
  d <- d %>% dplyr::filter(is.finite(t_sec), !is.na(OccBin))
  if (nrow(d) == 0) return(NULL)
  ggplot2::ggplot(d, ggplot2::aes(x = t_sec, y = CFU_ID, fill = factor(OccBin))) +
    ggplot2::geom_tile(height = 0.95, width = 0.95) +
    ggplot2::scale_fill_manual(values = c("0" = "#f0f0f0", "1" = "#2C7FB8")) +
    ggplot2::guides(fill = "none") +
    ggplot2::labs(title = paste0("CFU event-sequence raster (onsets) – ", file_id),
                  x = "Time (s)", y = "CFU ID") +
    theme_axes_black()
}

# --------------------------------------- GROUP waveform data builder ---------------------------------------
build_group_long <- function(dff_list, members, rel_delays_frames, frame_interval,
                             zscore = TRUE, apply_shift = TRUE) {
  if (length(members) == 0) return(data.frame())
  nT <- suppressWarnings(max(sapply(dff_list, function(v) length(v))))
  if (!is.finite(nT) || nT <= 0) return(data.frame())
  if (length(rel_delays_frames) != length(members)) rel_delays_frames <- rep(0L, length(members))
  ref_idx <- if (length(rel_delays_frames) > 0) which.min(abs(rel_delays_frames)) else 1
  rel0 <- as.integer(round(rel_delays_frames - rel_delays_frames[ref_idx]))
  rows <- vector("list", length(members))
  for (i in seq_along(members)) {
    cfu_id <- members[i]
    v <- dff_list[[cfu_id]]; if (is.null(v)) next
    if (length(v) < nT) v <- c(v, rep(NA_real_, nT - length(v))) else v <- v[1:nT]
    if (zscore) { mu <- mean(v, na.rm = TRUE); sdv <- sd(v, na.rm = TRUE); v <- if (is.finite(sdv) && sdv>0) (v-mu)/sdv else v*0 }
    if (apply_shift) {
      s <- rel0[i]
      if (s > 0) v <- c(rep(NA_real_, s), v)[1:nT] else if (s < 0) v <- c(v[(-s + 1):nT], rep(NA_real_, -s))
    }
    rows[[i]] <- data.frame(File = NA_character_, GroupID = NA_integer_, CFU_ID = factor(cfu_id),
                            t_index = seq_len(nT), t_sec = seq_len(nT) * frame_interval,
                            y = v, shift_frames = rel0[i], stringsAsFactors = FALSE)
  }
  dplyr::bind_rows(rows)
}

# ---------------- Event-coincidence helpers (network bursts) ----------------
ppx_collect_member_events <- function(prefix, members, get_times_fun) {
  ets <- vector("list", length(members))
  names(ets) <- as.character(members)
  for (i in seq_along(members)) {
    cfu <- members[i]
    v <- tryCatch(get_times_fun(prefix, cfu), error = function(e) numeric(0))
    v <- v[is.finite(v)]
    ets[[i]] <- sort(unique(as.numeric(v)))
  }
  ets
}

ppx_cluster_group_events <- function(events_by_cfu, tau_sec = 0.5, refractory_sec = 0.5,
                                     min_participating = NULL, min_fraction = NULL) {
  cfus <- names(events_by_cfu)
  all_rows <- lapply(cfus, function(c){
    t <- events_by_cfu[[c]]
    if (!length(t)) return(NULL)
    data.frame(t = t, cfu = as.integer(c), stringsAsFactors = FALSE)
  })
  ev <- do.call(rbind, all_rows)
  if (is.null(ev) || nrow(ev) == 0) return(list(episodes = data.frame(), members = cfus))
  ev <- ev[order(ev$t), , drop = FALSE]
  k <- length(cfus)
  if (is.null(min_participating) || !is.finite(min_participating)) {
    if (!is.null(min_fraction) && is.finite(min_fraction)) min_participating <- ceiling(min_fraction * k) else min_participating <- min(2L, k)
  } else { min_participating <- max(1L, as.integer(min_participating)) }
  episodes <- list(); i <- 1L; last_ep_time <- -Inf; n <- nrow(ev)
  while (i <= n) {
    t0 <- ev$t[i]; if ((t0 - last_ep_time) < refractory_sec) { i <- i + 1L; next }
    lo <- t0 - tau_sec; hi <- t0 + tau_sec
    j <- i; idxs <- integer(0)
    while (j <= n && ev$t[j] <= hi) { if (ev$t[j] >= lo) idxs <- c(idxs, j); j <- j + 1L }
    if (length(idxs)) {
      cfus_here <- sort(unique(ev$cfu[idxs])); part_n <- length(cfus_here)
      if (part_n >= min_participating) {
        times_here <- ev$t[idxs]; ep_time <- as.numeric(median(times_here)); jitter <- max(times_here) - min(times_here)
        episodes[[length(episodes)+1L]] <- data.frame(ep_time_sec = ep_time, n_participating = part_n, jitter_sec = jitter, stringsAsFactors = FALSE)
        last_ep_time <- ep_time; while (i <= n && ev$t[i] <= (ep_time + refractory_sec)) i <- i + 1L; next
      }
    }
    i <- i + 1L
  }
  ep_df <- if (length(episodes)) do.call(rbind, episodes) else data.frame()
  list(episodes = ep_df, members = cfus)
}

get_cfu_event_times_sec_from_mat <- function(cfuList, cfu_id, frame_interval) {
  ids <- tryCatch({ as.integer(sapply(seq_len(nrow(cfuList)), function(i) to_numeric_vec(cfuList[i,1][[1]])[1])) }, error = function(e) integer(0))
  row_i <- if (length(ids)) which(ids == as.integer(cfu_id)) else integer(0)
  if (!length(row_i)) row_i <- as.integer(cfu_id); row_i <- row_i[1]
  dff_vec <- tryCatch(to_numeric_vec(cfuList[row_i, 6][[1]]), error = function(e) numeric(0))
  nT <- length(dff_vec); if (!is.finite(nT) || nT <= 0) return(numeric(0))
  occ_cell <- tryCatch(cfuList[row_i, 4][[1]], error = function(e) NULL)
  occ_bin <- to_binary_sequence(occ_cell, nT = nT)
  if (length(occ_bin) != nT) return(numeric(0))
  fr_idx <- which(occ_bin == 1); if (!length(fr_idx)) return(numeric(0))
  fr_idx * frame_interval
}

# Plotting single CFU timecourse and events
plot_single_cfu <- function(dff0_long_df, file_id, cfu_id,
                             event_times_sec = NULL, fts_vecs = NULL,
                             frame_interval_arg = frame_interval,
                             pre_sec = 1.0, post_sec = 3.0) {
  d <- dff0_long_df %>% dplyr::filter(CFU_ID == cfu_id)
  if (nrow(d) == 0) return(NULL)

  p <- ggplot2::ggplot() +
    ggplot2::labs(title = paste0("CFU ", cfu_id, " – dF/F0 – ", file_id),
                 x = "Time (s)", y = "dF/F0") +
    theme_axes_black()

  # [v3.0] Grey individual per-event window traces behind the mean
  if (!is.null(event_times_sec) && length(event_times_sec) >= 1) {
    win_list <- lapply(seq_along(event_times_sec), function(ei) {
      t0 <- event_times_sec[ei]
      if (!is.null(fts_vecs) &&
          !is.null(fts_vecs$tBegin) && !is.null(fts_vecs$tEnd) &&
          ei <= length(fts_vecs$tBegin)) {
        t_start <- (fts_vecs$tBegin[ei] - 1L) * frame_interval_arg
        t_end   <- (fts_vecs$tEnd[ei]   - 1L) * frame_interval_arg
      } else {
        t_start <- t0 - pre_sec
        t_end   <- t0 + post_sec
      }
      seg <- d %>% dplyr::filter(t_sec >= t_start & t_sec <= t_end)
      if (nrow(seg) < 2) return(NULL)
      seg$event_idx <- as.character(ei)
      seg
    })
    win_df <- dplyr::bind_rows(Filter(Negate(is.null), win_list))
    if (nrow(win_df) > 0) {
      p <- p + ggplot2::geom_line(
        data = win_df %>% dplyr::filter(is.finite(dFF0)),
        ggplot2::aes(x = t_sec, y = dFF0, group = event_idx),
        color = "grey60", alpha = annot_individual_alpha,
        linewidth = annot_individual_lwd, inherit.aes = FALSE)
    }
  }

  # Black mean full timecourse on top
  p <- p + ggplot2::geom_line(
    data = d %>% dplyr::filter(is.finite(dFF0)),
    ggplot2::aes(x = t_sec, y = dFF0),
    color = "black", linewidth = 0.6, inherit.aes = FALSE)

  # Optional vertical event marker lines
  if (isTRUE(single_cfu_show_event_lines) && !is.null(event_times_sec) && length(event_times_sec)) {
    p <- p + ggplot2::geom_vline(xintercept = event_times_sec,
                                 color = "#B73779", alpha = 0.5, linewidth = 0.3)
  }
  p
}

# ---------------- IEI METRICS ----------------
calc_iei_stats <- function(event_times_sec) {
  if (length(event_times_sec) < 2) {
    return(list(MeanIEI_sec = NA_real_, IEI_CV = NA_real_))
  }
  iei <- diff(sort(event_times_sec))
  mean_iei <- mean(iei, na.rm = TRUE)
  iei_cv <- if (mean_iei > 0) sd(iei, na.rm = TRUE) / mean_iei else NA_real_
  list(MeanIEI_sec = mean_iei, IEI_CV = iei_cv)
}


# Modified event window slicing using provided start and end indices per event

# ── [v4.5] HDF5 (MAT v7.3) helpers — rhdf5 backend ────────────────────────────
# MATLAB v7.3 .mat files are HDF5. Cell arrays are stored as datasets of HDF5
# object references; the references point into a #refs# group, one target per
# cell array element. hdf5r 1.3.12 cannot dereference these references on this
# libhdf5 + MATLAB-file combination (H5Rdereference2 fails with "unable to open
# object by token"), so v4.5 uses rhdf5 (Bioconductor) instead.
#
# rhdf5 calling convention (confirmed by diagnostic v8):
#   refs <- rhdf5::h5read(path, "cfuInfo1")            # H5Ref S4, length = nfields*ncells
#   did  <- rhdf5::H5Rdereference(refs[i], fid)        # arg order: (ref, h5loc)
#   data <- rhdf5::H5Dread(did)
#   rhdf5::H5Dclose(did)
# Linear order from h5read on a [Nfields, Ncells] reference dataset is HDF5
# row-major: i = (field - 1) * Ncells + cell, so cell varies fastest.

# Check whether an HDF5 path exists in the open file id (rhdf5 has no
# convenient `exists` helper). Uses H5Lexists for top-level; for nested
# paths splits on "/" and checks each segment.
.rhdf5_path_exists <- function(fid, path) {
  parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(FALSE)
  cur <- ""
  for (p in parts) {
    cur <- if (nzchar(cur)) paste0(cur, "/", p) else p
    ok <- tryCatch(rhdf5::H5Lexists(fid, cur), error = function(e) FALSE)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

# Dimensions of a dataset, in HDF5 storage order (innermost = fastest-varying).
# For a MATLAB [Ncells, Nfields] cell array, HDF5 reports [Nfields, Ncells].
.rhdf5_dims <- function(fid, path) {
  did <- tryCatch(rhdf5::H5Dopen(fid, path), error = function(e) NULL)
  if (is.null(did)) return(integer(0))
  sid <- tryCatch(rhdf5::H5Dget_space(did), error = function(e) NULL)
  d <- if (!is.null(sid)) {
    tryCatch(rhdf5::H5Sget_simple_extent_dims(sid)$size,
             error = function(e) integer(0))
  } else integer(0)
  try(rhdf5::H5Sclose(sid), silent = TRUE)
  try(rhdf5::H5Dclose(did), silent = TRUE)
  d
}

# Read one H5R element and return its target's data as numeric vector,
# or numeric(0) on failure.
.rhdf5_deref_one <- function(ref_i, fid) {
  tryCatch({
    did <- rhdf5::H5Rdereference(ref_i, fid)
    v   <- rhdf5::H5Dread(did)
    try(rhdf5::H5Dclose(did), silent = TRUE)
    # [v4.8] Preserve dim attribute for 2D arrays.  Previously this returned
    # as.numeric(as.vector(v)) which strips dims, so a 502x502 spatial
    # pattern came back as a 252,004-length flat vector.  Downstream,
    # to_numeric_matrix() then reshaped it as a degenerate Nx1 column,
    # which save_cfu_spatial_png + geom_raster + coord_fixed cannot render
    # ("non-finite location and/or size for viewport").  Keep 2D arrays
    # as numeric matrices; flatten only true 1D vectors.  to_numeric_vec()
    # callers (event indices, dFF0 traces, IDs) already handle both shapes
    # via their internal as.vector(), so this is backward-compatible.
    if (is.null(v)) return(numeric(0))
    if (is.array(v) && length(dim(v)) == 2L) {
      d <- dim(v)
      return(matrix(as.numeric(v), nrow = d[1], ncol = d[2]))
    }
    if (is.array(v) && length(dim(v)) > 2L) {
      # 3D+ datasets are unexpected for cfuInfo fields, but preserve dims
      # rather than silently flatten -- caller can decide what to do.
      d <- dim(v)
      arr <- array(as.numeric(v), dim = d)
      return(arr)
    }
    as.numeric(as.vector(v))
  }, error = function(e) numeric(0))
}

# Read a MATLAB cell array of references and return a [Ncells x Nfields]
# list-matrix where each element is list(numeric_vector) — matching the
# structure that readMat() produces, so downstream code (cfu_mat[[cell, field]][[1]])
# works unchanged.
#
# [v4.6] Smart orientation detection.  Different files have different HDF5
# dim conventions for cfuInfo1, so we don't trust dims alone.  MATLAB writes
# cell arrays in column-major order: field 1 (IDs, integer scalars) comes
# first.  We find the longest prefix of integer-valued scalar refs as a
# candidate ncells, then choose the largest k from that prefix where
# total_refs %% k == 0 and total/k is a plausible nfields ([2, 200]).
# Falls back to dims if detection yields nothing usable.
.rhdf5_read_cell_array <- function(fid, path) {
  if (!.rhdf5_path_exists(fid, path)) return(NULL)
  fname <- rhdf5::H5Fget_name(fid)
  refs <- tryCatch(rhdf5::h5read(fname, path), error = function(e) NULL)
  if (is.null(refs) || !inherits(refs, "H5Ref")) return(NULL)

  dims    <- .rhdf5_dims(fid, path)
  n_total <- length(refs)

  # ---- Read ALL refs upfront (needed both for orientation detection and to
  # fill the result; reading once avoids repeated dereference cost). --------
  refs_data <- vector("list", n_total)
  refs_lens <- integer(n_total)
  for (i in seq_len(n_total)) {
    refs_data[[i]] <- .rhdf5_deref_one(refs[i], fid)
    refs_lens[i]   <- length(refs_data[[i]])
  }

  # ---- Smart orientation detection -----------------------------------------
  # MATLAB cfuInfo1 cell IDs are consecutive 1..Ncells.  Find the longest
  # prefix where each ref is a length-1 scalar whose VALUE equals its INDEX
  # (i.e., refs[1]=1, refs[2]=2, ...).  Distinguishes IDs from coincidental
  # scalar event vectors (a single event with frame index 137 does not match
  # ref position 3, so the prefix correctly stops at the last true ID).
  scalar_prefix <- 0L
  for (i in seq_len(n_total)) {
    v <- refs_data[[i]]
    if (refs_lens[i] == 1L && is.finite(v[1]) &&
        isTRUE(all.equal(as.numeric(v[1]), as.numeric(i)))) {
      scalar_prefix <- i
    } else break
  }
  ncells_detect <- 0L; nfields_detect <- 0L
  if (scalar_prefix > 0L) {
    # Try largest plausible ncells first; require both divisibility and a
    # reasonable nfields range so that e.g. extra single-event cells beyond
    # the real ID block don't extend the detection.
    for (k in seq.int(scalar_prefix, 1L)) {
      if (n_total %% k == 0L) {
        nf <- n_total %/% k
        if (nf >= 2L && nf <= 200L) {
          ncells_detect  <- k
          nfields_detect <- nf
          break
        }
      }
    }
  }

  if (ncells_detect > 0L) {
    ncells <- ncells_detect; nfields <- nfields_detect
    method <- sprintf("auto (scalar-ID prefix=%d)", scalar_prefix)
  } else {
    # ---- Fallback: dims interpretation -------------------------------------
    if (length(dims) == 2) {
      nfields <- dims[1]; ncells <- dims[2]
    } else if (length(dims) == 1) {
      if (grepl("cfuInfo", path) && dims[1] >= 6) { ncells <- 1L; nfields <- dims[1] }
      else                                         { ncells <- dims[1]; nfields <- 1L }
    } else return(NULL)
    method <- "dims fallback"
  }

  # ---- Build result matrix [Ncells × Nfields] in MATLAB orientation --------
  # MATLAB column-major: linear ref i -> (cell = ((i-1) %% ncells)+1,
  #                                       field = ((i-1) %/% ncells)+1)
  result     <- matrix(vector("list", ncells * nfields), nrow = ncells, ncol = nfields)
  n_resolved <- 0L
  for (i in seq_len(min(n_total, ncells * nfields))) {
    field <- ((i - 1L) %/% ncells) + 1L
    cell  <- ((i - 1L) %%  ncells) + 1L
    val   <- refs_data[[i]]
    if (length(val) > 0L) n_resolved <- n_resolved + 1L
    result[[cell, field]] <- list(val)
  }
  message(sprintf("    [v4.6] %s: %s; ncells=%d, nfields=%d; resolved %d/%d refs",
                  path, method, ncells, nfields, n_resolved, ncells * nfields))
  result
}

# Read a plain numeric dataset (e.g. cfuRelation, datPro) -> R matrix/vector.
.rhdf5_read_numeric <- function(fid, path) {
  if (!.rhdf5_path_exists(fid, path)) return(NULL)
  tryCatch(rhdf5::h5read(rhdf5::H5Fget_name(fid), path),
           error = function(e) { message("    .rhdf5_read_numeric(", path, "): ", e$message); NULL })
}

# [v4.6] Restored hdf5r-based safe-exists helper, used by
# integrate_event_windows_per_cfu() and the Part B vis loop when they open
# PRE companion .mat files via hdf5r to extract fts/curve/tBegin etc.
# PRE companion fts reads are plain numeric datasets (no H5R refs), so
# hdf5r handles them correctly; only this existence-check helper went
# missing when v4.5 dropped the old hdf5r helpers.
.h5_safe_exists <- function(h5f, path) {
  tryCatch({
    if (is.null(path) || !nzchar(path)) return(FALSE)
    parts <- strsplit(path, "/", fixed = TRUE)[[1]]
    parts <- parts[nzchar(parts)]
    if (!length(parts)) return(FALSE)
    cur <- ""
    for (p in parts) {
      cur <- if (nzchar(cur)) paste0(cur, "/", p) else p
      ok <- tryCatch(h5f$exists(cur), error = function(e) FALSE)
      if (!isTRUE(ok)) return(FALSE)
    }
    TRUE
  }, error = function(e) FALSE)
}

# Read fts1/fts curve vectors (tBegin/tEnd/tPeak). These are plain numeric
# datasets at known paths; no references involved.
.rhdf5_read_fts <- function(fid) {
  out <- list()
  fname <- rhdf5::H5Fget_name(fid)
  for (slot in c("fts1", "fts")) {
    for (field in c("tBegin", "tEnd", "tPeak")) {
      for (p in c(paste0(slot, "/curve/", field),
                  paste0("res/", slot, "/curve/", field))) {
        if (.rhdf5_path_exists(fid, p)) {
          v <- tryCatch(as.numeric(rhdf5::h5read(fname, p)), error = function(e) NULL)
          if (!is.null(v)) {
            if (is.null(out[[slot]])) out[[slot]] <- list(curve = list())
            out[[slot]]$curve[[field]] <- v
            break
          }
        }
      }
    }
  }
  out
}

# Top-level: read a v7.3 .mat file into a named list resembling what
# readMat() returns. Only handles the fields the pipeline uses
# (cfuInfo1, cfuInfo2, cfuRelation, cfuGroupInfo, datPro, fts1/fts).
.h5_to_mat_list_rhdf5 <- function(path) {
  fid <- tryCatch(rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY"),
                  error = function(e) { message("  ❌ rhdf5 open error: ", e$message); NULL })
  if (is.null(fid)) return(NULL)
  on.exit({ try(rhdf5::H5Fclose(fid), silent = TRUE); try(rhdf5::H5close(), silent = TRUE) },
          add = TRUE)

  out <- list()
  # Cell arrays — includes cfuGroupInfo, which downstream code (Part B) accesses
  # as grp[gi, 1][[1]] / grp[gi, 2][[1]] / etc., requiring a 2D list-matrix.
  for (cn in c("cfuInfo1", "cfuInfo2", "cfuGroupInfo")) {
    if (.rhdf5_path_exists(fid, cn)) {
      ca <- .rhdf5_read_cell_array(fid, cn)
      if (!is.null(ca)) out[[cn]] <- ca
    }
  }
  # Plain numerics
  for (nm in c("cfuRelation", "datPro")) {
    if (.rhdf5_path_exists(fid, nm)) {
      v <- .rhdf5_read_numeric(fid, nm)
      if (!is.null(v)) out[[nm]] <- v
    }
  }
  # fts curves (only present in PRE companion files; harmless if absent)
  fts_out <- .rhdf5_read_fts(fid)
  for (nm in names(fts_out)) out[[nm]] <- fts_out[[nm]]

  out
}

# Self-test: confirm rhdf5 dereference works against a sample POST file.
# Returns TRUE if dereferencing succeeds and produces non-empty numeric data,
# FALSE otherwise. Intended to be run once at startup; if it fails the user
# sees a clear message and can abort before processing 1000+ files.
rhdf5_self_test <- function(sample_post_files) {
  # [v4.13] Robust, multi-file rhdf5 dereference self-test.
  #
  # PURPOSE (unchanged from v4.5): confirm rhdf5's H5R dereference machinery
  # actually works before committing to a long run, since hdf5r 1.3.12's
  # deref path is broken for these files and a broken backend would yield
  # empty per-cell records.
  #
  # BUG FIXED IN v4.13: the old version tested only mat_files[1] and called
  # H5Rdereference(refs[1], fid) with NO type guard.  When the first file's
  # cfuInfo1 is NOT a reference array (e.g. a file with 0/1 CFUs whose
  # cfuInfo1 comes back as a plain integer array), refs[1] is an integer and
  # rhdf5 internally does ref@ID -> "no applicable method for `@` applied to
  # an object of class 'integer'", aborting the whole run.  The MAIN reader
  # (.rhdf5_read_cell_array) already guards this with inherits(refs,"H5Ref")
  # and skips such files gracefully; the self-test now does the same.
  #
  # This matters specifically when TEST_MODE flips off: the sorted full list
  # starts at "..._V1_..." (string-sorts before "..._V10_..."), a different
  # first file than the TEST_MODE subset happened to start with.
  #
  # STRATEGY: walk up to the first 10 candidate files.  Pass as soon as ONE
  # reference-typed cfuInfo1 dereferences to non-empty data (proves rhdf5
  # works).  Only FAIL (abort) if we find >=3 reference-typed files and NONE
  # dereferences -- the genuine "rhdf5 is broken" signal.  If no candidate
  # exercises the deref path at all, proceed with a warning: the per-file
  # tryCatch (v4.11) will isolate any genuinely unreadable file during the
  # run rather than gating the entire batch on the self-test.
  files <- Filter(function(f) !is.null(f) && file.exists(f), sample_post_files)
  if (length(files) == 0L) {
    message("⚠️  rhdf5_self_test: no readable POST files supplied; skipping.")
    return(TRUE)
  }
  max_try      <- min(length(files), 10L)
  n_ref_tested <- 0L   # files whose cfuInfo1 was a reference array
  n_ref_ok     <- 0L   # of those, how many dereferenced to non-empty data
  for (i in seq_len(max_try)) {
    f <- files[i]
    outcome <- tryCatch({
      fid <- rhdf5::H5Fopen(f, flags = "H5F_ACC_RDONLY")
      on.exit({ try(rhdf5::H5Fclose(fid), silent = TRUE)
                try(rhdf5::H5close(),       silent = TRUE) }, add = TRUE)
      if (!.rhdf5_path_exists(fid, "cfuInfo1")) {
        "no_cfuinfo"
      } else {
        refs <- rhdf5::h5read(f, "cfuInfo1")
        if (!inherits(refs, "H5Ref")) {          # [v4.13] the guard the self-test was missing
          "not_ref"
        } else {
          did  <- rhdf5::H5Rdereference(refs[1], fid)
          data <- rhdf5::H5Dread(did)
          try(rhdf5::H5Dclose(did), silent = TRUE)
          if (length(data) > 0) "pass" else "empty"
        }
      }
    }, error = function(e) paste0("error: ", conditionMessage(e)))

    if (identical(outcome, "pass")) {
      n_ref_tested <- n_ref_tested + 1L
      n_ref_ok     <- n_ref_ok + 1L
      message(sprintf("✅ rhdf5 self-test passed on %s — H5R dereference returns data.",
                      basename(f)))
      break  # one confirmed deref is enough
    } else if (identical(outcome, "empty") || startsWith(outcome, "error: ")) {
      n_ref_tested <- n_ref_tested + 1L
      message(sprintf("   rhdf5_self_test: %s on %s — trying next file.",
                      outcome, basename(f)))
    } else {
      # no_cfuinfo / not_ref: this file doesn't exercise the deref path
      message(sprintf("   rhdf5_self_test: %s on %s (cfuInfo1 not reference-typed) — trying next file.",
                      outcome, basename(f)))
    }
  }

  if (n_ref_ok >= 1L) return(TRUE)
  if (n_ref_tested >= 3L) {
    message("❌ rhdf5 self-test FAILED: found reference-typed cfuInfo1 in ",
            n_ref_tested, " file(s) but H5R dereference never returned data. ",
            "rhdf5 install/version is the likely cause.")
    return(FALSE)
  }
  message(sprintf(
    "⚠️  rhdf5_self_test: none of the first %d POST file(s) exercised the dereference path (no reference-typed cfuInfo1 found); proceeding. Per-file error handling will isolate any unreadable files.",
    max_try))
  TRUE
}

# ── [v4.5] read_mat_smart() — rhdf5 backend for v7.3 ──────────────────────────
# Reads a MAT file regardless of version:
#   v5/v6  → R.matlab::readMat()  (returns named list, same as always)
#   v7.3   → rhdf5 + .h5_to_mat_list_rhdf5() (returns equivalent named list)
# Always returns a plain named R list or NULL on failure.
read_mat_smart <- function(path) {
  res <- tryCatch(readMat(path), error = function(e) e)
  if (!inherits(res, "error")) return(res)   # readMat succeeded

  if (grepl("HDF5|v7.3|Hierarchical", conditionMessage(res), ignore.case = TRUE)) {
    if (!requireNamespace("rhdf5", quietly = TRUE)) {
      message("  ⚠️  MAT v7.3 detected but rhdf5 not installed — see top-of-script BiocManager block.")
      return(NULL)
    }
    message("  ℹ️  MAT v7.3 detected — reading via rhdf5")
    out <- tryCatch(.h5_to_mat_list_rhdf5(path), error = function(e) {
      message("  ❌ rhdf5 parse error: ", e$message); NULL
    })
    return(out)
  }

  message("  ❌ MAT read error: ", conditionMessage(res))
  NULL
}

# ── [v1.4] .get_fts_vectors ────────────────────────────────────────────────────
# Extracts per-event tBegin, tEnd, tPeak integer vectors from the AQuA2 res list.
# read_mat_smart() guarantees res is always a plain named R list (never H5File),
# so we only need the readMat-list branch here.
# Tries res$fts1$curve first (newer format), then res$fts$curve (older format).
# Returns a named list(tBegin, tEnd, tPeak) or NULL if unavailable.
.get_fts_vectors <- function(res) {
  .try_field <- function(obj, field) {
    tryCatch({
      v <- obj[[field]]
      if (is.list(v)) v <- unlist(v, recursive = TRUE, use.names = FALSE)
      v <- suppressWarnings(as.integer(v))
      v <- v[is.finite(v) & v > 0]
      if (length(v) > 0) v else NULL
    }, error = function(e) NULL)
  }
  for (slot in c("fts1", "fts")) {
    obj <- tryCatch(res[[slot]][["curve"]], error = function(e) NULL)
    if (is.null(obj)) next
    tB <- .try_field(obj, "tBegin")
    tE <- .try_field(obj, "tEnd")
    tP <- .try_field(obj, "tPeak")
    if (!is.null(tB) && !is.null(tE) && length(tB) == length(tE)) {
      if (is.null(tP)) tP <- as.integer(round((tB + tE) / 2))
      return(list(tBegin = tB, tEnd = tE, tPeak = tP))
    }
  }
  NULL
}

# ── [v1.4] .align_to_peak ──────────────────────────────────────────────────────
# Resamples a single event trace (t_rel, y_bl) onto a common grid centred at
# the event's own peak.  Returns a data frame with columns t_aligned, y_aligned.
#   t_rel_vec  : original time vector (seconds, starting at 0 = event onset)
#   y_vec      : dF/F0 values (baseline-subtracted)
#   pre_sec    : how many seconds to include before the peak
#   post_sec   : how many seconds to include after  the peak
#   dt         : resampling interval (seconds); NULL = use median spacing of t_rel_vec
.align_to_peak <- function(t_rel_vec, y_vec, pre_sec, post_sec, dt = NULL) {
  if (length(t_rel_vec) < 3 || length(y_vec) < 3) return(NULL)
  i_pk    <- which.max(y_vec)
  t_pk    <- t_rel_vec[i_pk]
  t_aln   <- t_rel_vec - t_pk                     # shift: peak is now at 0
  if (is.null(dt)) dt <- median(diff(t_rel_vec), na.rm = TRUE)
  if (!is.finite(dt) || dt <= 0) dt <- 0.05
  t_out   <- seq(-pre_sec, post_sec, by = dt)
  # linear interpolation; extrapolated regions get NA
  y_out   <- approx(t_aln, y_vec, xout = t_out, rule = 1)$y
  data.frame(t_aligned = t_out, y_aligned = y_out)
}

slice_cfu_event_windows_exact <- function(cfuList, cfu_id, frame_interval,
                                          use_dff0 = TRUE,
                                          event_starts = NULL, event_ends = NULL,
                                          baseline_len_sec = 0,
                                          per_event_tpeak = NULL) {
  # [v1.4] per_event_tpeak: integer vector (same length as event_starts) of
  # the frame index of each event's peak within the full recording.
  # When supplied, t_peak_abs is stored in the output so peak-alignment can use it.
  sig_col <- if (isTRUE(use_dff0)) 6 else 5
  ids <- tryCatch(as.integer(sapply(seq_len(nrow(cfuList)), function(i) to_numeric_vec(cfuList[i,1][[1]])[1])),
                  error = function(e) integer(0))
  row_i <- if (length(ids)) which(ids == as.integer(cfu_id)) else integer(0)
  if (!length(row_i)) row_i <- as.integer(cfu_id)
  row_i <- row_i[1]
  v <- tryCatch(to_numeric_vec(cfuList[row_i, sig_col][[1]]), error = function(e) numeric(0))
  nT <- length(v)
  if (!length(v) || is.null(event_starts) || is.null(event_ends)) return(data.frame())
  if (length(event_starts) != length(event_ends)) stop("Event starts and ends length mismatch")
  
  rows <- vector("list", length(event_starts))
  for (i in seq_along(event_starts)) {
    start_idx <- max(1, event_starts[i])
    end_idx <- min(nT, event_ends[i])
    baseline_idx_start <- max(1, start_idx - round(baseline_len_sec / frame_interval))
    baseline_idx_end <- start_idx - 1
    # Skip if baseline invalid
    baseline_val <- if (baseline_idx_end >= baseline_idx_start)
      mean(v[baseline_idx_start:baseline_idx_end], na.rm = TRUE)
    else 0
    y_win <- v[start_idx:end_idx] - baseline_val
    t_rel <- seq(0, by = frame_interval, length.out = length(y_win))
    t_abs <- seq(start_idx, end_idx) * frame_interval
    
    rows[[i]] <- data.frame(
      CFU_ID = factor(cfu_id),
      EventID = i,
      t_rel = t_rel,
      t_peak_frame = if (!is.null(per_event_tpeak) && i <= length(per_event_tpeak))
        as.integer(per_event_tpeak[i]) else NA_integer_,
      t_abs = t_abs,
      y_raw = v[start_idx:end_idx],
      y_bl = y_win,
      e_time = t_abs[1],
      stringsAsFactors = FALSE
    )
  }
  dplyr::bind_rows(rows)
}



compute_one_event_metrics <- function(win_df) {
  d <- win_df
  if (!all(c("t_rel","y_bl") %in% names(d)) || nrow(d) == 0) {
    return(data.frame(Amplitude = NA_real_, t_peak = NA_real_, FWHM_sec = NA_real_, AUC = NA_real_,
                      Rise10_90_sec = NA_real_, Decay90_10_sec = NA_real_, Tau_est_sec = NA_real_))
  }
  i_peak <- which.max(d$y_bl)
  amp    <- as.numeric(d$y_bl[i_peak])
  t_peak <- as.numeric(d$t_rel[i_peak])
  
  y_half <- amp / 2
  i_rise <- which(d$t_rel <= t_peak)
  i_fall <- which(d$t_rel >= t_peak)
  interp_cross <- function(x1, y1, x2, y2, y_query) {
    if (!all(is.finite(c(x1,y1,x2,y2,y_query)))) return(NA_real_)
    if (y1 == y2) return(NA_real_)
    x1 + (y_query - y1) * (x2 - x1) / (y2 - y1)
  }
  t_rise <- NA_real_
  if (length(i_rise) >= 2) {
    idx <- which(diff(d$y_bl[i_rise] >= y_half) != 0)
    if (length(idx)) { j <- i_rise[max(idx)]; t_rise <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], y_half) }
  }
  t_fall <- NA_real_
  if (length(i_fall) >= 2) {
    idx <- which(diff(d$y_bl[i_fall] >= y_half) != 0)
    if (length(idx)) { j <- i_fall[min(idx)]; t_fall <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], y_half) }
  }
  fwhm <- if (is.finite(t_rise) && is.finite(t_fall)) (t_fall - t_rise) else NA_real_
  
  p10 <- 0.1 * amp; p90 <- 0.9 * amp
  t10 <- NA_real_; t90 <- NA_real_
  if (length(i_rise) >= 2) {
    idx10 <- which(diff(d$y_bl[i_rise] >= p10) != 0)
    idx90 <- which(diff(d$y_bl[i_rise] >= p90) != 0)
    if (length(idx10)) { j <- i_rise[max(idx10)]; t10 <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], p10) }
    if (length(idx90)) { j <- i_rise[max(idx90)]; t90 <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], p90) }
  }
  rise_10_90 <- if (is.finite(t10) && is.finite(t90)) (t90 - t10) else NA_real_
  
  t90d <- NA_real_; t10d <- NA_real_
  if (length(i_fall) >= 2) {
    idx90d <- which(diff(d$y_bl[i_fall] <= p90) != 0)
    idx10d <- which(diff(d$y_bl[i_fall] <= p10) != 0)
    if (length(idx90d)) { j <- i_fall[min(idx90d)]; t90d <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], p90) }
    if (length(idx10d)) { j <- i_fall[min(idx10d)]; t10d <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], p10) }
  }
  decay_90_10 <- if (is.finite(t90d) && is.finite(t10d)) (t10d - t90d) else NA_real_
  
  auc <- sum(diff(d$t_rel) * zoo::rollmean(d$y_bl, 2, fill = NA), na.rm = TRUE)
  
  y_1e <- amp / exp(1)
  t_tau <- NA_real_
  if (length(i_fall) >= 2) {
    idx1e <- which(diff(d$y_bl[i_fall] <= y_1e) != 0)
    if (length(idx1e)) { j <- i_fall[min(idx1e)]; t_cross <- interp_cross(d$t_rel[j], d$y_bl[j], d$t_rel[j+1], d$y_bl[j+1], y_1e); t_tau <- if (is.finite(t_cross)) (t_cross - t_peak) else NA_real_ }
  }
  
  data.frame(Amplitude = amp, t_peak = t_peak, FWHM_sec = fwhm, AUC = auc,
             Rise10_90_sec = rise_10_90, Decay90_10_sec = decay_90_10, Tau_est_sec = t_tau,
             stringsAsFactors = FALSE)
}

summarize_cfu_event_metrics <- function(win_long) {
  if (!nrow(win_long)) return(data.frame())
  by_event <- split(win_long, win_long$EventID)
  rows <- lapply(by_event, compute_one_event_metrics)
  met <- dplyr::bind_rows(rows, .id = "EventID")
  met$EventID <- as.integer(met$EventID)
  met
}

# ── [v1.3] Annotation helper ───────────────────────────────────────────────────
# Draws bracket/arrow annotations on a ggplot object given a trace data frame
# and a single-row metrics data frame (mean metrics across events).
# All annotation positions are derived from the mean trace, so they are
# consistent regardless of individual event jitter.
.add_waveform_annotations <- function(p, mean_df, m,
                                       bracket_color = annot_bracket_color,
                                       bracket_lwd   = annot_bracket_lwd,
                                       label_size    = annot_label_size) {
  if (is.null(m) || nrow(m) == 0) return(p)

  # [v4.7] Early-bailout if mean_df is degenerate.  Without this, the label
  # annotation at (x_max * 0.98, y_max * 0.98) can land at -Inf when mean_df
  # has no finite y values, and ggsave then errors with the "non-finite
  # location and/or size for viewport" message that aborted v4.6 runs.
  if (is.null(mean_df) || !is.data.frame(mean_df) || nrow(mean_df) == 0) return(p)
  if (!all(c("t_rel", "y") %in% names(mean_df)))                          return(p)
  mean_df <- mean_df[is.finite(mean_df$t_rel) & is.finite(mean_df$y), , drop = FALSE]
  if (nrow(mean_df) == 0) return(p)

  amp      <- mean(m$Amplitude,        na.rm = TRUE)
  t_pk     <- mean(m$t_peak,           na.rm = TRUE)
  fwhm     <- mean(m$FWHM_sec,         na.rm = TRUE)
  rise     <- mean(m$Rise10_90_sec,    na.rm = TRUE)   # [v4.7] was Rise_10_90_sec
  decay    <- mean(m$Decay90_10_sec,   na.rm = TRUE)   # [v4.7] was Decay_90_10_sec
  auc_val  <- mean(m$AUC,              na.rm = TRUE)
  tau_val  <- mean(m$Tau_est_sec,      na.rm = TRUE)
  n_ev     <- if ("EventID" %in% names(m)) dplyr::n_distinct(m$EventID) else nrow(m)

  if (!is.finite(amp) || !is.finite(t_pk)) return(p)

  y_half  <- amp / 2
  y_10    <- amp * 0.10
  y_90    <- amp * 0.90
  y_1e    <- amp * exp(-1)

  # ── Helpers: find x on mean trace at a given y (rising or falling side)
  interp_x <- function(df, y_query, side = c("rise","fall")) {
    side <- match.arg(side)
    if (side == "rise") df2 <- df[df$t_rel <= t_pk, ] else df2 <- df[df$t_rel >= t_pk, ]
    if (nrow(df2) < 2) return(NA_real_)
    diffs <- diff(df2$y)
    if (side == "rise") {
      idx <- which(diffs > 0 & df2$y[-nrow(df2)] <= y_query & df2$y[-1] >= y_query)
    } else {
      idx <- which(diffs < 0 & df2$y[-nrow(df2)] >= y_query & df2$y[-1] <= y_query)
    }
    if (!length(idx)) return(NA_real_)
    i <- if (side == "rise") max(idx) else min(idx)
    x1 <- df2$t_rel[i]; y1 <- df2$y[i]
    x2 <- df2$t_rel[i+1]; y2 <- df2$y[i+1]
    if (y2 == y1) return(NA_real_)
    x1 + (y_query - y1) * (x2 - x1) / (y2 - y1)
  }

  # Interpolated x positions
  x_half_rise  <- interp_x(mean_df, y_half,  "rise")
  x_half_fall  <- interp_x(mean_df, y_half,  "fall")
  x_10_rise    <- interp_x(mean_df, y_10,    "rise")
  x_90_rise    <- interp_x(mean_df, y_90,    "rise")
  x_90_fall    <- interp_x(mean_df, y_90,    "fall")
  x_10_fall    <- interp_x(mean_df, y_10,    "fall")
  x_1e_fall    <- interp_x(mean_df, y_1e,    "fall")

  # ── 1. AUC shaded region under mean trace ──────────────────────────────────
  p <- p + ggplot2::geom_area(
    data = mean_df, ggplot2::aes(x = t_rel, y = pmax(y, 0)),
    fill = annot_auc_fill, alpha = annot_auc_alpha, inherit.aes = FALSE)

  # ── 2. Amplitude arrow: baseline (y=0) → peak ──────────────────────────────
  p <- p + ggplot2::annotate("segment",
    x = t_pk, xend = t_pk, y = 0, yend = amp * 0.95,
    arrow = ggplot2::arrow(ends = "both", length = grid::unit(0.12, "cm"), type = "closed"),
    color = bracket_color, linewidth = bracket_lwd)

  # ── 3. FWHM double-headed bracket at y = amp/2 ─────────────────────────────
  if (all(is.finite(c(x_half_rise, x_half_fall)))) {
    p <- p +
      ggplot2::annotate("segment",
        x = x_half_rise, xend = x_half_fall, y = y_half, yend = y_half,
        arrow = ggplot2::arrow(ends = "both", length = grid::unit(0.12, "cm"), type = "open"),
        color = "#D6604D", linewidth = bracket_lwd) +
      # Tick marks at ends
      ggplot2::annotate("segment",
        x = x_half_rise, xend = x_half_rise,
        y = y_half - amp*0.04, yend = y_half + amp*0.04,
        color = "#D6604D", linewidth = bracket_lwd) +
      ggplot2::annotate("segment",
        x = x_half_fall, xend = x_half_fall,
        y = y_half - amp*0.04, yend = y_half + amp*0.04,
        color = "#D6604D", linewidth = bracket_lwd)
  }

  # ── 4. Rise 10–90% bracket ─────────────────────────────────────────────────
  if (all(is.finite(c(x_10_rise, x_90_rise)))) {
    p <- p +
      ggplot2::annotate("segment",
        x = x_10_rise, xend = x_90_rise, y = amp * 1.08, yend = amp * 1.08,
        arrow = ggplot2::arrow(ends = "both", length = grid::unit(0.10,"cm"), type = "open"),
        color = "#4DAC26", linewidth = bracket_lwd) +
      ggplot2::annotate("segment",
        x = x_10_rise, xend = x_10_rise, y = amp * 1.04, yend = amp * 1.12,
        color = "#4DAC26", linewidth = bracket_lwd) +
      ggplot2::annotate("segment",
        x = x_90_rise, xend = x_90_rise, y = amp * 1.04, yend = amp * 1.12,
        color = "#4DAC26", linewidth = bracket_lwd)
  }

  # ── 5. Decay 90–10% bracket ────────────────────────────────────────────────
  if (all(is.finite(c(x_90_fall, x_10_fall)))) {
    p <- p +
      ggplot2::annotate("segment",
        x = x_90_fall, xend = x_10_fall, y = amp * 1.08, yend = amp * 1.08,
        arrow = ggplot2::arrow(ends = "both", length = grid::unit(0.10,"cm"), type = "open"),
        color = "#8073AC", linewidth = bracket_lwd) +
      ggplot2::annotate("segment",
        x = x_90_fall, xend = x_90_fall, y = amp * 1.04, yend = amp * 1.12,
        color = "#8073AC", linewidth = bracket_lwd) +
      ggplot2::annotate("segment",
        x = x_10_fall, xend = x_10_fall, y = amp * 1.04, yend = amp * 1.12,
        color = "#8073AC", linewidth = bracket_lwd)
  }

  # ── 6. τ (1/e) decay marker: dashed vertical + horizontal at y=amp*exp(-1) ─
  if (is.finite(x_1e_fall)) {
    p <- p +
      ggplot2::annotate("segment",
        x = x_1e_fall, xend = x_1e_fall,
        y = 0, yend = y_1e,
        linetype = "dashed", color = "#B35806", linewidth = bracket_lwd * 0.8) +
      ggplot2::annotate("segment",
        x = t_pk, xend = x_1e_fall, y = y_1e, yend = y_1e,
        linetype = "dashed", color = "#B35806", linewidth = bracket_lwd * 0.8) +
      ggplot2::annotate("point",
        x = x_1e_fall, y = y_1e,
        color = "#B35806", size = 1.8)
  }

  # ── 7. Metric text label box (upper-right) ─────────────────────────────────
  # [v4.7] Guard against mean_df having no finite t_rel/y (max() of an empty
  # set is -Inf, which then propagates into annotate(x=, y=) and triggers
  # the grid "non-finite location/size for viewport" error during ggsave.
  # The early-bailout above should have caught this, but belt-and-braces.
  x_max <- suppressWarnings(max(mean_df$t_rel, na.rm = TRUE))
  y_max <- suppressWarnings(max(mean_df$y,     na.rm = TRUE))
  if (!is.finite(x_max) || !is.finite(y_max)) return(p)
  fmt   <- function(v, digits = 3)
    if (is.finite(v)) formatC(v, digits = digits, format = "g") else "—"

  label_lines <- paste0(
    "n = ", n_ev, "
",
    "Amp = ",        fmt(amp),      " dF/F₀
",
    "FWHM = ",       fmt(fwhm),     " s
",
    "Rise₁₀₋₉₀ = ", fmt(rise), " s
",
    "Decay₉₀₋₁₀ = ", fmt(decay), " s
",
    "τ = ",     fmt(tau_val),  " s
",
    "AUC = ",        fmt(auc_val,2))

  p <- p + ggplot2::annotate("label",
    x     = x_max * 0.98,
    y     = y_max * 0.98,
    label = label_lines,
    hjust = 1, vjust = 1,
    size  = label_size,
    fill  = "white", color = "black",
    label.size = 0.3, label.r = grid::unit(0.1,"lines"),
    family = "Arial")

  # ── 8. Legend strip at bottom: colour key for annotations ──────────────────
  leg <- data.frame(
    x    = c(0.02, 0.22, 0.44, 0.66),
    xend = c(0.18, 0.38, 0.60, 0.82),
    y    = rep(-Inf, 4), yend = rep(-Inf, 4),
    col  = c("#D6604D","#4DAC26","#8073AC","#B35806"),
    lbl  = c("FWHM","Rise 10–90%","Decay 90–10%","τ"))
  # (drawn as text only — avoids secondary axis complexity)
  p <- p + ggplot2::labs(caption = paste(
    "—— FWHM (red)",
    "  —— Rise 10–90% (green)",
    "  —— Decay 90–10% (purple)",
    "  —— τ 1/e (orange)",
    "  ░░ AUC (blue)")) +
    ggplot2::theme(plot.caption = ggplot2::element_text(
      size = 7, color = "grey40", hjust = 0, family = "Arial"))

  p
}


# ════════════════════════════════════════════════════════════════════════════════
# plot_cfu_peak_aligned_overlay                                         [v1.4 NEW]
# ════════════════════════════════════════════════════════════════════════════════
# Overlays all individual event traces for one CFU, aligned to their own peaks
# (t_peak = 0), then draws the mean of the aligned traces in black on top.
# Annotates the mean with bracket/arrow markers via .add_waveform_annotations().
#
# Alignment strategy:
#   1. For each EventID in win_long, locate t_peak from the per-event max of y_bl.
#      If t_peak_frame is stored in win_long, it is used to recompute t_peak
#      relative to the window start (more accurate for asymmetric windows).
#   2. Shift t_rel so peak = 0: t_aligned = t_rel - t_peak.
#   3. Interpolate every event onto a common grid
#      [-annot_align_pre_sec, +annot_align_post_sec] at resolution annot_align_interp_dt
#      (or frame_interval if NULL).
#   4. Mean waveform = row-wise mean across aligned events (NAs ignored).
#   5. Annotations placed on the mean aligned trace.
# ════════════════════════════════════════════════════════════════════════════════
plot_cfu_peak_aligned_overlay <- function(win_long, file_id, cfu_id, metrics_df,
                                           frame_interval = 0.05) {
  if (!isTRUE(make_annotated_waveforms))
    return(plot_cfu_event_overlay_legacy(win_long, file_id, cfu_id, metrics_df))

  # ── 1. Interpolation grid parameters ────────────────────────────────────────
  dt      <- if (!is.null(annot_align_interp_dt) && is.finite(annot_align_interp_dt))
               annot_align_interp_dt
             else frame_interval
  pre_s   <- annot_align_pre_sec
  post_s  <- annot_align_post_sec
  t_grid  <- seq(-pre_s, post_s, by = dt)

  # ── 2. Peak-align every event ───────────────────────────────────────────────
  ev_ids   <- unique(win_long$EventID)
  n_ev     <- length(ev_ids)
  mat_y    <- matrix(NA_real_, nrow = length(t_grid), ncol = n_ev)
  aligned_rows <- vector("list", n_ev)

  for (j in seq_along(ev_ids)) {
    eid  <- ev_ids[j]
    df_e <- win_long[win_long$EventID == eid, , drop = FALSE]
    if (nrow(df_e) < 3) next

    # Determine t_peak within the window
    if ("t_peak_frame" %in% names(df_e) && !is.na(df_e$t_peak_frame[1])) {
      # Recompute from absolute frame: t_peak_rel = (t_peak_frame - start_frame) * fi
      # We don't have start_frame here, so fall back to max(y_bl)
    }
    i_pk   <- which.max(df_e$y_bl)
    t_pk   <- df_e$t_rel[i_pk]
    t_aln  <- df_e$t_rel - t_pk

    # Interpolate onto common grid (rule=1: NA outside range)
    y_out  <- approx(t_aln, df_e$y_bl, xout = t_grid, rule = 1)$y
    mat_y[, j] <- y_out

    # Store for individual trace plotting
    aligned_rows[[j]] <- data.frame(
      t_aligned = t_grid,
      y_aligned = y_out,
      EventID   = eid)
  }

  # ── 3. Mean aligned trace ───────────────────────────────────────────────────
  mean_y   <- rowMeans(mat_y, na.rm = TRUE)
  mean_df  <- data.frame(t_rel = t_grid, y = mean_y)
  mean_df  <- mean_df[is.finite(mean_df$y), , drop = FALSE]

  # ── 4. Build long data frame of all aligned individual traces ───────────────
  aligned_long <- do.call(rbind, Filter(Negate(is.null), aligned_rows))
  aligned_long <- aligned_long[!is.na(aligned_long$y_aligned), , drop = FALSE]

  if (nrow(mean_df) == 0 || nrow(aligned_long) == 0) {
    message(sprintf("CFU %s: no aligned data — falling back to legacy overlay", cfu_id))
    return(plot_cfu_event_overlay_legacy(win_long, file_id, cfu_id, metrics_df))
  }

  # ── 5. y-axis headroom (for rise/decay brackets above trace) ─────────────────
  y_lim_top <- max(mean_df$y, na.rm = TRUE) * 1.22
  if (!is.finite(y_lim_top) || y_lim_top <= 0) y_lim_top <- NA

  # ── 6. Build ggplot ─────────────────────────────────────────────────────────
  y_lab <- if (isTRUE(event_zscore_per_window)) "Signal (z, window)" else "dF/F₀ (baseline-subtracted)"

  p <- ggplot2::ggplot() +
    # Individual aligned traces (grey, transparent)
    ggplot2::geom_line(
      data = aligned_long,
      ggplot2::aes(x = t_aligned, y = y_aligned, group = EventID),
      color = "grey60", alpha = annot_individual_alpha,
      linewidth = annot_individual_lwd) +
    # Mean aligned trace (black)
    ggplot2::geom_line(
      data = mean_df,
      ggplot2::aes(x = t_rel, y = y),
      color = "black", linewidth = annot_mean_lwd) +
    # Peak reference line
    ggplot2::geom_vline(xintercept = 0, color = "grey40",
                        linetype = "dotted", linewidth = 0.4) +
    ggplot2::labs(
      title    = paste0("CFU ", cfu_id, "  —  ", file_id),
      subtitle = paste0(n_ev, " events  |  peak-aligned  |  mean trace annotated"),
      x        = "Time relative to peak (s)",
      y        = y_lab) +
    theme_axes_black()

  if (is.finite(y_lim_top))
    p <- p + ggplot2::coord_cartesian(ylim = c(NA, y_lim_top), clip = "off")

  # ── 7. Build mean-metrics for annotation (re-derive from mean_df) ───────────
  # Use met_by_ev averages but override t_peak = 0 (since we aligned to peak)
  # [v4.7] Renamed Rise_10_90_sec -> Rise10_90_sec and Decay_90_10_sec ->
  # Decay90_10_sec to match the column names emitted by compute_one_event_metrics().
  m_mean <- data.frame(
    Amplitude       = mean(metrics_df$Amplitude,      na.rm = TRUE),
    t_peak          = 0,   # aligned axis: peak is always at 0
    FWHM_sec        = mean(metrics_df$FWHM_sec,        na.rm = TRUE),
    Rise10_90_sec   = mean(metrics_df$Rise10_90_sec,   na.rm = TRUE),
    Decay90_10_sec  = mean(metrics_df$Decay90_10_sec,  na.rm = TRUE),
    AUC             = mean(metrics_df$AUC,             na.rm = TRUE),
    Tau_est_sec     = mean(metrics_df$Tau_est_sec,     na.rm = TRUE),
    EventID         = n_ev,
    stringsAsFactors = FALSE)

  .add_waveform_annotations(p, mean_df, m_mean)
}

# ── [v1.3] Annotated overlay plot (all events + annotated mean) ───────────────
plot_cfu_annotated_overlay <- function(win_long, file_id, cfu_id, metrics_df) {
  if (!isTRUE(make_annotated_waveforms))
    return(plot_cfu_event_overlay_legacy(win_long, file_id, cfu_id, metrics_df))

  mean_df <- win_long |>
    dplyr::group_by(t_rel) |>
    dplyr::summarize(y = mean(y_bl, na.rm = TRUE), .groups = "drop")

  y_lim_top <- max(mean_df$y, na.rm = TRUE) * 1.20  # room for rise/decay brackets
  if (!is.finite(y_lim_top) || y_lim_top <= 0) y_lim_top <- NA

  p <- ggplot2::ggplot() +
    # Individual traces
    ggplot2::geom_line(
      data = win_long,
      ggplot2::aes(x = t_rel, y = y_bl, group = EventID),
      color = "grey60", alpha = annot_individual_alpha,
      linewidth = annot_individual_lwd) +
    # Mean trace on top
    ggplot2::geom_line(
      data = mean_df,
      ggplot2::aes(x = t_rel, y = y),
      color = "black", linewidth = annot_mean_lwd) +
    ggplot2::labs(
      title    = paste0("CFU ", cfu_id, "  —  ", file_id),
      subtitle = paste0(dplyr::n_distinct(win_long$EventID),
                        " events overlaid  |  mean trace annotated"),
      x = "Time relative to event onset (s)",
      y = if (isTRUE(event_zscore_per_window)) "Signal (z, window)" else "dF/F₀ (baseline-subtracted)") +
    theme_axes_black()

  if (is.finite(y_lim_top))
    p <- p + ggplot2::coord_cartesian(ylim = c(NA, y_lim_top), clip = "off")

  # Build mean-metrics row for annotation
  # [v4.7] Renamed Rise_10_90_sec -> Rise10_90_sec and Decay_90_10_sec ->
  # Decay90_10_sec to match the column names emitted by compute_one_event_metrics().
  m_mean <- data.frame(
    Amplitude       = mean(metrics_df$Amplitude,      na.rm = TRUE),
    t_peak          = mean(metrics_df$t_peak,          na.rm = TRUE),
    FWHM_sec        = mean(metrics_df$FWHM_sec,        na.rm = TRUE),
    Rise10_90_sec   = mean(metrics_df$Rise10_90_sec,   na.rm = TRUE),
    Decay90_10_sec  = mean(metrics_df$Decay90_10_sec,  na.rm = TRUE),
    AUC             = mean(metrics_df$AUC,             na.rm = TRUE),
    Tau_est_sec     = mean(metrics_df$Tau_est_sec,     na.rm = TRUE),
    EventID         = dplyr::n_distinct(win_long$EventID),
    stringsAsFactors = FALSE)

  .add_waveform_annotations(p, mean_df, m_mean)
}

# ── [v1.3] Annotated single-event plot ────────────────────────────────────────
plot_cfu_annotated_single <- function(ev_df, file_id, cfu_id, ev_metrics) {
  if (!isTRUE(make_annotated_waveforms))
    return(plot_cfu_event_single_legacy(ev_df, file_id, cfu_id, ev_metrics))

  mean_df <- ev_df |>
    dplyr::rename(y = y_bl) |>
    dplyr::select(t_rel, y)

  y_lim_top <- max(mean_df$y, na.rm = TRUE) * 1.20
  if (!is.finite(y_lim_top) || y_lim_top <= 0) y_lim_top <- NA

  ev_id <- if ("EventID" %in% names(ev_df)) unique(ev_df$EventID)[1] else "?"

  p <- ggplot2::ggplot(ev_df, ggplot2::aes(x = t_rel, y = y_bl)) +
    ggplot2::geom_line(color = "black", linewidth = annot_mean_lwd) +
    ggplot2::labs(
      title    = paste0("CFU ", cfu_id, "  Event ", ev_id, "  —  ", file_id),
      subtitle = paste0("t_onset = ",
        formatC(if (nrow(ev_df)) ev_df$e_time[1] else NA, digits = 3, format = "g"), " s"),
      x = "Time relative to event onset (s)",
      y = if (isTRUE(event_zscore_per_window)) "Signal (z, window)" else "dF/F₀ (baseline-subtracted)") +
    theme_axes_black()

  if (is.finite(y_lim_top))
    p <- p + ggplot2::coord_cartesian(ylim = c(NA, y_lim_top), clip = "off")

  m_single <- if (nrow(ev_metrics)) ev_metrics else data.frame()
  .add_waveform_annotations(p, mean_df, m_single)
}

# ── [v1.3] Legacy stubs (used when make_annotated_waveforms = FALSE) ──────────
plot_cfu_event_overlay_legacy <- function(win_long, file_id, cfu_id, metrics_df) {
  mean_df <- win_long |> dplyr::group_by(t_rel) |>
    dplyr::summarize(y = mean(y_bl, na.rm = TRUE), .groups = "drop")
  ann <- if (nrow(metrics_df))
    sprintf("n=%d  amp=%.3g  FWHM=%.3g s  AUC=%.3g",
            dplyr::n_distinct(win_long$EventID),
            mean(metrics_df$Amplitude, na.rm = TRUE),
            mean(metrics_df$FWHM_sec,  na.rm = TRUE),
            mean(metrics_df$AUC,       na.rm = TRUE))
  else sprintf("n=%d", dplyr::n_distinct(win_long$EventID))
  p <- ggplot2::ggplot(win_long, ggplot2::aes(x = t_rel, y = y_bl, group = EventID)) +
    ggplot2::geom_line(color = "grey70", alpha = 0.5, linewidth = 0.4) +
    ggplot2::geom_line(data = mean_df, ggplot2::aes(x = t_rel, y = y),
                       color = "black", linewidth = 0.9, inherit.aes = FALSE) +
    ggplot2::labs(title = paste0("CFU ", cfu_id, " event windows (", file_id, ")"),
                  subtitle = ann,
                  x = "Time rel. to event (s)",
                  y = if (event_zscore_per_window) "Signal (z, window)" else "Signal (baseline-sub)") +
    theme_axes_black()
  if (nrow(metrics_df) && any(is.finite(metrics_df$t_peak)))
    p <- p + ggplot2::geom_vline(xintercept = mean(metrics_df$t_peak, na.rm = TRUE),
                                 color = "#555555", alpha = 0.5, linewidth = 0.5)
  if (nrow(metrics_df) && any(is.finite(metrics_df$Amplitude)))
    p <- p + ggplot2::geom_hline(yintercept = mean(metrics_df$Amplitude, na.rm = TRUE) / 2,
                                 linetype = "dashed", color = "grey40", linewidth = 0.4)
  p
}
plot_cfu_event_single_legacy <- function(ev_df, file_id, cfu_id, ev_metrics) {
  p <- ggplot2::ggplot(ev_df, ggplot2::aes(x = t_rel, y = y_bl)) +
    ggplot2::geom_line(color = "black", linewidth = 0.8) +
    ggplot2::labs(title = paste0("CFU ", cfu_id, " Event ", unique(ev_df$EventID), " (", file_id, ")"),
                  x = "Time rel. to event (s)",
                  y = if (event_zscore_per_window) "Signal (z, window)" else "Signal (baseline-sub)") +
    theme_axes_black()
  if (nrow(ev_metrics)) {
    p <- p + ggplot2::geom_point(ggplot2::aes(x = ev_metrics$t_peak[1], y = ev_metrics$Amplitude[1]),
                                 color = "#B73779", size = 2)
    if (is.finite(ev_metrics$FWHM_sec[1]))
      p <- p + ggplot2::geom_hline(yintercept = ev_metrics$Amplitude[1] / 2,
                                   linetype = "dashed", color = "grey40", linewidth = 0.4)
  }
  p
}
# [v1.3] Forward-compat aliases so any downstream calls to old names still work
plot_cfu_event_overlay <- function(...) plot_cfu_annotated_overlay(...)
plot_cfu_event_single  <- function(...) plot_cfu_annotated_single(...)


# ════════════════════════════════════════════════════════════════════════════════
# plot_cfu_event_feature_panel                                          [v1.2 NEW]
# ════════════════════════════════════════════════════════════════════════════════
# Reads the _CFUEventMetrics.csv written by integrate_event_windows_per_cfu()
# and produces a 6-panel figure (one panel per waveform feature) showing
# violin + jitter distributions of each metric grouped and coloured by CFU_ID.
#
# Metrics plotted:
#   Amplitude        peak dF/F0 above baseline
#   FWHM_sec         full-width at half-maximum (seconds)
#   AUC              area under the curve (baseline-subtracted)
#   Rise10_90_sec    10-to-90 % rise time (seconds)
#   Decay90_10_sec   90-to-10 % decay time (seconds)
#   Tau_est_sec      1/e decay time constant (seconds)
#
# Output: <prefix>_CFUEventFeaturePanel.png in dir_dff0_events_features
# ════════════════════════════════════════════════════════════════════════════════
plot_cfu_event_feature_panel <- function(metrics_csv_path, prefix,
                                          min_events     = feature_panel_min_events,
                                          pt_alpha       = feature_panel_point_alpha,
                                          pt_size        = feature_panel_point_size,
                                          viol_alpha     = feature_panel_violin_alpha) {

  if (!isTRUE(make_feature_panels))               return(invisible(NULL))
  if (!file.exists(metrics_csv_path))             return(invisible(NULL))

  met <- tryCatch(
    readr::read_csv(metrics_csv_path, show_col_types = FALSE),
    error = function(e) { message("Feature panel: could not read ", metrics_csv_path); NULL })
  if (is.null(met) || nrow(met) == 0)             return(invisible(NULL))

  # Rename legacy column names from compute_one_event_metrics (Rise10_90_sec etc.)
  names(met) <- gsub("^Rise10_90_sec$",   "Rise10_90_sec",   names(met))
  names(met) <- gsub("^Decay90_10_sec$",  "Decay90_10_sec",  names(met))
  names(met) <- gsub("^Rise_10_90_sec$",  "Rise10_90_sec",   names(met))
  names(met) <- gsub("^Decay_90_10_sec$", "Decay90_10_sec",  names(met))

  # Ensure CFU_ID is a factor; filter to CFUs with enough events
  met$CFU_ID <- factor(met$CFU_ID)
  cfu_counts <- table(met$CFU_ID)
  keep_cfus  <- names(cfu_counts[cfu_counts >= min_events])
  if (length(keep_cfus) == 0) {
    message("Feature panel: no CFU has >= ", min_events, " events in ", prefix, " — skipped.")
    return(invisible(NULL))
  }
  met <- met[met$CFU_ID %in% keep_cfus, , drop = FALSE]
  met$CFU_ID <- factor(met$CFU_ID, levels = sort(unique(as.integer(as.character(met$CFU_ID)))))

  # Metric definitions: column name + display label + unit
  metric_defs <- list(
    list(col = "Amplitude",       label = "Amplitude",      unit = "(dF/F0)"),
    list(col = "FWHM_sec",        label = "FWHM",           unit = "(s)"),
    list(col = "AUC",             label = "AUC",            unit = "(dF/F0 · s)"),
    list(col = "Rise10_90_sec",   label = "Rise 10–90%", unit = "(s)"),
    list(col = "Decay90_10_sec",  label = "Decay 90–10%","unit" = "(s)"),
    list(col = "Tau_est_sec",     label = "Tau (1/e)",      unit = "(s)")
  )

  # Build one ggplot per metric, collect only those with usable data
  panel_plots <- list()
  n_cfus      <- nlevels(met$CFU_ID)
  pal         <- if (n_cfus <= 8)  RColorBrewer::brewer.pal(max(3, n_cfus), "Set2")[seq_len(n_cfus)]
                 else               scales::hue_pal()(n_cfus)

  for (md in metric_defs) {
    col <- md$col
    if (!col %in% names(met)) next
    d <- met[, c("CFU_ID", col), drop = FALSE]
    names(d)[2] <- "value"
    d <- d[is.finite(d$value), , drop = FALSE]
    if (nrow(d) < 2) next

    # Winsorize upper 1% per metric to keep axes readable
    q99 <- as.numeric(stats::quantile(d$value, 0.99, na.rm = TRUE))
    d$value <- pmin(d$value, q99)

    p <- ggplot2::ggplot(d, ggplot2::aes(x = CFU_ID, y = value, fill = CFU_ID, color = CFU_ID)) +
      ggplot2::geom_violin(trim = TRUE, alpha = viol_alpha, linewidth = 0.3,
                           show.legend = FALSE, scale = "width") +
      ggplot2::geom_jitter(width = 0.18, alpha = pt_alpha, size = pt_size,
                           show.legend = FALSE) +
      ggplot2::stat_summary(fun = median, geom = "crossbar",
                            width = 0.45, fatten = 1.5,
                            color = "black", linewidth = 0.4,
                            show.legend = FALSE) +
      ggplot2::scale_fill_manual(values  = stats::setNames(pal, levels(met$CFU_ID))) +
      ggplot2::scale_color_manual(values = stats::setNames(pal, levels(met$CFU_ID))) +
      ggplot2::labs(
        title = paste0(md$label, "  ", md$unit),
        x     = "CFU ID",
        y     = paste0(md$label, " ", md$unit)) +
      theme_axes_black(base_size = 9) +
      ggplot2::theme(
        plot.title   = ggplot2::element_text(size = 9, face = "bold", hjust = 0),
        axis.text.x  = ggplot2::element_text(size = 7, angle = 45, hjust = 1),
        axis.title.x = ggplot2::element_blank()
      )
    panel_plots[[col]] <- p
  }

  n_panels <- length(panel_plots)
  if (n_panels == 0) {
    message("Feature panel: no valid metrics to plot for ", prefix)
    return(invisible(NULL))
  }

  # Arrange into a grid (3 cols, up to 2 rows)
  ncols <- min(3L, n_panels)
  nrows <- ceiling(n_panels / ncols)

  # Use patchwork if available, else cowplot, else gridExtra
  combined <- tryCatch({
    if (requireNamespace("patchwork", quietly = TRUE)) {
      pw <- Reduce(`+`, panel_plots) +
        patchwork::plot_layout(ncol = ncols) +
        patchwork::plot_annotation(
          title    = paste0("Per-CFU Event Feature Distributions — ", prefix),
          subtitle = paste0(nrow(met), " events across ", nlevels(met$CFU_ID), " CFUs"),
          theme    = ggplot2::theme(
            plot.title    = ggplot2::element_text(size = 11, face = "plain",
                                                   color = "black", hjust = 0,
                                                   family = "Arial"),
            plot.subtitle = ggplot2::element_text(size = 9,  color = "grey30",
                                                   hjust = 0, family = "Arial")))
      pw
    } else if (requireNamespace("cowplot", quietly = TRUE)) {
      cowplot::plot_grid(plotlist = panel_plots, ncol = ncols,
                         labels = NULL, align = "hv")
    } else {
      gridExtra::arrangeGrob(grobs = panel_plots, ncol = ncols)
    }
  }, error = function(e) {
    message("Feature panel arrange error: ", e$message)
    NULL
  })

  if (is.null(combined)) return(invisible(NULL))

  out_png <- file.path(dir_dff0_events_features,
                       paste0(prefix, "_CFUEventFeaturePanel.png"))
  tryCatch(
    ggplot2::ggsave(out_png, plot = combined,
                    width  = ncols * 3.5,
                    height = nrows * 3.8 + 0.6,
                    dpi    = png_dpi),
    error = function(e) message("Feature panel ggsave error: ", e$message))
  message("Feature panel saved: ", basename(out_png))
  invisible(out_png)
}

integrate_event_windows_per_cfu <- function(cfuList, res, df_dff0, prefix, frame_interval, mat_path = NULL, fts_vecs = NULL) {
  if (!isTRUE(make_event_windows)) return(invisible(FALSE))
  if (is.null(cfuList)) return(invisible(FALSE))
  
  # [v1.1] CHANGE 1 — Derive Nglob from col-6 dFF0 trace length (NOT from fts1) ──────────────
  # v1.0 BROKEN:
  #   tBeg  <- as.integer(as.vector(res$fts1$curve$tBegin))  # integer(0) in new MAT format
  #   tEnd  <- as.integer(as.vector(res$fts1$curve$tEnd))    # integer(0) in new MAT format
  #   Nglob <- length(tBeg)                                  # => 0  => all ev_idx filtered out
  # v1.1 FIX: use dFF0 vector length from col 6, always present regardless of MAT version.
  Nglob <- tryCatch({
    v <- to_numeric_vec(cfuList[[1, 6]][[1]])
    if (length(v) > 10) length(v) else
      suppressWarnings(max(sapply(seq_len(nrow(cfuList)), function(i)
        length(to_numeric_vec(tryCatch(cfuList[[i, 6]][[1]], error = function(e) NULL)))
      ), na.rm = TRUE))
  }, error = function(e) 9999L)
  if (!is.finite(Nglob) || Nglob == 0) Nglob <- 9999L

  # [v1.1] Fallback symmetric half-window (used when fts unavailable or event_use_true_duration=FALSE)
  half_win <- max(1L, as.integer(round(event_window_sec / frame_interval / 2)))

  # [v2.1] FIX: PRE companion .mat now found via recursive list.files() instead of
  # hardcoded csv_dir/<folder_prefix>_results/<pre_prefix>.mat path that silently
  # failed whenever the PRE subfolder naming did not match exactly.
  # Uses same recursive search pattern as csv_files / mat_files at top of script.
  if (is.null(fts_vecs) && isTRUE(event_use_true_duration) && !is.null(mat_path)) {   # [opt] reuse caller's fts_vecs
    pre_prefix     <- sub("_res_cfu\\.mat$", "", basename(mat_path))   # <stem>_AQuA2
    companion_path <- get_pre_companion(pre_prefix)                    # [opt] O(1) via pre_mat_index
    if (!is.null(companion_path)) {
      message("  [v2.1] Loading fts from PRE companion (HDF5 direct): ", basename(companion_path))
      fts_vecs <- tryCatch({
        h5f <- hdf5r::H5File$new(companion_path, mode = "r")
        on.exit(try(h5f$close_all(), silent = TRUE), add = TRUE)

        .h5read_vec <- function(h5f, path) {
          if (!.h5_safe_exists(h5f, path)) return(NULL)
          v <- tryCatch(as.integer(round(as.numeric(h5f[[path]]$read()))),
                        error = function(e) NULL)
          if (!is.null(v) && length(v) > 0) v else NULL
        }

        # Try fts1 first (confirmed present), then fts
        fts_root <- if (.h5_safe_exists(h5f, "res/fts1")) "res/fts1" else
                    if (.h5_safe_exists(h5f, "fts1"))     "fts1"     else
                    if (.h5_safe_exists(h5f, "res/fts"))  "res/fts"  else
                    if (.h5_safe_exists(h5f, "fts"))      "fts"      else NULL

        if (is.null(fts_root)) {
          NULL
        } else {
          tB <- .h5read_vec(h5f, paste0(fts_root, "/curve/tBegin"))
          tE <- .h5read_vec(h5f, paste0(fts_root, "/curve/tEnd"))
          tP <- .h5read_vec(h5f, paste0(fts_root, "/curve/dffMaxFrame"))  # tPeak proxy
          if (is.null(tP))
            tP <- .h5read_vec(h5f, paste0(fts_root, "/curve/tBegin"))     # fallback: use tBegin
          if (!is.null(tB) && !is.null(tE) && length(tB) == length(tE))
            list(tBegin = tB, tEnd = tE, tPeak = tP)
          else
            NULL
        }
      }, error = function(e) { message("  [v2.1] HDF5 read error: ", e$message); NULL })

      if (!is.null(fts_vecs))
        message(sprintf("  [v2.1] fts vectors loaded: %d events (tBegin/tEnd/tPeak)",
                        length(fts_vecs$tBegin)))
      else
        message("  [v2.1] fts unavailable in PRE companion — falling back to symmetric half-window")
    } else {
      message("  [v2.1] PRE companion not found for: ", pre_prefix,
              " — falling back to symmetric half-window")
    }
  }

  # Helper: get CFU_ID from col 1 if available, else use row index (matches perCellPerEvent)
  .get_cfu_id_safe <- function(cfuList, i_row) {
    v <- tryCatch({
      x <- cfuList[i_row, 1][[1]]
      if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
      as.numeric(x)
    }, error = function(e) numeric(0))
    if (length(v) >= 1 && is.finite(v[1])) as.integer(v[1]) else as.integer(i_row)
  }
  
  # Iterate rows of cfuList directly (mirrors perCellPerEvent)
  for (i_cfu in seq_len(nrow(cfuList))) {
    cfu_id <- .get_cfu_id_safe(cfuList, i_cfu)
    
    # Event IDs from column 2 (vis-pass), normalize 0-based -> 1-based if needed
    ev_idx <- tryCatch({
      x <- cfuList[i_cfu, 2][[1]]
      if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
      as.numeric(x)
    }, error = function(e) numeric(0))
    ev_idx <- ev_idx[is.finite(ev_idx)]
    if (!length(ev_idx)) { message(sprintf("CFU %d - no events found", cfu_id)); next }
    if (any(ev_idx == 0)) ev_idx <- ev_idx + 1
    ev_idx <- as.integer(round(ev_idx))
    # [v4.20] Bound event indices by the EVENT count, not the frame count.
    # Nglob is the dF/F trace length (frames); using it here wrongly rejected
    # valid high-numbered events whenever a recording had more events than
    # frames (active organoids), dropping those CFUs from the feature panel
    # with "no valid event indices".  When fts is loaded, ev_idx indexes the
    # per-event arrays, so the correct ceiling is length(fts_vecs$tBegin)
    # (= n_events).  Only the fts-absent fallback below uses ev_idx as a frame
    # position, so it still needs the Nglob (frame) bound.
    .ev_max <- if (!is.null(fts_vecs) && length(fts_vecs$tBegin) > 0L)
                 length(fts_vecs$tBegin) else Nglob
    ev_idx <- ev_idx[ev_idx > 0 & ev_idx <= .ev_max]
    if (!length(ev_idx)) { message(sprintf("CFU %d - no valid event indices", cfu_id)); next }
    
    # [v1.4] Build per-event windows: true duration if fts available, else symmetric fallback
    if (!is.null(fts_vecs) && length(fts_vecs$tBegin) >= max(ev_idx)) {
      event_starts   <- as.integer(fts_vecs$tBegin[ev_idx])
      event_ends     <- as.integer(fts_vecs$tEnd[ev_idx])
      per_event_tpeak_frames <- as.integer(fts_vecs$tPeak[ev_idx])
      # Optionally pad pre/post around the true window for visual context
      pre_pad  <- max(0L, as.integer(round(annot_align_pre_sec  / frame_interval)))
      post_pad <- max(0L, as.integer(round(annot_align_post_sec / frame_interval)))
      event_starts <- pmax(1L,    event_starts - pre_pad)
      event_ends   <- pmin(Nglob, event_ends   + post_pad)
    } else {
      # Fallback: symmetric ±half_win centred on onset (v1.1 behaviour)
      event_starts   <- pmax(1L,    ev_idx - half_win)
      event_ends     <- pmin(Nglob, ev_idx + half_win)
      per_event_tpeak_frames <- NULL
    }
    
    # Pick signal (dF/F0 = col 6) and bounds-check
    sig_col <- if (isTRUE(event_use_dff0)) 6L else 5L
    sig_vec <- tryCatch({
      x <- cfuList[i_cfu, sig_col][[1]]
      if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
      as.numeric(x)
    }, error = function(e) numeric(0))
    if (!length(sig_vec)) { message(sprintf("CFU %d - empty signal (col %d)", cfu_id, sig_col)); next }
    
    keep <- which(event_starts >= 1 & event_ends <= length(sig_vec) & event_starts <= event_ends)
    if (!length(keep)) { message(sprintf("CFU %d - no windows within signal bounds", cfu_id)); next }
    event_starts <- event_starts[keep]
    event_ends   <- event_ends[keep]
    
    # Slice exact windows, compute metrics, and plot (unchanged downstream)
    win_long <- slice_cfu_event_windows_exact(
      cfuList, cfu_id, frame_interval,
      use_dff0 = event_use_dff0,
      event_starts = event_starts,
      event_ends = event_ends,
      baseline_len_sec = event_baseline_sec,
      per_event_tpeak = per_event_tpeak_frames   # [v1.4] true peak frames
    )
    if (nrow(win_long) == 0) { message(sprintf("CFU %d - no data extracted", cfu_id)); next }
    
    met_by_ev <- summarize_cfu_event_metrics(win_long)
    met_by_ev$CFU_ID <- cfu_id
    met_by_ev$EventID <- as.integer(met_by_ev$EventID)
    met_by_ev$e_time <- win_long |>
      dplyr::group_by(EventID) |>
      dplyr::summarize(e_time = dplyr::first(e_time), .groups = "drop") |>
      dplyr::pull(e_time)
    
    met_path <- file.path(dir_dff0_csv, paste0(prefix, "_CFUEventMetrics.csv"))
    if (file.exists(met_path)) readr::write_csv(met_by_ev, met_path, append = TRUE) else {
      dir.create(dirname(met_path), recursive = TRUE, showWarnings = FALSE)
      readr::write_csv(met_by_ev, met_path)
    }
    
    # [v1.4] Peak-aligned annotated overlay — one PNG per CFU
    # [v4.7] Routed through .safe_ggsave; viewport errors per CFU no longer
    # abort the integrate_event_windows loop for the whole file.
    # [v4.11] Gated by PLOT_EVERYTHING.  At ~14 CFUs/file × thousands of
    # files this is the dominant source of PNG output volume; suppressing
    # it for scale runs cuts PNG count by ~10x without affecting summary,
    # group, or relationship plots.
    if (isTRUE(PLOT_EVERYTHING)) {
      p_overlay <- plot_cfu_peak_aligned_overlay(win_long, file_id = prefix,
                                                  cfu_id = cfu_id, metrics_df = met_by_ev,
                                                  frame_interval = frame_interval)
      .safe_ggsave(
        file.path(dir_dff0_annot_overlay,
                  paste0(prefix, "_CFU", cfu_id, "_PeakAligned.png")),
        plot = p_overlay, tag = paste0("PeakAligned/", prefix, "_CFU", cfu_id),
        width = 8.5, height = 5.5, dpi = png_dpi)
    }

    # Legacy plain overlay (backward compat → EventWindows/Overlays/)
    # [v4.11] Same per-CFU multiplier as the annotated overlay above;
    # gate by PLOT_EVERYTHING for scale runs.
    if (isTRUE(PLOT_EVERYTHING)) {
      p_overlay_plain <- plot_cfu_event_overlay_legacy(win_long, file_id = prefix,
                                                        cfu_id = cfu_id, metrics_df = met_by_ev)
      .safe_ggsave(
        file.path(dir_dff0_events_overlay,
                  paste0(prefix, "_CFU", cfu_id, "_EventOverlay.png")),
        plot = p_overlay_plain, tag = paste0("EventOverlay/", prefix, "_CFU", cfu_id),
        width = 7.5, height = 4.4, dpi = png_dpi)
    }
  }

  invisible(TRUE)
}



# --------------------------------------- PART A: PRE + POST AGGREGATION ---------------------------------------
# §17-18 -- For each input file, opens the POST .mat (containing CFU
# detections from AQuA2) and the matching PRE .csv (raw event activity),
# extracts per-cell event indices and per-event activity, and computes
# one row per CFU cell with the columns:
#   File, CellID, NumberOfEvents, DurationOfVideo_seconds, FrequencyHz,
#   MeanIEI_sec, IEI_CV, and per-CSV-variable means (~37 columns).
# Accumulated rows are rbinded into <AnalysisName>_per_cell_summary.csv.
#
# Production-scale behaviour [v4.11]:
#   - tryCatch wraps each per-file iteration: an unhandled error in one
#     file is recorded with status="error" and the loop continues.
#   - Successful prefixes are appended to <out_dir>/<analysis_name>_
#     checkpoint.txt; resumed runs skip them (status="skipped_ckpt").
#   - gc() fires every GC_EVERY_N_FILES files.
# --------------------------------------- PART A: PRE + POST AGGREGATION ---------------------------------------
# [v4.8] DIAGNOSTIC ARTIFACTS
# Maintainers asked for a single self-contained file to share when a run
# misbehaves, because pasting thousands of console lines back is unreliable.
# Two artifacts are written by this section + the end-of-script handler:
#
#   1.  RESULTS/diagnostics_v4.8_<timestamp>.log
#       Tee of console output written by the pipeline.  message() and
#       warning() are intercepted via globalCallingHandlers (R >= 4.0) and
#       written to the file in real time without suppressing their normal
#       display on the console.  print()/cat()/auto-printed tables are
#       tee'd via sink(type="output", split=TRUE).  The resulting log is
#       close to what the user sees interactively, minus a few R-internal
#       lines that bypass both routes (rare).
#
#   2.  RESULTS/diagnostics_v4.8_<timestamp>.json
#       Structured summary written at script end (or at first crash) with
#       the facts a maintainer needs to triage without reading the full log:
#         * versions (R / platform / ggplot2 / rhdf5 / hdf5r)
#         * TEST_MODE config and actual DonorCond distribution after pick
#         * Per-file Part A: cells added, skip reason if any
#         * Per-file Part B: ggsave failures grouped by tag and file
#         * Modeling class counts per grouping target
#
# Naming uses a timestamp so re-running the script does not clobber the
# previous run's diagnostics.  The log is opened in write mode, not append,
# because each run owns its own filename.
.v48_diag_stem <- file.path(out_dir,
  sprintf("diagnostics_%s_%s%s", SCRIPT_VERSION,   # [v4.10] was hardcoded "v4.8"
          format(Sys.time(), "%Y%m%d_%H%M%S"), .shard_sfx))  # [v4.18] shard-suffixed
.v48_log_path  <- paste0(.v48_diag_stem, ".log")
.v48_json_path <- paste0(.v48_diag_stem, ".json")

# [v4.9] Diagnostic capture redesigned.
# v4.8 combined sink(type="output", split=TRUE) with globalCallingHandlers
# for messages.  In RStudio this duplicated every message (once via the
# handler, once via stderr-being-routed-through-stdout-sink), and the
# end-of-script cleanup looped forever trying to pop RStudio's own message
# sink.  v4.9 uses ONLY globalCallingHandlers and never opens a sink.
#
# Consequences vs v4.8:
#   - No more duplicated console output.
#   - No more RStudio hang at script end.
#   - print()/cat()/auto-printed-table output is NOT captured in the log
#     file (it remains visible on console only).  The structural facts
#     -- DonorCond table, modeling class counts, etc. -- are recorded in
#     the JSON summary, which is what's actually needed for triage.
.v48_log_con <- file(.v48_log_path, open = "wt")
.v48_log_write <- function(s) {
  tryCatch({
    cat(s, file = .v48_log_con, sep = "")
    flush(.v48_log_con)
  }, error = function(e) NULL)
}

# [v4.9] Warning noise filter.  Each pattern is a regex matched against the
# warning message text.  Matches are muffled (no console display, no log
# write) but counted -- the counts appear in the JSON summary under
# `muffled_warning_counts` so volume is still visible.  Patterns chosen
# from the v4.8 run output where each of these fired dozens of times
# inline and obscured real diagnostic signal.
.v49_muffle_patterns <- c(
  "open HDF5 file handle exists",      # rhdf5::h5read keeps handles alive
  "Ignoring unknown parameters",        # annotate(label, label.size=...) in newer ggplot2
  "Removed [0-9]+ rows? containing",    # standard ggplot NA-removal notice
  "longer object length is not a multiple",  # harmless recycling in plot helpers
  # [v4.10] ggsignif emits this 402 times per v4.9 run.  When a feature has
  # degenerate within-group data (zero variance / 1 non-NA value), the
  # stat_signif() bracket annotation can't compute.  The Kruskal-Wallis +
  # FSA::dunnTest statistics that the plots are annotating still produce
  # correct p-values, so this is a presentation-only failure.  Muffling
  # also kills most of the recycling warnings already in the list above,
  # since those fire from inside the same failed stat_signif() pathway.
  "Computation failed in.*stat_signif"
)
.v49_muffled_counts <- list()

# [v4.9] Warning handler.  Three things to do per warning:
#   1. Check it against the muffle list; if match, increment counter and
#      muffleWarning so neither console nor log sees it.
#   2. Otherwise, write to log file (so the diagnostic log captures it).
#   3. Let it propagate to the default handler so the console still shows
#      it (calling handlers don't suppress unless they explicitly muffle).
.v49_warning_handler <- function(w) {
  msg <- conditionMessage(w)
  # [v4.21] Defensive guard.  A handler left registered from a PREVIOUS source
  # in the same R session (re-sourcing, or clearing the workspace, WITHOUT
  # Session > Restart R) can fire during package loading -- before this run has
  # re-defined the muffle state -- and previously crashed with
  # "object '.v49_muffle_patterns' not found".  If the infrastructure isn't
  # present, let the warning pass through untouched rather than erroring.
  if (!exists(".v49_muffle_patterns", envir = .GlobalEnv, inherits = FALSE) ||
      !exists(".v48_log_write", mode = "function")) return(invisible(NULL))
  for (pat in .v49_muffle_patterns) {
    if (grepl(pat, msg, perl = TRUE)) {
      .GlobalEnv$.v49_muffled_counts[[pat]] <-
        (if (is.null(.GlobalEnv$.v49_muffled_counts[[pat]])) 0L
         else .GlobalEnv$.v49_muffled_counts[[pat]]) + 1L
      invokeRestart("muffleWarning")
      return(invisible(NULL))
    }
  }
  .v48_log_write(paste0("Warning: ", msg, "\n"))
}

# globalCallingHandlers requires R >= 4.0 (April 2020).  Calling handlers
# run alongside the default handlers, so the console still shows messages
# and (non-muffled) warnings as normal.
# [v4.10] When the script is re-sourced in the same R session, the previous
# run's handlers are still registered, and globalCallingHandlers() emits
# "pushing duplicate `message` handler on top of the stack" as a *message*
# (not a warning -- options(warn = -1) does not affect it).  We cannot
# wrap the call in suppressMessages() because that uses withCallingHandlers
# internally, and globalCallingHandlers() refuses to be invoked while any
# calling handler is on the stack.  Instead we briefly redirect the
# message stream to nullfile() at the connection level: sink(nullfile(),
# type = "message") routes stderr writes to /dev/null for the duration of
# the call, and is popped immediately after.  This is scoped tightly to
# the single globalCallingHandlers() invocation and is safe with RStudio's
# own message sink (we pop only the sink we pushed).
.v410_install_handlers <- function(msg_h, warn_h) {
  if (!exists("globalCallingHandlers", mode = "function")) return(invisible(NULL))
  .nullcon <- file(nullfile(), open = "wt")
  sink(.nullcon, type = "message")
  on.exit({
    try(sink(type = "message"), silent = TRUE)
    try(close(.nullcon),         silent = TRUE)
  }, add = TRUE)
  # [v4.10] No tryCatch here.  tryCatch / try() / withCallingHandlers all
  # push an entry onto R's handler stack, and globalCallingHandlers
  # refuses to run while ANY handler is on that stack (the check is for
  # non-empty stack, not for calling-vs-exiting type).  The existence
  # check above gates us to R >= 4.0; if globalCallingHandlers errors for
  # any other reason it's a real problem worth crashing on.
  globalCallingHandlers(message = msg_h, warning = warn_h)
  invisible(NULL)
}
# [v4.10] Message handler filters the "pushing duplicate" notice from the
# log file.  The sink-to-nullfile bracket inside .v410_install_handlers
# suppresses the CONSOLE display of that notice, but the notice ALSO goes
# through the calling-handler chain -- so if a previous install left our
# handler active, that handler writes the notice to the log file even
# though the console no longer shows it.  Adding a one-line filter here
# keeps the log clean too.
.v410_message_handler <- function(m) {
  s <- conditionMessage(m)
  if (grepl("pushing duplicate .* handler", s, perl = TRUE)) return(invisible(NULL))
  if (!exists(".v48_log_write", mode = "function")) return(invisible(NULL))  # [v4.21] stale-handler guard
  .v48_log_write(s)
}
.v410_install_handlers(
  msg_h  = .v410_message_handler,
  warn_h = .v49_warning_handler)

# Accumulators populated by the pipeline as it runs.  Each is written into
# the JSON summary by .v48_write_diagnostics_summary() at script end.
.v48_ggsave_failures <- list()      # populated by .safe_ggsave on error
.v48_part_a_files    <- list()      # populated in Part A loop
.v48_vis_files       <- list()      # populated in Part B vis loop
.v48_modeling        <- list()      # populated in modeling pass

# [v4.11] Checkpoint / resume.  After each Part A file completes
# successfully, its prefix is appended to a checkpoint file in out_dir.
# On startup, if CHECKPOINT_RESUME is TRUE and the file exists, those
# prefixes are loaded into .v411_processed_set and skipped.  Delete the
# checkpoint file or set CHECKPOINT_RESUME=FALSE to force a clean restart.
.v411_checkpoint_path <- file.path(out_dir,
  paste0(AnalysisName, "_checkpoint", .shard_sfx, ".txt"))  # [v4.18] shard-suffixed in process stage
.v411_processed_set <- if (isTRUE(CHECKPOINT_RESUME) &&
                           file.exists(.v411_checkpoint_path)) {
  readLines(.v411_checkpoint_path, warn = FALSE)
} else {
  character(0)
}
if (length(.v411_processed_set)) {
  message(sprintf("[%s] CHECKPOINT_RESUME on: %d prefix(es) already processed will be skipped",
                  SCRIPT_VERSION, length(.v411_processed_set)))
}
.v411_record_processed <- function(prefix) {
  tryCatch(cat(prefix, "\n", file = .v411_checkpoint_path,
               append = TRUE, sep = ""),
           error = function(e) NULL)
}
.v411_is_processed <- function(prefix) prefix %in% .v411_processed_set

# [v4.11] Periodic garbage collection.  Each loop pass increments the
# counter; gc() fires when the counter is a multiple of GC_EVERY_N_FILES.
# Cheap insurance against unbounded memory growth from transient ggplot
# objects, spatial map matrices, and HDF5 read buffers.  Setting
# GC_EVERY_N_FILES=0 disables.
.v411_gc_counter <- 0L
.v411_maybe_gc <- function(label = "file") {
  .GlobalEnv$.v411_gc_counter <- .v411_gc_counter + 1L
  if (GC_EVERY_N_FILES > 0L &&
      .v411_gc_counter %% GC_EVERY_N_FILES == 0L) {
    invisible(gc(verbose = FALSE))
    message(sprintf("  [%s] gc() at %s %d", SCRIPT_VERSION,
                    label, .v411_gc_counter))
  }
}

# Write the JSON summary and close the log.  Wrapped in tryCatch so a
# failure inside the writer does not mask the original error.
.v48_write_diagnostics_summary <- function() {
  tryCatch({
    fails_by_tag <- list()
    if (length(.v48_ggsave_failures)) {
      tags <- vapply(.v48_ggsave_failures, function(x) x$tag, character(1))
      for (t in unique(tags)) {
        rows <- .v48_ggsave_failures[tags == t]
        fails_by_tag[[t]] <- list(
          count = length(rows),
          examples = lapply(head(rows, 3), function(r) list(
            file = r$file, message = r$message)))
      }
    }
    summary <- list(
      version       = SCRIPT_VERSION,   # [v4.10] was hardcoded "v4.8"
      timestamp     = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      analysis_name = AnalysisName,
      # [v4.11] Record scaling knob values so a 2000-file diagnostic JSON
      # is self-describing -- you can tell from the JSON alone whether the
      # run used PLOT_EVERYTHING=FALSE, what GC interval, and whether
      # resume was active.
      scaling_config = list(
        gc_every_n_files  = GC_EVERY_N_FILES,
        checkpoint_resume = isTRUE(CHECKPOINT_RESUME),
        plot_everything   = isTRUE(PLOT_EVERYTHING),
        checkpoint_path   = .v411_checkpoint_path,
        n_prefixes_resumed = length(.v411_processed_set)
      ),
      versions = list(
        R         = paste(R.version$major, R.version$minor, sep = "."),
        platform  = R.version$platform,
        ggplot2   = as.character(utils::packageVersion("ggplot2")),
        rhdf5     = tryCatch(as.character(utils::packageVersion("rhdf5")),
                             error = function(e) "not installed"),
        hdf5r     = tryCatch(as.character(utils::packageVersion("hdf5r")),
                             error = function(e) "not installed"),
        R.matlab  = tryCatch(as.character(utils::packageVersion("R.matlab")),
                             error = function(e) "not installed")),
      io = list(
        csv_dir = csv_dir, mat_dir = mat_dir, out_dir = out_dir,
        log_path = .v48_log_path),
      test_mode = list(
        enabled = isTRUE(TEST_MODE),
        n_requested = as.integer(TEST_N),
        seed = as.integer(TEST_SEED),
        n_actual = tryCatch(nrow(pairs), error = function(e) NA_integer_),
        donor_cond_distribution = tryCatch(
          as.list(table(pairs$DonorCond)),
          error = function(e) list())),
      part_a = list(
        files_processed = tryCatch(files_processed, error = function(e) NA_integer_),
        files_skipped   = tryCatch(files_skipped,   error = function(e) NA_integer_),
        total_cells_added = tryCatch(res_i, error = function(e) NA_integer_),
        per_file = .v48_part_a_files),
      vis_loop = list(
        files_total = length(.v48_vis_files),
        per_file = .v48_vis_files,
        ggsave_failures_by_tag = fails_by_tag,
        ggsave_failures_total  = length(.v48_ggsave_failures)),
      modeling = .v48_modeling,
      # [v4.9] Tally of warnings muffled by the noise filter.  Each entry
      # is a regex pattern -> count of matched warnings.  If a count is
      # surprisingly high, that's a hint the underlying cause is worth
      # investigating even though the warning itself is harmless.
      muffled_warning_counts = .v49_muffled_counts)
    writeLines(jsonlite::toJSON(summary, pretty = TRUE, auto_unbox = TRUE,
                                null = "null", na = "string"),
               .v48_json_path)
    message(sprintf("\n[%s] Diagnostic summary written: %s",
                    SCRIPT_VERSION, .v48_json_path))
    message(sprintf("[%s] Diagnostic log written:     %s",
                    SCRIPT_VERSION, .v48_log_path))
  }, error = function(e) {
    try(message(sprintf("[%s] Diagnostic summary write FAILED: %s",
                        SCRIPT_VERSION, conditionMessage(e))), silent = TRUE)
  })
  # [v4.9] Replace handlers with no-ops.  globalCallingHandlers persists
  # across script invocations until explicitly replaced, so without this
  # the handlers would fire on every subsequent message/warning in the
  # same R session (e.g. interactive prompts, package loads).  No-op
  # functions are the documented way to "remove" a global handler.
  # [v4.10] Re-uses the .v410_install_handlers helper, which suppresses
  # the "pushing duplicate handler" notice via sink-to-nullfile.
  .v410_install_handlers(
    msg_h  = function(m) invisible(NULL),
    warn_h = function(w) invisible(NULL))
  # NB v4.9: we no longer call sink() here.  v4.8 had a cleanup loop that
  # hung in RStudio because RStudio's internal message sink could not be
  # popped from user code (sink() returned silently without decrementing
  # sink.number(), causing an infinite loop that try() could not catch).
  try(close(.v48_log_con), silent = TRUE)
}

# Run the summary writer when the R session ends (catches both clean exits
# and Ctrl-C / errors that bubble all the way out).  reg.finalizer fires
# during garbage collection of the connection; .Last fires on session exit.
# Both are best-effort; the JSON write is idempotent.
.Last <- function() try(.v48_write_diagnostics_summary(), silent = TRUE)

message(sprintf("[%s] Diagnostic log: %s", SCRIPT_VERSION, .v48_log_path))
message(sprintf("[%s] R %s.%s | platform: %s | ggplot2 %s | started: %s",
                SCRIPT_VERSION,
                R.version$major, R.version$minor, R.version$platform,
                utils::packageVersion("ggplot2"),
                format(Sys.time())))

# [v4.12] Echo the effective run configuration so the active mode is never
# ambiguous.  This prints to both console and the diagnostic log.  If you
# set TEST_MODE <- FALSE but this line still reports TEST_MODE: TRUE, you
# sourced an older file or the edit didn't take.
message(sprintf(
  "[%s] RUN CONFIG | TEST_MODE: %s%s | PLOT_EVERYTHING: %s | CHECKPOINT_RESUME: %s | GC_EVERY_N_FILES: %d",
  SCRIPT_VERSION,
  TEST_MODE,
  if (isTRUE(TEST_MODE)) sprintf(" (TEST_N=%d, seed=%d)", TEST_N, TEST_SEED) else "",
  PLOT_EVERYTHING, CHECKPOINT_RESUME, GC_EVERY_N_FILES))
message(sprintf("[%s] RUN CONFIG | analysis: %s | csv_dir: %s | mat_dir: %s | out_dir: %s",
                SCRIPT_VERSION, AnalysisName, csv_dir, mat_dir, out_dir))

message("Output root: ", out_dir)
message("Per-cell summary will be written to: ", out_csv)
message("= Starting analysis: ", AnalysisName, " =")
message(sprintf("Temporal resolution: %.4f s/frame", frame_interval))

# ============= [hCO v1] PART A -- FILE LISTING / PAIRING =====================
# Replaces the old csv_files / mat_files / mat_prefixes block (incl. the v3.0
# _AQuA2 strip, which broke matching for hCO where BOTH sides carry _AQuA2).
post_files <- list.files(mat_dir, pattern = "_AQuA2_res_cfu\\.mat$", full.names = TRUE, recursive = TRUE)
csv_all    <- list.files(csv_dir, pattern = "_AQuA2_Ch1\\.csv$",     full.names = TRUE, recursive = TRUE)
pre_all    <- list.files(companion_mat_dir, pattern = "_AQuA2\\.mat$",  full.names = TRUE, recursive = TRUE)  # [v4.14] was csv_dir; now honors companion_mat_dir

key_post <- sub("_res_cfu\\.mat$", "", basename(post_files))   # <stem>_AQuA2
key_csv  <- sub("_Ch[0-9]+\\.csv$", "", basename(csv_all))     # <stem>_AQuA2
key_pre  <- sub("\\.mat$", "", basename(pre_all))              # <stem>_AQuA2

pairs <- data.frame(key = key_post, post = post_files, stringsAsFactors = FALSE)
pairs$csv     <- csv_all[match(pairs$key, key_csv)]
pairs$pre_mat <- pre_all[match(pairs$key, key_pre)]

n_no_csv <- sum(is.na(pairs$csv)); n_no_pre <- sum(is.na(pairs$pre_mat))
message(sprintf("Pairing: %d POST files | missing CSV: %d | missing PRE .mat: %d",
                nrow(pairs), n_no_csv, n_no_pre))
if (n_no_csv > 0) message("  e.g. no CSV for: ",
                          paste(head(pairs$key[is.na(pairs$csv)], 3), collapse = ", "))
if (n_no_pre > 0) message("  e.g. no PRE .mat for: ",
                          paste(head(pairs$key[is.na(pairs$pre_mat)], 3), collapse = ", "))

meta <- parse_stems(sub("_AQuA2$", "", pairs$key))
pairs <- cbind(pairs, meta)

message("Donor x Condition (full set, parsed):")
print(table(Donor = pairs$Donor, Condition = pairs$Condition, useNA = "ifany"))

# [v4.26] Promoter distribution (CAMK2A / DLX / ...).  NA = the file
# carried no recognised promoter token; either the recording genuinely
# lacks one, or PROMOTER_TOKENS needs a new entry.
if ("Promoter" %in% names(pairs)) {
  message("Promoter x Condition:")
  print(table(Promoter = pairs$Promoter, Condition = pairs$Condition, useNA = "ifany"))
  n_no_prom <- sum(is.na(pairs$Promoter))
  if (n_no_prom > 0L)
    message(sprintf("  [info] %d recording(s) have no recognised promoter token (Promoter=NA).", n_no_prom))
}

# [v4.16] Timepoint distribution + unbinned (gap) report.
message("Timepoint (from AgeDay) x Condition:")
print(table(Timepoint = pairs$Timepoint, Condition = pairs$Condition, useNA = "ifany"))
n_unbinned <- sum(!is.na(pairs$AgeDay) & is.na(pairs$Timepoint))
if (n_unbinned > 0) {
  gap_days <- sort(unique(pairs$AgeDay[!is.na(pairs$AgeDay) & is.na(pairs$Timepoint)]))
  message(sprintf("  [warn] %d recording(s) have an AgeDay outside all TIMEPOINT_BINS windows (days: %s) -> Timepoint=NA, EXCLUDED from Timepoint/CondTimepoint analyses.",
                  n_unbinned, paste(gap_days, collapse = ", ")))
  message("         e.g. d100 sits in the 91-109 gap.  Widen a window or add a bin in TIMEPOINT_BINS if these should be included.")
}
n_no_age <- sum(is.na(pairs$AgeDay))
# [v4.27] FOXP1 filenames carry no d<NN> age token by design, so AgeDay/Timepoint
# are NA for all recordings -- suppress the (expected) no-age warning for this build.
if (n_no_age > 0 && !identical(AnalysisName, "FOXP1_WT_HET"))
  message(sprintf("  [warn] %d recording(s) have no parseable AgeDay token (no d<NN>) -> Timepoint=NA.", n_no_age))
# [v4.27] For FOXP1, "parsed" means Condition (= genotype) resolved; Donor is NA
# by design and must NOT count as unparsed.
.unparsed_mask <- if (identical(AnalysisName, "FOXP1_WT_HET"))
                    is.na(pairs$Condition) else (is.na(pairs$Donor) | is.na(pairs$Condition))
n_unparsed <- sum(.unparsed_mask)
if (n_unparsed > 0)
  message("  [warn]  ", n_unparsed, " file(s) with unparsed metadata -- inspect: ",
          paste(head(pairs$key[.unparsed_mask], 5), collapse = ", "))

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(pairs, file.path(out_dir, "pairing_and_parse_audit.csv"))

# [v4.23] Apply recording-level scope filters (donor / condition / timepoint /
# baseline-active).  Done AFTER the audit write so the audit reflects the
# full pairing result; only the downstream processing is scoped.
if (!is.null(INCLUDE_DONORS)) {
  before <- nrow(pairs)
  pairs  <- pairs[!is.na(pairs$Donor) & pairs$Donor %in% as.character(INCLUDE_DONORS), , drop = FALSE]
  message(sprintf("[v4.23] INCLUDE_DONORS filter %s -> %d of %d recordings kept.",
                  paste(INCLUDE_DONORS, collapse=","), nrow(pairs), before))
}
if (!is.null(INCLUDE_CONDITIONS)) {
  before <- nrow(pairs)
  pairs  <- pairs[!is.na(pairs$Condition) & pairs$Condition %in% INCLUDE_CONDITIONS, , drop = FALSE]
  message(sprintf("[v4.23] INCLUDE_CONDITIONS filter %s -> %d of %d recordings kept.",
                  paste(INCLUDE_CONDITIONS, collapse=","), nrow(pairs), before))
}
if (!is.null(INCLUDE_TIMEPOINTS)) {
  before <- nrow(pairs)
  pairs  <- pairs[!is.na(pairs$Timepoint) & pairs$Timepoint %in% INCLUDE_TIMEPOINTS, , drop = FALSE]
  message(sprintf("[v4.23] INCLUDE_TIMEPOINTS filter %s -> %d of %d recordings kept.",
                  paste(INCLUDE_TIMEPOINTS, collapse=","), nrow(pairs), before))
}
if (!is.null(INCLUDE_PROMOTERS) && "Promoter" %in% names(pairs)) {
  before <- nrow(pairs)
  pairs  <- pairs[!is.na(pairs$Promoter) & pairs$Promoter %in% toupper(INCLUDE_PROMOTERS), , drop = FALSE]
  message(sprintf("[v4.26] INCLUDE_PROMOTERS filter %s -> %d of %d recordings kept.",
                  paste(INCLUDE_PROMOTERS, collapse=","), nrow(pairs), before))
}
if (nrow(pairs) == 0L)
  stop("[v4.23] Scope filters left zero recordings -- relax INCLUDE_*.")

pre_mat_index <- stats::setNames(pairs$pre_mat, pairs$key)

if (isTRUE(TEST_MODE)) {
  usable <- pairs[!is.na(pairs$csv) & !is.na(pairs$pre_mat), , drop = FALSE]
  set.seed(TEST_SEED)
  grp <- split(seq_len(nrow(usable)), usable$DonorCond)
  pick <- integer(0)
  # [v4.7 FIX] sample(x, 1) treats x as `n` when length(x)==1 -- classic R
  # footgun.  Use a safe picker that returns the single element when avail
  # is length-1, otherwise random-samples normally.  Without this, the
  # stratified picker can produce duplicate file indices, which propagates
  # all the way through to duplicate per-cell rows in the final CSV.
  safe_pick_one <- function(x) if (length(x) == 1L) x else sample(x, 1L)
  repeat {
    progressed <- FALSE
    for (g in grp) {
      if (length(pick) >= TEST_N) break
      avail <- setdiff(g, pick)
      if (length(avail)) { pick <- c(pick, safe_pick_one(avail)); progressed <- TRUE }
    }
    if (length(pick) >= TEST_N || !progressed) break
  }
  # [v4.7] Belt-and-braces dedup in case some future picker bug leaks
  # duplicates -- downstream code assumes one row per file.
  pick <- unique(pick)
  pairs <- usable[sort(pick), , drop = FALSE]
  message(sprintf("TEST_MODE on: %d of %d usable recordings (seed=%d).",
                  nrow(pairs), nrow(usable), TEST_SEED))
  print(table(DonorCond = pairs$DonorCond))
}

# [v4.18] SHARDING stage control.  No-op unless SHARDING_ENABLED.
#   process   : keep only this shard's 1/N slice of recordings; disable the
#               modeling/PART P loops (deferred to the aggregate stage).
#   aggregate : empty the recording table so NO per-file work runs; the merge
#               block before the modeling section rebuilds the master summary
#               from the shard CSVs, then modeling/PART P run on the full set.
if (isTRUE(SHARDING_ENABLED)) {
  if (identical(SHARD_STAGE, "process")) {
    if (SHARD_COUNT > 1L) {
      keep  <- ((seq_len(nrow(pairs)) - 1L) %% SHARD_COUNT) == (SHARD_INDEX - 1L)
      pairs <- pairs[keep, , drop = FALSE]
    }
    GROUPING_VARS <- character(0)   # skip modeling + PART P in per-file shards
    message(sprintf("[v4.18] SHARDING process stage: shard %d/%d -> %d recording(s); aggregation deferred.",
                    SHARD_INDEX, SHARD_COUNT, nrow(pairs)))
  } else if (identical(SHARD_STAGE, "aggregate")) {
    pairs <- pairs[0, , drop = FALSE]   # skip ALL per-file phases
    message("[v4.18] SHARDING aggregate stage: skipping per-file work; will merge shard CSVs then run modeling/PART P.")
  }
}

csv_files    <- pairs$csv
mat_files    <- pairs$post
mat_prefixes <- sub("_res_cfu\\.mat$", "", basename(mat_files))   # = <stem>_AQuA2
message("Using ", length(csv_files), " CSV / ", length(mat_files), " MAT for '", AnalysisName, "'.")

message("Found ", length(csv_files), " CSVs and ", length(mat_files),
        " MATs for analysis ‘", AnalysisName, "’.")

# [v4.5] One-time rhdf5 dereference self-test on the first POST file.
# If this fails the script aborts before processing thousands of files
# would silently produce empty per-cell records.
if (length(mat_files) > 0) {
  message("\n[v4.5] Running rhdf5 self-test on first readable POST file(s)…")
  if (!isTRUE(rhdf5_self_test(mat_files))) {
    stop("rhdf5 self-test failed — aborting. See message above. ",
         "Verify rhdf5 install (BiocManager::install(\"rhdf5\")) and that ",
         "the POST files are readable; re-run after fixing.")
  }
}

all_res <- list(); res_i <- 0
files_processed <- 0; files_skipped <- 0

for (csv_path in csv_files) {
  csv_name <- basename(csv_path)
  csv_base <- tools::file_path_sans_ext(csv_name)
  prefix   <- sub("_Ch[0-9]+$", "", csv_base)

  # [v4.11] Checkpoint skip: if this prefix is in the resume set, skip
  # immediately.  Recorded in the diagnostic accumulator as skipped_ckpt
  # so the JSON still has a row for every input file.
  if (.v411_is_processed(prefix)) {
    message("⏭️  [", SCRIPT_VERSION, "] Skipping ‘", prefix,
            "’ (already in checkpoint).")
    files_skipped <- files_skipped + 1L
    .v48_part_a_files[[length(.v48_part_a_files) + 1L]] <- list(
      prefix = prefix, status = "skipped_ckpt",
      cells_added = 0L, n_cells_mat = NA_integer_)
    next
  }

  message("\n▶ Processing CSV: ", csv_name)

  # [v4.11] Per-file tryCatch.  Any uncaught error inside the body is
  # caught here, recorded with status="error", and we proceed to the
  # next file.  next() inside the body still works for legitimate skip
  # paths (verified).
  tryCatch({
  
  mi <- match(prefix, mat_prefixes)
  if (is.na(mi)) { message("  ⚠️  No MAT for prefix ‘", prefix, "’ → skip."); files_skipped <- files_skipped + 1; next }
  mat_path <- mat_files[mi]; message("  ↔ Matched to MAT: ", basename(mat_path))
  
  df_raw <- tryCatch(read_csv(csv_path, col_names = FALSE),
                     error = function(e) { message("  ❌ CSV read error: ", e$message); NULL })
  if (is.null(df_raw)) { files_skipped <- files_skipped + 1; next }
  
  idx_row <- which(df_raw$X1 == "Index")
  if (length(idx_row) == 0) { message("  ⚠️  No ‘Index’ row found → skip."); files_skipped <- files_skipped + 1; next }
  event_ids <- as.integer(df_raw[idx_row, -1])
  var_names <- df_raw$X1[(idx_row+1):nrow(df_raw)]
  data_mat  <- as.matrix(df_raw[(idx_row+1):nrow(df_raw), -1])
  message("  ✅ CSV OK: ", length(event_ids), " events × ", length(var_names), " variables.")
  
  m <- tryCatch(read_mat_smart(mat_path), error = function(e) { message("  ❌ MAT read error: ", e$message); NULL })
  if (is.null(m)) { message("  ⚠️  MAT read failed → skip."); files_skipped <- files_skipped + 1; next }
  if (!("cfuInfo1" %in% names(m) || "cfuInfo" %in% names(m))) { message("  ⚠️  cfuInfo/cfuInfo1 missing → skip."); files_skipped <- files_skipped + 1; next }
  
  cfuList <- get_cfuinfo(m); dims <- dim(cfuList)
  if (is.null(dims) || length(dims) != 2) { message("  ⚠️  Unexpected cfuInfo dims → skip."); files_skipped <- files_skipped + 1; next }
  nCells <- dims[1]; cfuMat <- array(cfuList, dim = dims)
  # [v4.1] Guard: cfuInfo must have >=2 columns (field 2 = event indices).
  # Degenerate/empty recordings can produce a thin cell array; skip cleanly.
  if (is.null(ncol(cfuMat)) || ncol(cfuMat) < 2) {
    message("  ⚠️  cfuInfo has <2 columns (degenerate file) → skip.")
    files_skipped <- files_skipped + 1; next
  }
  message("  ✅ MAT OK: ", nCells, " cells found.")
  
  cells_added <- 0
  for (cell_idx in seq_len(nCells)) {
    raw_ev   <- cfuMat[cell_idx, 2][[1]]
    ev       <- as.integer(unlist(raw_ev))
    dff_cell <- if (ncol(cfuMat) >= 6) cfuMat[cell_idx, 6][[1]] else NULL
    dff_vec  <- to_numeric_vec(dff_cell)
    
    if (length(dff_vec) > 0) duration_s <- length(dff_vec) / frame_rate
    else if (length(ev) > 0 && all(is.finite(ev))) duration_s <- max(ev) / frame_rate
    else duration_s <- NA_real_
    
    n_events <- if (length(ev) > 0) length(ev) else 0
    freq_hz  <- if (!is.na(duration_s) && duration_s > 0) n_events / duration_s else NA_real_
    
    event_times_sec <- if (length(ev) > 0) ev * frame_interval else numeric(0)
    iei_stats <- calc_iei_stats(event_times_sec)
    
    if (length(ev) == 0) { message("    • Cell ", cell_idx, ": no events → skip"); next }
    cols <- event_ids %in% ev
    if (!any(cols)) { message("    • Cell ", cell_idx, ": no matching CSV cols → skip"); next }
    
    means <- rowMeans(data_mat[, cols, drop=FALSE], na.rm = TRUE)
    
    rec <- data.frame(
      File                     = prefix,
      CellID                   = cell_idx,
      NumberOfEvents           = n_events,
      DurationOfVideo_seconds  = duration_s,
      FrequencyHz              = freq_hz,
      MeanIEI_sec              = iei_stats$MeanIEI_sec,
      IEI_CV                   = iei_stats$IEI_CV,
      as.list(means),
      stringsAsFactors = FALSE
    )
    names(rec)[-(1:7)] <- make.names(var_names)
    
    res_i <- res_i + 1; all_res[[res_i]] <- rec; cells_added <- cells_added + 1
    message("    ✓ Added cell ", cell_idx, " (events=", n_events,
            ", duration=", ifelse(is.na(duration_s), "NA", signif(duration_s,3)),
            "s, freq=", ifelse(is.na(freq_hz), "NA", signif(freq_hz,3)), " Hz",
            ", meanIEI=", ifelse(is.na(iei_stats$MeanIEI_sec), "NA", signif(iei_stats$MeanIEI_sec,3)), "s",
            ", CV=", ifelse(is.na(iei_stats$IEI_CV), "NA", signif(iei_stats$IEI_CV,3)), ")")
  }
  files_processed <- files_processed + 1
  message("→ Completed ‘", prefix, "’: added ", cells_added, " cells.")
  # [v4.8] Push per-file summary into diagnostic accumulator.
  .v48_part_a_files[[length(.v48_part_a_files) + 1L]] <- list(
    prefix = prefix, status = "ok", cells_added = cells_added, n_cells_mat = nCells)
  # [v4.11] Record successful prefix in checkpoint file and maybe gc.
  .v411_record_processed(prefix)
  .v411_maybe_gc("Part A file")
  }, error = function(e) {
    # [v4.11] Uncaught error in file body -- log it, record it, and move
    # on.  Using <<- so the assignment reaches the global accumulator.
    msg <- conditionMessage(e)
    message("  ❌ [", SCRIPT_VERSION, "] Uncaught error processing '",
            prefix, "': ", msg)
    files_skipped <<- files_skipped + 1L
    .v48_part_a_files[[length(.v48_part_a_files) + 1L]] <<- list(
      prefix = prefix, status = "error", err = msg,
      cells_added = 0L, n_cells_mat = NA_integer_)
  })
}

message("\n[", AnalysisName, "] = SUMMARY (PRE+POST integration + Frequency + IEI) =")
message("Files processed: ", files_processed, " | Files skipped: ", files_skipped)
message("Total cells added: ", res_i)

if (res_i > 0) {
  final_df <- as.data.frame(data.table::rbindlist(all_res[1:res_i], fill = TRUE))  # [opt] fast rbind
  prefix_parts <- strsplit(final_df$File, "_")
  max_terms    <- max(lengths(prefix_parts))
  padded       <- lapply(prefix_parts, function(x){ length(x) <- max_terms; x })
  ids_mat      <- do.call(rbind, padded)
  colnames(ids_mat) <- paste0("ID", seq_len(max_terms))
  final_df2 <- cbind(as.data.frame(ids_mat, stringsAsFactors=FALSE), final_df)
  final_df2 <- cbind(parse_stems(sub("_AQuA2$", "", final_df2$File)), final_df2)  # [hCO] parsed metadata
  write_csv(final_df2, out_csv)
  message("✔️  Wrote per-cell summary: ", out_csv)
  if (isTRUE(PRISM_EXPORT)) write_prism_exports(out_csv, out_dir, final_df2)

  # ===================== [v4.27] ORGANOID-LEVEL AGGREGATION ==================
  # Views (V1/V2/V3) are different fields of the SAME organoid, so cell-level
  # rows pseudoreplicate for a WT-vs-HET comparison.  Here we collapse to the
  # organoid (SampleID, e.g. "WT4") by taking the MEAN of each numeric metric
  # across all that organoid's cells/views, then test WT vs HET on those
  # organoid means (true biological n = number of organoids, here 11).
  # Both levels are written: the cell-level summary above, and the two
  # organoid-level files below.
  tryCatch({
    if (all(c("SampleID","Genotype") %in% names(final_df2))) {
      num_cols <- names(final_df2)[vapply(final_df2, is.numeric, logical(1))]
      # drop pure-ID numeric columns that shouldn't be averaged
      num_cols <- setdiff(num_cols, c("Organoid","View","Video","NominalHz","EffectiveHz","AgeDay"))
      org_df <- final_df2 %>%
        dplyr::filter(!is.na(SampleID), !is.na(Genotype)) %>%
        dplyr::group_by(SampleID, Genotype, Organoid) %>%
        dplyr::summarize(
          n_cells = dplyr::n(),
          n_views = dplyr::n_distinct(View),
          dplyr::across(dplyr::all_of(num_cols), ~ mean(.x, na.rm = TRUE)),
          .groups = "drop"
        )
      org_csv <- file.path(out_dir, paste0(AnalysisName, "_per_organoid_summary.csv"))
      write_csv(org_df, org_csv)
      message("✔️  [v4.27] Wrote per-organoid summary (n=", nrow(org_df),
              " organoids): ", org_csv)

      # WT vs HET on organoid means: Wilcoxon rank-sum per metric (non-parametric,
      # appropriate for small n), plus group means/SD and Cohen's d.
      gA <- "WT"; gB <- "HET"
      stat_rows <- lapply(num_cols, function(m) {
        a <- org_df[[m]][org_df$Genotype == gA]
        b <- org_df[[m]][org_df$Genotype == gB]
        a <- a[is.finite(a)]; b <- b[is.finite(b)]
        if (length(a) < 2 || length(b) < 2) return(NULL)
        wt <- suppressWarnings(stats::wilcox.test(a, b, exact = FALSE))
        sp <- sqrt(((length(a)-1)*stats::var(a) + (length(b)-1)*stats::var(b)) /
                     (length(a)+length(b)-2))
        d  <- if (is.finite(sp) && sp > 0) (mean(a)-mean(b))/sp else NA_real_
        data.frame(
          Metric = m,
          n_WT = length(a), n_HET = length(b),
          mean_WT = mean(a), sd_WT = stats::sd(a),
          mean_HET = mean(b), sd_HET = stats::sd(b),
          Wilcoxon_p = unname(wt$p.value),
          Cohens_d = d,
          stringsAsFactors = FALSE
        )
      })
      stat_df <- dplyr::bind_rows(stat_rows)
      if (nrow(stat_df) > 0) {
        stat_df$p_adj_BH <- stats::p.adjust(stat_df$Wilcoxon_p, method = "BH")
        stat_df <- stat_df[order(stat_df$Wilcoxon_p), ]
        org_stat_csv <- file.path(out_dir, paste0(AnalysisName, "_organoid_WT_vs_HET_stats.csv"))
        write_csv(stat_df, org_stat_csv)
        message("✔️  [v4.27] Wrote organoid-level WT-vs-HET stats: ", org_stat_csv)
        message("    (Wilcoxon on organoid means; BH-adjusted; n_WT=",
                sum(org_df$Genotype==gA), " n_HET=", sum(org_df$Genotype==gB), " organoids)")
      } else {
        message("ℹ️  [v4.27] organoid-level stats skipped: too few organoids per group.")
      }
    } else {
      message("ℹ️  [v4.27] organoid aggregation skipped: SampleID/Genotype columns absent.")
    }
  }, error = function(e)
    message("⚠️  [v4.27] organoid-level aggregation failed: ", conditionMessage(e)))
  # ===================== end organoid-level aggregation ======================
} else {
  message("⚠️  No data collected; no output file created.")
}

# ============================ [hCO v2] PART P + modeling driver =============
# §19 -- PART P: feature distribution + non-parametric statistics.
# For each numeric feature in the per-cell summary and each grouping
# column in GROUPING_VARS, produces three distribution plots (violin,
# box, dot) annotated with Kruskal-Wallis omnibus p-value and Dunn
# pairwise comparisons (BH-adjusted).  Stat-only summary table goes to
# PART_P_<grouping>/PART_P_<grouping>_summary.csv.  Plots into the same
# directory.
#
# Runs once per GROUPING_VARS entry (default: "Condition" and
# "DonorCond").  Driven by run_distribution_plots_by_group() defined
# immediately below; the modeling pass §20 calls it after random-forest
# importance is computed.
# ============================ [hCO v2] PART P + modeling driver =============
# PART P, parameterized by grouping column; runs once per GROUPING_VARS entry.
run_distribution_plots_by_group <- function(df0, group_col,
                                             out_dir = get("out_dir", envir = .GlobalEnv),
                                             png_dpi = if (exists("png_dpi", envir = .GlobalEnv))
                                                         get("png_dpi", envir = .GlobalEnv) else 300) {
  suppressPackageStartupMessages({
    library(dplyr); library(readr); library(ggplot2); library(stringr)
    quietly_load <- function(pkg) if (!requireNamespace(pkg, quietly = TRUE)) FALSE else TRUE
    has_ggpubr   <- isTRUE(quietly_load("ggpubr"))
    has_FSA      <- isTRUE(quietly_load("FSA"))
    has_ggsignif <- isTRUE(quietly_load("ggsignif"))
    if (has_ggpubr)   library(ggpubr)
    if (has_ggsignif) library(ggsignif)
  })

  if (!is.data.frame(df0) || nrow(df0) == 0) {
    warning("run_distribution_plots_by_group: empty df0; skipping ", group_col); return(invisible(FALSE))
  }
  if (!(group_col %in% names(df0))) {
    warning("Grouping column '", group_col, "' not found; skipping."); return(invisible(FALSE))
  }

  plots_dir  <- file.path(out_dir, paste0("Plots_", group_col))
  violin_dir <- file.path(plots_dir, "Violin")
  box_dir    <- file.path(plots_dir, "Box")
  dot_dir    <- file.path(plots_dir, "Dot")
  for (base in c(violin_dir, box_dir, dot_dir))
    for (sd in c("Signif","Insignif")) {
      d <- file.path(base, sd)
      if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }

  coerce_to_numeric <- function(x) {
    if (is.numeric(x)) return(x)
    v <- as.character(x); v <- trimws(v)
    v[v %in% c("", "NA", "NaN", "Inf", "-Inf", "null", "NULL")] <- NA
    suppressWarnings(as.numeric(v))
  }
  safe_name <- function(x) { x <- gsub("[^A-Za-z0-9._-]+", "_", x); gsub("_+", "_", x) }
  kw_pvalue <- function(x, g) {
    ok <- is.finite(x) & !is.na(g); x <- x[ok]; g <- droplevels(g[ok])
    if (length(levels(g)) < 2) return(NA_real_)
    tab <- table(g); if (sum(tab > 0) < 2) return(NA_real_)
    tryCatch(stats::kruskal.test(x ~ g)$p.value, error = function(e) NA_real_)
  }
  pairwise_dunn <- function(df) {
    if (!has_FSA) return(data.frame())
    if (nlevels(df$ID1) < 2L) return(data.frame())
    kt <- tryCatch(FSA::dunnTest(value ~ ID1, data = df, method = "holm"), error = function(e) NULL)
    if (is.null(kt) || is.null(kt$res)) return(data.frame())
    out <- kt$res; comps <- strsplit(out$Comparison, "[-]")
    out$group1 <- vapply(comps, `[`, "", 1); out$group2 <- vapply(comps, `[`, "", 2); out
  }
  build_sig_brackets <- function(df, pw, y_pad_frac = 0.07) {
    empty <- data.frame(group1=character(), group2=character(),
                        y.position=double(), label=character(), stringsAsFactors = FALSE)
    if (!is.data.frame(pw) || !nrow(pw)) return(empty)
    max_y_by_group <- tapply(df$value, df$ID1, max, na.rm = TRUE)
    rng <- range(df$value, na.rm = TRUE); span <- diff(rng); if (!is.finite(span) || span <= 0) span <- 1
    pw <- pw[order(pw$P.adj, pw$P.unadj), , drop = FALSE]
    used_pairs <- list(); rows <- vector("list", nrow(pw))
    for (i in seq_len(nrow(pw))) {
      g1 <- pw$group1[i]; g2 <- pw$group2[i]
      if (!(g1 %in% names(max_y_by_group)) || !(g2 %in% names(max_y_by_group))) next
      base_y <- max(max_y_by_group[g1], max_y_by_group[g2])
      key <- paste(sort(c(g1, g2)), collapse = "|")
      bump_idx <- if (key %in% names(used_pairs)) used_pairs[[key]] + 1L else 1L
      used_pairs[[key]] <- bump_idx
      y <- base_y + bump_idx * (y_pad_frac * span); p <- pw$P.adj[i]
      stars <- if (is.na(p)) "ns" else if (p < 0.001) "***" else if (p < 0.01) "**" else if (p < 0.05) "*" else "ns"
      rows[[i]] <- data.frame(group1=g1, group2=g2, y.position=y,
                              label=paste0(stars, " (p=", formatC(p, format="e", digits=2), ")"),
                              stringsAsFactors = FALSE)
    }
    out <- do.call(rbind, Filter(Negate(is.null), rows)); if (is.null(out)) out <- empty; out
  }
  plot_theme <- function() {
    theme_minimal(base_family = "Arial") +
      theme(plot.title = element_text(hjust = 0, face = "bold"),
            axis.title.x = element_text(margin = ggplot2::margin(t = 6, unit = "pt")),
            axis.title.y = element_text(margin = ggplot2::margin(r = 6, unit = "pt")),
            plot.margin  = ggplot2::margin(8, 8, 16, 8, unit = "pt"))
  }

  df_plot <- df0 %>% mutate(ID1 = as.factor(.data[[group_col]]))
  id_cols <- unique(c(grep("^ID[0-9]+$", names(df_plot), value = TRUE),
                      "File", "CellID", META_COLS))
  cand    <- setdiff(names(df_plot), id_cols)

  numeric_ok <- character(0)
  for (nm in cand) {
    v <- coerce_to_numeric(df_plot[[nm]])
    if (any(is.finite(v), na.rm = TRUE)) { df_plot[[nm]] <- v; numeric_ok <- c(numeric_ok, nm) }
  }
  if (!length(numeric_ok)) { warning("No numeric features for ", group_col); return(invisible(FALSE)) }
  message("PART P [", group_col, "]: ", length(numeric_ok), " features, groups: ",
          paste(levels(df_plot$ID1), collapse = "/"))

  plot_one <- function(feature) {
    d <- df_plot %>% select(ID1, value = dplyr::all_of(feature)) %>% filter(is.finite(value), !is.na(ID1))
    if (nrow(d) == 0) return(invisible(FALSE))
    p_kw <- kw_pvalue(d$value, d$ID1); pw <- pairwise_dunn(d); br <- build_sig_brackets(d, pw)
    is_signif <- FALSE
    if (is.data.frame(pw) && nrow(pw) > 0) is_signif <- any(is.finite(pw$P.adj) & pw$P.adj < 0.05, na.rm = TRUE)
    else if (is.finite(p_kw)) is_signif <- (p_kw < 0.05)
    subfolder <- if (is_signif) "Signif" else "Insignif"
    slab  <- if (is.finite(p_kw)) paste0("Kruskal-Wallis p = ", formatC(p_kw, format="e", digits=2))
             else "Kruskal-Wallis p = NA (insufficient groups)"
    fname <- safe_name(feature)

    comparisons <- list(); ann_labels <- character(0)
    if (is.data.frame(pw) && nrow(pw) > 0) {
      pw_ok <- pw[is.finite(pw$P.adj), , drop = FALSE]
      if (nrow(pw_ok) > 0) {
        comparisons <- Map(function(a, b) c(as.character(a), as.character(b)), pw_ok$group1, pw_ok$group2)
        ann_labels  <- vapply(pw_ok$P.adj, function(p)
          if (is.na(p)) "ns" else if (p < 0.001) "***" else if (p < 0.01) "**" else if (p < 0.05) "*" else "ns",
          character(1))
      }
    }

    p_violin <- ggplot(d, aes(x = ID1, y = value, fill = ID1)) +
      geom_violin(trim = FALSE, alpha = 0.6, color = "gray30") +
      geom_boxplot(width = 0.12, outlier.shape = NA, color = "gray20", alpha = 0.7) +
      geom_point(position = position_jitter(width = 0.15, height = 0), alpha = 0.35, size = 1.1, color = "black") +
      labs(title = paste0(feature, " by ", group_col), x = group_col, y = feature, subtitle = slab) +
      guides(fill = "none") + plot_theme()
    p_box <- ggplot(d, aes(x = ID1, y = value, fill = ID1)) +
      geom_boxplot(width = 0.5, outlier.alpha = 0.5) +
      geom_point(position = position_jitter(width = 0.15, height = 0), alpha = 0.35, size = 1.1, color = "black") +
      labs(title = paste0(feature, " by ", group_col), x = group_col, y = feature, subtitle = slab) +
      guides(fill = "none") + plot_theme()
    p_dot <- ggplot(d, aes(x = ID1, y = value, color = ID1)) +
      geom_point(position = position_jitter(width = 0.15, height = 0), alpha = 0.6, size = 1.3) +
      stat_summary(fun = median, geom = "crossbar", width = 0.4, color = "black", fatten = 2, show.legend = FALSE, alpha = 0.9) +
      labs(title = paste0(feature, " by ", group_col), x = group_col, y = feature, subtitle = slab) +
      guides(color = "none") + plot_theme()

    br_ok <- is.data.frame(br) && nrow(br) > 0 && all(c("group1","group2","y.position","label") %in% names(br))
    if (br_ok && has_ggpubr) {
      for (nm in c("p_violin","p_box","p_dot")) assign(nm, get(nm) + ggpubr::stat_pvalue_manual(
        data = br, label = "label", xmin = "group1", xmax = "group2",
        y.position = "y.position", tip.length = 0.01, size = 3))
    } else if (has_ggsignif && length(comparisons) > 0) {
      pad <- 0.07 * diff(range(d$value, na.rm = TRUE)); if (!is.finite(pad) || pad <= 0) pad <- 0
      rng <- range(d$value, na.rm = TRUE)
      gs <- function(p) p + ggsignif::geom_signif(comparisons = comparisons, annotations = ann_labels,
              map_signif_level = FALSE, tip_length = 0.01, textsize = 3)
      p_violin <- gs(p_violin); p_box <- gs(p_box); p_dot <- gs(p_dot)
      if (pad > 0) {                                   # [hCO v2 FIX] rng[15] -> rng[2]
        p_violin <- p_violin + coord_cartesian(ylim = c(rng[1], rng[2] + 3 * pad))
        p_box    <- p_box    + coord_cartesian(ylim = c(rng[1], rng[2] + 3 * pad))
        p_dot    <- p_dot    + coord_cartesian(ylim = c(rng[1], rng[2] + 3 * pad))
      }
    } else if (br_ok) {
      lev <- levels(d$ID1); to_x <- function(g) which(lev == g)
      y_bump <- 0.01 * (max(d$value, na.rm = TRUE) - min(d$value, na.rm = TRUE))
      add_brackets <- function(p) {
        for (i in seq_len(nrow(br))) {
          x1 <- to_x(br$group1[i]); x2 <- to_x(br$group2[i]); y <- br$y.position[i]
          if (!length(x1) || !length(x2) || !is.finite(y)) next
          y2 <- y + y_bump
          p <- p +
            annotate("segment", x = x1, xend = x1, y = y,  yend = y2, linewidth = 0.3) +
            annotate("segment", x = x2, xend = x2, y = y,  yend = y2, linewidth = 0.3) +
            annotate("segment", x = x1, xend = x2, y = y2, yend = y2, linewidth = 0.3) +
            annotate("text", x = (x1 + x2)/2, y = y2, label = br$label[i], vjust = -0.2, size = 3)
        }
        p
      }
      p_violin <- add_brackets(p_violin); p_box <- add_brackets(p_box); p_dot <- add_brackets(p_dot)
    }

    ggsave(file.path(violin_dir, subfolder, paste0(fname, "_by_", group_col, "_violin.png")),
           plot = p_violin, width = 7.4, height = 6.2, dpi = png_dpi)
    ggsave(file.path(box_dir,    subfolder, paste0(fname, "_by_", group_col, "_box.png")),
           plot = p_box,    width = 7.4, height = 6.2, dpi = png_dpi)
    ggsave(file.path(dot_dir,    subfolder, paste0(fname, "_by_", group_col, "_dot.png")),
           plot = p_dot,    width = 7.4, height = 6.2, dpi = png_dpi)
    invisible(TRUE)
  }

  invisible(lapply(numeric_ok, plot_one))
  message("PART P [", group_col, "] saved under: ", plots_dir)
  if (!has_FSA)    message("  (FSA absent -> KW-only routing)")
  if (!has_ggpubr) message("  (ggpubr absent -> ggsignif/manual brackets)")
  invisible(TRUE)
}

# [v4.18] aggregate stage: merge all shard per-cell (and per-event) CSVs into
# the master summaries BEFORE modeling reads out_csv.  Runs only in aggregate.
if (isTRUE(SHARDING_ENABLED) && identical(SHARD_STAGE, "aggregate")) {
  pc_pat    <- paste0("^", AnalysisName, "_per_cell_summary_shard[0-9]+\\.csv$")
  pc_shards <- list.files(out_dir, pattern = pc_pat, full.names = TRUE)
  if (length(pc_shards) == 0L)
    stop("[v4.18] aggregate: no per-cell shard CSVs (", pc_pat, ") found in ", out_dir,
         " -- did the process-stage shards run and complete?")
  pc_all <- data.table::rbindlist(lapply(pc_shards, function(f)
              data.table::fread(f, colClasses = "character")), fill = TRUE)
  data.table::fwrite(pc_all, out_csv)
  message(sprintf("[v4.18] merged %d shard per-cell CSV(s) -> %s (%d rows)",
                  length(pc_shards), out_csv, nrow(pc_all)))
  pe_shards <- list.files(out_dir, pattern = "^per_cell_per_event_summary_shard[0-9]+\\.csv$",
                          full.names = TRUE)
  if (length(pe_shards) > 0L) {
    pe_all <- data.table::rbindlist(lapply(pe_shards, function(f)
                data.table::fread(f, colClasses = "character")), fill = TRUE)
    data.table::fwrite(pe_all, file.path(out_dir, "per_cell_per_event_summary.csv"))
    message(sprintf("[v4.18] merged %d shard per-event CSV(s) (%d rows)",
                    length(pe_shards), nrow(pe_all)))
    rm(pe_all)
  }
  rm(pc_all)
}

if (!exists("df0") || !is.data.frame(df0)) {
  if (file.exists(out_csv)) df0 <- readr::read_csv(out_csv, show_col_types = FALSE)
}

# [v4.23] FAST/skip: bypass both modeling and PART P by emptying GROUPING_VARS.
if (isTRUE(SKIP_MODELING_AND_PARTP)) {
  message("[v4.23] FAST/skip: bypassing modeling + PART P (GROUPING_VARS emptied).")
  GROUPING_VARS <- character(0)
}

for (gcol in GROUPING_VARS) {
  message("\n================= PART P grouping: ", gcol, " =================")
  run_distribution_plots_by_group(df0, gcol)
}



# ============================ MODELING PASS: FEATURE IMPORTANCE ============================
# [v4.14] SAMPLING-UNIT CAVEAT.  Filenames encode Organoid (ORG#) and View
# (V#); V1/V5/V10 are different fields of view of the SAME organoid, not
# independent samples.  parse_stem() already extracts both Organoid and the
# view number.  This pass (and PART P below) currently treats each CFU cell
# as an independent observation grouped by Condition / DonorCond, which
# pools across views AND organoids -- i.e. it pseudoreplicates: cells from
# different views of one organoid are correlated.  This does not affect the
# per-cell summaries or plots, but it inflates effective N for the
# Kruskal-Wallis / Dunn / RF-importance steps.  If statistical inference at
# the organoid level is the goal, the proper unit is Donor x Condition x
# Organoid (aggregate cells to an organoid-level summary, or use a mixed
# model with Organoid as a random effect).  Left as-is pending a decision;
# flagged here so it is not overlooked.
# ============================ MODELING PASS: FEATURE IMPORTANCE ============================
# §20 -- Random forest feature importance vs each target in GROUPING_VARS.
# Loads <AnalysisName>_per_cell_summary.csv, filters to user-selected
# features (requested_features list below), drops underrepresented
# classes (default min_class_count = 5), trains an RF, and emits:
#   Modeling_<target>/<target>_feature_importance.csv  (numeric scores)
#   Modeling_<target>/<target>_feature_importance.png  (top-N bar)
#   Modeling_<target>/<target>_confusion_matrix.png    (classification)
#   Modeling_<target>/<target>_oob_error.txt           (holdout summary)
# Class counts (raw and filtered) are captured in the diagnostic JSON's
# `modeling.<target>` block so you can tell from the JSON alone which
# classes were dropped and why.
#
# After the RF importance step, this section also invokes
# run_distribution_plots_by_group() to produce PART P's distribution
# plots and KW/Dunn statistics for the same grouping.
# ============================ MODELING PASS: FEATURE IMPORTANCE ============================
# Configure target and output directory for modeling artifacts
for (GROUPING_VAR in GROUPING_VARS) {   # [hCO] run modeling once per grouping scheme
modeling_target_column <- GROUPING_VAR   # set to any target column (numeric for regression, factor-like for classification)
modeling_out_dir <- file.path(out_dir, paste0("Modeling_", GROUPING_VAR))
if (!dir.exists(modeling_out_dir)) dir.create(modeling_out_dir, recursive = TRUE, showWarnings = FALSE)

message("\n= Modeling pass: feature importance vs target ‘", modeling_target_column, "’ =")

# Load the per-cell summary written earlier
summary_csv_path <- out_csv
if (!file.exists(summary_csv_path)) {
  warning("Per-cell summary CSV not found: ", summary_csv_path, ". Skipping modeling.")
} else {
  df0 <- tryCatch(readr::read_csv(summary_csv_path, show_col_types = FALSE),
                  error = function(e) { warning("Failed to read summary CSV: ", e$message); NULL })
  
  if (is.null(df0) || nrow(df0) == 0) {
    warning("Empty per-cell summary. Skipping modeling.")
  } else {
    
    # ---------------- User-selected features (exact list provided) ----------------
    requested_features <- c(
      "NumberOfEvents",
      "DurationOfVideo_seconds",
      "FrequencyHz",
      "MeanIEI_sec",
      "IEI_CV",
      "Starting.Frame",
      "Basic...Area",
      "Basic...Perimeter..only.for.2D.video.",
      "Basic...Circularity",
      "Curve...P.Value.on.max.Dff...log10.",
      "Curve...Max.Df",
      "Curve...Max.Dff",
      "Curve...Duration.of.visualized.event.overlay",
      "Curve...Duration.50..to.50..based.on.averge.dF.F",
      "Curve...Duration.10..to.10..based.on.averge.dF.F",
      "Curve...Rising.duration.10..to.90..based.on.averge.dF.F",
      "Curve...Decaying.duration.90..to.10..based.on.averge.dF.F",
      "Curve...dat.AUC",
      "Curve...df.AUC",
      "Curve...dff.AUC",
      "Curve...Decay.tau",
      "Propagation...onset...overall",
      "Propagation...onset...one.direction...Anterior",
      "Propagation...onset...one.direction...Posterior",
      "Propagation...onset...one.direction...Left",
      "Propagation...onset...one.direction...Right",
      "Propagation...onset...one.direction...ratio...Anterior",
      "Propagation...onset...one.direction...ratio...Posterior",
      "Propagation...onset...one.direction...ratio...Left",
      "Propagation...onset...one.direction...ratio...Right",
      "Propagation...offset...overall",
      "Propagation...offset...one.direction...Anterior",
      "Propagation...offset...one.direction...Posterior",
      "Propagation...offset...one.direction...Left",
      "Propagation...offset...one.direction...Right",
      "Propagation...offset...one.direction...ratio...Anterior",
      "Propagation...offset...one.direction...ratio...Posterior",
      "Propagation...offset...one.direction...ratio...Left",
      "Propagation...offset...one.direction...ratio...Right",
      "Network...number.of.events.in.the.same.location",
      "Network...number.of.events.in.the.same.location.with.similar.size.only",
      "Network...maximum.number.of.events.appearing.at.the.same.time"
    )
    
    # ---------------- Helpers ----------------
    coerce_to_numeric <- function(x) {
      if (is.numeric(x)) return(x)
      v <- as.character(x)
      v <- trimws(v)
      v[v %in% c("", "NA", "NaN", "Inf", "-Inf", "null", "NULL")] <- NA
      suppressWarnings(as.numeric(v))
    }
    
    drop_constant_or_all_na <- function(X) {
      keep_cols <- vapply(X, function(col) {
        any(is.finite(col)) && {
          s <- suppressWarnings(sd(col, na.rm = TRUE))
          is.finite(s) && s > 0
        }
      }, logical(1))
      if (!any(keep_cols)) return(X[, 0, drop = FALSE])
      X[, keep_cols, drop = FALSE]
    }
    
    # ---------------- Build feature matrix from requested features that exist ----------------
    present <- intersect(requested_features, names(df0))
    if (length(present) == 0) {
      warning("None of the requested features are present in the per-cell summary. Skipping modeling.")
    } else {
      X_sel <- df0[, present, drop = FALSE]
      for (nm in names(X_sel)) X_sel[[nm]] <- coerce_to_numeric(X_sel[[nm]])
      X_sel <- drop_constant_or_all_na(X_sel)
      
      if (ncol(X_sel) == 0) {
        warning("After numeric coercion and filtering, no usable requested features remain. Skipping modeling.")
      } else {
        # Optional: simple median imputation for remaining NA in features
        for (nm in names(X_sel)) {
          med <- suppressWarnings(median(X_sel[[nm]], na.rm = TRUE))
          if (!is.finite(med)) med <- 0
          X_sel[[nm]][!is.finite(X_sel[[nm]])] <- med
        }
        
        # ---------------- Prepare target ----------------
        if (!(modeling_target_column %in% names(df0))) {
          warning("Target column not found in per-cell summary: ", modeling_target_column, ". Skipping modeling.")
        } else {
          y_raw <- df0[[modeling_target_column]]
          
          # Decide regression vs classification based on target coercion
          y_num <- suppressWarnings(coerce_to_numeric(y_raw))
          y_num_all_na <- all(is.na(y_num))
          if (!y_num_all_na) {
            task_type <- "regression"
            y <- y_num
            row_mask <- is.finite(y)
          } else {
            task_type <- "classification"
            y <- as.factor(y_raw)
            row_mask <- !is.na(y)
            y <- droplevels(y[row_mask])
          }
          
          # Align rows for X and y
          X_imp <- X_sel[row_mask, , drop = FALSE]
          
          # Final sanity checks
          n <- nrow(X_imp); p <- ncol(X_imp)
          if (n <= 0 || p <= 0) {
            warning("Insufficient data after filtering (n=", n, ", p=", p, "). Skipping modeling.")
          } else {
            if (task_type == "classification") {
              cls_counts <- table(y)
              message("  Target class counts (raw):")
              print(cls_counts)
              # [v4.8] Capture raw class counts for the JSON summary.
              .v48_modeling[[modeling_target_column]] <- list(
                target = modeling_target_column,
                task = "classification",
                raw_class_counts = as.list(cls_counts))

              # Optional minimal class size filter to avoid degenerate folds
              min_class_count <- 5
              ok_levels <- names(cls_counts)[cls_counts >= min_class_count]
              if (length(ok_levels) > 0 && any(!(y %in% ok_levels))) {
                keep <- y %in% ok_levels
                y <- droplevels(y[keep])
                X_imp <- X_imp[keep, , drop = FALSE]
                message("  After filtering by min class count (", min_class_count, "):")
                print(table(y))
                # [v4.8] Capture post-filter counts too.
                .v48_modeling[[modeling_target_column]]$filtered_class_counts <-
                  as.list(table(y))
              }

              if (nrow(X_imp) == 0 || length(levels(y)) <= 1) {
                warning("⚠️ Insufficient label diversity or rows for classification. Skipping modeling.")
              }
            }
            
            viable <- if (task_type == "regression") {
              (nrow(X_imp) >= 10) && any(is.finite(y))
            } else {
              (nrow(X_imp) >= 10) && (length(levels(y)) >= 2)
            }
            
            if (!viable) {
              warning("⚠️ Insufficient data for modeling after filtering (features=", p, ", n=", nrow(X_imp), "). Skipping.")
            } else {
              # ---------------- Compute multi-method feature importance ----------------
              suppressPackageStartupMessages({
                library(randomForest)
                library(FSelectorRcpp)
                library(glmnet)
                library(ggplot2)
                library(dplyr)
                library(readr)
              })
              
              X_mat <- as.matrix(X_imp)
              importance_long <- list()
              
              # 1) Random Forest + permutation-like importance
              set.seed(123)
              if (task_type == "regression") {
                rf <- randomForest(x = X_mat, y = as.numeric(y), importance = TRUE, ntree = 500)
                if ("%IncMSE" %in% colnames(rf$importance)) {
                  vi <- rf$importance[, "%IncMSE"]
                } else {
                  vi <- rf$importance[, "IncNodePurity"]
                }
              } else {
                rf <- randomForest(x = X_mat, y = y, importance = TRUE, ntree = 500)
                if ("MeanDecreaseAccuracy" %in% colnames(rf$importance)) {
                  vi <- rf$importance[, "MeanDecreaseAccuracy"]
                } else {
                  vi <- rf$importance[, "MeanDecreaseGini"]
                }
              }
              importance_long[["RF_permutation"]] <- data.frame(
                feature = rownames(rf$importance),
                importance = as.numeric(vi),
                method = "RF_permutation",
                stringsAsFactors = FALSE
              )
              
              # 2) Mutual Information
              if (task_type == "classification") {
                dat_mi <- data.frame(as.data.frame(X_imp), .TARGET. = y)
                ig <- tryCatch(information_gain(.TARGET. ~ ., data = dat_mi), error = function(e) NULL)
                if (!is.null(ig) && nrow(ig) > 0) {
                  importance_long[["MI_classification"]] <- data.frame(
                    feature = ig$attributes,
                    importance = ig$importance,
                    method = "MI_classification",
                    stringsAsFactors = FALSE
                  )
                }
              } else {
                y_bins <- cut(y, breaks = quantile(y, probs = seq(0,1,0.25), na.rm = TRUE),
                              include.lowest = TRUE, labels = FALSE)
                dat_mi <- data.frame(as.data.frame(X_imp), .TARGET. = factor(y_bins))
                ig <- tryCatch(information_gain(.TARGET. ~ ., data = dat_mi), error = function(e) NULL)
                if (!is.null(ig) && nrow(ig) > 0) {
                  importance_long[["MI_quartiledY"]] <- data.frame(
                    feature = ig$attributes,
                    importance = ig$importance,
                    method = "MI_quartiledY",
                    stringsAsFactors = FALSE
                  )
                }
              }
              
              # 3) Univariate statistics
              if (task_type == "regression") {
                cors <- suppressWarnings(apply(X_mat, 2, function(col) {
                  if (all(!is.finite(col))) return(NA_real_)
                  suppressWarnings(abs(stats::cor(col, y, use = "pairwise.complete.obs")))
                }))
                cors <- cors[is.finite(cors)]
                if (length(cors)) {
                  importance_long[["Univariate_absPearson"]] <- data.frame(
                    feature = names(cors),
                    importance = as.numeric(cors),
                    method = "Univariate_absPearson",
                    stringsAsFactors = FALSE
                  )
                }
              } else {
                eta2 <- sapply(colnames(X_mat), function(nm) {
                  xv <- X_mat[, nm]
                  if (!any(is.finite(xv))) return(NA_real_)
                  suppressWarnings({
                    fit <- tryCatch(aov(xv ~ y), error = function(e) NULL)
                    if (is.null(fit)) return(NA_real_)
                    ss <- tryCatch(summary(fit)[[1]][["Sum Sq"]], error = function(e) NULL)
                    if (is.null(ss) || length(ss) < 2) return(NA_real_)
                    ss_between <- ss[10]; ss_total <- sum(ss, na.rm = TRUE)
                    if (!is.finite(ss_between) || !is.finite(ss_total) || ss_total <= 0) return(NA_real_)
                    as.numeric(ss_between / ss_total)
                  })
                })
                eta2 <- eta2[is.finite(eta2)]
                if (length(eta2)) {
                  importance_long[["Univariate_eta2_ANOVA"]] <- data.frame(
                    feature = names(eta2),
                    importance = as.numeric(eta2),
                    method = "Univariate_eta2_ANOVA",
                    stringsAsFactors = FALSE
                  )
                }
              }
              
              # 4) Elastic Net (regression only)
              if (task_type == "regression") {
                set.seed(123)
                cvfit <- tryCatch(glmnet::cv.glmnet(X_mat, y, alpha = 0.5, nfolds = 5, standardize = TRUE),
                                  error = function(e) NULL)
                if (!is.null(cvfit)) {
                  best_lambda <- cvfit$lambda.min
                  fit <- glmnet::glmnet(X_mat, y, alpha = 0.5, lambda = best_lambda, standardize = TRUE)
                  b <- as.numeric(coef(fit))
                  nm <- rownames(coef(fit))
                  if (length(b) == length(nm)) {
                    if (nm[1] == "(Intercept)") { b <- b[-1]; nm <- nm[-1] }
                    importance_long[["ElasticNet_absCoef"]] <- data.frame(
                      feature = nm,
                      importance = abs(b),
                      method = "ElasticNet_absCoef",
                      stringsAsFactors = FALSE
                    )
                  }
                }
              }
              
              # ---------------- Consolidate and rank ----------------
              if (length(importance_long) == 0) {
                warning("No importance scores could be computed. Skipping exports.")
              } else {
                imp_long <- dplyr::bind_rows(importance_long)
                
                # Write long CSV
                long_path <- file.path(modeling_out_dir, paste0("feature_importance_", modeling_target_column, "_long.csv"))
                readr::write_csv(imp_long, long_path)
                
                # Rank within each method (higher importance -> better rank 1)
                imp_long <- imp_long %>%
                  dplyr::group_by(method) %>%
                  dplyr::mutate(rank = dplyr::min_rank(dplyr::desc(importance))) %>%
                  dplyr::ungroup()
                
                # Aggregate across methods
                ranked <- imp_long %>%
                  dplyr::group_by(feature) %>%
                  dplyr::summarize(
                    methods_covered = dplyr::n_distinct(method),
                    avg_rank = mean(rank, na.rm = TRUE),
                    best_method_idx = which.min(rank),
                    .groups = "drop"
                  )
                
                ranked <- ranked %>%
                  dplyr::rowwise() %>%
                  dplyr::mutate(
                    best_method = imp_long$method[imp_long$feature == feature][best_method_idx],
                    best_score  = imp_long$importance[imp_long$feature == feature][best_method_idx]
                  ) %>%
                  dplyr::ungroup() %>%
                  dplyr::arrange(avg_rank, dplyr::desc(methods_covered))
                
                ranked_path <- file.path(modeling_out_dir, paste0("feature_importance_", modeling_target_column, "_ranked.csv"))
                readr::write_csv(ranked, ranked_path)
                
                # ---------------- Quick plots: top-N bar charts ----------------
                topN <- 25L
                top_ranked <- ranked %>% dplyr::slice_head(n = topN)
                
                p_avg <- ggplot2::ggplot(top_ranked, ggplot2::aes(x = reorder(feature, -avg_rank), y = -avg_rank)) +
                  ggplot2::geom_col(fill = "#2C7FB8") +
                  ggplot2::coord_flip() +
                  ggplot2::labs(title = paste0("Top features by average rank (target=", modeling_target_column, ")"),
                                x = "Feature", y = "-avg_rank (higher = better)") +
                  ggplot2::theme_minimal(base_family = "Arial")
                
                ggplot2::ggsave(filename = file.path(modeling_out_dir, paste0("feature_importance_", modeling_target_column, "_avgRank_top.png")),
                                plot = p_avg, width = 8, height = 10, dpi = 300)
                
                imp_top <- imp_long %>% dplyr::filter(feature %in% top_ranked$feature)
                p_by_method <- ggplot2::ggplot(imp_top, ggplot2::aes(x = feature, y = importance, fill = method)) +
                  ggplot2::geom_col(position = "dodge") +
                  ggplot2::coord_flip() +
                  ggplot2::labs(title = paste0("Top features by method (target=", modeling_target_column, ")"),
                                x = "Feature", y = "Importance") +
                  ggplot2::theme_minimal(base_family = "Arial")
                
                ggplot2::ggsave(filename = file.path(modeling_out_dir, paste0("feature_importance_", modeling_target_column, "_byMethod_top.png")),
                                plot = p_by_method, width = 10, height = 10, dpi = 300)
                
                message("✔️ Modeling outputs saved in: ", modeling_out_dir)
                message("   - ", long_path)
                message("   - ", ranked_path)
              } # end if importance
            } # end viable
          } # end target exists
        } # end usable features
      } # end any requested present
    } # end nonempty df0
  } # end summary exists
} # end modeling pass
} # [hCO] end grouping pass -- modeling
# ==========================================================================================



# --------------------------------------- PART A2: PER-CELL PER-EVENT SUMMARY (NO AVERAGING) ---------------------------------------
# §21 -- Companion to Part A but does not average events within a cell.
# For each input file: extracts the same per-event activity as Part A,
# but emits ONE ROW PER EVENT rather than one row per cell.  Adds
# EventID and t_event_sec columns; per-CSV variables become the per-event
# values (not means).  Output is much larger than Part A's per-cell CSV
# (rows = sum of NumberOfEvents across all cells) but preserves all the
# raw measurement detail for downstream PART P feature-distribution and
# modeling work.
#
# Per-file split goes to PerCellPerEvent/<prefix>_per_cell_per_event.csv.
# All files combined into per_cell_per_event_summary.csv at root.
#
# Production-scale behaviour [v4.11]:
#   - Per-file tryCatch (same as Part A).  No checkpoint here because
#     output is one consolidated CSV at the end; partial rows from a
#     previous attempt would be invisible to a resume.
#   - gc() fires every GC_EVERY_N_FILES files.
# --------------------------------------- PART A2: PER-CELL PER-EVENT SUMMARY (NO AVERAGING) ---------------------------------------
message("\n= Building per-cell PER-EVENT summary (no averaging metrics) =")

per_event_all_rows <- list()
per_event_i <- 0L
files_processed_ev <- 0L
files_skipped_ev <- 0L

.aq_to_num <- function(x) {
  if (is.null(x)) return(numeric(0))
  if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
  if (is.array(x) || is.matrix(x)) x <- as.vector(x)
  x <- suppressWarnings(as.numeric(x))
  x[is.finite(x)]
}
.get_cfu_id_safe <- function(cfuList, i_row) {
  v <- tryCatch(.aq_to_num(cfuList[i_row, 1][[1]]), error = function(e) numeric(0))
  if (length(v) >= 1 && is.finite(v[1])) as.integer(v[1]) else as.integer(i_row)
}

# [v4.23] FAST/skip: bypass Part A2 (per-event summary) by emptying csv_files.
if (isTRUE(SKIP_PARTA2)) {
  message("[v4.23] FAST/skip: bypassing Part A2 (per-event summary).")
  csv_files <- character(0)
}

for (csv_path in csv_files) {
  csv_name <- basename(csv_path)
  message("\n▶ (per-event) Processing CSV: ", csv_name)
  csv_base <- tools::file_path_sans_ext(csv_name)
  prefix   <- sub("_Ch[0-9]+$", "", csv_base)

  # [v4.11] Per-file tryCatch.  Same pattern as Part A: existing `next`
  # statements for legitimate skips still work; only uncaught errors
  # trigger the error handler.  This loop has no checkpoint because its
  # output is consolidated (a single CSV at the end), so partial-run
  # rows from a previous attempt would be invisible to a resume anyway.
  # Re-running this loop is cheap relative to Part A.
  tryCatch({
  
  mi <- match(prefix, mat_prefixes)
  if (is.na(mi)) {
    message("  ⚠️  No MAT for prefix ‘", prefix, "’ → skip per-event for this file.")
    files_skipped_ev <- files_skipped_ev + 1L
    next
  }
  mat_path <- mat_files[mi]
  m <- tryCatch(read_mat_smart(mat_path), error = function(e) { message("  ❌ MAT read error: ", e$message); NULL })
  if (is.null(m)) { files_skipped_ev <- files_skipped_ev + 1L; next }
  
  cfuList <- get_cfuinfo(m)
  # [v4.7] Distinguish "cfuInfo missing entirely" (clean skip, expected for
  # recordings with zero detected CFUs) from "cfuInfo present but wrong
  # shape" (unexpected; worth flagging more loudly).  Part A uses similar
  # wording -- keep the per-event log consistent.
  if (is.null(cfuList)) {
    message("  ⚠️  cfuInfo/cfuInfo1 missing → skip.")
    files_skipped_ev <- files_skipped_ev + 1L
    next
  }
  dims <- dim(cfuList)
  if (is.null(dims) || length(dims) != 2) {
    message("  ⚠️  Unexpected cfuInfo dims → skip file.")
    files_skipped_ev <- files_skipped_ev + 1L
    next
  }
  
  df_raw <- tryCatch(readr::read_csv(csv_path, col_names = FALSE),
                     error = function(e) { message("  ❌ CSV read error: ", e$message); NULL })
  if (is.null(df_raw)) { files_skipped_ev <- files_skipped_ev + 1L; next }
  
  idx_row <- which(df_raw$X1 == "Index")
  if (length(idx_row) == 0) {
    message("  ⚠️  No ‘Index’ row in CSV → skip.")
    files_skipped_ev <- files_skipped_ev + 1L
    next
  }
  
  event_ids <- as.integer(df_raw[idx_row, -1])
  var_names <- df_raw$X1[(idx_row+1):nrow(df_raw)]
  data_mat  <- as.matrix(df_raw[(idx_row+1):nrow(df_raw), -1])
  
  if (length(event_ids) != ncol(data_mat) || length(var_names) != nrow(data_mat)) {
    message("  ⚠️  CSV shape mismatch (events × variables) → skip.")
    files_skipped_ev <- files_skipped_ev + 1L
    next
  }
  
  nCFU <- dims[1]
  for (i_cfu in seq_len(nCFU)) {
    cfu_id <- .get_cfu_id_safe(cfuList, i_cfu)
    raw_ev_cell <- tryCatch(cfuList[i_cfu, 2][[1]], error = function(e) NULL)
    ev_idx <- as.integer(unlist(raw_ev_cell))
    ev_idx <- ev_idx[is.finite(ev_idx)]
    if (!length(ev_idx)) next
    
    t_event_sec_vec <- as.numeric(ev_idx) * frame_interval
    
    for (k in seq_along(ev_idx)) {
      e_id <- ev_idx[k]
      col_j <- which(event_ids == e_id)
      if (length(col_j) != 1) next
      e_values <- data_mat[, col_j, drop = TRUE]
      rec <- data.frame(
        File = prefix,
        CFU_ID = as.integer(cfu_id),
        EventID = as.integer(e_id),
        t_event_sec = as.numeric(t_event_sec_vec[k]),
        t(e_values),
        stringsAsFactors = FALSE
      )
      names(rec)[-(1:4)] <- make.names(var_names)
      per_event_i <- per_event_i + 1L
      per_event_all_rows[[per_event_i]] <- rec
    }
  }
  
  files_processed_ev <- files_processed_ev + 1L
  message("  ✔️  Per-event rows collected for ‘", prefix, "’.")
  # [v4.11] Maybe gc() after this file.  The per-event loop builds large
  # row lists; gc helps keep memory bounded over hundreds of files.
  .v411_maybe_gc("per-event file")
  }, error = function(e) {
    # [v4.11] Uncaught error: log and skip this file.  Note the per-event
    # loop has no diagnostic accumulator of its own; the failure shows up
    # in the log file and reduces files_processed_ev.
    msg <- conditionMessage(e)
    message("  ❌ [", SCRIPT_VERSION, "] Uncaught error in per-event for '",
            prefix, "': ", msg)
    files_skipped_ev <<- files_skipped_ev + 1L
  })
}

if (per_event_i > 0) {
  per_event_df <- as.data.frame(data.table::rbindlist(per_event_all_rows, fill = TRUE))  # [opt] fast rbind
  parts <- strsplit(per_event_df$File, "_")
  max_terms <- max(lengths(parts))
  padded <- lapply(parts, function(x){ length(x) <- max_terms; x })
  ids_mat <- do.call(rbind, padded)
  colnames(ids_mat) <- paste0("ID", seq_len(max_terms))
  per_event_df2 <- cbind(as.data.frame(ids_mat, stringsAsFactors = FALSE), per_event_df)
  per_event_df2 <- cbind(parse_stems(sub("_AQuA2$", "", per_event_df2$File)), per_event_df2)  # [hCO] parsed metadata
  
  out_consolidated <- file.path(out_dir, paste0("per_cell_per_event_summary", .shard_sfx, ".csv"))  # [v4.18] shard-suffixed in process stage
  readr::write_csv(per_event_df2, out_consolidated)
  message("✔️  Wrote per-cell-per-event summary: ", out_consolidated)
  
  by_file <- split(per_event_df2, per_event_df2$File)
  out_dir_events <- file.path(out_dir, "PerCellPerEvent")
  if (!dir.exists(out_dir_events)) dir.create(out_dir_events, recursive = TRUE)
  for (nm in names(by_file)) {
    readr::write_csv(by_file[[nm]], file.path(out_dir_events, paste0(nm, "_perCellPerEvent.csv")))
  }
  message("✔️  Wrote per-file per-event CSVs in: ", out_dir_events)
} else {
  message("ℹ️  No per-event rows collected.")
}

message("Per-event pass complete. Proceeding to POST-CFU visualizations…")

# --------------------------------------- PART B: POST-CFU VISUALIZATIONS ---------------------------------------
# §23 -- The per-file visualization loop.  For each MAT file (with its
# detected CFUs from AQuA2):
#   1. Reads cfuList, cfuRelation, datPro, fts, and the PRE companion
#      .mat for fts windows.
#   2. Emits the feature panel (per-CFU rise/decay/amplitude summary).
#   3. Emits dF/F0 and non-dF/F0 weighted-average timecourses
#      (faceted, overlaid, heatmaps; per-CFU singles).
#   4. Emits per-CFU spatial maps and per-file combined presence/sum.
#   5. Emits the event-sequence raster.
#   6. Emits per-event annotated overlays (peak-aligned + legacy).
#   7. Computes cfuRelation, writes the lag table, draws the directed
#      relationship graph.
#   8. If cfuGroupInfo is present: detects network bursts on raw event
#      times, emits per-group raw + aligned waveform plots, and
#      consolidates membership + bursts CSVs.
#
# Production-scale behaviour:
#   - Each iteration is wrapped in tryCatch (v4.7): an error inside any
#     of the steps above is recorded in the JSON's vis_loop accumulator
#     and the loop moves to the next file.
#   - Per-CFU annotated overlays + spatial maps gated by PLOT_EVERYTHING
#     (v4.11): TRUE = full output set, FALSE = scale-friendly subset.
#   - gc() fires every GC_EVERY_N_FILES files [v4.11].
# --------------------------------------- PART B: POST-CFU VISUALIZATIONS ---------------------------------------
mat_files_vis <- if (isTRUE(SKIP_PARTB_VIS)) {
  message("[v4.23] FAST/skip: bypassing Part B (per-file visualization loop).")
  character(0)
} else mat_files   # [hCO] reuse paired + TEST_MODE-subset list from Part A
message("\n= Starting POST-CFU visualization pass (", length(mat_files_vis), " MAT files) =")

# Global accumulators for membership and bursts across all files
all_grp_rows <- list()
all_burst_rows <- list()

# ---------------- MANUAL GROUP EVENT ANNOTATION (VISUAL) – SETTINGS + HELPERS ----------------
manual_burst_enable <- TRUE
manual_burst_color  <- "#E36F47"
manual_burst_alpha  <- 0.9
manual_burst_lwd    <- 0.7

# Flat manual CSV path: one CSV per prefix, all in one folder
get_manual_csv_path <- function(prefix) {
  dir.create(dir_grp_manual_csvs, recursive = TRUE, showWarnings = FALSE)
  file.path(dir_grp_manual_csvs, paste0(prefix, "_manual_group_events.csv"))
}

manual_consolidated_out <- file.path(dir_grp_csv, "group_event_bursts_manual.csv")

read_manual_group_times <- function(prefix, group_id) {
  csv_path <- get_manual_csv_path(prefix)
  if (!file.exists(csv_path)) return(numeric(0))
  df <- tryCatch(readr::read_csv(csv_path, show_col_types = FALSE), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(numeric(0))
  nm <- tolower(names(df))
  col_file  <- which(nm == "file")
  col_gid   <- which(nm == "groupid")
  col_t     <- which(nm %in% c("t_sec","time","time_sec","t"))
  if (length(col_file)!=1 || length(col_gid)!=1 || length(col_t)!=1) return(numeric(0))
  idx <- which(as.character(df[[col_file]]) == prefix & as.integer(df[[col_gid]]) == as.integer(group_id))
  if (!length(idx)) return(numeric(0))
  out <- suppressWarnings(as.numeric(df[[col_t]][idx]))
  out <- out[is.finite(out)]
  sort(unique(out))
}

# Save a manual-only bundle (flat; no automatic markers inside bundle plots)
save_group_waveform_bundle <- function(prefix, gid, frame_interval, d_aligned, d_raw, grp_wave_use_dff0) {
  if (is.null(d_aligned) && is.null(d_raw)) return(invisible(NULL))
  if (!dir.exists(dir_grp_manual_bundles)) dir.create(dir_grp_manual_bundles, recursive = TRUE, showWarnings = FALSE)
  bundle_path <- file.path(
    dir_grp_manual_bundles,
    paste0(prefix, "_Group", gid, if (grp_wave_use_dff0) "_dFF0" else "_non_dFF0", "_bundle.Rds")
  )
  obj <- list(
    file = prefix,
    group_id = gid,
    frame_interval = frame_interval,
    aligned = d_aligned,
    raw     = d_raw
  )
  saveRDS(obj, bundle_path)
  invisible(bundle_path)
}

overlay_manual_annotations <- function(p, manual_times_sec) {
  if (is.null(p) || !length(manual_times_sec)) return(p)
  p + ggplot2::geom_vline(
    xintercept = manual_times_sec,
    color = manual_burst_color,
    alpha = manual_burst_alpha,
    linewidth = manual_burst_lwd
  )
}

# Accumulator to collect manual annotations during plotting; write once after loop.
.all_manual_burst_rows <- list()

record_manual_for_consolidation <- function(prefix, gid, members, manual_times_sec, duration_sec) {
  if (!length(manual_times_sec)) return(invisible(NULL))
  manual_count <- length(manual_times_sec)
  .all_manual_burst_rows[[length(.all_manual_burst_rows)+1]] <<- data.frame(
    File = prefix,
    GroupID = as.integer(gid),
    n_members = length(members),
    members_json = safe_json(as.integer(members)),
    manual_burst_count = manual_count,
    duration_sec = duration_sec,
    manual_burst_freq_hz = if (is.finite(duration_sec) && duration_sec > 0) manual_count / duration_sec else NA_real_,
    manual_burst_rate_per_min = if (is.finite(duration_sec) && duration_sec > 0) manual_count / (duration_sec / 60) else NA_real_,
    manual_burst_times_sec_json = safe_json(as.numeric(sort(manual_times_sec))),
    stringsAsFactors = FALSE
  )
  invisible(NULL)
}

write_consolidated_manual_csv <- function() {
  if (!length(.all_manual_burst_rows)) {
    message("ℹ️  No manual group event annotations found during this run.")
    return(invisible(NULL))
  }
  manual_rows_fixed <- lapply(.all_manual_burst_rows, function(df) {
    for (nm in c("members_json","manual_burst_times_sec_json")) {
      if (nm %in% names(df)) df[[nm]] <- as.character(df[[nm]])
    }
    df
  })
  manual_df_all <- dplyr::bind_rows(manual_rows_fixed)
  parts_m <- strsplit(manual_df_all$File, "_")
  max_terms_m <- max(lengths(parts_m))
  padded_m <- lapply(parts_m, function(x){ length(x) <- max_terms_m; x })
  ids_mat_m <- do.call(rbind, padded_m); colnames(ids_mat_m) <- paste0("ID", seq_len(max_terms_m))
  manual_df_all <- cbind(as.data.frame(ids_mat_m, stringsAsFactors = FALSE), manual_df_all)
  readr::write_csv(manual_df_all, manual_consolidated_out)
  message("✔️  Wrote consolidated manual group events: ", manual_consolidated_out)
  invisible(manual_consolidated_out)
}

launch_manual_group_event_annotator <- function(results_dir = out_dir) {
  suppressPackageStartupMessages({
    library(shiny); library(ggplot2); library(dplyr); library(readr)
  })
  bundles_root <- dir_grp_manual_bundles
  list_bundles <- function() list.files(bundles_root, pattern = r"(_bundle\.Rds$)", full.names = TRUE)
  load_bundle <- function(path) {
    x <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(x)) return(NULL)
    req_fields <- c("file","group_id","aligned","raw")
    if (!all(req_fields %in% names(x))) return(NULL)
    x
  }
  load_file_ann <- function(prefix) {
    f <- get_manual_csv_path(prefix)
    if (file.exists(f)) suppressWarnings(readr::read_csv(f, show_col_types = FALSE)) else
      tibble::tibble(File=character(), GroupID=integer(), t_sec=double(), label=character(), note=character())
  }
  save_file_ann <- function(prefix, df) {
    f <- get_manual_csv_path(prefix)
    readr::write_csv(df, f)
  }
  
  ui <- fluidPage(
    titlePanel("Manual Group Event Annotation"),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        selectInput("bundle_path", "Bundle", choices = list_bundles(), width = "100%"),
        radioButtons("view_mode", "View", choices = c("Aligned","Raw"), selected = "Aligned", inline = TRUE),
        checkboxInput("show_auto", "Show automatic events", FALSE),
        textInput("label_text", "Optional label", value = ""),
        textInput("note_text", "Optional note", value = ""),
        actionButton("btn_save", "Save annotations (for this File)"),
        actionButton("btn_clear_group", "Clear current group's annotations"),
        hr(),
        h4("Current group's annotations (s)"),
        tableOutput("annot_table")
      ),
      mainPanel(
        width = 9,
        plotOutput("wave_plot", height = "520px", click = "plot_click"),
        p("Click to add a marker. Click near an existing marker (±0.25s) to remove.")
      )
    )
  )
  
  server <- function(input, output, session) {
    observe({ updateSelectInput(session, "bundle_path", choices = list_bundles()) })
    bundle <- reactive({ req(input$bundle_path); load_bundle(input$bundle_path) })
    ann_df <- reactiveVal(NULL)
    
    observeEvent(bundle(), {
      bd <- bundle(); req(bd)
      ann_df(load_file_ann(bd$file))
    }, ignoreInit = FALSE)
    
    output$annot_table <- renderTable({
      bd <- bundle(); req(bd)
      df <- ann_df(); if (is.null(df)) return(NULL)
      df %>% dplyr::filter(File == bd$file, GroupID == as.integer(bd$group_id)) %>%
        dplyr::arrange(t_sec) %>% dplyr::mutate(t_sec = round(t_sec, 3))
    })
    
    output$wave_plot <- renderPlot({
      bd <- bundle(); req(bd)
      d <- if (input$view_mode == "Aligned") bd$aligned else bd$raw
      req(nrow(d) > 0)
      mean_df <- d %>% dplyr::filter(is.finite(y)) %>% dplyr::group_by(t_sec) %>% dplyr::summarize(y = mean(y, na.rm = TRUE), .groups = "drop")
      p <- ggplot(d %>% dplyr::filter(is.finite(y)), aes(x = t_sec, y = y, group = CFU_ID, color = CFU_ID)) +
        geom_line(alpha = 0.5, linewidth = 0.4, show.legend = FALSE) +
        geom_line(data = mean_df, aes(x = t_sec, y = y), inherit.aes = FALSE, color = "black", linewidth = 0.9) +
        theme_minimal() + labs(title = paste0("File=", bd$file, "  Group=", bd$group_id, " [", input$view_mode, "]"),
                               x = "Time (s)", y = "Signal (z)")
      if (isTRUE(input$show_auto) && !is.null(bd$burst_auto_times_sec) && length(bd$burst_auto_times_sec)) {
        p <- p + geom_vline(xintercept = bd$burst_auto_times_sec, color = "#222222", alpha = 0.6, linewidth = 0.7)
      }
      df <- ann_df(); mt <- numeric(0)
      if (!is.null(df)) {
        mt <- df %>% dplyr::filter(File == bd$file, GroupID == as.integer(bd$group_id)) %>% dplyr::pull(t_sec)
        mt <- sort(unique(as.numeric(mt[is.finite(mt)])))
      }
      if (length(mt))
        p <- p + geom_vline(xintercept = mt, color = manual_burst_color, alpha = manual_burst_alpha, linewidth = manual_burst_lwd)
      p
    })
    
    observeEvent(input$plot_click, {
      bd <- bundle(); req(bd)
      t_click <- as.numeric(input$plot_click$x); if (!is.finite(t_click)) return(NULL)
      df <- ann_df(); if (is.null(df)) df <- tibble::tibble(File=character(), GroupID=integer(), t_sec=double(), label=character(), note=character())
      rows <- which(df$File == bd$file & df$GroupID == as.integer(bd$group_id))
      tol <- 0.25
      if (length(rows)) {
        tvals <- as.numeric(df$t_sec[rows])
        j <- which.min(abs(tvals - t_click))
        if (length(j) == 1 && abs(tvals[j] - t_click) <= tol) {
          df <- df[-rows[j], , drop = FALSE]
          ann_df(df); return(NULL)
        }
      }
      new_row <- tibble::tibble(File = bd$file, GroupID = as.integer(bd$group_id),
                                t_sec = t_click, label = input$label_text, note = input$note_text)
      ann_df(dplyr::bind_rows(df, new_row))
    })
    
    observeEvent(input$btn_clear_group, {
      bd <- bundle(); req(bd)
      df <- ann_df(); if (is.null(df)) return(NULL)
      ann_df(df %>% dplyr::filter(!(File == bd$file & GroupID == as.integer(bd$group_id))))
    })
    
    observeEvent(input$btn_save, {
      bd <- bundle(); req(bd)
      df <- ann_df(); if (is.null(df)) return(NULL)
      df <- df %>% dplyr::filter(File == bd$file) %>%
        dplyr::arrange(GroupID, t_sec) %>%
        dplyr::distinct(File, GroupID, t_sec, .keep_all = TRUE)
      save_file_ann(bd$file, df)
      showNotification(paste0("Saved annotations for File=", bd$file), type = "message", duration = 2)
    })
  }
  
  shinyApp(ui, server)
}

# -------------------- Visualization loop --------------------
# [v4.7] Each iteration is wrapped in tryCatch so a fatal error inside one
# file (e.g. an uncaught grid viewport error, an HDF5 read failure, an
# igraph layout error) no longer aborts the entire Part B batch.  The error
# is printed with the file name and the loop continues to the next file.
for (mat_path in mat_files_vis) {
  # [v4.8] Track per-file vis-loop status for the JSON diagnostic summary.
  # We snapshot the failure-counter at the start of the iteration so we can
  # compute "failures attributable to THIS file" at the end.  Status starts
  # as "unknown" and is overwritten depending on what happens.
  .v48_vis_idx     <- length(.v48_vis_files) + 1L
  .v48_vis_fail_n0 <- length(.v48_ggsave_failures)
  .v48_vis_files[[.v48_vis_idx]] <- list(
    prefix = sub("_res_cfu\\.mat$", "", basename(mat_path)),
    status = "started", ggsave_failures = 0L, err_message = NA_character_)
  tryCatch({
  message("\n▶ Reading (vis): ", basename(mat_path))
  # [v1.6] read_mat_smart: v5/v6 via readMat; v7.3 HDF5 via hdf5r (returns same named list)
  res <- read_mat_smart(mat_path)
  if (is.null(res)) next

  cfuList <- get_cfuinfo(res)
  if (is.null(cfuList)) { message("  ⚠️ No cfuInfo/cfuInfo1 → skip file"); next }
  dims <- dim(cfuList)
  if (is.null(dims) || length(dims) != 2 || dims[2] < 6) { message("  ⚠️ Unexpected cfuInfo dims → skip file"); next }
  
  nCFU   <- dims[1]
  prefix <- sub("_res_cfu\\.mat$", "", basename(mat_path))
  message("  ✅ cfuInfo OK for ", prefix, ": ", nCFU, " CFUs.")
  # [v3.0] Resolve fts_vecs for this file (needed by plot_single_cfu for grey traces)
  # Uses same recursive PRE companion search as integrate_event_windows_per_cfu()
  fts_vecs <- NULL
  if (isTRUE(event_use_true_duration)) {
    companion_path_vis <- get_pre_companion(prefix)                   # [opt] O(1) via pre_mat_index
    if (!is.null(companion_path_vis)) {
      fts_vecs <- tryCatch({
        h5f <- hdf5r::H5File$new(companion_path_vis, mode = "r")
        on.exit(try(h5f$close_all(), silent = TRUE), add = TRUE)
        .h5rv <- function(h5f, path) {
          if (!.h5_safe_exists(h5f, path)) return(NULL)
          v <- tryCatch(as.integer(round(as.numeric(h5f[[path]]$read()))), error=function(e) NULL)
          if (!is.null(v) && length(v) > 0) v else NULL
        }
        fts_root <- if (.h5_safe_exists(h5f, "res/fts1")) "res/fts1" else
                    if (.h5_safe_exists(h5f, "fts1"))     "fts1"     else
                    if (.h5_safe_exists(h5f, "res/fts"))  "res/fts"  else
                    if (.h5_safe_exists(h5f, "fts"))      "fts"      else NULL
        if (is.null(fts_root)) NULL else {
          tB <- .h5rv(h5f, paste0(fts_root, "/curve/tBegin"))
          tE <- .h5rv(h5f, paste0(fts_root, "/curve/tEnd"))
          tP <- .h5rv(h5f, paste0(fts_root, "/curve/dffMaxFrame"))
          if (is.null(tP)) tP <- tB
          if (!is.null(tB) && !is.null(tE) && length(tB)==length(tE))
            list(tBegin=tB, tEnd=tE, tPeak=tP) else NULL
        }
      }, error = function(e) NULL)
      if (!is.null(fts_vecs))
        message(sprintf("  [v3.0] fts_vecs loaded for vis loop: %d events", length(fts_vecs$tBegin)))
    }
  }

  
  file_rows_dff0    <- vector("list", nCFU)
  file_rows_nondff0 <- vector("list", nCFU)
  keep <- logical(nCFU)
  
  file_upper <- NA_real_
  if (spatial_use_filewide_scale) {
    max_q <- 0
    for (i in seq_len(nCFU)) {
      sp_cell <- cfuList[i, 3][[1]]
      sp_mat  <- to_numeric_matrix(sp_cell)
      nz <- as.numeric(sp_mat); nz <- nz[nz > 0 & is.finite(nz)]
      if (!length(nz)) next
      q <- as.numeric(stats::quantile(nz, probs = spatial_upper_quantile, na.rm = TRUE, type = 7))
      if (is.finite(q) && q > max_q) max_q <- q
    }
    file_upper <- if (is.finite(max_q) && max_q > 0) max_q else 1
  }
  
  for (i in seq_len(nCFU)) {
    id_cell    <- cfuList[i, 1][[1]]
    cfu_id_vec <- to_numeric_vec(id_cell)
    cfu_id     <- if (length(cfu_id_vec) >= 1) as.integer(cfu_id_vec[1]) else i
    dff_cell <- cfuList[i, 6][[1]]
    dff_vec  <- to_numeric_vec(dff_cell); if (length(dff_vec) == 0) next
    nT <- length(dff_vec)
    occ_cell <- cfuList[i, 4][[1]]
    occ_bin  <- to_binary_sequence(occ_cell, nT = nT)
    has_occ  <- length(occ_bin) == nT
    non_cell <- cfuList[i, 5][[1]]
    non_vec  <- to_numeric_vec(non_cell)
    if (length(non_vec) != nT) {
      if (length(non_vec) == 0) non_vec <- rep(NA_real_, nT)
      else non_vec <- if (length(non_vec) > nT) non_vec[seq_len(nT)] else c(non_vec, rep(NA_real_, nT - length(non_vec)))
    }
    file_rows_dff0[[i]] <- data.frame(File = prefix, CFU_ID = cfu_id, t_index = seq_len(nT), t_sec = seq_len(nT)*frame_interval,
                                      dFF0 = dff_vec, OccBin = if (has_occ) occ_bin else NA_real_, stringsAsFactors = FALSE)
    file_rows_nondff0[[i]] <- data.frame(File = prefix, CFU_ID = cfu_id, t_index = seq_len(nT), t_sec = seq_len(nT)*frame_interval,
                                         non_dFF0 = non_vec, OccBin = if (has_occ) occ_bin else NA_real_, stringsAsFactors = FALSE)
    keep[i] <- TRUE
  }
  
  if (!any(keep)) { message("  ⚠️ No CFU with weighted average dF/F0 in ", prefix, " → skip."); next }
  
  df_dff0 <- bind_rows(file_rows_dff0[keep])
  cfu_levels <- sort(unique(df_dff0$CFU_ID))
  df_dff0$CFU_ID <- factor(df_dff0$CFU_ID, levels = cfu_levels)
  
  df_nondff0 <- bind_rows(file_rows_nondff0[keep])
  df_nondff0$CFU_ID <- factor(df_nondff0$CFU_ID, levels = cfu_levels)
  
  # ---- Per‑CFU single‑trace PNGs (dF/F0) ----
  if (isTRUE(make_single_cfu)) {
    cfu_ids <- levels(df_dff0$CFU_ID)
    for (cid in cfu_ids) {
      # [v3.0] Always extract event times so grey traces are always drawn;
      # single_cfu_show_event_lines only controls the vertical marker lines.
      ev_times <- get_event_times_from_ev_idx(
        cfuList, as.integer(as.character(cid)), frame_interval)

      p1 <- plot_single_cfu(df_dff0, file_id = prefix, cfu_id = cid,
                             event_times_sec    = ev_times,
                             fts_vecs           = fts_vecs,
                             frame_interval_arg = frame_interval)
      if (!is.null(p1)) {
        .safe_ggsave(file.path(dir_dff0_singlecfu, paste0(prefix, "_CFU", cid, "_dFF0.png")),
                     plot = p1, tag = paste0("SingleCFU/", prefix, "_CFU", cid),
                     width = 8, height = 4, dpi = png_dpi)
      }
    }
    # Call modified integration passing full MAT file content 'res'
    integrate_event_windows_per_cfu(cfuList, res, df_dff0, prefix, frame_interval, mat_path = mat_path, fts_vecs = fts_vecs)  # [opt] fts read once

  # [v1.2] Per-CFU event feature panel — reads the metrics CSV just written above
  feat_csv <- file.path(dir_dff0_csv, paste0(prefix, "_CFUEventMetrics.csv"))
  plot_cfu_event_feature_panel(metrics_csv_path = feat_csv, prefix = prefix)
    
  }
  
  
  
  # ----- Compute safe CFU order (choose preferred method) -----
  cfu_order <- compute_cfu_order_by_timecourse(
    df_dff0, value_col = "dFF0", method = "corr", min_non_na_per_row = 3L
  )
  # Apply ordered factor to both data frames
  df_dff0$CFU_ID    <- factor(df_dff0$CFU_ID, levels = cfu_order, ordered = TRUE)
  df_nondff0$CFU_ID <- factor(df_nondff0$CFU_ID, levels = cfu_order, ordered = TRUE)
  
  
  if (save_long_csv) {
    write_csv(df_dff0,    file.path(dir_dff0_csv,  paste0(prefix, "_WeightedAvg_dFF0_long.csv")))
    write_csv(df_nondff0, file.path(dir_nond_csv,  paste0(prefix, "_WeightedAvg_non_dFF0_long.csv")))
  }
  
  # --- Recording duration for this file (robust, in seconds) ---
  duration_sec <- tryCatch({
    d <- suppressWarnings(max(df_dff0$t_sec, na.rm = TRUE))
    if (!is.finite(d) || d <= 0) {
      # fallback: derive nT from the longest CFU trace in the MAT
      nT_vec <- vapply(seq_len(nCFU), function(i) {
        v <- to_numeric_vec(cfuList[i, 6][[1]])  # dF/F0 vector
        length(v)
      }, FUN.VALUE = integer(1))
      nT <- suppressWarnings(max(nT_vec, na.rm = TRUE))
      if (is.finite(nT) && nT > 0) nT * frame_interval else NA_real_
    } else {
      d
    }
  }, error = function(e) NA_real_)
  
  
  # ---------------- CFU GROUP WAVEFORM PLOTS (Aligned + Raw) + RAW-TIME EVENT BURSTS ----------------
  if (grp_plot_waveforms || grp_burst_enable) {
    grp <- get_cfu_groupinfo(res)
    grp_valid <- FALSE
    if (!is.null(grp)) {
      grp_valid <- tryCatch({
        nrows <- nrow(grp)
        !is.null(nrows) && is.finite(nrows) && nrows > 0
      }, error = function(e) {
        tryCatch({
          if (is.list(grp) && length(grp) > 0) TRUE else FALSE
        }, error = function(e2) FALSE)
      })
    }
    
    if (grp_valid) {
      nGroups <- tryCatch(nrow(grp), error = function(e) NA_integer_)
      if (!is.finite(nGroups) || nGroups <= 0) {
        message("  ℹ️  cfuGroupInfo present but row count invalid – skipping group outputs.")
      } else {
        grp_rows  <- list()
        burst_rows <- list()
        
        dff_list <- vector("list", nCFU)
        for (i in seq_len(nCFU)) {
          col_idx <- if (grp_wave_use_dff0) 6 else 5
          dff_list[[i]] <- to_numeric_vec(cfuList[i, col_idx][[1]])
        }
        
        for (gi in seq_len(nGroups)) {
          gid     <- to_numeric_vec(grp[gi, 1][[1]]); gid <- if (length(gid)) as.integer(gid[1]) else gi
          members <- as.integer(to_numeric_vec(grp[gi, 2][[1]]))
          rdel    <- to_numeric_vec(grp[gi, 3][[1]])
          mpvals  <- to_numeric_vec(grp[gi, 4][[1]])
          if (length(members) == 0) next
          
          if (length(rdel) != length(members)) {
            if (length(rdel) < length(members)) rdel <- c(rdel, rep(0, length(members) - length(rdel))) else rdel <- rdel[seq_len(length(members))]
          }
          rdel_frames <- as.integer(round(rdel))
          
          grp_rows[[length(grp_rows)+1]] <- data.frame(
            File = prefix, GroupID = gid, n_members = length(members),
            members_json = safe_json(as.integer(members)),
            rel_delays_frames_json = safe_json(as.integer(rdel_frames)),
            rel_delays_sec_json = safe_json(as.numeric(rdel_frames * frame_interval)),
            member_p_json = safe_json(as.numeric(mpvals)),
            stringsAsFactors = FALSE
          )
          
          # RAW-time clustering (automatic)
          burst_times_sec <- numeric(0)
          if (isTRUE(grp_burst_enable)) {
            get_times_fun <- function(prefix_arg, cfu_arg) { get_cfu_event_times_sec_from_mat(cfuList, cfu_arg, frame_interval) }
            events_by_cfu <- ppx_collect_member_events(prefix, members, get_times_fun)
            tau_sec  <- grp_burst_tau_sec
            refr_sec <- grp_burst_refractory_sec
            min_frac <- if (is.na(grp_burst_min_participating)) grp_burst_min_fraction else NA
            min_part <- if (!is.na(grp_burst_min_participating)) grp_burst_min_participating else NA
            cl <- ppx_cluster_group_events(events_by_cfu,
                                           tau_sec = tau_sec,
                                           refractory_sec = refr_sec,
                                           min_participating = min_part,
                                           min_fraction = min_frac)
            ep <- cl$episodes
            burst_count <- nrow(ep)
            if (burst_count > 0) burst_times_sec <- as.numeric(ep$ep_time_sec)
            
            burst_rows[[length(burst_rows)+1]] <- data.frame(
              File = prefix,
              GroupID = gid,
              n_members = length(members),
              members_json = safe_json(as.integer(members)),
              burst_count = burst_count,
              duration_sec = duration_sec,
              burst_freq_hz = if (is.finite(duration_sec) && duration_sec > 0) burst_count / duration_sec else NA_real_,
              burst_rate_per_min = if (is.finite(duration_sec) && duration_sec > 0) burst_count / (duration_sec / 60) else NA_real_,
              burst_times_sec_json = safe_json(if (burst_count) burst_times_sec else numeric(0)),
              params_json = safe_json(list(
                method = "event_coincidence_cluster_raw",
                tau_sec = tau_sec, refractory_sec = refr_sec,
                min_fraction = if (is.na(min_part)) min_frac else NA,
                min_participating = if (!is.na(min_part)) as.integer(min_part) else NA
              ), auto_unbox = TRUE),
              stringsAsFactors = FALSE
            )
          } # <-- close: if (isTRUE(grp_burst_enable))
          
          # Build data for plots
          d_aligned <- build_group_long(dff_list, members, rdel_frames, frame_interval, zscore = grp_wave_zscore_per_cfu, apply_shift = TRUE)
          d_raw     <- build_group_long(dff_list, members, rdel_frames, frame_interval, zscore = grp_wave_zscore_per_cfu, apply_shift = FALSE)
          
          # AUTOMATIC plots (flat)
          if (grp_plot_waveforms) {
            if (nrow(d_aligned) > 0) {
              p_auto_al <- plot_group_waveforms(d_aligned, file_id = prefix, group_id = gid, apply_shift = TRUE,
                                                use_dff0 = grp_wave_use_dff0,
                                                alpha = grp_wave_alpha, lwd = grp_wave_lwd, mean_lwd = grp_wave_mean_lwd)
              if (!is.null(p_auto_al) && isTRUE(grp_burst_overlay_enable) && length(burst_times_sec)) {
                p_auto_al <- add_burst_lines_to_group_plot(p_auto_al, burst_times_sec,
                                                           color = grp_burst_marker_color,
                                                           alpha = grp_burst_marker_alpha,
                                                           lwd   = grp_burst_marker_lwd) +
                  labs(subtitle = grp_burst_overlay_subtitle)
              }
              if (!is.null(p_auto_al)) {
                .safe_ggsave(file.path(dir_grp_wave_aligned, paste0(prefix, "_Group", gid, if (grp_wave_use_dff0) "_dFF0" else "_non_dFF0", "_Aligned_Auto.png")),
                             plot = p_auto_al,
                             tag = paste0("GroupAlignedAuto/", prefix, "_G", gid),
                             width = 10, height = 5, dpi = png_dpi)
              }
            }
            if (nrow(d_raw) > 0) {
              p_auto_rw <- plot_group_waveforms(d_raw, file_id = prefix, group_id = gid, apply_shift = FALSE,
                                                use_dff0 = grp_wave_use_dff0,
                                                alpha = grp_wave_alpha, lwd = grp_wave_lwd, mean_lwd = grp_wave_mean_lwd)
              if (!is.null(p_auto_rw) && isTRUE(grp_burst_overlay_enable) && length(burst_times_sec)) {
                p_auto_rw <- add_burst_lines_to_group_plot(p_auto_rw, burst_times_sec,
                                                           color = grp_burst_marker_color,
                                                           alpha = grp_burst_marker_alpha,
                                                           lwd   = grp_burst_marker_lwd) +
                  labs(subtitle = grp_burst_overlay_subtitle)
              }
              if (!is.null(p_auto_rw)) {
                .safe_ggsave(file.path(dir_grp_wave_raw, paste0(prefix, "_Group", gid, if (grp_wave_use_dff0) "_dFF0" else "_non_dFF0", "_Raw_Auto.png")),
                             plot = p_auto_rw,
                             tag = paste0("GroupRawAuto/", prefix, "_G", gid),
                             width = 10, height = 5, dpi = png_dpi)
              }
            }
          }
          
          # MANUAL bundles and MANUAL plots (flat; manual lines only)
          save_group_waveform_bundle(prefix, gid, frame_interval, d_aligned, d_raw, grp_wave_use_dff0)
          manual_times_sec <- if (isTRUE(manual_burst_enable)) read_manual_group_times(prefix, gid) else numeric(0)
          
          # --- Replace original call: pass duration_sec so manual CSV has duration and rates ---
          # Call site (inside group loop, after manual_times_sec is read):
          record_manual_for_consolidation(prefix, gid, members, manual_times_sec, duration_sec)
          
          if (nrow(d_aligned) > 0) {
            p_man_al <- plot_group_waveforms(d_aligned, file_id = paste0(prefix," (Manual)"), group_id = gid, apply_shift = TRUE,
                                             use_dff0 = grp_wave_use_dff0,
                                             alpha = grp_wave_alpha, lwd = grp_wave_lwd, mean_lwd = grp_wave_mean_lwd)
            if (!is.null(p_man_al) && length(manual_times_sec)) {
              p_man_al <- overlay_manual_annotations(p_man_al, manual_times_sec) +
                labs(subtitle = "Manual annotations")
            }
            if (!is.null(p_man_al)) {
              .safe_ggsave(file.path(dir_grp_manual_aligned, paste0(prefix, "_Group", gid, if (grp_wave_use_dff0) "_dFF0" else "_non_dFF0", "_Aligned_Manual.png")),
                           plot = p_man_al,
                           tag = paste0("GroupAlignedManual/", prefix, "_G", gid),
                           width = 10, height = 5, dpi = png_dpi)
            }
          }
          if (nrow(d_raw) > 0) {
            p_man_rw <- plot_group_waveforms(d_raw, file_id = paste0(prefix," (Manual)"), group_id = gid, apply_shift = FALSE,
                                             use_dff0 = grp_wave_use_dff0,
                                             alpha = grp_wave_alpha, lwd = grp_wave_lwd, mean_lwd = grp_wave_mean_lwd)
            if (!is.null(p_man_rw) && length(manual_times_sec)) {
              p_man_rw <- overlay_manual_annotations(p_man_rw, manual_times_sec) +
                labs(subtitle = "Manual annotations")
            }
            if (!is.null(p_man_rw)) {
              .safe_ggsave(file.path(dir_grp_manual_raw, paste0(prefix, "_Group", gid, if (grp_wave_use_dff0) "_dFF0" else "_non_dFF0", "_Raw_Manual.png")),
                           plot = p_man_rw,
                           tag = paste0("GroupRawManual/", prefix, "_G", gid),
                           width = 10, height = 5, dpi = png_dpi)
            }
          }
        } # end groups
        
        if (length(grp_rows) > 0) {
          all_grp_rows[[length(all_grp_rows)+1]] <- dplyr::bind_rows(grp_rows)
          message("  • Group membership rows collected for ‘", prefix, "’.")
        }
        if (isTRUE(grp_burst_enable) && length(burst_rows) > 0) {
          all_burst_rows[[length(all_burst_rows)+1]] <- dplyr::bind_rows(burst_rows)
          message("  • Group event bursts collected for ‘", prefix, "’.")
        }
        if (grp_plot_waveforms) message("  ✔️  Group waveform plots saved for ‘", prefix, "’.")
      }
    } else {
      message("  ℹ️  No cfuGroupInfo in ‘", prefix, "’ or group info is empty – skipping group outputs.")
    }
  }
  
  # ---------------- Additional per-file visualizations outside group section ----------------
  # [v4.7] All ggsave calls below routed through .safe_ggsave so a single
  # bad plot can no longer abort the entire Part B loop with a viewport
  # error. Each call has a distinct tag so the log identifies which plot
  # failed for which file.
  if (make_overlaid_lines) {
    p <- plot_overlaid_dff0(df_dff0, file_id = prefix, use_z = use_z_for_lines)
    .safe_ggsave(file.path(dir_dff0_overlaid, paste0(prefix, "_WeightedAvg_dFF0_Timecourses_Overlaid.png")),
                 plot = p, tag = paste0("OverlaidDFF0/", prefix),
                 width = 10, height = 6, dpi = png_dpi)
  }
  if (make_faceted_lines) {
    p <- plot_faceted_dff0(df_dff0, file_id = prefix, use_z = FALSE, ncol = 6)
    .safe_ggsave(file.path(dir_dff0_faceted, paste0(prefix, "_WeightedAvg_dFF0_Timecourses_Faceted.png")),
                 plot = p, tag = paste0("FacetedDFF0/", prefix),
                 width = 14, height = 10, dpi = png_dpi)
  }
  p <- plot_overlaid_nondff0(df_nondff0, file_id = prefix)
  .safe_ggsave(file.path(dir_nond_overlaid, paste0(prefix, "_WeightedAvg_non_dFF0_Timecourses_Overlaid.png")),
               plot = p, tag = paste0("OverlaidNonDFF0/", prefix),
               width = 10, height = 6, dpi = png_dpi)
  p <- plot_faceted_nondff0(df_nondff0, file_id = prefix, ncol = 6)
  .safe_ggsave(file.path(dir_nond_faceted, paste0(prefix, "_WeightedAvg_non_dFF0_Timecourses_Faceted.png")),
               plot = p, tag = paste0("FacetedNonDFF0/", prefix),
               width = 14, height = 10, dpi = png_dpi)

  if (make_heatmap) {
    p <- plot_heatmap_dff0_raw(df_dff0, file_id = prefix)
    .safe_ggsave(file.path(dir_dff0_heat_raw, paste0(prefix, "_WeightedAvg_dFF0_Timecourses_Heatmap_Raw.png")),
                 plot = p, tag = paste0("HeatmapDFF0Raw/", prefix),
                 width = 10, height = 8, dpi = png_dpi)
    p <- plot_heatmap_dff0_norm(df_dff0, file_id = prefix)
    .safe_ggsave(file.path(dir_dff0_heat_norm, paste0(prefix, "_WeightedAvg_dFF0_Timecourses_Heatmap_Norm.png")),
                 plot = p, tag = paste0("HeatmapDFF0Norm/", prefix),
                 width = 10, height = 8, dpi = png_dpi)
  }

  p <- plot_heatmap_nondff0_raw(df_nondff0, file_id = prefix)
  .safe_ggsave(file.path(dir_nond_heat_raw, paste0(prefix, "_WeightedAvg_non_dFF0_Timecourses_Heatmap_Raw.png")),
               plot = p, tag = paste0("HeatmapNonDFF0Raw/", prefix),
               width = 10, height = 8, dpi = png_dpi)

  if (make_raster) {
    p <- plot_raster_occ(df_dff0, file_id = prefix)
    if (!is.null(p))
      .safe_ggsave(file.path(dir_raster_root, paste0(prefix, "_CFU_EventSequence_Raster_Onsets.png")),
                   plot = p, tag = paste0("Raster/", prefix),
                   width = 10, height = 8, dpi = png_dpi)
  }
  
  # Spatial maps: per-CFU (flat) and combined per-file presence/sum (flat)
  # [v4.11] The per-CFU loop below is gated by PLOT_EVERYTHING; the
  # combined per-file map (further down) is always emitted because it's
  # one PNG per file, not per CFU.
  if (isTRUE(PLOT_EVERYTHING)) {
  for (i in seq_len(nCFU)) {
    id_cell    <- cfuList[i, 1][[1]]
    cfu_id_vec <- to_numeric_vec(id_cell)
    cfu_id     <- if (length(cfu_id_vec) >= 1) as.integer(cfu_id_vec[1]) else i
    sp_cell <- cfuList[i, 3][[1]]
    sp_mat  <- to_numeric_matrix(sp_cell)
    if (!is.matrix(sp_mat) || any(dim(sp_mat) == 0)) next
    out_png <- file.path(dir_spatial_percfu, paste0(prefix, "_CFU", cfu_id, "_SpatialPattern.png"))
    ttl <- paste0("CFU ", cfu_id, " – Weighted Spatial Pattern (col 3) – ", prefix)
    save_cfu_spatial_png(
      spmat = sp_mat,
      out_png = out_png,
      title = ttl,
      upper_limit = if (spatial_use_filewide_scale) file_upper else NULL,
      upper_quantile = spatial_upper_quantile,
      width_in = 5, height_in = 5, dpi = png_dpi
    )
  }
  }  # /PLOT_EVERYTHING
  
  comb <- combine_cfu_spatial_patterns(cfuList, binarize = TRUE)
  if (!is.null(comb)) {
    pres_png <- file.path(dir_spatial_perfile, paste0(prefix, "_CFU_All_SpatialPresence.png"))
    save_cfu_spatial_png(
      spmat = comb$presence,
      out_png = pres_png,
      title = paste0("All CFUs – Presence Map (", prefix, ")"),
      upper_limit = 1,
      upper_quantile = 1,
      width_in = 6, height_in = 6, dpi = png_dpi
    )
    sum_png <- file.path(dir_spatial_perfile, paste0(prefix, "_CFU_All_SummedWeights.png"))
    save_cfu_spatial_png(
      spmat = comb$sum,
      out_png = sum_png,
      title = paste0("All CFUs – Summed Spatial Weights (", prefix, ")"),
      upper_limit = NULL,
      upper_quantile = spatial_upper_quantile,
      width_in = 6, height_in = 6, dpi = png_dpi
    )
  } else {
    message("  ℹ️  Combined spatial map skipped for ‘", prefix, "’ (no usable CFU spatial matrices or mismatched dims).")
  }
  
  # Relationships (unchanged) ...
  # end per-file visualization loop
  
  # Relationships
  if (rel_make_graphs) {
    rel <- get_cfu_relation(res)
    if (!is.null(rel)) {
      rel_mat <- to_numeric_matrix(rel)
      if (ncol(rel_mat) >= 4 && nrow(rel_mat) > 0) {
        rel_df <- as.data.frame(rel_mat[,1:4, drop=FALSE]); names(rel_df) <- c("c1","c2","p","delay")
        rel_df$c1 <- as.integer(round(rel_df$c1))
        rel_df$c2 <- as.integer(round(rel_df$c2))
        # v1.7: skip BH when fewer than 10 pairs — too few for meaningful FDR correction
        # [v3.0] Skip BH for tiny pair counts; replace any NA p_adj with raw p
        rel_df$p_adj <- if (nrow(rel_df) >= 10) p.adjust(rel_df$p, method = "BH") else rel_df$p
        rel_df$p_adj <- ifelse(!is.finite(rel_df$p_adj) & is.finite(rel_df$p),
                               rel_df$p, rel_df$p_adj)
        rel_df$delay_sec <- rel_df$delay * frame_interval
        
        dir_map <- rel_df %>%
          mutate(
            delay_sec = ifelse(is.finite(delay_sec), delay_sec, NA_real_),
            delay_class = dplyr::case_when(
              !is.finite(delay_sec) ~ "na",
              abs(delay_sec) < rel_epsilon_sec ~ "zero",
              delay_sec > 0 ~ "c1_to_c2",
              delay_sec < 0 ~ "c2_to_c1"
            ),
            src = dplyr::case_when(
              delay_class == "c1_to_c2" ~ c1,
              delay_class == "c2_to_c1" ~ c2,
              TRUE ~ NA_integer_
            ),
            dst = dplyr::case_when(
              delay_class == "c1_to_c2" ~ c2,
              delay_class == "c2_to_c1" ~ c1,
              TRUE ~ NA_integer_
            ),
            delay_sec_abs = abs(delay_sec),
            weight_strength = ifelse(is.finite(p_adj) & p_adj > 0, -log10(p_adj), NA_real_),
            sig = is.finite(p_adj) & (p_adj <= rel_alpha)  # v1.7: <= catches boundary
          )
        
        if (rel_drop_zero_delays) dir_map <- dir_map %>% dplyr::filter(delay_class %in% c("c1_to_c2","c2_to_c1"))
        
        write_csv(dir_map %>% mutate(File = prefix, .before = 1),
                  file.path(dir_rel_csv, paste0(prefix, "_cfu_relation_edges.csv")))
        
        edges_sig <- dir_map %>% dplyr::filter(sig, !is.na(src), !is.na(dst), src != dst)
        # v1.7: two-tier edge selection — BH FDR first, fall back to raw p
        used_fallback <- FALSE
        if (nrow(edges_sig) == 0) {
          message("  ℹ️  No BH-significant edges for '", prefix,
                  "' — loosening to raw p ≤ ", rel_alpha, " for graph.")
          edges_sig     <- dir_map %>%
            dplyr::filter(is.finite(p) & p <= rel_alpha, !is.na(src), !is.na(dst), src != dst)
          used_fallback <- TRUE
        }
        # [v3.0] Final fallback: use ALL directed pairs so graph is never empty
        if (nrow(edges_sig) == 0) {
          message("  ℹ️  Still no edges after raw-p filter for '", prefix,
                  "' — plotting all directed pairs.")
          edges_sig    <- dir_map %>%
            dplyr::filter(!is.na(src), !is.na(dst), src != dst)
          used_fallback <- TRUE
        }
        if (nrow(edges_sig) > 0) {
          nodes <- data.frame(CFU_ID = sort(unique(c(edges_sig$src, edges_sig$dst))), stringsAsFactors = FALSE)
          g <- graph_from_data_frame(
            d = edges_sig %>% transmute(from = src, to = dst, weight_strength, delay_sec = delay_sec_abs),
            vertices = nodes %>% transmute(name = CFU_ID),
            directed = TRUE
          )
          out_deg <- degree(g, mode = "out"); in_deg <- degree(g, mode = "in")
          es <- igraph::as_data_frame(g, what = "edges")   # [v4.19] qualify: dplyr/tibble also export as_data_frame and mask igraph's after re-attach
          mean_out_delay <- tapply(es$delay_sec, es$from, function(x) ifelse(length(x)>0, mean(x, na.rm=TRUE), NA_real_))
          mean_in_delay  <- tapply(es$delay_sec, es$to,   function(x) ifelse(length(x)>0, mean(x, na.rm=TRUE), NA_real_))
          
          comm <- cluster_louvain(as.undirected(g)); comm_membership <- membership(comm)
          nodes_df <- data.frame(
            CFU_ID = as.integer(V(g)$name),
            out_degree_sig = out_deg[V(g)],
            in_degree_sig  = in_deg[V(g)],
            mean_out_delay_sec_sig = as.numeric(mean_out_delay[as.character(V(g)$name)]),
            mean_in_delay_sec_sig  = as.numeric(mean_in_delay[as.character(V(g)$name)]),
            community = as.integer(comm_membership[V(g)]),
            stringsAsFactors = FALSE
          )
          write_csv(nodes_df %>% mutate(File = prefix, .before = 1),
                    file.path(dir_rel_csv, paste0(prefix, "_cfu_relation_nodes.csv")))
          
          set.seed(42)
          lay <- layout_with_fr(g)
          plot_df_nodes <- cbind(nodes_df, as.data.frame(lay))
          names(plot_df_nodes)[(ncol(plot_df_nodes)-1):ncol(plot_df_nodes)] <- c("x","y")
          
          delay_trim <- quantile(es$delay_sec, probs = rel_trim_delay_q, na.rm = TRUE)
          es$delay_trimmed <- pmin(es$delay_sec, delay_trim)
          es$w <- scales::rescale(es$weight_strength, to = c(0.4, 2.5), from = range(es$weight_strength, na.rm = TRUE))
          es$w[!is.finite(es$w)] <- 0.8
          
          edge_plot_df <- es %>%
            mutate(x = plot_df_nodes$x[match(from, plot_df_nodes$CFU_ID)],
                   y = plot_df_nodes$y[match(from, plot_df_nodes$CFU_ID)],
                   xend = plot_df_nodes$x[match(to,  plot_df_nodes$CFU_ID)],
                   yend = plot_df_nodes$y[match(to,  plot_df_nodes$CFU_ID)],
                   delay_col = delay_trimmed,
                   w = w)
          
          plot_df_nodes$size <- scales::rescale(plot_df_nodes$out_degree_sig, to = c(3,10),
                                                from = range(plot_df_nodes$out_degree_sig, na.rm = TRUE))
          plot_df_nodes$size[!is.finite(plot_df_nodes$size)] <- 3
          
          p_g <- ggplot() +
            geom_segment(
              data = edge_plot_df,
              aes(x = x, y = y, xend = xend, yend = yend, color = delay_col),
              linewidth = edge_plot_df$w,
              alpha = 0.7,
              lineend = "round",
              arrow = arrow(length = unit(0.18, "cm"), type = "closed")
            ) +
            geom_point(
              data = plot_df_nodes,
              aes(x = x, y = y, size = size, fill = factor(community)),
              shape = 21,
              color = "black",
              stroke = 0.3,
              alpha = 0.95
            ) +
            scale_size_identity() +
            scale_fill_brewer(palette = "Set2", name = "Community") +
            scale_color_viridis_c(
              option = "magma",
              name = "Delay (s)",
              guide = guide_colorbar(barheight = unit(4, "cm"))
            ) +
            theme_void(base_family = "Arial") +
            theme(
              legend.position = "right",
              plot.title = element_text(family = "Arial", face = "plain", color = "black", hjust = 0)
            ) +
            labs(title = if (used_fallback)
                   paste0("CFU Directed Interaction Network (raw p≤", rel_alpha,
                          ", no BH-sig) – ", prefix)
                 else
                   paste0("CFU Directed Interaction Network (FDR<", rel_alpha, ") – ", prefix))
          
          hubs <- plot_df_nodes %>% arrange(desc(out_degree_sig)) %>% head(rel_max_label_nodes)
          if (nrow(hubs) > 0) {
            p_g <- p_g + ggrepel::geom_text_repel(
              data = hubs,
              aes(x = x, y = y, label = CFU_ID),
              size = 3.2, family = "Arial", color = "black",
              max.overlaps = Inf, box.padding = 0.3, point.padding = 0.3, min.segment.length = 0
            )
          }
          .safe_ggsave(file.path(dir_rel_graphs, paste0(prefix, "_CFU_Graph_Significant.png")),
                       plot = p_g, tag = paste0("RelationshipGraph/", prefix),
                       width = 9, height = 7, dpi = png_dpi)
          message("  ✔️  Relationship graph saved for '", prefix, "'",
                  if (used_fallback) " [raw-p fallback]" else " [BH FDR]", ".")
        } else {
          message("  ℹ️  No directed edges passed any threshold for '", prefix,
                  "' (BH FDR≤", rel_alpha, " and raw p≤", rel_alpha, "). Skipping graph.")  # v1.7
        }
      } else {
        if (length(unlist(rel)) > 0)  # non-empty but wrong shape = genuinely malformed
          message("  ⚠️  cfuRelation present but wrong shape (",
                  nrow(rel_mat), "r × ", ncol(rel_mat), "c) in '", prefix,
                  "' — needs ≥4 columns. Skipping relationship graph.")
        # else: field exists but is empty/null-padded → silently skip
      }
    } else {
      message("  ℹ️  No cfuGroupInfo in ‘", prefix, "’ or group info is empty – skipping group outputs.")
    }
  }
  }, error = function(e) {
    # [v4.7] Catch any uncaught error from the per-file vis body so the batch
    # continues with the next file.  ggsave errors are already handled by
    # .safe_ggsave; this is the catch-all for non-ggsave failures.
    msg <- conditionMessage(e)
    message(sprintf("[v4.7] vis-loop FAILED for %s: %s",
                    basename(mat_path), msg))
    # [v4.8] Record uncaught-error status in the accumulator.
    .GlobalEnv$.v48_vis_files[[.v48_vis_idx]]$status      <- "error"
    .GlobalEnv$.v48_vis_files[[.v48_vis_idx]]$err_message <- msg
  })
  # [v4.8] If we got here without an uncaught error, mark the file ok and
  # count the ggsave failures recorded during this iteration.
  if (identical(.v48_vis_files[[.v48_vis_idx]]$status, "started")) {
    .v48_vis_files[[.v48_vis_idx]]$status <- "ok"
  }
  .v48_vis_files[[.v48_vis_idx]]$ggsave_failures <-
    length(.v48_ggsave_failures) - .v48_vis_fail_n0
  # [v4.11] Maybe gc() after this file's vis pass.  ggplot2 grobs and
  # rasterized panels are the biggest transient memory consumers; gc
  # here keeps the working set bounded over long runs.
  .v411_maybe_gc("vis file")
} # end per-file visualization loop

# ---------------- Write consolidated manual annotations (once after all files) ----------------
write_consolidated_manual_csv()

# --------------------------------------- WRITE CONSOLIDATED GROUP CSVs ---------------------------------------
if (length(all_grp_rows) > 0) {
  grp_rows_fixed <- lapply(all_grp_rows, function(df) {
    for (nm in c("members_json","rel_delays_frames_json","rel_delays_sec_json","member_p_json")) {
      if (nm %in% names(df)) df[[nm]] <- as.character(df[[nm]])
    }
    df
  })
  grp_df_all <- dplyr::bind_rows(grp_rows_fixed)
  parts <- strsplit(grp_df_all$File, "_"); max_terms <- max(lengths(parts))
  padded <- lapply(parts, function(x){ length(x) <- max_terms; x })
  ids_mat <- do.call(rbind, padded); colnames(ids_mat) <- paste0("ID", seq_len(max_terms))
  grp_df_all <- cbind(as.data.frame(ids_mat, stringsAsFactors = FALSE), grp_df_all)
  write_csv(grp_df_all, file.path(dir_grp_csv, "cfu_groups_membership.csv"))
  message("✔️  Wrote consolidated membership CSV: ", file.path(dir_grp_csv, "cfu_groups_membership.csv"))
} else {
  message("ℹ️  No group membership rows collected.")
}

if (isTRUE(grp_burst_enable) && length(all_burst_rows) > 0) {
  bursts_rows_fixed <- lapply(all_burst_rows, function(df) {
    for (nm in c("members_json","burst_times_sec_json","params_json")) {
      if (nm %in% names(df)) df[[nm]] <- as.character(df[[nm]])
    }
    df
  })
  bursts_df_all <- dplyr::bind_rows(bursts_rows_fixed)
  parts_b <- strsplit(bursts_df_all$File, "_"); max_terms_b <- max(lengths(parts_b))
  padded_b <- lapply(parts_b, function(x){ length(x) <- max_terms_b; x })
  ids_mat_b <- do.call(rbind, padded_b); colnames(ids_mat_b) <- paste0("ID", seq_len(max_terms_b))
  bursts_df_all <- cbind(as.data.frame(ids_mat_b, stringsAsFactors = FALSE), bursts_df_all)
  write_csv(bursts_df_all, file.path(dir_grp_csv, "group_event_bursts.csv"))
  message("✔️  Wrote consolidated bursts CSV: ", file.path(dir_grp_csv, "group_event_bursts.csv"))
} else if (isTRUE(grp_burst_enable)) {
  message("ℹ️  No group burst rows collected.")
}

# --------------------------------------- FINAL SUMMARY ---------------------------------------
# §25 -- Run-completion banner and diagnostic write.  Prints a list of
# the output trees produced under out_dir, then calls
# .v48_write_diagnostics_summary() to:
#   - Compose the structured run summary (versions, IO paths, per-file
#     statuses for Part A and the vis loop, modeling class counts,
#     muffled warning counts, v4.11 scaling-knob values).
#   - Write diagnostics_<SCRIPT_VERSION>_<ts>.json (canonical triage
#     artifact for a long run).
#   - Replace the message/warning handlers with no-ops so they don't
#     fire on subsequent interactive prompts in the same R session.
#   - Close the diagnostic log connection.
# --------------------------------------- FINAL SUMMARY ---------------------------------------
message("\n= Analysis ‘", AnalysisName, "’ complete =")
message("Outputs organized under RESULTS/:")
message("  - ", out_csv, "  (combined per-cell summary)")
message("  - ", dir_dff0_root, "        (ALL dF/F0 outputs)")
message("  - ", dir_nond_root, "     (ALL non-dF/F0 outputs)")
message("  - ", dir_spatial_root,      " (CFU spatial maps; full FOV)")
message("  - ", dir_raster_root,       " (CFU event-sequence rasters; seconds on x-axis)")
message("  - ", dir_rel_root,          " (CFU relationships: CSVs + directed graphs)")
message("  - ", file.path(dir_grp_csv, "cfu_groups_membership.csv"))
message("  - ", file.path(dir_grp_csv, "group_event_bursts.csv"))
message("  - ", file.path(dir_grp_csv, "group_event_bursts_manual.csv"))

# [v4.8] Write the diagnostic JSON summary and flush the log on clean exit.
# .Last would also handle this on session end, but writing explicitly here
# ensures the file is present immediately after a successful run.
.v48_write_diagnostics_summary()

# launch_manual_group_event_annotator()
