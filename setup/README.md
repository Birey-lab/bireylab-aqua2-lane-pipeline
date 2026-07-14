# setup/ — one-time instance provisioning

Everything the pipeline and downstream analysis need that **isn't** in git (git holds
the scripts; these are the multi-GB apps): **Fiji**, **R**, optionally **RStudio**, and
the **R packages** the analysis scripts import.

## Install-Dependencies.ps1

Run it **once** on a fresh instance (or bake it into the next AMI). It is:

- **Idempotent** — every component is checked first and skipped if already present;
  safe to re-run to fill gaps. Nothing is ever removed.
- **Official sources only** — Fiji from imagej.net, R from CRAN, RStudio via winget.
- **Logged** — full transcript under `C:\AQuA2\logs\install_dependencies_<time>.log`.

```powershell
# Preview only (writes nothing) -- do this first:
powershell -ExecutionPolicy Bypass -File .\setup\Install-Dependencies.ps1 -DryRun

# Full provision (run from an ELEVATED PowerShell):
powershell -ExecutionPolicy Bypass -File .\setup\Install-Dependencies.ps1

# Variations:
#   -SkipRStudio      R only (enough to RUN the analysis; no IDE)
#   -SkipFiji         if Fiji is already installed elsewhere
#   -FijiDir D:\Fiji      install Fiji somewhere other than C:\Fiji
```

After it finishes, `C:\Fiji\fiji-windows-x64.exe` is the default `-FijiExe` for
`Run-Pipeline.ps1`'s Phase 0 LIF extraction, so no extra flag is needed. (Older
Fiji builds use `Fiji.app\ImageJ-win64.exe`; the script detects either.)

### What gets installed

| Component | Default | Source | How |
|---|---|---|---|
| Fiji/ImageJ | `C:\Fiji` (bundled JDK) | downloads.imagej.net | download + unzip |
| R | latest | CRAN / winget `RProject.R` | silent installer |
| RStudio | latest | winget `Posit.RStudio` | silent installer (skipped if no winget) |
| ffmpeg | `C:\ffmpeg` | winget `Gyan.FFmpeg` / gyan.dev | winget, else static build unzip |
| R packages | — | CRAN + Bioconductor | `install.packages` / `BiocManager` (missing only) |

ffmpeg is used by the pipeline's Consolidate step to turn PreCFU GIF overlays into
MP4 movies. `-SkipFfmpeg` to opt out; the pipeline degrades gracefully (skips the
Movies folder with a warning) if it's absent.

R packages provisioned (from `library()`/`require()` in the analysis scripts):
`dplyr tidyr readr stringr scales ggplot2 ggpubr ggrepel ggsignif patchwork
RColorBrewer igraph jsonlite shiny R.matlab hdf5r glmnet randomForest ranger
FSelectorRcpp` (CRAN) and `rhdf5` (Bioconductor). `grid` is base R.
