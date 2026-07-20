<#
.TITLE
    OneDrive Known Folder Move Remediation Script

.SYNOPSIS
    Configures OneDrive silent Known Folder Move via policy registry keys.

.DESCRIPTION
    Writes the OneDrive policy registry values that silently move Desktop,
    Documents, and Pictures into OneDrive for the configured tenant:
    KFMSilentOptIn with the tenant ID, silent opt-in without notification, and
    KFMBlockOptOut so users cannot move the folders back out. OneDrive applies the
    move at its next sign-in or policy refresh. Paired with
    detect-onedrive-kfm-not-configured.ps1.

.TAGS
    Remediation,Action

.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-onedrive-kfm-not-configured.ps1

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
    .\remediate-onedrive-kfm.ps1
    Writes the KFM silent opt-in policy for the configured tenant

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - IMPORTANT: set $TenantId to your Entra tenant ID before deploying (both scripts)
    - Users must be signed in to OneDrive with a licensed account for the folder move to complete
    - Set $BlockOptOut to $false if users should be allowed to redirect folders back
#>

$ErrorActionPreference = "Stop"

# Set this to your Entra tenant ID before deploying
$TenantId = "00000000-0000-0000-0000-000000000000"

# Prevent users from moving known folders back out of OneDrive
$BlockOptOut = $true

try {
    if ($TenantId -eq "00000000-0000-0000-0000-000000000000") {
        Write-Output "Configuration error: TenantId has not been set in the remediation script."
        exit 1
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    if (-not (Test-Path $policyPath)) {
        $null = New-Item -Path $policyPath -Force
    }

    # Silent opt-in moves Desktop/Documents/Pictures without user interaction
    Set-ItemProperty -Path $policyPath -Name "KFMSilentOptIn" -Value $TenantId -Type String
    Set-ItemProperty -Path $policyPath -Name "KFMSilentOptInWithNotification" -Value 0 -Type DWord

    if ($BlockOptOut) {
        Set-ItemProperty -Path $policyPath -Name "KFMBlockOptOut" -Value 1 -Type DWord
    }

    Write-Output "KFM silent opt-in configured for tenant $TenantId. OneDrive applies the folder move at its next sign-in or policy refresh."
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
