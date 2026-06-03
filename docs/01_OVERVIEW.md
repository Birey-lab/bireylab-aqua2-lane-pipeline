# 01 — Overview

What this pipeline does, how the pieces fit together, and the design decisions behind it. Read this first.

---

## What the pipeline does

The pipeline takes calcium-imaging recordings (multi-frame TIFF stacks) and produces per-recording event-detection and CFU-clustering outputs ready for downstream statistical analysis in R. It is designed to process anywhere from a handful to thousands of recordings on a single cloud instance, with wall-clock scaling roughly linearly with file count divided by lane parallelism.

The end-to-end flow:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  RAW DATA                                                               │
│  Microscope output (often Leica .lif files)                             │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ optional: Fiji/ImageJ macros to convert
                         │           .lif → TIFF, trim frames, etc.
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TIFF STACKS                                                            │
│  One per recording, each containing N frames                            │
│  Filename should encode metadata for grouping (donor, condition, etc.)  │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ Split-IntoLanes.ps1
                         │ (size-balanced subfolders, one per worker)
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  LANE FOLDERS                                                           │
│  laneNN/  (N = your chosen parallelism, typically 8–32)                 │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ Launch-Lanes-Exe.ps1  →  aqua_lane.exe × N
                         │ (one parallel worker per lane,
                         │  each reads parameters_for_batch.csv)
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  DETECTION RESULTS  (Part 1 output)                                     │
│  Per recording:                                                         │
│   <stem>_AQuA2.mat         — event detection (v7.3 HDF5)                │
│   <stem>_AQuA2_Ch1.csv     — per-event feature table                    │
│   <stem>_AQuA2_curves.xlsx — fluorescence traces                        │
│   <stem>_Movie.tif         — playback render (optional)                 │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ Build-CFU-Lanes.ps1 (NTFS junctions, no copy)
                         │ Launch-CFU-Lanes.ps1  →  cfu_lane.exe × N
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  CFU RESULTS  (Part 2 output)                                           │
│  Per recording:                                                         │
│   <stem>_AQuA2.mat              — original + cfuInfo1/2/Relation/       │
│                                   cfuGroupInfo baked in (in-place)      │
│   <stem>_AQuA2_res_cfu.mat      — standalone CFU output                 │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ Consolidate-Template.ps1 (flatten by stem)
                         │ aws s3 sync (backup to cloud storage)
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  CONSOLIDATED + BACKED UP                                               │
│  PreCFU_<dataset>/<stem>_results/  (detection bundle, one folder/file)  │
│  <dataset>_POST/<stem>_AQuA2_res_cfu.mat  (CFU standalones, flat)       │
│  s3://<bucket>/.../  (everything mirrored for safety + sharing)         │
└────────────────────────┬────────────────────────────────────────────────┘
                         │ R script (your own analysis pipeline)
                         │ reads csv_dir (recursive) + mat_dir
                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  R ANALYSIS RESULTS                                                     │
│  RESULTS_<dataset>/                                                     │
│   per-condition summaries, stats, ggplots, GraphPad-ready CSVs          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Mental model: "lanes" and why they exist

AQuA2's reference implementation processes one TIFF at a time. For a single recording that's fine — for hundreds or thousands of recordings, sequential processing takes days to weeks.

The pipeline parallelizes by **splitting the input set into N lanes** (subfolders), then launching N independent worker processes, one per lane. Each worker is single-threaded (we disable AQuA2's internal `parpool`) and processes the files in its lane sequentially; parallelism is across lanes, not within.

This design buys you:
- Linear speedup with `N` lanes, up to the box's RAM and disk limits
- Fault isolation — if one lane hits a bad file, only that lane is affected
- Trivial restart — re-running the launcher skips already-completed files

The cost: you need enough RAM for `N` simultaneous worker processes. This is what drives instance sizing (see [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md)).

---

## Why the workers are compiled executables

The compiled `aqua_lane.exe` and `cfu_lane.exe` files run on the **free MATLAB Runtime** — no MATLAB license consumed per worker. This is the unlock that makes high parallelism cheap.

Without compilation, each parallel worker would launch `matlab -batch` and consume one license seat. Most academic MATLAB licenses are concurrent-user-limited; running 32 parallel workers would saturate the license pool and starve other users in your institution.

With compilation:
- One person with MATLAB + the MATLAB Compiler toolbox runs `mcc` once to produce `.exe` files
- Those `.exe` files run anywhere with the free MATLAB Runtime installed (download from MathWorks at no cost)
- Parallelism is limited only by your hardware, not by license seats
- Workers start faster (no MATLAB IDE startup overhead)

The downside: any time you change worker behavior (e.g., turn movie generation off), you must recompile. In practice this is rare — once the workers are stable, they don't change.

The `.m` sources for both workers are in [`matlab/`](../matlab/) along with the `mcc` commands used to compile them.

---

## What's variable vs. what's fixed

Things you'll typically configure per dataset:

| Variable | Set in | Typical range |
|---|---|---|
| Number of files (N) | (determined by your data) | 10s to 1000s |
| Magnification → `spatialRes` | `parameters_for_batch.csv` | 1.0–5.0 µm/px |
| Frame rate → `frameRate` | `parameters_for_batch.csv` | 0.01–1.0 s/frame |
| `maxSize` (event size cap) | `parameters_for_batch.csv` | 2000–inf, typically 50000 |
| Number of lanes | Launch script parameter | 8–32 |
| Instance type | AWS Console | r7i.xlarge to r7a.32xlarge |
| EBS volume size | AWS Console | 500 GB to 12 TB |

Things that are fixed by the pipeline design (don't change without good reason):

- The compiled workers' internal flags: `movie=ON`, `risingMaps=OFF`, `parpool=disabled`, `resume+per-file-guard=ON` for `aqua_lane`; `whetherUpdateRes=true`, `whetherOutputCFURes=true` for `cfu_lane`
- The CFU clustering thresholds baked into `cfu_lane.exe`: `overlapThr=0.5`, `minNumEvt=3`, `maxDist=10`, `pValueThr=1e-5`, `cfuNumThr=3`
- The file format conventions: outputs always v7.3 HDF5 `.mat`, per-event CSVs alongside, `_res_cfu.mat` standalone

If you need different CFU thresholds or want movies off, recompile the worker `.m` files with the changes.

---

## What you need to know before starting

This pipeline assumes:
- You have AWS access (or equivalent cloud compute with Windows + GPU-free instances)
- Your data is in TIFF format (multi-frame stacks, one file per recording)
- Your filenames encode metadata you'll want to group by (donor, condition, age, etc.) — see filename-convention notes in the case studies
- You're comfortable with PowerShell command-line usage on Windows
- For downstream analysis, you can use R (the pipeline produces R-friendly outputs but you write your own analysis scripts on top)

If any of those are missing, address them first.

---

## Next steps

1. [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) — provision the AWS environment and confirm software is in place
2. [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) — measure your data, pick the right instance
3. [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) — run the actual pipeline
