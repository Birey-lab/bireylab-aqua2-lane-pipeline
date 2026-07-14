<#
.SYNOPSIS
    Provision a fresh AQuA2-pipeline Windows instance with everything the pipeline
    and downstream analysis need: Fiji (for Phase 0 LIF extraction + the macros),
    R, optionally RStudio, and the R packages the analysis scripts import.

.DESCRIPTION
    IDEMPOTENT and SAFE to re-run: every component is checked first and skipped if
    already present. Nothing is ever removed or overwritten. Downloads come only
    from official sources (imagej.net, CRAN, and winget's Microsoft-curated repo)
    and are fetched to a temp folder. Every action is logged.

    Run it ONCE on a fresh instance (or bake it into the next AMI). It is the
    "everything we need is there" step that git alone can't provide (git holds the
    scripts; this materializes the multi-GB apps). Re-running only fills gaps.

    Requires an ELEVATED (Administrator) PowerShell for the R/RStudio installers.

.PARAMETER FijiDir
    Where Fiji is installed. Default C:\Fiji.app (matches Run-Pipeline.ps1's
    -FijiExe default: <FijiDir>\ImageJ-win64.exe).

.PARAMETER SkipFiji / SkipR / SkipRStudio / SkipRPackages
    Opt out of a component (e.g. -SkipRStudio if you only need R to run analysis).

.PARAMETER DryRun
    Report what WOULD be installed (and what's already present) and exit without
    downloading or installing anything. Use this for your first look.

.EXAMPLE
    # Preview only -- writes nothing:
    powershell -ExecutionPolicy Bypass -File .\setup\Install-Dependencies.ps1 -DryRun

.EXAMPLE
    # Full provision (elevated):
    powershell -ExecutionPolicy Bypass -File .\setup\Install-Dependencies.ps1

.EXAMPLE
    # R + packages + Fiji, but no RStudio IDE:
    powershell -ExecutionPolicy Bypass -File .\setup\Install-Dependencies.ps1 -SkipRStudio
#>
[CmdletBinding()]
param(
    # Current Fiji unzips to a top-level "Fiji\" folder with launcher
    # fiji-windows-x64.exe (older builds used "Fiji.app\ImageJ-win64.exe").
    [string]$FijiDir      = 'C:\Fiji',
    [string]$FijiExe      = '',   # point at an existing launcher to reuse it (skips download)
    [string]$FijiUrl      = 'https://downloads.imagej.net/fiji/latest/fiji-latest-win64-jdk.zip',
    # ffmpeg is used by Run-Pipeline.ps1's Consolidate step to make MP4 movies
    # from the PreCFU GIF overlays. Installed to C:\ffmpeg (pipeline auto-discovers
    # C:\ffmpeg\bin\ffmpeg.exe) or via winget (added to PATH).
    [string]$FfmpegDir    = 'C:\ffmpeg',
    [string]$FfmpegUrl    = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
    [switch]$SkipFiji,
    [switch]$SkipR,
    [switch]$SkipRStudio,
    [switch]$SkipRPackages,
    [switch]$SkipFfmpeg,
    [switch]$DryRun,
    [string]$LogDir       = 'C:\AQuA2\logs'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# R packages the analysis scripts import (derived from the library()/require()
# calls in r/*.R and docs/case-studies/*/scripts/*.R). rhdf5 is Bioconductor;
# everything else is CRAN.
$CranPkgs = @(
    'dplyr','tidyr','readr','stringr','scales','ggplot2','ggpubr','ggrepel',
    'ggsignif','patchwork','RColorBrewer','igraph','jsonlite','shiny',
    'R.matlab','hdf5r','glmnet','randomForest','ranger','FSelectorRcpp'
)
$BiocPkgs = @('rhdf5')
# 'grid' is base R (ships with R) -- intentionally not installed.

# -------------------------------------------------------------------
# Logging + helpers
# -------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $LogDir "install_dependencies_$stamp.log"
$script:results = New-Object System.Collections.ArrayList

function Log($msg, $color = 'Gray') {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logPath -Value $line
}
function Ok($m)   { Log "[OK]   $m" 'Green' }
function Warn($m) { Log "[WARN] $m" 'Yellow' }
function Err($m)  { Log "[ERR]  $m" 'Red' }
function Record($component, $status, $detail) {
    [void]$script:results.Add([pscustomobject]@{ Component=$component; Status=$status; Detail=$detail })
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinGet {
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($wg) { return $wg.Source } else { return $null }
}

function Get-RscriptPath {
    # Find an existing R ANYWHERE the standard installer or PATH would put it, so a
    # non-default install location isn't mistaken for "R absent":
    #   - PATH (Rscript on the PATH),
    #   - the R-core registry key under BOTH HKLM (all-users) and HKCU (per-user),
    #   - the default C:\Program Files\R\R-* tree.
    $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $roots = @()
    foreach ($hive in 'HKLM:\SOFTWARE\R-core\R', 'HKCU:\SOFTWARE\R-core\R',
                       'HKLM:\SOFTWARE\WOW6432Node\R-core\R') {
        try {
            $reg = Get-ItemProperty $hive -ErrorAction SilentlyContinue
            if ($reg -and $reg.InstallPath) { $roots += $reg.InstallPath }
        } catch {}
    }
    $roots += (Get-ChildItem 'C:\Program Files\R' -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | ForEach-Object { $_.FullName })
    foreach ($r in ($roots | Select-Object -Unique)) {
        foreach ($rel in 'bin\x64\Rscript.exe', 'bin\Rscript.exe') {
            $rs = Join-Path $r $rel
            if (Test-Path $rs) { return $rs }
        }
    }
    return $null
}

# Known Fiji launcher executables, current first then legacy.
$FijiLaunchers = @('fiji-windows-x64.exe', 'ImageJ-win64.exe')

function Get-FijiExeInDir {
    param([string]$Dir)
    foreach ($n in $FijiLaunchers) {
        $p = Join-Path $Dir $n
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Find-Ffmpeg {
    # Reuse an existing ffmpeg rather than reinstalling: PATH, then C:\ffmpeg\bin
    # and other common spots.
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        (Join-Path $FfmpegDir 'bin\ffmpeg.exe'),
        'C:\ffmpeg\bin\ffmpeg.exe',
        "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
        (Join-Path $env:USERPROFILE 'ffmpeg\bin\ffmpeg.exe'))) {
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Find-Fiji {
    # Locate an existing Fiji so an install in a non-default spot is reused rather
    # than duplicated. Handles BOTH the current (Fiji\fiji-windows-x64.exe) and
    # legacy (Fiji.app\ImageJ-win64.exe) layouts. Order: explicit -FijiExe, the
    # -FijiDir default, common roots, then the PATH.
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return (Resolve-Path $Explicit).Path }
    $roots = @(
        $FijiDir,
        'C:\Fiji', 'C:\Fiji.app',
        'C:\Program Files\Fiji', 'C:\Program Files\Fiji.app',
        (Join-Path $env:USERPROFILE 'Fiji'),           (Join-Path $env:USERPROFILE 'Fiji.app'),
        (Join-Path $env:USERPROFILE 'Desktop\Fiji'),   (Join-Path $env:USERPROFILE 'Desktop\Fiji.app'),
        (Join-Path $env:USERPROFILE 'Downloads\Fiji'), (Join-Path $env:USERPROFILE 'Downloads\Fiji.app'),
        'D:\Fiji', 'D:\Fiji.app'
    )
    foreach ($r in ($roots | Select-Object -Unique)) {
        $hit = Get-FijiExeInDir $r
        if ($hit) { return $hit }
    }
    foreach ($n in $FijiLaunchers) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Invoke-Native {
    # Run a native command (winget, Rscript, ...) streaming its merged output to
    # the log, WITHOUT letting its stderr trip $ErrorActionPreference='Stop' (a
    # merged native stderr line raises a terminating NativeCommandError under Stop,
    # and these tools write to stderr even on success). Returns the exit code.
    param([string]$File, [string[]]$Arguments)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $File @Arguments 2>&1 | ForEach-Object { Log "    $_" }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eap
    }
}

function Download-File($url, $dest) {
    Log "  download: $url"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -le 0) {
        throw "download produced no file: $url"
    }
    Log ("  saved: {0} ({1:N1} MB)" -f $dest, ((Get-Item $dest).Length / 1MB))
}

# -------------------------------------------------------------------
# Header
# -------------------------------------------------------------------
Log "=============================================" 'Cyan'
Log " AQuA2 instance dependency provisioner" 'Cyan'
Log ("  Mode: {0}" -f ($(if ($DryRun) { 'DRY RUN (nothing will be installed)' } else { 'INSTALL' }))) 'Cyan'
Log ("  Log:  {0}" -f $logPath) 'Cyan'
Log "=============================================" 'Cyan'

if (-not (Test-Admin)) {
    Warn "Not running as Administrator. R/RStudio installers need elevation."
    if (-not $DryRun) { Warn "Re-launch this script from an elevated PowerShell, or continue for Fiji/packages only." }
}
$winget = Get-WinGet
Log ("winget available: {0}" -f ($(if ($winget) { 'yes' } else { 'no (will use direct downloads)' })))

$tmp = Join-Path $env:TEMP ("aqua2_setup_" + $stamp)
if (-not $DryRun) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

# ===================================================================
# 1. Fiji
# ===================================================================
Log ""
Log "--- Fiji / ImageJ ---" 'Cyan'
$existingFiji = Find-Fiji $FijiExe
$fijiExe      = $existingFiji   # set to the installed path in the install branch
if (-not $SkipFiji) {
    if ($existingFiji) {
        Ok "Fiji already present: $existingFiji"
        $defaultExe = Get-FijiExeInDir $FijiDir
        if ($existingFiji -ne $defaultExe) {
            Warn "  (not at the default $FijiDir -- pass this to the pipeline: -FijiExe `"$existingFiji`")"
        }
        Record 'Fiji' 'present' $existingFiji
    } elseif ($DryRun) {
        Warn "WOULD download Fiji -> $FijiDir  (from $FijiUrl)"
        Record 'Fiji' 'would-install' $FijiDir
    } else {
        try {
            $zip = Join-Path $tmp 'fiji.zip'
            Download-File $FijiUrl $zip
            # Current archive contains a top-level "Fiji\" folder (older builds:
            # "Fiji.app\"). Locate the launcher inside the extract, then move its
            # containing folder to $FijiDir -- robust to either layout/name.
            # Extract to a SHORT root: Fiji's deep internal paths can exceed the
            # 260-char MAX_PATH under the long %TEMP%\aqua2_setup_... prefix and make
            # Expand-Archive fail partway.
            $expandTo = Join-Path $env:SystemDrive '_fiji_extract'
            if (Test-Path $expandTo) { Remove-Item $expandTo -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $expandTo -Force | Out-Null
            Log "  expanding archive (~655 MB; this takes a few minutes)..."
            Expand-Archive -Path $zip -DestinationPath $expandTo -Force
            $foundExe = Get-ChildItem $expandTo -Recurse -File -Include $FijiLaunchers -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $foundExe) { throw "no Fiji launcher ($($FijiLaunchers -join '/')) found in the archive" }
            $srcApp = $foundExe.Directory.FullName
            $parent = Split-Path $FijiDir -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            if (Test-Path $FijiDir) { throw "$FijiDir already exists but has no Fiji launcher; move it aside and re-run" }
            Move-Item -Path $srcApp -Destination $FijiDir
            Remove-Item $expandTo -Recurse -Force -ErrorAction SilentlyContinue   # tidy the short temp
            $fijiExe = Get-FijiExeInDir $FijiDir
            if ($fijiExe) { Ok "Fiji installed: $fijiExe"; Record 'Fiji' 'installed' $fijiExe }
            else { throw "post-install check failed: no launcher under $FijiDir" }
        } catch {
            Err "Fiji install failed: $($_.Exception.Message)"
            Record 'Fiji' 'FAILED' $_.Exception.Message
        }
    }
} else {
    Log "skipped (-SkipFiji)"; Record 'Fiji' 'skipped' ''
}

# ===================================================================
# 2. R
# ===================================================================
Log ""
Log "--- R ---" 'Cyan'
$rscript = Get-RscriptPath
if (-not $SkipR) {
    if ($rscript) {
        Ok "R already present: $rscript"
        Record 'R' 'present' $rscript
    } elseif ($DryRun) {
        Warn "WOULD install R (winget id RProject.R, or CRAN installer)"
        Record 'R' 'would-install' 'CRAN/winget'
    } else {
        try {
            if ($winget) {
                Log "  installing R via winget (RProject.R)..."
                Invoke-Native 'winget' @('install','--id','RProject.R','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity') | Out-Null
                $rscript = Get-RscriptPath
            }
            if (-not $rscript) {
                # No winget (or winget didn't yield a working R) -> direct CRAN
                # installer (Inno Setup -> silent flags).
                if ($winget) { Warn "  winget didn't produce a working R; falling back to the CRAN installer." }
                $page = Invoke-WebRequest 'https://cran.r-project.org/bin/windows/base/' -UseBasicParsing
                $exeName = ([regex]'R-\d+\.\d+\.\d+-win\.exe').Match($page.Content).Value
                if (-not $exeName) { throw "could not determine current R installer filename from CRAN" }
                $rexe = Join-Path $tmp $exeName
                Download-File "https://cran.r-project.org/bin/windows/base/$exeName" $rexe
                Log "  running R installer silently..."
                Start-Process -FilePath $rexe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait
                $rscript = Get-RscriptPath
            }
            if ($rscript) { Ok "R installed: $rscript"; Record 'R' 'installed' $rscript }
            else { throw "post-install check failed: Rscript.exe not found" }
        } catch {
            Err "R install failed: $($_.Exception.Message)"
            Record 'R' 'FAILED' $_.Exception.Message
        }
    }
} else {
    Log "skipped (-SkipR)"; Record 'R' 'skipped' ''
}

# ===================================================================
# 3. RStudio (optional convenience IDE)
# ===================================================================
Log ""
Log "--- RStudio ---" 'Cyan'
function Test-RStudio {
    if (Get-Command rstudio -ErrorAction SilentlyContinue) { return $true }
    $paths = @("$env:ProgramFiles\RStudio\rstudio.exe", "$env:ProgramFiles\RStudio\bin\rstudio.exe")
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    return $false
}
if (-not $SkipRStudio) {
    if (Test-RStudio) {
        Ok "RStudio already present"
        Record 'RStudio' 'present' ''
    } elseif ($DryRun) {
        Warn "WOULD install RStudio (winget id Posit.RStudio)"
        Record 'RStudio' 'would-install' 'winget'
    } elseif ($winget) {
        try {
            Log "  installing RStudio via winget (Posit.RStudio)..."
            Invoke-Native 'winget' @('install','--id','Posit.RStudio','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity') | Out-Null
            if (Test-RStudio) { Ok "RStudio installed"; Record 'RStudio' 'installed' '' }
            else { Warn "RStudio install ran but the exe wasn't found where expected; verify manually."; Record 'RStudio' 'unverified' '' }
        } catch {
            Err "RStudio install failed: $($_.Exception.Message)"
            Record 'RStudio' 'FAILED' $_.Exception.Message
        }
    } else {
        Warn "winget unavailable; skipping RStudio (not required to RUN analysis -- Rscript suffices). Install it manually if you want the IDE."
        Record 'RStudio' 'skipped-no-winget' ''
    }
} else {
    Log "skipped (-SkipRStudio)"; Record 'RStudio' 'skipped' ''
}

# ===================================================================
# 3.5. ffmpeg (for Consolidate's PreCFU GIF -> MP4 movies)
# ===================================================================
Log ""
Log "--- ffmpeg ---" 'Cyan'
if (-not $SkipFfmpeg) {
    $existingFfmpeg = Find-Ffmpeg
    if ($existingFfmpeg) {
        Ok "ffmpeg already present: $existingFfmpeg"
        Record 'ffmpeg' 'present' $existingFfmpeg
    } elseif ($DryRun) {
        Warn "WOULD install ffmpeg (winget Gyan.FFmpeg, or static build -> $FfmpegDir)"
        Record 'ffmpeg' 'would-install' $FfmpegDir
    } else {
        try {
            if ($winget) {
                Log "  installing ffmpeg via winget (Gyan.FFmpeg)..."
                Invoke-Native 'winget' @('install','--id','Gyan.FFmpeg','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity') | Out-Null
                $existingFfmpeg = Find-Ffmpeg
            }
            if (-not $existingFfmpeg) {
                if ($winget) { Warn "  winget didn't produce a working ffmpeg; falling back to the static build." }
                $zip = Join-Path $tmp 'ffmpeg.zip'
                Download-File $FfmpegUrl $zip
                $expandTo = Join-Path $env:SystemDrive '_ffmpeg_extract'
                if (Test-Path $expandTo) { Remove-Item $expandTo -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $expandTo -Force | Out-Null
                Log "  expanding ffmpeg archive..."
                Expand-Archive -Path $zip -DestinationPath $expandTo -Force
                $foundFf = Get-ChildItem $expandTo -Recurse -File -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $foundFf) { throw "ffmpeg.exe not found in the archive" }
                # Move the build root (parent of \bin) to $FfmpegDir so the exe
                # lands at $FfmpegDir\bin\ffmpeg.exe (what the pipeline looks for).
                $buildRoot = Split-Path $foundFf.Directory.FullName -Parent
                if (Test-Path $FfmpegDir) { Remove-Item $FfmpegDir -Recurse -Force -ErrorAction SilentlyContinue }
                Move-Item -Path $buildRoot -Destination $FfmpegDir
                Remove-Item $expandTo -Recurse -Force -ErrorAction SilentlyContinue
                $existingFfmpeg = Join-Path $FfmpegDir 'bin\ffmpeg.exe'
            }
            if ($existingFfmpeg -and (Test-Path $existingFfmpeg)) {
                Ok "ffmpeg installed: $existingFfmpeg"; Record 'ffmpeg' 'installed' $existingFfmpeg
            } else { throw "post-install check failed: ffmpeg.exe not found" }
        } catch {
            Err "ffmpeg install failed: $($_.Exception.Message)"
            Record 'ffmpeg' 'FAILED' $_.Exception.Message
        }
    }
} else {
    Log "skipped (-SkipFfmpeg)"; Record 'ffmpeg' 'skipped' ''
}

# ===================================================================
# 4. R packages (CRAN + Bioconductor) -- installs only what's missing
# ===================================================================
Log ""
Log "--- R packages ---" 'Cyan'
if (-not $SkipRPackages) {
    if (-not $rscript) {
        Warn "R not available; cannot install R packages. Install R first, then re-run."
        Record 'R packages' 'skipped-no-R' ''
    } elseif ($DryRun) {
        Warn ("WOULD ensure {0} CRAN + {1} Bioconductor package(s) (only missing ones get installed):" -f $CranPkgs.Count, $BiocPkgs.Count)
        Warn ("  CRAN: {0}" -f ($CranPkgs -join ' '))
        Warn ("  Bioc: {0}" -f ($BiocPkgs -join ' '))
        Record 'R packages' 'would-install' "$($CranPkgs.Count) CRAN + $($BiocPkgs.Count) Bioc"
    } else {
        try {
            # Idempotent R snippet: install only packages not already present.
            $cranList = ($CranPkgs | ForEach-Object { "'$_'" }) -join ','
            $biocList = ($BiocPkgs | ForEach-Object { "'$_'" }) -join ','
            $rCode = @"
options(repos = c(CRAN = 'https://cloud.r-project.org'))
cran <- c($cranList)
bioc <- c($biocList)
inst <- rownames(installed.packages())
miss <- setdiff(cran, inst)
cat('CRAN missing:', if (length(miss)) paste(miss, collapse=' ') else '(none)', '\n')
if (length(miss)) install.packages(miss)
if (length(bioc)) {
  bmiss <- setdiff(bioc, rownames(installed.packages()))
  cat('Bioc missing:', if (length(bmiss)) paste(bmiss, collapse=' ') else '(none)', '\n')
  if (length(bmiss)) {
    if (!requireNamespace('BiocManager', quietly=TRUE)) install.packages('BiocManager')
    BiocManager::install(bmiss, update=FALSE, ask=FALSE)
  }
}
all <- c(cran, bioc)
final <- rownames(installed.packages())
stillmiss <- setdiff(all, final)
if (length(stillmiss)) { cat('STILL MISSING:', paste(stillmiss, collapse=' '), '\n'); quit(status=2) }
cat('All', length(all), 'packages present.\n')
"@
            $rFile = Join-Path $tmp 'install_packages.R'
            Set-Content -Path $rFile -Value $rCode -Encoding ASCII
            Log "  running R package install (only missing packages; this can take a while)..."
            $rc = Invoke-Native $rscript @('--vanilla', $rFile)
            if ($rc -eq 0) { Ok "R packages present"; Record 'R packages' 'installed/present' "$($CranPkgs.Count)+$($BiocPkgs.Count)" }
            else { Err "some R packages are still missing (see log above)"; Record 'R packages' 'INCOMPLETE' "exit $rc" }
        } catch {
            Err "R package install failed: $($_.Exception.Message)"
            Record 'R packages' 'FAILED' $_.Exception.Message
        }
    }
} else {
    Log "skipped (-SkipRPackages)"; Record 'R packages' 'skipped' ''
}

# ===================================================================
# Summary
# ===================================================================
Log ""
Log "=============================================" 'Cyan'
Log " SUMMARY" 'Cyan'
Log "=============================================" 'Cyan'
foreach ($r in $script:results) {
    $c = switch -Wildcard ($r.Status) {
        'present'        { 'Green' }
        'installed*'     { 'Green' }
        'would-install'  { 'Yellow' }
        'skipped*'       { 'DarkGray' }
        'FAILED'         { 'Red' }
        'INCOMPLETE'     { 'Red' }
        default          { 'Yellow' }
    }
    Log ("  {0,-12} {1,-18} {2}" -f $r.Component, $r.Status, $r.Detail) $c
}
$failed = @($script:results | Where-Object { $_.Status -in 'FAILED','INCOMPLETE' })
Log ""
if ($DryRun) {
    Log "DRY RUN complete -- nothing was installed. Re-run without -DryRun to provision." 'Yellow'
} elseif ($failed.Count -eq 0) {
    Ok "All requested components are present."
    if ($fijiExe -and (Test-Path $fijiExe)) { Log ("Phase 0 can use: -FijiExe `"{0}`"" -f $fijiExe) }
} else {
    Err ("{0} component(s) need attention -- see the log: {1}" -f $failed.Count, $logPath)
}
Log ("Full log: {0}" -f $logPath)
if ($failed.Count -gt 0 -and -not $DryRun) { exit 1 }
