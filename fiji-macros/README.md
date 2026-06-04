# Fiji / ImageJ macros

Custom macros for preprocessing TIFFs before the AQuA2 pipeline runs. All are written in ImageJ macro language (`.ijm`) and run from inside Fiji.

| Macro | What it does |
|---|---|
| `LIF_Extractor_Consolidated_v2.0.ijm` | Convert Leica `.lif` files to multi-frame TIFFs. Handles batch extraction across many series/recordings. |
| `AQUA2_movie_timestamp_batch_v8.ijm` | Add timestamps to the output movies AQuA2 produces. Useful for figure preparation. |
| `Custom/TrimTIF_Frames.ijm` | Trim the first N / last N frames from a TIFF stack. Useful for removing bleach-correction artifacts or stimulus-onset frames. |
| `Custom/LIFtoTIF_Middle60trimmer.ijm` | Specialized `.lif` → `.tif` converter that auto-trims to the middle 60% of the recording duration. |

## How to use

In Fiji: **Plugins → Macros → Run...** → pick the `.ijm` file → it executes in the active Fiji session.

For batch use, drop the macro file in `C:\Fiji\macros\` and it appears in the Macros menu directly.

For headless / scripted use, invoke from the command line:
```cmd
"C:\Fiji\ImageJ-win64.exe" --headless -macro path\to\macro.ijm "input_arg|other_arg"
```

## Notes

- These macros have **hardcoded path assumptions** in many places (`C:\Users\Administrator\Documents\...`). Read each macro before running on a new system; you'll likely need to edit paths.
- The `Custom/` subdirectory mirrors the `C:\Fiji\macros\Custom\` location on the production EC2 instance.
- Older versions of `AQUA2_movie_timestamp_batch` (`(4)` and `(7)` numbered iterations) are archived in S3 at `_PipelineArtifacts/2026-06-03/instance-scripts/fiji-macros/`. Only the latest (`v8`) is shipped here.
