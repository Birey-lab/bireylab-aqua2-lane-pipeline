# 05 — Downstream R Analysis

How to read the pipeline's outputs in R, and conventions that make analysis scripts maintainable. This document focuses on **integration** (what files exist, how to read them) and **patterns** that have proven helpful across multiple datasets, rather than prescribing a specific analysis.

You write the actual analysis script. This document tells you what to read, how to read it, and what gotchas to know about.

---

## A. What you have to work with

After the pipeline runs, two folders contain the outputs:

```
PreCFU_<dataset>/                                ← detection results
├── <stem1>_results/
│   ├── <stem1>_AQuA2.mat              ← v7.3 .mat: detection + CFU baked in
│   ├── <stem1>_AQuA2_Ch1.csv          ← per-event feature table
│   ├── <stem1>_AQuA2_curves.xlsx      ← fluorescence traces (Excel)
│   └── <stem1>_Movie.tif              ← playback render (optional, large)
├── <stem2>_results/
│   └── ...
└── (N folders)

<dataset>_POST/                                  ← CFU standalones (flat)
├── <stem1>_AQuA2_res_cfu.mat          ← v7.3 .mat: CFU output only
├── <stem2>_AQuA2_res_cfu.mat
└── (N files)
```

**Pairing PRE and POST:** by filename stem. For a POST file `<stem>_AQuA2_res_cfu.mat`, the matching PRE folder is `PreCFU_<dataset>/<stem>_results/`. Strip `_AQuA2_res_cfu.mat` to get the stem, then locate the corresponding folder.

---

## B. What's in the `.mat` files

### B.1 — `<stem>_AQuA2.mat` (the detection file)

This is the "everything" file. After CFU has run, it contains:

| Variable | Type | What it is |
|---|---|---|
| `res` | struct | AQuA2's main result container |
| `evtMap` | 3D array | Per-pixel event indices over time |
| `fts1` | nested struct | Per-event features (channel 1) — **event timing lives here** |
| `dffMat` | 3D array | dF/F0 values per frame (large!) |
| `opts` | struct | Parameters used for this run |
| `cfuInfo1` | cell array | Channel 1 CFU info (added by `cfu_lane.exe`) |
| `cfuInfo2` | cell array | Channel 2 CFU info |
| `cfuRelation` | matrix | Pairwise CFU relationships |
| `cfuGroupInfo` | cell array | CFU group/cluster assignments |

The fields you'll most often need:
- `fts1.curve.tBegin`, `fts1.curve.tEnd`, `fts1.curve.dffMaxFrame` — event timing in frames
- `cfuInfo1` — list of CFUs with their event memberships
- `opts.frameRate`, `opts.spatialRes` — for converting frames-to-seconds and pixels-to-microns

### B.2 — `<stem>_AQuA2_res_cfu.mat` (the CFU standalone)

A smaller file containing just CFU output:

| Variable | Type | What it is |
|---|---|---|
| `cfuInfo1` | cell array | Same as in the detection file |
| `cfuInfo2` | cell array | |
| `cfuRelation` | matrix | |
| `cfuGroupInfo` | cell array | |
| `cfuOpts` | struct | CFU clustering parameters |
| `datPro` | various | Processing metadata |

**Important:** `_res_cfu.mat` does **NOT** contain `fts` — for event timing you must reach into the matching `_AQuA2.mat`. This is why most R scripts need both directories.

### B.3 — `<stem>_AQuA2_Ch1.csv` (the event feature table)

A flat CSV with one row per detected event and columns for AQuA2's per-event features (area, peak dF/F, duration, etc.). Easy to read with `readr::read_csv()` — no HDF5 backend needed.

This is your fastest path to per-event data. If your analysis only needs event-level features and not CFU info, you may not need to touch the `.mat` files at all.

---

## C. Reading `.mat` files in R (the HDF5 backend)

### C.1 — Use `rhdf5`, NOT `hdf5r`

The `.mat` files are MATLAB v7.3 format — which is HDF5 underneath. **The R package `hdf5r` is unreliable for files written by MATLAB v7.3:** specifically, `H5R` reference dereferencing has bugs that cause empty reads, NULL returns, and crashes on cell arrays.

**Use `rhdf5` from Bioconductor instead.** Install:
```r
if (!require("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("rhdf5")
```

Reading basic numeric fields:
```r
library(rhdf5)
h <- H5Fopen("path/to/file_AQuA2.mat")
nev <- h5read(h, "/fts1/basic/area")
H5Fclose(h)
```

Note the leading `/` and the nested-struct path syntax.

### C.2 — Cell arrays need extra care

MATLAB cell arrays are stored as HDF5 object references that point to the actual data. Dereferencing them requires:
```r
ref_dataset <- h5read(h, "/cfuInfo1")  # vector of references
# For each ref, follow it to get the underlying data
H5Rdereference(ref, h5loc)
```

A real-world helper function that handles this:

```r
read_cfu_info <- function(matfile) {
  h <- H5Fopen(matfile)
  on.exit(H5Fclose(h), add = TRUE)

  refs <- h5read(h, "/cfuInfo1")
  cfus <- vector("list", length(refs))
  for (i in seq_along(refs)) {
    cfu_data <- H5Rdereference(refs[[i]], h)
    cfus[[i]] <- cfu_data  # process per your schema
  }
  cfus
}
```

### C.3 — Cell-array orientation: a real gotcha

When you read a MATLAB cell array via rhdf5, orientation can be ambiguous: a 1×N cell of scalar values can look structurally similar to a single scalar wrapped in a reference. You can't tell from the HDF5 metadata alone.

**The fix:** use a known-structure check. For `cfuInfo1`, the IDs are always consecutive integers 1..N (this is how AQuA2 creates them). So:

```r
# real cfuInfo1: ref[i].id == i for all i
# coincidental scalar lookalike: won't satisfy this
is_real_cell_array <- all(sapply(seq_along(parsed), function(i) {
  parsed[[i]]$id == i
}))
```

If you skip this check and pass a malformed cell array to downstream code, you get nonsense results that won't error obviously.

Also: **`cfuGroupInfo` must be read with the same cell-array machinery as `cfuInfo1`/`cfuInfo2`**. Treating it as a flat list of values gives wrong answers.

---

## D. Recommended R script architecture

Patterns that have served well across multiple datasets. Adopt or adapt as needed.

### D.1 — File header with version and changelog

```r
# AQuA2 CFU Analysis Pipeline
# Version: v1.0
# Dataset: <name>
# Author: <you>
# Date: <date>
#
# MASTER CHANGELOG
# ================
# v1.0  Initial version
# v1.1  Added per-organoid aggregation
# v1.2  ...
```

Every script delivery includes a version bump and a changelog entry. Helps anyone (including future-you) understand what changed and when.

### D.2 — Dual-path config blocks

Maintain both **local-test** (Mac/Linux laptop) and **production** (EC2 Windows) paths as commented alternatives at the top of the script. Switch by commenting/uncommenting:

```r
# ---- Paths ----
# csv_dir <- "/Volumes/External/CalciumTesting/PreCFU_<dataset>/"   # local test (Mac)
csv_dir <- "C:/Users/Administrator/Documents/PreCFU_<dataset>/"      # production (EC2)

# mat_dir <- "/Volumes/External/CalciumTesting/<dataset>_POST/"     # local test (Mac)
mat_dir <- "C:/Users/Administrator/Documents/<dataset>_POST/"        # production (EC2)

# fts_dir <- csv_dir   # fts1 lives in _AQuA2.mat files = same as csv_dir
companion_mat_dir <- csv_dir

# out_dir <- "/Volumes/External/CalciumTesting/RESULTS_<dataset>/"
out_dir <- "C:/Users/Administrator/Documents/RESULTS_<dataset>/"
```

Forward slashes work on Windows in R; no escaping needed.

### D.3 — Recursive CSV search

The `_AQuA2_Ch1.csv` files live nested inside `<stem>_results/` subfolders. Read them recursively:

```r
csv_files <- list.files(csv_dir,
                         pattern = "_AQuA2_Ch1\\.csv$",
                         recursive = TRUE,
                         full.names = TRUE)
```

If you do a non-recursive `list.files()`, you'll find zero files and get confused.

### D.4 — Parsing the filename stem for grouping variables

Filenames typically encode metadata. Parse with regex; document the convention:

```r
# Expected filename: <donor><condition>_d<age>_<mag>x_<rateHz>_<tissue>_<promoter>_ORG<n>_V<m>_<measuredHz>.tif
parse_stem <- function(stem) {
  m <- regmatches(stem, regexec(
    "^(\\d+)([A-Z])_d(\\d+)_(\\d+)x_(\\d+)Hz_([A-Za-z]+)(?:_([A-Za-z]+))?_ORG(\\d+)_V(\\d+)_([\\d.]+)Hz",
    stem
  ))
  if (length(m[[1]]) == 0) return(NULL)
  list(
    donor      = m[[1]][2],
    condition  = m[[1]][3],
    age_days   = as.integer(m[[1]][4]),
    magnif     = paste0(m[[1]][5], "x"),
    nominal_hz = as.integer(m[[1]][6]),
    tissue     = m[[1]][7],
    promoter   = m[[1]][8],  # may be NA if absent
    organoid   = as.integer(m[[1]][9]),
    video      = as.integer(m[[1]][10]),
    measured_hz = as.numeric(m[[1]][11])
  )
}
```

**Important on Hz tokens:** filenames may include a *nominal* acquisition rate mid-name (e.g., `20Hz`) and an *actual measured* rate end-anchored (e.g., `19.23Hz`). For computing event timing in seconds, use the **measured** rate, not the nominal. The pipeline's CSV uses a single `frameRate` parameter — typically the nominal one for cross-dataset consistency, with the option of swapping to measured rates if exact temporal accuracy matters more than consistency.

### D.5 — FAST_MODE pattern for development

When iterating, you often want to skip slow steps (full-resolution plots, modeling, manual annotation). A simple toggle pattern:

```r
FAST_MODE <- TRUE  # set FALSE for full run

# control which sections actually iterate
include_donors      <- if (FAST_MODE) c("1") else c("1", "2", "4")
include_conditions  <- if (FAST_MODE) c("C") else c("C", "G", "L")
include_timepoints  <- if (FAST_MODE) c(122) else c(80, 100, 122, 126, 150)

# Then downstream sections iterate over those vectors:
for (donor in include_donors) {
  for (condition in include_conditions) {
    # ...
  }
}
```

The pattern is: **skip by emptying or shortening iteration vectors**, not by wrapping each section in `if (!FAST_MODE)` conditionals. The empty-vector approach is more robust because the iteration just becomes a no-op naturally.

### D.6 — Output organization

Direct everything to `out_dir`. Subdivide by analysis type:

```
RESULTS_<dataset>/
├── PartA_QC/                    ← quality control plots, exclusion lists
├── PartB_Descriptive/           ← summary statistics, per-condition tables
├── PartC_Manual/                ← optional: manually-curated annotations
├── PartD_Stats/                 ← significance tests, effect sizes
├── PartE_Plots/                 ← publication-ready figures
├── Prism_Exports/               ← wide-format CSVs for GraphPad Prism
└── run_log.txt                  ← analysis run timestamps + parameters
```

`PartC_Manual/` is optional and traditionally implemented as commented-out functions at the bottom of the script (e.g., `launch_manual_group_event_annotator()`). Manual annotations should never overwrite Parts A/B outputs.

### D.7 — Prism / GraphPad export

For lab members who use GraphPad Prism, write wide-format CSVs where each column is a condition and rows are recordings/organoids:

```r
# example: nCFU per recording, wide-format for Prism
library(tidyr)
wide_df <- summary_df %>%
  select(condition, organoid_id, nCFU) %>%
  pivot_wider(names_from = condition, values_from = nCFU)

write.csv(wide_df,
          file.path(out_dir, "Prism_Exports", "nCFU_by_condition_wide.csv"),
          row.names = FALSE,
          na = "")
```

Prism reads wide-format CSVs natively.

---

## E. Reading sketch (minimum viable per-event read)

If you just want to start exploring, here's the minimum:

```r
library(rhdf5)
library(readr)
library(dplyr)

csv_dir <- "C:/Users/Administrator/Documents/PreCFU_<dataset>/"

# read all event CSVs into one data frame
csv_files <- list.files(csv_dir, pattern = "_AQuA2_Ch1\\.csv$",
                        recursive = TRUE, full.names = TRUE)

events <- bind_rows(lapply(csv_files, function(f) {
  df <- read_csv(f, show_col_types = FALSE)
  stem <- sub("_AQuA2_Ch1\\.csv$", "", basename(f))
  df$recording_stem <- stem
  df
}))

# now `events` has all events from all recordings, with `recording_stem` to group by
nrow(events)
length(unique(events$recording_stem))
```

This works without touching the `.mat` files at all — useful for first-pass exploration of event-level features. For CFU info, you'll need to go to the `_res_cfu.mat` files via `rhdf5`.

---

## F. Helpful R packages

| Package | Use |
|---|---|
| `rhdf5` (Bioconductor) | Reading v7.3 `.mat` files |
| `readr` | Fast CSV reading |
| `dplyr` / `tidyr` | Data manipulation, wide↔long |
| `ggplot2` | Plots |
| `purrr` | Functional iteration over file lists |
| `here` | Path management |
| `lme4` / `lmerTest` | Mixed-effects models for repeated measures |
| `emmeans` | Estimated marginal means + contrasts |
| `effectsize` | Standardized effect sizes |

---

## G. Common pitfalls in R analysis (specific to this pipeline)

1. **Using `hdf5r` instead of `rhdf5`** → empty reads, mysterious failures. Use `rhdf5`.
2. **Forgetting `recursive = TRUE` in `list.files()`** → zero files found because they're in subfolders.
3. **Treating `cfuGroupInfo` as flat** → wrong group counts. Must use cell-array reader.
4. **Mixing nominal and measured Hz** → off-by-a-few-percent in derived rates. Pick one explicitly.
5. **Loading every `.mat` at once with `lapply`** → memory blowup. Stream or chunk instead.
6. **Forgetting that some files have nCFU=0** → empty tables that break downstream summaries. Handle the zero case explicitly.

---

## Next steps

Once you have outputs in `RESULTS_<dataset>/`, back them up to S3:
```powershell
aws s3 sync C:\Users\Administrator\Documents\RESULTS_<dataset> "s3://<bucket>/CalciumImagingAnalysis/R_Analysis_Results/<DatasetName>/" --storage-class STANDARD
```

Then continue to [`07_TEARDOWN_CHECKLIST.md`](07_TEARDOWN_CHECKLIST.md) when you're ready to shut down the instance.
