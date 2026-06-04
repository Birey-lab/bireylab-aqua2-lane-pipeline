# Fiji Macros for BireyLab AQuA2 Pipeline

Three custom `.ijm` macros for the imaging pipeline. As of v3.0 (2026-06-04), **every operational parameter is prompted at runtime** — no editing source files just to change a frame count or a trim window. Cosmetic settings are controlled via **preset modes** where they exist.

## The three macros

| Macro | Purpose | Notable features |
|---|---|---|
| `LIF_Extractor.ijm` | Recursive `.lif` → TIFF with optional trim | Resume-safe (3 levels), optional UNTRIMMED-only mode, sibling-or-mirrored output, configurable rate-mismatch policy |
| `AQUA2_Movie_Timestamp.ijm` | Add elapsed-time stamps to AQuA2 output movies | Preset modes (Presentation / Compact / Minimal / Custom), GIF or AVI output, real-time-correct timestamps even with speedup |
| `TrimTIF_Frames.ijm` | Trim FINAL N frames from existing TIFFs | Simple prompts, preserves frame-interval metadata |

## Design principles

1. **No hardcoded parameters.** Every value that affects what the macro does is prompted at runtime. The default values reflect the BireyLab standard protocol (60s trim at 15s into recording, 20 Hz acquisition, etc.), so for typical use you can press Enter through the dialogs.
2. **Preset modes for cosmetic settings.** Where a macro has many cosmetic knobs (font, contrast, etc.), they're grouped into named presets ("Presentation" / "Compact" / "Minimal" / "Custom"). You pick one, the macro fills in matching defaults, and you can override individual values in the second dialog if needed.
3. **Resume-safe by default.** Macros that produce per-file outputs check for existing output before processing, so re-running picks up where it left off.
4. **Originals are never modified.** Every macro writes to a separate output folder. If you accidentally point input and output at the same folder, the macro will refuse for files where output and input collide.
5. **Versioned and tracked in Git.** The canonical source for these macros lives at `https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline` under `fiji-macros/`. Each macro carries a `VERSION` string and a changelog block. When you edit, update both.

## Running

Three ways:

1. **From Fiji's Plugins menu:** Plugins → Macros → Run... → pick the `.ijm` file
2. **Direct from `C:\Fiji\macros\`:** if dropped here, they appear in the Macros menu of Fiji
3. **Headless / scripted:** `"C:\Fiji\ImageJ-win64.exe" --headless -macro path\to\macro.ijm` (note: the macros use `getDirectory()` and `Dialog.create()` prompts, so they're not currently fully headless — would need a wrapper macro that hardcodes paths and calls these as functions)

## What each macro asks you

### `LIF_Extractor.ijm`

1. **Choose root input folder** — recursive scan starts here
2. **Operational dialog**:
   - Trim start (seconds into recording)
   - Target trim length (seconds; 0 = skip trim, save UNTRIMMED only)
   - Output mode (sibling-to-LIF or mirrored)
   - Rate mismatch policy (warn-and-save or drop)
   - TileScan filter on/off
3. **Choose root output folder** — only if mirrored mode chosen

Defaults reproduce the lab's standard 60s @ 15s sibling-output run with rate warnings (the v2.0 behavior).

### `AQUA2_Movie_Timestamp.ijm`

1. **Preset choice**: Presentation / Compact / Minimal / Custom
2. **Choose input and output folders**
3. **Operational dialog**:
   - Acquisition FPS (rate of the source recording — must match the data)
   - Speedup factor (how many times faster than real-time, via frame decimation)
   - Playback FPS (display rate of output)
   - Output format (gif or avi)
   - Output layout (flat with prefixed names, or mirror input subfolders)
4. **Advanced dialog** (only shown for "Custom" preset): font size, decimals, text position, autoContrast, saturated %, JPEG quality, filename suffix

### `TrimTIF_Frames.ijm`

1. **Choose input folder** (TIFFs)
2. **Choose output folder**
3. **Frames to keep** (defaults to 2400)
4. **Output filename suffix** (optional; blank = same name)

## Behavior notes

**Rate-mismatch handling (LIF Extractor):** if a series has a different acquisition rate than the first valid series seen in the run, you choose what happens:
- "Warn but save" (default, recommended) — both the standard and the mismatched series are extracted; the log shows `[WARN-RATE]`. Good when you intentionally mix rates within a dataset.
- "Drop the series" — mismatched series are skipped entirely, logged as `[DROP-RATE]`. Conservative, prevents accidental mixing.

**Speedup via decimation (Timestamp Macro):** when you set "speedup = 5", the macro keeps only every 5th frame, not "plays back 5x faster." This preserves GIF playback (which can't reliably go above ~50 fps) and keeps file sizes small. The displayed times remain physically correct because they're computed from the original frame numbers before decimation.

**TileScan filter (LIF Extractor):** series named `TileScan_*` are skipped by default *unless* the name also contains `Merging`. This matches Leica's naming convention for stitched outputs. Disable the filter if your `.lif` files use different naming.

**Resume safety (LIF Extractor):**
- Per-LIF: if the per-LIF output folder already has the expected number of TIFFs, the whole LIF is skipped (`[SKIP-DONE]`)
- Per-series: if a specific series TIFF already exists, just that series is skipped
- The macro pre-flights zero-byte LIF files and logs `[FAIL]` without crashing the batch

## Edge cases and known limitations

1. **`Dialog.create()` requires Fiji's GUI.** These macros aren't fully headless without modification (would need `getArgument()` parsing). For now, run interactively.

2. **Corrupt input files** can still kill the batch if Bio-Formats throws an exception inside `run("Bio-Formats Importer", ...)`. The pre-flight zero-byte check catches truncation, but a malformed (non-zero) LIF will still bring down the run. Workaround: move the bad file out and re-run; resume safety picks up automatically.

3. **Bio-Formats version drift.** Fiji's auto-updater occasionally bumps Bio-Formats to a version that changes metadata field names. **Say No to Fiji updates on this AMI** as the default. If you need an update, do it deliberately and re-test the macros.

4. **GIF playback rate is capped** at ~50 fps in most viewers. If you set Playback FPS > 50 with GIF output, the file is valid but viewers will throttle. Stick to ≤50 or switch to AVI.

5. **Output paths with spaces or non-ASCII characters** can occasionally trip up `saveAs("Tiff", ...)`. Stick to plain ASCII paths if possible.

## Updating macros

These are tracked in Git. To update on the AMI:

```powershell
cd C:\Users\Administrator\Documents\pipeline-repo
git pull
Copy-Item fiji-macros\*.ijm C:\Fiji\macros\ -Force
```

That's it. To contribute changes back, edit on your Mac in the repo, test, commit, push.
