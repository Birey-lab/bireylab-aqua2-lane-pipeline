# 02 — Infrastructure Setup

What you need installed on the compute side, how to set up cloud storage, and how to authenticate cleanly. This is the one-time setup before the first run; you won't redo most of this for subsequent datasets.

---

## A. Software stack on the compute instance

The pipeline runs on **Windows** (Server 2022 or 2025 recommended). The full stack:

| Software | Version (tested) | Purpose | Cost |
|---|---|---|---|
| Windows Server | 2022 / 2025 | OS | Standard EC2 pricing |
| MATLAB Runtime | **R2026a** (must match the version the `.exe`s were compiled with) | Required to run `aqua_lane.exe` / `cfu_lane.exe` | Free |
| AQuA2 | v3+ | The actual detection/CFU algorithms | Free (open source) |
| MATLAB (full) | **R2026a Update 2** (the version the current workers were built with) | **Only needed to compile workers** | License required |
| MATLAB Compiler toolbox | matching MATLAB version | **Only for compilation** | License required |
| R | 4.5+ | Downstream analysis | Free |
| `rhdf5` R package | 2.50+ | Reading MATLAB v7.3 `.mat` files in R | Free (Bioconductor) |
| Fiji / ImageJ | latest | TIFF preprocessing (trimming, conversion) | Free |
| AWS CLI v2 | latest | S3 transfers | Free |
| rclone | 1.74+ | Optional: mount S3 as a drive letter | Free |
| WinFsp | 2.0+ | Required by rclone for S3 mounting | Free |
| Git for Windows | latest | Optional but recommended | Free |

**Distinction worth emphasizing:** the *full MATLAB* + *Compiler toolbox* are only needed by **one person, once**, to produce the worker `.exe` files. Everyone else (and every subsequent instance) only needs the free **MATLAB Runtime**, which has no license restriction.

---

## B. Three paths to a working compute environment

### Path 1: Use an AMI (Amazon Machine Image) — fastest

If your lab/institution has a pre-built AMI with this stack installed, launch from that. Snapshot-based; one-click recreation. License caveats: if the AMI includes a full MATLAB installation tied to an individual license, that AMI is personal-use only and cannot be shared outside the license holder's permitted use.

### Path 2: Build your own AMI — one-time investment

Launch a fresh Windows Server EC2 instance, install everything from the stack table, validate, then snapshot it as an AMI. Subsequent launches use that AMI. ~half-day to set up properly.

Order of installation:
1. Windows updates
2. AWS CLI v2 (so you can pull software from S3 if needed)
3. R + RStudio
4. Fiji
5. rclone + WinFsp
6. MATLAB Runtime (download from MathWorks — **R2026a**, matching the version the current `.exe`s were compiled with; a mismatched Runtime won't run them)
7. AQuA2 (clone from `https://github.com/yu-lab-vt/AQuA2`)
8. Place compiled `.exe`s at `C:\AQuA2\compiled\`
9. Place `parameters_for_batch.csv` at `C:\AQuA2\cfg\`
10. (Optional) Clone this pipeline repo to `C:\Users\Administrator\Documents\pipeline-repo`
11. Test by running the probe protocol on a small set of files (see Sizing Guide Part C)
12. Stop the instance, snapshot as AMI

### Path 3: Install from scratch each time — not recommended

You can install the full stack on every fresh instance, but it takes hours each time. Only viable if you're running this rarely. The AMI approach is the right amortized investment.

---

## C. S3 bucket setup

You'll need at least one S3 bucket to store:
- Source TIFFs (the input)
- Detection results (the bulk of the storage — multi-GB per recording)
- CFU results (small)
- R analysis outputs
- (Optional) frozen archive of older parameter runs

### Recommended bucket layout

```
s3://<your-bucket>/
├── CalciumImagingTIFFs/                                    ← source data
│   └── <dataset-name>/                                     ← e.g. by donor, age, condition
│
└── CalciumImagingAnalysis/
    ├── AQuA2_Outputs/
    │   ├── <DatasetName>_MaxSize<value>/                  ← detection results (Standard)
    │   ├── <DatasetName>_MaxSize<value>_CFU/              ← CFU results (Standard)
    │   └── Archive/
    │       └── <DatasetName>_<old_params>/                ← old runs (Deep Archive)
    │
    └── R_Analysis_Results/
        └── <DatasetName>_MaxSize<value>/                  ← R outputs
```

The double-`MaxSize<value>` suffix in folder names lets you keep multiple parameter runs side by side (e.g., `Dataset_MaxSize2000/` and `Dataset_MaxSize50000/`).

### Region choice

**Put the bucket in the same region as your EC2 instance.** EC2-to-S3 transfer within the same region is free; cross-region transfer is metered. For most US users this means `us-east-2` (Ohio), `us-east-1` (N. Virginia), or `us-west-2` (Oregon).

### Storage classes

| Class | Cost/GB-month | When to use |
|---|---|---|
| Standard | ~$0.023 | Active datasets, recent results |
| Standard-IA | ~$0.0125 | Datasets you access monthly or less |
| Glacier Instant | ~$0.004 | Rarely-touched but want fast retrieval |
| Deep Archive | ~$0.001 | Cold archive, 12h retrieval OK, 180-day minimum |

For active work, **Standard**. After a paper is published and you have no more analysis to do, move artifacts to **Deep Archive** to drop storage cost by ~95%.

### Create the bucket

AWS Console → S3 → Create bucket. Pick a globally-unique name (your-lab-name is typical), choose your region, leave defaults for everything else except:
- Enable versioning if you want safety nets for accidental deletions (recommended)
- Leave public access blocked (default — never make these buckets public)

---

## D. IAM role for the EC2 instance

The cleanest way for your EC2 instance to access S3 is via an **IAM role** attached to the instance. No access keys to manage, credentials never appear in scripts.

### Create the role

AWS Console → IAM → Roles → Create role:
- **Trusted entity:** AWS service → EC2
- **Permissions:** attach `AmazonS3FullAccess` (or build a tighter custom policy that grants access only to your specific bucket — better practice)
- **Name:** something descriptive like `EC2-to-S3-Full` or `BireyLab-S3-Access`
- Create role

### Attach the role to instances

When launching a new instance: in the "Configure instance" step, select your IAM role from the IAM instance profile dropdown.

For an existing instance: EC2 Console → select instance → Actions → Security → Modify IAM role → pick your role.

### Verify the role works

After attaching, from the instance run:
```powershell
aws sts get-caller-identity
```
Should return a JSON blob with your account ID and the role's assumed-role ARN. If it errors with "Unable to locate credentials," the role isn't attached correctly.

Then test bucket access:
```powershell
aws s3 ls s3://<your-bucket>/
```
Should list bucket contents (or be empty, but no permission error).

---

## E. Optional: rclone mount for convenience

`aws s3 cp/sync` is the right tool for batch transfers, but for browsing S3 like a regular drive (Windows Explorer, double-clicking files), rclone + WinFsp mounts S3 as a drive letter.

After installing both, configure an rclone remote:
```powershell
rclone config
```
Walk through the prompts:
- Name: `s3_emory` (or whatever you like)
- Type: `s3` (Amazon S3 Compliant Storage Providers)
- Provider: `AWS`
- `env_auth`: **true** (use the IAM role; no keys needed)
- Leave `access_key_id` and `secret_access_key` blank
- Region: match your bucket's region
- Accept defaults for the rest

Then mount S3 as drive `X:`:
```powershell
rclone mount s3_emory:<your-bucket> X: --vfs-cache-mode writes --daemon
```

Now `X:\` in PowerShell or Explorer maps to your bucket. Useful for visual browsing; **don't** use it for large batch transfers (use `aws s3 sync` instead).

---

## F. EBS (local disk) sizing

The EC2 instance comes with an EBS volume serving as its `C:\` drive. Size it for:

- **Source TIFFs:** `N_files × avg_TIFF_size`
- **Detection output:** ~2-3× source TIFF size (the `_AQuA2.mat` + CSV + movie can be larger than the input)
- **Working space:** 20% extra safety margin
- **OS + installed software:** ~80-100 GB baseline

For a representative case: 1000 recordings × 1.5 GB each = 1.5 TB source + 3-4 TB output = ~6 TB. Add OS + safety = **8-12 TB EBS** for processing 1000 files comfortably.

For smaller workloads (10s-100s of files), 500 GB-1 TB is plenty.

**Use `gp3`** (general-purpose SSD), not gp2. It's cheaper at the same performance, and lets you tune throughput independently:
- Default: 125 MB/s throughput
- Pipeline-tuned: 1000 MB/s throughput (recommended for the CFU phase, which is disk-bound)
- Pricing: ~$0.08/GB-month base + small fees for throughput/IOPS above defaults

EBS volumes can be **resized larger online** (no instance restart). Shrinking is not supported — you must create a new smaller volume and migrate, so err on the larger side.

---

## G. Cost overview

Prices below are rough on-demand figures (2026, us-east-2) and are **illustrative only** — AWS rates change and are not consistent across every doc here. Confirm the current rate on the [AWS pricing page](https://aws.amazon.com/ec2/pricing/on-demand/) before a long run. Expect roughly:

| Phase | Instance | Hourly | For ~1000 files |
|---|---|---|---|
| Probe (3-5 files) | r7i.2xlarge | ~$0.53 | ~$1-3 |
| Detection (~1000 files, 32 lanes) | r7a.24xlarge | ~$6.12 | ~$25-50 (4-8 hours) |
| CFU (~1000 files) | r7a.8xlarge | ~$2.04 | ~$1 (30 min) |
| S3 sync, cleanup | r7i.2xlarge | ~$0.53 | ~$1-2 |
| R analysis | r7i.4xlarge | ~$1.06 | $2-10 depending on workload |
| **Idle (instance stopped, EBS only)** | — | EBS only, ~$0.11/hour per TB | $0/hour compute |

Plus ongoing S3 storage (~$70-100/month per fully-replicated dataset at Standard, much less in Archive).

Detailed cost calculator in [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md) Part H.

---

## H. Final pre-flight check

Before running the actual pipeline on a real dataset, validate the instance has everything it needs:

```powershell
# software checks
Test-Path "C:\AQuA2\compiled\aqua_lane.exe"
Test-Path "C:\AQuA2\compiled\cfu_lane.exe"
Test-Path "C:\AQuA2\cfg\parameters_for_batch.csv"
Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
Test-Path "C:\Program Files\MATLAB\MATLAB Runtime"

# AWS auth
aws sts get-caller-identity
aws s3 ls s3://<your-bucket>/

# disk space
Get-PSDrive C | Select @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}
```

All `Test-Path` should return `True`. `aws` commands should succeed without "Unable to locate credentials" errors. Free disk space should be comfortable for your planned dataset.

If anything fails, fix it before proceeding to sizing and pipeline operations.
