# Case Study 1 — Human Cortical Organoid (hCO) Calcium Imaging

A worked example showing what a "large run" looked like in practice, with the real numbers, decisions, and a notable parameter-mixing problem that drove a full re-run. Use this for grounding the generic procedures in [`../03_SIZING_AND_RESIZING_GUIDE.md`](../03_SIZING_AND_RESIZING_GUIDE.md) and [`../04_PIPELINE_OPERATIONS.md`](../04_PIPELINE_OPERATIONS.md).

**Run date:** 2026  |  **Lab:** Birey Lab, Emory  |  **Pipeline version:** v1 (raw .m workers, pre-compilation) → v2 (compiled exes)

---

## A. The dataset

| Property | Value |
|---|---|
| **N recordings (processed)** | 1191 |
| **Donors** | Donors 1 and 4 only (donors 2 and 3 excluded for separate reasons unrelated to pipeline) |
| **Conditions** | C (control), G (gain-of-function), L (loss-of-function) |
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

### C.2 — The v2 re-run at uniform maxSize=50000

After discussion, we re-ran the entire dataset at uniform `maxSize=50000`:
- High enough that most files don't hit the cap (so event sizes are reasonably preserved)
- Low enough to force convergence on the hyperactive files
- The compromise value that became the **standard for all subsequent datasets** in the lab for cross-dataset comparability

Outcome: all 1191 files processed successfully at uniform maxSize=50000. **This is the analysis set of record.**

### C.3 — What we did with v1

We didn't delete v1 — kept it as a frozen fallback in case the v1 vs v2 comparison ever became scientifically interesting. Moved v1 to **S3 Deep Archive**:
- Storage cost: ~$3/month for 3.8 TB (vs $70-100/month at Standard)
- 12h retrieval time if ever needed
- Tagged with a README explicitly documenting the mixed-parameter status and recovery instructions

This "keep but archive" pattern has been useful — Deep Archive is cheap enough that frozen fallbacks aren't a meaningful cost burden.

### C.4 — Lessons

- **Pick a uniform maxSize before the first run.** 50000 is now the standard.
- **If a file hangs, isolate-and-exclude rather than re-running at different parameters.** Mixed parameters within a dataset is a hidden landmine.
- **Document parameter choices in a README that travels with the data.** Future-you doesn't remember what was different about which file.
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
│   ├── hCO_Donors1and4_MaxSize50000/         ← v2 detection, Standard (7,147 obj / 3.67 TB)
│   ├── hCO_Donors1and4_MaxSize50000_CFU/     ← v2 CFU, Standard (1,191 obj / 30.5 GB)
│   └── Archive/
│       └── hCO_Donors1and4_MaxSize_MIXED_2000andINF/   ← v1 fallback, Deep Archive
└── R_Analysis_Results/
    └── hCO_Donors1and4_MaxSize50000/         ← R outputs
```

Each S3 prefix has a README explaining parameters and any caveats.

---

## F. Lessons specific to this run

1. **The 32xlarge was overkill.** Subsequent assembloid runs used r7a.24xlarge with no issues. Always probe first.

2. **Movies are on by default and account for ~70% of detection output size.** If downstream analysis doesn't need movies, recompile `aqua_lane.m` with `movie=OFF` to save ~2.5 TB of storage per dataset of this size.

3. **The "instant return" AWS sync issue.** The first attempt to sync the v2 detection set to S3 returned in seconds with only the README uploaded — none of the 3.4 TB actually transferred. We verified by count, re-ran the sync, and the second attempt actually transferred everything. **Always verify by `aws s3 ls --summarize` after a sync.**

4. **74 files with zero CFUs is normal** for this preparation type. Not all recordings are productive; quiet recordings produce no CFUs at the minimum-event thresholds. Downstream R analysis should handle the zero case explicitly (some files will have empty CFU tables).

5. **v1 → v2 disk pressure.** Running v2 while v1 was still on disk meant we briefly held ~7 TB of detection output simultaneously. EBS had room (12 TB) but it was a closer call than we'd planned for. Either size EBS generously, or delete the previous parameter run from local disk before starting the new one.
