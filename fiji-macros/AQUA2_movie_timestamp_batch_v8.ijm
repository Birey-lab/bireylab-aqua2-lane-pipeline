// =====================================================================
//  AQUA2 Movie  ->  Timestamped Video  (Batch Converter, recursive)
//  ImageJ / Fiji macro  (.ijm)
//  Version: 1.4.1
// ---------------------------------------------------------------------
//  Walks the input folder AND all of its subdirectories, finds every
//  multi-page TIFF, optionally auto-contrasts and speeds it up, burns
//  an elapsed-time stamp (in seconds, computed from the REAL acquisition
//  rate) into each frame, and saves a presentation-ready movie of each
//  one into the output folder. Originals are never modified.
//
//  OUTPUT FORMAT (set outputFormat below):
//    "gif"  - Animated GIF. Easiest for PowerPoint: Insert > Picture and
//             it autoplays + loops. No codec issues across machines.
//    "avi"  - JPEG-compressed AVI. Smaller files for long movies, but
//             needs a codec on the target machine.
//
//  SPEEDUP works by decimating (keeping every Nth frame), not by
//  inflating the playback rate. This keeps GIF playback reliable
//  (GIFs cap out near 50 fps on most viewers) and keeps file sizes
//  small. Timestamps remain physically correct because they are
//  computed from the original frame numbers and the real acquisition
//  rate before decimation.
//
//  By default everything is saved into ONE flat folder, with each
//  output's input subfolder path prefixed onto its filename to keep
//  names unique (e.g. "cell01_results_movie.gif"). Set
//  flattenOutput = false to mirror AQUA2's per-file subfolder structure
//  into the output folder instead.
// ---------------------------------------------------------------------
//  CHANGELOG
//    v1.4.1  Bugfix: "Image not found" after Reduce. ImageJ's
//            "Reduce..." modifies the stack in place rather than
//            creating a new image, so the previous code closed the
//            only existing image and then tried to re-select it. Now
//            we only close-original-and-select-reduced if Reduce
//            actually produced a separate image.
//    v1.4.0  Flat output is now the DEFAULT (flattenOutput = true).
//            All videos go into one folder with subfolder paths
//            prefixed onto filenames. Set flattenOutput = false to
//            restore the mirrored-subfolder behavior.
//    v1.3.0  Replaced secondsPerFrame with acquisitionFps (more natural).
//            Added speedup parameter (implemented via frame decimation,
//            keeping GIF playback within format limits and shrinking
//            file size). Added playbackFps as a separate setting from
//            acquisition rate. Added autoContrast option using stack-
//            wide histogram + normalize for temporally consistent
//            brightness scaling.
//    v1.2.0  Added GIF output (default) for easy PowerPoint use, via
//            outputFormat setting. AVI still available.
//    v1.1.0  Recurse into subdirectories. Output mirrors input subfolder
//            structure (or flattens with path-prefixed names).
//    v1.0.0  Initial release. Batch TIFF-stack -> timestamped AVI,
//            JPEG-compressed, with white text + shadow for legibility.
// =====================================================================


// ------------------------- USER SETTINGS -----------------------------
// --- TIMING ---
var acquisitionFps  = 20;    // Real-world acquisition rate (frames per second)
var speedup         = 5;     // 1 = real time, 5 = 5x faster, etc.
var playbackFps     = 20;    // Display rate of the output video.
                             // (Keep <= 50 for GIF compatibility.)

// --- AUTO CONTRAST ---
var autoContrast    = true;  // Auto-stretch contrast stack-wide before saving
var saturatedPct    = 0.35;  // Pixels to saturate (%). 0.35 = ImageJ default

// --- OUTPUT ---
var outputFormat    = "gif"; // "gif" (PowerPoint-friendly) or "avi"
var jpegQuality     = 85;    // AVI only: JPEG quality 0-100 (lower = smaller)
var outSuffix       = "";    // Appended to output filename, e.g. "_ts"
var flattenOutput   = true;  // true = one flat folder (subfolder path is prefixed
                             //        onto each filename to keep names unique);
                             // false = mirror the input subfolder structure

// --- TIMESTAMP TEXT ---
var fontSize        = 18;    // Font size in pixels
var decimalPlaces   = 1;     // Decimals shown on the timestamp (e.g. "12.4 s")
var textX           = 12;    // X position (pixels from left)
var unitLabel       = " s";  // Text appended after the number
// ---------------------------------------------------------------------


// ----- Derived values (computed from the user settings above) --------
var secondsPerFrame = 1.0 / acquisitionFps;   // real seconds between frames
var frameStride     = round(speedup * playbackFps / acquisitionFps);
if (frameStride < 1) frameStride = 1;         // can't slow below input

var outputDir;
var count = 0;

inputDir  = getDirectory("Choose the INPUT folder (will include all subfolders)");
outputDir = getDirectory("Choose the OUTPUT folder (videos go here)");

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

    // 1. Auto-contrast (stack-wide histogram + normalize so brightness
    //    scaling is identical across slices and won't flicker).
    if (autoContrast)
        run("Enhance Contrast...",
            "saturated=" + saturatedPct + " normalize process_all use");

    // 2. Convert to RGB so the timestamp text and any color overlays
    //    render correctly.
    if (bitDepth() != 24)
        run("RGB Color");

    // 3. Burn the timestamp into only the frames we'll keep after
    //    decimation. Reduce() keeps slices 1, 1+stride, 1+2*stride, ...
    //    matching the loop below exactly.
    textY = fontSize + 10;
    for (s = 1; s <= nSlices; s += frameStride) {
        setSlice(s);
        t     = (s - 1) * secondsPerFrame;
        label = d2s(t, decimalPlaces) + unitLabel;

        setFont("SansSerif", fontSize, "antialiased");
        setColor(0, 0, 0);                       // shadow for legibility
        drawString(label, textX + 1, textY + 1);
        setColor(255, 255, 255);                 // white text on top
        drawString(label, textX, textY);
    }

    // 4. Decimate (frame-skip) to achieve the requested speedup.
    //    Note: on most ImageJ builds "Reduce..." modifies the stack
    //    IN PLACE (same image ID, fewer slices). On builds where it
    //    creates a new image instead, close the original.
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
        File.makeDirectory(targetDir);           // safe if it already exists
        outPath = targetDir + base + outSuffix + extension;
    }

    // 6. Save
    if (outputFormat == "gif") {
        Stack.setFrameRate(playbackFps);         // controls GIF frame delay
        saveAs("Gif", outPath);
    } else {
        run("AVI... ", "compression=JPEG quality=" + jpegQuality +
                       " frame=" + playbackFps + " save=[" + outPath + "]");
    }

    close();
    count++;
}
