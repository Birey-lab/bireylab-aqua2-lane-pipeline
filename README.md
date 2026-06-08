# AQuA2 Lane Pipeline

Parallel detection + CFU clustering for calcium-imaging data using AQuA2, designed to run on AWS EC2 Windows instances at any scale from tens to thousands of recordings.

The pipeline takes raw multi-frame TIFFs (calcium fluorescence movies), splits them into `N` parallel "lanes" (one MATLAB worker per lane), runs AQuA2 event detection and CFU clustering, and produces per-recording `.mat` outputs ready for downstream R analysis.

**Current release: orchestrator [v0.7.4](https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline/releases/tag/v0.7.4)** (June 2026). The orchestrator script `powershell/Run-Pipeline.ps1` drives the entire pipeline end-to-end (Split → Detect → CFU → Consolidate → Upload to S3) with per-run audit trails, three-stage stall detection, and resume guards.

**Key design decisions:**

- **Compiled, license-free workers.** The detection and CFU scripts are compiled into Windows executables (`aqua_lane.exe`, `cfu_lane.exe`) that run on the free MATLAB Runtime. No MATLAB license is consumed per lane, so parallelism is unbounded by license seats.
- **Resume + per-file guard.** Each worker skips already-completed files (safe to interrupt and re-run) and wraps each file in `try/catch` so a single bad TIFF doesn't kill an entire lane.
- **Three-stage stall detection.** Lanes that stop making progress get a yellow WARN at 30 min, a red ESCALATE at 45 min, and an AUTO-SKIP at 60 min that quarantines the stuck file and restarts the lane.
- **Measurement-based instance sizing.** The orchestrator's Auto-Size phase probes the largest input TIFF and computes a safe lane count for the instance's RAM. For unfamiliar datasets, the manual probe protocol in [`docs/03`](docs/03_SIZING_AND_RESIZING_GUIDE.md) is still the gold standard.

---

## Quick start (if you have lab AMI access)

If you can launch from the `Windows2025-AQuA2-Pipeline-v2-Clean` AMI, everything is pre-installed. The fast path:

1. Launch an EC2 instance from the AMI with IAM role `EC2toS3Full` attached
2. RDP in as `Administrator`
3. Pull the latest orchestrator: `cd C:\Users\Administrator\Documents\pipeline-repo; git pull`
4. Stage your TIFFs in `D:\incoming_tiffs\` (from S3 or upload)
5. Dry-run preview:
   ```powershell
   cd C:\Users\Administrator\Documents\pipeline-repo\powershell
   .\Run-Pipeline.ps1 -OutputRoot "D:\runs" -ProjectName "my_dataset" -InputTIFFs "D:\incoming_tiffs" -WhatIfMode
   ```
6. Full run with S3 upload:
   ```powershell
   .\Run-Pipeline.ps1 `
       -OutputRoot  "D:\runs" `
       -ProjectName "my_dataset" `
       -InputTIFFs  "D:\incoming_tiffs" `
       -Upload      $true `
       -S3Prefix    "s3://<your-bucket>/CalciumImagingAnalysis/AQuA2_Outputs/my_dataset/"
   ```

Full details: [`docs/09_AMI_QUICK_LAUNCH.md`](docs/09_AMI_QUICK_LAUNCH.md).

For users without AMI access, or anyone building infrastructure for the first time, read the numbered docs in order — see [Where to start](#where-to-start) below.

---

## Where to start

**Have AMI access?** → [`docs/09_AMI_QUICK_LAUNCH.md`](docs/09_AMI_QUICK_LAUNCH.md) (covers everything for routine runs)

**Building from scratch, or want the full conceptual background**, read these in order:

1. [`docs/01_OVERVIEW.md`](docs/01_OVERVIEW.md) — what the pipeline does, conceptually
2. [`docs/02_INFRASTRUCTURE_SETUP.md`](docs/02_INFRASTRUCTURE_SETUP.md) — software stack, AWS, IAM, storage
3. [`docs/03_SIZING_AND_RESIZING_GUIDE.md`](docs/03_SIZING_AND_RESIZING_GUIDE.md) — **measure your data before launching big compute** ← do not skip
4. [`docs/04_PIPELINE_OPERATIONS.md`](docs/04_PIPELINE_OPERATIONS.md) — orchestrator usage, monitoring, recovery (v0.7.4)
5. [`docs/05_DOWNSTREAM_R_ANALYSIS.md`](docs/05_DOWNSTREAM_R_ANALYSIS.md) — R script integration
6. [`docs/06_PITFALLS_AND_RECOVERY.md`](docs/06_PITFALLS_AND_RECOVERY.md) — read at least once before any major run
7. [`docs/07_TEARDOWN_CHECKLIST.md`](docs/07_TEARDOWN_CHECKLIST.md) — what to grab before deleting an instance
8. [`docs/08_OPERATIONS_PLAYBOOK.md`](docs/08_OPERATIONS_PLAYBOOK.md) — pre-flight, smoke test, step-by-step gotchas, recovery. **Read this before any new dataset.**
9. [`docs/09_AMI_QUICK_LAUNCH.md`](docs/09_AMI_QUICK_LAUNCH.md) — the AMI fast-path (recommended entry for routine work)

**Case studies** showing what real runs looked like, with concrete numbers and decisions: [`docs/case-studies/`](docs/case-studies). Useful for grounding the generic docs in real examples.

---

## Repository structure

| Path | What's in it |
|---|---|
| `powershell/Run-Pipeline.ps1` | **The orchestrator** — single script that drives the entire pipeline (v0.7.4+) |
| `powershell/` | Underlying lane-orchestration scripts (`Split-IntoLanes.ps1`, `Launch-Lanes-Exe.ps1`, `Build-CFU-Lanes.ps1`, `Launch-CFU-Lanes.ps1`, `Consolidate-Template.ps1`) — wrapped by the orchestrator; can be called directly for debugging |
| `matlab/` | Real MATLAB source for the compiled workers (`aqua_lane.m`, `aqua_cmd_batch_lane.m`, `cfu_lane.m`) |
| `fiji-macros/` | Fiji/ImageJ macros for TIFF preprocessing (`LIF_Extractor.ijm`, `TrimTIF_Frames.ijm`, `AQUA2_Movie_Timestamp.ijm`) |
| `r/` | Canonical R analysis script (latest version). Earlier versions in S3 archive |
| `config/` | Parameter file template |
| `docs/` | Numbered documentation (9 files + template) |
| `docs/case-studies/` | Worked examples (CACNA1A hCO, CACNA1A Assembloid, FOXP1 WT/HET), each with its own README + scripts used for that dataset |

---

## Lab-internal note: archived run artifacts

For lab members continuing this work: pipeline artifacts from past runs (compiled `.exe` workers, MATLAB source tree, per-run `parameters_for_batch_*.csv` files) are archived at `s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/ARCHIVE/_PipelineArtifacts/` with date-stamped subfolders. The June 2026 snapshot includes the parameter CSVs for the CACNA1A hCO, CACNA1A Assembloid, and FOXP1 WT/HET runs documented in [`docs/case-studies/`](docs/case-studies). Authoritative per-recording parameter values also live in each `_AQuA2.mat` file's `opts` struct in the per-dataset S3 prefixes.

The current lab AMI is `Windows2025-AQuA2-Pipeline-v2-Clean` in `us-east-1`; ask Arvin for access.

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
