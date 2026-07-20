<#
.TITLE
    Reboot Pending Remediation Script

.SYNOPSIS
    Schedules a restart with a visible user warning on devices that have a pending reboot.

.DESCRIPTION
    Schedules a system restart after a configurable delay (default 4 hours) using
    shutdown.exe with a warning message, giving the user time to save work. If a
    restart is already scheduled the script leaves it in place. Paired with
    detect-reboot-pending.ps1 which triggers only for devices that carry a pending
    reboot beyond the uptime threshold.

.TAGS
    Remediation,Action

.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-reboot-pending.ps1

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
    .\remediate-reboot-pending.ps1
    Schedules a restart in 4 hours with a user-visible warning

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - Adjust $DelaySeconds to fit maintenance windows; users see the Windows restart warning immediately
    - A user or admin can cancel the scheduled restart with: shutdown /a
#>

$ErrorActionPreference = "Stop"

# Delay before the restart fires (default 4 hours)
$DelaySeconds = 14400
$Message = "Your IT department scheduled a restart to finish installing updates. Save your work. The device restarts automatically in 4 hours. "

try {
    # If a shutdown is already scheduled, shutdown.exe returns error 1190;
    # leave the existing schedule untouched
    $process = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/r /t $DelaySeconds /c `"$Message`"" -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Output "Restart scheduled in $([math]::Round($DelaySeconds / 3600, 1)) hours."
        exit 0
    }
    elseif ($process.ExitCode -eq 1190) {
        Write-Output "A restart is already scheduled on this device - leaving it in place."
        exit 0
    }
    else {
        Write-Output "shutdown.exe returned exit code $($process.ExitCode)"
        exit 1
    }
}
catch {
    Write-Error $_
    exit 1
}
