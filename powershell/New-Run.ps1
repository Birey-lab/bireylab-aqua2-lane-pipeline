<#
.SYNOPSIS
  One-window GUI to set up a pipeline run: every option on a single screen,
  pre-filled with defaults, with a live detection-parameter preview. Build the
  equivalent Run-Pipeline.ps1 command (Preview) or launch it (Run). The run
  itself streams to THIS console so you see progress and can Ctrl+C.

.DESCRIPTION
  Interactive only (needs a desktop -- RDP is fine; not for headless/scheduled
  use, where you'd use Run-Pipeline.ps1 with flags directly).

.EXAMPLE
  .\New-Run.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$PresetDir  = Join-Path $RepoRoot 'cfg\presets'
$DefaultCsv = 'C:\AQuA2\cfg\parameters_for_batch.csv'
$RunPipe    = Join-Path $PSScriptRoot 'Run-Pipeline.ps1'

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    Write-Error "This GUI needs a Windows desktop session (WinForms). For headless use, run Run-Pipeline.ps1 with flags."
}

# --- data ---
$presets = @(Get-ChildItem $PresetDir -Filter *.csv -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
$paramChoices = @()
$paramChoices += ($presets | ForEach-Object { "preset: $_" })
$paramChoices += "current active CSV"

function Get-ParamText([string]$csvPath) {
    # Show the ENTIRE active parameter set (every row's Variable = File1 value),
    # so nothing is hidden -- the pane scrolls.
    if (-not (Test-Path $csvPath)) { return "(CSV not found: $csvPath)" }
    try { $rows = @(Import-Csv -LiteralPath $csvPath) } catch { return "(could not read CSV)" }
    $lines = @($csvPath, ("{0} parameters (File1 column):" -f @($rows | Where-Object { $_.Variable }).Count), "")
    foreach ($r in $rows) {
        if ($r.Variable) {
            $tag = if ($r.Variable -eq 'detectGlo') { if ($r.File1 -eq '1') { '   <- global signal ON' } else { '   <- global signal OFF' } } else { '' }
            $lines += ("{0,-26} = {1}{2}" -f $r.Variable, $r.File1, $tag)
        }
    }
    return ($lines -join "`r`n")
}
function Resolve-ParamCsv([string]$choice) {
    if ($choice -like 'preset: *') { return (Join-Path $PresetDir (($choice -replace '^preset: ', '') + '.csv')) }
    return $DefaultCsv
}

# ---------------------------------------------------------------------------
# Form + controls
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AQuA2 Pipeline -- set up a run'
$form.Size = New-Object System.Drawing.Size(640, 840)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Fill'
$panel.AutoScroll = $true
$form.Controls.Add($panel)

$y = 12
function Section([string]$text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = "10,$script:y"; $l.Size = '580,18'
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = [System.Drawing.Color]::MidnightBlue
    $script:panel.Controls.Add($l); $script:y += 24
}
function Field([string]$label, [System.Windows.Forms.Control]$ctrl, [int]$h = 24) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $label; $l.Location = "20,$($script:y + 3)"; $l.Size = '160,20'
    $script:panel.Controls.Add($l)
    $ctrl.Location = "185,$script:y"; if (-not $ctrl.Width -or $ctrl.Width -lt 10) { $ctrl.Size = "300,$h" }
    $script:panel.Controls.Add($ctrl)
    $script:y += ($h + 6)
    return $ctrl
}
function TextField([string]$label, [string]$default, [int]$w = 300) {
    $t = New-Object System.Windows.Forms.TextBox; $t.Text = $default; $t.Size = "$w,24"
    return (Field $label $t)
}
function TextFieldBrowse([string]$label, [string]$default) {
    # Text box + a Browse... button that opens a folder picker.
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label; $lbl.Location = "20,$($script:y + 3)"; $lbl.Size = '160,20'
    $t = New-Object System.Windows.Forms.TextBox; $t.Text = $default; $t.Size = '250,24'; $t.Location = "185,$script:y"
    $b = New-Object System.Windows.Forms.Button; $b.Text = 'Browse...'; $b.Size = '70,24'; $b.Location = "442,$($script:y - 1)"
    $b.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($t.Text -and (Test-Path $t.Text)) { $dlg.SelectedPath = $t.Text }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $t.Text = $dlg.SelectedPath }
    }.GetNewClosure())
    $script:panel.Controls.AddRange(@($lbl, $t, $b))
    $script:y += 30
    return $t
}
function Combo([string]$label, [string[]]$items, [string]$default) {
    $c = New-Object System.Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.Size = '300,24'
    foreach ($i in $items) { [void]$c.Items.Add($i) }
    if ($default -and $c.Items.Contains($default)) { $c.SelectedItem = $default } elseif ($c.Items.Count) { $c.SelectedIndex = 0 }
    return (Field $label $c)
}
function Check([string]$label, [bool]$checked) {
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $label; $cb.Checked = $checked; $cb.Size = '440,20'
    $cb.Location = "20,$script:y"; $script:panel.Controls.Add($cb); $script:y += 26
    return $cb
}

# --- Basics ---
Section 'Run'
$tbProject = TextField 'Project name *' ''
$tbOut     = TextFieldBrowse 'Output root' (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AQuA2_runs')

# --- Source ---
Section 'Source'
$cbSource  = Combo 'Start from' @('LIF (extract to TIFFs)', 'TIFFs already prepared') 'LIF (extract to TIFFs)'
$tbLif     = TextFieldBrowse 'LIF source folder' 'C:\CalciumData\lif_test'
$tbTiff    = TextFieldBrowse 'Input TIFFs folder' ''
$ckRecurse = Check 'Recurse into TIFF subfolders' $false

# --- Extraction ---
Section 'Extraction (LIF only)'
$ckUntrim  = Check 'Save a full UNTRIMMED copy of each series' $true
$cbTrim    = Combo 'Trim window' @('none', 'first (beginning)', 'middle (centered)', 'last (final)') 'last (final)'
$numAmt    = New-Object System.Windows.Forms.NumericUpDown; $numAmt.Maximum = 1000000; $numAmt.Value = 60; $numAmt.Size = '100,24'
$numAmt    = Field 'Trim amount' $numAmt
$cbUnit    = Combo 'Trim unit' @('seconds', 'frames') 'seconds'
$numStart  = New-Object System.Windows.Forms.NumericUpDown; $numStart.Maximum = 1000000; $numStart.Value = 0; $numStart.Size = '100,24'
$numStart  = Field 'First: skip N sec at start' $numStart
$cbDetectOn= Combo 'Detect on' @('auto', 'trimmed', 'untrimmed') 'auto'
$cbRate    = Combo 'Rate mismatch policy' @('warn (keep it)', 'drop (strict)') 'warn (keep it)'
$ckTile    = Check "Skip TileScan_* series (unless 'Merging')" $true

# --- Parameters ---
Section 'Detection parameters'
$cbPreset  = Combo 'Parameter set' $paramChoices ($paramChoices[-1])
$tbParams  = New-Object System.Windows.Forms.TextBox
$tbParams.Multiline = $true; $tbParams.ReadOnly = $true; $tbParams.ScrollBars = 'Vertical'
$tbParams.Font = New-Object System.Drawing.Font('Consolas', 8)
$tbParams.Location = "20,$y"; $tbParams.Size = '490,230'; $tbParams.BackColor = [System.Drawing.Color]::WhiteSmoke
$panel.Controls.Add($tbParams); $y += 238
$cbPreset.Add_SelectedIndexChanged({ $tbParams.Text = Get-ParamText (Resolve-ParamCsv $cbPreset.SelectedItem) })
$tbParams.Text = Get-ParamText (Resolve-ParamCsv $cbPreset.SelectedItem)

# --- Phases ---
Section 'Phases'
$ckDetect  = Check 'Detection' $true
$ckCFU     = Check 'CFU' $true
$ckCons    = Check 'Consolidate' $true
$ckMovies  = Check 'Make MP4 movies from overlays (needs ffmpeg)' $true

# --- Buttons ---
$btnPrev = New-Object System.Windows.Forms.Button; $btnPrev.Text = 'Preview command'; $btnPrev.Size = '140,30'; $btnPrev.Location = "20,$y"
$btnRun  = New-Object System.Windows.Forms.Button; $btnRun.Text = 'Run';  $btnRun.Size = '110,30';  $btnRun.Location = "330,$y"
$btnCan  = New-Object System.Windows.Forms.Button; $btnCan.Text = 'Cancel'; $btnCan.Size = '90,30';  $btnCan.Location = "450,$y"
$panel.Controls.AddRange(@($btnPrev, $btnRun, $btnCan))
$y += 40

# ---------------------------------------------------------------------------
# Collect -> args hashtable (shared with the post-dialog launch)
# ---------------------------------------------------------------------------
$script:runArgs = $null
function Build-Args {
    if (-not $tbProject.Text.Trim()) { [System.Windows.Forms.MessageBox]::Show('Project name is required.') | Out-Null; return $null }
    $a = [ordered]@{}
    $a.ProjectName = $tbProject.Text.Trim()
    if ($tbOut.Text.Trim()) { $a.OutputRoot = $tbOut.Text.Trim() }
    $isLif = $cbSource.SelectedItem -like 'LIF*'
    if ($isLif) {
        $a.LIFSource     = $tbLif.Text.Trim()
        $a.SaveUntrimmed = [bool]$ckUntrim.Checked
        $tm = ($cbTrim.SelectedItem -split ' ')[0]
        $a.TrimMode = $tm
        if ($tm -ne 'none') {
            $a.TrimUnit   = $cbUnit.SelectedItem
            $a.TrimAmount = [double]$numAmt.Value
            if ($tm -eq 'first') { $a.TrimStartSec = [double]$numStart.Value }
        }
        $a.DetectOn      = $cbDetectOn.SelectedItem
        $a.RatePolicy    = ($cbRate.SelectedItem -split ' ')[0]
        $a.SkipTileScans = [bool]$ckTile.Checked
    } else {
        $a.InputTIFFs = $tbTiff.Text.Trim()
        if ($ckRecurse.Checked) { $a.RecurseInput = $true }
    }
    if ($cbPreset.SelectedItem -like 'preset: *') { $a.ParamPreset = ($cbPreset.SelectedItem -replace '^preset: ', '') }
    $a.Detect      = [bool]$ckDetect.Checked
    $a.CFU         = [bool]$ckCFU.Checked
    $a.Consolidate = [bool]$ckCons.Checked
    if (-not $ckMovies.Checked) { $a.SkipMovies = $true }
    return $a
}
function Format-Command($a) {
    $switchKeys = 'RecurseInput','SkipMovies'
    $parts = @('.\Run-Pipeline.ps1')
    foreach ($k in $a.Keys) {
        $v = $a[$k]
        if ($switchKeys -contains $k) { if ($v) { $parts += "-$k" }; continue }
        if ($v -is [bool]) { $parts += "-$k `$$($v.ToString().ToLower())"; continue }
        $s = [string]$v
        if ($s -match '\s') { $parts += "-$k `"$s`"" } else { $parts += "-$k $s" }
    }
    $parts += '-Force'
    return ($parts -join ' ')
}

$btnPrev.Add_Click({
    $a = Build-Args; if (-not $a) { return }
    [System.Windows.Forms.MessageBox]::Show((Format-Command $a), 'Equivalent command') | Out-Null
})
$btnRun.Add_Click({
    $a = Build-Args; if (-not $a) { return }
    $script:runArgs = $a
    $form.Close()
})
$btnCan.Add_Click({ $script:runArgs = $null; $form.Close() })

[void]$form.ShowDialog()

# ---------------------------------------------------------------------------
# Launch in the CONSOLE (so output streams + Ctrl+C works)
# ---------------------------------------------------------------------------
if ($script:runArgs) {
    Write-Host ""
    Write-Host "Launching:" -ForegroundColor Cyan
    Write-Host ("  " + (Format-Command $script:runArgs))
    Write-Host ""
    $splat = @{}
    foreach ($k in $script:runArgs.Keys) { $splat[$k] = $script:runArgs[$k] }
    $splat['Force'] = $true
    & $RunPipe @splat
} else {
    Write-Host "Cancelled -- nothing launched." -ForegroundColor Yellow
}
