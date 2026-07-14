<#
.SYNOPSIS
  Snapshot the current active detection-parameter CSV into the repo's named
  preset library (cfg/presets/<Name>.csv), so it can be reused with
  Run-Pipeline.ps1 -ParamPreset <Name> and shared via git.

.DESCRIPTION
  Copies -SourceCsv (default C:\AQuA2\cfg\parameters_for_batch.csv) to
  cfg/presets/<Name>.csv. Refuses to overwrite an existing preset unless -Force.
  After saving, commit it so every instance gets it on the next git pull.

.EXAMPLE
  .\Save-Preset.ps1 -Name C4
  .\Save-Preset.ps1 -Name hCO_default -SourceCsv D:\my_params.csv -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$SourceCsv = 'C:\AQuA2\cfg\parameters_for_batch.csv',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Validate the name (it becomes a filename).
if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
    Write-Error "Preset name must be letters/digits/._- only (got '$Name')."
}
if (-not (Test-Path -LiteralPath $SourceCsv)) {
    Write-Error "Source CSV not found: $SourceCsv"
}

# Sanity-check it looks like a parameters_for_batch.csv (has a Variable column
# and the key detection rows), so we don't save an unrelated file by mistake.
try {
    $rows = @(Import-Csv -LiteralPath $SourceCsv)
} catch {
    Write-Error "Source is not a readable CSV: $SourceCsv ($($_.Exception.Message))"
}
$vars = @($rows | ForEach-Object { $_.Variable } | Where-Object { $_ })
foreach ($need in 'frameRate','maxSize','spatialRes') {
    if ($vars -notcontains $need) {
        Write-Error "Source CSV doesn't look like a parameters_for_batch.csv (missing '$need' row): $SourceCsv"
    }
}

$presetDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'cfg\presets'
if (-not (Test-Path $presetDir)) { New-Item -ItemType Directory -Path $presetDir -Force | Out-Null }
$dest = Join-Path $presetDir ("{0}.csv" -f $Name)

if ((Test-Path $dest) -and -not $Force) {
    Write-Error "Preset '$Name' already exists: $dest  (pass -Force to overwrite)"
}

Copy-Item -LiteralPath $SourceCsv -Destination $dest -Force
Write-Host "Saved preset '$Name' -> $dest" -ForegroundColor Green
Write-Host ""
Write-Host "Key values (File1 column):" -ForegroundColor Cyan
foreach ($r in $rows) {
    if ($r.Variable -in 'frameRate','spatialRes','maxSize','minSize','thrARScl','sourceSensitivity','detectGlo','gloDur','smoXY','minDur') {
        Write-Host ("  {0,-20} = {1}" -f $r.Variable, $r.File1)
    }
}
Write-Host ""
Write-Host "To share it with every instance, commit it:" -ForegroundColor Yellow
Write-Host "  git add cfg/presets/$Name.csv && git commit -m `"preset: $Name`" && git push"
