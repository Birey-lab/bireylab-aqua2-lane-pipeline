# AQuA2 Lane Pipeline

Parallel detection + CFU clustering for calcium-imaging data using AQuA2, designed to run on AWS EC2 Windows instances at any scale from tens to thousands of recordings.

The pipeline takes raw multi-frame TIFFs (calcium fluorescence movies), splits them into `N` parallel "lanes" (one MATLAB worker per lane), runs AQuA2 event detection and CFU clustering, and produces per-recording `.mat` outputs ready for downstream R analysis.

**Key design decisions:**
- **Compiled, license-free workers.** The detection and CFU scripts are compiled into Windows executables (`aqua_lane.exe`, `cfu_lane.exe`) that run on the free MATLAB Runtime. No MATLAB license is consumed per lane, so parallelism is unbounded by license seats.
- **Resume + per-file guard.** Each worker skips already-completed files (safe to interrupt and re-run) and wraps each file in `try/catch` so a single bad TIFF doesn't kill an entire lane.
- **Measurement-based instance sizing.** Rather than guessing at instance size, you run a probe protocol on a small subset of your data to measure per-lane RAM and per-file wall-clock, then pick an instance type accordingly.

---

## Where to start

**If you are a new user starting from scratch on a new dataset, read these in order:**

1. [`docs/01_OVERVIEW.md`](docs/01_OVERVIEW.md) — what the pipeline does, conceptually
2. [`docs/02_INFRASTRUCTURE_SETUP.md`](docs/02_INFRASTRUCTURE_SETUP.md) — software, AWS, storage setup
3. [`docs/03_SIZING_AND_RESIZING_GUIDE.md`](docs/03_SIZING_AND_RESIZING_GUIDE.md) — **measure your data before launching big compute** ← do not skip
4. [`docs/04_PIPELINE_OPERATIONS.md`](docs/04_PIPELINE_OPERATIONS.md) — detection, CFU, consolidation, monitoring
5. [`docs/05_DOWNSTREAM_R_ANALYSIS.md`](docs/05_DOWNSTREAM_R_ANALYSIS.md) — R script integration
6. [`docs/06_PITFALLS_AND_RECOVERY.md`](docs/06_PITFALLS_AND_RECOVERY.md) — read at least once before any major run
7. [`docs/07_TEARDOWN_CHECKLIST.md`](docs/07_TEARDOWN_CHECKLIST.md) — what to grab before deleting an instance

**Case studies** showing what real runs looked like, with concrete numbers and decisions: [`docs/case-studies/`](docs/case-studies/). These are useful for grounding the generic docs in real examples.

---

## Repository structure

| Path | What's in it |
|---|---|
| `docs/` | Conceptual/procedural documentation (7 numbered files + template) |
| `docs/case-studies/` | Three worked examples, each in its own folder with the case-study `README.md` plus `scripts/` (the actual code that ran for that dataset) |
| `powershell/` | Generic lane-orchestration scripts (`.ps1`) — the real ones used in production |
| `matlab/` | Real MATLAB source for the compiled workers (`.m`) |
| `fiji-macros/` | Fiji/ImageJ macros for TIFF preprocessing (`.ijm`) |
| `r/` | Canonical R analysis script (latest version). Earlier versions in S3 archive |
| `config/` | Parameter file template |

---

## Lab-internal note: archived run artifacts

For lab members continuing this work: pipeline artifacts from past runs (compiled `.exe` workers, MATLAB source tree, per-run `parameters_for_batch_*.csv` files) are archived at `s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/ARCHIVE/_PipelineArtifacts/` with date-stamped subfolders. The June 2026 snapshot includes the parameter CSVs for the CACNA1A hCO, CACNA1A Assembloid, and FOXP1 WT/HET runs documented in [`docs/case-studies/`](docs/case-studies/). Authoritative per-recording parameter values also live in each `_AQuA2.mat` file's `opts` struct in the per-dataset S3 prefixes.

---

## What this is NOT

- **Not a replacement for AQuA2.** This pipeline is orchestration around AQuA2 — it does not modify or replace AQuA2's detection or clustering logic. The compiled exes wrap AQuA2's calls; everything algorithmic lives in AQuA2 itself.
- **Not a one-click pipeline.** You will configure parameters, probe your data, and make sizing decisions. The docs walk you through each, but it is not push-button.
- **Not validated outside Windows / AWS EC2.** Linux is theoretically possible but the compiled exes here are Windows-built. Adapting to Linux requires recompiling MATLAB sources on a Linux machine and rewriting PowerShell scripts as bash.

---

## License and attribution

Pipeline scripts and documentation are released under the MIT License (see [`LICENSE`](LICENSE)). The AQuA2 package itself is separately licensed; consult the [AQuA2 repository](https://github.com/yu-lab-vt/AQuA2) for its terms.

The compiled `aqua_lane.exe` and `cfu_lane.exe` files are not distributed in this repository — they are produced by running MATLAB Compiler (`mcc`) on the included `.m` sources, which requires a MATLAB installation with the MATLAB Compiler toolbox.

This pipeline was developed in the Birey Lab at Emory University for processing calcium-imaging data from cortical organoids, assembloids, and related preparations. If it's useful for your work, citation is appreciated but not required.

---

## Issues and contributions

Bug reports, questions, and PRs welcome via the GitHub issue tracker.
