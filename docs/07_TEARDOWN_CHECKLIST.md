# 07 — Instance Teardown Checklist

Before terminating an EC2 instance you've used for pipeline work, work through this list to make sure no work is lost. Most steps are tiny S3 uploads (KB to MB); the cost of running them all is negligible. The cost of forgetting one is potentially hours of re-derivation.

---

## A. Decision: terminate or just stop?

**Stop the instance** (don't terminate) if:
- You expect to use the same EBS volume + installed software within days or weeks
- You're done for now but might pick up the project soon
- Cost: EBS storage only (~$0.08/GB-month for gp3), no compute

**Snapshot to AMI then terminate** if:
- You want to free the EBS volume but preserve the software setup for future re-launch
- You won't touch the project for months
- Cost: AMI snapshot storage (~$0.05/GB-month), much cheaper than live EBS

**Terminate without AMI** if:
- The project is permanently done
- You have all source files in S3 and all scripts in Git
- You'd start fresh if you ever revisit

The rest of this doc covers the **terminate** path (with or without AMI), since stop is trivial (no checklist needed).

---

## B. What's already safe (in S3 from prior steps)

If you followed the pipeline operations correctly, these are already in S3 and don't need re-uploading:

- ✓ Source TIFFs at `s3://<bucket>/CalciumImagingTIFFs/<dataset>/`
- ✓ Detection outputs at `s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>/`
- ✓ CFU outputs at `s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>_CFU/`
- ✓ R analysis outputs at `s3://<bucket>/CalciumImagingAnalysis/R_Analysis_Results/<DatasetName>/` (if you've completed that phase)

**Verify each one explicitly** before assuming it's safe. Run:
```powershell
aws s3 ls "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>/" --recursive --summarize | Select-Object -Last 2
(aws s3 ls "s3://<bucket>/CalciumImagingAnalysis/AQuA2_Outputs/<DatasetName>/" --recursive | Select-String '_AQuA2\.mat').Count
```
Counts should match what you remember from the original sync.

---

## C. What's NOT yet in S3 (the things you need to grab)

These are the things that typically aren't backed up automatically. Each category goes into a dedicated subfolder under a teardown-backup prefix:

```powershell
$BACKUP = "s3://<bucket>/CalciumImagingAnalysis/_Instance_Backup_<YYYY-MM>/"
```

### C.1 — Pipeline configuration

The `parameters_for_batch.csv` you used for this run, in case the values differ from defaults:
```powershell
aws s3 cp C:\AQuA2\cfg\parameters_for_batch.csv "$BACKUP/config/parameters_for_batch_used.csv"
```

### C.2 — Lane logs (provenance)

These document what actually ran. Tiny, invaluable for any future questions:
```powershell
# detection logs
aws s3 sync C:\Users\Administrator\Documents\<dataset>_v1\_lane_logs "$BACKUP/logs/<dataset>_detection_logs/"

# CFU logs (live in the hardcoded path - see Pitfalls 7)
aws s3 sync C:\Users\Administrator\Documents\CFU_lanes\_logs "$BACKUP/logs/<dataset>_CFU_logs/"
```

### C.3 — Pipeline scripts (only if you modified them since the repo version)

If you have a Git repo for the pipeline (recommended), the scripts are already there. But if you patched any scripts directly on the instance and didn't commit those changes back, grab them now:
```powershell
$scripts = @(
  "Launch-Lanes-Exe.ps1"
  "Build-CFU-Lanes.ps1"
  "Launch-CFU-Lanes.ps1"
  "Split-IntoLanes.ps1"
  "Consolidate-Template.ps1"
)
foreach ($s in $scripts) {
  $src = "C:\Users\Administrator\Documents\$s"
  if (Test-Path $src) {
    aws s3 cp $src "$BACKUP/scripts/$s"
  }
}
```

Compare against your Git repo afterward — if any differ, commit the on-instance versions as updates.

### C.4 — R analysis scripts (if not yet committed)

```powershell
Get-ChildItem C:\ -Recurse -Filter "*.R" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notlike "*Program Files*" -and $_.FullName -notlike "*\R-*\*" } |
  Select FullName | Format-Table -Auto
```
Identify the R analysis script(s) you used. Upload them and any helper R files:
```powershell
aws s3 sync C:\Users\Administrator\Documents "$BACKUP/r-scripts/" --exclude "*" --include "*.R"
```

### C.5 — Custom Fiji macros (if any)

```powershell
if (Test-Path C:\Fiji\macros\Custom) {
  aws s3 sync C:\Fiji\macros\Custom "$BACKUP/fiji-macros/"
}
```

### C.6 — MATLAB sources (only if modified or first-time backup)

If you've recompiled the workers or modified `.m` files:
```powershell
aws s3 sync C:\AQuA2\src "$BACKUP/matlab-src/" --exclude "*.exe" --exclude "*.dll"
```

### C.7 — Compiled exes (only if rebuilt)

If you rebuilt the exes (different version, different flags), back them up to S3 — they're not in Git (binaries don't belong there). If you didn't rebuild, the original exes are in the AMI (or wherever you got them from) and don't need re-backup.
```powershell
aws s3 sync C:\AQuA2\compiled "$BACKUP/compiled-exes/" --include "*.exe"
```

### C.8 — README files documenting this run

The per-dataset READMEs you wrote during S3 backup are already in S3 alongside the data. But if you wrote any additional notes, grab them:
```powershell
aws s3 sync C:\Users\Administrator\Documents "$BACKUP/notes/" --exclude "*" --include "README_*.txt" --include "*.md"
```

---

## D. Verify the backup

After all the syncs in Section C, verify everything is there:
```powershell
aws s3 ls $BACKUP --recursive --summarize | Select-Object -Last 2
aws s3 ls $BACKUP --recursive
```

Eyeball the listing — make sure you see content under `config/`, `logs/`, `scripts/`, `r-scripts/`, and any other categories you uploaded. If any look empty when they shouldn't be, fix before terminating.

---

## E. (Optional) Snapshot the AMI

If you want to be able to relaunch this exact software environment later:

1. **Stop the instance:** EC2 Console → Instances → select your instance → Actions → Instance State → Stop. Wait for State="stopped".
2. **Create image:** Actions → Image and templates → Create image
   - **Image name:** descriptive, e.g., `<lab>-aqua2-pipeline-v<N>`
   - **Image description:** what's installed, what's tested, what's the date
   - **No reboot:** unchecked (instance is already stopped)
   - **Create image**
3. Wait 10-20 minutes for the snapshot to complete (EC2 → AMIs in console; status goes from `pending` to `available`).
4. Note the AMI ID (`ami-xxxxx...`) somewhere persistent for future reference.

If your AMI contains a licensed-software install (e.g., full MATLAB), the AMI is **personal-use only** by license terms. Don't share publicly. Keep within the license-holder's permitted use.

---

## F. The actual termination

Once all backup is verified:

1. **Confirm everything you want is in S3:**
   ```powershell
   aws s3 ls $BACKUP --recursive --summarize | Select-Object -Last 2
   ```

2. **Double-check no compute is still running anywhere in your account** (cross-instance check):
   ```powershell
   aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table
   ```
   Should show only this instance (or nothing if you already stopped it).

3. **Terminate via AWS Console:** EC2 → Instances → select instance → Actions → Instance State → Terminate. Confirm.

4. **The attached EBS volume is deleted automatically** (the root volume default). If you had additional EBS volumes attached, you'll be prompted whether to delete them too.

5. **Allow a few minutes** for AWS to process. Instance moves to "terminated" state; eventually disappears from the active list.

---

## G. After termination

A few cleanup items that aren't urgent but worth knowing:

**AMIs you created:** persist until you delete them. Periodically check EC2 → AMIs and delete ones you no longer need (snapshot storage costs accumulate).

**S3 lifecycle policies:** consider setting a policy that auto-transitions old data to cheaper storage classes after some time. AWS Console → S3 → bucket → Management → Lifecycle rules. For example: transition everything older than 90 days from Standard to Standard-IA, then to Glacier after 180 days. Saves significant money on long-tail storage.

**Cost monitoring:** AWS Cost Explorer can show you the running totals. Worth a glance monthly. EBS snapshot costs especially can sneak up if you've accumulated many AMI versions.

**Documentation update:** if you made any improvements to the pipeline during this run (script fixes, new pitfalls discovered, parameter changes), update the Git repo so the next user benefits.

---

## H. Re-launching from your AMI later

If you keep an AMI and want to spin up a new instance from it:

1. EC2 Console → AMIs → select your AMI → Launch instance from AMI
2. Pick instance type (consult [`03_SIZING_AND_RESIZING_GUIDE.md`](03_SIZING_AND_RESIZING_GUIDE.md))
3. Attach your IAM role (`EC2-to-S3-Full` or equivalent) for S3 access
4. Network/storage settings: same as before, or adjusted per your new dataset
5. Launch

After RDP-ing in, the first thing to do is **pull the latest pipeline scripts from your Git repo:**
```powershell
cd C:\Users\Administrator\Documents
git clone https://github.com/<your-org>/<your-repo>.git pipeline-repo
cd pipeline-repo
git pull   # if cloned previously
```

If your AMI has a `Run-First.ps1` on the Desktop that automates this, run that instead.

Then verify the environment (see [`02_INFRASTRUCTURE_SETUP.md`](02_INFRASTRUCTURE_SETUP.md) Part H) and proceed with whatever new work brought you back.
