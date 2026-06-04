# R analysis scripts

The canonical R analysis script for downstream statistics on AQuA2 + CFU outputs.

| Script | Notes |
|---|---|
| `AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R` | Latest version (May 31, 2026). 331 KB. Adapted for the FOXP1 WT/HET dataset (see case study 3) but the upstream architecture works for any dataset with appropriate scope-filter adjustments. |

## Version history

Earlier versions of this script (v4.0 through v4.26) are archived in S3 at `s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/ARCHIVE/_PipelineArtifacts/2026-06-03/instance-scripts/R/`. The chronological evolution:

| Version | Dataset | Key change |
|---|---|---|
| v4.0 | (developing) | Starting point, forked from earlier LindaDGvsCA work |
| v4.11.1 | hCO | Hardening, audit framework |
| v4.17 | hCO | Stable hCO version |
| v4.25 | Assembloids 20x | Repointed paths, FAST_MODE + TEST_MODE pattern |
| v4.26 | Assembloids 20x | Promoter awareness (CAMK2A / DLX) |
| v4.27 | FOXP1 WT/HET | Genotype-aware parsing, organoid-level aggregation, Wilcoxon+Cohen's d+BH |

The dataset-specialized versions (`v4.26_Assembloids_20x.R`, `v4_27_FOXP1_WT_HET.R`) also live in each case study's `scripts/` folder alongside their narrative `README.md`.

## Architecture (general)

The script follows a documented architecture pattern shared across versions — see [`../docs/05_DOWNSTREAM_R_ANALYSIS.md`](../docs/05_DOWNSTREAM_R_ANALYSIS.md) for the conceptual overview. Key invariants:

- **Dual-path config** at the top (Mac local + EC2 Windows paths, switched by comment toggle)
- **Scope filters** (`INCLUDE_DONORS`, `INCLUDE_CONDITIONS`, `INCLUDE_TIMEPOINTS`, `INCLUDE_PROMOTERS`) — set to `NULL` for "no filter"
- **`FAST_MODE` / `TEST_MODE`** toggles for development iteration
- **MASTER CHANGELOG** comment block at the top of every version documenting what changed
- **`rhdf5` (Bioconductor)**, not `hdf5r`, for reading MATLAB v7.3 `.mat` files (see Pitfall 5)
- **Part A / B / C / D / E** structure: QC → Descriptive → (optional manual) → Stats → Plots

## Running

The script is intentionally a single-file long-form analysis. To run:

```r
# In RStudio, open the file and source() it, OR from command line:
Rscript AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R
```

The script writes outputs to whatever `out_dir` is set to (typically `C:\Users\Administrator\Documents\RESULTS_<dataset>\` on EC2 or `/Volumes/External/CalciumTesting/RESULTS_<dataset>/` on a Mac for local testing).

## Adapting for a new dataset

Open the script and update:
1. **Paths** at the top (`csv_dir`, `mat_dir`, `companion_mat_dir`, `out_dir`)
2. **`parse_stem`** — the filename-parsing regex needs to match your filename convention
3. **Scope filters** (`INCLUDE_*`) — set to match the groups you want, or `NULL` for all
4. **`GROUPING_VARS`** — the columns you want statistical comparisons across
5. **`META_COLS`** — the metadata columns that exist in your dataset (set unused ones to `NA`)
6. **`frame_interval`** — `1 / acquisition_Hz`. **Don't leave this at a previous dataset's value** (see the v4.27 changelog note on this exact hazard)
7. **MASTER CHANGELOG** — add a new top entry documenting your changes

Re-run; check the `pairing_and_parse_audit.csv` output first to confirm parsing is working before proceeding with the full analysis.
