# Case Study 1 — Human Cortical Organoid (hCO) Calcium Imaging

A worked example showing what a "large run" looked like in practice, with the real numbers, decisions, and a notable parameter-mixing problem that drove a full re-run. Use this for grounding the generic procedures in [`../03_SIZING_AND_RESIZING_GUIDE.md`](../03_SIZING_AND_RESIZING_GUIDE.md) and [`../04_PIPELINE_OPERATIONS.md`](../04_PIPELINE_OPERATIONS.md).

**Run date:** 2026  |  **Lab:** Birey Lab, Emory  |  **Pipeline version:** v1 (raw .m workers, pre-compilation) → v2 (compiled exes)

---

## A. The dataset

| Property | Value |
|---|---|
| **N recordings (processed)** | 1191 |
| **Donors** | Donors 1 and 4 only (donors 2 and 3 excluded for separate reasons unrelated to pipeline) |
| **Genetic line** | **CACNA1A** (the conditions are CACNA1A alleles) |
| **Conditions** | C (control), G (gain-of-function), L (loss-of-function) — CACNA1A alleles |
| **Per-condition counts** | 1C=162, 1G=126, 1L=148, 4C=290, 4G=217, 4L=248 |
| **Magnification** | 20x objective |
| **Acquisition rate** | 20 Hz nominal (frameRate=0.05); measured ~19.1-19.3 Hz |
| **Frames per recording** | ~1500 |
| **Spatial dimensions** | ~1024 × 1024 pixels |
| **Tissue** | Human cortical organoid (hCO), single-region |
| **Filename pattern** | `<donor><condition>_d<age>_20x_20Hz_hCO_ORG<n>_V<m>_<measuredHz>.tif` |
| **Example filename** | `4L_d128_20x_20Hz_hCO_ORG3_V1_19.23Hz.tif` |

The filename encodes: donor (1 or 4), condition (C/G/L), age in days, magnification, nominal Hz, tissue tag, organoid number, video number, measured Hz.

---

## B. Compute setup

**Instance type:** `r7a.32xlarge` for the original run (128 vCPU, 1024 GiB RAM). In retrospect, `r7a.24xlarge` (96 vCPU, 768 GiB) would have been sufficient and saved ~$2/hour. We used the 32xlarge because we hadn't measured per-lane RAM carefully before launching.

**EBS volume:** 12 TB gp3, 1000 MB/s throughput. Sized for two datasets back-to-back; if hCO alone, ~6 TB would have sufficed.

**Lanes:** 32 (one process per lane; ~37 files per lane average).

**Measured per-lane RAM during detection:** ~12 GB average, occasional spikes to ~20+ GB on hyperactive files. So the 768 GiB box would have been adequate: `12 × 32 × 1.3 + 16 = 515 GB`, within the r7a.16xlarge (512 GiB) ceiling tightly, comfortable on r7a.24xlarge (768 GiB).

---

## C. The maxSize parameter saga (the painful lesson)

This was the most consequential issue we hit, and the reason the dataset went through *two* full runs.

### C.1 — Original "v1" run with mixed parameters

The original detection run used `maxSize=inf` (AQuA2 default). On the first pass, 18 of the donor-4 recordings hung in spatial segmentation — hyperactive cells with too many large active regions to converge.

**The expedient fix at the time:** re-run those 18 files alone at `maxSize=2000`. They completed.

**The hidden problem:** the dataset now had **18 files processed at maxSize=2000 and 1173 files at maxSize=inf**, with no record of which was which. This mixed parameter set is a real confound — event sizes and CFU counts depend on `maxSize`, so cross-file comparisons become questionable.

The output was used briefly, but the lab realized the inconsistency was a problem for publication.

### C.2 — The v2 re-run at a uniform maxSize

After discussion, we re-ran the entire dataset at a uniform `maxSize` chosen to be appropriate for the dataset's activity profile. All 1191 files completed under that single uniform value. **This is the analysis set of record.**

The full parameter CSV for this run is archived in S3 at `_PipelineArtifacts/2026-06-03/config/parameters_for_batch_ProbablyCACNA1AhCO20xMay2026.csv`. The "Probably" in the filename reflects post-hoc archival uncertainty — the authoritative parameter values for this run live inside each `<stem>_AQuA2.mat` file's `opts` struct in S3, which AQuA2 writes at detection time. If exact reproducibility is needed, read `opts` from one of those files.

Confirmed parameters (consistent across archived hCO/Assembloid CSVs):

| Parameter | Value |
|---|---|
| `registrateCorrect` | 2 |
| `bleachCorrect` | 3 |
| `smoXY` | 0.5 |
| `thrARScl` | 2 |
| `minDur` | 3 |
| `minSize` | 20 |
| `sigThr` | 2.5 |
| `maxDelay` | 0.5 |
| `sourceSensitivity` | 9 |
| `detectGlo` | 1 |
| `gloDur` | 20 |
| `frameRate` | 0.05 (20 Hz) |
| `spatialRes` | 1.3 (20x) |
| **`maxSize`** | Uniform across the dataset; specific value see archived CSV and `opts` in the `.mat` files |

### C.3 — What we did with v1

We didn't delete v1 — kept it as a frozen fallback in case the v1 vs v2 comparison ever became scientifically interesting. Moved v1 to **S3 Deep Archive**:
- Storage cost: ~$3/month for 3.8 TB (vs $70-100/month at Standard)
- 12h retrieval time if ever needed
- Tagged with a README explicitly documenting the mixed-parameter status and recovery instructions

This "keep but archive" pattern has been useful — Deep Archive is cheap enough that frozen fallbacks aren't a meaningful cost burden.

### C.4 — Lessons

- **Pick a uniform maxSize before the first run** and document it in a per-dataset README that gets uploaded with the data. The CSV gets overwritten by the next run, so without an external record the choice gets lost (or at minimum, uncertain enough to require forensic recovery from `.mat` `opts` structs).
- **If a file hangs, isolate-and-exclude rather than re-running at different parameters.** Mixed parameters within a dataset is a hidden landmine. The v1 → v2 re-run for this dataset was driven by exactly that landmine — v1 had a few files re-processed at lower maxSize during recovery, creating implicit mixed parameters across the dataset that we later wanted to clean up.
- **Document parameter choices in a README that travels with the data.** This wasn't done thoroughly here; we had to recover the parameter CSV from a file named `parameters_for_batch_ProbablyCACNA1AhCO20xMay2026.csv` archived on the EC2 instance — the "Probably" prefix tells you how much uncertainty had already crept in by archive time.
- **The authoritative parameter record is the `opts` struct inside each `_AQuA2.mat` file.** AQuA2 writes the parameters used into the output. If you ever need to know what was actually used, read `opts` from a representative result file in S3. This is the only truly forensic source — CSV files can be overwritten, READMEs can be forgotten, but `opts` is baked into the output.
- **Deep Archive is cheap insurance** for old parameter runs you might want to revisit.

---

## D. The actual run results

After the v2 re-run:

| Metric | Value |
|---|---|
| Files processed | **1191 / 1191** |
| Files with errors | **0** |
| Total detection compute time | ~4 hours wall-clock on r7a.32xlarge with 32 lanes |
| Detection output size | ~3.67 TB (with movies on) |
| CFU clustering time | ~30 minutes on the same box |
| CFU output size | ~30.5 GB (small standalones) |
| Mean nCFU per recording | 21.6 |
| Max nCFU | 198 (one hyperactive recording) |
| Recordings with 0 CFUs | 74 (~6%) |

---

## E. Storage layout (final state)

```
s3://<bucket>/CalciumImagingAnalysis/
├── AQuA2_Outputs/
│   ├── hCO_Donors1and4/                     ← v2 detection, Standard (7,147 obj / 3.67 TB)
│   ├── hCO_Donors1and4_CFU/                 ← v2 CFU, Standard (1,191 obj / 30.5 GB)
│   └── Archive/
│       └── hCO_Donors1and4_MIXED_v1/        ← v1 fallback (mixed maxSize), Deep Archive
└── R_Analysis_Results/
    └── hCO_Donors1and4/                     ← R outputs
```

Each S3 prefix has a README explaining parameters and any caveats. **The exact parameter CSV for this run was recovered from a backup file on the EC2 instance** (`parameters_for_batch_ProbablyCACNA1AhCO20xMay2026.csv`, now archived in S3 at `_PipelineArtifacts/2026-06-03/config/`). The "Probably" prefix on the filename indicates we were uncertain at archival time — confirmed authoritative after recovery and cross-reference (June 2026).

---

## F. Lessons specific to this run

1. **The 32xlarge was overkill.** Subsequent assembloid runs used r7a.24xlarge with no issues. Always probe first.

2. **Movies are on by default and account for ~70% of detection output size.** If downstream analysis doesn't need movies, recompile `aqua_lane.m` with `movie=OFF` to save ~2.5 TB of storage per dataset of this size.

3. **The "instant return" AWS sync issue.** The first attempt to sync the v2 detection set to S3 returned in seconds with only the README uploaded — none of the 3.4 TB actually transferred. We verified by count, re-ran the sync, and the second attempt actually transferred everything. **Always verify by `aws s3 ls --summarize` after a sync.**

4. **74 files with zero CFUs is normal** for this preparation type. Not all recordings are productive; quiet recordings produce no CFUs at the minimum-event thresholds. Downstream R analysis should handle the zero case explicitly (some files will have empty CFU tables).

5. **v1 → v2 disk pressure.** Running v2 while v1 was still on disk meant we briefly held ~7 TB of detection output simultaneously. EBS had room (12 TB) but it was a closer call than we'd planned for. Either size EBS generously, or delete the previous parameter run from local disk before starting the new one.
