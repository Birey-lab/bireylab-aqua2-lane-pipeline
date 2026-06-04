# Case Study 2 — Cortical Assembloids (20x) Calcium Imaging

A second large run, executed after the hCO experience and benefiting from those lessons. Notable for: a single confirmed pathological file isolated and excluded, **uniform `maxSize=50000`** chosen as a tighter bound than the hCO run (a deliberate parameter choice — see cross-dataset note in Section A).

**Run date:** 2026 (a few weeks after hCO v2)  |  **Lab:** Birey Lab, Emory

---

## A. The dataset

| Property | Value |
|---|---|
| **N recordings (started)** | 1013 |
| **N recordings (completed)** | **1012** (one excluded — see Section C) |
| **Genetic line** | **CACNA1A** (same line as hCO Case Study 1) |
| **Donors** | Donors 1 and 4 |
| **Conditions** | C (control), G (gain-of-function), L (loss-of-function) — CACNA1A alleles |
| **Promoters** | CAMK2A, DLX |
| **Ages observed** | d122, d126 (and others) |
| **Magnification** | 20x objective |
| **Acquisition rate** | 20 Hz nominal; measured ~19.1-19.3 Hz |
| **Tissue** | Cortical-subpallium assembloid |
| **Filename pattern** | `<donor><condition>_d<age>_20x_20Hz_Assembloid_<promoter>_ORG<n>_V<m>_<measuredHz>.tif` |
| **Example** | `4L_d126_20x_20Hz_Assembloid_DLX_ORG3_V1_19.23Hz.tif` |

### Cross-dataset comparability (read this before comparing to hCO)

Both this Assembloid dataset and the hCO Case Study 1 dataset were processed at the **same `maxSize=50000`** with otherwise identical detection parameters (`thrARScl=2`, `minDur=3`, `minSize=20`, `sourceSensitivity=9`, `sigThr=2.5`, `maxDelay=0.5`, `registrateCorrect=2`, `bleachCorrect=3`, `frameRate=0.05`, `spatialRes=1.3`).

This means **direct cross-dataset comparison is valid** for all derived metrics. The differences observed between hCO and Assembloid reflect the biology of the preparations, not parameter-induced confounds.

### Full parameter set (archived as `parameters_for_batch_CACNA1AAssembloidsArvinMay2026.csv`, backed up to S3)

| Parameter | Value |
|---|---|
| `registrateCorrect` | 2 |
| `bleachCorrect` | 3 |
| `smoXY` | 0.5 |
| `thrARScl` | 2 |
| `minDur` | 3 |
| `minSize` | 20 |
| **`maxSize`** | **50000** |
| `sigThr` | 2.5 |
| `maxDelay` | 0.5 |
| `sourceSensitivity` | 9 |
| `detectGlo` | 1 |
| `gloDur` | 20 |
| `frameRate` | 0.05 (20 Hz) |
| `spatialRes` | 1.3 (20x) |

---

## B. Compute setup

**Instance type:** `r7a.24xlarge` (96 vCPU, 768 GiB RAM). **Sized appropriately this time** based on the hCO experience — we knew per-lane RAM was ~12 GB, and 32 lanes × 12 × 1.3 + 16 = 515 GB, well within the 768 GiB box.

**Lanes:** 32, ~31-32 files per lane.

**Wall-clock for detection:** roughly comparable to hCO per file on average. Same `maxSize=50000`, same other parameters, similar TIFF sizes — so the timing comparison is apples-to-apples and the modest per-file differences are real characteristics of the preparations.

---

## C. The pathological file

This is the interesting operational story for the assembloid run.

### C.1 — Discovery

After ~6 hours of detection running smoothly, 31 of 32 lanes had finished, leaving lane 14 alone with 19 of its 32 files done and one process still running. The remaining files in that lane were stuck behind something heavy.

Diagnosis:
```powershell
Get-Content '...\_lane_logs\lane14.log' -Tail 30 -Wait
```
The log showed `SE 158` (spatial segmentation iteration counter) and **stayed there for over 10 minutes**. CPU was climbing (~30 seconds/minute), so the process wasn't deadlocked — it was actively computing. But no progress was being made through SE iterations.

This is the **"pathological loop"** signature: CPU consumed, no forward progress, no error. A hyperactive recording where `maxSize=50000` allowed creation of merged regions large enough to spin in segmentation.

### C.2 — Isolation strategy

Rather than guess at the file, we:

1. Killed only the stuck lane: `Stop-Process -Name aqua_lane -Force` (only one process was alive at this point)
2. Listed the 13 pending files in lane 14
3. Split them across 13 fresh mini-lanes, **one file per lane** (max parallelism, perfect isolation)
4. Re-launched the mini-batch
5. Watched: 12 of 13 lanes completed within minutes. **One lane stayed alive.**

By elimination, the lane still running held the pathological file: `4C_d126_20x_20Hz_Assembloid_DLX_ORG5_V10_19.23Hz.tif`

### C.3 — Decision: exclude vs. re-run at lower maxSize

The hCO experience had taught us: **mixed maxSize is more dangerous than excluding one file.** With N=1012 vs. N=1013, losing one recording in one promoter × age × donor cell was statistically negligible.

Decision: **exclude** the file. Documented in the dataset README; final analysis set is N=1012 at uniform `maxSize=50000`.

Time investment in this isolation procedure: ~1 hour. Cost on the running instance: ~$6.

### C.4 — Aftermath

The 12 redistributed files completed normally and were merged back into the main results tree via the "move per-recording subfolders, not lane wrappers" pattern (see [`../../06_PITFALLS_AND_RECOVERY.md`](../../06_PITFALLS_AND_RECOVERY.md) Pitfall 8). The final detection set was clean: 1012 recordings, no errors, no `_ERROR.txt` files.

---

## D. The actual run results

| Metric | Value |
|---|---|
| Files processed | **1012 / 1013** (1 excluded as pathological) |
| Files with errors | 0 |
| Total detection time | ~6 hours including the redistribution recovery |
| Detection output size | ~3.06 TB (with movies on) |
| CFU clustering time | ~10 minutes on same box |
| CFU output size | ~15 GB |
| Mean nCFU per recording | **11.7** |
| Max nCFU | 138 |
| Recordings with 0 CFUs | **184 (~18%)** |

### D.1 — Cross-dataset comparison to hCO

|  | hCO (n=1191) | Assembloids 20x (n=1012) |
|---|---|---|
| `maxSize` | 50000 (confirmed via [hCO scripts/Repartition-hCO-v2.ps1](../01_hCO_cortical_organoids/scripts/Repartition-hCO-v2.ps1)) | 50000 (confirmed via archived CSV) |
| Mean nCFU | 21.6 | **11.7** |
| Max nCFU | 198 | **138** |
| Files with 0 CFUs | 74 (~6%) | **184 (~18%)** |

Same detection parameters; the differences reflect **biology**, not processing:
- Lower mean nCFU in assembloids — sparser CFU-eligible activity in this preparation
- Higher zero-rate — many recordings have minimal CFU-eligible activity
- Lower max — no single assembloid recording reaches the level of the busiest hCO

This is exactly what cross-dataset comparability at uniform parameters lets you say: directional differences are real, not artifactual.

---

## E. Storage layout (final state)

```
s3://<bucket>/CalciumImagingAnalysis/
├── AQuA2_Outputs/
│   ├── Assembloids_20x_MaxSize50000/         ← detection, Standard (6,072 obj / 3.06 TB)
│   └── Assembloids_20x_MaxSize50000_CFU/     ← CFU, Standard (1,013 obj / 15 GB)
└── R_Analysis_Results/
    └── Assembloids_20x_MaxSize50000/         ← R outputs
```

The detection README explicitly notes the one excluded file and the maxSize chosen.

---

## F. Lessons specific to this run

1. **Sizing on prior probe data works.** Skipping the probe phase was reasonable here because we had hCO data with very similar recording properties. The r7a.24xlarge was correctly sized. **But:** if you're at all unsure, probe anyway. The probe costs $3; getting it wrong costs much more.

2. **The "one file per lane" isolation pattern is gold.** When you have a suspected pathological file among several pending, splitting one-file-per-lane gets you a definitive answer in minutes. The cost of running 13 idle lanes briefly is trivial; the time saved on diagnosis is significant.

3. **Excluding one file is almost always better than mixing parameters.** Especially at N>1000, losing 1 sample is in the noise. Mixing parameters within a dataset is forever.

4. **184 zero-CFU files (18%) was higher than hCO** but consistent across conditions — not concentrated in one group, just a feature of the preparation. Worth checking the per-condition distribution of zeros early so you know if it correlates with anything biological.

5. **Cross-dataset consistency pays off.** Because hCO and Assembloid were run at the same `maxSize=50000` with identical other parameters, the two datasets can be directly compared on essentially any metric. This was a deliberate choice (uniform parameters across runs of the same line/preparation), and it's what makes the cross-study biological observations defensible. **Future preparations meant to be directly comparable should keep this same parameter set.** Other preparations with different acquisition modes (like FOXP1 at 1.55 Hz vs. these at 20 Hz) will necessarily diverge — see Case 3.

6. **The CFU launcher's hardcoded log path overwrote the hCO CFU logs.** We didn't rename `CFU_lanes/_logs/` before running this batch, so lanes 1-20 of the hCO CFU logs were silently overwritten. The hCO nCFU summary statistics had been pulled and saved beforehand, so no scientific information was lost — but the lane-level provenance for hCO CFU is now gone. **Always rename `CFU_lanes/_logs/` before a new CFU run.** Now permanently in the operations doc.
