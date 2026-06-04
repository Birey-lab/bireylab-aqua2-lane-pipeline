// =====================================================================
//  AQUA2 Movie  ->  Timestamped Video  (Batch Converter, recursive)
//  ImageJ / Fiji macro  (.ijm)
//  VERSION: 2.0   (2026-06-04)
//  REPO:    https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline
// ---------------------------------------------------------------------
//  Walks the input folder AND all subdirectories, finds every multi-page
//  TIFF, optionally auto-contrasts and speeds it up, burns an elapsed-
//  time stamp (in seconds, computed from the REAL acquisition rate) into
//  each frame, and saves a presentation-ready movie of each one into the
//  output folder. Originals are never modified.
//
//  WHAT'S NEW IN v2.0
//    - NO HARDCODED PARAMETERS. All operational settings (input/output
//      folders, acquisition rate, speedup, format) prompted at runtime.
//    - PRESET MODES for cosmetic settings:
//        "Presentation"  - GIF, large font, autoContrast, 5x speedup
//        "Compact"       - AVI JPEG, smaller font, 10x speedup
//        "Minimal"       - GIF, small font, no autoContrast, 1x speedup
//        "Custom"        - opens advanced dialog for full control
//      The preset only sets the cosmetic defaults; operational params
//      are always prompted regardless of preset.
//
//  OUTPUT FORMAT:
//    "gif"  - Animated GIF. Easiest for PowerPoint: Insert > Picture and
//             it autoplays + loops. No codec issues across machines.
//    "avi"  - JPEG-compressed AVI. Smaller files for long movies, but
//             needs a codec on the target machine.
//
//  SPEEDUP works by decimating (keeping every Nth frame), not by
//  inflating playback rate. Preserves GIF compatibility (GIFs cap near
//  50 fps on most viewers) and keeps file sizes small. Timestamps remain
//  physically correct because they're computed from the original frame
//  numbers and the real acquisition rate before decimation.
// ---------------------------------------------------------------------
//  CHANGELOG
//    v2.0   (2026-06-04)
//      - NO HARDCODED PARAMETERS. All operational settings prompted.
//      - Added preset modes for cosmetic settings.
//      - Combined recursive walk + flat-vs-mirrored output into a
//        single 'Output layout' choice in the dialog.
//    v1.4.1 - Bugfix: "Image not found" after Reduce.
//    v1.4.0 - Flat output is now the default.
//    v1.3.0 - acquisitionFps + speedup via decimation + autoContrast.
//    v1.2.0 - GIF output (default).
//    v1.1.0 - Recurse into subdirectories.
//    v1.0.0 - Initial release.
// =====================================================================

VERSION = "2.0";

// ============================================================
// STAGE 1: PRESET SELECTION
// ============================================================
presetNames = newArray(
    "Presentation - GIF, large font, autoContrast, 5x speedup (default)",
    "Compact     - AVI/JPEG, medium font, autoContrast, 10x speedup",
    "Minimal     - GIF, small font, no contrast change, real-time (1x)",
    "Custom      - open the advanced dialog and set every parameter"
);

Dialog.create("Timestamp Movie Converter v" + VERSION + " - preset");
Dialog.addMessage("Pick a preset. You can still tweak any operational parameter below.");
Dialog.addChoice("Preset:", presetNames, presetNames[0]);
Dialog.show();
presetChoice = Dialog.getChoice();

// --- Apply preset defaults ---
if (presetChoice == presetNames[0]) {
    // Presentation
    pref_outputFormat = "gif";
    pref_fontSize     = 18;
    pref_decimals     = 1;
    pref_textX        = 12;
    pref_unitLabel    = " s";
    pref_autoContrast = true;
    pref_saturatedPct = 0.35;
    pref_jpegQuality  = 85;
    pref_speedup      = 5;
    pref_playbackFps  = 20;
    pref_flatten      = true;
    pref_outSuffix    = "";
    customMode = false;
} else if (presetChoice == presetNames[1]) {
    // Compact
    pref_outputFormat = "avi";
    pref_fontSize     = 14;
    pref_decimals     = 1;
    pref_textX        = 10;
    pref_unitLabel    = " s";
    pref_autoContrast = true;
    pref_saturatedPct = 0.35;
    pref_jpegQuality  = 70;
    pref_speedup      = 10;
    pref_playbackFps  = 20;
    pref_flatten      = true;
    pref_outSuffix    = "_compact";
    customMode = false;
} else if (presetChoice == presetNames[2]) {
    // Minimal
    pref_outputFormat = "gif";
    pref_fontSize     = 12;
    pref_decimals     = 1;
    pref_textX        = 8;
    pref_unitLabel    = " s";
    pref_autoContrast = false;
    pref_saturatedPct = 0.35;
    pref_jpegQuality  = 85;
    pref_speedup      = 1;
    pref_playbackFps  = 20;
    pref_flatten      = true;
    pref_outSuffix    = "_raw";
    customMode = false;
} else {
    // Custom
    pref_outputFormat = "gif";
    pref_fontSize     = 18;
    pref_decimals     = 1;
    pref_textX        = 12;
    pref_unitLabel    = " s";
    pref_autoContrast = true;
    pref_saturatedPct = 0.35;
    pref_jpegQuality  = 85;
    pref_speedup      = 5;
    pref_playbackFps  = 20;
    pref_flatten      = true;
    pref_outSuffix    = "";
    customMode = true;
}

// ============================================================
// STAGE 2: INPUT / OUTPUT FOLDERS
// ============================================================
inputDir  = getDirectory("Choose the INPUT folder (will include all subfolders)");
outputDir = getDirectory("Choose the OUTPUT folder (videos go here)");

// ============================================================
// STAGE 3: OPERATIONAL PARAMETERS (always prompted)
// ============================================================
formatChoices = newArray("gif", "avi");
layoutChoices = newArray("Flat (subfolder prefix in filename)",
                         "Mirror input subfolder structure");

Dialog.create("Timestamp Movie Converter v" + VERSION + " - settings");

Dialog.addMessage("Acquisition rate of the source recordings (must match the data!)");
Dialog.addNumber("Acquisition FPS (Hz):", 20);

Dialog.addMessage("\nPlayback speed and format");
Dialog.addNumber("Speedup factor (1 = real time, 5 = 5x faster, ...):", pref_speedup);
Dialog.addNumber("Playback FPS (display rate of output):", pref_playbackFps);
Dialog.addChoice("Output format:", formatChoices, pref_outputFormat);
Dialog.addChoice("Output layout:", layoutChoices, layoutChoices[0]);

Dialog.show();

acquisitionFps = Dialog.getNumber();
speedup        = Dialog.getNumber();
playbackFps    = Dialog.getNumber();
outputFormat   = Dialog.getChoice();
layoutChoice   = Dialog.getChoice();
flattenOutput  = (layoutChoice == layoutChoices[0]);

// ============================================================
// STAGE 4: ADVANCED DIALOG (only if Custom preset chosen)
// ============================================================
if (customMode) {
    Dialog.create("Timestamp Movie Converter v" + VERSION + " - advanced");

    Dialog.addMessage("Contrast handling");
    Dialog.addCheckbox("Auto-stretch contrast stack-wide before saving", pref_autoContrast);
    Dialog.addNumber("Saturated pixels (%) for contrast (default 0.35):", pref_saturatedPct);

    Dialog.addMessage("\nText style");
    Dialog.addNumber("Font size (pixels):", pref_fontSize);
    Dialog.addNumber("Decimal places shown on timestamp:", pref_decimals);
    Dialog.addNumber("Text X position (pixels from left):", pref_textX);
    Dialog.addString("Unit label appended to number:", pref_unitLabel);

    Dialog.addMessage("\nFormat-specific");
    Dialog.addNumber("AVI JPEG quality (0-100, lower = smaller):", pref_jpegQuality);
    Dialog.addString("Output filename suffix (e.g. '_ts'):", pref_outSuffix);

    Dialog.show();

    autoContrast = Dialog.getCheckbox();
    saturatedPct = Dialog.getNumber();
    fontSize     = Dialog.getNumber();
    decimals     = Dialog.getNumber();
    textX        = Dialog.getNumber();
    unitLabel    = Dialog.getString();
    jpegQuality  = Dialog.getNumber();
    outSuffix    = Dialog.getString();
} else {
    autoContrast = pref_autoContrast;
    saturatedPct = pref_saturatedPct;
    fontSize     = pref_fontSize;
    decimals     = pref_decimals;
    textX        = pref_textX;
    unitLabel    = pref_unitLabel;
    jpegQuality  = pref_jpegQuality;
    outSuffix    = pref_outSuffix;
}

// ============================================================
// Derived values
// ============================================================
secondsPerFrame = 1.0 / acquisitionFps;
frameStride     = round(speedup * playbackFps / acquisitionFps);
if (frameStride < 1) frameStride = 1;

count = 0;

print("\\Clear");
print("Timestamp converter v" + VERSION + " starting...");
print("  preset:        " + presetChoice);
print("  input:         " + inputDir);
print("  output:        " + outputDir);
print("  format:        " + outputFormat);
print("  acquisitionFps:" + acquisitionFps);
print("  speedup:       " + speedup + "x (stride " + frameStride + ")");
print("  playbackFps:   " + playbackFps);
print("  autoContrast:  " + autoContrast);
print("");

setBatchMode(true);
processFolder(inputDir, "");
setBatchMode(false);

showMessage("Done",
    "Converted " + count + " movie(s) to ." + outputFormat +
    "\n" + speedup + "x speed, " + playbackFps + " fps playback" +
    "\nKeeping every " + frameStride + " frame(s)" +
    "\nSaved to: " + outputDir);


// ---------------------------------------------------------------------
// Recursively walk a folder. relPath is the path so far, relative to
// the chosen input root (e.g. "cell01/results/").
// ---------------------------------------------------------------------
function processFolder(dir, relPath) {
    list = getFileList(dir);
    for (i = 0; i < list.length; i++) {
        entry = list[i];
        if (endsWith(entry, "/")) {
            processFolder(dir + entry, relPath + entry);   // descend
        } else {
            lower = toLowerCase(entry);
            if (endsWith(lower, ".tif") || endsWith(lower, ".tiff"))
                convertFile(dir + entry, entry, relPath);
        }
    }
}

// ---------------------------------------------------------------------
// Open one TIFF stack: auto-contrast, RGB-convert, timestamp the kept
// frames, decimate to achieve speedup, save in chosen format.
// ---------------------------------------------------------------------
function convertFile(fullPath, name, relPath) {
    open(fullPath);

    // 1. Auto-contrast
    if (autoContrast)
        run("Enhance Contrast...",
            "saturated=" + saturatedPct + " normalize process_all use");

    // 2. Convert to RGB
    if (bitDepth() != 24)
        run("RGB Color");

    // 3. Burn timestamp into frames we'll keep after decimation
    textY = fontSize + 10;
    for (s = 1; s <= nSlices; s += frameStride) {
        setSlice(s);
        t     = (s - 1) * secondsPerFrame;
        label = d2s(t, decimals) + unitLabel;

        setFont("SansSerif", fontSize, "antialiased");
        setColor(0, 0, 0);                       // shadow
        drawString(label, textX + 1, textY + 1);
        setColor(255, 255, 255);                 // white text
        drawString(label, textX, textY);
    }

    // 4. Decimate
    if (frameStride > 1) {
        originalID = getImageID();
        run("Reduce...", "reduction=" + frameStride);
        reducedID = getImageID();
        if (reducedID != originalID) {
            selectImage(originalID);
            close();
            selectImage(reducedID);
        }
    }

    // 5. Build output path
    if (outputFormat == "gif") extension = ".gif";
    else                       extension = ".avi";

    dot  = lastIndexOf(name, ".");
    base = substring(name, 0, dot);

    if (flattenOutput) {
        prefix  = replace(relPath, "/", "_");
        outPath = outputDir + prefix + base + outSuffix + extension;
    } else {
        targetDir = outputDir + relPath;
        File.makeDirectory(targetDir);
        outPath = targetDir + base + outSuffix + extension;
    }

    // 6. Save
    if (outputFormat == "gif") {
        Stack.setFrameRate(playbackFps);
        saveAs("Gif", outPath);
    } else {
        run("AVI... ", "compression=JPEG quality=" + jpegQuality +
                       " frame=" + playbackFps + " save=[" + outPath + "]");
    }

    close();
    count++;
    print("  [" + count + "] " + outPath);
}
