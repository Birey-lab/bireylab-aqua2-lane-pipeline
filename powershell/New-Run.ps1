<#
.SYNOPSIS
  Interactive setup for a pipeline run. Walks every decision with the default
  shown, forces you to review the detection parameters, prints the exact
  equivalent Run-Pipeline.ps1 command (so the run is reproducible), then launches
  it. Terminal-based: works over RDP and logs to the run transcript.

.DESCRIPTION
  Nothing silently defaults -- every choice is shown and accepted. At the end it
  echoes the equivalent flag command; save that to re-run non-interactively.

.EXAMPLE
  .\New-Run.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$PresetDir  = Join-Path $RepoRoot 'cfg\presets'
$DefaultCsv = 'C:\AQuA2\cfg\parameters_for_batch.csv'

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------
function Ask-Text($prompt, $default) {
    $d = if ($default) { " [$default]" } else { "" }
    $v = Read-Host ("{0}{1}" -f $prompt, $d)
    if ([string]::IsNullOrWhiteSpace($v)) { return $default } else { return $v.Trim() }
}
function Ask-YesNo($prompt, $defaultYes) {
    $d = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $v = Read-Host ("{0} {1}" -f $prompt, $d)
        if ([string]::IsNullOrWhiteSpace($v)) { return $defaultYes }
        if ($v -match '^[Yy]') { return $true }
        if ($v -match '^[Nn]') { return $false }
        Write-Host "  Please answer y or n." -ForegroundColor DarkGray
    }
}
function Ask-Choice($prompt, $choices, $default) {
    Write-Host $prompt -ForegroundColor White
    for ($i = 0; $i -lt $choices.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $choices[$i]) }
    while ($true) {
        $d = if ($default) { " (default: $default)" } else { "" }
        $v = Read-Host ("Choose 1-{0}{1}" -f $choices.Count, $d)
        if ([string]::IsNullOrWhiteSpace($v) -and $default) { return $default }
        if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le $choices.Count) { return $choices[[int]$v - 1] }
        Write-Host "  Enter a number from the list." -ForegroundColor DarkGray
    }
}
function Show-ParamValues($csvPath) {
    if (-not (Test-Path $csvPath)) { Write-Host "  (CSV not found: $csvPath)" -ForegroundColor Red; return }
    $rows = @(Import-Csv -LiteralPath $csvPath)
    $keys = 'frameRate','spatialRes','maxSize','minSize','thrARScl','sigThr','minDur','sourceSensitivity','smoXY','detectGlo','gloDur'
    Write-Host ("  {0}" -f $csvPath) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        if ($r.Variable -in $keys) {
            $flag = if ($r.Variable -eq 'detectGlo') { if ($r.File1 -eq '1') { '  <-- global signal ON' } else { '  <-- global signal OFF' } } else { '' }
            Write-Host ("    {0,-20} = {1}{2}" -f $r.Variable, $r.File1, $flag)
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " AQuA2 Pipeline -- interactive setup"           -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "(press Enter to accept the [default] shown)"    -ForegroundColor DarkGray
Write-Host ""

$runArgs = [ordered]@{}

# --- Project ---
$runArgs.ProjectName = Ask-Text "Project name (folder for this run's outputs)" ""
while (-not $runArgs.ProjectName) { $runArgs.ProjectName = Ask-Text "Project name (required)" "" }
$runArgs.OutputRoot = Ask-Text "Output root" (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AQuA2_runs')

# --- Source: LIF or TIFF ---
Write-Host ""
$src = Ask-Choice "Start from:" @('LIF files (extract to TIFFs first)', 'TIFFs already prepared') 'LIF files (extract to TIFFs first)'
if ($src -like 'LIF*') {
    $runArgs.LIFSource = Ask-Text "  LIF source folder (searched recursively for .lif)" ""
    while (-not $runArgs.LIFSource -or -not (Test-Path $runArgs.LIFSource)) {
        $runArgs.LIFSource = Ask-Text "  Folder not found -- LIF source folder" ""
    }

    Write-Host ""
    Write-Host "  Extraction options:" -ForegroundColor White
    $runArgs.SaveUntrimmed = Ask-YesNo "    Save a full UNTRIMMED copy of each series?" $true
    $trim = Ask-Choice "    Trim window:" @('none (raw only)', 'first (beginning)', 'middle (centered)', 'last (final)') 'last (final)'
    $runArgs.TrimMode = ($trim -split ' ')[0]
    if ($runArgs.TrimMode -ne 'none') {
        $runArgs.TrimUnit   = Ask-Choice "    Trim amount unit:" @('seconds', 'frames') 'seconds'
        $runArgs.TrimAmount = [double](Ask-Text ("    Keep how many {0}?" -f $runArgs.TrimUnit) '60')
        if ($runArgs.TrimMode -eq 'first') {
            $runArgs.TrimStartSec = [double](Ask-Text "    Skip how many seconds at the start first? (0 = from the very beginning)" '0')
        }
    }
    $runArgs.DetectOn      = Ask-Choice "    Run detection on which set?" @('trimmed', 'untrimmed', 'auto') 'auto'
    $rate                  = Ask-Choice "    If a series' rate differs from the first-seen:" @('warn (keep it)', 'drop (strict)') 'warn (keep it)'
    $runArgs.RatePolicy    = ($rate -split ' ')[0]
    $runArgs.SkipTileScans = Ask-YesNo "    Skip TileScan_* series (unless 'Merging')?" $true
} else {
    $runArgs.InputTIFFs   = Ask-Text "  Input TIFFs folder" ""
    $runArgs.RecurseInput = Ask-YesNo "  Recurse into subfolders for TIFFs?" $false
}

# --- Detection parameters (preset picker + forced review) ---
Write-Host ""
Write-Host "Detection parameters" -ForegroundColor White
$presets = @(Get-ChildItem $PresetDir -Filter *.csv -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
$paramCsvForReview = $DefaultCsv
if ($presets.Count -gt 0) {
    $opts = @($presets | ForEach-Object { "preset: $_" })
    $opts += "current active CSV ($DefaultCsv)"
    $pick = Ask-Choice "  Which parameter set?" $opts $opts[-1]
    if ($pick -like 'preset: *') {
        $runArgs.ParamPreset = $pick -replace '^preset: ', ''
        $paramCsvForReview = Join-Path $PresetDir ("{0}.csv" -f $runArgs.ParamPreset)
    }
} else {
    Write-Host "  (no saved presets yet -- using the current active CSV; save one later with Save-Preset.ps1)" -ForegroundColor DarkGray
}

# FORCED REVIEW: show the values and require an explicit confirmation.
while ($true) {
    Write-Host ""
    Write-Host "  Review these detection parameters:" -ForegroundColor Yellow
    Show-ParamValues $paramCsvForReview
    Write-Host ""
    $ok = Ask-Choice "  Are these correct?" @('yes -- use them', 'no -- abort so I can edit the CSV/preset') 'yes -- use them'
    if ($ok -like 'yes*') { break }
    Write-Host "Aborted so you can edit the parameters. Re-run New-Run.ps1 when ready." -ForegroundColor Yellow
    return
}

# --- Phases ---
Write-Host ""
$full = Ask-YesNo "Run the full pipeline (Detect -> CFU -> Consolidate)?" $true
if (-not $full) {
    $runArgs.Detect      = Ask-YesNo "  Run Detection?"   $true
    $runArgs.CFU         = Ask-YesNo "  Run CFU?"         $true
    $runArgs.Consolidate = Ask-YesNo "  Run Consolidate?" $true
}
$runArgs.SkipMovies = -not (Ask-YesNo "Make MP4 movies from the AQuA2 overlays (needs ffmpeg)?" $true)

# --- Build + echo the equivalent command ---
function Format-Arg($k, $v) {
    if ($v -is [bool]) { return "-$k `$$($v.ToString().ToLower())" }
    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v) { return "-$k" } else { return "" } }
    $s = [string]$v
    if ($s -match '\s') { return "-$k `"$s`"" } else { return "-$k $s" }
}
# SkipMovies/RecurseInput are switches: only emit when true.
$switchKeys = 'SkipMovies','RecurseInput'
$parts = @('.\Run-Pipeline.ps1')
foreach ($k in $runArgs.Keys) {
    $v = $runArgs[$k]
    if ($switchKeys -contains $k) { if ($v) { $parts += "-$k" }; continue }
    $parts += (Format-Arg $k $v)
}
$parts += '-Force'
$cmd = ($parts | Where-Object { $_ }) -join ' '

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Equivalent command (save this to reproduce):" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  $cmd"
Write-Host ""

if (-not (Ask-YesNo "Launch it now?" $true)) {
    Write-Host "Not launched. Copy the command above to run it whenever you're ready." -ForegroundColor Yellow
    return
}

# --- Launch (splat), converting switch keys to real switches ---
$splat = @{}
foreach ($k in $runArgs.Keys) {
    if ($switchKeys -contains $k) { if ($runArgs[$k]) { $splat[$k] = $true } }
    else { $splat[$k] = $runArgs[$k] }
}
$splat['Force'] = $true
& (Join-Path $PSScriptRoot 'Run-Pipeline.ps1') @splat
