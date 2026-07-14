# cfg/presets — named detection-parameter sets

Each `*.csv` here is a complete AQuA2 `parameters_for_batch.csv` saved under a
memorable name. Because they live in the repo, a preset you save is **versioned,
diff-able, and travels to every instance via `git pull`** — so "the C4 parameter
set" is one file everyone can review and reuse, instead of a CSV someone edited
by hand and forgot.

## Use a preset
```powershell
.\Run-Pipeline.ps1 -ProjectName MyRun -ParamPreset C4 ...
```
`-ParamPreset C4` uses `cfg/presets/C4.csv` as the detection config (it's sugar for
`-ConfigCSV cfg\presets\C4.csv`). The orchestrator still prints the full parameter
table and, without `-Force`, asks you to confirm before detection.

## Save the current active CSV as a preset
```powershell
.\Save-Preset.ps1 -Name C4
# snapshots C:\AQuA2\cfg\parameters_for_batch.csv -> cfg\presets\C4.csv
```

## Where the durable record lives (NOT git)
The authoritative record of "what parameters produced a run" is **not** a committed
preset -- it's the CSV that `Run-Pipeline` copies into each run's output:
`for_upload/<Project>_parameters_for_batch_USED.csv`, which is uploaded to S3 with
the data. So provenance always travels with the results, no git required.

Presets here are just a **convenience for selecting/reusing** a named set on an
instance. Committing one (`git add/commit/push`) is *optional* -- only do it if you
deliberately want that named set on OTHER instances or baked into the next AMI, and
be careful running git from an instance (make sure it's on an up-to-date branch).

## Notes
- A preset is the *whole* CSV (all rows, `File1` = the active column).
- The GUI (`New-Run.ps1`) is the easiest way to make/adjust presets: load one into
  the editable parameter grid, change any value inline, and click **Save as
  preset...** to write a new `cfg/presets/<name>.csv` (it only rewrites the File1
  values, preserving the CSV's exact format). Reuse it from the dropdown.
