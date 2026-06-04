<#
.SYNOPSIS
    Reports the current EC2 instance's compute and storage capacity.

.DESCRIPTION
    Quick read-only check of vCPU, RAM, and disk specs. Useful as a sanity
    check before launching the pipeline, or as the first step in deciding
    how to size lane counts.

    For a full profile-based lane-count recommendation, use Auto-Size-Lanes.ps1
    instead. This script just reports the hardware specs.

.EXAMPLE
    .\Get-Instance-Capacity.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Compute ---
$sys = Get-CimInstance Win32_ComputerSystem
$os  = Get-CimInstance Win32_OperatingSystem
$cpu = $sys.NumberOfLogicalProcessors
$ramGB = [math]::Round($sys.TotalPhysicalMemory / 1GB, 1)

# Try to get instance type via metadata (v2/IMDSv2 first, fall back to v1)
$instanceType = "(unknown)"
$instanceId   = "(unknown)"
try {
    $token = Invoke-WebRequest -UseBasicParsing -Method PUT `
        -Uri "http://169.254.169.254/latest/api/token" `
        -Headers @{'X-aws-ec2-metadata-token-ttl-seconds'='60'} `
        -TimeoutSec 3 -ErrorAction Stop | Select-Object -ExpandProperty Content
    $hdr = @{'X-aws-ec2-metadata-token' = $token}
    $instanceType = (Invoke-WebRequest -UseBasicParsing -Headers $hdr -Uri "http://169.254.169.254/latest/meta-data/instance-type" -TimeoutSec 3).Content
    $instanceId   = (Invoke-WebRequest -UseBasicParsing -Headers $hdr -Uri "http://169.254.169.254/latest/meta-data/instance-id"   -TimeoutSec 3).Content
} catch {
    # Not on EC2 (or IMDS blocked) -- that's fine, leave unknowns.
}

# --- Disk ---
$cDrive = Get-PSDrive C -ErrorAction SilentlyContinue
$cFreeGB = if ($cDrive) { [math]::Round($cDrive.Free / 1GB, 1) } else { 0 }
$cUsedGB = if ($cDrive) { [math]::Round($cDrive.Used / 1GB, 1) } else { 0 }
$cTotalGB = $cFreeGB + $cUsedGB

# Disk type (SSD/HDD via physical media)
$diskTypes = @()
try {
    $disks = Get-PhysicalDisk -ErrorAction Stop
    foreach ($d in $disks) {
        $diskTypes += "$($d.FriendlyName) [$($d.MediaType), $([math]::Round($d.Size/1GB,0)) GB]"
    }
} catch {
    $diskTypes = @("(could not enumerate physical disks)")
}

# --- Print report ---
Write-Host ""
Write-Host "============================================="  -ForegroundColor Cyan
Write-Host " EC2 Instance Capacity Report"                   -ForegroundColor Cyan
Write-Host "============================================="  -ForegroundColor Cyan
Write-Host ""
Write-Host "Instance ID:   $instanceId"
Write-Host "Instance type: $instanceType"
Write-Host "OS:            $($os.Caption) (build $($os.BuildNumber))"
Write-Host ""
Write-Host "--- Compute ---"
Write-Host ("  Logical CPUs (vCPU):  {0}" -f $cpu)
Write-Host ("  Total physical RAM:   {0} GB" -f $ramGB)
Write-Host ""
Write-Host "--- Disk ---"
Write-Host ("  C: drive -- {0:N1} GB used / {1:N1} GB total ({2:N1} GB free)" -f $cUsedGB, $cTotalGB, $cFreeGB)
foreach ($t in $diskTypes) {
    Write-Host "    $t"
}
Write-Host ""
Write-Host "--- Rough lane-count starting points ---"
$cpuCap = [math]::Floor($cpu / 3)
$cpuCapWith32 = [math]::Min($cpuCap, 32)
Write-Host ("  CPU-only ceiling (vCPU/3):     {0}" -f $cpuCap)
Write-Host ("  CPU-only ceiling capped at 32: {0}" -f $cpuCapWith32)
Write-Host "  (RAM ceiling depends on per-file demand -- use Auto-Size-Lanes.ps1 to profile)"
Write-Host ""
Write-Host "Note: EBS volume throughput is set per-volume in AWS Console (gp3 default = 125 MB/s)."
Write-Host "      32 simultaneous lane workers on default gp3 may bottleneck on IO, not CPU/RAM."
Write-Host ""
