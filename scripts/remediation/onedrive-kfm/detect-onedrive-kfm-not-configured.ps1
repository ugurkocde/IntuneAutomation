<#
.TITLE
    OneDrive Known Folder Move Detection Script

.SYNOPSIS
    Detects devices where OneDrive Known Folder Move is not configured via policy.

.DESCRIPTION
    Checks the OneDrive policy registry keys for silent Known Folder Move opt-in
    (KFMSilentOptIn with the tenant ID) and verifies the OneDrive sync client is
    installed. Returns exit code 1 when the KFM policy is missing or points to a
    different tenant, triggering the paired remediation that writes the policy keys.
    Desktop, Documents, and Pictures then move to OneDrive automatically at the next
    OneDrive sign-in.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-onedrive-kfm.ps1

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
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\detect-onedrive-kfm-not-configured.ps1
    Returns exit 1 if the KFM silent opt-in policy is not set for the tenant

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - IMPORTANT: set $ExpectedTenantId to your Entra tenant ID before deploying (both scripts)
    - Devices without the OneDrive sync client are reported compliant with a note, since KFM cannot apply there
#>

$ErrorActionPreference = "Stop"

# Set this to your Entra tenant ID before deploying
$ExpectedTenantId = "00000000-0000-0000-0000-000000000000"

try {
    if ($ExpectedTenantId -eq "00000000-0000-0000-0000-000000000000") {
        Write-Output "Configuration error: ExpectedTenantId has not been set in the detection script."
        exit 2
    }

    # OneDrive must be present for KFM to work
    $oneDrivePaths = @(
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    $oneDriveInstalled = $false
    foreach ($path in $oneDrivePaths) {
        if (Test-Path $path) { $oneDriveInstalled = $true; break }
    }

    if (-not $oneDriveInstalled) {
        Write-Output "OneDrive sync client is not installed - KFM policy not applicable."
        exit 0
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    $configuredTenant = $null
    if (Test-Path $policyPath) {
        $configuredTenant = (Get-ItemProperty -Path $policyPath -Name "KFMSilentOptIn" -ErrorAction SilentlyContinue).KFMSilentOptIn
    }

    if ($configuredTenant -eq $ExpectedTenantId) {
        Write-Output "KFM silent opt-in is configured for the expected tenant."
        exit 0
    }

    if ($configuredTenant) {
        Write-Output "KFM silent opt-in points to a different tenant ($configuredTenant)."
    }
    else {
        Write-Output "KFM silent opt-in policy is not configured."
    }
    exit 1
}
catch {
    Write-Error $_
    exit 2
}
