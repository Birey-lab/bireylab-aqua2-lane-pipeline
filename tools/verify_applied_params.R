#!/usr/bin/env Rscript
# verify_applied_params.R
# =============================================================================
# Confirm the detection parameters BAKED INTO an AQuA2 output .mat match the
# parameters CSV the run actually used.
#
# Why this exists: AQuA2's compiled worker reads the File1 column of
# parameters_for_batch.csv fresh from disk, once per file (aqua_lane.m:81), and
# bakes the resulting `opts` struct into <stem>_AQuA2.mat as res.opts
# (aqua_lane.m:390). This script reads res.opts back out of a finished .mat --
# the ground-truth record of what was applied to that specific recording -- and
# (optionally) diffs it against the run's parameters_for_batch_USED.csv.
#
# The .mat is MATLAB v7.3 (HDF5), so we read it with hdf5r -- no MATLAB needed.
# (hdf5r's known trouble is with MATLAB cell arrays / strings; the plain numeric
# opts scalars we read here are fine. If it ever errors on a file, the same
# fields are readable from Python h5py: h5py.File(mat)['res/opts/maxSize'][()].)
#
# Usage:
#   Rscript verify_applied_params.R <path\to\..._AQuA2.mat> [<path\to\parameters_for_batch_USED.csv>]
#
# With one arg it just prints the baked opts. With the CSV too, it prints a
# CSV-vs-baked diff and an OK / MISMATCH result for each compared parameter.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript verify_applied_params.R <_AQuA2.mat> [parameters_for_batch_USED.csv]")
}
matPath <- args[1]
csvPath <- if (length(args) >= 2) args[2] else NA_character_

if (!file.exists(matPath)) stop(sprintf("mat not found: %s", matPath))
if (!requireNamespace("hdf5r", quietly = TRUE)) {
  stop("Package 'hdf5r' is required (installed by setup/install_deps.R).")
}
suppressWarnings(suppressMessages(library(hdf5r)))

# Detection params that map 1:1 from CSV `Variable` -> opts field. frameRate,
# maxSize, minSize, spatialRes are stored as-is; a few others may be lightly
# transformed, so treat their diffs as informational, not failures.
directKeys <- c("frameRate", "spatialRes", "maxSize", "minSize")
otherKeys  <- c("minDur", "smoXY", "thrARScl", "sourceSensitivity",
                "detectGlo", "gloDur", "regMaskGap", "needTemp", "needSpa")
keys <- c(directKeys, otherKeys)

f <- H5File$new(matPath, mode = "r")
on.exit(f$close_all(), add = TRUE)

read_opt <- function(name) {
  p <- paste0("res/opts/", name)
  tryCatch(as.numeric(f[[p]]$read())[1], error = function(e) NA_real_)
}
opts <- setNames(lapply(keys, read_opt), keys)

cat(sprintf("\nBaked res.opts read from:\n  %s\n", matPath))
cat(strrep("-", 64), "\n")
for (k in keys) {
  v <- opts[[k]]
  cat(sprintf("  %-20s = %s\n", k, if (is.na(v)) "(not found)" else format(v)))
}

if (!is.na(csvPath) && file.exists(csvPath)) {
  csv  <- read.csv(csvPath, stringsAsFactors = FALSE, check.names = FALSE)
  vcol <- names(csv)[tolower(names(csv)) == "variable"][1]
  fcol <- names(csv)[tolower(names(csv)) == "file1"][1]
  if (is.na(vcol) || is.na(fcol)) {
    cat("\n(could not find Variable/File1 columns in CSV; skipping diff)\n")
  } else {
    cat(sprintf("\nCSV File1 (%s) vs baked opts:\n", basename(csvPath)))
    cat(strrep("-", 64), "\n")
    mism <- 0
    for (k in keys) {
      row <- which(csv[[vcol]] == k)
      if (length(row) == 0) next
      csvval <- suppressWarnings(as.numeric(csv[[fcol]][row[1]]))
      bak    <- opts[[k]]
      if (is.na(csvval) || is.na(bak)) {
        status <- "?"
      } else if (isTRUE(all.equal(csvval, bak, tolerance = 1e-6))) {
        status <- "OK"
      } else {
        status <- if (k %in% directKeys) "MISMATCH" else "differs*"
      }
      if (status == "MISMATCH") mism <- mism + 1
      cat(sprintf("  %-20s CSV=%-12s baked=%-12s [%s]\n", k,
                  if (is.na(csvval)) "NA" else format(csvval),
                  if (is.na(bak))    "NA" else format(bak), status))
    }
    cat(strrep("-", 64), "\n")
    if (mism == 0) {
      cat("RESULT: all directly-mapped params (frameRate/spatialRes/maxSize/minSize)\n")
      cat("        match the CSV this run used. Parameters were applied. [PASS]\n")
    } else {
      cat(sprintf("RESULT: %d directly-mapped param(s) DIFFER from the CSV. [FAIL]\n", mism))
      cat("        Most likely cause: the .mat is from an EARLIER run (resume guard\n")
      cat("        skipped it), so it carries the OLD params. Delete its _results\n")
      cat("        folder and re-run detection, or use a fresh -ProjectName. See\n")
      cat("        docs/06 Pitfall #19.\n")
    }
    cat("* 'differs' on non-direct keys can be a unit/representation transform, not an error.\n")
  }
}
cat("\n")
