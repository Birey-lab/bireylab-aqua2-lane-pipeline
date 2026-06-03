<#
.SYNOPSIS
  Build CFU lane folders using NTFS junctions (no data copying).

.DESCRIPTION
  Recursively finds all <stem>_AQuA2.mat files under -Root, then creates
  N lane subfolders under -LaneRoot. Each lane gets junctions (Windows
  directory symlinks) pointing back at the original <stem>_results/ folders
  containing those .mat files.

  Junctions resolve at runtime — cfu_lane.exe sees a normal folder
  containing _AQuA2.mat, but no actual data is copied.

  Without -Execute, performs a dry run.
  With    -Execute, creates the junctions.

  Cleanup: when CFU is done, "Remove-Item <LaneRoot> -Recurse -Force"
  removes only the junctions, never the underlying data.

.PARAMETER Root
  Root of the detection output tree (e.g., the ResultsRoot from Launch-Lanes-Exe.ps1).
  Recursive search for _AQuA2.mat files happens here.

.PARAMETER LaneRoot
  Destination for the CFU lane folders.

.PARAMETER Lanes
  Number of CFU lanes. Typical: 28-32. CFU is disk-bound; more lanes past
  ~32 don't help.

.PARAMETER Execute
  Required to actually create junctions; otherwise dry run.

.EXAMPLE
  # Dry run
  .\Build-CFU-Lanes.ps1 -Root C:\data\my_results -LaneRoot C:\data\my_CFU_lanes -Lanes 28

  # Execute
  .\Build-CFU-Lanes.ps1 -Root C:\data\my_results -LaneRoot C:\data\my_CFU_lanes -Lanes 28 -Execute
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Root,
  [Parameter(Mandatory)] [string]$LaneRoot,
  [Parameter(Mandatory)] [int]$Lanes,
  [switch]$Execute
)

if (-not (Test-Path $Root)) {
  Write-Error "Root not found: $Root"
  exit 1
}

# Find all _AQuA2.mat files; we want their parent folders
$matFiles = Get-ChildItem $Root -Recurse -Filter *_AQuA2.mat -File
if ($matFiles.Count -eq 0) {
  Write-Error "No *_AQuA2.mat files found under $Root"
  exit 1
}

# Group: one entry per parent folder (each holds one recording's results)
$resultFolders = $matFiles | ForEach-Object { $_.Directory } | Sort-Object FullName -Unique
Write-Host ("Found {0} _AQuA2.mat files in {1} result folders" -f $matFiles.Count, $resultFolders.Count)

# Round-robin assignment to lanes
$assignments = @{}
for ($i = 1; $i -le $Lanes; $i++) {
  $assignments["lane{0:D2}" -f $i] = @()
}
$i = 0
foreach ($folder in $resultFolders) {
  $laneName = "lane{0:D2}" -f (($i % $Lanes) + 1)
  $assignments[$laneName] += $folder
  $i++
}

# Show the plan
Write-Host ""
Write-Host "Plan:"
$assignments.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host ("  {0}: {1} folders" -f $_.Key, $_.Value.Count)
}

if (-not $Execute) {
  Write-Host ""
  Write-Host "Dry run complete. Re-run with -Execute to create junctions."
  exit 0
}

# Execute: create lane subfolders + junctions
$null = New-Item -ItemType Directory -Path $LaneRoot -Force
Write-Host ""
Write-Host "Creating junctions..."

foreach ($lane in $assignments.Keys | Sort-Object) {
  $laneDir = Join-Path $LaneRoot $lane
  $null = New-Item -ItemType Directory -Path $laneDir -Force

  foreach ($srcFolder in $assignments[$lane]) {
    $junctionName = $srcFolder.Name  # e.g., <stem>_results
    $junctionPath = Join-Path $laneDir $junctionName

    # cmd mklink /J: create directory junction
    cmd /c mklink /J "$junctionPath" "$($srcFolder.FullName)" | Out-Null
  }
  Write-Host ("  {0}: created {1} junctions" -f $lane, $assignments[$lane].Count)
}

Write-Host ""
Write-Host "Done. Junctions point at the original folders; no data was copied."
Write-Host "To clean up later: Remove-Item $LaneRoot -Recurse -Force"
