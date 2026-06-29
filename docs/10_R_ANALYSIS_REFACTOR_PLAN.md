# 10 — R Analysis Refactor Plan (design, not yet executed)

Status: **proposal**. This document describes a planned refactor of the
downstream R analysis. No R code has been changed yet. It exists so the work can
be scoped, reviewed, and executed deliberately — the R analysis produces the
lab's published numbers, so changes must be behavior-preserving and verified.

Companion: [`05_DOWNSTREAM_R_ANALYSIS.md`](05_DOWNSTREAM_R_ANALYSIS.md) (how the
current scripts work), [`r/README.md`](../r/README.md).

---

## 1. The problem

There are three ~6,300-line R scripts that are **~99% identical**:

| Script | Lines | Dataset |
|---|---|---|
| `r/AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R` | 6,318 | FOXP1 WT/HET (canonical) |
| `docs/case-studies/03_foxp1_wt_het/scripts/AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R` | 6,318 | byte-identical copy of canonical |
| `docs/case-studies/02_assembloids_20x/scripts/AQuA2_CFU_pipeline_v4.26_Assembloids_20x.R` | 6,200 | assembloids 20x |

What actually differs between versions is small and localized:

- `parse_stem()` — the filename→metadata regex (FOXP1 vs assembloid vs hCO)
- Scope filters — `INCLUDE_DONORS`, `INCLUDE_CONDITIONS`, `INCLUDE_TIMEPOINTS`
- `GROUPING_VARS`, `META_COLS`, `AnalysisName`
- I/O paths (`csv_dir`, `mat_dir`, `companion_mat_dir`, `out_dir`)
- PRISM export cohort mapping (`c("WT"="WT","HET"="HET")` vs `c("C"=...,"G"=...,"L"=...)`)

Everything else — HDF5/`rhdf5` readers, per-cell and per-event aggregation,
plotting, Kruskal–Wallis / Dunn / Wilcoxon stats, organoid-level aggregation,
random-forest importance, checkpoint/resume, sharding, the diagnostics/JSON
apparatus — is shared.

### Why this hurts

1. **Every bug fix must be applied three times.** Past examples that had to be
   hand-propagated: the igraph namespace qualification (v4.19), the HDF5
   reference-dereference fixes (v4.1–v4.4), the O(1) companion-`.mat` index.
2. **Silent scope-filter failure.** If someone adapts a script to a new dataset
   and forgets to update `INCLUDE_*`, the filters drop *every* file and the run
   produces an empty output with **no error** — the `pairing_and_parse_audit.csv`
   simply has 0 rows. The v4.25 notes flag this as a real near-miss.
3. **Hardcoded absolute paths** (`C:/Users/Administrator/Desktop/...`) mean
   adapting to a new dataset requires editing the script body, which is exactly
   what invites (1) and (2).
4. **Temporal-calibration hazard.** `frame_interval` (e.g. 0.645 s for 1.55 Hz)
   is set in the script body; every temporal metric depends on it, and it has
   silently been left at a previous dataset's value before. There is no check
   that it matches the data.

---

## 2. Target architecture

One analysis engine + one small config per dataset.

```
r/
  run_analysis.R              # thin entry point: reads a config, calls the engine
  config/
    foxp1_wt_het.yml          # ~30 lines: paths, filters, grouping, parser id, frame_interval
    assembloids_20x.yml
    hco.yml
  R/                          # the engine, split into modules
    io_hdf5.R                 # rhdf5 readers (cfuInfo, fts, cfuRelation) + numeric coercion
    parse_stem.R             # PARSER_REGISTRY: named list of dataset filename parsers
    aggregate.R              # per-cell + per-event + organoid-level summaries
    stats.R                  # KW/Dunn/Wilcoxon/effect sizes/adjustments
    plots.R                  # theme_aqua2(), palette_aqua2(), shared ggplot builders
    prism.R                  # PRISM wide-format export, cohort mapping from config
    validate.R               # pre-flight checks (see §3)
    diagnostics.R            # JSON + log apparatus, warning muffler
```

A config is data, not code:

```yaml
analysis_name: FOXP1_WT_HET
parser: foxp1                 # key into PARSER_REGISTRY
frame_interval_sec: 0.645     # 1.55 Hz — MUST match acquisition
paths:
  csv_dir:           "C:/.../CarolDataPOGZ_lanes/"
  mat_dir:           "C:/.../CarolDataPOGZ_lanes/_CFU_POST/"
  companion_mat_dir: "C:/.../CarolDataPOGZ_lanes/"
  out_dir:           "C:/.../RESULTS_FOXP1/"
include:
  conditions: ["WT", "HET"]
  donors:     null
  timepoints: null
grouping_vars: ["Condition"]
prism_cohorts: { WT: WT, HET: HET }
```

Running becomes: `Rscript run_analysis.R config/foxp1_wt_het.yml`
(sharding stays available: `Rscript run_analysis.R config/foxp1_wt_het.yml --shard-stage process --count 8 --index 1`).

---

## 3. Pre-flight validation (the highest-value single addition)

Before the Part A loop, `validate.R` parses a sample of input filenames and
prints an audit table, then **fails fast** on the silent-drop hazards:

- **Filter sanity:** every non-null `include.*` value must appear in the parsed
  data. If `include.conditions = ["WT","HET"]` but parsed conditions are all `NA`,
  abort with: *"Filter conditions=[WT,HET] matches 0 of N files; parsed
  conditions were [NA,NA,...]. Did you set the wrong parser/filter for this
  dataset?"*
- **frame_interval sanity:** cross-check the config value against the Hz token
  parsed from filenames (and/or the dF/F trace length). Warn loudly on a
  mismatch — this is the single most common, most damaging R-side error.
- **Pairing sanity:** expected vs found `.mat`/companion pairs; abort if 0.

This alone removes the two worst real-world failure modes regardless of how far
the rest of the refactor gets.

---

## 4. Phased migration (each phase shippable and verifiable)

1. **Extract the parser registry + config loader, no other changes.** Move the
   three `parse_stem` variants into `PARSER_REGISTRY` and lift paths/filters into
   a config. The engine stays one file. Lowest risk; immediately kills the
   path-editing-per-dataset problem.
2. **Add `validate.R` pre-flight.** Pure addition; no change to results.
3. **Extract `io_hdf5.R`, `stats.R`, `plots.R`, `prism.R`.** Mechanical moves;
   verify byte-identical outputs (see §5) after each extraction.
4. **Collapse the three scripts to one engine + three configs.** Delete the
   case-study script copies; the case-study READMEs point to the config that
   reproduced them. Keep the old scripts in git history (and tag the last
   pre-refactor commit) for provenance.
5. **(Optional) Package as `aqua2.pipeline`** with `testthat` unit tests for the
   readers and parsers.

Stop after any phase and still have a net improvement.

## 5. Acceptance / verification

The refactor must be **numerically behavior-preserving**:

- Pick the FOXP1 dataset as the golden reference. Run the current canonical
  script; archive every output CSV (`per_cell_summary`, `per_cell_per_event`,
  organoid stats, PRISM exports) and a hash of each.
- After each phase, run the refactored engine with `config/foxp1_wt_het.yml` and
  diff outputs. Numeric columns must match to floating-point tolerance; row
  counts and group assignments must match exactly.
- Plots: spot-check a sample rather than pixel-diff (ggplot output is not
  byte-stable); confirm counts and facet structure match.
- Only when FOXP1 reproduces exactly, repeat for assembloids 20x.

## 6. Explicitly out of scope (for this refactor)

- Changing any statistical method, threshold, or default (pure restructuring).
- Re-opening the pseudoreplication question — v4.27 already added organoid-level
  aggregation; document which output is inferential vs descriptive, but don't
  change the science here.
- Parallelizing `rhdf5` reads (not thread-safe); the existing shard model stays.

## 7. Effort estimate

Phases 1–2: ~half a day, high value, low risk. Phases 3–4: ~1–2 days with the
verification harness. Phase 5: optional, ~1 day. The verification harness (§5) is
the gating prerequisite — build it first.
