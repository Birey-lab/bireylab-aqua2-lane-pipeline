// ============================================================
// Trim FINAL N timepoints from TIFF stacks (batch)
// VERSION: 1.1   (2026-06-04)
// REPO:    https://github.com/Birey-lab/bireylab-aqua2-lane-pipeline
// ------------------------------------------------------------
// CHANGELOG
//  v1.1 (2026-06-04)
//    - Added VERSION header + changelog block.
//    - Removed BOM and CRLF line endings.
//    - Added optional output suffix prompt so trimmed copies don't
//      have to share the source's filename.
//
//  v1.0 (pre-2026-06-04)
//    - Initial: keep the FINAL N frames of every TIFF in a folder,
//      preserving original frame interval and stack metadata.
//      Originals never modified.
// ============================================================

VERSION = "1.1";

inputDir       = getDirectory("Choose INPUT folder with TIF stacks");
outputDir      = getDirectory("Choose OUTPUT folder for trimmed stacks");
frames_to_keep = getNumber("Number of FINAL frames to keep:", 2400);
suffixPrompt   = getString("Output filename suffix (e.g. '_trim2400'; leave blank to keep same name):", "");

fileList = getFileList(inputDir);
setBatchMode(true);

processed = 0;
skipped   = 0;

print("\\Clear");
print("TrimTIF_Frames v" + VERSION);
print("  Input:   " + inputDir);
print("  Output:  " + outputDir);
print("  Keep:    final " + frames_to_keep + " frames");
print("  Suffix:  '" + suffixPrompt + "'");
print("");

for (i = 0; i < fileList.length; i++) {

    fileName = fileList[i];
    if (!(endsWith(fileName, ".tif") || endsWith(fileName, ".tiff"))) continue;

    open(inputDir + fileName);
    origTitle = getTitle();

    // Preserve original timing
    origFrameInterval = Stack.getFrameInterval();

    total = nSlices;
    if (total < frames_to_keep) {
        print("  [SKIP] " + fileName + " (not enough frames: " + total + " < " + frames_to_keep + ")");
        close();
        skipped++;
        continue;
    }

    start = total - frames_to_keep + 1;
    end   = total;

    dupTitle = "TRIMMED";
    run("Duplicate...", "title=[" + dupTitle + "] duplicate range=" + start + "-" + end);
    selectWindow(dupTitle);

    // Restore as t-series hyperstack: C=1, Z=1, T=frames_to_keep
    Stack.setDimensions(1, 1, frames_to_keep);
    Stack.setFrameInterval(origFrameInterval);

    // Build output filename
    if (suffixPrompt == "") {
        outName = fileName;
    } else {
        // Insert suffix before extension
        dot = lastIndexOf(fileName, ".");
        if (dot < 0) {
            outName = fileName + suffixPrompt;
        } else {
            outName = substring(fileName, 0, dot) + suffixPrompt + substring(fileName, dot);
        }
    }

    print("  [OK]   " + fileName + " original=" + total + " saved=" + nSlices + " -> " + outName);

    saveAs("Tiff", outputDir + outName);

    close();
    selectWindow(origTitle);
    close();

    processed++;
}

setBatchMode(false);
print("");
print("Done. Processed " + processed + " file(s), skipped " + skipped + ".");
