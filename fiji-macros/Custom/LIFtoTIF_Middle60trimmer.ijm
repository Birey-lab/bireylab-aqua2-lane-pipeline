// ============================================================
// LIF to TIF Extractor: Trimmed + Untrimmed versions
// - Recurses all subfolders of inputDir
// - Mirrors subfolder structure in outputDir
// - One LIF_basename/TRIMMED/ and LIF_basename/UNTRIMMED/ per LIF
// - Originals NEVER modified
// - Writes formatted summary log on completion
// ============================================================

inputDir  = getDirectory("Choose ROOT INPUT folder (will recurse all subfolders)");
outputDir = getDirectory("Choose ROOT OUTPUT folder");

TARGET_SECONDS = 60;
TRIM_START_SEC = 15;

logPath = outputDir + "extraction_log.txt";
f = File.open(logPath);

getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
month = month + 1;
now = "" + year + "-" + IJ.pad(month,2) + "-" + IJ.pad(dayOfMonth,2) + " " + IJ.pad(hour,2) + ":" + IJ.pad(minute,2) + ":" + IJ.pad(second,2);

print(f, "=============================================");
print(f, " AQuA2 LIF EXTRACTION SUMMARY");
print(f, " Run: " + now);
print(f, "=============================================");
print(f, "");
print(f, " INPUT:  " + inputDir);
print(f, " OUTPUT: " + outputDir);
print(f, "");

run("Bio-Formats Macro Extensions");
setBatchMode(true);

globalFrameInterval = -1;
totalOK       = 0;
totalSkipped  = 0;
totalWarnings = 0;
totalLIFs     = 0;

processFolder(inputDir, outputDir);

print(f, "=============================================");
print(f, " TOTALS");
print(f, " LIF files processed:       " + totalLIFs);
print(f, " Series saved (OK):         " + totalOK);
print(f, " Series skipped:            " + totalSkipped);
print(f, " Warnings (rate/length):    " + totalWarnings);
if (globalFrameInterval > 0) {
    print(f, " Reference frame rate:      " + d2s(1/globalFrameInterval, 2) + " fps (" + d2s(globalFrameInterval, 4) + "s/frame)");
} else {
    print(f, " Reference frame rate:      N/A (no valid series found)");
}
print(f, "=============================================");

File.close(f);
setBatchMode(false);
print("Done! Check extraction_log.txt in your output folder.");


function processFolder(srcDir, dstDir) {
    list = getFileList(srcDir);

    for (i = 0; i < list.length; i++) {
        item = list[i];

        if (endsWith(item, "/")) {
            subSrc = srcDir + item;
            subDst = dstDir + item;
            File.makeDirectory(subDst);
            processFolder(subSrc, subDst);

        } else if (endsWith(toLowerCase(item), ".lif")) {
            processLIF(srcDir + item, item, dstDir);
        }
    }
}


function processLIF(lifPath, fname, dstDir) {
    lifBase = replace(fname, ".lif", "");
    lifBase = replace(lifBase, ".LIF", "");

    lifOutDir    = dstDir + lifBase + File.separator;
    trimmedDir   = lifOutDir + "TRIMMED"   + File.separator;
    untrimmedDir = lifOutDir + "UNTRIMMED" + File.separator;
    File.makeDirectory(lifOutDir);
    File.makeDirectory(trimmedDir);
    File.makeDirectory(untrimmedDir);

    Ext.setId(lifPath);
    Ext.getSeriesCount(seriesCount);

    print(f, "---------------------------------------------");
    print(f, " FILE: " + lifPath);
    print(f, " Series found: " + seriesCount);
    print(f, "---------------------------------------------");

    totalLIFs++;

    for (s = 0; s < seriesCount; s++) {

        run("Bio-Formats Importer",
            "open=[" + lifPath + "] " +
            "autoscale color_mode=Default rois_import=[ROI manager] " +
            "view=Hyperstack stack_order=XYCZT " +
            "series_" + (s+1));

        rawTitle    = getTitle();
        totalFrames = nSlices;

        seriesName = rawTitle;
        if (indexOf(seriesName, " - ") >= 0) {
            seriesName = substring(seriesName, lastIndexOf(seriesName, " - ") + 3);
        }

        if (totalFrames <= 1) {
            print(f, "  [SKIP] " + seriesName + padTo(seriesName, 50) + "| " + totalFrames + " frame   | reason: single frame (not a time series)");
            close();
            totalSkipped++;
            continue;
        }

        Stack.getUnits(xu, yu, zu, tu, vu);
        fi = Stack.getFrameInterval();

        if (tu == "ms" || tu == "msec" || tu == "millisec") {
            fi = fi / 1000.0;
        } else if (tu == "min" || tu == "minutes") {
            fi = fi * 60.0;
        }

        if (fi <= 0) {
            print(f, "  [SKIP] " + seriesName + padTo(seriesName, 50) + "| " + totalFrames + " frames | reason: no frame interval in metadata");
            close();
            totalSkipped++;
            continue;
        }

        fpsStr = d2s(1/fi, 2) + " fps (" + d2s(fi, 4) + "s/frame)";
        if (globalFrameInterval < 0) {
            globalFrameInterval = fi;
        } else {
            if (abs(fi - globalFrameInterval) > 0.001) {
                print(f, "  [WARN] " + seriesName + padTo(seriesName, 50) + "| " + totalFrames + " frames | " + fpsStr + " | FRAME RATE DIFFERS from reference " + d2s(1/globalFrameInterval,2) + " fps");
                close();
                totalWarnings++;
                totalSkipped++;
                continue;
            }
        }

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

        run("Make Substack...", "frames=" + startFrame + "-" + endFrame);
        Stack.setFrameInterval(fi);
        Stack.setTUnit("s");
        saveAs("Tiff", trimmedDir + seriesName + ".tif");
        close();
        close();

        if (shortStack) {
            print(f, "  [WARN] " + seriesName + padTo(seriesName, 50) + "| " + totalFrames + " frames | " + fpsStr + " | kept frames " + startFrame + "-" + endFrame + " (" + keptSec + "s) - SHORTER THAN EXPECTED");
            totalWarnings++;
        } else {
            print(f, "  [OK]   " + seriesName + padTo(seriesName, 50) + "| " + totalFrames + " frames | " + fpsStr + " | kept frames " + startFrame + "-" + endFrame + " (" + keptSec + "s)");
        }

        totalOK++;
    }

    print(f, "");
    Ext.close();
}


function padTo(s, targetLen) {
    padded = "";
    for (p = lengthOf(s); p < targetLen; p++) {
        padded = padded + " ";
    }
    return padded;
}
