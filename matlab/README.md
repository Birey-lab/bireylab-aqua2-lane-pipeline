# MATLAB worker sources

The real `.m` source files for the two compiled workers that drive the pipeline.

| File | Lines | Role |
|---|---|---|
| `aqua_lane.m` | 491 | Detection worker — reads TIFFs, calls AQuA2 detection, writes `_AQuA2.mat` + CSV + XLSX + movie |
| `cfu_lane.m` | 129 | CFU clustering worker — reads detection results, runs CFU clustering, bakes results in-place + writes standalone `_res_cfu.mat` |

> **Not in this repo: `aqua_cmd_batch_lane.m`.** The legacy
> [`powershell/Launch-Lanes.ps1`](../powershell/Launch-Lanes.ps1) launcher (the
> pre-compiled, license-consuming path) calls a script named
> `aqua_cmd_batch_lane.m`. That file is intentionally **not committed** here — the
> compiled `aqua_lane.m` path replaced it. If you must run the legacy launcher,
> recover the script from the S3 `_PipelineArtifacts/` archive. For all normal use,
> use `aqua_lane.exe` via `Launch-Lanes-Exe.ps1` / `Run-Pipeline.ps1`.

## How these get used

These `.m` files are **compiled** into Windows executables (`aqua_lane.exe`, `cfu_lane.exe`) via MATLAB Compiler (`mcc`), then placed at `C:\AQuA2\compiled\` on the EC2 instance. The compiled exes run on the free MATLAB Runtime — **no MATLAB license consumed per worker**, which is the unlock for high parallelism.

## Compiling

You need a machine with:
- MATLAB R2026a (or whatever version your Runtime targets) — full installation
- MATLAB Compiler toolbox
- The AQuA2 source tree on the MATLAB path

Then:

```matlab
addpath(genpath('C:\AQuA2'));   % AQuA2 source
mcc -m aqua_lane.m -o aqua_lane -d C:\AQuA2\compiled
mcc -m cfu_lane.m  -o cfu_lane  -d C:\AQuA2\compiled
```

Each `mcc` call takes ~5-10 minutes.

The compiled exes only need to be rebuilt when:
- You change the worker `.m` files themselves (worker behavior change)
- You upgrade MATLAB to a new major version (Runtime mismatch)

For normal pipeline use, just use the existing exes.

## What's baked in vs. external

**Baked into the exes at compile time:**
- The decision flags in `aqua_lane.m`: `movie=ON`, `risingMaps=OFF`, `parpool=disabled`, `resume+per-file-guard=ON`
- The decision flags in `cfu_lane.m`: `whetherUpdateRes=true`, `whetherOutputCFURes=true`
- The CFU clustering thresholds in `cfu_lane.m`: `overlapThr=0.5`, `minNumEvt=3`, `maxDist=10`, `pValueThr=1e-5`, `cfuNumThr=3`

**Read at runtime (no recompile needed):**
- Per-recording parameters via `C:\AQuA2\cfg\parameters_for_batch.csv` (or any path passed as 3rd arg to `aqua_lane`)

So most parameter changes don't require recompilation — just edit the CSV.

## See also

- The full AQuA2 source tree (which these workers call into) lives at `https://github.com/yu-lab-vt/AQuA2` and was archived in S3 at `_PipelineArtifacts/2026-06-03/AQuA2-full/` for the version that produced this lab's results.
- Compilation metadata for the existing exes (`buildresult.json`, `mccExcludedFiles.log`, etc.) is in S3 at `_PipelineArtifacts/2026-06-03/compiled/`.
