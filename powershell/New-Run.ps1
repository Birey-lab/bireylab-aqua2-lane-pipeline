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
Section 'Trim / prep  (LIF always; TIFFs when a trim mode is chosen. Rate + TileScan = LIF only)'
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

# --- Parameters (editable) ---
# Model of the loaded CSV kept as RAW lines so we only ever change the File1 cell
# (never reformat the file the MATLAB workers read). Grid edits map back by Variable.
$script:paramRaw = @(); $script:paramVarIdx = -1; $script:paramF1Idx = -1; $script:loadedMap = @{}
function Load-ParamModel([string]$csvPath) {
    if (-not (Test-Path $csvPath)) { $script:paramRaw = @(); return @() }
    $script:paramRaw = @(Get-Content -LiteralPath $csvPath)
    $cols = $script:paramRaw[0].Split(',')
    $script:paramVarIdx = [array]::IndexOf($cols, 'Variable')
    $script:paramF1Idx  = [array]::IndexOf($cols, 'File1')
    $rows = @(); $script:loadedMap = @{}
    for ($i = 1; $i -lt $script:paramRaw.Count; $i++) {
        $c = $script:paramRaw[$i].Split(',')
        if ($script:paramVarIdx -lt 0 -or $c.Count -le $script:paramF1Idx) { continue }
        $v = $c[$script:paramVarIdx]; if (-not $v) { continue }
        $rows += , @($v, $c[$script:paramF1Idx]); $script:loadedMap[$v] = $c[$script:paramF1Idx]
    }
    return $rows
}
function Get-GridMap($g) {
    $m = @{}; foreach ($r in $g.Rows) { if (-not $r.IsNewRow) { $m[[string]$r.Cells[0].Value] = [string]$r.Cells[1].Value } }; return $m
}
function Grid-Edited($g) {
    $m = Get-GridMap $g; foreach ($k in $m.Keys) { if ("$($script:loadedMap[$k])" -ne "$($m[$k])") { return $true } }; return $false
}
function Write-ParamCsv($g, [string]$destPath) {
    $m = Get-GridMap $g; $out = @($script:paramRaw[0])
    for ($i = 1; $i -lt $script:paramRaw.Count; $i++) {
        $c = $script:paramRaw[$i].Split(',')
        if ($script:paramVarIdx -ge 0 -and $c.Count -gt $script:paramF1Idx -and $m.ContainsKey($c[$script:paramVarIdx])) {
            $c[$script:paramF1Idx] = $m[$c[$script:paramVarIdx]]; $out += ($c -join ',')
        } else { $out += $script:paramRaw[$i] }
    }
    Set-Content -LiteralPath $destPath -Value $out -Encoding ASCII
}

Section 'Detection parameters  (edit any Value, then "Save as preset" to name + keep it)'
$cbPreset = Combo 'Load parameter set' $paramChoices ($paramChoices[-1])
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = "20,$y"; $grid.Size = '490,230'
$grid.AllowUserToAddRows = $false; $grid.RowHeadersVisible = $false; $grid.AllowUserToResizeRows = $false
$grid.ColumnCount = 2
$grid.Columns[0].Name = 'Parameter'; $grid.Columns[0].ReadOnly = $true; $grid.Columns[0].Width = 300
$grid.Columns[1].Name = 'Value'; $grid.Columns[1].Width = 165
$panel.Controls.Add($grid); $y += 238
function Reload-Grid {
    $grid.Rows.Clear()
    foreach ($r in (Load-ParamModel (Resolve-ParamCsv $cbPreset.SelectedItem))) { [void]$grid.Rows.Add($r[0], $r[1]) }
}
$cbPreset.Add_SelectedIndexChanged({ Reload-Grid })
Reload-Grid

$btnSaveP = New-Object System.Windows.Forms.Button; $btnSaveP.Text = 'Save as preset...'; $btnSaveP.Size = '150,26'; $btnSaveP.Location = "20,$y"
$panel.Controls.Add($btnSaveP); $y += 34
$btnSaveP.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Save these parameters as a preset named:', 'Save preset', '')
    if (-not $name) { return }
    if ($name -notmatch '^[A-Za-z0-9._-]+$') { [void][System.Windows.Forms.MessageBox]::Show('Name: letters/digits/._- only.'); return }
    $dest = Join-Path $PresetDir ($name + '.csv')
    if ((Test-Path $dest) -and ([System.Windows.Forms.MessageBox]::Show("Preset '$name' exists. Overwrite?", 'Confirm', 'YesNo') -ne 'Yes')) { return }
    if (-not (Test-Path $PresetDir)) { New-Item -ItemType Directory -Path $PresetDir -Force | Out-Null }
    Write-ParamCsv $grid $dest
    if (-not $cbPreset.Items.Contains("preset: $name")) { [void]$cbPreset.Items.Insert(0, "preset: $name") }
    $cbPreset.SelectedItem = "preset: $name"   # reloads grid from the saved file -> edits cleared
    [void][System.Windows.Forms.MessageBox]::Show("Saved preset '$name' on this instance -- pick it from the dropdown to reuse it.`r`n`r`nThe exact parameters you actually run with are written into the run's output folder (for_upload, uploaded to S3), so the provenance always travels with the data -- you do NOT need to commit anything to git.")
}.GetNewClosure())

# --- Phases ---
Section 'Phases'
$ckDetect  = Check 'Detection' $true
$ckCFU     = Check 'CFU' $true
$ckCons    = Check 'Consolidate' $true
$ckMovies  = Check 'Make MP4 movies from overlays (needs ffmpeg)' $true

# --- Buttons (fixed bottom bar, always visible above the scrolling panel) ---
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 46
$form.Controls.Add($bottom)
$form.Controls.SetChildIndex($bottom, 0)   # keep the scroll panel filling above it
$btnPrev = New-Object System.Windows.Forms.Button; $btnPrev.Text = 'Preview command'; $btnPrev.Size = '150,30'; $btnPrev.Location = '14,8'
$btnRun  = New-Object System.Windows.Forms.Button; $btnRun.Text = 'Run';    $btnRun.Size = '110,30'; $btnRun.Location = '360,8'
$btnCan  = New-Object System.Windows.Forms.Button; $btnCan.Text = 'Cancel'; $btnCan.Size = '90,30';  $btnCan.Location = '480,8'
$bottom.Controls.AddRange(@($btnPrev, $btnRun, $btnCan))

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
    $tm = ($cbTrim.SelectedItem -split ' ')[0]
    if ($isLif) { $a.LIFSource = $tbLif.Text.Trim() } else { $a.InputTIFFs = $tbTiff.Text.Trim(); if ($ckRecurse.Checked) { $a.RecurseInput = $true } }
    # Trim/prep settings apply to BOTH sources. For TIFFs, they only take effect
    # (Phase 0 runs) when a trim mode is chosen; for LIF, extraction always runs.
    if ($isLif -or $tm -ne 'none') {
        $a.SaveUntrimmed = [bool]$ckUntrim.Checked
        $a.TrimMode = $tm
        if ($tm -ne 'none') {
            $a.TrimUnit   = $cbUnit.SelectedItem
            $a.TrimAmount = [double]$numAmt.Value
            if ($tm -eq 'first') { $a.TrimStartSec = [double]$numStart.Value }
        }
        $a.DetectOn = $cbDetectOn.SelectedItem
        if ($isLif) {   # rate policy + TileScan filter are LIF-only
            $a.RatePolicy    = ($cbRate.SelectedItem -split ' ')[0]
            $a.SkipTileScans = [bool]$ckTile.Checked
        }
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
    if (Grid-Edited $grid) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "You've edited detection parameters but haven't saved them.`r`n`r`nClick 'Save as preset...' first so the run uses a named, reproducible set.",
            'Save your parameter edits')
        return
    }
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
