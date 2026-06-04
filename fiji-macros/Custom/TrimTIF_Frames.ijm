// Batch trim FINAL N timepoints from TIFF stacks
// Original files are NOT modified
// Output saved with the SAME filename into outputDir

inputDir  = getDirectory("Choose INPUT folder with TIF stacks");
outputDir = getDirectory("Choose OUTPUT folder for trimmed stacks");
frames_to_keep = getNumber("Number of FINAL frames to keep:", 2400);

fileList = getFileList(inputDir);
setBatchMode(true);

for (i = 0; i < fileList.length; i++) {

    fileName = fileList[i];
    if (!(endsWith(fileName, ".tif") || endsWith(fileName, ".tiff"))) continue;

    open(inputDir + fileName);
    origTitle = getTitle();

    // Keep original timing
    origFrameInterval = Stack.getFrameInterval();

    total = nSlices;
    if (total < frames_to_keep) {
        print("Skipping " + fileName + " (not enough frames: " + total + ")");
        close();
        continue;
    }

    start = total - frames_to_keep + 1;
    end   = total;

    // Robust trim: duplicate by stack-plane range
    dupTitle = "TRIMMED";
    run("Duplicate...", "title=[" + dupTitle + "] duplicate range=" + start + "-" + end);
    selectWindow(dupTitle);

    // Restore as t-series hyperstack: C=1, Z=1, T=frames_to_keep
    Stack.setDimensions(1, 1, frames_to_keep);
    Stack.setFrameInterval(origFrameInterval);

    print(fileName + " original=" + total + " saved=" + nSlices + " (target=" + frames_to_keep + ")");

    saveAs("Tiff", outputDir + fileName);

    close();
    selectWindow(origTitle);
    close();
}

setBatchMode(false);
print("Batch processing complete.");
