<#
.TITLE
    Windows Defender Definition Update Detection

.SYNOPSIS
    Detects if Windows Defender antivirus definitions are outdated

.DESCRIPTION
    Checks if Windows Defender definitions are current (within 48 hours).
    Returns exit code 1 if definitions are outdated.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-antivirus-definitions.ps1

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
    .\detect-antivirus-definitions-outdated.ps1

.NOTES
    Runs in SYSTEM context
#>

$ErrorActionPreference = "Stop"
$script:MaxDefinitionAgeHours = 48

try {
    # Get Defender status
    $mpStatus = Get-MpComputerStatus -ErrorAction Stop
    
    # Check definition age
    $now = Get-Date
    $definitionAge = ($now - $mpStatus.AntivirusSignatureLastUpdated).TotalHours
    
    Write-Output "Definition age: $([math]::Round($definitionAge, 1)) hours"
    Write-Output "Last updated: $($mpStatus.AntivirusSignatureLastUpdated)"
    Write-Output "Version: $($mpStatus.AntivirusSignatureVersion)"
    
    if ($definitionAge -gt $script:MaxDefinitionAgeHours) {
        Write-Output "Definitions are outdated (threshold: $script:MaxDefinitionAgeHours hours)"
        exit 1
    }
    
    Write-Output "Windows Defender definitions are up to date"
    exit 0
}
catch {
    Write-Error "Detection failed: $_"
    exit 2
}