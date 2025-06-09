<#
.TITLE
    Windows Defender Definition Update Remediation

.SYNOPSIS
    Updates Windows Defender antivirus definitions

.DESCRIPTION
    Forces Windows Defender signature updates and verifies they were successful.

.TAGS
    Remediation,Action

.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-antivirus-definitions-outdated.ps1

.PLATFORM
    Windows

.MINROLE
    Intune Service Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial version

.LASTUPDATE
    2025-06-09

.EXAMPLE
    .\remediate-antivirus-definitions.ps1

.NOTES
    Runs in SYSTEM context
#>

$ErrorActionPreference = "Stop"

try {
    Write-Output "Starting definition update..."
    
    # Get current definition version
    $beforeUpdate = Get-MpComputerStatus -ErrorAction Stop
    $beforeVersion = $beforeUpdate.AntivirusSignatureVersion
    Write-Output "Current version: $beforeVersion"
    
    # Update signatures
    Write-Output "Downloading latest definitions..."
    Update-MpSignature -ErrorAction Stop
    
    # Wait for update to complete (max 2 minutes)
    $maxWait = 120
    $waited = 0
    
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 10
        $waited += 10
        
        $currentStatus = Get-MpComputerStatus -ErrorAction Stop
        if ($currentStatus.AntivirusSignatureVersion -ne $beforeVersion) {
            Write-Output "Definitions updated to version: $($currentStatus.AntivirusSignatureVersion)"
            break
        }
    }
    
    # Verify update
    $finalStatus = Get-MpComputerStatus -ErrorAction Stop
    $definitionAge = ((Get-Date) - $finalStatus.AntivirusSignatureLastUpdated).TotalHours
    
    if ($definitionAge -lt 48) {
        Write-Output "Update successful - Definitions are current ($([math]::Round($definitionAge, 1)) hours old)"
        exit 0
    }
    else {
        Write-Output "Update may have failed - Definitions still outdated"
        exit 1
    }
}
catch {
    Write-Error "Remediation failed: $_"
    exit 1
}