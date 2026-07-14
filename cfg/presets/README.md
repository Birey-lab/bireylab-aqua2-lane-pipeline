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
Then commit it so it's shared:
```powershell
git add cfg/presets/C4.csv && git commit -m "preset: C4" && git push
```

## Notes
- A preset is the *whole* CSV (all rows, `File1` = the active column). Editing a
  preset = editing that file.
- `Run-Pipeline` archives the exact CSV used into each run's `_logs/run_*/`
  (`parameters_for_batch_USED.csv`), so provenance travels with the data too.
- The interactive wizard (`New-Run.ps1`) lets you pick a preset from a menu and
  shows its values before you commit to a run.
