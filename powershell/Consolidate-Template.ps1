<#
.SYNOPSIS
  Consolidate detection output from lane-organized layout into clean per-stem layout.

.DESCRIPTION
  Detection produces output organized by lane:
    <Src>/lane01_results/<stem1>_AQuA2.mat
    <Src>/lane01_results/<stem1>_AQuA2_Ch1.csv  ... etc.
    <Src>/lane02_results/<stem2>_AQuA2.mat
    ...

  This script flattens to per-recording layout:
    <Dest>/<stem1>_results/
      <stem1>_AQuA2.mat
      <stem1>_AQuA2_Ch1.csv
      <stem1>_AQuA2_curves.xlsx
      <stem1>_Movie.tif
    <Dest>/<stem2>_results/
      ...

  Lane wrappers are removed; each recording gets its own uniquely-named folder.
  Suitable layout for S3 upload and for R's recursive file search.

  Files are MOVED, not copied. Without -Execute, prints a plan; with -Execute,
  actually moves.

.PARAMETER Src
  Source detection-output tree (contains laneNN_results/ subfolders, and
  possibly some already-flat <stem>_results/ folders from redistribution work).

.PARAMETER Dest
  Destination for the flat per-stem layout.

.PARAMETER Execute
  Required to perform moves; otherwise dry run.

.EXAMPLE
  # Dry run
  .\Consolidate-Template.ps1 -Src C:\data\my_results -Dest C:\data\PreCFU_mydata

  # Execute
  .\Consolidate-Template.ps1 -Src C:\data\my_results -Dest C:\data\PreCFU_mydata -Execute
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Src,
  [Parameter(Mandatory)] [string]$Dest,
  [switch]$Execute
)

if (-not (Test-Path $Src)) {
  Write-Error "Src not found: $Src"
  exit 1
}

# Find all _AQuA2.mat files recursively; their stems determine destination folders
$matFiles = Get-ChildItem $Src -Recurse -Filter *_AQuA2.mat -File
if ($matFiles.Count -eq 0) {
  Write-Error "No *_AQuA2.mat files found under $Src"
  exit 1
}

Write-Host ("Found {0} recordings to consolidate" -f $matFiles.Count)

# Plan
$plan = @()
foreach ($mat in $matFiles) {
  $stem = $mat.BaseName -replace '_AQuA2$',''
  $destFolder = Join-Path $Dest ($stem + "_results")
  # find all sibling files matching this stem in the source folder
  $siblings = Get-ChildItem $mat.Directory.FullName -Filter ($stem + '*') -File
  $plan += [pscustomobject]@{
    Stem       = $stem
    Source     = $mat.Directory.FullName
    Dest       = $destFolder
    FileCount  = $siblings.Count
    TotalGB    = [math]::Round((($siblings | Measure-Object Length -Sum).Sum) / 1GB, 3)
  }
}

# Show summary
Write-Host ""
Write-Host ("Plan summary:")
Write-Host ("  Recordings:     {0}" -f $plan.Count)
Write-Host ("  Total files:    {0}" -f (($plan | Measure-Object FileCount -Sum).Sum))
Write-Host ("  Total size:     {0:N2} GB" -f (($plan | Measure-Object TotalGB -Sum).Sum))
Write-Host ""
Write-Host "First 5 entries:"
$plan | Select -First 5 | Format-Table -Auto

if (-not $Execute) {
  Write-Host ""
  Write-Host "Dry run complete. Re-run with -Execute to perform the moves."
  exit 0
}

# Execute
$null = New-Item -ItemType Directory -Path $Dest -Force
$ok = 0; $skip = 0
foreach ($p in $plan) {
  if (-not (Test-Path $p.Dest)) {
    $null = New-Item -ItemType Directory -Path $p.Dest -Force
  }
  $siblings = Get-ChildItem $p.Source -Filter ($p.Stem + '*') -File
  foreach ($f in $siblings) {
    $target = Join-Path $p.Dest $f.Name
    if (Test-Path $target) {
      $skip++
      continue
    }
    Move-Item -LiteralPath $f.FullName -Destination $target -Force
    $ok++
  }
}
Write-Host ""
Write-Host ("Moved: {0} files   Skipped (already present): {1}" -f $ok, $skip)
Write-Host "Done."
