# Case Study 3 — FOXP1 WT/HET Organoid Calcium Imaging

A *smaller* dataset (33 recordings, vs. ~1000 in the other case studies) processed for a collaborator. Demonstrates that the pipeline works well at modest scale, and surfaces a different failure mode — array-index errors during global signal detection on specific files — that the prior cases hadn't shown. Useful contrast to Cases 1 and 2.

**Run date:** 2026  |  **Lab:** Birey Lab, Emory (collaboration)  |  **Pipeline version:** v2 (compiled exes)

---

## A. The dataset

| Property | Value |
|---|---|
| **N recordings (started)** | 33 |
| **N recordings (completed)** | **31** (2 failed — see Section C) |
| **Genotypes** | WT (wild-type), HET (FOXP1 heterozygous) |
| **Donors** | 3 |
| **Magnification** | 20x objective |
| **Acquisition rate** | 1.55 Hz nominal (CSV `frameRate=0.64` — close enough to 1/1.55=0.6452) |
| **Spatial dimensions** | 512 × 512 pixels |
| **Frames per recording** | ~280 |
| **Tissue** | Human cortical organoid (FOXP1 WT/HET line) |
| **Filename pattern** | `FOXP1<genotype><donor>_<n>_20x_1.55Hz_<measuredHz>.tif` |
| **Example** | `FOXP1HET3_3_20x_1.55Hz_1.547Hz.tif` |

Note the very different acquisition profile from Cases 1-2: **much smaller TIFFs** (512² × 280 frames ≈ 140 MB each, vs. ~1.5 GB for the 20Hz hCO data), **slower frame rate** (1.55 Hz vs 20 Hz), and **much shorter recordings** (~180 seconds vs. ~75 seconds at higher framerate). A different acquisition philosophy: longer wall-time per recording, fewer total frames.

### Full parameter set (still in `C:\AQuA2\cfg\parameters_for_batch.csv` on EC2 as of teardown, backed up to S3)

This dataset's parameters are **substantially different from Cases 1 and 2** — reflecting a different recording type that requires different tuning:

| Parameter | FOXP1 value | Comparison to hCO/Assembloid |
|---|---|---|
| `registrateCorrect` | 1 | (2 for hCO/Assembloid) — different registration mode |
| `bleachCorrect` | 1 | (3 for hCO/Assembloid) — different bleach correction |
| `smoXY` | 0.5 | same |
| `thrARScl` | 3 | (2 for hCO/Assembloid) — **higher threshold**, less sensitive |
| `minDur` | 5 | (3 for hCO/Assembloid) — longer minimum duration (in frames; fewer frames overall at 1.55 Hz) |
| `minSize` | 10 | (20 for hCO/Assembloid) — smaller minimum (smaller pixels at 512² vs 1024²) |
| **`maxSize`** | **400** | (50000 for Assembloid; hCO uniform but exact value see Case 1 §C.2) — **much tighter cap** in FOXP1, reflecting different activity profile |
| `sigThr` | 3.5 | (2.5 for hCO/Assembloid) — more conservative significance |
| `maxDelay` | 0.6 | (0.5 for hCO/Assembloid) |
| `sourceSensitivity` | 10 | (9 for hCO/Assembloid) — maximum sensitivity |
| `detectGlo` | 1 | same — but see Section C on what goes wrong here |
| `gloDur` | 20 | same |
| **`frameRate`** | **0.64** | (0.05 for hCO/Assembloid) — 1.55 Hz acquisition |
| **`spatialRes`** | **2.6** | (1.3 for hCO/Assembloid) — different objective/scaling |

**Implication:** this dataset is **not directly comparable** to Cases 1 or 2 on essentially any metric. It's a different preparation, different microscope settings, and different detection parameters. The pipeline works on it fine, but cross-study comparisons need to be limited to qualitative observations (was there activity at all? does WT differ from HET?) rather than quantitative side-by-side.

---

## B. Compute setup

**Instance type:** ran on the same r7a.24xlarge that was already provisioned for the assembloid work. Massively oversized for this dataset — N=33 doesn't justify it.

**Right-sized for this dataset alone:** `r7i.2xlarge` (64 GB RAM, 8 vCPU). Per-lane RAM is ~2 GB on these small TIFFs; 8 lanes × 2 GB × 1.3 + 16 = ~37 GB.

**Lanes:** 8 (~4 files per lane).

**Wall-clock:** detection completed in ~15 minutes total. CFU in ~2 minutes. If we'd been on a right-sized r7i.2xlarge, total compute cost would have been under $1.

This is the case for **probing first** — but probing makes less sense for N=33, because you'd be probing on ~10% of your data. For small datasets, you can:
- Skip probing and run the whole thing on r7i.2xlarge from the start
- Or treat the first lane completing as your probe — read the RAM numbers, decide if you need to resize before letting the rest run

---

## C. The 2 failed recordings

Two files failed during detection with the same error signature, on the same Carol/FOXP1 dataset:

| File | Lane | Error |
|---|---|---|
| `FOXP1HET3_3_20x_1.55Hz_1.547Hz.tif` | lane 05 | `Index exceeds array elements` (during global signal detection) |
| `FOXP1WT1_1_20x_1.55Hz_1.547Hz.tif` | lane 30 | `Index exceeds array elements` (during global signal detection) |

These are **different from the hyperactive-loop pattern** seen in Case 2:
- Not "running forever with CPU pegged" — they crash quickly with a definite MATLAB error
- The error is in AQuA2's **global signal detection** module
- The per-file `try/catch` guard in the compiled `aqua_lane.exe` caught the error and continued the lane — both failures wrote `<stem>_ERROR.txt` files to the output and the lane processed its remaining files normally

### C.1 — Likely cause

`Index exceeds array elements` during global signal detection suggests an edge case in AQuA2's handling of **short recordings with sparse events**. The `gloDur=20` default assumes enough frames are available; at 280 frames with low activity, there may be too few qualifying events for the global-signal window to compute correctly.

**Not investigated further at this point.** The 2 failures are tracked for follow-up but didn't block the analysis. With N=31 surviving recordings split across 2 genotypes × 3 donors, the cells are still adequately filled for the comparison.

### C.2 — Options for recovering the 2 files (not yet attempted)

If recovering them becomes important:
- Try `detectGlo=0` (disable global signal detection) for those two files — but that's mixed parameters across the dataset, with the same caveats from Case 1
- Try `gloDur=10` to shorten the window — same caveat
- Investigate the data files directly to see if there's something unusual about the recordings themselves
- Accept the exclusion and note in the publication

**Current status:** flagged for follow-up; analysis proceeding on N=31.

---

## D. The actual run results

| Metric | Value |
|---|---|
| Files processed | **31 / 33** (2 excluded due to AQuA2 errors) |
| Total detection time | ~15 minutes |
| Detection output size | small (~50 GB — small TIFFs, short recordings) |
| CFU clustering time | ~2 minutes |
| Mean nCFU per recording | (analysis ongoing) |

---

## E. R analysis specifics

The R script for this dataset was version `v4.27` (continuing a longer versioning chain from the lab's other projects). It was structured around **two-group comparison** (WT vs HET) using:

- **Wilcoxon rank-sum tests** for each metric
- **Cohen's d** effect size for magnitude
- **Benjamini-Hochberg correction** for multiple comparisons across the panel of metrics

This is a typical "small-N, two-group" analysis structure. The pipeline outputs (per-event CSVs + CFU `.mat` standalones) feed directly into this without any unusual handling.

---

## F. Storage layout (final state)

```
s3://<bucket>/CalciumImagingAnalysis/FOXP1_WT_HET_AQuA2_May2026/
├── TIFFs/         ← source TIFFs
├── PreCFU/        ← detection outputs (31 _results folders + 2 _ERROR.txt)
└── PostCFU/       ← CFU standalones (31 _res_cfu.mat)
```

A single dataset-level README at the top of that prefix documents the parameters, the 2 failures, and that analysis proceeded on N=31.

---

## G. Lessons specific to this run

1. **The pipeline scales down well.** Same scripts, same workflow, just smaller and faster. No special accommodations needed for small N.

2. **Right-sizing matters even more on small datasets.** Running 33 files on a $6/hour instance instead of a $0.53/hour one is a 12× overpayment. For a 17-minute run, that's ~$1.50 vs. $0.13 — small absolute, but emblematic. **If your dataset is small enough that probing is overhead, just run on r7i.2xlarge directly.**

3. **A new failure mode: `Index exceeds array elements`.** This wasn't seen in the larger datasets at 20 Hz. The combination of short recording + slow frame rate + sparse activity seems to trigger an edge case in AQuA2's global signal detection. The compiled `aqua_lane.exe`'s per-file `try/catch` guard kept this from being catastrophic — the lane processed its remaining files normally and we got clean `_ERROR.txt` markers identifying exactly which files failed and why.

4. **Per-file guard pays off here.** Without `try/catch`, the lane 05 and lane 30 failures would have killed those lanes mid-stride, losing potentially several other files behind the crash. Instead, only the 2 specifically-bad files were lost.

5. **Small datasets don't need 32 lanes.** 8 lanes for 33 files (~4 files per lane) is the right shape. More lanes than needed wastes scheduling overhead and provides no speedup.

6. **The CFU clustering output is small per file.** Total CFU output for 31 files was ~500 MB. CFU storage is essentially free for any dataset; only detection output is sizable.
