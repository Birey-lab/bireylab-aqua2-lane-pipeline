// ============================================================
// LIF Extract & Trim  —  consolidated AQuA2 input-prep tool
// VERSION: 1.0   (2026-07-01)
// REPO:    https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline
// ------------------------------------------------------------
// WHAT THIS DOES
//   One interactive macro that takes raw acquisitions and produces
//   detection-ready TIFFs for the AQuA2 pipeline. It consolidates the
//   old LIF_Extractor.ijm (LIF -> TIFF, recurse, resume, rate policy,
//   TileScan filter) and TrimTIF_Frames.ijm (keep-final-N trimming) into
//   a single tool, and adds the feature the downstream R analysis needs:
//   the MEASURED acquisition rate is appended to every output filename,
//   end-anchored (e.g. "MySeries_1.55Hz.tif"), so the R parser can read
//   it (see docs/06 Pitfall #14, docs/05).
//
//   TWO INPUT MODES (chosen at startup):
//     1. LIF files   — recurse a folder, extract every valid series to a
//                      full (UNTRIMMED) TIFF and/or a TRIMMED TIFF.
//     2. TIFF stacks — trim + Hz-label a folder of existing TIFFs
//                      (subsumes the old TrimTIF_Frames use case).
//
// MAXIMUM PRESERVATION OF QUALITY / EXACTNESS (do not break this):
//   - Pixel data is NEVER modified. No contrast/RGB/annotation is applied
//     to the saved images — they must feed into AQuA2 bit-exact. The Hz
//     label lives ONLY in the filename, not in the pixels. (Burning a
//     visible timestamp is a separate, POST-detection job — see
//     AQUA2_Movie_Timestamp.ijm; do not add it here.)
//   - Frame-interval metadata is preserved exactly (t-unit forced to "s").
//   - Trimming uses exact frame selection (Make Substack), never re-encoding.
//   - Originals are never touched; outputs go to new files/folders.
//
// PROACTIVE ERROR-CHECKING
//   - Pre-flight discovery + a confirmation dialog summarizing the plan
//     (with a "Dry run" option that writes nothing).
//   - Per-file guard: zero-byte / unreadable inputs are logged [FAIL] and
//     the batch continues.
//   - Resume-safe: series/files already extracted (Hz-labelled or not) are
//     skipped.
//   - Skips single-frame snapshots, TileScan_* (unless "Merging"), and
//     series with no frame-interval metadata (can't compute Hz).
//   - Per-series frame-rate mismatch policy (warn / drop).
//   - Trim window longer than the recording is logged [WARN-LEN], not fatal.
//   - Full timestamped log + end-of-run totals and expected-vs-found check.
//
//   NOTE: ImageJ macro language has no linter/CI here — smoke-test this on
//   ONE .lif in Fiji and confirm the outputs before a large batch.
// ============================================================

VERSION = "1.0";
requires("1.48a");
run("Bio-Formats Macro Extensions");   // loaded once; used by LIF mode (harmless for TIFF mode)

// ============================================================
// STAGE 0: INPUT MODE
// ============================================================
modeNames = newArray(
    "LIF files  - extract raw (UNTRIMMED) + optional TRIMMED TIFFs",
    "TIFF stacks - trim + Hz-label existing TIFFs");
Dialog.create("LIF Extract & Trim v" + VERSION + " - input mode");
Dialog.addMessage("What are you starting from?");
Dialog.addChoice("Input:", modeNames, modeNames[0]);
Dialog.show();
modeChoice = Dialog.getChoice();
modeLIF = (modeChoice == modeNames[0]);

// ============================================================
// STAGE 1: INPUT FOLDER
// ============================================================
if (modeLIF)
    inputDir = getDirectory("Choose ROOT INPUT folder of .lif files (recurses all subfolders)");
else
    inputDir = getDirectory("Choose INPUT folder of .tif/.tiff stacks");

// ============================================================
// STAGE 2: SETTINGS
// ============================================================
trimModes = newArray("No trim (raw only)",
                     "Middle window (start + length)",
                     "Keep FINAL portion",
                     "Keep FIRST portion");
trimUnits = newArray("seconds", "frames");
outputModes = newArray("Sibling to each .lif (no second folder)",
                       "Mirrored under a chosen ROOT OUTPUT folder");
ratePolicies = newArray("Warn but save (mixed rates allowed; each file keeps its own Hz)",
                        "Drop the series (strict; only the first-seen rate accepted)");

Dialog.create("LIF Extract & Trim v" + VERSION + " - settings");

Dialog.addMessage("Outputs");
Dialog.addCheckbox("Save full UNTRIMMED copy", true);
Dialog.addChoice("Trim mode:", trimModes, trimModes[1]);
Dialog.addNumber("Trim start (seconds; used by Middle/First):", 15);
Dialog.addNumber("Trim amount:", 60);
Dialog.addChoice("Trim amount unit:", trimUnits, trimUnits[0]);

Dialog.addMessage("\nFilename Hz label (what the R analysis parses)");
Dialog.addCheckbox("Append measured _<Hz>Hz to every output filename", true);
Dialog.addNumber("Hz decimal places:", 2);

if (modeLIF) {
    Dialog.addMessage("\nLIF options");
    Dialog.addChoice("Output location:", outputModes, outputModes[0]);
    Dialog.addChoice("If a series' rate differs from the first-seen:", ratePolicies, ratePolicies[0]);
    Dialog.addCheckbox("Skip TileScan_* series (unless name contains 'Merging')", true);
}

Dialog.addMessage("\nSafety");
Dialog.addCheckbox("Dry run (report the plan in the log; write NO files)", false);

Dialog.show();

SAVE_UNTRIMMED = Dialog.getCheckbox();
trimModeChoice = Dialog.getChoice();
TRIM_START_SEC = Dialog.getNumber();
TRIM_AMOUNT    = Dialog.getNumber();
trimUnitChoice = Dialog.getChoice();
HZ_LABEL       = Dialog.getCheckbox();
HZ_DECIMALS    = Dialog.getNumber();
if (modeLIF) {
    outputModeChoice = Dialog.getChoice();
    ratePolicyChoice = Dialog.getChoice();
    SKIP_TILESCANS   = Dialog.getCheckbox();
} else {
    outputModeChoice = outputModes[1];   // TIFF mode always uses a chosen output folder
    ratePolicyChoice = ratePolicies[0];
    SKIP_TILESCANS   = false;
}
DRY_RUN = Dialog.getCheckbox();

doTrim            = (trimModeChoice != trimModes[0]);
trimUnitSeconds   = (trimUnitChoice == trimUnits[0]);
outputModeSibling = (modeLIF && outputModeChoice == outputModes[0]);
rateDrop          = (ratePolicyChoice == ratePolicies[1]);
if (HZ_DECIMALS < 0) HZ_DECIMALS = 0;

if (!SAVE_UNTRIMMED && !doTrim)
    exit("Nothing to do: UNTRIMMED copy is off AND trim mode is 'No trim'. Enable at least one output.");

// ============================================================
// STAGE 3: OUTPUT FOLDER (mirrored LIF mode, or TIFF mode)
// ============================================================
outputRoot = "";
if (!outputModeSibling) {
    if (modeLIF) outputRoot = getDirectory("Choose ROOT OUTPUT folder for mirrored extraction");
    else         outputRoot = getDirectory("Choose OUTPUT folder for trimmed / labelled TIFFs");
    if (outputRoot == inputDir)
        exit("OUTPUT folder must differ from the INPUT folder (would risk overwriting originals).");
}

// ============================================================
// Open log
// ============================================================
getDateAndTime(year, month, dow, dom, hour, minute, second, msec);
month = month + 1;
nowStr = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dom,2)
       + "_" + IJ.pad(hour,2) + "-" + IJ.pad(minute,2) + "-" + IJ.pad(second,2);
nowPretty = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dom,2)
       + " " + IJ.pad(hour,2) + ":" + IJ.pad(minute,2) + ":" + IJ.pad(second,2);

logDir = inputDir;
if (!outputModeSibling) logDir = outputRoot;
logPath = logDir + "extract_and_trim_log_" + nowStr + ".txt";
flog = File.open(logPath);

trimDesc = "DISABLED";
if (doTrim) {
    unitStr = "s"; if (!trimUnitSeconds) unitStr = " frames";
    if (trimModeChoice == trimModes[1]) trimDesc = "middle " + TRIM_AMOUNT + unitStr + " starting " + TRIM_START_SEC + "s in";
    else if (trimModeChoice == trimModes[2]) trimDesc = "keep FINAL " + TRIM_AMOUNT + unitStr;
    else trimDesc = "keep FIRST " + TRIM_AMOUNT + unitStr + " (from " + TRIM_START_SEC + "s in)";
}

print(flog, "=============================================");
print(flog, " LIF EXTRACT & TRIM (macro v" + VERSION + ")");
print(flog, " Run: " + nowPretty);
print(flog, "=============================================");
print(flog, "");
print(flog, " Input mode:      " + modeChoice);
print(flog, " ROOT INPUT:      " + inputDir);
if (!outputModeSibling) print(flog, " OUTPUT:          " + outputRoot);
print(flog, " Save untrimmed:  " + SAVE_UNTRIMMED);
print(flog, " Trim:            " + trimDesc);
print(flog, " Hz filename tag: " + HZ_LABEL + " (" + HZ_DECIMALS + " dp)");
if (modeLIF) {
    print(flog, " Rate mismatch:   " + ratePolicyChoice);
    print(flog, " TileScan filter: " + SKIP_TILESCANS);
}
print(flog, " DRY RUN:         " + DRY_RUN);
print(flog, "");

print("\\Clear");
print("LIF Extract & Trim v" + VERSION + " starting" + msg_dry() + "...");
print("Log: " + logPath);
print("");

// --- Globals ---
globalFrameInterval = -1;
totalOK = 0; totalSkippedSnap = 0; totalSkippedTile = 0; totalSkippedDone = 0;
totalSkippedNoFI = 0; totalSkippedRate = 0; totalWarnings = 0;
totalUnitsAllDone = 0; totalFailed = 0;

// ============================================================
// PASS 1: discover inputs
// ============================================================
showStatus("Scanning...");
if (modeLIF) {
    inputPaths = newArray(0);
    inputPaths = discoverLIFs(inputDir, inputPaths);
} else {
    inputPaths = listTifs(inputDir);
}
nInputs = inputPaths.length;
print("Discovered " + nInputs + " input file(s).");
print(flog, " Discovered inputs: " + nInputs);
print(flog, "");

if (nInputs == 0) {
    print(flog, " (nothing to do)");
    File.close(flog);
    exit("No input files found under " + inputDir);
}

// ============================================================
// PRE-FLIGHT CONFIRM (Cancel here aborts, writing nothing)
// ============================================================
Dialog.create("LIF Extract & Trim - confirm");
Dialog.addMessage("Ready to process " + nInputs + " input file(s).");
Dialog.addMessage("Outputs:  untrimmed=" + SAVE_UNTRIMMED + "   trim=" + trimDesc);
Dialog.addMessage("Hz label: " + HZ_LABEL + "     Dry run: " + DRY_RUN);
Dialog.addMessage("Log: " + logPath);
Dialog.addMessage("Press OK to proceed, or Cancel to abort.");
Dialog.show();

setBatchMode(true);
runStartMs = getTime();

// ============================================================
// PASS 2: process
// ============================================================
for (i = 0; i < nInputs; i++) {
    full = inputPaths[i];
    fname = File.getName(full);
    showProgress(i, nInputs);
    print("[" + (i+1) + "/" + nInputs + "] " + fname + "   " + etaString(i, nInputs, getTime()-runStartMs));
    showStatus("[" + (i+1) + "/" + nInputs + "] " + fname);

    parent = File.getParent(full);
    if (!endsWith(parent, File.separator)) parent = parent + File.separator;

    if (modeLIF) {
        if (outputModeSibling) outParent = parent;
        else {
            relParent = substring(parent, lengthOf(inputDir));
            outParent = outputRoot + relParent;
            if (!DRY_RUN) File.makeDirectory(outParent);
        }
        processLIF(full, fname, outParent, i, nInputs);
    } else {
        processTiff(full, fname, outputRoot);
    }
}
showProgress(1.0);

// ============================================================
// Footer
// ============================================================
totalSec = (getTime() - runStartMs) / 1000.0;
print(flog, "");
print(flog, "=============================================");
print(flog, " TOTALS");
print(flog, " Input files seen:              " + nInputs);
print(flog, "   ...fully skipped (done):     " + totalUnitsAllDone);
print(flog, "   ...failed (corrupt/error):   " + totalFailed);
print(flog, " Series/files saved (OK):       " + totalOK);
print(flog, " Skipped - already done:        " + totalSkippedDone);
print(flog, " Skipped - single frame:        " + totalSkippedSnap);
print(flog, " Skipped - TileScan:            " + totalSkippedTile);
print(flog, " Skipped - no frame interval:   " + totalSkippedNoFI);
print(flog, " Skipped - rate drop:           " + totalSkippedRate);
print(flog, " Warnings (rate/length):        " + totalWarnings);
if (globalFrameInterval > 0)
    print(flog, " Reference rate:                " + d2s(1/globalFrameInterval,2) + " Hz (" + d2s(globalFrameInterval,4) + " s/frame)");
print(flog, " Total runtime:                 " + formatDuration(totalSec));
if (DRY_RUN) print(flog, " (DRY RUN - no files were written)");
print(flog, "=============================================");
File.close(flog);
setBatchMode(false);

print("");
print("DONE (v" + VERSION + ")" + msg_dry() + ". " + totalOK + " saved, " + totalSkippedDone + " already done, " + totalFailed + " failed.");
print("Runtime: " + formatDuration(totalSec) + "   Log: " + logPath);
showStatus("Done: " + totalOK + " saved in " + formatDuration(totalSec));


// ============================================================
// Process one LIF
// ============================================================
function processLIF(lifPath, fname, dstParent, idx, total) {
    lifBase = fname;
    if (endsWith(toLowerCase(lifBase), ".lif")) lifBase = substring(lifBase, 0, lengthOf(lifBase)-4);

    lifOutDir    = dstParent + lifBase + File.separator;
    untrimmedDir = lifOutDir + "UNTRIMMED" + File.separator;
    trimmedDir   = lifOutDir + "TRIMMED"   + File.separator;

    if (File.length(lifPath) <= 0) { print(flog, "[FAIL] " + lifPath + "   (zero-byte file)"); totalFailed++; return; }

    Ext.setId(lifPath);
    Ext.getSeriesCount(seriesCount);

    print(flog, "---------------------------------------------");
    print(flog, " FILE: " + lifPath + "   (series: " + seriesCount + ")");

    if (!DRY_RUN) {
        File.makeDirectory(lifOutDir);
        if (SAVE_UNTRIMMED) File.makeDirectory(untrimmedDir);
        if (doTrim)         File.makeDirectory(trimmedDir);
    }

    for (s = 0; s < seriesCount; s++) {
        Ext.setSeries(s);
        Ext.getSeriesName(peekName);
        Ext.getSizeT(peekT);
        cleanPeek = stripPrefix(peekName);

        if (SKIP_TILESCANS && indexOf(peekName, "TileScan_") > -1 && indexOf(peekName, "Merging") < 0) {
            print(flog, "  [SKIP-TILE] " + cleanPeek); totalSkippedTile++; continue;
        }
        if (peekT <= 1) { print(flog, "  [SKIP-SNAP] " + cleanPeek + " | " + peekT + " frame"); totalSkippedSnap++; continue; }

        // Resume: skip if an output for this series already exists (Hz-labelled or not)
        doneU = (!SAVE_UNTRIMMED) || alreadyExtracted(untrimmedDir, cleanPeek);
        doneT = (!doTrim) || alreadyExtracted(trimmedDir, cleanPeek);
        if (doneU && doneT) { print(flog, "  [SKIP-DONE] " + cleanPeek); totalSkippedDone++; continue; }

        // Import this series (data preserved; autoscale is display-only, pixels are saved raw)
        run("Bio-Formats Importer",
            "open=[" + lifPath + "] autoscale color_mode=Default rois_import=[ROI manager] " +
            "view=Hyperstack stack_order=XYCZT series_" + (s+1));
        rawTitle = getTitle();
        totalFrames = nSlices;
        seriesName = stripPrefix(rawTitle);

        fi = frameIntervalSeconds();
        if (fi <= 0) {
            print(flog, "  [SKIP-NOFI] " + seriesName + " | " + totalFrames + " frames | no frame interval -> cannot compute Hz");
            close(); totalSkippedNoFI++; continue;
        }
        hzStr = d2s(1/fi, HZ_DECIMALS);
        fpsStr = hzStr + " Hz (" + d2s(fi,4) + " s/frame)";

        if (globalFrameInterval < 0) globalFrameInterval = fi;
        else if (abs(fi - globalFrameInterval) > 0.001) {
            if (rateDrop) {
                print(flog, "  [DROP-RATE] " + seriesName + " | " + fpsStr + " | differs from ref " + d2s(1/globalFrameInterval,2) + " Hz - DROPPED");
                close(); totalSkippedRate++; totalWarnings++; continue;
            } else {
                print(flog, "  [WARN-RATE] " + seriesName + " | " + fpsStr + " | differs from ref " + d2s(1/globalFrameInterval,2) + " Hz - saved");
                totalWarnings++;
            }
        }

        outName = labelled(seriesName, hzStr);

        // UNTRIMMED (duplicate so the source stays open for the substack)
        if (SAVE_UNTRIMMED && !alreadyExtracted(untrimmedDir, cleanPeek)) {
            if (DRY_RUN) {
                print(flog, "  [DRY-U]     " + outName + ".tif | " + fpsStr);
            } else {
                run("Duplicate...", "duplicate");
                Stack.setFrameInterval(fi); Stack.setTUnit("s");
                saveAs("Tiff", untrimmedDir + outName + ".tif");
                close();
            }
        }

        // TRIMMED
        if (doTrim && !alreadyExtracted(trimmedDir, cleanPeek)) {
            fr = computeTrimFrames(totalFrames, fi);   // "start,end,short,bad"
            parts = split(fr, ",");
            startFrame = parseInt(parts[0]); endFrame = parseInt(parts[1]);
            shortStack = (parts[2] == "1"); badTrim = (parts[3] == "1");
            if (badTrim) {
                print(flog, "  [WARN-LEN]  " + seriesName + " | " + fpsStr + " | recording shorter than trim start (" + TRIM_START_SEC + "s) - no trimmed copy written");
                totalWarnings++;
            } else {
                nKeep = endFrame - startFrame + 1;
                keptSec = d2s(nKeep * fi, 1);
                if (DRY_RUN) {
                    print(flog, "  [DRY-T]     " + outName + ".tif | frames " + startFrame + "-" + endFrame + " (" + keptSec + "s)");
                } else {
                    run("Make Substack...", "frames=" + startFrame + "-" + endFrame);
                    Stack.setFrameInterval(fi); Stack.setTUnit("s");
                    saveAs("Tiff", trimmedDir + outName + ".tif");
                    close();
                }
                if (shortStack) {
                    print(flog, "  [WARN-LEN]  " + seriesName + " | " + fpsStr + " | kept " + startFrame + "-" + endFrame + " (" + keptSec + "s) - SHORTER THAN REQUESTED");
                    totalWarnings++;
                } else {
                    print(flog, "  [OK]        " + seriesName + " | " + fpsStr + " | kept " + startFrame + "-" + endFrame + " (" + keptSec + "s)");
                }
            }
        } else if (!doTrim) {
            print(flog, "  [OK-UNTRIM] " + seriesName + " | " + fpsStr + " | UNTRIMMED only");
        }

        close();   // close the imported source
        totalOK++;
    }
    Ext.close();
    print(flog, "");
}

// ============================================================
// Process one existing TIFF (Mode 2)
// ============================================================
function processTiff(tifPath, fname, outRoot) {
    if (File.length(tifPath) <= 0) { print(flog, "[FAIL] " + tifPath + "   (zero-byte file)"); totalFailed++; return; }

    base = fname;
    dot = lastIndexOf(base, ".");
    if (dot > 0) base = substring(base, 0, dot);

    untrimmedDir = outRoot + "UNTRIMMED" + File.separator;
    trimmedDir   = outRoot + "TRIMMED"   + File.separator;

    doneU = (!SAVE_UNTRIMMED) || alreadyExtracted(untrimmedDir, base);
    doneT = (!doTrim) || alreadyExtracted(trimmedDir, base);
    if (doneU && doneT) { print(flog, "  [SKIP-DONE] " + base); totalSkippedDone++; return; }

    open(tifPath);
    totalFrames = nSlices;
    if (totalFrames <= 1) { print(flog, "  [SKIP-SNAP] " + base + " | " + totalFrames + " frame"); close(); totalSkippedSnap++; return; }

    fi = frameIntervalSeconds();
    hzStr = "NA";
    if (fi > 0) hzStr = d2s(1/fi, HZ_DECIMALS);
    else if (HZ_LABEL) print(flog, "  [WARN-NOFI] " + base + " | no frame interval -> Hz label omitted");

    outName = base;
    if (HZ_LABEL && fi > 0) outName = labelled(base, hzStr);

    if (!DRY_RUN) { if (SAVE_UNTRIMMED) File.makeDirectory(untrimmedDir); if (doTrim) File.makeDirectory(trimmedDir); }

    if (SAVE_UNTRIMMED && !alreadyExtracted(untrimmedDir, base)) {
        if (DRY_RUN) print(flog, "  [DRY-U]     " + outName + ".tif");
        else {
            run("Duplicate...", "duplicate");
            if (fi > 0) { Stack.setFrameInterval(fi); Stack.setTUnit("s"); }
            saveAs("Tiff", untrimmedDir + outName + ".tif"); close();
        }
    }
    if (doTrim && !alreadyExtracted(trimmedDir, base)) {
        useFi = fi; if (useFi <= 0) useFi = 1;   // frames-based trim still works without FI
        fr = computeTrimFrames(totalFrames, useFi);
        parts = split(fr, ",");
        startFrame = parseInt(parts[0]); endFrame = parseInt(parts[1]);
        shortStack = (parts[2] == "1"); badTrim = (parts[3] == "1");
        if (badTrim) {
            print(flog, "  [WARN-LEN]  " + base + " | recording shorter than trim start - no trimmed copy written");
            totalWarnings++;
        } else {
            if (DRY_RUN) print(flog, "  [DRY-T]     " + outName + ".tif | frames " + startFrame + "-" + endFrame);
            else {
                run("Make Substack...", "frames=" + startFrame + "-" + endFrame);
                if (fi > 0) { Stack.setFrameInterval(fi); Stack.setTUnit("s"); }
                saveAs("Tiff", trimmedDir + outName + ".tif"); close();
            }
            w = "  [OK]        "; if (shortStack) { w = "  [WARN-LEN]  "; totalWarnings++; }
            print(flog, w + base + " | frames " + startFrame + "-" + endFrame);
        }
    }
    close();
    totalOK++;
}

// ============================================================
// Helpers
// ============================================================

// Frame interval in SECONDS, normalizing ms/min units. <=0 means unknown.
function frameIntervalSeconds() {
    Stack.getUnits(xu, yu, zu, tu, vu);
    fi = Stack.getFrameInterval();
    if (tu == "ms" || tu == "msec" || tu == "millisec") fi = fi / 1000.0;
    else if (tu == "min" || tu == "minutes")            fi = fi * 60.0;
    return fi;
}

// Compute trim [startFrame,endFrame,shortFlag] as "start,end,short" for the chosen mode.
function computeTrimFrames(totalFrames, fi) {
    amt = TRIM_AMOUNT;
    nKeep = amt;
    if (trimUnitSeconds) nKeep = floor(amt / fi);
    if (nKeep < 1) nKeep = 1;
    short = 0;
    if (trimModeChoice == trimModes[1]) {          // Middle window
        startFrame = floor(TRIM_START_SEC / fi) + 1;
        endFrame = startFrame + nKeep - 1;
    } else if (trimModeChoice == trimModes[2]) {   // Keep FINAL
        endFrame = totalFrames;
        startFrame = totalFrames - nKeep + 1;
        if (startFrame < 1) { startFrame = 1; short = 1; }
    } else {                                        // Keep FIRST
        startFrame = floor(TRIM_START_SEC / fi) + 1;
        endFrame = startFrame + nKeep - 1;
    }
    if (startFrame < 1) startFrame = 1;
    if (endFrame > totalFrames) { endFrame = totalFrames; short = 1; }
    // bad = the trim window starts past the end of the recording (e.g. a clip
    // shorter than TRIM_START_SEC). Caller skips the trimmed copy instead of
    // emitting an invalid Make Substack range.
    bad = 0;
    if (startFrame > totalFrames || startFrame > endFrame) bad = 1;
    return "" + startFrame + "," + endFrame + "," + short + "," + bad;
}

// Append _<hz>Hz to a name unless it already ends that way (idempotent).
function labelled(name, hzStr) {
    if (!HZ_LABEL) return name;
    if (matches(name, ".*_[0-9]+(\\.[0-9]+)?Hz")) return name;   // already labelled
    return name + "_" + hzStr + "Hz";
}

// True if <base>.tif or <base>_<..>Hz.tif already exists in dir.
function alreadyExtracted(dir, base) {
    if (!File.exists(dir)) return false;
    arr = getFileList(dir);
    for (k = 0; k < arr.length; k++) {
        nm = arr[k];
        low = toLowerCase(nm);
        if (!(endsWith(low, ".tif") || endsWith(low, ".tiff"))) continue;
        if (nm == base + ".tif" || nm == base + ".tiff") return true;
        if (startsWith(nm, base + "_") && matches(nm, ".*_[0-9]+(\\.[0-9]+)?Hz\\.tiff?")) return true;
    }
    return false;
}

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

function listTifs(dir) {
    arr = getFileList(dir);
    out = newArray(0);
    for (k = 0; k < arr.length; k++) {
        low = toLowerCase(arr[k]);
        if ((endsWith(low, ".tif") || endsWith(low, ".tiff")) && !startsWith(arr[k], "._"))
            out = Array.concat(out, dir + arr[k]);
    }
    return out;
}

// Strip everything up to and including the LAST " - " in a series title; sanitize.
function stripPrefix(title) {
    out = title;
    p = lastIndexOf(out, " - ");
    if (p >= 0) out = substring(out, p + 3);
    out = replace(out, "/", "_");
    out = replace(out, "\\", "_");
    out = replace(out, ":", "_");
    return out;
}

function formatDuration(totalSec) {
    s = floor(totalSec); h = floor(s/3600); m = floor((s%3600)/60); sec = s%60;
    if (h > 0) return h + "h " + m + "m " + sec + "s";
    if (m > 0) return m + "m " + sec + "s";
    return sec + "s";
}

function etaString(done, total, elapsedMs) {
    if (done == 0) return "(ETA --)";
    avg = (elapsedMs/1000.0) / done;
    return "(elapsed " + formatDuration(elapsedMs/1000.0) + ", ETA " + formatDuration(avg*(total-done)) + ")";
}

function msg_dry() {
    if (DRY_RUN) return " [DRY RUN]";
    return "";
}
