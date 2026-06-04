# Pipeline orchestration scripts

These are the **real PowerShell scripts** as run in production on the EC2 Windows instance. Each is parameterized via `param()` blocks but ships with **hCO-flavored default paths** (`C:\Users\Administrator\Documents\hCO_lanes`, etc.) reflecting the dataset they were most recently used on. **Always pass explicit `-Source`, `-LaneRoot`, etc., when running on a different dataset.**

## Scripts

| Script | Role |
|---|---|
| **`Run-Pipeline.ps1`** | **One-command orchestrator** — runs everything from split → detection → CFU with auto-sizing and real-time progress. The recommended entry point for typical runs. |
| `Get-Instance-Capacity.ps1` | Read-only report of current instance: vCPU, RAM, disk type, instance type. Run this first to know what you're working with. |
| `Auto-Size-Lanes.ps1` | Profile one TIFF through `aqua_lane.exe` and compute the safe number of parallel lanes for this instance. Saves you from "guess and iterate." See [Operations Playbook §1.7](../docs/08_OPERATIONS_PLAYBOOK.md). |
| `Split-IntoLanes.ps1` | Greedy size-balanced split of TIFFs into N lane folders for parallel processing |
| `Launch-Lanes-Exe.ps1` | Launch N parallel `aqua_lane.exe` workers for detection |
| `Build-CFU-Lanes.ps1` | Build NTFS-junction-based CFU lane folders (no data copying) |
| `Launch-CFU-Lanes.ps1` | Launch parallel `cfu_lane.exe` workers for CFU clustering |
| `Consolidate-Template.ps1` | Generic template for flattening lane-organized output into per-stem folders (dataset-specific consolidate scripts live in each case study's `scripts/` folder) |
| `Launch-Lanes.ps1` | **Historical reference** — the pre-compilation version of the detection launcher, used `matlab -batch` instead of `.exe`. Kept for reference; not the recommended approach (license-bound, slow startup) |

## Quick usage

All scripts have inline `<#  .SYNOPSIS / .EXAMPLE  #>` blocks. Read those for current usage.

**Simplest — one command (default: split + detect, stops for review):**

```powershell
.\Run-Pipeline.ps1 -InputTIFFs C:\path\to\AllTIFFs -OutputRoot C:\path\to\dataset
```

That auto-sizes lanes, splits TIFFs, runs detection, then stops. Pre-flight summary prints first; you confirm with Y to proceed.

After reviewing detection results, continue to CFU:

```powershell
.\Run-Pipeline.ps1 -OutputRoot C:\path\to\dataset -Split $false -Detect $false -CFU $true
```

Full end-to-end including S3 upload, no confirmation prompt:

```powershell
.\Run-Pipeline.ps1 -InputTIFFs C:\path\to\AllTIFFs -OutputRoot C:\path\to\dataset `
                   -CFU $true -Upload $true -S3Prefix s3://... -Force
```

For a custom parameters_for_batch.csv (different `maxSize`, `frameRate`, etc. per dataset):

```powershell
.\Run-Pipeline.ps1 -InputTIFFs ... -OutputRoot ... -ConfigCSV C:\my_params.csv
```

The orchestrator backs up the existing default CSV before swapping in yours.

**Step-by-step (if you want to inspect intermediate state):**

0. `Auto-Size-Lanes.ps1 -ProbeFolder <TIFFs>` ← profiles one file, tells you the safe N
1. `Split-IntoLanes.ps1 -Source ... -LaneRoot ... -Lanes N` (dry-run first, then `-Execute`)
2. `Launch-Lanes-Exe.ps1 -LaneRoot ... -ResultsRoot ... -Lanes N`
3. ... wait for detection ...
4. `Build-CFU-Lanes.ps1 -Root ... -LaneRoot ... -Lanes M -Execute` (M usually ~0.75×N)
5. `Launch-CFU-Lanes.ps1 -LaneRoot ... -Post ... -LogDir ...` ← **pass `-LogDir` explicitly to avoid overwriting prior logs** (see [Pitfall 7](../docs/06_PITFALLS_AND_RECOVERY.md))
6. ... wait for CFU ...
7. Consolidate (use the case study's specific consolidator as a template; adapt to your paths)

## Notes

- **Compiled `.exe` workers don't suffer from the `matlab -batch` quote-mangling issue** (Pitfall 2). The real `Launch-Lanes-Exe.ps1` and `Launch-CFU-Lanes.ps1` use `Start-Process` directly, not `cmd /c`. This is correct.
- All scripts default to **dry-run mode** when destructive (need `-Execute` to actually move/symlink). Run dry first, eyeball the plan, then re-run with `-Execute`.
- Resume-safety: re-running any launcher skips already-completed files.
