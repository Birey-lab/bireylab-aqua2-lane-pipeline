# =============================================================================
# install_deps.R
# Dependency installer for the AQuA2 CFU pipeline (v4.28 / v4.30)
# Target environment: R 4.5.x on Windows (x86_64-w64-mingw32)
#
# USAGE:
#   1. Install Rtools45 FIRST (see check below), restart R, then:
#   2. source("install_deps.R")
#
# This is the SINGLE SOURCE OF TRUTH for the downstream R analysis dependencies.
# setup/Install-Dependencies.ps1 installs R + Rtools45 and then runs this script
# (with Rtools on PATH). It is idempotent: it skips anything already installed
# and only fetches what's missing. Safe to re-run after any partial failure.
# =============================================================================

# ---- 0. Stable CRAN mirror -------------------------------------------------
# cloud.r-project.org is load-balanced and more consistent than the default
# RStudio mirror, which is where the colorspace 2.1-2 404 loop tends to occur.
options(repos = c(CRAN = "https://cloud.r-project.org"))

# ---- 1. Rtools check (Windows) --------------------------------------------
# Rtools45 is REQUIRED to compile any package whose CRAN binary lags the
# current source version (e.g. colorspace 2.1-3). Without it, install.packages
# will HANG on the "install from sources?" prompt rather than error cleanly.
if (.Platform$OS.type == "windows") {
  make_path <- Sys.which("make")
  if (!nzchar(make_path)) {
    stop(paste0(
      "\n>>> Rtools45 not detected (Sys.which('make') is empty).\n",
      ">>> Install it from: https://cran.r-project.org/bin/windows/Rtools/rtools45/\n",
      ">>> Take all installer defaults (installs to C:/rtools45), then FULLY\n",
      ">>> restart R and re-run this script.\n",
      ">>> If it's installed but still not found, run:\n",
      ">>>   writeLines('PATH=\"${RTOOLS45_HOME}\\\\usr\\\\bin;${PATH}\"', '~/.Renviron')\n",
      ">>> then restart R and re-check Sys.which('make').\n"))
  } else {
    message("[deps] Rtools OK: make found at ", make_path)
  }
}

# ---- 2. Compile-from-source preference ------------------------------------
# With Rtools present, prefer building from source when the binary is stale.
# This prevents the "binary 2.1-2 not found (404)" dead-end for packages whose
# source has advanced past the last-built Windows binary.
options(install.packages.compile.from.source = "always")
Sys.setenv(R_REMOTES_UPGRADE = "never")

# ---- 3. Bioconductor: rhdf5 -----------------------------------------------
# rhdf5 reads the HDF5-backed *_AQuA2_res_cfu.mat POST files. It is NOT on
# CRAN and must come from Bioconductor.
if (!requireNamespace("BiocManager", quietly = TRUE)) {
  install.packages("BiocManager")
}
if (!requireNamespace("rhdf5", quietly = TRUE)) {
  message("[deps] Installing Bioconductor package: rhdf5")
  BiocManager::install("rhdf5", update = FALSE, ask = FALSE)
} else {
  message("[deps] rhdf5 already installed; skipping.")
}

# ---- 4. CRAN packages (direct dependencies) -------------------------------
# These are the packages the pipeline's library() calls load directly.
# Transitive dependencies (colorspace, rstatix, car, RcppArmadillo, etc.)
# are pulled in automatically by install.packages().
cran_pkgs <- c(
  "R.matlab",       # read companion *_AQuA2.mat / *_AQuA2_Ch1 metadata
  "hdf5r",          # secondary HDF5 reader / fallback
  "igraph",         # CFU relation / network graph handling
  "ggrepel",        # non-overlapping plot labels
  "glmnet",         # modeling (PART P, optional)  [compiled]
  "ranger",         # random forest modeling (PART P, optional)  [compiled]
  "FSelectorRcpp",  # feature selection (PART P, optional)  [compiled]
  "randomForest",   # RF importance (PART P, optional)  [compiled]
  "patchwork",      # multi-panel figure composition
  "cowplot",        # figure alignment / theming
  "gridExtra",      # grid-based figure layout
  "zoo",            # rolling / time-series helpers
  "ggpubr",         # publication-style ggplot wrappers
  "FSA",            # dunnTest() -> Dunn post-hoc (core stats)
  "ggsignif",       # significance bars (* / ** / ***) on plots
  "shiny",          # optional Part B/C manual annotator UI
  "data.table",     # fast fwrite() for PRISM CSV export
  "FlexParamCurve"  # parametric curve fitting (event kinetics)
)

installed <- rownames(installed.packages())
to_install <- setdiff(cran_pkgs, installed)

if (length(to_install)) {
  message("[deps] Installing missing CRAN packages: ",
          paste(to_install, collapse = ", "))
  # Answer "yes" to source-compile prompts non-interactively via the
  # compile-from-source option set above.
  install.packages(to_install, dependencies = TRUE)
} else {
  message("[deps] All direct CRAN packages already installed; skipping.")
}

# ---- 5. Verification -------------------------------------------------------
# Confirm every required package can actually be loaded (installed != loadable
# if a compile silently failed). Reports any that are missing/broken.
all_required <- c("rhdf5", cran_pkgs)
message("\n[deps] Verifying all packages load...")
missing <- character(0)
for (p in all_required) {
  ok <- requireNamespace(p, quietly = TRUE)
  if (!ok) missing <- c(missing, p)
  message(sprintf("  %-16s %s", p, if (ok) "OK" else "*** MISSING / BROKEN ***"))
}

if (length(missing)) {
  stop(paste0(
    "\n>>> These packages failed to install/load: ",
    paste(missing, collapse = ", "),
    "\n>>> If the failure was a 404 on a stale binary, retry that package with:\n",
    ">>>   install.packages('<pkg>', type = 'source')\n",
    ">>> (requires Rtools, checked at the top of this script).\n"))
} else {
  message("\n[deps] SUCCESS: all ", length(all_required),
          " required packages installed and loadable.")
  message("[deps] You can now source the AQuA2 CFU pipeline script.")
}

# ---- Notes for the operator ------------------------------------------------
# * No Python, system libraries, or external CLI tools are required. This is a
#   pure R + Rtools stack.
# * Base/recommended packages used by the pipeline (stats, utils, tools, grid,
#   parallel) ship with R and need no installation.
# * The only non-R inputs are the AQuA2 output files themselves:
#     - POST: *_AQuA2_res_cfu.mat  (HDF5, read by rhdf5)
#     - PRE:  *_AQuA2_Ch1.csv  and  *_AQuA2.mat companions
# * Known failure mode: a CRAN binary 404 (e.g. colorspace_2.1-2.zip not found)
#   means the mirror's prebuilt binary lags the current source. With Rtools
#   installed this script compiles from source automatically. WITHOUT Rtools it
#   will hang on the compile prompt -- that is not a network error.
