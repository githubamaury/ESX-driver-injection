<#
.SYNOPSIS
Interactively injects a community driver into a VMware ESXi image using PowerCLI.

.DESCRIPTION
This script prompts the user for required paths and driver name, unblocks itself,
installs PowerCLI if needed, and exports a customized ESXi ISO.

.NOTES
Run in elevated PowerShell with internet access.
#>

function Log { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Fail { param([string]$msg) Write-Error "[ERROR] $msg"; exit 1 }

# Step 1: Unblock the script
try {
    $scriptPath = $MyInvocation.MyCommand.Path
    Unblock-File -Path $scriptPath -ErrorAction SilentlyContinue
    Log "✅ Script unblocked: $scriptPath"
} catch {
    Log "⚠️ Could not unblock script (already unblocked or running in memory)"
}

# Step 2: Install PowerCLI if missing
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Log "Installing VMware PowerCLI..."
    try {
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Log "✅ PowerCLI installed successfully."
    } catch {
        Fail "Failed to install PowerCLI: $_"
    }
} else {
    Log "✅ PowerCLI already installed."
}

# Step 3: Prompt user for input
$EsxiDepotPath = Read-Host "Enter full path to ESXi Offline Bundle ZIP"
$DriverDepotPath = Read-Host "Enter full path to community driver ZIP or VIB"
$DriverPackageName = Read-Host "Enter exact name of driver package (e.g., net-community for NICs)"
$OutputIsoPath = Read-Host "Enter output path for customized ISO (or press Enter for C drive root directory)"
if (-not $OutputIsoPath) {
    $OutputIsoPath = "C:\Custom-ESXi.iso"
}

# Sanitize input
$EsxiDepotPath = $EsxiDepotPath.Trim('"')
$DriverDepotPath = $DriverDepotPath.Trim('"')
$DriverPackageName = $DriverPackageName.Trim('"')
$OutputIsoPath = $OutputIsoPath.Trim('"')

# Validate paths
if (-not (Test-Path $EsxiDepotPath)) {
    Fail "ESXi depot file not found at: $EsxiDepotPath"
}
if (-not (Test-Path $DriverDepotPath)) {
    Fail "Driver depot file not found at: $DriverDepotPath"
}

# Step 4: Import ImageBuilder
try {
    Import-Module VMware.ImageBuilder -ErrorAction Stop
    Log "✅ ImageBuilder module imported."
} catch {
    Fail "Failed to import VMware.ImageBuilder: $_"
}

# Step 5: Add depots
try {
    Log "Adding ESXi depot: $EsxiDepotPath"
    Add-EsxSoftwareDepot -DepotUrl $EsxiDepotPath -ErrorAction Stop

    Log "Adding driver depot: $DriverDepotPath"
    Add-EsxSoftwareDepot -DepotUrl $DriverDepotPath -ErrorAction Stop
} catch {
    Fail "Failed to add software depots: $_"
}

# Step 6: Clone image profile with unique name
try {
    $baseProfile = Get-EsxImageProfile | Where-Object { $_.Name -like "*ESXi*" } | Select-Object -First 1
    if (-not $baseProfile) { Fail "No matching image profile found." }

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $CustomProfileName = "Custom-ESXi-Image-$timestamp"

    Log "Cloning image profile: $($baseProfile.Name) → $CustomProfileName"
    $customProfile = New-EsxImageProfile -CloneProfile $baseProfile -Name $CustomProfileName -Vendor "Community" -ErrorAction Stop
} catch {
    Fail "Failed to clone image profile: $_"
}

# Step 7: Inject driver
try {
    Log "Injecting driver package: $DriverPackageName"
    Add-EsxSoftwarePackage -ImageProfile $customProfile -SoftwarePackage $DriverPackageName -ErrorAction Stop
} catch {
    Fail "Failed to inject driver: $_"
}

# Step 8: Export ISO
try {
    Log "Exporting ISO to: $OutputIsoPath"
    Export-EsxImageProfile -ImageProfile $customProfile -ExportToIso -FilePath $OutputIsoPath 

    Log "✅ ISO exported successfully!"
} catch {
    Fail "Failed to export ISO: $_"
}