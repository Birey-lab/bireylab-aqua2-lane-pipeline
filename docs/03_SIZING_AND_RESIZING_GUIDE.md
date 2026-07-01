# 03 — Sizing & Resizing Guide

**Before launching a big expensive EC2 instance and running the pipeline, read this.** It will save you money and avoid the two failure modes: under-provisioning (instance crashes or thrashes) and over-provisioning (paying for idle capacity).

Instance sizing is **data-dependent.** Different TIFF sizes, frame counts, and AQuA2 `maxSize` settings produce wildly different per-lane RAM and per-file wall-clock numbers. This guide teaches you to measure those numbers on your own data via a quick probe, then size accordingly.

For worked examples with real numbers, see the [case studies](case-studies/).

---

## Table of contents

- [Part A — Why sizing matters](#a)
- [Part B — Conceptual model: what consumes what](#b)
- [Part C — The probe protocol (measure before you commit)](#c)
- [Part D — From probe to instance choice](#d)
- [Part E — Phase-by-phase sizing (the instance lifecycle)](#e)
- [Part F — How to actually resize (AWS Console)](#f)
- [Part G — Disk/EBS sizing](#g)
- [Part H — Cost calculator](#h)
- [Part I — Decision tree](#i)

---

<a name="a"></a>
## Part A — Why sizing matters

EC2 pricing is **per second of wall-clock**, regardless of whether you're using all the CPUs and RAM. Memory-optimized "r" family instances (which this pipeline uses) span a wide cost range:

| Instance | RAM | vCPU | On-demand ($/hour, US, 2026) | Per 24 hours |
|---|---|---|---|---|
| r7a.32xlarge | 1024 GiB | 128 | ~$8.16 | ~$196 |
| r7a.24xlarge | 768 GiB | 96 | ~$6.12 | ~$147 |
| r7a.16xlarge | 512 GiB | 64 | ~$4.08 | ~$98 |
| r7a.12xlarge | 384 GiB | 48 | ~$3.06 | ~$73 |
| r7a.8xlarge | 256 GiB | 32 | ~$2.04 | ~$49 |
| r7a.4xlarge | 128 GiB | 16 | ~$1.02 | ~$24 |
| r7a.2xlarge | 64 GiB | 8 | ~$0.51 | ~$12 |
| r7i.2xlarge | 64 GiB | 8 | ~$0.53 | ~$13 |
| r7i.xlarge | 32 GiB | 4 | ~$0.27 | ~$6 |

(`r7a` = AMD-based, slightly cheaper; `r7i` = Intel. Performance differences are minor for this workload.)

> **Pricing basis (read once).** These are **approximate** on-demand US-region figures for 2026 and drift over time. Rule of thumb: **≈ $0.06/vCPU-hour** for `r7a` (`r7i` is similar), so cost scales roughly linearly with vCPU count — about **~$0.5/hr at 8 vCPU up to ~$12/hr at 192 vCPU** (`r7a.48xlarge`). **This table is the single cost reference for the repo**; other docs quote rounded/broad versions of it. Always confirm the current rate in the [AWS pricing calculator](https://calculator.aws/) before committing to a long run (and consider Spot for interruptible work).

**Two ways to lose money:**
1. **Over-provision:** running r7a.32xlarge for an R analysis that needs only 64 GiB → wasting ~$7/hour times hours
2. **Under-provision then crash:** picking r7a.4xlarge for a high-RAM detection run, OOMing, losing partial progress, having to resize and restart

**Sizing is data-dependent.** The right instance for your batch is not necessarily the one any other lab used; it's the one matched to **your** per-lane RAM × **your** desired parallelism.

---

<a name="b"></a>
## Part B — Conceptual model: what consumes what

For each phase of the pipeline, different resources matter. Here's the breakdown.

### B.1 — Detection (Part 1 of pipeline) — RAM and CPU heavy

What consumes **RAM** during detection:

- **Loaded TIFF**: full frame stack in memory (`width × height × frames × bytes_per_pixel`). A 512×512×280 uint16 TIFF is ~140 MB. A 1024×1024×3000 uint16 TIFF is ~6 GB.
- **dF/F matrix**: same dimensions, double-precision, often ~2× the TIFF size in memory.
- **Active region masks and event maps**: depend on activity level. More active recordings allocate more.
- **`maxSize` parameter directly affects this**: a higher cap allows larger merged regions, which are stored — `maxSize=inf` can use *much* more RAM than `maxSize=2000` on the same file.
- **MATLAB Runtime overhead**: ~500 MB per process baseline.

**Per-lane peak RAM** depends entirely on your data. For 20x objective with ~1024² × ~1500 frame TIFFs and `maxSize=50000`, expect ~10-15 GB/lane average with spikes to ~20+ GB on hyperactive files. For smaller TIFFs (512² × ~300 frames) and lower `maxSize`, expect 2-5 GB/lane. **You must measure on your own data** (Part C).

What consumes **CPU** during detection: AQuA2's spatial-segmentation pass scales with the number and size of active regions. Each lane uses **one logical CPU effectively** (we disable internal parpool — `parpool=disabled` in the exe banner). So `N` lanes = `~N` CPU cores busy.

**Implication for sizing:** the box needs **(per-lane RAM × number of lanes) × ~1.3 safety** total RAM, and at least as many vCPU as lanes (preferably 2-3× to leave headroom for OS and I/O).

### B.2 — CFU (Part 2 of pipeline) — disk-bound, low compute

CFU clustering does very little computation but rewrites multi-GB `.mat` files in place. The bottleneck is **EBS write throughput**, not CPU or RAM.

Per-lane RAM during CFU: typically 2-4 GB, dominated by loading the detection result. Much cheaper than detection.

CPU during CFU: trivial — most time is spent waiting on disk writes.

**Implication for sizing:** CFU doesn't need the same beefy box as detection. You can run CFU on a smaller instance, or stay on the same box for convenience. EBS throughput matters more than instance type here.

### B.3 — S3 sync — network-bound, near-zero compute

S3 syncs use network I/O. They saturate at the smaller of: instance network bandwidth, disk read throughput, or the S3 service rate. None of these are improved by a bigger instance type beyond the small/medium tier.

**Implication for sizing:** S3 sync work runs perfectly well on **r7i.2xlarge** or **r7i.xlarge**. After detection finishes, downsize to one of these for the sync phase to save ~90% of the per-hour cost.

### B.4 — R analysis — RAM and CPU moderate, dataset-dependent

R aggregates per-recording data into condition-level summaries. RAM scales with how much you load into memory at once.

Typical needs:
- **Descriptive stats + ggplots:** 16-32 GB of RAM is plenty. r7i.xlarge (32 GB) or r7i.2xlarge (64 GB).
- **Modeling (randomForest, glmnet, brms):** RAM-hungry. r7i.4xlarge (128 GB) safer.
- **Per-event aggregation at full resolution:** can spike high if you `rbind` everything into one giant frame; consider chunked processing.

**Implication for sizing:** R doesn't need extreme RAM. 64-128 GB is the sweet spot for most workloads.

### B.5 — Consolidation, cleanup, exploration — minimal needs

Anything that's just file moves and listings runs on **r7i.xlarge** or smaller comfortably.

---

<a name="c"></a>
## Part C — The probe protocol (measure before you commit)

**Do this first before any large run.** Total cost: a few dollars. Time: 1-3 hours including instance spin-up.

### C.1 — What you'll measure

For *your* TIFFs at *your* AQuA2 parameters, you need:
- **Peak RAM per lane (single-file processing)** — call this `R_peak` GB
- **Wall-clock per file (single-file processing)** — call this `T_file` minutes
- **Output size per file on disk** — call this `D_file` GB (includes `_AQuA2.mat`, CSV, XLSX, movie)

These three numbers determine everything downstream.

### C.2 — Probe setup

**1. Launch a small probe instance** — r7i.2xlarge (64 GB RAM, ~$0.53/hour). Big enough to hold a single lane comfortably even on heavy data; small enough not to waste money during the probe.

**2. Pull your TIFFs from S3** to local disk. Pick **3-5 representative recordings** — ideally including any you suspect may be heavy/hyperactive. Total local need: ~3-5 × your TIFF size in GB, plus output room (estimate 3× for safety).

**3. Set up parameters** in `C:\AQuA2\cfg\parameters_for_batch.csv` with the values you intend to use for the real run (especially `maxSize`, `spatialRes`, `frameRate`).

### C.3 — Probe execution

**Run a single lane with your 3-5 probe files:**
```powershell
$probeIn = "C:\probe\lane01"
$probeOut = "C:\probe\results"
New-Item -ItemType Directory -Path $probeOut -Force | Out-Null

# launch ONE lane in the foreground, so we can watch
& "C:\AQuA2\compiled\aqua_lane.exe" $probeIn $probeOut
```

**While it runs**, in a second PowerShell window, sample memory and progress every 30 seconds:
```powershell
while ($true) {
  $p = Get-Process aqua_lane -ErrorAction SilentlyContinue
  if ($p) {
    $rss_gb = [math]::Round($p.WorkingSet64 / 1GB, 2)
    $done = (Get-ChildItem "C:\probe\results" -Filter *_AQuA2.mat -ErrorAction SilentlyContinue).Count
    "[{0}]  RAM: {1} GB  |  done: {2}" -f (Get-Date -Format HH:mm:ss), $rss_gb, $done
  }
  Start-Sleep 30
}
```

**Record:**
- The highest RAM number you see across the whole run → that's your `R_peak`.
- Total wall-clock divided by file count → that's `T_file` (minutes per file).

**When done, measure output size:**
```powershell
$out_size_gb = [math]::Round(((Get-ChildItem "C:\probe\results" -Recurse -File | Measure-Object -Sum Length).Sum) / 1GB, 2)
$file_count = (Get-ChildItem "C:\probe\results" -Filter *_AQuA2.mat).Count
"Output per file: $([math]::Round($out_size_gb / $file_count, 2)) GB"
```
That's your `D_file`.

### C.4 — Carry these numbers forward

Write down your `R_peak`, `T_file`, and `D_file`. You'll use them in Part D (instance sizing) and Part H (cost estimation).

### C.5 — Spike check (heavy file detection)

Note any individual file in the probe that took **significantly longer than the others** or used **significantly more RAM**. These are early warnings that some files in your full set may be **pathological** under your `maxSize` setting — see [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) on stuck-lane recovery. Document them now so you're not surprised mid-run.

---

<a name="d"></a>
## Part D — From probe to instance choice

You have `R_peak` (GB per lane). Now decide:

### D.1 — How many lanes do you want?

Lanes = parallelism. More lanes = faster wall-clock, but more RAM and CPU consumed.

| Total files (N) | Suggested lanes |
|---|---|
| N < 50 | 8 lanes |
| 50 ≤ N < 200 | 16 lanes |
| 200 ≤ N < 500 | 24 lanes |
| N ≥ 500 | 32 lanes |

These are starting points, not hard rules. **More lanes is not always better** — past ~32 you usually hit diminishing returns on a single box (disk contention, OS scheduling overhead).

### D.2 — Compute required instance RAM

Formula:
```
Required RAM (GB) = R_peak × lane_count × 1.3 (safety margin) + 16 (OS overhead)
```

The 1.3 multiplier accounts for: occasional spikes above the probe-measured peak, OS file cache, MATLAB Runtime overhead, and headroom for any other processes.

The +16 GB OS overhead is a safe minimum for Windows Server.

**Example calculations:**

If `R_peak = 12, lanes = 32`: `12 × 32 × 1.3 + 16 = 515 GB` → **r7a.16xlarge (512 GB) is borderline**, prefer **r7a.24xlarge (768 GB)** for headroom.

If `R_peak = 3, lanes = 8`: `3 × 8 × 1.3 + 16 = 47 GB` → **r7a.2xlarge (64 GB)** is plenty.

If `R_peak = 6, lanes = 16`: `6 × 16 × 1.3 + 16 = 141 GB` → pick **r7a.8xlarge (256 GB)** for comfortable safety, or r7a.4xlarge (128 GB) if you're willing to push it.

### D.3 — Verify vCPU is adequate

Rule of thumb: have at least as many vCPU as lanes, preferably ~2× to leave OS/IO headroom. All r-family instances have 4 GB RAM per vCPU, so picking by RAM usually gives you adequate CPU automatically. But verify:

| Instance | RAM | vCPU | Comfortable lane count |
|---|---|---|---|
| r7a.2xlarge | 64 GB | 8 | up to 4-8 lanes |
| r7a.4xlarge | 128 GB | 16 | up to 8-16 lanes |
| r7a.8xlarge | 256 GB | 32 | up to 16-32 lanes |
| r7a.16xlarge | 512 GB | 64 | up to 32 lanes (RAM-limited usually before CPU) |
| r7a.24xlarge | 768 GB | 96 | up to 32 lanes comfortably |
| r7a.32xlarge | 1024 GB | 128 | 32+ lanes |

### D.4 — Sizing summary table

| Your `R_peak × lanes` is roughly... | Pick this instance |
|---|---|
| < 30 GB | r7i.xlarge (32 GB) |
| < 50 GB | r7a.2xlarge (64 GB) |
| < 100 GB | r7a.4xlarge (128 GB) |
| < 200 GB | r7a.8xlarge (256 GB) |
| < 400 GB | r7a.16xlarge (512 GB) |
| < 600 GB | r7a.24xlarge (768 GB) |
| < 800 GB | r7a.32xlarge (1024 GB) |
| ≥ 800 GB | reduce lanes, run sequentially in batches, or rent multiple instances |

---

<a name="e"></a>
## Part E — Phase-by-phase sizing (the instance lifecycle)

Here's the typical instance journey for a single dataset. **You will resize multiple times.** Resizing is cheap and fast (3-5 min downtime; EBS persists).

### Phase 0 — Probe (~$1-3 total)

- Instance: **r7i.2xlarge** ($0.53/hour)
- Duration: 1-3 hours
- Purpose: measure R_peak, T_file, D_file on representative TIFFs

### Phase 1 — Detection (the expensive phase)

- Instance: from Part D table, sized to your data
- Duration: `(N_total / lanes) × T_file / 60` hours, plus overhead
- **Resize UP from probe** before this phase, **resize DOWN immediately** when it's done

### Phase 2 — CFU clustering (cheaper)

- Instance: same as detection box works (you may already be on it), or downsize to ~half-size. CFU is disk-bound; RAM headroom matters less
- Duration: ~5-15 minutes for ~1000 files (disk-throughput-limited)
- **Optional resize down** for CFU; often easier to run CFU back-to-back with detection on the same box

### Phase 3 — Consolidation + S3 upload

- Instance: **r7i.2xlarge** ($0.53/hour) — sync is network-bound
- Duration: hours for several TB of upload (network-limited)
- **Resize DOWN to r7i.2xlarge after CFU.** Single biggest cost-saving move

### Phase 4 — R analysis

- Instance: **r7i.4xlarge** (128 GB, 16 vCPU) is a safe default. Smaller if you're confident, larger only if modeling chokes
- Duration: highly variable (minutes for descriptive, hours for heavy modeling)
- **Resize UP from r7i.2xlarge before R, back DOWN after**

### Phase 5 — Idle / between sessions

- Option A — **stop the instance** entirely. EBS volume persists at $0.08/GB-month (~$100/month for a 12 TB volume), no compute charge. Good for hours-to-days gaps.
- Option B — **terminate** the instance and AMI-image it first. EBS gone, only AMI snapshot persists ($0.05/GB-month). Good for weeks-to-months gaps.
- Option C — leave running on r7i.2xlarge. ~$13/day. Only sensible for a few days of sync/light work.

### Phase 6 — Teardown

When the project is done: follow [`07_TEARDOWN_CHECKLIST.md`](07_TEARDOWN_CHECKLIST.md) and terminate.

### E.1 — Lifecycle visualized

```
  COST/hr ($)
    8 │                      ████ Detection
      │                      ████ (largest spend - keep brief!)
    6 │                      ████
      │                      ████
    4 │                      ████  ██ CFU
      │                      ████  ██ (medium)
    2 │              ┃       ████  ██       ┃        ██ R
      │       Probe  ┃       ████  ██       ┃        ██
   0.5│       ▒▒▒▒▒  ┃       ████  ██  ▒▒▒  ┃  ▒▒▒  ██  ▒▒▒  Idle
      │       (small)┃       ████  ██  ▒▒▒  ┃  ▒▒▒  ██  ▒▒▒  (small/stop)
    0 └───────────────────────────────────────────────────────────────► Time
           Phase 0  resize    Phase 1     Phase 2   Phase 3      Phase 4   Phase 5/6
                    UP                              resize DOWN  resize UP

  Total instance cost is dominated by Phase 1 width × height.
  Phases 0, 3, 4, 5 should all be on small/medium instances.
```

---

<a name="f"></a>
## Part F — How to actually resize (AWS Console)

Resizing an EC2 instance is straightforward but you need to **stop** the instance first (not terminate). The EBS volume and all data persist.

### F.1 — Step-by-step

1. **AWS Console → EC2 → Instances** → select your instance.
2. **Stop the instance:** Actions → Instance State → **Stop**. Wait until State shows "stopped" (~30 seconds to 2 minutes).
3. **Change type:** Actions → Instance Settings → **Change Instance Type**.
4. **Select the new instance type** from the dropdown. Confirm.
5. **Start the instance:** Actions → Instance State → **Start**. Wait for State="running" + Status Checks=2/2 passed (~2-3 minutes).
6. **Reconnect** via RDP. The new IP may differ (the public IP changes on stop/start unless you have an Elastic IP).
7. **Verify** the new instance type:
   ```powershell
   Get-CimInstance Win32_ComputerSystem | Select TotalPhysicalMemory, NumberOfLogicalProcessors
   ```
   `TotalPhysicalMemory / 1GB` should match the spec sheet.

### F.2 — Downtime budget

- Stop + change + start: typically **3-5 minutes total**
- Disk and all files are unchanged
- Running processes are **killed by Stop**; relaunch any active detection runs (which is fine because of the resume guard)

### F.3 — Resize while a job is running?

**You cannot resize a running instance.** You must stop it first. So if detection is running and you realize you need more RAM:

1. `Stop-Process -Name aqua_lane -Force` to kill workers cleanly
2. Stop the instance
3. Resize up
4. Start the instance
5. Re-launch the detection — resume guard skips completed files

This is annoying but recoverable. **The whole point of the probe phase is to size correctly the first time and avoid this.**

### F.4 — Limit / quota considerations

AWS imposes per-account quotas on large instance families. If you try to launch a huge box and get "InsufficientInstanceCapacity" or "VcpuLimitExceeded":

- Check **EC2 → Limits** in the console for your region
- Request a quota increase via the support center (often granted within hours)
- Workaround: use the next available size

---

<a name="g"></a>
## Part G — Disk/EBS sizing

EBS is the local disk on the instance — separate from instance type. You can resize it independently.

### G.1 — How much disk do you need?

For one dataset:

| Item | Size |
|---|---|
| Source TIFFs (kept locally) | `N × TIFF_size` |
| Detection output (per file) | ~2-3× TIFF size (movie + mat + csv + xlsx) |
| CFU output (per file) | ~10-30 MB |
| Working space / scratch | +20% safety |
| OS / installed software | ~80-100 GB baseline |

**Worked example:** for 500 files × 1 GB each = 0.5 TB source + 500 × 2 GB output = 1 TB detection + 10 GB CFU + 300 GB scratch + 100 GB OS = **~2 TB EBS** minimum.

For small probes: 200-500 GB is plenty.

### G.2 — Always use gp3

- **gp3**: ~$0.08/GB-month, configurable throughput up to 1000 MB/s, configurable IOPS up to 16000
- gp2: older, throughput tied to size, less flexible — don't use
- io2: high-performance, expensive, overkill
- st1 / sc1: throughput HDDs — too slow for AQuA2's random I/O patterns

**Use gp3, and set throughput to 1000 MB/s** if the CFU phase feels slow.

### G.3 — Resizing EBS

**Increasing volume size:** while the instance is running. AWS Console → EBS → Volumes → select volume → Actions → Modify Volume → enter new size → save. Then in Windows: Disk Management → right-click C: → Extend Volume. 5 minutes total.

**Decreasing volume size:** **not supported** by AWS. Create a new smaller volume, copy data over, swap. Rarely worth it.

**Configuring throughput / IOPS** (gp3 only): same Modify Volume dialog. Throughput up to 1000 MB/s makes CFU faster.

### G.4 — Cost vs convenience

| Volume size | Monthly cost (gp3 baseline) |
|---|---|
| 500 GB | ~$40 |
| 1 TB | ~$80 |
| 5 TB | ~$400 |
| 12 TB | ~$960 |

**Strategy:** start small (500 GB) for the probe. Expand before the big detection run. After data is in S3, terminate the instance and the EBS volume is deleted with it.

---

<a name="h"></a>
## Part H — Cost calculator

Worked example for a hypothetical user with:
- N = 200 files
- R_peak measured = 6 GB
- T_file measured = 4 minutes
- D_file measured = 1.5 GB

### H.1 — Phase budgets

**Phase 0 — Probe:** r7i.2xlarge × 2 hours = **$1.06**

**Phase 1 — Detection:**
- Lanes: 16 (200 files → ~12 per lane)
- Required RAM: `6 × 16 × 1.3 + 16 = 141 GB` → **r7a.4xlarge (128 GB)** is borderline → pick **r7a.8xlarge (256 GB)** for comfort
- Wall-clock: `(200 / 16) × 4 / 60 ≈ 0.85 hours`, call it 1 hour
- Cost: 1 hour × $2.04 = **$2.04**

**Phase 2 — CFU:** same box, ~15 minutes = **$0.51**

**Phase 3 — S3 sync:**
- Total upload: `200 × 1.5 = 300 GB`
- Resize to r7i.2xlarge first
- Time at ~80 MB/s effective sync rate: ~1 hour
- Cost: 1 hour × $0.53 = **$0.53**

**Phase 4 — R analysis:**
- r7i.4xlarge for 2 hours = **$2.12**

**Phase 5 — Idle:** stop the instance, EBS only.

**Total compute cost for one full run: ~$6.30 plus EBS time.**

### H.2 — Rough scaling rules

- **Detection cost scales roughly linearly with file count** (more files = more time on the same box)
- **Detection cost scales with R_peak via instance size** (heavier files need bigger box)
- **S3 storage cost scales with output size** (~$0.023/GB-month Standard, ~$0.001/GB-month Deep Archive)
- **One-shot compute > ongoing storage** for most projects

### H.3 — Optimization opportunities

In order of impact:

1. **Right-size the detection box** (Phase 1) — biggest dollar lever
2. **Downsize immediately after detection** — don't let the big box sit through CFU + sync at full price
3. **Use Deep Archive for cold backups** — 95% cost reduction for the same storage
4. **Stop the instance during idle periods** — EBS-only cost, not compute
5. **Spot instances** for non-critical runs — up to 70% cheaper but can be reclaimed mid-run

---

<a name="i"></a>
## Part I — Decision tree

```
Are you starting a new dataset?
├── YES → Phase 0: Probe on r7i.2xlarge with 3-5 representative TIFFs.
│         Measure R_peak, T_file, D_file. Then proceed to Detection.
│
└── NO, mid-pipeline → which phase?
    │
    ├── About to launch Detection?
    │   → Have you measured R_peak? If NO, go back and probe.
    │   → Use the Part D table to pick instance size.
    │   → Resize UP before launching.
    │
    ├── Detection just finished?
    │   → Verify completion (process count = 0, .mat count = N).
    │   → CFU can be on same box OR downsize first.
    │   → After CFU: downsize to r7i.2xlarge for sync.
    │
    ├── CFU done, syncing to S3?
    │   → You should already be on r7i.2xlarge. If not, downsize NOW.
    │   → Let sync run. Verify with `aws s3 ls --summarize` after.
    │
    ├── About to run R?
    │   → Resize UP to r7i.4xlarge if doing modeling.
    │   → r7i.2xlarge is fine for descriptive stats.
    │
    ├── R done, ready to wrap up?
    │   → Sync RESULTS to S3.
    │   → Either stop the instance (keep for later) or work the teardown checklist.
    │
    └── Hit an OOM or crash?
        → Stop-Process all workers, save the lane logs, resize UP.
        → Resume guard lets you re-launch safely.
```

### I.1 — When to abandon and re-strategize

Sometimes the right answer is "stop and rethink." Signals:

- **Per-lane RAM in the probe was much higher than expected.** Investigate: is `maxSize` too high for your activity level? Are TIFFs unusually large? Consider lowering `maxSize`, downsampling spatially, or processing fewer files at once.
- **A pathological file (or many) is hanging** the lane. Don't keep waiting — isolate, exclude or re-run at lower maxSize. See [`04_PIPELINE_OPERATIONS.md`](04_PIPELINE_OPERATIONS.md) on stuck-lane recovery.
- **Disk filling unexpectedly fast.** Movie generation can double output size; if you don't need movies, recompile `aqua_lane.m` with `movie=OFF`.
- **Wall-clock vastly exceeds the probe estimate.** Some files may be 10× heavier than your probe set. Inspect the slowest lanes' logs.

---

## Appendix — Quick sizing recipes by dataset profile

These are **starting points** for rough planning. Always confirm with a probe on your own data.

| Dataset profile | Probe | Detection | CFU | Sync | R |
|---|---|---|---|---|---|
| Small (N<50, ~512² TIFFs, low maxSize) | r7i.xlarge | r7a.2xlarge (64GB, 8 lanes) | same | r7i.xlarge | r7i.2xlarge |
| Medium (N~200-500, ~1024² TIFFs) | r7i.2xlarge | r7a.4xlarge or 8xlarge (16 lanes) | r7a.4xlarge | r7i.2xlarge | r7i.4xlarge |
| Large (N>500, ~1024² × 1500+ frames, maxSize=50000) | r7i.2xlarge | r7a.16xlarge or 24xlarge (32 lanes) | r7a.8xlarge | r7i.2xlarge | r7i.4xlarge |
| Very large (N>2000 or unusually big TIFFs) | r7i.2xlarge | r7a.32xlarge (32 lanes), or split dataset | same | r7i.2xlarge | r7i.4xlarge or 8xlarge |

**Spending $3 on a probe to avoid spending $50 on the wrong instance is the right tradeoff.**
