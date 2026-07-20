<#
.TITLE
    Reboot Pending Detection Script

.SYNOPSIS
    Detects devices that have a pending reboot older than the configured threshold.

.DESCRIPTION
    Checks the standard Windows pending-reboot signals: Component Based Servicing,
    Windows Update, pending file rename operations, and pending computer rename.
    Returns exit code 1 when a reboot is pending and the device has been up longer
    than the minimum uptime threshold, triggering the paired remediation that
    schedules a restart with user warning.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-reboot-pending.ps1

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
    .\detect-reboot-pending.ps1
    Returns exit 1 if a reboot is pending and uptime exceeds the threshold

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - $MinimumUptimeDays avoids flagging devices that rebooted recently but picked up a new pending flag
    - PendingFileRenameOperations alone is noisy (installers set it constantly), so it only counts together with uptime
#>

$ErrorActionPreference = "Stop"

# Only flag devices that have not rebooted for at least this long
$MinimumUptimeDays = 2

function Test-PendingReboot {
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $reasons.Add("Component Based Servicing")
    }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $reasons.Add("Windows Update")
    }

    try {
        $pendingRenames = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pendingRenames) {
            $reasons.Add("Pending file rename operations")
        }
    }
    catch {
        # Value not present - nothing pending
    }

    try {
        $activeName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        $pendingName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        if ($activeName -and $pendingName -and $activeName -ne $pendingName) {
            $reasons.Add("Pending computer rename ($activeName -> $pendingName)")
        }
    }
    catch {
        # Ignore - rename detection is best effort
    }

    return @($reasons)
}

try {
    $lastBoot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptimeDays = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)

    $pendingReasons = Test-PendingReboot

    if ($pendingReasons.Count -eq 0) {
        Write-Output "No reboot pending. Uptime: $uptimeDays days."
        exit 0
    }

    if ($uptimeDays -lt $MinimumUptimeDays) {
        Write-Output "Reboot pending ($($pendingReasons -join '; ')) but uptime is only $uptimeDays days - below the $MinimumUptimeDays day threshold."
        exit 0
    }

    Write-Output "Reboot pending for $uptimeDays days: $($pendingReasons -join '; ')"
    exit 1
}
catch {
    Write-Error $_
    exit 2
}
