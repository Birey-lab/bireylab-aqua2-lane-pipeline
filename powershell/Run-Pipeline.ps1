<#
.SYNOPSIS
    End-to-end AQuA2 pipeline orchestrator with explicit per-phase toggles.
    Version 0.10.0-dev (unreleased; targeting v0.10.0). Base tag: v0.9.1.

.DESCRIPTION
    v0.10.0 (unreleased) changes: optional Phase 0 input prep + Movies + presets/GUI.
    - Phase 0 (optional): start from LIF files, or trim/Hz-label existing TIFFs, before
      Split. Headless Bio-Formats port of LIF_Extract_and_Trim.ijm
      (fiji-macros/lif_extract_headless.py, config via LIF_EXTRACT_CONFIG env var).
      Params: -LIFSource, -DetectOn, -SaveUntrimmed, -TrimMode/-TrimStartSec/
      -TrimAmount/-TrimUnit, -HzLabel/-HzDecimals, -RatePolicy, -SkipTileScans,
      -ExtractDryRun, -FijiExe. No -LIFSource and no -TrimMode = TIFF start as before.
    - Movies (Consolidate): each <stem>_AQuA2_Movie.tif (multi-frame TIFF) -> MP4 in
      for_upload\Movies\ via Fiji (stack -> lossless PNG AVI) -> ffmpeg (AVI -> H.264).
      ffmpeg can't read multi-page TIFF directly (first page only). Params: -MovieCrf
      (default 17), -MovieLossless, -MovieAviCompression (default PNG), -MovieFps
      (default 20), -SkipMovies, -FfmpegExe. Optional + NON-FATAL (warns+skips if Fiji
      or ffmpeg missing). Engine: fiji-macros/movies_to_avi.py.
    - Consolidate input_TIFFs\ mirrors the original LIF subfolder tree (both UNTRIMMED
      and TRIMMED) when a run extracted from LIF; flat for TIFF-start runs.
    - Both headless Fiji launches pass ArgumentList as an ARRAY ('--headless','--run',
      $engine): the single joined-string form made the launcher reject --run.
    - Default -OutputRoot is now <Documents>\AQuA2_runs (was mandatory).
    - Preset library (-ParamPreset <name> -> cfg/presets/<name>.csv; Save-Preset.ps1)
      and a WinForms GUI launcher (New-Run.ps1). Params used are always written into
      each run's output, so provenance travels with the data (no git needed).
    See CHANGELOG.md.

    v0.9.1 changes: stall-detector correctness + splitter recursion, all found
    during the first full-scale real-data run (292 TIFFs).
    - Per-lane stall counters no longer false-fire. The DETECTION per-lane counter
      and Find-StuckFile used `Get-ChildItem -Include` with no `-Recurse`, which
      matches nothing, so every lane's completion count was pinned at 0 -> endless
      false [STALL WARN]/[ESCALATED]/[AUTO-SKIP] (and auto-skip was a silent no-op).
      Added `-Recurse`. The CFU per-lane counter failed differently: it recursed
      from the lane root, but CFU lanes are directory JUNCTIONS and `-Recurse`
      doesn't reliably cross reparse points -> also pinned at 0. Now enumerates each
      junction and reads it via direct access. Net: auto-skip fires only on genuine
      hangs (important, since the CFU auto-skip kills the worker).
    - Splitter can recurse. Split-IntoLanes.ps1 gains an opt-in `-Recurse` (with a
      hard duplicate-filename collision guard); Run-Pipeline.ps1 gains `-RecurseInput`
      that drives BOTH the splitter and the pre-flight input count, so they always
      agree (previously pre-flight recursed while Split took top-level only, so
      nested inputs counted N but Split moved 0 and Detect died mid-run).
    - Cosmetic: "Junctions ready: N lane folders" counted with `^lane`, which never
      matches `cfu_laneNN` -> always printed 0. Fixed to `^cfu_lane`.

    v0.9.0 changes: adds the consolidated Fiji input-prep tool
    (fiji-macros/LIF_Extract_and_Trim.ijm: .lif -> raw + trimmed TIFFs with the
    measured Hz appended to each filename). Run-Pipeline.ps1 itself is UNCHANGED
    from v0.8.5. See CHANGELOG.md.

    v0.8.5 changes: docs-only release. AWS pricing figures reconciled to broad,
    consistent ranges (docs/03 is the cost reference; ~$0.06/vCPU-hr + AWS
    calculator link); intended git-pull update model documented in the README.
    No code change. See CHANGELOG.md.

    v0.8.4 changes: repo-level consistency release. Run-Pipeline.ps1 itself is
    unchanged; the code change is in Launch-CFU-Lanes.ps1 (its default -LogDir now
    derives from -LaneRoot, resolving the standalone log-collision footgun in
    docs/06 Pitfall #7). Docs + CHANGELOG consistency pass. See CHANGELOG.md.

    v0.8.3 changes (diagnosability):
    - Failures are now grouped by a normalized error signature in
      failures_summary_<phase>.md, so systemic problems (e.g., 12 files with the
      same "Index exceeds array bounds") are obvious vs one-off bad files.
    - The end-of-run summary prints an explicit "ISSUES DETECTED" block (console +
      RUN_SUMMARY.md) covering count mismatches, per-file failures, stalls, lanes
      that died at startup (.err with content), and detection incompleteness --
      instead of leaving the operator to infer problems from the raw counts.
    - Pre-flight runs a config sanity check on parameters_for_batch.csv (frameRate
      plausible, maxSize / spatialRes present) to catch misconfiguration up front.
    - Companion read-only triage script Get-PipelineStatus.ps1 gives a one-command
      health report for any project (including finished/archived runs).

    v0.8.2 changes (observability + correctness):
    - An INCOMPLETE detection no longer writes a PHASE_detect_COMPLETE marker; it
      writes PHASE_detect_INCOMPLETE instead (and clears any stale COMPLETE marker),
      so the plan-summary "PREVIOUSLY COMPLETED" hint can't misrepresent a partial run.
    - Consolidate prints periodic progress (every 100 stems) so a large run isn't
      silent for minutes during hardlinking.

    v0.8.1 changes (correctness):
    - Consolidate and Upload now honor the detection-completeness gate. v0.8.0
      refused CFU on an incomplete detection but still consolidated (and could
      upload) the partial PreCFU set, which re-opened the exact "partial looks
      complete" hole the gate was meant to close. Both phases now no-op with a
      clear error when detection did not finish for all real inputs in this run.
    - CFU stall auto-skip message corrected: it kills the worker and writes a
      _STALLED_ marker (no file move, no auto-restart, because CFU lanes are
      junctions). The previous "moving stuck file aside and restarting" text
      described detection behavior, not CFU behavior.
    - Upload now reports the ACTUAL number of files synced (counted from the real
      `aws s3 sync` output via Tee-Object) instead of echoing the dry-run
      prediction as if it were the result.
    - Post-CFU completeness check: warns prominently if fewer _res_cfu.mat files
      were produced than _AQuA2.mat inputs (detection had a bounded auto-relaunch
      for this; CFU previously just exited silently when a worker died).
    - RUN_SUMMARY.md phase table now lists the Consolidate phase.

    v0.8.0 changes:
    - CRITICAL (correctness): detection no longer reports COMPLETE just because
      all workers exited. It now compares real-input count (excluding macOS ._
      AppleDouble sidecars) to _AQuA2.mat output count. If outputs < inputs it
      auto-relaunches the lane workers (bounded by -MaxDetectRelaunch, default 3;
      completed files are skipped on relaunch), and if still short it marks the
      run detectionIncomplete and refuses to proceed to CFU. This prevents a
      silently half-processed dataset from looking "done" (root cause of the
      DGvsCA_C4and8858 incident: a ._ stub killed each lane and the run reported
      fail 0 / COMPLETE at 50%).
    - AppleDouble (._*) files are now excluded everywhere: the lane TIFF count,
      the completeness check, and the input_TIFFs consolidation. Split-IntoLanes
      and aqua_lane.m also drop them at the source. (They have a .tif extension
      but are not images; the Tiff reader throws a fatal on them.)
    - Consolidate now defaults ON (-Consolidate $true) so every run leaves a
      clean for_upload/ ready for S3. The exact parameters_for_batch_USED.csv
      (named <ProjectName>_...) and RUN_SUMMARY.md are copied into it for
      provenance.
    - NEW -Cleanup switch (default OFF, destructive): after a VERIFIED consolidate
      (counts must match sources), removes intermediates (lanes/, CFU_lanes/,
      PreCFU/, POST/) using junction-aware deletion (CFU_lanes junctions removed
      before their PreCFU targets, via rmdir without /s so targets are never
      followed) and renames for_upload/ -> <ProjectName>_AQuA2/, leaving one
      self-contained, S3-ready folder.

    v0.7.4 fixes (CRITICAL):
    - Per-lane completion counter was checking wrong path. The worker
      writes outputs to PreCFU/laneNN_results/<stem>_AQuA2.mat, but the
      orchestrator was looking at PreCFU/<stem>/<stem>_AQuA2.mat. Result:
      counter was always 0 even when workers were completing successfully,
      so stall detection fired false positives at 15 min for every lane.
      AT 60 MIN: Find-StuckFile would have classified completed TIFFs as
      stuck and Invoke-AutoSkipFile would have quarantined valid data
      AND restarted already-exited workers. Fixed by recursive name-match
      against actual worker output paths.
    - Three-stage stall thresholds (per user request):
        Stage 1 WARN      at -StallWarnMin     (default 30 min)
        Stage 2 ESCALATE  at -StallEscalateMin (default 45 min, red banner)
        Stage 3 AUTO-SKIP at -StallAutoSkipMin (default 60 min)
    - Same fixes applied to CFU phase stall tracking.

    v0.7.3 fix: Show-CSVValues uses Import-Csv on actual multi-column
    parameters_for_batch.csv format; detectGlo gets prominent ON/OFF
    visual marker.

    v0.7.2 fix: PreCFU consolidation gathers ALL accessory files per
    stem via "<stem>*" filter.

    v0.7.1 fix: PreCFU per-stem subfolders + hardlinks not copies.

.DESCRIPTION
    Runs any subset of the pipeline phases on a folder of TIFFs:
      Phase 0 - Auto-size detection lanes (if -Lanes not specified)
      Phase 1 - Split TIFFs into balanced lane folders   (-Split,       default ON)
      Phase 2 - Detection (parallel aqua_lane.exe)       (-Detect,      default ON)
      Phase 3 - CFU build + run                          (-CFU,         default ON in v0.7)
      Phase 4 - Consolidate outputs into for_upload/     (-Consolidate, default ON in v0.8; also auto-ON if Upload)
      Phase 5 - S3 upload                                (-Upload,      default OFF)

    REQUIRED parameters: -OutputRoot AND -ProjectName.
    All data + audit content lives at <OutputRoot>/<ProjectName>/.

    v0.7 changes from v0.6.3:
    - -ProjectName is now REQUIRED. Project dir = <OutputRoot>/<ProjectName>/.
    - Default CFU is now ON (Split + Detect + CFU run together).
    - NEW Consolidate phase creates a flat layout at
      <projectRoot>/for_upload/ with:
        - input_TIFFs/   (LIF runs: mirrors the original LIF tree, both UNTRIMMED
                          + TRIMMED; TIFF-start runs: flat hardlinks)
        - PreCFU/        (per-stem subfolders with _AQuA2.mat)
        - PostCFU/       (flat; one _res_cfu.mat per stem)
        - Movies/        (one .mp4 per AQuA2 _Movie.tif overlay; needs Fiji + ffmpeg)
      Upload phase syncs for_upload/ to S3.
    - Per-run audit subfolder _logs/run_<timestamp>[_<RunName>]/ contains
      all audit artifacts for this run.
    - Stall detection: warns at -StallWarnMin (default 15 min) and (if
      policy is auto-skip) moves the stuck file aside + restarts that
      lane's worker at -StallAutoSkipMin (default 60 min).
    - Final summary shows stalled files prominently with file paths.
    - Stale _ERROR.txt files at phase start are snapshotted; the "fail N"
      counter shows only NEW failures from this run.
    - ConfigCSV resolution simplified to -ConfigCSV or default (no
      auto-detect or prompts); Show-CSVValues displays key values in plan
      summary so you can sanity-check.
    - Phase markers dual-written: top-level for resume detection,
      per-run for historical record.
    - Split phase warns explicitly that it MOVES files.

    The default (v0.8+) runs Split + Detect + CFU + Consolidate ON and Upload
    OFF, so a routine invocation leaves a clean for_upload/ ready for S3 without
    publishing anything automatically. The safety net against committing CFU to a
    broken detection is no longer a manual checkpoint but the v0.8 completeness
    gate: detection auto-relaunches if outputs < real inputs, and CFU/Consolidate/
    Upload refuse to run on a detection that still did not finish (see v0.8.0 and
    v0.8.1 changes above). To stop after detection for manual inspection, pass
    -CFU $false.

    Pre-flight checks run BEFORE any heavy work. Pre-flight summary prints
    the plan with checkmarks and requires confirmation (skip with -Force).

    Real-time progress prints every 60 seconds during long phases, with a
    detailed snapshot every 5 minutes.

    Individual scripts (Split-IntoLanes.ps1, Launch-Lanes-Exe.ps1, etc.)
    still work standalone for step-by-step users.

.PARAMETER InputTIFFs
    Folder containing TIFFs to process. Required if -Split is true.

.PARAMETER OutputRoot
    Root for all pipeline outputs. Subfolders created automatically:
      <OutputRoot>/lanes/      detection lane staging
      <OutputRoot>/PreCFU/     detection outputs (_AQuA2.mat)
      <OutputRoot>/CFU_lanes/  CFU lane junctions
      <OutputRoot>/POST/       CFU outputs (_res_cfu.mat)
      <OutputRoot>/_logs/      pipeline logs

.PARAMETER Split
    Run Phase 1 (split TIFFs into lanes). Default: $true.

.PARAMETER Detect
    Run Phase 2 (detection). Default: $true.

.PARAMETER CFU
    Run Phase 3 (CFU build + run, combined). Default: $false.

.PARAMETER Upload
    Run Phase 4 (S3 sync). Default: $false. Requires -S3Prefix.

.PARAMETER Lanes
    Detection lane count. If 0 (default), runs Auto-Size-Lanes.ps1 first.

.PARAMETER CFULanes
    CFU lane count. If 0 (default), uses floor(Lanes * 0.75).

.PARAMETER ConfigCSV
    Path to a parameters_for_batch.csv to use for THIS dataset. If specified,
    the orchestrator backs up the existing default and copies this CSV into
    C:\AQuA2\cfg\parameters_for_batch.csv before launching detection.
    If omitted, uses whatever is already at the default location.

.PARAMETER S3Prefix
    Required if -Upload $true. Destination like s3://bucket/prefix/

.PARAMETER MinFreeDiskGB
    Abort detection if free disk drops below this on C:\. Default: 50.

.PARAMETER Force
    Skip the pre-flight "Proceed?" confirmation prompt.

.PARAMETER WhatIfMode
    Show plan + pre-flight without executing anything.

.PARAMETER PollEverySec
    Seconds between one-line status updates. Default: 60.

.PARAMETER DetailEverySec
    Seconds between detailed snapshots. Default: 300.

.PARAMETER ScriptsDir
    Folder containing the other pipeline scripts. Default: this script's folder.

.EXAMPLE
    # Default: split + detection only, stop and let user inspect
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS

.EXAMPLE
    # With custom parameter CSV
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS `
                       -ConfigCSV C:\NewDS\my_params.csv

.EXAMPLE
    # Continue to CFU after reviewing detection results
    .\Run-Pipeline.ps1 -OutputRoot C:\NewDS -Split $false -Detect $false -CFU $true

.EXAMPLE
    # Full end-to-end including upload, no confirmation prompt
    .\Run-Pipeline.ps1 -InputTIFFs C:\NewDS\AllTIFFs -OutputRoot C:\NewDS `
                       -CFU $true -Upload $true `
                       -S3Prefix s3://bireylab-arvin-us-east-2/CalciumImagingAnalysis/NewDS/ `
                       -Force
#>

[CmdletBinding()]
param(
    [string]$InputTIFFs,
    # Default output root under the user's Documents (keeps run data off the
    # crowded C:\ root). Override with -OutputRoot. Created if it doesn't exist.
    [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AQuA2_runs'),
    [Parameter(Mandatory=$true)] [string]$ProjectName,

    # --- Phase toggles (default ON ON ON OFF OFF) ---
    [bool]$Split        = $true,
    [bool]$Detect       = $true,
    [bool]$CFU          = $true,
    [bool]$Consolidate  = $true,    # v0.8: default ON -- always leave a clean for_upload/. Gated so it no-ops if CFU produced nothing.
    [bool]$Upload       = $false,
    [bool]$Cleanup      = $false,   # v0.8: destructive -- remove intermediates + rename to <ProjectName>_AQuA2/. OFF by default; verified before deleting.
    [int]$MaxDetectRelaunch = 3,    # v0.8: bounded auto-relaunch if detection workers die with files remaining
    [switch]$RecurseInput,          # v0.9.1: recurse into -InputTIFFs subfolders when splitting (default OFF = top-level only). Keeps the pre-flight count and the splitter consistent.

    # --- Detection parameters ---
    [int]$Lanes = 0,
    [string]$ConfigCSV = '',
    # Named parameter preset from the repo's cfg/presets/<name>.csv (versioned in
    # git; travels via git pull). Sugar for -ConfigCSV cfg/presets/<name>.csv.
    [string]$ParamPreset = '',

    # --- CFU parameters ---
    [int]$CFULanes = 0,

    # --- Upload ---
    [string]$S3Prefix = '',

    # --- Run identification ---
    [string]$RunName = '',

    # --- Stall detection (three-stage) ---
    # At StallWarnMin: print yellow [STALL WARN] with lane log tail (first heads-up)
    # At StallEscalateMin: print red [STALL ESCALATED] with louder formatting (still no destructive action; gives you a chance to manually intervene)
    # At StallAutoSkipMin: auto-skip the stuck file (if policy = auto-skip), restart lane worker
    [int]$StallWarnMin = 30,
    [int]$StallEscalateMin = 45,
    [int]$StallAutoSkipMin = 60,
    [ValidateSet('warn-only','auto-skip')]
    [string]$StallPolicy = 'auto-skip',

    # --- Safety / behavior ---
    [int]$MinFreeDiskGB = 50,
    [int]$PollEverySec = 60,
    [int]$DetailEverySec = 300,
    [switch]$Force,
    [switch]$WhatIfMode,

    # --- Phase 0: optional extract/trim (v0.10) ---
    # A Phase-0 step drives Fiji headless (fiji-macros/lif_extract_headless.py) to
    # produce trimmed, Hz-labelled TIFFs, then feeds the chosen set into Split. It
    # runs when EITHER -LIFSource is given (extract .lif series) OR -InputTIFFs is
    # given with a -TrimMode other than 'none' (trim an existing TIFF folder).
    # Plain TIFF start with -TrimMode none skips Phase 0 entirely, as before.
    [string]$LIFSource = '',
    [ValidateSet('trimmed','untrimmed','auto')][string]$DetectOn = 'auto',  # which extracted set feeds detection
    [bool]$SaveUntrimmed = $true,
    # Trim window position: first = beginning (after an optional -TrimStartSec
    # lead-in to skip), middle = centered, last = end. Duration is frame-based, so
    # it needn't divide evenly (e.g. 60s @ 19.07Hz keeps 1144 frames ~= 59.95s).
    [ValidateSet('none','middle','last','first')][string]$TrimMode = 'none',
    [double]$TrimStartSec = 0,     # 'first' lead-in to skip (0 = from the very start); ignored by middle/last
    [double]$TrimAmount = 60,
    [ValidateSet('seconds','frames')][string]$TrimUnit = 'seconds',
    [bool]$HzLabel = $true,
    [int]$HzDecimals = 2,
    [ValidateSet('warn','drop')][string]$RatePolicy = 'warn',
    [bool]$SkipTileScans = $true,
    [switch]$ExtractDryRun,
    # Cap Phase 0 extraction to the first N series per LIF (0 = all). For fast
    # end-to-end smoke tests: extract a handful, run the full chain, then re-run
    # with 0 for the real thing. Only affects extraction, not detection.
    [int]$ExtractMaxSeries = 0,
    # Current Fiji installs as C:\Fiji\fiji-windows-x64.exe; older ones use
    # C:\Fiji.app\ImageJ-win64.exe. Pre-flight auto-discovers either if this
    # default isn't present.
    [string]$FijiExe = 'C:\Fiji\fiji-windows-x64.exe',

    # --- Consolidate: MP4 movies from the AQuA2 _Movie.tif overlays ---
    # Consolidate converts each PreCFU <stem>_AQuA2_Movie.tif (a multi-frame stack)
    # to an .mp4 under for_upload\Movies\, via Fiji (stack -> AVI) then ffmpeg
    # (AVI -> MP4) -- ffmpeg alone can't read multi-page TIFF. Needs both Fiji and
    # ffmpeg (setup\Install-Dependencies.ps1). Missing either -> skipped, never
    # fatal. Reading big movie TIFFs is slow; -SkipMovies to opt out.
    [switch]$SkipMovies,
    [string]$FfmpegExe = 'ffmpeg',
    [int]$MovieFps = 20,    # frame rate for the AQuA2 movie MP4s (Fiji AVI -> ffmpeg)
    # Movie quality. The Fiji->AVI hop is LOSSLESS (PNG); the only lossy step is
    # ffmpeg's H.264 encode. -MovieCrf sets that quality: lower = higher fidelity
    # / bigger file (17 is visually transparent; 23 is ffmpeg's default). Ignored
    # when -MovieLossless is set, which encodes mathematically lossless (qp 0,
    # yuv444p = no color subsampling) -- best possible, but larger files that
    # won't play in Safari/QuickTime. Default yuv420p is universally playable.
    [ValidateRange(0,51)][int]$MovieCrf = 17,
    [switch]$MovieLossless,
    [ValidateSet('PNG','Uncompressed','JPEG')][string]$MovieAviCompression = 'PNG',

    [string]$ScriptsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# Sanitize ProjectName to be filesystem-safe
$ProjectName = $ProjectName -replace '[^A-Za-z0-9_\-\.]', '_'
if (-not $ProjectName) {
    throw "ProjectName cannot be empty or all invalid characters."
}

# Auto-enable Consolidate when Upload is on (otherwise leave as user specified)
if ($Upload -and -not $Consolidate) {
    $Consolidate = $true
}

# ==========================================================
# Output helpers
# ==========================================================
function Hdr($txt) {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host (" $txt") -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
}
function Phase($num, $name) {
    Write-Host ""
    Write-Host ("[PHASE {0}] {1}" -f $num, $name) -ForegroundColor Green
    Write-Host ("  Started: {0}" -f (Get-Date -Format 'HH:mm:ss'))
    Write-Host ""
}
function PhaseEnd($num, $name, $start, $extra) {
    $dur = (Get-Date) - $start
    Write-Host ""
    Write-Host ("[PHASE {0} COMPLETE] {1}" -f $num, $name) -ForegroundColor Green
    Write-Host ("  Duration: {0:hh\:mm\:ss}" -f $dur)
    if ($extra) { Write-Host "  $extra" }
}
function Note($txt)  { Write-Host "  $txt" }
function OK2($txt)   { Write-Host "  [OK]   $txt" -ForegroundColor Green }
function Warn2($txt) { Write-Host "  [WARN] $txt" -ForegroundColor Yellow }
function Err2($txt)  { Write-Host "  [ERR]  $txt" -ForegroundColor Red }
function Get-FreeGB { [math]::Round((Get-PSDrive C).Free / 1GB, 1) }
function Get-AvailRAMGB {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    } catch { return -1 }
}

# ==========================================================
# Audit-trail helpers
# ==========================================================
function Get-LanePID {
    # Find PID of aqua_lane.exe (or cfu_lane.exe) processing a given lane folder
    # by matching the FULL lane path in the process's CommandLine.
    # Using full path avoids lane2-vs-lane20 substring collisions.
    param([string]$LaneFolder, [string]$WorkerExeName)
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = '$WorkerExeName'" -ErrorAction SilentlyContinue
        $pattern = [regex]::Escape($LaneFolder)
        foreach ($p in $procs) {
            if ($p.CommandLine -and ($p.CommandLine -match $pattern)) {
                return $p.ProcessId
            }
        }
    } catch { }
    return $null
}

function Find-StuckFile {
    # Given a lane folder and a results root, find the .tif that's most likely the stuck file.
    # A TIFF is "stuck" if no corresponding _AQuA2.mat exists ANYWHERE under the results root.
    # We search recursively because the worker writes to subfolders like lane01_results/.
    param([string]$LaneFolder, [string]$ResultsRoot)
    # NOTE: -Recurse is REQUIRED. Get-ChildItem -Include matches nothing unless the path
    # ends in \* or -Recurse is present; without it $laneTiffs is always empty and this
    # helper returns $null, silently disabling auto-skip. (v0.9.1 fix.)
    $laneTiffs = @(Get-ChildItem $LaneFolder -File -Recurse -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                   Where-Object { $_.Directory.FullName -notmatch '\\_stalled(\\|$)' })
    foreach ($t in $laneTiffs) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($t.Name)
        # Search ANYWHERE under ResultsRoot for "<stem>_AQuA2.mat"
        $foundMat = Get-ChildItem $ResultsRoot -Recurse -Filter "${stem}_AQuA2.mat" -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if (-not $foundMat) {
            return $t  # FileInfo of stuck file
        }
    }
    return $null
}

function Invoke-AutoSkipFile {
    # When auto-skip policy fires, move stuck file aside and restart the lane worker.
    # Returns $true if a skip was performed, $false otherwise.
    param(
        [string]$LaneFolder,
        [string]$ResultsRoot,
        [string]$WorkerExe,    # full path to aqua_lane.exe
        [string]$LogPath,      # full path to lane log
        [string]$StallLogPath  # full path to stall_log.txt
    )
    $laneName = Split-Path $LaneFolder -Leaf
    $stuck = Find-StuckFile -LaneFolder $LaneFolder -ResultsRoot $ResultsRoot
    if (-not $stuck) {
        return $false
    }
    Warn2 ("Stall auto-skip: {0} stuck on {1}" -f $laneName, $stuck.Name)

    # Identify and kill the worker for this lane
    $exeName = Split-Path $WorkerExe -Leaf
    $stuckPID = Get-LanePID -LaneFolder $LaneFolder -WorkerExeName $exeName
    if ($stuckPID) {
        Warn2 ("Killing stuck worker PID {0}..." -f $stuckPID)
        Stop-Process -Id $stuckPID -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Warn2 "Could not identify stuck worker PID by lane match. Continuing with file quarantine anyway."
    }

    # Move stuck file to _stalled/ subfolder
    $stalledDir = Join-Path $LaneFolder "_stalled"
    if (-not (Test-Path $stalledDir)) { New-Item -ItemType Directory -Path $stalledDir -Force | Out-Null }
    try {
        Move-Item -Path $stuck.FullName -Destination (Join-Path $stalledDir $stuck.Name) -Force
        Warn2 ("Moved {0} -> {1}\" -f $stuck.Name, $stalledDir)
    } catch {
        Err2 ("Could not move stuck file: {0}" -f $_.Exception.Message)
        return $false
    }

    # Append to stall log
    $entry = @"
[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')] Auto-skip on lane $laneName
  Stuck file: $($stuck.FullName)
  Quarantined to: $stalledDir\$($stuck.Name)
  Killed worker PID: $stuckPID
  Worker exe: $WorkerExe
"@
    Add-Content -Path $StallLogPath -Value $entry

    # Restart the worker on this lane (it will skip done files + the quarantined one)
    try {
        $proc = Start-Process -FilePath $WorkerExe `
            -ArgumentList "`"$LaneFolder`"", "`"$ResultsRoot`"" `
            -RedirectStandardOutput $LogPath `
            -RedirectStandardError ("$LogPath.err") `
            -PassThru -NoNewWindow
        Note ("Restarted worker on {0}: new PID {1}" -f $laneName, $proc.Id)
    } catch {
        Err2 ("Failed to restart worker for {0}: {1}" -f $laneName, $_.Exception.Message)
        return $false
    }
    return $true
}

function Get-LaneLogTail {
    # Return the last N non-empty lines of a lane log file
    param([string]$LogPath, [int]$N = 3)
    if (-not (Test-Path $LogPath)) { return @() }
    try {
        return @(Get-Content $LogPath -Tail $N -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
    } catch {
        return @()
    }
}

function Save-ParametersInUse {
    # Copy active parameters_for_batch.csv into per-run audit dir
    $activeCSV = "C:\AQuA2\cfg\parameters_for_batch.csv"
    $dest = Join-Path $runAuditDir "parameters_for_batch_USED.csv"
    if (Test-Path $activeCSV) {
        Copy-Item $activeCSV $dest -Force
        OK2 ("audit: archived active parameters_for_batch.csv -> {0}" -f $dest)
    } else {
        Warn2 "audit: no parameters_for_batch.csv found at C:\AQuA2\cfg\ to archive"
    }
}

function Save-CFUBakedParameters {
    $bakedSrc = "C:\AQuA2\cfg\cfu_parameters_BAKED.txt"
    $dest = Join-Path $runAuditDir "cfu_parameters_BAKED.txt"
    if (Test-Path $bakedSrc) {
        Copy-Item $bakedSrc $dest -Force
        OK2 ("audit: archived CFU baked-parameters reference -> {0}" -f $dest)
    } else {
        Warn2 "audit: cfu_parameters_BAKED.txt not found at C:\AQuA2\cfg\."
        Warn2 "       CFU thresholds in use will NOT be captured in the audit trail."
        Warn2 "       Install it on the AMI from the repo (config/cfu_parameters_BAKED.txt)."
    }
}

function Write-PerFileStatus {
    param(
        [string]$Phase,
        [string]$ResultsDir,
        [string]$OkPattern,
        [string]$FailDir
    )
    $rows = New-Object System.Collections.ArrayList
    $okFiles = Get-ChildItem $ResultsDir -Recurse -Filter $OkPattern -File -ErrorAction SilentlyContinue
    foreach ($f in $okFiles) {
        [void]$rows.Add([pscustomobject]@{
            file         = $f.Name
            phase        = $Phase
            status       = 'OK'
            completed    = $f.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            size_bytes   = $f.Length
            location     = $f.DirectoryName
        })
    }
    $failFiles = Get-ChildItem $ResultsDir -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue
    foreach ($f in $failFiles) {
        [void]$rows.Add([pscustomobject]@{
            file         = ($f.Name -replace '_ERROR\.txt$','')
            phase        = $Phase
            status       = 'FAIL'
            completed    = $f.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            size_bytes   = $f.Length
            location     = $f.DirectoryName
        })
    }
    $dest = Join-Path $runAuditDir ("per_file_status_{0}.csv" -f $Phase)
    if ($rows.Count -gt 0) {
        $rows | Export-Csv -Path $dest -NoTypeInformation
        OK2 ("audit: per-file status CSV -> {0} ({1} files)" -f $dest, $rows.Count)
    } else {
        Warn2 ("audit: no result files found for $Phase phase")
    }
}

function Get-ErrorSignature {
    # v0.8.3: reduce an _ERROR.txt to a normalized one-line signature so similar
    # failures bucket together (systemic vs one-off). Handles both worker formats:
    # cfu_lane writes an "Error: <msg>" line; aqua_lane writes getReport() output.
    param([string]$ErrorFilePath)
    try { $lines = Get-Content $ErrorFilePath -TotalCount 40 -ErrorAction Stop } catch { return 'unreadable error file' }
    $msg = $null
    foreach ($l in $lines) {
        if ($l -match '^\s*Error:\s*(.+)$') { $msg = $Matches[1]; break }   # cfu_lane format
    }
    if (-not $msg) {
        foreach ($l in $lines) {
            $t = $l.Trim()
            if ($t -and $t -notmatch '^(FILE|File):' -and $t -notmatch '^Time:' -and $t -notmatch '^Error using' -and $t -notmatch '^at ') { $msg = $t; break }
        }
    }
    if (-not $msg) { $msg = 'unknown error' }
    # Normalize: quoted names -> X, drive paths -> PATH, digits -> #, collapse ws, cap length.
    $sig = $msg -replace "'[^']*'", 'X' -replace '"[^"]*"', 'X'
    $sig = $sig -replace '[A-Za-z]:\\[^\s]*', 'PATH' -replace '\d+', '#'
    $sig = ($sig -replace '\s+', ' ').Trim()
    if ($sig.Length -gt 100) { $sig = $sig.Substring(0, 100) }
    return $sig
}

function Save-FailuresSummary {
    param([string]$Phase, [string]$ResultsDir)

    $errFiles = @(Get-ChildItem $ResultsDir -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue)
    if ($errFiles.Count -eq 0) { return }

    $failDir = Join-Path $runAuditDir "failures"
    if (-not (Test-Path $failDir)) { New-Item -ItemType Directory -Path $failDir -Force | Out-Null }
    $phaseFailDir = Join-Path $failDir $Phase
    if (-not (Test-Path $phaseFailDir)) { New-Item -ItemType Directory -Path $phaseFailDir -Force | Out-Null }

    $summary = New-Object System.Collections.ArrayList
    [void]$summary.Add("# Failures during $Phase phase")
    [void]$summary.Add("")
    [void]$summary.Add("Total failed files: $($errFiles.Count)")
    [void]$summary.Add("")
    # v0.8.3: group by normalized error signature (systemic vs one-off at a glance)
    $groups = $errFiles | Group-Object { Get-ErrorSignature $_.FullName } | Sort-Object Count -Descending
    [void]$summary.Add("## Error signatures (grouped)")
    [void]$summary.Add("")
    foreach ($g in $groups) { [void]$summary.Add(("- **{0}x** -- {1}" -f $g.Count, $g.Name)) }
    [void]$summary.Add("")
    [void]$summary.Add("## Per-file detail")
    [void]$summary.Add("")
    foreach ($e in $errFiles) {
        $stem = ($e.Name -replace '_ERROR\.txt$','')
        # Copy the error file into per-run audit dir for easy access
        Copy-Item $e.FullName (Join-Path $phaseFailDir $e.Name) -Force
        # Add summary entry with first few lines of error
        [void]$summary.Add("## $stem")
        [void]$summary.Add("- Original: ``$($e.FullName)``")
        [void]$summary.Add("- Modified: $($e.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))")
        [void]$summary.Add("")
        [void]$summary.Add("Error excerpt:")
        [void]$summary.Add('```')
        $errLines = Get-Content $e.FullName -TotalCount 10 -ErrorAction SilentlyContinue
        foreach ($l in $errLines) { [void]$summary.Add($l) }
        [void]$summary.Add('```')
        [void]$summary.Add("")
    }
    $summaryPath = Join-Path $runAuditDir ("failures_summary_${Phase}.md")
    $summary -join "`n" | Out-File $summaryPath -Encoding UTF8
    OK2 ("audit: failures summary -> {0} ({1} files)" -f $summaryPath, $errFiles.Count)
}

function Write-RunManifest {
    param(
        [datetime]$Started,
        [datetime]$Completed,
        [hashtable]$Counts
    )
    $exeAqua = "C:\AQuA2\compiled\aqua_lane.exe"
    $exeCfu  = "C:\AQuA2\compiled\cfu_lane.exe"

    $phasesRun = @()
    if ($Split)  { $phasesRun += 'split' }
    if ($Detect) { $phasesRun += 'detect' }
    if ($CFU)         { $phasesRun += 'cfu' }
    if ($Consolidate) { $phasesRun += 'consolidate' }
    if ($Upload)      { $phasesRun += 'upload' }

    $manifest = [ordered]@{
        run_id           = $Started.ToString('yyyyMMdd_HHmmss')
        started          = $Started.ToString('yyyy-MM-ddTHH:mm:ss')
        completed        = $Completed.ToString('yyyy-MM-ddTHH:mm:ss')
        wall_clock       = ('{0:hh\:mm\:ss}' -f ($Completed - $Started))
        project_name     = $ProjectName
        output_base      = $OutputRoot
        project_root     = $projectRoot
        run_label        = $RunName
        input_tiffs      = $InputTIFFs
        phases_run       = $phasesRun
        detection_lanes  = $Lanes
        cfu_lanes        = $CFULanes
        config_csv       = if ($ConfigCSV) { $ConfigCSV } else { '(default at C:\AQuA2\cfg\parameters_for_batch.csv)' }
        s3_prefix        = $S3Prefix
        workers          = [ordered]@{
            aqua_lane = if (Test-Path $exeAqua) { [ordered]@{
                path = $exeAqua
                size_bytes = (Get-Item $exeAqua).Length
                modified = (Get-Item $exeAqua).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            } } else { '(not found)' }
            cfu_lane = if (Test-Path $exeCfu) { [ordered]@{
                path = $exeCfu
                size_bytes = (Get-Item $exeCfu).Length
                modified = (Get-Item $exeCfu).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            } } else { '(not found)' }
        }
        instance         = [ordered]@{
            instance_type = $script:instanceType
            vCPUs         = $cpu
            ram_GB        = $ramGB
        }
        counts           = $Counts
    }

    $dest = Join-Path $runAuditDir "run_manifest.json"
    $manifest | ConvertTo-Json -Depth 6 | Out-File $dest -Encoding UTF8
    OK2 ("audit: machine-readable manifest -> {0}" -f $dest)
}

function Write-RunSummary {
    param(
        [datetime]$Started,
        [datetime]$Completed,
        [hashtable]$Counts,
        [string[]]$Issues = @()
    )
    $wall = '{0:hh\:mm\:ss}' -f ($Completed - $Started)
    $boxX = '[X]'
    $boxE = '[ ]'
    $rows = @(
        ('{0} Split TIFFs into lanes'      -f ($(if ($Split)       { $boxX } else { $boxE })))
        ('{0} Detection (aqua_lane.exe)'   -f ($(if ($Detect)      { $boxX } else { $boxE })))
        ('{0} CFU (build + run)'           -f ($(if ($CFU)         { $boxX } else { $boxE })))
        ('{0} Consolidate (for_upload/)'   -f ($(if ($Consolidate) { $boxX } else { $boxE })))
        ('{0} S3 upload'                   -f ($(if ($Upload)      { $boxX } else { $boxE })))
    )

    $md = @"
# Pipeline Run Summary

**Run ID:** $($Started.ToString('yyyyMMdd_HHmmss'))
**Started:** $($Started.ToString('yyyy-MM-dd HH:mm:ss'))
**Completed:** $($Completed.ToString('yyyy-MM-dd HH:mm:ss'))
**Wall-clock:** $wall

## Phases run

$($rows -join "`n")

## Configuration

**Detection parameters CSV:** see ``parameters_for_batch_USED.csv`` in this folder.
$(if ($ConfigCSV) { "Source: ``$ConfigCSV``" } else { "Source: default at ``C:\AQuA2\cfg\parameters_for_batch.csv`` (no override)" })

**CFU clustering parameters:** see ``cfu_parameters_BAKED.txt`` in this folder.
These are compiled into ``cfu_lane.exe``. To change, edit ``C:\AQuA2\cfu_lane.m``, recompile, and update the BAKED file.

## Compute

- Instance type:      $script:instanceType
- Logical CPUs:       $cpu
- Total RAM:          $ramGB GB
- Detection lanes:    $Lanes
- CFU lanes:          $CFULanes

## Workers

| Worker | Path | Size | Compiled |
|---|---|---|---|
| ``aqua_lane.exe`` | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { 'C:\AQuA2\compiled\aqua_lane.exe' } else { '(not present)' }) | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { '{0:N0} bytes' -f (Get-Item 'C:\AQuA2\compiled\aqua_lane.exe').Length } else { '-' }) | $(if (Test-Path 'C:\AQuA2\compiled\aqua_lane.exe') { (Get-Item 'C:\AQuA2\compiled\aqua_lane.exe').LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }) |
| ``cfu_lane.exe`` | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { 'C:\AQuA2\compiled\cfu_lane.exe' } else { '(not present)' }) | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { '{0:N0} bytes' -f (Get-Item 'C:\AQuA2\compiled\cfu_lane.exe').Length } else { '-' }) | $(if (Test-Path 'C:\AQuA2\compiled\cfu_lane.exe') { (Get-Item 'C:\AQuA2\compiled\cfu_lane.exe').LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }) |

## Results

| Metric | Value |
|---|---|
| Input TIFFs | $($Counts['input_count']) |
| Detection succeeded | $($Counts['detection_ok']) |
| Detection failed | $($Counts['detection_fail']) |
| CFU succeeded | $($Counts['cfu_ok']) |
| CFU failed | $($Counts['cfu_fail']) |

## Issues detected

$(if ($Issues -and $Issues.Count -gt 0) { ($Issues | ForEach-Object { "- $_" }) -join "`n" } else { "None. Every phase that ran produced the expected outputs." })

## Files in this folder

- ``pipeline_<timestamp>.log`` -- full orchestrator transcript (verbose)
- ``parameters_for_batch_USED.csv`` -- the parameter CSV in effect for THIS run's detection
- ``cfu_parameters_BAKED.txt`` -- what's compiled into the cfu_lane.exe used
- ``per_file_status_detection.csv`` -- file-by-file detection results
- ``per_file_status_cfu.csv`` -- file-by-file CFU results
- ``run_manifest.json`` -- machine-readable summary (for programmatic comparison across runs)
- ``RUN_SUMMARY.md`` -- this file

## To go deeper

- Per-lane detection logs: ``$($paths['lanes'])\_logs\lane<N>.log``
- Per-lane CFU logs: ``$($paths['CFU_lanes'])\_logs\cfu_lane<N>.log``
- Per-file failure details: ``$($paths['PreCFU'])\<stem>\_failures\<name>_ERROR.txt`` (detection) and ``$($paths['POST'])\_failures\<name>_ERROR.txt`` (CFU)
- Authoritative per-file parameters: ``opts`` struct inside each ``_AQuA2.mat`` file
"@

    $dest = Join-Path $runAuditDir "RUN_SUMMARY.md"
    $md | Out-File $dest -Encoding UTF8
    OK2 ("audit: human-readable summary -> {0}" -f $dest)
}

# ==========================================================
# ConfigCSV resolution + parsing helpers
# ==========================================================
function Show-CSVValues {
    # Print key parameter values from parameters_for_batch.csv for user sanity-check
    # before pressing Y.
    #
    # The CSV format is:
    #   Name,Variable,Type,File1,File2,File3,...,File12
    #   Spatial smoothing level,smoXY,preprocessing,0.5,0.5,0.5,...
    #   Whether detect global signals,detectGlo,glo,0,0,0,...
    #
    # We display the Variable name and the File1 (first preset) value, with
    # prominent ON/OFF markers for critical flags (especially detectGlo
    # because it controls whether _Glo_*.xlsx output files are produced).
    param([string]$CSVPath, [string]$Label = 'Parameters in effect')

    if (-not (Test-Path $CSVPath)) {
        Note ("  (could not find {0})" -f $CSVPath)
        return
    }

    try {
        $rows = @(Import-Csv $CSVPath -ErrorAction Stop)
    } catch {
        Note ("  (could not parse {0} as CSV: {1})" -f $CSVPath, $_.Exception.Message)
        return
    }
    if ($rows.Count -eq 0) {
        Note "  (CSV is empty or has no data rows)"
        return
    }

    Write-Host "  ==== $Label ===="
    Write-Host ("  Source:   {0}" -f $CSVPath)
    Write-Host ("  Modified: {0}" -f (Get-Item $CSVPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Host "  Key parameters (showing File1 / first preset column):"

    # Critical parameters to surface in the display.
    # detectGlo gets a prominent marker because it controls whether
    # _Glo_Ch1.xlsx and _Glo_Ch1_curves.xlsx output files are produced.
    $interesting = @(
        'frameRate', 'spatialRes',
        'thrARScl', 'minDur', 'minSize', 'maxSize', 'circularityThr',
        'smoXY', 'sourceSensitivity', 'whetherExtend',
        'detectGlo', 'gloDur',
        'ignoreTau', 'propMetric', 'networkFeatures'
    )

    $shown = 0
    foreach ($row in $rows) {
        if (-not $row.Variable) { continue }
        $varName = $row.Variable.Trim()
        if (-not $varName) { continue }
        if ($interesting -notcontains $varName) { continue }

        $value = if ($row.File1) { $row.File1.Trim() } else { '(empty)' }

        $marker = ''
        $color = 'White'
        if ($varName -eq 'detectGlo') {
            if ($value -eq '1') {
                $marker = '   <-- GLOBAL SIGNAL DETECTION: ON  (will produce _Glo_*.xlsx files)'
                $color = 'Green'
            } else {
                $marker = '   <-- GLOBAL SIGNAL DETECTION: OFF (no _Glo_*.xlsx files)'
                $color = 'Yellow'
            }
        }
        $line = "    {0,-22} = {1}{2}" -f $varName, $value, $marker
        Write-Host $line -ForegroundColor $color
        $shown++
    }
    Write-Host ("  ({0} of {1} total rows shown; full CSV archived to per-run audit dir)" -f $shown, $rows.Count)
}

function Test-ConfigSanity {
    # v0.8.3: cheap pre-flight sanity check on the detection CSV so a misconfigured
    # run (stale frameRate, missing maxSize) is caught before hours of compute.
    # Warnings only -- never blocks; the operator decides.
    param([string]$CSVPath)
    if (-not (Test-Path $CSVPath)) { return }
    try { $rows = @(Import-Csv $CSVPath -ErrorAction Stop) } catch { Warn2 "config sanity: could not parse CSV."; return }

    function _cv($name) {
        $r = $rows | Where-Object { $_.Variable -and $_.Variable.Trim() -eq $name } | Select-Object -First 1
        if ($r -and $r.File1) { return $r.File1.Trim() } else { return $null }
    }

    $warns = 0
    $fr = _cv 'frameRate'
    if (-not $fr) {
        Warn2 "config sanity: no 'frameRate' row found -- detection timing may be wrong."; $warns++
    } else {
        $frNum = 0.0
        if ([double]::TryParse($fr, [ref]$frNum)) {
            if ($frNum -le 0 -or $frNum -gt 1.0) {
                $hz = if ($frNum -gt 0) { [math]::Round(1.0 / $frNum, 2) } else { '?' }
                Warn2 ("config sanity: frameRate={0} s/frame is outside the usual 0.001-1.0 range (~{1} Hz). Confirm it matches acquisition." -f $fr, $hz); $warns++
            }
        } else {
            Warn2 ("config sanity: frameRate='{0}' is not numeric." -f $fr); $warns++
        }
    }
    if (-not (_cv 'maxSize'))    { Warn2 "config sanity: no 'maxSize' row found (hyperactive files can hang at maxSize=inf)."; $warns++ }
    if (-not (_cv 'spatialRes')) { Warn2 "config sanity: no 'spatialRes' row found -- event areas will be wrong."; $warns++ }

    if ($warns -eq 0) { OK2 "config sanity: frameRate / maxSize / spatialRes present and plausible." }
    else { Warn2 ("config sanity: {0} warning(s) above -- review the CSV before proceeding." -f $warns) }
}

function Get-CSVKeyValues {
    # Kept for backward compat; returns ordered dict of Variable=>File1 value
    param([string]$CSVPath)
    $values = [ordered]@{}
    if (-not (Test-Path $CSVPath)) { return $values }
    try {
        $rows = @(Import-Csv $CSVPath -ErrorAction Stop)
        foreach ($r in $rows) {
            if ($r.Variable) {
                $values[$r.Variable.Trim()] = if ($r.File1) { $r.File1.Trim() } else { '' }
            }
        }
    } catch { }
    return $values
}

function Resolve-ConfigCSV {
    # Simple resolution: use explicit -ConfigCSV if given, else the default at
    # C:\AQuA2\cfg\parameters_for_batch.csv. NO auto-detect from InputTIFFs or
    # OutputRoot. NO multi-candidate prompts. The user must opt in to a
    # non-default CSV by passing -ConfigCSV explicitly.
    param([string]$ExplicitCSV)
    $defaultCSV = "C:\AQuA2\cfg\parameters_for_batch.csv"

    if ($ExplicitCSV) {
        if (-not (Test-Path $ExplicitCSV)) {
            Write-Error "ConfigCSV not found: $ExplicitCSV"
        }
        return $ExplicitCSV
    }
    if (-not (Test-Path $defaultCSV)) {
        Write-Error "Default ConfigCSV not found at $defaultCSV. Either install it on the AMI or pass -ConfigCSV explicitly."
    }
    return $defaultCSV
}

$pipelineStart = Get-Date

# ==========================================================
# Resolve / create paths
# ==========================================================
# Named parameter preset -> cfg/presets/<name>.csv (versioned in the repo). Sugar
# for -ConfigCSV; the rest of the CSV plumbing then treats it as the config source.
if ($ParamPreset) {
    if ($ConfigCSV) { Write-Error "Pass either -ParamPreset or -ConfigCSV, not both." }
    $presetDir = Join-Path (Split-Path $ScriptsDir -Parent) 'cfg\presets'
    $presetCsv = Join-Path $presetDir ("{0}.csv" -f $ParamPreset)
    if (-not (Test-Path $presetCsv)) {
        $avail = @(Get-ChildItem $presetDir -Filter *.csv -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
        $availStr = if ($avail.Count) { $avail -join ', ' } else { '(none saved yet -- use Save-Preset.ps1)' }
        Write-Error ("Parameter preset '{0}' not found ({1}). Available presets: {2}" -f $ParamPreset, $presetCsv, $availStr)
    }
    $ConfigCSV = $presetCsv
    Write-Host ("  Using parameter preset '{0}' -> {1}" -f $ParamPreset, $presetCsv) -ForegroundColor Cyan
}

if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

# Project root = <OutputRoot>/<ProjectName>/ -- all data + audit lives here
$projectRoot = Join-Path $OutputRoot $ProjectName
if (-not (Test-Path $projectRoot)) {
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
}

$paths = @{
    'lanes'      = Join-Path $projectRoot 'lanes'
    'PreCFU'     = Join-Path $projectRoot 'PreCFU'
    'CFU_lanes'  = Join-Path $projectRoot 'CFU_lanes'
    'POST'       = Join-Path $projectRoot 'POST'
    'logs'       = Join-Path $projectRoot '_logs'
    'for_upload' = Join-Path $projectRoot 'for_upload'
}
foreach ($p in $paths.Values) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# Phase 0 runs when there's prep work: extracting LIFs (-LIFSource), OR trimming a
# folder of existing TIFFs (-InputTIFFs with a -TrimMode). Its folders are created
# only then, so plain TIFF-start-no-trim projects stay clean.
$doTrim = ($TrimMode -ne 'none')
$extractMode = if (-not [string]::IsNullOrWhiteSpace($LIFSource)) { 'lif' }
               elseif ((-not [string]::IsNullOrWhiteSpace($InputTIFFs)) -and $doTrim) { 'tiff' }
               else { '' }
$doExtract = [bool]$extractMode
$extractSource = if ($extractMode -eq 'lif') { $LIFSource } elseif ($extractMode -eq 'tiff') { $InputTIFFs } else { '' }
$resolvedDetectOn = ''          # set in pre-flight when extracting
$engineScript = ''              # set in pre-flight when extracting
if ($doExtract) {
    $paths['extracted']     = Join-Path $projectRoot 'extracted'      # mirror of engine output: <lifbase>\{UNTRIMMED,TRIMMED}\
    $paths['extract_input'] = Join-Path $projectRoot 'extract_input'  # flat staged detection set -> becomes InputTIFFs
    foreach ($k in 'extracted','extract_input') {
        if (-not (Test-Path $paths[$k])) { New-Item -ItemType Directory -Path $paths[$k] -Force | Out-Null }
    }
}

# Per-run audit subfolder: _logs/run_<timestamp>[_<RunName>]/
$runTimestamp = $pipelineStart.ToString('yyyyMMdd_HHmmss')
$runFolderName = if ($RunName) { "run_${runTimestamp}_${RunName}" } else { "run_${runTimestamp}" }
$runFolderName = $runFolderName -replace '[^A-Za-z0-9_\-]', '_'
$runAuditDir = Join-Path $paths['logs'] $runFolderName
New-Item -ItemType Directory -Path $runAuditDir -Force | Out-Null

$masterLog = Join-Path $runAuditDir "pipeline.log"
Start-Transcript -Path $masterLog -Append | Out-Null

# ==========================================================
# Header
# ==========================================================
Hdr "AQuA2 Pipeline Orchestrator"
Note ("Started:           {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Project name:      {0}" -f $ProjectName)
Note ("Output base:       {0}" -f $OutputRoot)
Note ("Project root:      {0}" -f $projectRoot)
if ($doExtract) {
    $srcLabel = if ($extractMode -eq 'lif') { 'LIF source' } else { 'TIFF prep src' }
    Note ("{0}:      {1}  (Phase 0 {2} -> TIFFs -> Split)" -f $srcLabel, $extractSource, $(if ($extractMode -eq 'lif') { 'extract' } else { 'trim' }))
} else {
    Note ("Input TIFFs:       {0}" -f $InputTIFFs)
}
Note ("Run audit dir:     {0}" -f $runAuditDir)
Note ("Master log:        {0}" -f $masterLog)
if ($RunName) {
    Note ("Run label:         {0}" -f $RunName)
}

# ==========================================================
# Pre-flight checks
# ==========================================================
Hdr "Pre-flight checks"
$checksFailed = 0

# --- 1. Companion scripts exist ---
$companionScripts = @{
    'Auto-Size-Lanes.ps1'    = ($Lanes -le 0)
    'Split-IntoLanes.ps1'    = $Split
    'Launch-Lanes-Exe.ps1'   = $Detect
    'Build-CFU-Lanes.ps1'    = $CFU
    'Launch-CFU-Lanes.ps1'   = $CFU
}
foreach ($s in $companionScripts.GetEnumerator()) {
    if (-not $s.Value) { continue }
    $p = Join-Path $ScriptsDir $s.Key
    if (Test-Path $p) {
        OK2 ("script found: {0}" -f $s.Key)
    } else {
        Err2 ("script MISSING: {0} (expected at {1})" -f $s.Key, $p)
        $checksFailed++
    }
}

# --- 2. Worker exes ---
$workerExes = @{
    'aqua_lane.exe' = $Detect
    'cfu_lane.exe'  = $CFU
}
foreach ($e in $workerExes.GetEnumerator()) {
    if (-not $e.Value) { continue }
    $p = "C:\AQuA2\compiled\$($e.Key)"
    if (Test-Path $p) {
        OK2 ("worker exe found: {0}" -f $e.Key)
    } else {
        Err2 ("worker exe MISSING: {0} (expected at {1})" -f $e.Key, $p)
        $checksFailed++
    }
}

# --- 2.5. No leftover live workers from a previous crashed run ---
$liveWorkers = Get-Process aqua_lane, cfu_lane -ErrorAction SilentlyContinue
if ($liveWorkers) {
    Err2 "Existing pipeline workers are already running on this instance:"
    foreach ($w in $liveWorkers) {
        Err2 ("  PID {0,6}  {1}  (started: {2})" -f $w.Id, $w.Name, $w.StartTime.ToString('HH:mm:ss'))
    }
    Err2 "These may be orphans from a previous crashed orchestrator run."
    Err2 "Options:"
    Err2 "  (a) Wait for them to finish (they continue writing to their existing output paths),"
    Err2 "      then re-run; the orchestrator's per-file resume guard will skip what they did."
    Err2 "  (b) Kill them and start fresh:"
    Err2 "      Get-Process aqua_lane,cfu_lane | Stop-Process -Force"
    Err2 "Refusing to launch new workers on top of existing ones."
    $checksFailed++
} else {
    OK2 "no leftover workers running (clean slate)"
}

# --- 2.9. Phase 0 prerequisites (LIF extraction, or trimming a TIFF folder) ---
if ($doExtract) {
    if (-not (Test-Path -LiteralPath $extractSource)) {
        Err2 ("{0} source folder not found: {1}" -f $extractMode.ToUpper(), $extractSource); $checksFailed++
    } elseif ($extractMode -eq 'lif') {
        $lifCount = @(Get-ChildItem -LiteralPath $extractSource -Recurse -File -Filter *.lif -ErrorAction SilentlyContinue).Count
        if ($lifCount -eq 0) { Err2 ("No .lif files under {0}" -f $extractSource); $checksFailed++ }
        else { OK2 ("LIF source: {0} .lif file(s) under {1}" -f $lifCount, $extractSource) }
    } else {
        $tifCount = @(Get-ChildItem -LiteralPath $extractSource -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ieq '.tif' -or $_.Extension -ieq '.tiff' }).Count
        if ($tifCount -eq 0) { Err2 ("No .tif/.tiff files at the top level of {0}" -f $extractSource); $checksFailed++ }
        else { OK2 ("TIFF prep source: {0} .tif file(s) in {1}  (will trim: {2})" -f $tifCount, $extractSource, $TrimMode) }
    }
    # Resolve Fiji: if -FijiExe (default C:\Fiji.app\ImageJ-win64.exe) isn't there,
    # auto-discover an install in a non-default spot before giving up, so a Fiji
    # installed elsewhere still works without the caller knowing the exact path.
    if (-not (Test-Path -LiteralPath $FijiExe)) {
        # Search common install roots for either the current (fiji-windows-x64.exe,
        # under Fiji\) or legacy (ImageJ-win64.exe, under Fiji.app\) launcher.
        $fijiRoots = @(
            'C:\Fiji', 'C:\Fiji.app',
            'C:\Program Files\Fiji', 'C:\Program Files\Fiji.app',
            (Join-Path $env:USERPROFILE 'Fiji'),      (Join-Path $env:USERPROFILE 'Fiji.app'),
            (Join-Path $env:USERPROFILE 'Desktop\Fiji'),   (Join-Path $env:USERPROFILE 'Desktop\Fiji.app'),
            (Join-Path $env:USERPROFILE 'Downloads\Fiji'), (Join-Path $env:USERPROFILE 'Downloads\Fiji.app'),
            'D:\Fiji', 'D:\Fiji.app'
        )
        $fijiCandidates = foreach ($r in $fijiRoots) {
            (Join-Path $r 'fiji-windows-x64.exe'); (Join-Path $r 'ImageJ-win64.exe')
        }
        $found = $fijiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $found) {
            foreach ($exe in 'fiji-windows-x64.exe','ImageJ-win64.exe') {
                $cmd = Get-Command $exe -ErrorAction SilentlyContinue
                if ($cmd) { $found = $cmd.Source; break }
            }
        }
        if ($found) {
            $FijiExe = $found
            OK2 ("Fiji (auto-discovered): {0}" -f $FijiExe)
        } else {
            Err2 ("Fiji executable not found at {0} or common locations." -f $FijiExe)
            Err2 "  Pass -FijiExe <path to ImageJ-win64.exe>, or install Fiji + R via setup\Install-Dependencies.ps1."
            $checksFailed++
        }
    } else { OK2 ("Fiji: {0}" -f $FijiExe) }
    $engineScript = Join-Path (Split-Path $ScriptsDir -Parent) 'fiji-macros\lif_extract_headless.py'
    if (-not (Test-Path $engineScript)) {
        Err2 ("Extraction engine not found: {0}" -f $engineScript); $checksFailed++
    } else { OK2 ("Extract engine: {0}" -f $engineScript) }
    if (-not $SaveUntrimmed -and -not $doTrim) {
        Err2 "Extract: nothing to do (-SaveUntrimmed `$false AND -TrimMode none). Enable at least one output."; $checksFailed++
    }
    $resolvedDetectOn = if ($DetectOn -eq 'auto') { if ($doTrim) { 'trimmed' } else { 'untrimmed' } } else { $DetectOn }
    if ($resolvedDetectOn -eq 'trimmed'  -and -not $doTrim)        { Err2 "-DetectOn trimmed but -TrimMode is none (no trimmed set would exist)."; $checksFailed++ }
    if ($resolvedDetectOn -eq 'untrimmed' -and -not $SaveUntrimmed) { Err2 "-DetectOn untrimmed but -SaveUntrimmed is `$false (no untrimmed set would exist)."; $checksFailed++ }
    if ($checksFailed -eq 0) { OK2 ("extract plan: save_untrimmed={0}, trim={1}, detect-on={2}" -f $SaveUntrimmed, $TrimMode, $resolvedDetectOn) }
    if ($ExtractMaxSeries -gt 0) { Warn2 ("extract SMOKE-TEST cap: first {0} series per LIF only (-ExtractMaxSeries). Re-run with 0 for all." -f $ExtractMaxSeries) }
}

# --- 3. Input TIFFs ---
$inputCount = 0
$inputSizeGB = 0
# When extracting, the input TIFFs don't exist yet (Phase 0 produces them and
# reassigns $InputTIFFs), so skip the input-required check here.
if ($Split -and -not $doExtract) {
    if (-not $InputTIFFs -or -not (Test-Path $InputTIFFs)) {
        Err2 "InputTIFFs folder missing or not specified (required for -Split)"
        $checksFailed++
    } else {
        # v0.9.1: count the SAME files the splitter will actually move. Split-IntoLanes reads
        # top-level only unless -Recurse is passed; gating both on -RecurseInput keeps this
        # pre-flight count honest (previously this always recursed while Split took top-level
        # only, so nested inputs showed N here but Split moved 0 and Detect then died).
        $tifFiles = if ($RecurseInput) {
                        Get-ChildItem -Path $InputTIFFs -Recurse -Include *.tif,*.tiff -File
                    } else {
                        Get-ChildItem -Path $InputTIFFs -File | Where-Object { $_.Extension -ieq '.tif' -or $_.Extension -ieq '.tiff' }
                    }
        $tifFiles = @($tifFiles | Where-Object { $_.Name -notlike '._*' })
        $inputCount = $tifFiles.Count
        $inputSizeGB = [math]::Round(($tifFiles | Measure-Object Length -Sum).Sum / 1GB, 2)
        if ($inputCount -eq 0) {
            Err2 "InputTIFFs contains no .tif/.tiff files"
            $checksFailed++
        } else {
            OK2 ("input TIFFs: {0} files, {1} GB total" -f $inputCount, $inputSizeGB)
        }
    }
}

# --- 4. Detection prerequisites ---
if ($Detect -and -not $Split) {
    $laneDirs = Get-ChildItem $paths['lanes'] -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^lane' }
    if (-not $laneDirs -or $laneDirs.Count -eq 0) {
        Err2 ("Detect enabled but no lane folders found under {0}" -f $paths['lanes'])
        Err2 "Either set -Split `$true, or populate lanes manually first."
        $checksFailed++
    } else {
        OK2 ("existing lane folders found: {0}" -f $laneDirs.Count)
    }
}

# --- 5. CFU prerequisites ---
if ($CFU -and -not $Detect) {
    $matCount = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
    if ($matCount -eq 0) {
        Err2 ("CFU enabled but no _AQuA2.mat files under {0}" -f $paths['PreCFU'])
        Err2 "Either set -Detect `$true, or populate PreCFU manually first."
        $checksFailed++
    } else {
        OK2 ("existing detection results: {0} _AQuA2.mat files" -f $matCount)
    }
}

# --- 6. Upload prerequisites ---
if ($Upload) {
    if (-not $S3Prefix) {
        Err2 "-Upload requested but -S3Prefix not provided"
        $checksFailed++
    } elseif ($S3Prefix -notmatch '^s3://') {
        Err2 "-S3Prefix must start with s3:// (got: $S3Prefix)"
        $checksFailed++
    } else {
        try {
            $null = & aws sts get-caller-identity 2>&1
            if ($LASTEXITCODE -eq 0) {
                OK2 "AWS credentials work (sts get-caller-identity succeeded)"
            } else {
                Err2 "AWS CLI failed sts get-caller-identity. Check IAM role / credentials."
                $checksFailed++
            }
        } catch {
            Err2 "AWS CLI not available on PATH"
            $checksFailed++
        }
    }
}

# --- 7. Custom ConfigCSV ---
if ($ConfigCSV) {
    if (-not (Test-Path $ConfigCSV)) {
        Err2 ("Custom -ConfigCSV not found: {0}" -f $ConfigCSV)
        $checksFailed++
    } else {
        $csvLines = (Get-Content $ConfigCSV | Measure-Object -Line).Lines
        OK2 ("custom config CSV: {0} ({1} lines)" -f $ConfigCSV, $csvLines)
    }
}

# --- 8. Disk space ---
$freeNow = Get-FreeGB
$estNeed = if ($inputSizeGB -gt 0) { [math]::Round($inputSizeGB * 5, 0) } else { -1 }
if ($freeNow -lt $MinFreeDiskGB) {
    Err2 ("disk free ({0} GB) below abort threshold ({1} GB)" -f $freeNow, $MinFreeDiskGB)
    $checksFailed++
} elseif ($estNeed -gt 0 -and $freeNow -lt $estNeed) {
    Warn2 ("disk free ({0} GB) below estimated need ({1} GB). May fill mid-run." -f $freeNow, $estNeed)
} else {
    if ($estNeed -gt 0) {
        OK2 ("disk: {0} GB free, ~{1} GB estimated need" -f $freeNow, $estNeed)
    } else {
        OK2 ("disk: {0} GB free" -f $freeNow)
    }
}

# --- 9. Instance capacity (informational) ---
$cpu = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$script:instanceType = "(unknown)"
try {
    $token = Invoke-WebRequest -UseBasicParsing -Method PUT `
        -Uri "http://169.254.169.254/latest/api/token" `
        -Headers @{'X-aws-ec2-metadata-token-ttl-seconds'='60'} `
        -TimeoutSec 3 -ErrorAction Stop | Select-Object -ExpandProperty Content
    $script:instanceType = (Invoke-WebRequest -UseBasicParsing -Headers @{'X-aws-ec2-metadata-token'=$token} `
        -Uri "http://169.254.169.254/latest/meta-data/instance-type" -TimeoutSec 3).Content
} catch { }
OK2 ("instance: {0} ({1} vCPU, {2} GB RAM)" -f $script:instanceType, $cpu, $ramGB)

# --- Abort if any failed ---
if ($checksFailed -gt 0) {
    Write-Host ""
    Stop-Transcript | Out-Null
    Write-Error "$checksFailed pre-flight check(s) failed. Fix and re-run."
}

# ==========================================================
# Plan summary
# ==========================================================
Hdr "Plan summary"

# Phase-complete markers (written at end of each successful phase)
$markerExtract     = Join-Path $paths['logs'] 'PHASE_extract_COMPLETE.txt'
$markerSplit       = Join-Path $paths['logs'] 'PHASE_split_COMPLETE.txt'
$markerDetect      = Join-Path $paths['logs'] 'PHASE_detect_COMPLETE.txt'
$markerCFU         = Join-Path $paths['logs'] 'PHASE_cfu_COMPLETE.txt'
$markerConsolidate = Join-Path $paths['logs'] 'PHASE_consolidate_COMPLETE.txt'
$markerUpload      = Join-Path $paths['logs'] 'PHASE_upload_COMPLETE.txt'

$extractLabel = if ($doExtract) { "LIF extract (Phase 0 -> detect on $resolvedDetectOn)" } else { 'LIF extract (Phase 0)' }
$phaseList = @(
    @{ name=$extractLabel;                       on=$doExtract;   marker=$markerExtract     },
    @{ name='Split TIFFs into lanes';            on=$Split;       marker=$markerSplit       },
    @{ name='Detection (aqua_lane.exe)';         on=$Detect;      marker=$markerDetect      },
    @{ name='CFU (build junctions + run)';       on=$CFU;         marker=$markerCFU         },
    @{ name='Consolidate (flat layout for S3)';  on=$Consolidate; marker=$markerConsolidate },
    @{ name='S3 upload';                         on=$Upload;      marker=$markerUpload      }
)
foreach ($p in $phaseList) {
    $sym = if ($p.on) { '[X]' } else { '[ ]' }
    $col = if ($p.on) { 'Green' } else { 'DarkGray' }
    $suffix = ''
    if ($p.on -and (Test-Path $p.marker)) {
        $when = (Get-Item $p.marker).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $suffix = "  (PREVIOUSLY COMPLETED $when -- will re-run; per-file resume guard skips done files)"
        $col = 'Yellow'
    }
    Write-Host ("  {0} {1}{2}" -f $sym, $p.name, $suffix) -ForegroundColor $col
}
Write-Host ""

# Resume counts: how many files are already done in each output dir?
$existingDetect = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
$existingCFU    = (Get-ChildItem $paths['POST']   -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue).Count
if ($existingDetect -gt 0 -or $existingCFU -gt 0) {
    Note "Resume context (files already in output folders from previous run):"
    if ($existingDetect -gt 0) {
        Note ("  Detection .mat files:  {0}  (these will be skipped by per-file resume guard)" -f $existingDetect)
    }
    if ($existingCFU -gt 0) {
        Note ("  CFU .mat files:        {0}  (these will be skipped by per-file resume guard)" -f $existingCFU)
    }
    Write-Host ""
}

if ($Lanes -le 0) {
    Note "Detection lanes:    will auto-size (probe largest input TIFF) -- if Split=true"
    Note "                    or will derive from existing lane folders -- if Split=false"
} else {
    Note ("Detection lanes:    {0}" -f $Lanes)
}
if ($CFULanes -le 0) {
    Note "CFU lanes:          auto-derive (~0.75x detection lanes)"
} else {
    Note ("CFU lanes:          {0}" -f $CFULanes)
}

# Resolve and display the parameters_for_batch.csv that will be used
if ($Detect) {
    $resolvedCSV = Resolve-ConfigCSV -ExplicitCSV $ConfigCSV
    Write-Host ""
    Show-CSVValues -CSVPath $resolvedCSV -Label 'Detection parameters in effect'
    Write-Host ""
    Test-ConfigSanity -CSVPath $resolvedCSV
    Write-Host ""
    if ($resolvedCSV -ne "C:\AQuA2\cfg\parameters_for_batch.csv") {
        Note "  (will be copied to C:\AQuA2\cfg\parameters_for_batch.csv at detection start; existing backed up)"
    } else {
        Note "  (already at the expected location; no copy needed)"
    }
    $script:resolvedConfigCSV = $resolvedCSV
}

if ($Upload -and $S3Prefix) {
    Note ("S3 destination:     {0}" -f $S3Prefix)
}
Write-Host ""
Note ("Free disk:          {0} GB" -f $freeNow)
if ($estNeed -gt 0) {
    Note ("Estimated need:     {0} GB (input x 5)" -f $estNeed)
}

# Stall detection info
if ($Detect -or $CFU) {
    Write-Host ""
    Note "Stall detection (three-stage):"
    Note ("  Stage 1 -- WARN          at {0} min: yellow warning + log tail" -f $StallWarnMin)
    Note ("  Stage 2 -- ESCALATE      at {0} min: red banner + longer log tail (no destructive action yet)" -f $StallEscalateMin)
    Note ("  Stage 3 -- AUTO-ACTION   at {0} min (policy: {1})" -f $StallAutoSkipMin, $StallPolicy)
    if ($StallPolicy -eq 'auto-skip') {
        Note "  When Stage 3 fires: move stuck file to <lane>\_stalled\, kill+restart worker, continue lane"
    } else {
        Note "  When Stage 3 fires: warn only; user must intervene manually"
    }
}

# Split move warning
if ($Split) {
    Write-Host ""
    if ($doExtract) {
        Warn2 ("Phase 1 (Split) MOVES the Phase-0 extracted {0} TIFFs into {1}\lane<N>\" -f $resolvedDetectOn, $paths['lanes'])
        Warn2 "Those are hardlinks into extracted\; the extracted\ archive (incl. UNTRIMMED) is preserved."
    } else {
        Warn2 ("Phase 1 (Split) MOVES TIFFs from {0} into {1}\lane<N>\" -f $InputTIFFs, $paths['lanes'])
        Warn2 "Originals are REMOVED from InputTIFFs. To keep originals, copy them elsewhere first."
    }
}

Write-Host ""
Note "To cancel mid-run:"
Note "  Get-Process aqua_lane,cfu_lane -ErrorAction SilentlyContinue | Stop-Process -Force"
Write-Host ""

if ($WhatIfMode) {
    Write-Host "DRY RUN MODE - nothing will execute. Exiting." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    return
}

if (-not $Force) {
    $resp = Read-Host "Proceed? [Y/n]"
    if ($resp -and $resp -notmatch '^[Yy]') {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        return
    }
}

# ==========================================================
# Phase 0: Extract/prep (optional) -- produces TIFFs, then sets $InputTIFFs
# Mode 'lif' extracts .lif series; mode 'tiff' trims/labels an existing TIFF folder.
# ==========================================================
if ($doExtract) {
    $phaseLabel = if ($extractMode -eq 'lif') { "LIF extraction (headless Fiji)" } else { "TIFF trim/prep (headless Fiji)" }
    Phase 'Extract' $phaseLabel
    $extractStart = Get-Date

    # Engine output goes under the project's extracted/ folder so the SOURCE (LIF
    # tree or your input TIFFs) is never modified. Config is a key=value file the
    # engine reads via the LIF_EXTRACT_CONFIG env var (no PowerShell->Fiji quoting).
    $extractLog = Join-Path $runAuditDir 'lif_extract.log'
    $cfgPath    = Join-Path $runAuditDir 'lif_extract.cfg'
    $cfgLines = @(
        "mode=$extractMode",
        "input=$extractSource",
        "output=$($paths['extracted'])",
        "output_mode=mirror",
        "save_untrimmed=$($SaveUntrimmed.ToString().ToLower())",
        "trim_mode=$TrimMode",
        "trim_start_sec=$TrimStartSec",
        "trim_amount=$TrimAmount",
        "trim_unit=$TrimUnit",
        "hz_label=$($HzLabel.ToString().ToLower())",
        "hz_decimals=$HzDecimals",
        "rate_policy=$RatePolicy",
        "skip_tilescans=$($SkipTileScans.ToString().ToLower())",
        "dry_run=$($ExtractDryRun.IsPresent.ToString().ToLower())",
        "max_series=$ExtractMaxSeries",
        "log=$extractLog"
    )
    Set-Content -Path $cfgPath -Value $cfgLines -Encoding ASCII
    Copy-Item $cfgPath (Join-Path $runAuditDir 'lif_extract_USED.cfg') -Force -ErrorAction SilentlyContinue

    Note ("Fiji:            {0}" -f $FijiExe)
    Note ("Engine:          {0}" -f $engineScript)
    Note ("Config:          {0}" -f $cfgPath)
    Note ("Detect-on set:   {0}" -f $resolvedDetectOn)
    Note ("Extract dry-run: {0}" -f $ExtractDryRun.IsPresent)
    Note "Launching headless Fiji (large LIFs can take a while)..."

    $env:LIF_EXTRACT_CONFIG = $cfgPath
    $fijiOut = Join-Path $runAuditDir 'fiji_stdout.log'
    $fijiErr = Join-Path $runAuditDir 'fiji_stderr.log'
    # fiji-windows-x64.exe is a GUI-SUBSYSTEM app: launching it with '&' returns
    # IMMEDIATELY without waiting, so a following log check would race ahead of the
    # engine (observed on the instance: "GUI program launched from PowerShell").
    # Use Start-Process -Wait so we block until Fiji exits, and redirect its
    # stdout/stderr to files (also sidesteps the native-stderr/EAP=Stop issue --
    # no pipeline involved). NOTE: the current launcher REJECTS --console
    # ("Ignoring invalid argument"), so it is intentionally omitted.
    # ArgumentList MUST be an ARRAY (one element per token): a single joined
    # string "--headless --run <path>" makes the launcher reject --run
    # ("Ignoring invalid argument: --run") and the engine never runs -- verified
    # on the instance. The array form quotes each token correctly.
    try {
        $proc = Start-Process -FilePath $FijiExe `
            -ArgumentList '--headless','--run',$engineScript `
            -Wait -NoNewWindow -PassThru `
            -RedirectStandardOutput $fijiOut -RedirectStandardError $fijiErr
        if ($proc) { Note ("Fiji exited with code {0}" -f $proc.ExitCode) }
    } finally {
        Remove-Item Env:\LIF_EXTRACT_CONFIG -ErrorAction SilentlyContinue
    }

    # Fiji's launcher can exit 0 even when the Jython script throws, so verify the
    # engine log itself: it must exist, reach the TOTALS block, and carry no
    # Traceback / class-load error.
    $engineOk = $false
    if (Test-Path $extractLog) {
        $logText = Get-Content $extractLog -Raw
        $engineOk = ($logText -match 'TOTALS') -and ($logText -notmatch 'Traceback|NoClassDefFoundError|UnsupportedClassVersionError')
    }
    if (-not $engineOk) {
        Err2 "LIF extraction did not complete cleanly. Inspect:"
        Err2 ("  engine log:  {0}" -f $extractLog)
        Err2 ("  fiji stdout: {0}" -f $fijiOut)
        Err2 ("  fiji stderr: {0}" -f $fijiErr)
        if (Test-Path $extractLog)  { Get-Content $extractLog -Tail 15 | ForEach-Object { Warn2 "  | $_" } }
        elseif (Test-Path $fijiErr) { Get-Content $fijiErr   -Tail 15 | ForEach-Object { Warn2 "  | $_" } }
        Stop-Transcript | Out-Null
        Write-Error "Phase 0 (LIF extraction) failed."
        return
    }

    if ($ExtractDryRun) {
        Note "Extract DRY-RUN complete -- planned outputs (no files written):"
        Get-Content $extractLog -Tail 40 | ForEach-Object { Write-Host "  | $_" }
        Note "Re-run without -ExtractDryRun to write TIFFs and continue into Split."
        Stop-Transcript | Out-Null
        return
    }

    # Stage the chosen set (TRIMMED|UNTRIMMED) from the mirrored per-LIF subfolders
    # into a FLAT folder that becomes -InputTIFFs. Hardlinked (zero extra disk on
    # NTFS); the extracted/ archive keeps its own links (incl. the untrimmed copies).
    $setDir = if ($resolvedDetectOn -eq 'trimmed') { 'TRIMMED' } else { 'UNTRIMMED' }
    $stage  = $paths['extract_input']
    $srcTiffs = @(Get-ChildItem $paths['extracted'] -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ieq $setDir })
    if ($srcTiffs.Count -eq 0) {
        Err2 ("No {0} TIFFs found under {1} after extraction." -f $setDir, $paths['extracted'])
        Stop-Transcript | Out-Null
        Write-Error "Phase 0 produced no detection inputs."
        return
    }
    # Collision guard: staging is flat by filename (series names must be unique
    # across LIFs). Fail loudly rather than silently overwrite.
    $dupes = $srcTiffs | Group-Object Name | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        Err2 "Duplicate filenames across LIFs would collide in the flat detection input:"
        foreach ($g in $dupes) { Err2 ("  {0} ({1} copies)" -f $g.Name, $g.Count) }
        Stop-Transcript | Out-Null
        Write-Error "Phase 0: duplicate extracted filenames; give the series unique names and re-run."
        return
    }
    $linked = 0; $copied = 0
    foreach ($f in $srcTiffs) {
        $dest = Join-Path $stage $f.Name
        if (Test-Path $dest) { continue }
        try { New-Item -ItemType HardLink -Path $dest -Value $f.FullName -ErrorAction Stop | Out-Null; $linked++ }
        catch { Copy-Item $f.FullName $dest -Force; $copied++ }
    }
    Note ("Staged {0} {1} TIFF(s) for detection (hardlinked={2}, copied={3})" -f $srcTiffs.Count, $setDir, $linked, $copied)

    # From here the pipeline treats the staged flat folder as the input. It is FLAT
    # by construction, so -RecurseInput is not needed downstream.
    $InputTIFFs = $stage

    "Extract completed $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')`nDetect-on set: $setDir`nStaged TIFFs: $($srcTiffs.Count)`nInput folder: $stage" |
        Out-File $markerExtract -Encoding UTF8
    "Extract completed $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Out-File (Join-Path $runAuditDir 'PHASE_extract_COMPLETE.txt') -Encoding UTF8
    PhaseEnd 'Extract' "LIF extraction" $extractStart ("{0} {1} TIFFs staged -> Split" -f $srcTiffs.Count, $setDir)
}

# ==========================================================
# Phase 0: Auto-size (if Lanes not given)
# ==========================================================
if (($Split -or $Detect) -and $Lanes -le 0) {
    if (-not $Split) {
        # Resume scenario: no need to split, derive lane count from existing folders
        $existingLanes = @(Get-ChildItem $paths['lanes'] -Directory -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -match '^lane' })
        if ($existingLanes.Count -gt 0) {
            $Lanes = $existingLanes.Count
            Note ("Using existing lane count: {0} lanes (from {1})" -f $Lanes, $paths['lanes'])
        } else {
            Warn2 "Cannot run Detect without lanes. No existing lane folders, and -Split is `$false."
            Warn2 "Either run with -Split `$true and provide -InputTIFFs, or populate lanes manually first."
            Stop-Transcript | Out-Null
            Write-Error "No lanes available for Detection."
        }
    } else {
        # Fresh start: profile InputTIFFs to determine lane count
        Phase 0 "Auto-size lanes"
        $autoSizer = Join-Path $ScriptsDir 'Auto-Size-Lanes.ps1'
        $sizeStart = Get-Date

        # Clear any previous recommendation file
        $recFile = Join-Path $env:TEMP "autosize_recommendation.txt"
        if (Test-Path $recFile) { Remove-Item $recFile -Force }

        Note "Profiling the largest TIFF (runs a full single-file detection; can take 30+ min on large/slow recordings, and auto-times-out if the probe file hangs). Pass -Lanes to skip this."
        & $autoSizer -ProbeFolder $InputTIFFs

        if (Test-Path $recFile) {
            $Lanes = [int]((Get-Content $recFile -Raw).Trim())
            Note ("Auto-Size recommended: {0} detection lanes (probe took {1:N1} min)" -f $Lanes, ((Get-Date)-$sizeStart).TotalMinutes)
            Remove-Item $recFile -Force -ErrorAction SilentlyContinue
        } else {
            Warn2 "Auto-Size did not produce a recommendation file. Falling back to CPU-only default."
            $Lanes = [math]::Min([math]::Floor($cpu / 3), 32)
            Note ("Using {0} detection lanes (CPU-only default)." -f $Lanes)
        }
    }
}
if ($CFULanes -le 0) {
    # On a CFU-only resume (Split + Detect both off), the auto-sizer above didn't
    # run, so $Lanes is still 0 -> derive it from the existing detection lane
    # folders so CFU gets a sane lane count (not 1). Falls back to CFU=1 only if
    # nothing is found (then pass -CFULanes yourself).
    if ($Lanes -le 0) {
        $existingLaneCount = @(Get-ChildItem $paths['lanes'] -Directory -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -match '^lane' }).Count
        if ($existingLaneCount -gt 0) {
            $Lanes = $existingLaneCount
            Note ("CFU-only resume: derived {0} from existing detection lane folders." -f $Lanes)
        }
    }
    $CFULanes = [math]::Max([math]::Floor($Lanes * 0.75), 1)
    if ($CFU) { Note ("CFU lanes: {0}" -f $CFULanes) }
}

# ==========================================================
# Phase 1: Split
# ==========================================================
if ($Split) {
    Phase 1 ("Split {0} TIFFs into {1} lanes" -f $inputCount, $Lanes)
    $start = Get-Date
    $splitter = Join-Path $ScriptsDir 'Split-IntoLanes.ps1'
    & $splitter -Source $InputTIFFs -LaneRoot $paths['lanes'] -Lanes $Lanes -Execute -Recurse:$RecurseInput
    $laneFolders = Get-ChildItem $paths['lanes'] -Directory | Where-Object { $_.Name -match '^lane' }
    Note ("Created {0} lane folders" -f $laneFolders.Count)
    PhaseEnd 1 "Split" $start $null

    # Phase-complete markers: dual-write (top-level for resume, per-run for history)
    $splitMarkerContent = @"
Split phase completed at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Lane folders created: $($laneFolders.Count)
Input TIFFs:          $inputCount
Lane root:            $($paths['lanes'])
Run audit dir:        $runAuditDir
"@
    $splitMarkerContent | Out-File $markerSplit -Encoding UTF8
    $splitMarkerContent | Out-File (Join-Path $runAuditDir 'PHASE_split_COMPLETE.txt') -Encoding UTF8
}

# ==========================================================
# Phase 2: Detection
# ==========================================================
if ($Detect) {
    # Swap config CSV if the resolved one differs from the default location
    $defaultCSV = "C:\AQuA2\cfg\parameters_for_batch.csv"
    $sourceCSV = if ($script:resolvedConfigCSV) { $script:resolvedConfigCSV } else { $defaultCSV }
    if ($sourceCSV -and (Test-Path $sourceCSV) -and ($sourceCSV -ne $defaultCSV)) {
        if (Test-Path $defaultCSV) {
            $backup = "$defaultCSV.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $defaultCSV $backup
            Note ("Backed up existing default CSV to {0}" -f $backup)
        }
        Copy-Item $sourceCSV $defaultCSV -Force
        Note ("Active config CSV (copied from {0}): {1}" -f $sourceCSV, $defaultCSV)
    } else {
        Note ("Active config CSV: {0}" -f $defaultCSV)
    }

    # Archive the active CSV into per-run audit dir BEFORE detection starts
    Save-ParametersInUse

    # Snapshot stale failure count so we only report NEW failures from this run
    $baselineFailures = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
    if ($baselineFailures -gt 0) {
        Note ("Pre-existing _ERROR.txt files at phase start: {0} (will be ignored in 'fail' counter)" -f $baselineFailures)
    }

    Phase 2 ("Detection ({0} parallel workers)" -f $Lanes)
    $start = Get-Date
    $launcher = Join-Path $ScriptsDir 'Launch-Lanes-Exe.ps1'

    $tifCount = (Get-ChildItem -Path $paths['lanes'] -Recurse -Include *.tif,*.tiff -File |
                 Where-Object { $_.Name -notlike '._*' }).Count   # v0.8: ignore macOS ._ sidecars
    $alreadyDone = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
    Note ("Total TIFFs across lanes: {0}" -f $tifCount)
    if ($alreadyDone -gt 0) {
        $remaining = $tifCount - $alreadyDone
        Note ("Already processed (resume): {0} files" -f $alreadyDone)
        Note ("Remaining to process:       {0} files" -f $remaining)
        Note "(workers' per-file resume guard will skip the already-done ones)"
    } else {
        Note "Fresh start (no previous detection outputs found)."
    }
    Note "Invoking Launch-Lanes-Exe.ps1 (spawns workers, returns quickly)..."

    # Launch-Lanes-Exe.ps1 is fire-and-forget: it spawns aqua_lane.exe processes
    # via Start-Process and returns. We call it synchronously, then poll based on
    # the actual aqua_lane.exe processes.
    & $launcher -LaneRoot $paths['lanes'] -ResultsRoot $paths['PreCFU'] -Lanes $Lanes

    Note "Launcher returned. Waiting 10s for workers to register, then polling..."
    Start-Sleep -Seconds 10

    $lastDetail = Get-Date
    $throughputWindow = New-Object System.Collections.Queue
    $aborted = $false
    $noWorkersStreak = 0
    $everSawWorkers = $false
    # v0.8: bounded auto-relaunch + completeness tracking for detection
    $DetectRelaunchCount = 0
    if (-not $PSBoundParameters.ContainsKey('MaxDetectRelaunch')) { $MaxDetectRelaunch = 3 }
    $detectionIncomplete = $false
    # Per-lane stall tracking: laneName -> @{ lastCount=N; lastChangeAt=DateTime; warned=$false }
    $laneStall = @{}
    $stallLogPath = Join-Path $runAuditDir "stall_log.txt"
    $laneLogDir = Join-Path $paths['PreCFU'] '_lane_logs'

    while ($true) {
        $workers = @(Get-Process aqua_lane -ErrorAction SilentlyContinue)
        $workerCount = $workers.Count
        if ($workerCount -gt 0) { $everSawWorkers = $true }

        $rawCompleted = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
        $rawFailures  = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
        # Adjust failures by subtracting baseline (stale failures from previous runs)
        $completed = $rawCompleted
        $failures  = [math]::Max(0, $rawFailures - $baselineFailures)
        $free      = Get-FreeGB
        $availRAM  = Get-AvailRAMGB
        $elapsed   = (Get-Date) - $start

        $throughputWindow.Enqueue([pscustomobject]@{ t = Get-Date; c = $completed })
        while ($throughputWindow.Count -gt 5) { [void]$throughputWindow.Dequeue() }
        $tw = @($throughputWindow)
        if ($tw.Count -ge 2) {
            $delta = $tw[-1].c - $tw[0].c
            $dtMin = ($tw[-1].t - $tw[0].t).TotalMinutes
            $rate = if ($dtMin -gt 0) { $delta / $dtMin } else { 0 }
        } else { $rate = 0 }

        $remaining = $tifCount - $completed
        $etaMin = if ($rate -gt 0.01) { [math]::Round($remaining / $rate, 0) } else { -1 }
        $etaStr = if ($etaMin -ge 0) { "{0,5:N0}m" -f $etaMin } else { "  ???" }
        $pct = if ($tifCount -gt 0) { ($completed / $tifCount) * 100 } else { 0 }

        Write-Host (
            "  [{0}] {1,4}/{2,-4} {3,5:N1}% | {4,5:N1} f/min | ETA {5} | workers {6}/{7} | RAM {8,5:N1}GB | Disk {9,5:N0}GB | fail {10}" `
            -f (Get-Date -Format 'HH:mm:ss'), $completed, $tifCount, $pct, $rate, $etaStr, $workerCount, $Lanes, $availRAM, $free, $failures
        )

        # ===== Per-lane stall tracking =====
        $laneFolders = @(Get-ChildItem $paths['lanes'] -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^lane' })
        # Cache the list of completed mat files once per polling iteration (avoids N*M lookups)
        $allCompletedMats = @{}
        Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue | ForEach-Object {
            $allCompletedMats[($_.Name -replace '_AQuA2\.mat$','')] = $true
        }

        foreach ($laneDir in $laneFolders) {
            $laneName = $laneDir.Name
            # Count completed _AQuA2.mat for TIFFs originating from this lane.
            # Worker writes output to PreCFU/laneNN_results/<stem>_AQuA2.mat,
            # so we search by stem (filename match) anywhere under PreCFU rather than
            # guessing the output directory.
            # NOTE: -Recurse is REQUIRED here. Get-ChildItem -Include matches nothing without
            # -Recurse (or a \* path), so before v0.9.1 $expectedTiffs was always empty ->
            # $laneCompleted pinned at 0 -> the stall clock never advanced -> false WARN/
            # ESCALATE/AUTO-SKIP on every lane while the run progressed fine. (v0.9.1 fix.)
            $expectedTiffs = @(Get-ChildItem $laneDir.FullName -File -Recurse -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                               Where-Object { $_.Directory.FullName -notmatch '\\_stalled(\\|$)' })
            $laneCompleted = 0
            foreach ($t in $expectedTiffs) {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($t.Name)
                if ($allCompletedMats.ContainsKey($stem)) { $laneCompleted++ }
            }
            # Check if this lane's worker is still alive
            $lanePID = Get-LanePID -LaneFolder $laneDir.FullName -WorkerExeName 'aqua_lane.exe'
            $laneAlive = ($lanePID -ne $null)

            if (-not $laneStall.ContainsKey($laneName)) {
                $laneStall[$laneName] = @{ lastCount=$laneCompleted; lastChangeAt=Get-Date; warned=$false; escalated=$false }
            } elseif ($laneCompleted -ne $laneStall[$laneName].lastCount) {
                $laneStall[$laneName].lastCount = $laneCompleted
                $laneStall[$laneName].lastChangeAt = Get-Date
                $laneStall[$laneName].warned = $false
                $laneStall[$laneName].escalated = $false
            } else {
                # No progress in this lane; if worker is still alive, check stall thresholds
                if ($laneAlive) {
                    $stalledMin = ((Get-Date) - $laneStall[$laneName].lastChangeAt).TotalMinutes
                    # Stage 1: warn threshold (yellow, first heads-up)
                    if ($stalledMin -ge $StallWarnMin -and -not $laneStall[$laneName].warned) {
                        Write-Host ""
                        Warn2 ("[STALL WARN] {0} (PID {1}) has made no progress for {2:N1} min" -f $laneName, $lanePID, $stalledMin)
                        $laneLog = Join-Path $laneLogDir ("{0}.log" -f $laneName)
                        $tail = Get-LaneLogTail -LogPath $laneLog -N 5
                        if ($tail) {
                            Warn2 "  Last lines from $laneName log:"
                            foreach ($l in $tail) { Warn2 "    $l" }
                        }
                        Warn2 ("  Auto-skip will fire at {0} min; manual abort: Stop-Process -Id {1} -Force" -f $StallAutoSkipMin, $lanePID)
                        $laneStall[$laneName].warned = $true
                        Add-Content -Path $stallLogPath -Value ("[{0}] STALL WARN: {1} (PID {2}) no progress for {3:N1} min" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $laneName, $lanePID, $stalledMin)
                        Write-Host ""
                    }
                    # Stage 2: escalated warning (red, louder formatting; still no destructive action)
                    if ($stalledMin -ge $StallEscalateMin -and -not $laneStall[$laneName].escalated) {
                        Write-Host ""
                        Write-Host "================================================================" -ForegroundColor Red
                        Write-Host (" [STALL ESCALATED] {0} (PID {1}) stalled {2:N1} min" -f $laneName, $lanePID, $stalledMin) -ForegroundColor Red
                        Write-Host "================================================================" -ForegroundColor Red
                        $laneLog = Join-Path $laneLogDir ("{0}.log" -f $laneName)
                        $tail = Get-LaneLogTail -LogPath $laneLog -N 10
                        if ($tail) {
                            Write-Host "  Last 10 lines from $laneName log:" -ForegroundColor Red
                            foreach ($l in $tail) { Write-Host ("    $l") -ForegroundColor Red }
                        }
                        $minsToAutoSkip = [math]::Round($StallAutoSkipMin - $stalledMin, 1)
                        Write-Host ("  Auto-skip will fire in {0} more minutes (at {1} min total)" -f $minsToAutoSkip, $StallAutoSkipMin) -ForegroundColor Red
                        Write-Host "  To intervene manually:" -ForegroundColor Red
                        Write-Host ("    Stop-Process -Id {0} -Force" -f $lanePID) -ForegroundColor Red
                        Write-Host ""
                        $laneStall[$laneName].escalated = $true
                        Add-Content -Path $stallLogPath -Value ("[{0}] STALL ESCALATED: {1} (PID {2}) no progress for {3:N1} min" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $laneName, $lanePID, $stalledMin)
                    }
                    # Stage 3: auto-skip threshold
                    if ($stalledMin -ge $StallAutoSkipMin -and $StallPolicy -eq 'auto-skip') {
                        Write-Host ""
                        Warn2 ("[STALL AUTO-SKIP] {0} stalled for {1:N1} min -- moving stuck file aside and restarting" -f $laneName, $stalledMin)
                        $laneLogPath = Join-Path $laneLogDir ("{0}.log" -f $laneName)
                        $didSkip = Invoke-AutoSkipFile `
                            -LaneFolder $laneDir.FullName `
                            -ResultsRoot $paths['PreCFU'] `
                            -WorkerExe "C:\AQuA2\compiled\aqua_lane.exe" `
                            -LogPath $laneLogPath `
                            -StallLogPath $stallLogPath
                        if ($didSkip) {
                            $laneStall[$laneName].lastChangeAt = Get-Date
                            $laneStall[$laneName].warned = $false
                            $laneStall[$laneName].escalated = $false
                            Start-Sleep -Seconds 5  # let new worker register
                        } else {
                            Warn2 ("Auto-skip did not succeed for {0}; will warn again at next interval." -f $laneName)
                        }
                        Write-Host ""
                    }
                }
            }
        }

        # --- Exit conditions ---
        if ($workerCount -eq 0) {
            $noWorkersStreak++
        } else {
            $noWorkersStreak = 0
        }
        if ($everSawWorkers -and $noWorkersStreak -ge 2) {
            # v0.8: workers gone is NOT the same as "done". A single unreadable file
            # (e.g. a macOS ._ stub, a truncated TIFF) can kill a lane worker mid-run.
            # Before declaring complete, check whether every REAL input has an output.
            # _real_ excludes ._ AppleDouble sidecars (counted as TIFFs by the OS but not images).
            $realInputs = @(Get-ChildItem -Path $paths['lanes'] -Recurse -Include *.tif,*.tiff -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -notlike '._*' -and $_.Directory.FullName -notmatch '\\_stalled(\\|$)' }).Count
            $doneNow    = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue).Count
            if ($doneNow -ge $realInputs) {
                Note ("All detection workers have exited. Completeness check OK: {0}/{1} real inputs detected." -f $doneNow, $realInputs)
                break
            } else {
                $missing = $realInputs - $doneNow
                if ($DetectRelaunchCount -lt $MaxDetectRelaunch) {
                    $DetectRelaunchCount++
                    Warn2 ("Workers exited with {0} of {1} real inputs still unprocessed. Relaunching detection (attempt {2}/{3}); completed files are skipped." -f $missing, $realInputs, $DetectRelaunchCount, $MaxDetectRelaunch)
                    & $launcher -LaneRoot $paths['lanes'] -ResultsRoot $paths['PreCFU'] -Lanes $Lanes
                    $noWorkersStreak = 0
                    $everSawWorkers = $false
                    $relaunchStart = Get-Date
                    Start-Sleep -Seconds 10
                    continue
                } else {
                    Err2 ("Detection INCOMPLETE: {0} of {1} real inputs processed ({2} missing) after {3} relaunch attempt(s)." -f $doneNow, $realInputs, $missing, $MaxDetectRelaunch)
                    Err2 "Likely an unreadable input file repeatedly killing a lane. Check PreCFU\_lane_logs\*.err for [FAIL] lines, remove the offending file(s), and re-run -Detect."
                    $detectionIncomplete = $true
                    break
                }
            }
        }
        if (-not $everSawWorkers -and $elapsed.TotalSeconds -gt 90) {
            Err2 "Launcher returned but no aqua_lane.exe workers detected after 90s."
            Err2 "Check Launch-Lanes-Exe.ps1 output above for errors. Aborting."
            $aborted = $true
            break
        }

        # --- Disk-space abort ---
        if ($free -lt $MinFreeDiskGB) {
            Err2 ("Free disk ({0} GB) below threshold ({1} GB). Aborting." -f $free, $MinFreeDiskGB)
            Err2 "Killing workers:"
            Get-Process aqua_lane -ErrorAction SilentlyContinue | Stop-Process -Force
            $aborted = $true
            break
        }

        if (((Get-Date) - $lastDetail).TotalSeconds -ge $DetailEverySec) {
            $lastDetail = Get-Date
            Write-Host ""
            Write-Host ("  --- Detailed snapshot @ {0} ---" -f (Get-Date -Format 'HH:mm:ss'))
            Write-Host ("  Elapsed: {0:hh\:mm\:ss}" -f $elapsed)
            Write-Host ("  Throughput (recent window): {0:N1} files/min" -f $rate)
            Write-Host ("  Workers alive: {0}/{1}" -f $workerCount, $Lanes)
            if ($etaMin -ge 0) {
                $eta = (Get-Date).AddMinutes($etaMin)
                Write-Host ("  ETA: {0} min (~{1})" -f $etaMin, $eta.ToString('HH:mm'))
            }
            # Per-lane progress + log tail
            Write-Host "  Per-lane progress:"
            foreach ($ln in $laneStall.Keys | Sort-Object) {
                $stallMin = ((Get-Date) - $laneStall[$ln].lastChangeAt).TotalMinutes
                $alive = (Get-LanePID -LaneFolder (Join-Path $paths['lanes'] $ln) -WorkerExeName 'aqua_lane.exe') -ne $null
                $aliveStr = if ($alive) { 'ALIVE' } else { 'gone ' }
                Write-Host ("    {0}: {1} ({2:N1} min since last completion in lane) [{3}]" -f $ln, $laneStall[$ln].lastCount, $stallMin, $aliveStr)
                $laneLog = Join-Path $laneLogDir ("{0}.log" -f $ln)
                $tail = Get-LaneLogTail -LogPath $laneLog -N 2
                foreach ($l in $tail) { Write-Host ("      | $l") }
            }
            if ($failures -gt 0) {
                Write-Host "  Recent NEW failures (last 3):"
                Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File |
                    Sort-Object LastWriteTime -Desc | Select-Object -First 3 |
                    ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
            }
            Write-Host ""
        }

        Start-Sleep -Seconds $PollEverySec
    }

    if ($aborted) {
        Stop-Transcript | Out-Null
        Write-Error "Detection aborted. Free up disk or fix launcher issue, then re-run with -Split `$false -Detect `$true."
    }

    $finalDone = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File).Count
    $finalFailRaw = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_ERROR.txt" -File).Count
    $finalFailNew = [math]::Max(0, $finalFailRaw - $baselineFailures)
    PhaseEnd 2 "Detection" $start ("Files: $finalDone OK, $finalFailNew failed in this run ($finalFailRaw total _ERROR.txt files; $baselineFailures pre-existing)")

    # Per-file audit CSV for detection
    Write-PerFileStatus -Phase 'detection' -ResultsDir $paths['PreCFU'] -OkPattern '*_AQuA2.mat' -FailDir $null

    # Failures summary (collect _ERROR.txt files into per-run audit dir)
    Save-FailuresSummary -Phase 'detection' -ResultsDir $paths['PreCFU']

    # Phase-complete markers: write to BOTH top-level (for resume) AND per-run (for history).
    # v0.8.2: an INCOMPLETE detection must NOT leave a PHASE_detect_COMPLETE marker -- that
    # marker drives the "PREVIOUSLY COMPLETED" plan-summary hint and reads as a finished phase.
    # Write a distinct _INCOMPLETE marker instead (and remove any stale COMPLETE marker), so
    # the run's true state is unambiguous on re-run.
    $statusWord = if ($detectionIncomplete) { 'INCOMPLETE' } else { 'completed' }
    $markerContent = @"
Detection phase $statusWord at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Files OK:                $finalDone
Files failed (this run): $finalFailNew
Files failed (total _ERROR.txt): $finalFailRaw
Files attempted:         $tifCount
Already-done at start:   $alreadyDone
Detection lanes used:    $Lanes
Stall warnings issued:   $((Get-Content $stallLogPath -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Auto-skip' }).Count)
Config CSV in effect:    $(if ($script:resolvedConfigCSV) { $script:resolvedConfigCSV } else { 'C:\AQuA2\cfg\parameters_for_batch.csv (default)' })
Run audit dir:           $runAuditDir
"@
    if ($detectionIncomplete) {
        $incMarker = Join-Path $paths['logs'] 'PHASE_detect_INCOMPLETE.txt'
        $markerContent | Out-File $incMarker -Encoding UTF8
        $markerContent | Out-File (Join-Path $runAuditDir 'PHASE_detect_INCOMPLETE.txt') -Encoding UTF8
        if (Test-Path $markerDetect) { Remove-Item $markerDetect -Force -ErrorAction SilentlyContinue }
        Warn2 "Detection incomplete: wrote PHASE_detect_INCOMPLETE.txt (no COMPLETE marker)."
    } else {
        $markerContent | Out-File $markerDetect -Encoding UTF8
        $markerContent | Out-File (Join-Path $runAuditDir 'PHASE_detect_COMPLETE.txt') -Encoding UTF8
    }
}

# ==========================================================
# Phase 3: CFU (build + run, combined)
# ==========================================================
if ($CFU) {
    # v0.8: never run CFU on a detection that didn't finish -- that produces a
    # silently partial result set that looks complete downstream.
    if ($detectionIncomplete) {
        Err2 "Skipping CFU: detection did not complete for all real inputs (see message above). Fix the offending input(s) and re-run -Detect before CFU."
    } else {
    Phase 3 ("CFU build + run ({0} parallel workers)" -f $CFULanes)
    $start = Get-Date

    # Archive the CFU baked-parameters reference into _logs/
    Save-CFUBakedParameters

    # --- 3a: junctions ---
    $builder = Join-Path $ScriptsDir 'Build-CFU-Lanes.ps1'
    $matCount = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File).Count
    Note ("Detection .mat files: {0}" -f $matCount)
    Note "Building CFU lane junctions..."
    & $builder -Root $paths['PreCFU'] -LaneRoot $paths['CFU_lanes'] -Lanes $CFULanes -Execute
    # CFU lane folders are named cfu_laneNN, so '^lane' matched none -> "Junctions ready: 0". (v0.9.1 fix.)
    $cfuLaneFolders = Get-ChildItem $paths['CFU_lanes'] -Directory | Where-Object { $_.Name -match '^cfu_lane' }
    Note ("Junctions ready: {0} lane folders" -f $cfuLaneFolders.Count)

    # --- 3b: clustering ---
    $cfuLauncher = Join-Path $ScriptsDir 'Launch-CFU-Lanes.ps1'
    $cfuLogDir = Join-Path $paths['CFU_lanes'] '_logs'
    $cfuAlreadyDone = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue).Count
    if ($cfuAlreadyDone -gt 0) {
        $cfuRemaining = $matCount - $cfuAlreadyDone
        Note ("Already CFU-processed (resume): {0} files" -f $cfuAlreadyDone)
        Note ("Remaining to process:           {0} files" -f $cfuRemaining)
        Note "(workers' per-file resume guard will skip the already-done ones)"
    } else {
        Note "Fresh CFU start (no previous CFU outputs found)."
    }
    Note "Invoking Launch-CFU-Lanes.ps1 (spawns workers, returns quickly)..."

    & $cfuLauncher -LaneRoot $paths['CFU_lanes'] -Post $paths['POST'] -LogDir $cfuLogDir -Lanes $CFULanes

    Note "CFU launcher returned. Waiting 10s for workers to register, then polling..."
    Start-Sleep -Seconds 10

    $throughputWindow = New-Object System.Collections.Queue
    $noWorkersStreak = 0
    $everSawWorkers = $false
    $aborted = $false
    $cfuLastDetail = Get-Date
    $cfuLaneStall = @{}
    $cfuStallLogPath = Join-Path $runAuditDir "stall_log.txt"
    $cfuBaselineFailures = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
    if ($cfuBaselineFailures -gt 0) {
        Note ("Pre-existing CFU _ERROR.txt files at phase start: {0} (will be ignored)" -f $cfuBaselineFailures)
    }

    while ($true) {
        $workers = @(Get-Process cfu_lane -ErrorAction SilentlyContinue)
        $workerCount = $workers.Count
        if ($workerCount -gt 0) { $everSawWorkers = $true }

        $rawCompleted = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue).Count
        $rawFailures  = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File -ErrorAction SilentlyContinue).Count
        $completed = $rawCompleted
        $failures  = [math]::Max(0, $rawFailures - $cfuBaselineFailures)
        $free = Get-FreeGB
        $availRAM = Get-AvailRAMGB
        $cfuElapsed = (Get-Date) - $start

        $throughputWindow.Enqueue([pscustomobject]@{ t = Get-Date; c = $completed })
        while ($throughputWindow.Count -gt 5) { [void]$throughputWindow.Dequeue() }
        $tw = @($throughputWindow)
        if ($tw.Count -ge 2) {
            $delta = $tw[-1].c - $tw[0].c
            $dtMin = ($tw[-1].t - $tw[0].t).TotalMinutes
            $rate = if ($dtMin -gt 0) { $delta / $dtMin } else { 0 }
        } else { $rate = 0 }

        $remaining = $matCount - $completed
        $etaMin = if ($rate -gt 0.01) { [math]::Round($remaining / $rate, 0) } else { -1 }
        $etaStr = if ($etaMin -ge 0) { "{0,5:N0}m" -f $etaMin } else { "  ???" }
        $pct = if ($matCount -gt 0) { ($completed / $matCount) * 100 } else { 0 }

        Write-Host (
            "  [{0}] {1,4}/{2,-4} {3,5:N1}% | {4,5:N1} f/min | ETA {5} | workers {6}/{7} | RAM {8,5:N1}GB | Disk {9,5:N0}GB | fail {10}" `
            -f (Get-Date -Format 'HH:mm:ss'), $completed, $matCount, $pct, $rate, $etaStr, $workerCount, $CFULanes, $availRAM, $free, $failures
        )

        # ===== Per-CFU-lane stall tracking =====
        $cfuLaneFolders = @(Get-ChildItem $paths['CFU_lanes'] -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^cfu_lane' })
        # Cache completed _res_cfu.mat names once per iteration
        $allCompletedRes = @{}
        Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue | ForEach-Object {
            $allCompletedRes[($_.Name -replace '_AQuA2_res_cfu\.mat$','')] = $true
        }

        foreach ($laneDir in $cfuLaneFolders) {
            $laneName = $laneDir.Name
            # CFU input files are _AQuA2.mat reached THROUGH directory junctions (each
            # cfu_laneNN\ holds junctions -> the real result folders; see Build-CFU-Lanes.ps1).
            # Get-ChildItem -Recurse from the lane root does NOT reliably descend through
            # junction reparse points (behavior differs by PowerShell version), so before
            # v0.9.1 this count read 0 all run -> false CFU stalls. Fix: list each junction as
            # a top-level child dir, then read its contents via DIRECT access (Get-ChildItem on
            # the junction path itself), which resolves through the junction reliably. The real
            # result folder holds the _AQuA2.mat at its top level, so no inner recurse is needed.
            $laneMats = @(
                Get-ChildItem $laneDir.FullName -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-ChildItem $_.FullName -File -Filter '*_AQuA2.mat' -ErrorAction SilentlyContinue }
            )
            $laneCompleted = 0
            foreach ($m in $laneMats) {
                $stem = ($m.Name -replace '_AQuA2\.mat$','')
                if ($allCompletedRes.ContainsKey($stem)) { $laneCompleted++ }
            }
            $lanePID = Get-LanePID -LaneFolder $laneDir.FullName -WorkerExeName 'cfu_lane.exe'
            $laneAlive = ($lanePID -ne $null)

            if (-not $cfuLaneStall.ContainsKey($laneName)) {
                $cfuLaneStall[$laneName] = @{ lastCount=$laneCompleted; lastChangeAt=Get-Date; warned=$false; escalated=$false }
            } elseif ($laneCompleted -ne $cfuLaneStall[$laneName].lastCount) {
                $cfuLaneStall[$laneName].lastCount = $laneCompleted
                $cfuLaneStall[$laneName].lastChangeAt = Get-Date
                $cfuLaneStall[$laneName].warned = $false
                $cfuLaneStall[$laneName].escalated = $false
            } else {
                if ($laneAlive) {
                    $stalledMin = ((Get-Date) - $cfuLaneStall[$laneName].lastChangeAt).TotalMinutes
                    # Stage 1: warn
                    if ($stalledMin -ge $StallWarnMin -and -not $cfuLaneStall[$laneName].warned) {
                        Write-Host ""
                        Warn2 ("[CFU STALL WARN] {0} (PID {1}) has made no progress for {2:N1} min" -f $laneName, $lanePID, $stalledMin)
                        $laneLog = Join-Path $cfuLogDir ("{0}.log" -f $laneName)
                        $tail = Get-LaneLogTail -LogPath $laneLog -N 5
                        if ($tail) {
                            Warn2 "  Last lines from $laneName log:"
                            foreach ($l in $tail) { Warn2 "    $l" }
                        }
                        $cfuLaneStall[$laneName].warned = $true
                        Add-Content -Path $cfuStallLogPath -Value ("[{0}] CFU STALL WARN: {1} (PID {2}) no progress for {3:N1} min" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $laneName, $lanePID, $stalledMin)
                        Write-Host ""
                    }
                    # Stage 2: escalate
                    if ($stalledMin -ge $StallEscalateMin -and -not $cfuLaneStall[$laneName].escalated) {
                        Write-Host ""
                        Write-Host "================================================================" -ForegroundColor Red
                        Write-Host (" [CFU STALL ESCALATED] {0} (PID {1}) stalled {2:N1} min" -f $laneName, $lanePID, $stalledMin) -ForegroundColor Red
                        Write-Host "================================================================" -ForegroundColor Red
                        $laneLog = Join-Path $cfuLogDir ("{0}.log" -f $laneName)
                        $tail = Get-LaneLogTail -LogPath $laneLog -N 10
                        if ($tail) {
                            Write-Host "  Last 10 lines from $laneName log:" -ForegroundColor Red
                            foreach ($l in $tail) { Write-Host ("    $l") -ForegroundColor Red }
                        }
                        $minsToAutoSkip = [math]::Round($StallAutoSkipMin - $stalledMin, 1)
                        Write-Host ("  Auto-action will fire in {0} more minutes (at {1} min total)" -f $minsToAutoSkip, $StallAutoSkipMin) -ForegroundColor Red
                        Write-Host "  To intervene manually:" -ForegroundColor Red
                        Write-Host ("    Stop-Process -Id {0} -Force" -f $lanePID) -ForegroundColor Red
                        Write-Host ""
                        $cfuLaneStall[$laneName].escalated = $true
                        Add-Content -Path $cfuStallLogPath -Value ("[{0}] CFU STALL ESCALATED: {1} (PID {2}) no progress for {3:N1} min" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $laneName, $lanePID, $stalledMin)
                    }
                    # Stage 3: auto-action (CFU is conservative: kills worker + writes marker, no auto-restart)
                    if ($stalledMin -ge $StallAutoSkipMin -and $StallPolicy -eq 'auto-skip') {
                        Write-Host ""
                        Warn2 ("[CFU STALL AUTO-SKIP] {0} stalled for {1:N1} min -- killing worker and writing a stall marker (no auto-restart for CFU)" -f $laneName, $stalledMin)
                        # Find stuck file: a _AQuA2.mat under this lane (via junction) without matching _res_cfu.mat
                        $stuck = $null
                        foreach ($m in $laneMats) {
                            $stem = ($m.Name -replace '_AQuA2\.mat$','')
                            if (-not $allCompletedRes.ContainsKey($stem)) { $stuck = $m; break }
                        }
                        if ($stuck) {
                            Warn2 ("Stuck CFU file: {0}" -f $stuck.Name)
                            # Kill the worker
                            if ($lanePID) {
                                Stop-Process -Id $lanePID -Force -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 2
                            }
                            # For CFU, the lane folder contains junctions to detection output dirs.
                            # We can't easily "move" a junction-linked file to _stalled/.
                            # Instead, write a marker file that the user / re-run can use to skip this stem.
                            $stalledMarker = Join-Path $laneDir.FullName ("_STALLED_{0}.txt" -f $stuck.BaseName)
                            $markerContent = @"
Marked stalled at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Source _AQuA2.mat: $($stuck.FullName)
Lane: $laneName
Reason: cfu_lane stalled for $stalledMin min on this file
NOTE: This is a marker only. To actually skip this file, manually rename or move
      the source _AQuA2.mat or its parent folder before restarting CFU.
"@
                            $markerContent | Out-File $stalledMarker -Encoding UTF8
                            Add-Content -Path $cfuStallLogPath -Value $markerContent

                            Warn2 "CFU stall handling: worker killed, marker written. NOT restarting CFU worker automatically"
                            Warn2 "(because CFU lanes use junctions; safer to let user inspect and manually re-run)"
                            Warn2 ("Marker: {0}" -f $stalledMarker)
                        } else {
                            Warn2 ("Could not identify stuck CFU file for {0}; skip not performed." -f $laneName)
                        }
                        $cfuLaneStall[$laneName].lastChangeAt = Get-Date
                        $cfuLaneStall[$laneName].warned = $false
                        $cfuLaneStall[$laneName].escalated = $false
                        Write-Host ""
                    }
                }
            }
        }

        # Exit conditions
        if ($workerCount -eq 0) { $noWorkersStreak++ } else { $noWorkersStreak = 0 }
        if ($everSawWorkers -and $noWorkersStreak -ge 2) {
            Note "All CFU workers have exited."
            break
        }
        if (-not $everSawWorkers -and $cfuElapsed.TotalSeconds -gt 90) {
            Err2 "CFU launcher returned but no cfu_lane.exe workers detected after 90s."
            Err2 "Check Launch-CFU-Lanes.ps1 output above. Aborting CFU."
            $aborted = $true
            break
        }

        if (((Get-Date) - $cfuLastDetail).TotalSeconds -ge $DetailEverySec) {
            $cfuLastDetail = Get-Date
            Write-Host ""
            Write-Host ("  --- CFU detailed snapshot @ {0} ---" -f (Get-Date -Format 'HH:mm:ss'))
            Write-Host ("  Elapsed: {0:hh\:mm\:ss}" -f $cfuElapsed)
            Write-Host ("  Throughput: {0:N1} files/min" -f $rate)
            Write-Host ("  Workers alive: {0}/{1}" -f $workerCount, $CFULanes)
            if ($cfuLaneStall.Keys.Count -gt 0) {
                Write-Host "  Per-CFU-lane progress:"
                foreach ($ln in $cfuLaneStall.Keys | Sort-Object) {
                    $stallMin = ((Get-Date) - $cfuLaneStall[$ln].lastChangeAt).TotalMinutes
                    $alive = (Get-LanePID -LaneFolder (Join-Path $paths['CFU_lanes'] $ln) -WorkerExeName 'cfu_lane.exe') -ne $null
                    $aliveStr = if ($alive) { 'ALIVE' } else { 'gone ' }
                    Write-Host ("    {0}: {1} done ({2:N1} min since last) [{3}]" -f $ln, $cfuLaneStall[$ln].lastCount, $stallMin, $aliveStr)
                    $laneLog = Join-Path $cfuLogDir ("{0}.log" -f $ln)
                    $tail = Get-LaneLogTail -LogPath $laneLog -N 2
                    foreach ($l in $tail) { Write-Host ("      | $l") }
                }
            }
            if ($failures -gt 0) {
                Write-Host "  Recent NEW CFU failures (last 3):"
                Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File |
                    Sort-Object LastWriteTime -Desc | Select-Object -First 3 |
                    ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
            }
            Write-Host ""
        }

        Start-Sleep -Seconds $PollEverySec
    }

    if ($aborted) {
        Stop-Transcript | Out-Null
        Write-Error "CFU aborted. Investigate launcher output and re-run with -Split `$false -Detect `$false -CFU `$true."
    }

    $finalDone = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File).Count
    $finalFailRaw = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_ERROR.txt" -File).Count
    $finalFailNew = [math]::Max(0, $finalFailRaw - $cfuBaselineFailures)
    PhaseEnd 3 "CFU" $start ("Files: $finalDone OK, $finalFailNew failed in this run")

    # v0.8.1: CFU completeness check. Detection has a bounded auto-relaunch + hard
    # gate (v0.8.0); CFU previously just exited when its workers died, so a worker
    # killed by a bad _AQuA2.mat could leave POST silently short. We don't auto-
    # relaunch CFU (its lanes are junctions and a persistently-bad file would loop),
    # but we surface the shortfall loudly so it isn't mistaken for a complete run.
    if ($finalDone -lt $matCount) {
        $cfuMissing = $matCount - $finalDone
        Warn2 ("CFU INCOMPLETE: {0}/{1} detection outputs produced a _res_cfu.mat ({2} missing)." -f $finalDone, $matCount, $cfuMissing)
        Warn2 "Check POST\_failures\*_ERROR.txt and any _STALLED_*.txt markers under CFU_lanes\, then re-run -CFU (the resume guard skips completed files)."
    }

    # Per-file audit CSV for CFU
    Write-PerFileStatus -Phase 'cfu' -ResultsDir $paths['POST'] -OkPattern '*_res_cfu.mat' -FailDir $null

    # Failures summary for CFU
    Save-FailuresSummary -Phase 'cfu' -ResultsDir $paths['POST']

    # Phase-complete markers: dual-write
    $cfuMarkerContent = @"
CFU phase completed at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Files OK:                $finalDone
Files failed (this run): $finalFailNew
Files failed (total _ERROR.txt): $finalFailRaw
Files attempted:         $matCount
Already-done at start:   $cfuAlreadyDone
CFU lanes used:          $CFULanes
Run audit dir:           $runAuditDir
"@
    $cfuMarkerContent | Out-File $markerCFU -Encoding UTF8
    $cfuMarkerContent | Out-File (Join-Path $runAuditDir 'PHASE_cfu_COMPLETE.txt') -Encoding UTF8
    }   # end else (detection complete)
}

# ==========================================================
# Phase 4: Consolidate -- flatten outputs into for_upload/
# ==========================================================
if ($Consolidate -and $detectionIncomplete) {
    # v0.8.1: do not package a partial detection as if it were complete.
    Phase 4 ("Consolidate outputs for upload")
    Err2 "Skipping Consolidate: detection did not complete for all real inputs this run (see message above)."
    Err2 "A partial result set must not be packaged into for_upload/. Fix the offending input(s), re-run -Detect, then -Consolidate."
}
elseif ($Consolidate) {
    Phase 4 ("Consolidate outputs for upload")
    $start = Get-Date

    $uploadDir = $paths['for_upload']
    $upTIFFs   = Join-Path $uploadDir 'input_TIFFs'
    $upPreCFU  = Join-Path $uploadDir 'PreCFU'
    $upPost    = Join-Path $uploadDir 'PostCFU'
    foreach ($d in @($upTIFFs, $upPreCFU, $upPost)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # ---- input TIFFs ----
    # If this project came from LIF extraction (a <projectRoot>\extracted\ tree
    # exists), MIRROR that whole tree -- both UNTRIMMED and TRIMMED, under each
    # LIF's original subpath -- so input_TIFFs preserves the original LIF
    # structure. Otherwise (TIFF-start), fall back to a flat hardlink from lanes.
    $extractedDir = Join-Path $projectRoot 'extracted'
    $tiffLinked = 0; $tiffCopied = 0; $tiffSkipped = 0; $tiffFailed = 0
    if (Test-Path $extractedDir) {
        Note "Consolidating input TIFFs (mirroring LIF structure from extracted\; hardlinked)..."
        $srcTiffs = @(Get-ChildItem $extractedDir -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -notlike '._*' })
        $extractedPrefix = (Resolve-Path -LiteralPath $extractedDir).Path.TrimEnd('\') + '\'
        Note ("  Found {0} TIFFs under extracted\ (both UNTRIMMED + TRIMMED)" -f $srcTiffs.Count)
        foreach ($t in $srcTiffs) {
            $rel  = $t.FullName.Substring($extractedPrefix.Length)   # e.g. Inhibitory\LIF1\TRIMMED\s3_20Hz.tif
            $dest = Join-Path $upTIFFs $rel
            if (Test-Path $dest) { $tiffSkipped++; continue }
            $destParent = Split-Path $dest -Parent
            if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
            try {
                New-Item -ItemType HardLink -Path $dest -Value $t.FullName -ErrorAction Stop | Out-Null
                $tiffLinked++
            } catch {
                try { Copy-Item $t.FullName $dest -Force; $tiffCopied++ }
                catch { $tiffFailed++; Warn2 ("Failed to consolidate {0}: {1}" -f $rel, $_.Exception.Message) }
            }
        }
        $subdirCount = @(Get-ChildItem $upTIFFs -Directory -ErrorAction SilentlyContinue).Count
        Note ("  input_TIFFs mirrored: hardlinked={0}, copied={1}, already present={2}, failed={3} ({4} top-level group(s))" -f $tiffLinked, $tiffCopied, $tiffSkipped, $tiffFailed, $subdirCount)
    } else {
        Note "Consolidating input TIFFs (flat hardlink from lanes; no LIF structure to preserve)..."
        $allTiffs = @()
        if (Test-Path $paths['lanes']) {
            $allTiffs += @(Get-ChildItem $paths['lanes'] -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -notlike '._*' -and $_.Directory.FullName -notmatch '\\_stalled(\\|$)' })
        }
        Note ("  Found {0} TIFFs in lane folders (excluding _stalled)" -f $allTiffs.Count)
        foreach ($t in $allTiffs) {
            $dest = Join-Path $upTIFFs $t.Name
            if (Test-Path $dest) { $tiffSkipped++; continue }
            try {
                New-Item -ItemType HardLink -Path $dest -Value $t.FullName -ErrorAction Stop | Out-Null
                $tiffLinked++
            } catch {
                try { Copy-Item $t.FullName $dest -Force; $tiffCopied++ }
                catch { $tiffFailed++; Warn2 ("Failed to consolidate {0}: {1}" -f $t.Name, $_.Exception.Message) }
            }
        }
        Note ("  Hardlinked: {0}, copied: {1}, already present: {2}, failed: {3}" -f $tiffLinked, $tiffCopied, $tiffSkipped, $tiffFailed)
    }

    # ---- PreCFU: per-stem subfolders, hardlinked. Each stem gets ALL its accessory files. ----
    # AQuA2 produces per-recording bundles:
    #   <stem>_AQuA2.mat            <- main results
    #   <stem>_AQuA2_Ch1.csv        <- channel 1 data
    #   <stem>_AQuA2_Ch1_curves.xlsx
    #   <stem>_AQuA2_Movie.tif      <- visualization movie
    #   ...possibly more
    # We hardlink ALL of them into for_upload\PreCFU\<stem>\.
    Note "Consolidating PreCFU outputs (per-stem subfolders, ALL accessory files, hardlinked)..."

    # Detect stale lane-organized layout from v0.7.0 (pre-fix) runs
    $staleSubdirs = @(Get-ChildItem $upPreCFU -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -match '_results$' -or $_.Name -match '^lane\d+$' })
    if ($staleSubdirs.Count -gt 0) {
        Warn2 ("Detected {0} stale lane-organized subfolder(s) in for_upload\PreCFU\:" -f $staleSubdirs.Count)
        foreach ($d in $staleSubdirs) { Warn2 ("    {0}" -f $d.FullName) }
        Warn2 "These are from a v0.7.0 run with broken PreCFU layout."
        Warn2 "Recommended: delete for_upload\PreCFU\ contents and re-run Consolidate."
        Warn2 "Proceeding with per-stem layout alongside (mixed structure)."
    }

    # Find ALL _AQuA2.mat files anywhere under PreCFU; route by stem
    $allMatFiles = @(Get-ChildItem $paths['PreCFU'] -Recurse -File -Filter "*_AQuA2.mat" -ErrorAction SilentlyContinue |
                     Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' })
    Note ("  Found {0} _AQuA2.mat files (stems) in source PreCFU" -f $allMatFiles.Count)

    $preLinked = 0
    $preCopied = 0
    $preSkipped = 0
    $preFiles = 0
    $stemIdx = 0
    foreach ($matFile in $allMatFiles) {
        # v0.8.2: periodic progress so a large consolidation isn't silent for minutes
        $stemIdx++
        if ($stemIdx % 100 -eq 0) { Note ("  ... {0}/{1} stems consolidated" -f $stemIdx, $allMatFiles.Count) }
        $stem = ($matFile.Name -replace '_AQuA2\.mat$','')
        $destDir = Join-Path $upPreCFU $stem
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        # Find ALL accessory files for this stem in the SAME directory as the .mat
        # Filter "<stem>*" catches: _AQuA2.mat, _AQuA2_Ch1.csv, _AQuA2_Ch1_curves.xlsx,
        # _AQuA2_Movie.tif, and any other per-recording outputs.
        # _ERROR.txt files live under _failures/ subfolders (different directory) so excluded.
        $stemFiles = @(Get-ChildItem $matFile.DirectoryName -File -Filter "$stem*" -ErrorAction SilentlyContinue)
        $preFiles += $stemFiles.Count

        foreach ($f in $stemFiles) {
            $destFile = Join-Path $destDir $f.Name
            if (Test-Path $destFile) {
                $preSkipped++
                continue
            }
            try {
                New-Item -ItemType HardLink -Path $destFile -Value $f.FullName -ErrorAction Stop | Out-Null
                $preLinked++
            } catch {
                try {
                    Copy-Item $f.FullName $destFile -Force
                    $preCopied++
                } catch {
                    Warn2 ("Failed to consolidate {0}: {1}" -f $f.Name, $_.Exception.Message)
                }
            }
        }
    }
    Note ("  PreCFU: {0} stems, {1} total files (hardlinked={2}, copied={3}, already present={4})" -f $allMatFiles.Count, $preFiles, $preLinked, $preCopied, $preSkipped)

    # ---- PostCFU: flat dir, hardlinked (one .mat per stem, no subfolders) ----
    Note "Consolidating PostCFU outputs (flat layout, hardlinked)..."
    $postMats = @(Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' })
    Note ("  Found {0} _res_cfu.mat files in source POST" -f $postMats.Count)
    $postLinked = 0
    $postCopied = 0
    $postSkipped = 0
    foreach ($m in $postMats) {
        $destFile = Join-Path $upPost $m.Name
        if (Test-Path $destFile) {
            $postSkipped++
            continue
        }
        try {
            New-Item -ItemType HardLink -Path $destFile -Value $m.FullName -ErrorAction Stop | Out-Null
            $postLinked++
        } catch {
            try {
                Copy-Item $m.FullName $destFile -Force
                $postCopied++
            } catch {
                Warn2 ("Failed to consolidate {0}: {1}" -f $m.Name, $_.Exception.Message)
            }
        }
    }
    Note ("  PostCFU: hardlinked={0}, copied={1}, already present={2}" -f $postLinked, $postCopied, $postSkipped)

    # ---- Movies: MP4 of each AQuA2 _Movie.tif overlay ----
    # AQuA2 writes a MULTI-FRAME overlay movie per recording as <stem>_AQuA2_Movie.tif.
    # ffmpeg can't read multi-page TIFF (it decodes only the first page -- verified),
    # so we go Fiji (reads the stack -> AVI via movies_to_avi.py) then ffmpeg
    # (AVI -> MP4). Optional + NON-FATAL: needs BOTH Fiji and ffmpeg; if either is
    # missing (or there are no movies), it's skipped with a warning and the run
    # still succeeds. NOTE: reading large movie TIFFs is slow -- -SkipMovies to opt out.
    $mp4Ok = 0; $mp4Fail = 0; $mp4Skip = 0; $movieCount = 0
    if (-not $SkipMovies) {
        $upMovies  = Join-Path $uploadDir 'Movies'
        $srcMovies = @(Get-ChildItem $paths['PreCFU'] -Recurse -File -Filter *_Movie.tif -ErrorAction SilentlyContinue |
                       Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' })
        $movieCount = $srcMovies.Count
        if ($movieCount -eq 0) {
            Note "Movies: no *_Movie.tif overlays found under PreCFU; nothing to convert."
        } else {
            # Resolve ffmpeg
            $ffmpegResolved = $null
            $ffCmd = Get-Command $FfmpegExe -ErrorAction SilentlyContinue
            if ($ffCmd) { $ffmpegResolved = $ffCmd.Source }
            else { foreach ($cand in @('C:\ffmpeg\bin\ffmpeg.exe', "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe", (Join-Path $env:USERPROFILE 'ffmpeg\bin\ffmpeg.exe'))) { if (Test-Path $cand) { $ffmpegResolved = $cand; break } } }
            # Resolve Fiji (may not have been resolved earlier if no extract ran this invocation)
            $fijiForMovies = if (Test-Path -LiteralPath $FijiExe) { $FijiExe } else { $null }
            if (-not $fijiForMovies) {
                foreach ($r in @('C:\Fiji','C:\Fiji.app','C:\Program Files\Fiji','C:\Program Files\Fiji.app', (Join-Path $env:USERPROFILE 'Fiji'), (Join-Path $env:USERPROFILE 'Fiji.app'), 'D:\Fiji','D:\Fiji.app')) {
                    foreach ($exe in 'fiji-windows-x64.exe','ImageJ-win64.exe') { $p = Join-Path $r $exe; if (Test-Path $p) { $fijiForMovies = $p; break } }
                    if ($fijiForMovies) { break }
                }
            }
            $moviesEngine = Join-Path (Split-Path $ScriptsDir -Parent) 'fiji-macros\movies_to_avi.py'
            if (-not $ffmpegResolved -or -not $fijiForMovies -or -not (Test-Path $moviesEngine)) {
                Warn2 ("Movies: skipping {0} movie(s) -- need Fiji AND ffmpeg (Fiji found={1}, ffmpeg found={2}, engine present={3}). Install via setup\Install-Dependencies.ps1 then re-run -Consolidate. (non-fatal)" -f $movieCount, [bool]$fijiForMovies, [bool]$ffmpegResolved, (Test-Path $moviesEngine))
            } else {
                if (-not (Test-Path $upMovies)) { New-Item -ItemType Directory -Path $upMovies -Force | Out-Null }
                $aviDir = Join-Path $projectRoot '_movies_avi'
                if (-not (Test-Path $aviDir)) { New-Item -ItemType Directory -Path $aviDir -Force | Out-Null }
                Note ("Movies: {0} *_Movie.tif -> AVI (Fiji, {1}) -> MP4 (ffmpeg). Reading big movie TIFFs is slow." -f $movieCount, $fijiForMovies)

                # 1) Fiji: multi-frame TIFF stacks -> AVI (one headless invocation for all)
                $moviesLog = Join-Path $runAuditDir 'movies_to_avi.log'
                $moviesCfg = Join-Path $runAuditDir 'movies_to_avi.cfg'
                @("input_root=$($paths['PreCFU'])", "output_dir=$aviDir", "fps=$MovieFps",
                  "compression=$MovieAviCompression", "log=$moviesLog") |
                    Set-Content -Path $moviesCfg -Encoding ASCII
                $env:MOVIES_CONFIG = $moviesCfg
                try {
                    $mvErr = Join-Path $runAuditDir 'movies_fiji_stderr.log'
                    $mvOut = Join-Path $runAuditDir 'movies_fiji_stdout.log'
                    # ArgumentList as an ARRAY (see the extract launch above): a
                    # single joined string makes the launcher reject --run.
                    Start-Process -FilePath $fijiForMovies -ArgumentList '--headless','--run',$moviesEngine `
                        -Wait -NoNewWindow -RedirectStandardOutput $mvOut -RedirectStandardError $mvErr | Out-Null
                } finally { Remove-Item Env:\MOVIES_CONFIG -ErrorAction SilentlyContinue }
                $avis = @(Get-ChildItem $aviDir -File -Filter *.avi -ErrorAction SilentlyContinue)
                Note ("  Fiji produced {0} AVI(s) (log: {1})" -f $avis.Count, $moviesLog)

                # 2) ffmpeg: AVI -> MP4 (the only lossy step). -MovieLossless =
                # mathematically lossless (qp 0, yuv444p, no chroma subsampling);
                # otherwise CRF-based high quality with universally-playable yuv420p.
                if ($MovieLossless) {
                    $ffQualArgs = @('-c:v','libx264','-preset','veryslow','-qp','0','-pix_fmt','yuv444p')
                    Note ("  ffmpeg: lossless (qp 0, yuv444p) -- larger files, limited player support")
                } else {
                    $ffQualArgs = @('-c:v','libx264','-preset','slow','-crf',"$MovieCrf",'-pix_fmt','yuv420p')
                    Note ("  ffmpeg: CRF {0} (yuv420p); lower CRF = higher fidelity. -MovieLossless for exact." -f $MovieCrf)
                }
                $movieErrLog = Join-Path $runAuditDir 'movies_ffmpeg_errors.log'
                if (Test-Path $movieErrLog) { Remove-Item $movieErrLog -Force -ErrorAction SilentlyContinue }
                foreach ($avi in $avis) {
                    $mp4 = Join-Path $upMovies ($avi.BaseName + '.mp4')
                    if (Test-Path $mp4) { $mp4Skip++; continue }
                    & $ffmpegResolved -y -loglevel error -i $avi.FullName @ffQualArgs `
                        -movflags +faststart -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" $mp4 2>> $movieErrLog
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $mp4) -and (Get-Item $mp4).Length -gt 0) { $mp4Ok++ }
                    else {
                        $mp4Fail++
                        $errTail = if (Test-Path $movieErrLog) { Get-Content $movieErrLog -Tail 1 } else { '' }
                        Warn2 ("  Movie FAILED: {0} (exit {1}) {2}" -f $avi.Name, $LASTEXITCODE, $errTail)
                        if (Test-Path $mp4) { Remove-Item $mp4 -Force -ErrorAction SilentlyContinue }
                    }
                }
                Remove-Item $aviDir -Recurse -Force -ErrorAction SilentlyContinue   # tidy AVI intermediates
                Note ("  Movies: {0} MP4 created, {1} failed, {2} already present -> {3}" -f $mp4Ok, $mp4Fail, $mp4Skip, $upMovies)
                if ($avis.Count -eq 0)  { Warn2 ("  Fiji produced no AVIs -- check {0} and {1}" -f $moviesLog, $mvErr) }
                if ($mp4Fail -gt 0)     { Warn2 ("  {0} movie(s) failed ffmpeg; see {1}" -f $mp4Fail, $movieErrLog) }
            }
        }
    } else {
        Note "Movies: skipped (-SkipMovies)."
    }

    $finalTiffs   = (Get-ChildItem $upTIFFs  -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue).Count
    $finalPreCFU  = (Get-ChildItem $upPreCFU -Recurse -Filter "*_AQuA2.mat" -File).Count
    $finalPostCFU = (Get-ChildItem $upPost   -File -Filter "*_res_cfu.mat").Count
    $finalMovies  = if (Test-Path (Join-Path $uploadDir 'Movies')) { (Get-ChildItem (Join-Path $uploadDir 'Movies') -File -Filter *.mp4 -ErrorAction SilentlyContinue).Count } else { 0 }

    # Drop the exact parameters CSV used into the upload folder, named with the
    # project, so provenance travels with the data (uploaded to S3) -- this is the
    # durable record of "what params produced this run", independent of any git
    # preset. Copy (not hardlink) so it survives cleanup. Bulletproof: if the
    # detection-time archive is missing (e.g. a run that skipped Detect), fall back
    # to the resolved config CSV, then the active default -- so the params CSV is
    # ALWAYS present in for_upload whenever one exists on the box.
    $csvDest = Join-Path $uploadDir ("{0}_parameters_for_batch_USED.csv" -f $ProjectName)
    $paramsSrc = @(
        (Join-Path $runAuditDir 'parameters_for_batch_USED.csv'),
        $script:resolvedConfigCSV,
        'C:\AQuA2\cfg\parameters_for_batch.csv'
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($paramsSrc) {
        Copy-Item $paramsSrc $csvDest -Force
        Note ("  Parameters CSV copied to {0}  (from {1})" -f (Split-Path $csvDest -Leaf), $paramsSrc)
    } else {
        Warn2 "No parameters_for_batch.csv found to include in for_upload (checked audit dir, resolved config, and C:\AQuA2\cfg\)."
    }
    # Also drop the human-readable run summary alongside, if present
    $runSummary = Join-Path $runAuditDir 'RUN_SUMMARY.md'
    if (Test-Path $runSummary) { Copy-Item $runSummary (Join-Path $uploadDir 'RUN_SUMMARY.md') -Force }

    PhaseEnd 4 "Consolidate" $start ("for_upload/: {0} TIFFs, {1} PreCFU .mat, {2} PostCFU .mat, {3} movies" -f $finalTiffs, $finalPreCFU, $finalPostCFU, $finalMovies)

    # ------------------------------------------------------------------
    # v0.8 OPTIONAL CLEANUP (-Cleanup, default OFF; destructive, gated)
    # Removes intermediate working dirs (lanes/, CFU_lanes/, PreCFU/, POST/)
    # and renames for_upload/ -> <ProjectName>_AQuA2/ so the user is left with a
    # single, self-contained, S3-ready folder. Only runs if the consolidated
    # output is VERIFIED complete first -- never delete sources on faith.
    # ------------------------------------------------------------------
    if ($Cleanup) {
        Note ""
        Note "[CLEANUP] Verifying consolidated output before removing intermediates..."

        # Real (non-._) source counts to verify against
        $srcRealTiffs = @(Get-ChildItem $paths['lanes'] -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -notlike '._*' -and $_.Directory.FullName -notmatch '\\_stalled(\\|$)' }).Count
        $srcPreCFU    = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter "*_AQuA2.mat" -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' }).Count
        $srcPostCFU   = (Get-ChildItem $paths['POST'] -Recurse -Filter "*_res_cfu.mat" -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.DirectoryName -notmatch '\\_failures(\\|$)' }).Count

        $okTiff = ($finalTiffs  -ge $srcRealTiffs)
        $okPre  = ($finalPreCFU -ge $srcPreCFU)
        $okPost = ($finalPostCFU -ge $srcPostCFU)

        if ($okTiff -and $okPre -and $okPost) {
            Note ("  Verified: TIFFs {0}/{1}, PreCFU {2}/{3}, PostCFU {4}/{5}. Safe to clean up." -f `
                  $finalTiffs, $srcRealTiffs, $finalPreCFU, $srcPreCFU, $finalPostCFU, $srcPostCFU)

            # Junction-aware removal helper: CFU_lanes contains directory junctions whose
            # targets are the real PreCFU result folders. Recursing INTO a junction would
            # delete the real data. Remove the reparse-point link itself, not its target.
            function Remove-DirSafe([string]$Dir) {
                if (-not (Test-Path $Dir)) { return }
                Get-ChildItem $Dir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        # junction: delete the link without following it (rmdir, no /s)
                        cmd /c rmdir "$($_.FullName)" 2>$null
                    }
                }
                Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Order matters: remove CFU_lanes (junctions) BEFORE PreCFU (their targets)
            foreach ($d in @('CFU_lanes','lanes','PreCFU','POST')) {
                $target = $paths[$d]
                if ($target -and (Test-Path $target)) {
                    Note ("  Removing intermediate: {0}" -f $target)
                    Remove-DirSafe $target
                }
            }

            # Rename for_upload -> <ProjectName>_AQuA2 (the single deliverable folder)
            $finalDir = Join-Path $OutputRoot ("{0}_AQuA2" -f $ProjectName)
            if (Test-Path $finalDir) {
                Warn2 ("  Target {0} already exists; leaving for_upload/ in place (manual merge needed)." -f $finalDir)
            } else {
                try {
                    Move-Item $uploadDir $finalDir -Force
                    Note ("  Final deliverable: {0}" -f $finalDir)
                    Note "  Contains: input_TIFFs/ (LIF structure), PreCFU/, PostCFU/, Movies/, parameters CSV, RUN_SUMMARY.md"
                } catch {
                    Warn2 ("  Could not rename for_upload/ -> {0}: {1}" -f $finalDir, $_.Exception.Message)
                }
            }
        } else {
            Err2 ("[CLEANUP] ABORTED -- consolidated counts do not match sources (TIFFs {0}/{1}, PreCFU {2}/{3}, PostCFU {4}/{5}). Nothing deleted; intermediates preserved for inspection." -f `
                  $finalTiffs, $srcRealTiffs, $finalPreCFU, $srcPreCFU, $finalPostCFU, $srcPostCFU)
        }
    }

    # Phase-complete markers (dual-write)
    $consolidateMarker = @"
Consolidate phase completed at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Upload-ready directory:  $uploadDir
input_TIFFs/ count:      $finalTiffs (hardlinked=$tiffLinked, copied=$tiffCopied)
PreCFU/ .mat count:      $finalPreCFU (hardlinked=$preLinked, copied=$preCopied)
PostCFU/ .mat count:     $finalPostCFU (hardlinked=$postLinked, copied=$postCopied)
Movies/ .mp4 count:      $finalMovies (converted=$mp4Ok, failed=$mp4Fail, from $movieCount _Movie.tif)
Run audit dir:           $runAuditDir
"@
    $consolidateMarker | Out-File $markerConsolidate -Encoding UTF8
    $consolidateMarker | Out-File (Join-Path $runAuditDir 'PHASE_consolidate_COMPLETE.txt') -Encoding UTF8
}

# ==========================================================
# Phase 5: S3 upload
# ==========================================================
if ($Upload -and $detectionIncomplete) {
    # v0.8.1: never publish a partial dataset to S3.
    Phase 5 ("S3 upload to {0}" -f $S3Prefix)
    Err2 "Skipping S3 upload: detection did not complete for all real inputs this run; refusing to publish a partial dataset to S3."
    Err2 "Fix the offending input(s), re-run -Detect, then re-run with -Upload."
}
elseif ($Upload) {
    if (-not $S3Prefix) {
        Err2 "Upload enabled but -S3Prefix not specified. Skipping upload."
    } else {
        Phase 5 ("S3 upload to {0}" -f $S3Prefix)
        $start = Get-Date

        # Source: prefer for_upload/ if it exists (consolidated), else fall back to project root
        $uploadSource = if (Test-Path $paths['for_upload']) { $paths['for_upload'] } else { $projectRoot }
        Note ("Upload source:   {0}" -f $uploadSource)
        Note ("Upload target:   {0}" -f $S3Prefix)

        Note "Running dry-run first..."
        $dry = & aws s3 sync $uploadSource $S3Prefix --dryrun 2>&1
        $dryCount = ($dry | Where-Object { $_ -match '^\(dryrun\) upload' }).Count
        Note ("Dry-run: {0} files would be uploaded." -f $dryCount)

        Note "Proceeding with real upload..."
        # v0.8.1: Tee the real sync output so we both stream it live AND count the
        # files actually uploaded (lines start with "upload:"; dry-run lines start
        # with "(dryrun) upload:"). Previously the dry-run prediction was reported
        # as the result, which was wrong if anything changed between the two calls.
        & aws s3 sync $uploadSource $S3Prefix 2>&1 | Tee-Object -Variable realSync
        $uploadedCount = (@($realSync) | Where-Object { $_ -match '^upload:' }).Count
        PhaseEnd 5 "S3 upload" $start ("Files uploaded: $uploadedCount (dry-run predicted $dryCount)")

        $uploadMarker = @"
Upload phase completed at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
Source:        $uploadSource
Destination:   $S3Prefix
Files uploaded: $uploadedCount (dry-run predicted $dryCount)
Run audit dir: $runAuditDir
"@
        $uploadMarker | Out-File $markerUpload -Encoding UTF8
        $uploadMarker | Out-File (Join-Path $runAuditDir 'PHASE_upload_COMPLETE.txt') -Encoding UTF8
    }
}

# ==========================================================
# Final summary
# ==========================================================
$completedAt = Get-Date
$total = $completedAt - $pipelineStart

# Collect counts for audit
$counts = @{
    input_count    = $inputCount
    detection_ok   = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter '*_AQuA2.mat' -File -ErrorAction SilentlyContinue).Count
    detection_fail = (Get-ChildItem $paths['PreCFU'] -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue).Count
    cfu_ok         = (Get-ChildItem $paths['POST']   -Recurse -Filter '*_res_cfu.mat' -File -ErrorAction SilentlyContinue).Count
    cfu_fail       = (Get-ChildItem $paths['POST']   -Recurse -Filter '*_ERROR.txt' -File -ErrorAction SilentlyContinue).Count
}

# Collect stalled files (quarantined detection TIFFs + CFU stall markers)
$stalledTIFFs   = @(Get-ChildItem $paths['lanes']     -Recurse -File -Include *.tif,*.tiff -ErrorAction SilentlyContinue |
                    Where-Object { $_.Directory.FullName -match '\\_stalled(\\|$)' })
$stalledCFU     = @(Get-ChildItem $paths['CFU_lanes'] -Recurse -File -Filter "_STALLED_*.txt" -ErrorAction SilentlyContinue)

# v0.8.3: assemble an explicit issues list so problems surface instead of hiding in the counts.
$issues = New-Object System.Collections.Generic.List[string]
if ($detectionIncomplete) { [void]$issues.Add("Detection did NOT complete for all real inputs this run (CFU/Consolidate/Upload were gated off).") }
if ($Detect -and $inputCount -gt 0 -and $counts['detection_ok'] -lt $inputCount) {
    [void]$issues.Add(("Detection produced {0} _AQuA2.mat for {1} input TIFFs ({2} missing)." -f $counts['detection_ok'], $inputCount, ($inputCount - $counts['detection_ok'])))
}
if ($CFU -and $counts['detection_ok'] -gt 0 -and $counts['cfu_ok'] -lt $counts['detection_ok']) {
    [void]$issues.Add(("CFU produced {0} _res_cfu.mat for {1} detection outputs ({2} missing)." -f $counts['cfu_ok'], $counts['detection_ok'], ($counts['detection_ok'] - $counts['cfu_ok'])))
}
if ($counts['detection_fail'] -gt 0) { [void]$issues.Add(("{0} detection per-file failure(s) -- see failures_summary_detection.md." -f $counts['detection_fail'])) }
if ($counts['cfu_fail'] -gt 0)       { [void]$issues.Add(("{0} CFU per-file failure(s) -- see failures_summary_cfu.md." -f $counts['cfu_fail'])) }
if ($stalledTIFFs.Count -gt 0) { [void]$issues.Add(("{0} detection file(s) quarantined to _stalled\ by stall auto-skip." -f $stalledTIFFs.Count)) }
if ($stalledCFU.Count -gt 0)   { [void]$issues.Add(("{0} CFU stall marker(s) (_STALLED_*.txt) under CFU_lanes\." -f $stalledCFU.Count)) }
$errWithContent = @()
$errWithContent += @(Get-ChildItem (Join-Path $paths['PreCFU'] '_lane_logs') -Filter *.err -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
$errWithContent += @(Get-ChildItem (Join-Path $paths['CFU_lanes'] '_logs') -Filter *.err -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
if ($errWithContent.Count -gt 0) { [void]$issues.Add(("{0} lane .err file(s) have content (a worker may have failed at startup) -- inspect them." -f $errWithContent.Count)) }
$issues = @($issues)

# Write machine-readable + human-readable summaries
Hdr "Writing audit trail"
Write-RunManifest -Started $pipelineStart -Completed $completedAt -Counts $counts
Write-RunSummary  -Started $pipelineStart -Completed $completedAt -Counts $counts -Issues $issues

Hdr "PIPELINE COMPLETE"
Note ("Total wall-clock:   {0:hh\:mm\:ss}" -f $total)
Note ("Project:            {0}" -f $ProjectName)
Note ("Project root:       {0}" -f $projectRoot)
Note ("  Detection (.mat): {0} files" -f $counts['detection_ok'])
Note ("  CFU (_res_cfu):   {0} files" -f $counts['cfu_ok'])
if ($Consolidate -and (Test-Path $paths['for_upload'])) {
    $upTiffCount = (Get-ChildItem (Join-Path $paths['for_upload'] 'input_TIFFs') -File -ErrorAction SilentlyContinue).Count
    $upPostCount = (Get-ChildItem (Join-Path $paths['for_upload'] 'PostCFU') -File -Filter "*_res_cfu.mat" -ErrorAction SilentlyContinue).Count
    Note ("  for_upload:       {0} TIFFs, {1} PostCFU .mat (ready for S3)" -f $upTiffCount, $upPostCount)
}
Note ("Master log:         {0}" -f $masterLog)

# ===== Issues summary: explicit, so problems don't hide in the counts (v0.8.3) =====
Write-Host ""
if ($issues.Count -gt 0) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host (" ISSUES DETECTED ({0})" -f $issues.Count) -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    foreach ($it in $issues) { Write-Host ("  - {0}" -f $it) -ForegroundColor Red }
    Write-Host ""
    Write-Host ("  Full triage: .\Get-PipelineStatus.ps1 -ProjectRoot `"{0}`"" -f $projectRoot) -ForegroundColor Yellow
} else {
    Write-Host "[OK] No issues detected -- every phase that ran produced the expected outputs." -ForegroundColor Green
}

# ===== Stalled files: PROMINENT visual indication =====
if ($stalledTIFFs.Count -gt 0 -or $stalledCFU.Count -gt 0) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host (" STALLED FILES ATTENTION REQUIRED") -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    if ($stalledTIFFs.Count -gt 0) {
        Write-Host ("  Detection stalled and skipped {0} file(s):" -f $stalledTIFFs.Count) -ForegroundColor Yellow
        foreach ($s in $stalledTIFFs) {
            Write-Host ("    - {0}" -f $s.FullName) -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  These files were moved to a _stalled subfolder so the lane could continue."
        Write-Host "  They will NOT appear in detection outputs, PreCFU, PostCFU, or for_upload/."
        Write-Host "  Inspect, run individually with relaxed parameters, or accept them as known-bad."
    }
    if ($stalledCFU.Count -gt 0) {
        Write-Host ""
        Write-Host ("  CFU stall markers ({0}):" -f $stalledCFU.Count) -ForegroundColor Yellow
        foreach ($s in $stalledCFU) {
            Write-Host ("    - {0}" -f $s.FullName) -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host ("  Full stall log: {0}" -f (Join-Path $runAuditDir 'stall_log.txt')) -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
}

Write-Host ""
Note "Audit trail saved to $runAuditDir"
Note "  - RUN_SUMMARY.md                 (human-readable)"
Note "  - run_manifest.json              (machine-readable)"
Note "  - parameters_for_batch_USED.csv  (detection parameter CSV in effect)"
if ($CFU) {
    Note "  - cfu_parameters_BAKED.txt       (CFU thresholds compiled into cfu_lane.exe)"
    Note "  - per_file_status_cfu.csv        (CFU file-by-file)"
}
if ($Detect) {
    Note "  - per_file_status_detection.csv  (detection file-by-file)"
}
if ($stalledTIFFs.Count -gt 0 -or $stalledCFU.Count -gt 0) {
    Note "  - stall_log.txt                  (stall events for this run)"
}
if ($counts['detection_fail'] -gt 0 -or $counts['cfu_fail'] -gt 0) {
    Note "  - failures_summary_*.md          (consolidated error reports)"
    Note "  - failures/                       (copies of per-file _ERROR.txt)"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
if ($Detect -and -not $CFU) {
    Write-Host "  1. Verify detection looks right:"
    Write-Host ("       Get-ChildItem {0} -Recurse -Filter '*_AQuA2.mat' | Measure-Object" -f $paths['PreCFU'])
    Write-Host ("       Check {0}\<lane>\_failures\ if any" -f $paths['lanes'])
    Write-Host ""
    Write-Host "  2. When ready for CFU:"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -ProjectName {1} -Split `$false -Detect `$false -CFU `$true" -f $OutputRoot, $ProjectName)
    Write-Host ""
}
if ($CFU -and -not $Upload -and -not $Consolidate) {
    Write-Host "  1. R analysis:"
    Write-Host "       Open r\AQuA2_CFU_pipeline_v4_27_FOXP1_WT_HET.R in RStudio."
    Write-Host "       Edit frame_interval, filename regex, scope filters (docs/08_OPERATIONS_PLAYBOOK.md sec 1.4)."
    Write-Host "       Run; check pairing_and_parse_audit.csv before trusting results."
    Write-Host ""
    Write-Host "  2. Consolidate outputs into flat structure for S3:"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -ProjectName {1} -Split `$false -Detect `$false -CFU `$false -Consolidate `$true" -f $OutputRoot, $ProjectName)
    Write-Host ""
    Write-Host "  3. Or consolidate+upload in one go:"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -ProjectName {1} -Split `$false -Detect `$false -CFU `$false -Upload `$true -S3Prefix s3://..." -f $OutputRoot, $ProjectName)
    Write-Host ""
}
if ($Consolidate -and -not $Upload) {
    Write-Host "  Consolidated outputs ready at:" -ForegroundColor Green
    Write-Host ("    {0}" -f $paths['for_upload'])
    if (Test-Path (Join-Path $projectRoot 'extracted')) {
        Write-Host "      input_TIFFs/   (mirrors the original LIF tree; UNTRIMMED + TRIMMED)"
    } else {
        Write-Host "      input_TIFFs/   (flat: all source TIFFs)"
    }
    Write-Host "      PreCFU/        (per-stem subfolders with _AQuA2.mat)"
    Write-Host "      PostCFU/       (flat: one _res_cfu.mat per stem)"
    if (Test-Path (Join-Path $paths['for_upload'] 'Movies')) {
        Write-Host "      Movies/        (one .mp4 per AQuA2 _Movie.tif overlay)"
    }
    Write-Host ""
    Write-Host "  To upload to S3:"
    Write-Host ("       .\Run-Pipeline.ps1 -OutputRoot {0} -ProjectName {1} -Split `$false -Detect `$false -CFU `$false -Consolidate `$false -Upload `$true -S3Prefix s3://..." -f $OutputRoot, $ProjectName)
    Write-Host ""
}
if ($Upload) {
    Write-Host "  All phases complete. Outputs uploaded to:" -ForegroundColor Green
    Write-Host ("    {0}" -f $S3Prefix)
    Write-Host ""
    Write-Host "  (Optional) Terminate instance once you've confirmed S3 has everything."
    Write-Host "    See docs/07_TEARDOWN_CHECKLIST.md"
    Write-Host ""
}

Stop-Transcript | Out-Null
