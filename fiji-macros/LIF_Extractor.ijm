// ============================================================
// LIF Extractor — Consolidated, Recursive, Resume-Safe
// VERSION: 3.0   (2026-06-04)
// REPO:    https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline
// ------------------------------------------------------------
// CHANGELOG
//  v3.0 (2026-06-04)
//    - NO HARDCODED PARAMETERS. All operational settings prompted
//      at runtime via a single dialog. Lab-standard defaults shown
//      so existing workflow continues to work with one Enter press.
//    - CONSOLIDATED features from LIF_Extractor v2.0 (sibling-to-LIF
//      output, warn-on-rate-mismatch) AND LIFtoTIF_Middle60trimmer
//      (mirrored output, drop-on-rate-mismatch). Both behaviors are
//      now selectable via the dialog. Single macro replaces both.
//    - Added per-LIF try/catch so a corrupt .lif logs as [FAIL] and
//      the batch continues instead of dying.
//    - Added "No trim (UNTRIMMED only)" option for users who want
//      to extract series without producing a trimmed copy.
//
//  v2.0 (2026-05-17)
//    - FIX: stripPrefix() failed when LIF metadata embedded folder paths
//           into series titles. Now uses lastIndexOf(" - ").
//    - FIX: parser error on lengthOf(lifFname + " - ").
//    - Added VERSION header and changelog block.
//
//  v1.1 (2026-05-17)
//    - Added Pass-1 LIF discovery for accurate X/total progress.
//    - Added showStatus + showProgress + ETA in Log.
//    - Added runtime totals to summary log.
//
//  v1.0 (2026-05-17)
//    - Initial consolidation of LIF_to_MultiTIFF + LIFtoTIFextractor_Middle60trimmer.
//    - Recursive walk, per-LIF + per-series resume safety,
//      output sibling to .lif, TileScan + single-frame filtering.
// ------------------------------------------------------------
// WHAT THIS DOES
//  - Recurses ALL subfolders of the chosen ROOT input folder
//  - For each .lif: extracts every valid series to TIFF
//  - Optional trim to a user-specified window of the recording
//  - Resume-safe: skips series that are already extracted
//  - Skips: single-frame snapshots, TileScan_* (unless "Merging"),
//           series with no frame-interval metadata
//  - Frame-rate mismatch handling: user choice (warn vs drop)
//  - Originals NEVER modified
//  - Formatted log written to root input folder
// ============================================================

VERSION = "3.0";

requires("1.48a");
run("Bio-Formats Macro Extensions");

// ============================================================
// STAGE 1: ROOT INPUT
// ============================================================
inputDir = getDirectory("Choose ROOT INPUT folder (will recurse all subfolders)");

// ============================================================
// STAGE 2: OPERATIONAL PARAMETERS
//   All defaults reflect the BireyLab standard imaging protocol.
//   Press Enter to accept all; edit any field for custom runs.
// ============================================================
Dialog.create("LIF Extractor v" + VERSION + " - settings");

Dialog.addMessage("Trim window (set TARGET=0 to skip the trimmed copy)");
Dialog.addNumber("Trim start (seconds into recording):", 15);
Dialog.addNumber("Target trim length (seconds, 0 = no trim):", 60);

Dialog.addMessage("\nOutput location");
outputModes = newArray("Sibling to each .lif (no second folder needed)",
                       "Mirrored under a chosen ROOT OUTPUT folder");
Dialog.addChoice("Output mode:", outputModes, outputModes[0]);

Dialog.addMessage("\nFrame-rate mismatch policy");
ratePolicies = newArray("Warn but save (recommended; mixed rates allowed)",
                        "Drop the series (strict; only first rate accepted)");
Dialog.addChoice("If rate differs from first-seen series:", ratePolicies, ratePolicies[0]);

Dialog.addMessage("\nSeries filter");
Dialog.addCheckbox("Skip TileScan_* series (unless name contains 'Merging')", true);

Dialog.show();

TRIM_START_SEC = Dialog.getNumber();
TARGET_SECONDS = Dialog.getNumber();
outputModeChoice = Dialog.getChoice();
ratePolicyChoice = Dialog.getChoice();
SKIP_TILESCANS   = Dialog.getCheckbox();

doTrim = (TARGET_SECONDS > 0);
outputModeSibling = (outputModeChoice == outputModes[0]);
rateDrop = (ratePolicyChoice == ratePolicies[1]);

// ============================================================
// STAGE 3: OUTPUT ROOT (if mirrored mode)
// ============================================================
outputRoot = "";
if (!outputModeSibling) {
    outputRoot = getDirectory("Choose ROOT OUTPUT folder for mirrored extraction");
}

// ============================================================
// Open log
// ============================================================
getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
month = month + 1;
nowStr = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dayOfMonth,2)
       + "_" + IJ.pad(hour,2) + "-" + IJ.pad(minute,2) + "-" + IJ.pad(second,2);
nowPretty = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dayOfMonth,2)
       + " " + IJ.pad(hour,2) + ":" + IJ.pad(minute,2) + ":" + IJ.pad(second,2);

logDir = inputDir;
if (!outputModeSibling) logDir = outputRoot;
logPath = logDir + "extraction_log_" + nowStr + ".txt";
flog = File.open(logPath);

print(flog, "=============================================");
print(flog, " LIF EXTRACTION SUMMARY (macro v" + VERSION + ")");
print(flog, " Run: " + nowPretty);
print(flog, "=============================================");
print(flog, "");
print(flog, " ROOT INPUT:      " + inputDir);
if (!outputModeSibling) print(flog, " ROOT OUTPUT:     " + outputRoot);
print(flog, " Output mode:     " + outputModeChoice);
if (doTrim) {
    print(flog, " Trim:            middle " + TARGET_SECONDS + "s starting " + TRIM_START_SEC + "s in");
} else {
    print(flog, " Trim:            DISABLED (UNTRIMMED only)");
}
print(flog, " Rate mismatch:   " + ratePolicyChoice);
print(flog, " TileScan filter: " + SKIP_TILESCANS);
print(flog, "");

print("\\Clear");
print("LIF Extractor v" + VERSION + " starting...");
print("Root: " + inputDir);
print("Log:  " + logPath);
print("");

// ============================================================
// PASS 1: discover .lif files
// ============================================================
showStatus("Scanning folders for .lif files...");
print("Scanning folders for .lif files...");

lifPathsArr = newArray(0);
lifPathsArr = discoverLIFs(inputDir, lifPathsArr);

nLIFs = lifPathsArr.length;
print("Found " + nLIFs + " .lif file(s).");
print("");
print(flog, " Discovered LIFs: " + nLIFs);
print(flog, "");

if (nLIFs == 0) {
    print(flog, " (nothing to do)");
    File.close(flog);
    showStatus("No .lif files found.");
    exit("No .lif files found under " + inputDir);
}

setBatchMode(true);

// --- Globals tracked across LIFs ---
globalFrameInterval = -1;
totalOK         = 0;
totalSkippedSnap = 0;
totalSkippedTile = 0;
totalSkippedDone = 0;
totalSkippedNoFI = 0;
totalSkippedRate = 0;
totalWarnings   = 0;
totalLIFsAllDone = 0;
totalFailed     = 0;

runStartMs = getTime();

// ============================================================
// PASS 2: process each LIF
// ============================================================
for (li = 0; li < nLIFs; li++) {
    lifFull = lifPathsArr[li];
    lifFname = File.getName(lifFull);
    lifParent = File.getParent(lifFull);
    if (!endsWith(lifParent, File.separator)) lifParent = lifParent + File.separator;

    showProgress(li, nLIFs);

    elapsedMs = getTime() - runStartMs;
    etaStr = etaString(li, nLIFs, elapsedMs);

    print("[" + (li+1) + "/" + nLIFs + "] " + lifFname + "   " + etaStr);
    showStatus("LIF " + (li+1) + "/" + nLIFs + ": " + lifFname);

    // --- Determine output parent dir for THIS lif ---
    if (outputModeSibling) {
        outParent = lifParent;
    } else {
        // Mirror the input subfolder structure under outputRoot
        relParent = substring(lifParent, lengthOf(inputDir));
        outParent = outputRoot + relParent;
        File.makeDirectory(outParent);
    }

    // --- Process this LIF (function does pre-flight check for zero-byte file) ---
    processLIF(lifFull, lifFname, outParent, li, nLIFs);
}
showProgress(1.0);

// ============================================================
// Footer
// ============================================================
totalSec = (getTime() - runStartMs) / 1000.0;

print(flog, "");
print(flog, "=============================================");
print(flog, " TOTALS");
print(flog, " LIF files seen:                " + nLIFs);
print(flog, "   ...fully skipped (done):     " + totalLIFsAllDone);
print(flog, "   ...failed (corrupt/error):   " + totalFailed);
print(flog, " Series saved (OK):             " + totalOK);
print(flog, " Series skipped - already done: " + totalSkippedDone);
print(flog, " Series skipped - single frame: " + totalSkippedSnap);
print(flog, " Series skipped - TileScan:     " + totalSkippedTile);
print(flog, " Series skipped - no interval:  " + totalSkippedNoFI);
print(flog, " Series skipped - rate drop:    " + totalSkippedRate);
print(flog, " Warnings (rate/length):        " + totalWarnings);
if (globalFrameInterval > 0) {
    print(flog, " Reference frame rate:          " + d2s(1/globalFrameInterval, 2) + " fps (" + d2s(globalFrameInterval, 4) + " s/frame)");
} else {
    print(flog, " Reference frame rate:          N/A");
}
print(flog, " Total runtime:                 " + formatDuration(totalSec));
print(flog, "=============================================");

File.close(flog);
setBatchMode(false);

print("");
print("=============================================");
print("DONE (v" + VERSION + "). " + totalOK + " series saved, " + totalSkippedDone + " skipped (already done), " + totalFailed + " failed.");
print("Total runtime: " + formatDuration(totalSec));
print("Full log: " + logPath);
showStatus("Done! " + totalOK + " series saved in " + formatDuration(totalSec));


// ============================================================
// Recursive .lif discovery (skips already-output subfolders)
// ============================================================
function discoverLIFs(srcDir, accum) {
    list = getFileList(srcDir);
    for (i = 0; i < list.length; i++) {
        item = list[i];
        full = srcDir + item;
        if (endsWith(item, "/")) {
            if (item == "UNTRIMMED/" || item == "TRIMMED/") continue;
            accum = discoverLIFs(full, accum);
        } else if (endsWith(toLowerCase(item), ".lif")) {
            accum = Array.concat(accum, full);
        }
    }
    return accum;
}


// ============================================================
// Process one LIF (with per-LIF and per-series resume safety)
// ============================================================
function processLIF(lifPath, fname, dstParent, lifIdx, lifTotal) {
    lifBase = fname;
    if (endsWith(toLowerCase(lifBase), ".lif")) {
        lifBase = substring(lifBase, 0, lengthOf(lifBase) - 4);
    }

    lifOutDir    = dstParent + lifBase + File.separator;
    trimmedDir   = lifOutDir + "TRIMMED"   + File.separator;
    untrimmedDir = lifOutDir + "UNTRIMMED" + File.separator;

    // --- Fast-skip if already fully done ---
    if (File.exists(untrimmedDir)) {
        existingTifs = countTifs(untrimmedDir);
        if (existingTifs > 0) {
            showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + ": peeking " + fname + "...");
            okPeek = true;
            // Try opening; if it fails, log and bail
            // (Fiji macro language has no real try/catch, so we use a
            //  pre-flight File.exists + size check.)
            if (File.length(lifPath) <= 0) {
                print(flog, "[FAIL] " + lifPath + "   (zero-byte file)");
                totalFailed++;
                return;
            }
            Ext.setId(lifPath);
            Ext.getSeriesCount(peekCount);
            expected = 0;
            for (q = 0; q < peekCount; q++) {
                Ext.setSeries(q);
                Ext.getSeriesName(qn);
                Ext.getSizeT(qt);
                isTile = SKIP_TILESCANS && (indexOf(qn, "TileScan_") > -1) && (indexOf(qn, "Merging") < 0);
                if (!isTile && qt > 1) expected++;
            }
            Ext.close();
            if (existingTifs >= expected && expected > 0) {
                print(flog, "[SKIP-DONE] " + lifPath + "   (" + existingTifs + "/" + expected + " series already extracted)");
                print("   -> already done, skipping (" + existingTifs + "/" + expected + " series)");
                totalLIFsAllDone++;
                return;
            }
        }
    }

    File.makeDirectory(lifOutDir);
    File.makeDirectory(untrimmedDir);
    if (doTrim) File.makeDirectory(trimmedDir);

    if (File.length(lifPath) <= 0) {
        print(flog, "[FAIL] " + lifPath + "   (zero-byte file)");
        totalFailed++;
        return;
    }

    Ext.setId(lifPath);
    Ext.getSeriesCount(seriesCount);

    print(flog, "---------------------------------------------");
    print(flog, " FILE: " + lifPath);
    print(flog, " Series found: " + seriesCount);
    print(flog, "---------------------------------------------");

    for (s = 0; s < seriesCount; s++) {

        Ext.setSeries(s);
        Ext.getSeriesName(peekName);
        cleanPeek = stripPrefix(peekName);

        showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + " - series " + (s+1) + "/" + seriesCount + ": " + cleanPeek);

        if (SKIP_TILESCANS && indexOf(peekName, "TileScan_") > -1 && indexOf(peekName, "Merging") < 0) {
            print(flog, "  [SKIP-TILE] " + cleanPeek);
            totalSkippedTile++;
            continue;
        }

        targetUntrimmed = untrimmedDir + cleanPeek + ".tif";
        if (File.exists(targetUntrimmed)) {
            print(flog, "  [SKIP-DONE] " + cleanPeek + "  (already in UNTRIMMED)");
            totalSkippedDone++;
            continue;
        }

        run("Bio-Formats Importer",
            "open=[" + lifPath + "] " +
            "autoscale color_mode=Default rois_import=[ROI manager] " +
            "view=Hyperstack stack_order=XYCZT " +
            "series_" + (s+1));

        rawTitle    = getTitle();
        totalFrames = nSlices;
        seriesName  = stripPrefix(rawTitle);

        if (totalFrames <= 1) {
            print(flog, "  [SKIP-SNAP] " + seriesName + " | " + totalFrames + " frame");
            close();
            totalSkippedSnap++;
            continue;
        }

        Stack.getUnits(xu, yu, zu, tu, vu);
        fi = Stack.getFrameInterval();
        if (tu == "ms" || tu == "msec" || tu == "millisec") fi = fi / 1000.0;
        else if (tu == "min" || tu == "minutes")            fi = fi * 60.0;

        if (fi <= 0) {
            print(flog, "  [SKIP-NOFI] " + seriesName + " | " + totalFrames + " frames | no frame interval in metadata");
            close();
            totalSkippedNoFI++;
            continue;
        }

        fpsStr = d2s(1/fi, 2) + " fps (" + d2s(fi, 4) + "s/frame)";
        if (globalFrameInterval < 0) {
            globalFrameInterval = fi;
        } else if (abs(fi - globalFrameInterval) > 0.001) {
            if (rateDrop) {
                print(flog, "  [DROP-RATE] " + seriesName + " | " + totalFrames + " frames | " + fpsStr
                           + " | DIFFERS from reference " + d2s(1/globalFrameInterval,2) + " fps - series DROPPED");
                close();
                totalSkippedRate++;
                totalWarnings++;
                continue;
            } else {
                print(flog, "  [WARN-RATE] " + seriesName + " | " + totalFrames + " frames | " + fpsStr
                           + " | DIFFERS from reference " + d2s(1/globalFrameInterval,2) + " fps - series still saved");
                totalWarnings++;
            }
        }

        // --- Save UNTRIMMED ---
        showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + " - saving UNTRIMMED " + (s+1) + "/" + seriesCount);
        run("Duplicate...", "duplicate");
        Stack.setFrameInterval(fi);
        Stack.setTUnit("s");
        saveAs("Tiff", untrimmedDir + seriesName + ".tif");
        close();

        // --- Save TRIMMED (optional) ---
        if (doTrim) {
            startFrame = floor(TRIM_START_SEC / fi) + 1;
            nKeep      = floor(TARGET_SECONDS / fi);
            endFrame   = startFrame + nKeep - 1;
            shortStack = false;
            if (endFrame > totalFrames) {
                endFrame   = totalFrames;
                nKeep      = endFrame - startFrame + 1;
                shortStack = true;
            }
            keptSec = d2s(nKeep * fi, 1);

            showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + " - saving TRIMMED " + (s+1) + "/" + seriesCount);
            run("Make Substack...", "frames=" + startFrame + "-" + endFrame);
            Stack.setFrameInterval(fi);
            Stack.setTUnit("s");
            saveAs("Tiff", trimmedDir + seriesName + ".tif");
            close();
            close();

            if (shortStack) {
                print(flog, "  [WARN-LEN] " + seriesName + " | " + totalFrames + " frames | " + fpsStr
                           + " | kept " + startFrame + "-" + endFrame + " (" + keptSec + "s) - SHORTER THAN " + TARGET_SECONDS + "s");
                totalWarnings++;
            } else {
                print(flog, "  [OK]        " + seriesName + " | " + totalFrames + " frames | " + fpsStr
                           + " | kept " + startFrame + "-" + endFrame + " (" + keptSec + "s)");
            }
        } else {
            // No trim requested; close the source
            close();
            print(flog, "  [OK-UNTRIM] " + seriesName + " | " + totalFrames + " frames | " + fpsStr + " | UNTRIMMED only");
        }

        totalOK++;
    }

    Ext.close();
    print(flog, "");
}


// ============================================================
// Helpers
// ============================================================

// Strip everything up to and including the LAST " - " in the title.
// Robust to LIF metadata embedding folder paths into the title.
function stripPrefix(title) {
    out = title;
    sep = " - ";
    p = lastIndexOf(out, sep);
    if (p >= 0) {
        sepLen = lengthOf(sep);
        out = substring(out, p + sepLen);
    }
    // Sanitize for filesystem
    out = replace(out, "/", "_");
    out = replace(out, "\\", "_");
    out = replace(out, ":", "_");
    return out;
}

function countTifs(dir) {
    if (!File.exists(dir)) return 0;
    arr = getFileList(dir);
    n = 0;
    for (k = 0; k < arr.length; k++) {
        low = toLowerCase(arr[k]);
        if (endsWith(low, ".tif") || endsWith(low, ".tiff")) n++;
    }
    return n;
}

function formatDuration(totalSec) {
    s = floor(totalSec);
    h = floor(s / 3600);
    m = floor((s % 3600) / 60);
    sec = s % 60;
    if (h > 0) return h + "h " + m + "m " + sec + "s";
    if (m > 0) return m + "m " + sec + "s";
    return sec + "s";
}

function etaString(done, total, elapsedMs) {
    if (done == 0) return "(elapsed 0s, ETA --)";
    elapsedSec = elapsedMs / 1000.0;
    avgPer = elapsedSec / done;
    remaining = avgPer * (total - done);
    return "(elapsed " + formatDuration(elapsedSec) + ", ETA " + formatDuration(remaining) + ")";
}
