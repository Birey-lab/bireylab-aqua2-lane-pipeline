// ============================================================
// LIF Extractor — Consolidated, Recursive, Resume-Safe
// VERSION: 2.0   (2026-05-17)
// ------------------------------------------------------------
// CHANGELOG
//  v2.0 (2026-05-17)
//    - FIX: stripPrefix() failed when LIF metadata embedded folder paths
//           into series titles (e.g. "Assembloids/Excitatory/foo.lif - bar").
//           Now uses lastIndexOf(" - "), matching the original macro #2 behavior.
//    - FIX: parser error on `lengthOf(lifFname + " - ")` — precompute prefix
//           into a variable before passing to lengthOf().
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
// BEHAVIOR
//  - Recurses ALL subfolders of the chosen ROOT input folder
//  - For each .lif: creates <LIF_basename>/ NEXT TO the .lif
//      <LIF_basename>/UNTRIMMED/<seriesName>.tif   (full time series)
//      <LIF_basename>/TRIMMED/<seriesName>.tif     (middle 60s, starting 15s in)
//  - Resume-safe: skips series whose UNTRIMMED .tif already exists
//  - Single-frame series skipped; TileScan_* skipped (unless name has "Merging")
//  - Frame-rate consistency check (warn, don't drop)
//  - Originals NEVER modified
//  - Formatted log written to root input folder
// ============================================================

VERSION = "2.0";

requires("1.48a");
run("Bio-Formats Macro Extensions");

inputDir = getDirectory("Choose ROOT INPUT folder (will recurse all subfolders)");

TARGET_SECONDS = 60;
TRIM_START_SEC = 15;

// --- Open log in the root input folder ---
getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
month = month + 1;
nowStr = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dayOfMonth,2)
       + "_" + IJ.pad(hour,2) + "-" + IJ.pad(minute,2) + "-" + IJ.pad(second,2);
nowPretty = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dayOfMonth,2)
       + " " + IJ.pad(hour,2) + ":" + IJ.pad(minute,2) + ":" + IJ.pad(second,2);

logPath = inputDir + "extraction_log_" + nowStr + ".txt";
flog = File.open(logPath);

print(flog, "=============================================");
print(flog, " LIF EXTRACTION SUMMARY (macro v" + VERSION + ")");
print(flog, " Run: " + nowPretty);
print(flog, "=============================================");
print(flog, "");
print(flog, " ROOT INPUT: " + inputDir);
print(flog, " Trim:       middle " + TARGET_SECONDS + "s starting " + TRIM_START_SEC + "s in");
print(flog, "");

print("\\Clear");
print("LIF Extractor v" + VERSION + " starting...");
print("Root: " + inputDir);
print("Log:  " + logPath);
print("");

// ============================================================
// PASS 1: Discover all LIFs
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

// --- Globals ---
globalFrameInterval = -1;
totalOK         = 0;
totalSkippedSnap = 0;
totalSkippedTile = 0;
totalSkippedDone = 0;
totalSkippedNoFI = 0;
totalWarnings   = 0;
totalLIFsAllDone = 0;

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

    processLIF(lifFull, lifFname, lifParent, li, nLIFs);
}
showProgress(1.0);

// ============================================================
// Footer
// ============================================================
totalSec = (getTime() - runStartMs) / 1000.0;

print(flog, "");
print(flog, "=============================================");
print(flog, " TOTALS");
print(flog, " LIF files seen:               " + nLIFs);
print(flog, "   ...fully skipped (done):    " + totalLIFsAllDone);
print(flog, " Series saved (OK):            " + totalOK);
print(flog, " Series skipped - already done:" + totalSkippedDone);
print(flog, " Series skipped - single frame:" + totalSkippedSnap);
print(flog, " Series skipped - TileScan:    " + totalSkippedTile);
print(flog, " Series skipped - no interval: " + totalSkippedNoFI);
print(flog, " Warnings (rate/length):       " + totalWarnings);
if (globalFrameInterval > 0) {
    print(flog, " Reference frame rate:         " + d2s(1/globalFrameInterval, 2) + " fps (" + d2s(globalFrameInterval, 4) + " s/frame)");
} else {
    print(flog, " Reference frame rate:         N/A");
}
print(flog, " Total runtime:                " + formatDuration(totalSec));
print(flog, "=============================================");

File.close(flog);
setBatchMode(false);

print("");
print("=============================================");
print("DONE (v" + VERSION + "). " + totalOK + " series saved, " + totalSkippedDone + " skipped (already done).");
print("Total runtime: " + formatDuration(totalSec));
print("Full log: " + logPath);
showStatus("Done! " + totalOK + " series saved in " + formatDuration(totalSec));


// ============================================================
// Recursive .lif discovery
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
// Process one LIF
// ============================================================
function processLIF(lifPath, fname, dstParent, lifIdx, lifTotal) {
    lifBase = fname;
    if (endsWith(toLowerCase(lifBase), ".lif")) {
        lifBase = substring(lifBase, 0, lengthOf(lifBase) - 4);
    }

    lifOutDir    = dstParent + lifBase + File.separator;
    trimmedDir   = lifOutDir + "TRIMMED"   + File.separator;
    untrimmedDir = lifOutDir + "UNTRIMMED" + File.separator;

    // --- Fast-skip if fully done ---
    if (File.exists(untrimmedDir)) {
        existingTifs = countTifs(untrimmedDir);
        if (existingTifs > 0) {
            showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + ": peeking " + fname + "...");
            Ext.setId(lifPath);
            Ext.getSeriesCount(peekCount);
            expected = 0;
            for (q = 0; q < peekCount; q++) {
                Ext.setSeries(q);
                Ext.getSeriesName(qn);
                Ext.getSizeT(qt);
                isTile = (indexOf(qn, "TileScan_") > -1) && (indexOf(qn, "Merging") < 0);
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
    File.makeDirectory(trimmedDir);
    File.makeDirectory(untrimmedDir);

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

        if (indexOf(peekName, "TileScan_") > -1 && indexOf(peekName, "Merging") < 0) {
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
            print(flog, "  [WARN-RATE] " + seriesName + " | " + totalFrames + " frames | " + fpsStr
                       + " | DIFFERS from reference " + d2s(1/globalFrameInterval,2) + " fps - series still saved");
            totalWarnings++;
        }

        showStatus("LIF " + (lifIdx+1) + "/" + lifTotal + " - saving UNTRIMMED " + (s+1) + "/" + seriesCount);
        run("Duplicate...", "duplicate");
        Stack.setFrameInterval(fi);
        Stack.setTUnit("s");
        saveAs("Tiff", untrimmedDir + seriesName + ".tif");
        close();

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

        totalOK++;
    }

    Ext.close();
    print(flog, "");
}


// ============================================================
// Helpers
// ============================================================

// Strip everything up to and including the LAST " - " in the title.
// This matches the original macro #2 approach and is robust to LIF
// metadata that embeds folder paths into the title.
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
