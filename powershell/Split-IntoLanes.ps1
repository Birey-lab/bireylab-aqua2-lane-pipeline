<#
.SYNOPSIS
  Split a folder of TIFFs into N size-balanced "lane" subfolders for parallel processing.

.DESCRIPTION
  Greedy bin-packing by file size: sorts TIFFs largest-first, then places each
  into the currently-smallest lane folder. Result is N lanes with roughly equal
  total bytes (not necessarily equal file count, since file sizes vary).

  Without -Execute, performs a dry run showing what WOULD happen.
  With    -Execute, actually moves files.

.PARAMETER Source
  Folder containing TIFF files (non-recursive — files must be directly inside).

.PARAMETER LaneRoot
  Destination folder; will contain lane01/, lane02/, ..., laneNN/ subfolders.

.PARAMETER Lanes
  Number of lanes to create. Typical values: 8, 16, 24, 32.

.PARAMETER Execute
  Without this flag, the script prints a plan but moves nothing.
  With this flag, files are moved.

.EXAMPLE
  # Dry run
  .\Split-IntoLanes.ps1 -Source C:\data\my_tiffs -LaneRoot C:\data\my_lanes -Lanes 32

  # Actually move them
  .\Split-IntoLanes.ps1 -Source C:\data\my_tiffs -LaneRoot C:\data\my_lanes -Lanes 32 -Execute
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Source,
  [Parameter(Mandatory)] [string]$LaneRoot,
  [Parameter(Mandatory)] [int]$Lanes,
  [switch]$Execute
)

if (-not (Test-Path $Source)) {
  Write-Error "Source folder not found: $Source"
  exit 1
}
if ($Lanes -lt 1) {
  Write-Error "Lanes must be >= 1"
  exit 1
}

$tiffs = Get-ChildItem $Source -Filter *.tif -File | Sort-Object Length -Descending
if ($tiffs.Count -eq 0) {
  Write-Error "No .tif files found in $Source"
  exit 1
}

Write-Host ("Found {0} TIFFs ({1:N1} GB total)" -f `
  $tiffs.Count, (($tiffs | Measure-Object Length -Sum).Sum / 1GB))

# Initialize N empty lanes
$laneSizes = @{}
$laneFiles = @{}
for ($i = 1; $i -le $Lanes; $i++) {
  $name = "lane{0:D2}" -f $i
  $laneSizes[$name] = 0L
  $laneFiles[$name] = @()
}

# Greedy: each file goes to the smallest lane
foreach ($t in $tiffs) {
  $smallest = $laneSizes.GetEnumerator() | Sort-Object Value | Select-Object -First 1
  $laneSizes[$smallest.Key] += $t.Length
  $laneFiles[$smallest.Key] += $t
}

# Show the plan
Write-Host ""
Write-Host "Plan:"
Write-Host ("{0,-10} {1,7} {2,12}" -f "Lane", "Files", "Total GB")
$laneSizes.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host ("{0,-10} {1,7} {2,12:N2}" -f $_.Key, $laneFiles[$_.Key].Count, ($_.Value / 1GB))
}

if (-not $Execute) {
  Write-Host ""
  Write-Host "Dry run complete. Re-run with -Execute to perform the moves."
  exit 0
}

# Execute the moves
Write-Host ""
Write-Host "Moving files..."
$null = New-Item -ItemType Directory -Path $LaneRoot -Force
foreach ($lane in $laneFiles.Keys | Sort-Object) {
  $laneDir = Join-Path $LaneRoot $lane
  $null = New-Item -ItemType Directory -Path $laneDir -Force
  foreach ($f in $laneFiles[$lane]) {
    Move-Item -LiteralPath $f.FullName -Destination $laneDir
  }
  Write-Host ("  {0}: moved {1} files" -f $lane, $laneFiles[$lane].Count)
}

Write-Host ""
Write-Host "Done."
