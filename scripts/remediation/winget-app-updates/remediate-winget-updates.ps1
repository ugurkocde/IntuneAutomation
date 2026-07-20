<#
.TITLE
    Winget App Updates Remediation Script

.SYNOPSIS
    Silently upgrades third-party applications using winget.

.DESCRIPTION
    Runs winget upgrade for all applications with available updates, excluding a
    configurable list of package IDs that are managed elsewhere. Upgrades run
    silently with license agreements accepted. Apps with unknown installed versions
    are skipped because winget cannot upgrade them reliably. Paired with
    detect-winget-updates-available.ps1.

.TAGS
    Remediation,Action

.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-winget-updates-available.ps1

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
    .\remediate-winget-updates.ps1
    Upgrades all upgradable apps silently

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - Keep $ExcludedIds in sync with the detection script
    - Apps in use during upgrade may prompt the user to close or fail silently; winget reports per-app results in the output
#>

$ErrorActionPreference = "Stop"

# Keep in sync with the detection script's exclusion list
$ExcludedIds = @(
    "Microsoft.Office",
    "Microsoft.Teams"
)

function Resolve-WingetPath {
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCommand) { return $wingetCommand.Source }

    $packageFolder = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1

    if ($packageFolder) {
        $candidate = Join-Path $packageFolder.FullName "winget.exe"
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

try {
    $winget = Resolve-WingetPath
    if (-not $winget) {
        Write-Output "winget is not installed on this device."
        exit 1
    }

    $arguments = @(
        "upgrade", "--all", "--silent",
        "--accept-source-agreements", "--accept-package-agreements",
        "--disable-interactivity"
    )

    foreach ($excludedId in $ExcludedIds) {
        # winget 1.4+ hides pinned packages from --all; explicit pinning per run
        # is not persistent, so exclusions are enforced via pin add
        & $winget pin add --id $excludedId --accept-source-agreements 2>&1 | Out-Null
    }

    $output = & $winget @arguments 2>&1 | Out-String
    $wingetExit = $LASTEXITCODE

    # Remove the temporary pins again so they do not leak into user context
    foreach ($excludedId in $ExcludedIds) {
        & $winget pin remove --id $excludedId 2>&1 | Out-Null
    }

    Write-Output $output.Trim()

    if ($wingetExit -eq 0) {
        Write-Output "winget upgrade completed."
        exit 0
    }

    # Non-zero also occurs when nothing was applicable; treat "no upgrades" as success
    if ($output -match "No installed package found|No available upgrade") {
        Write-Output "No applicable upgrades."
        exit 0
    }

    Write-Output "winget upgrade finished with exit code $wingetExit - some upgrades may have failed."
    exit 1
}
catch {
    Write-Error $_
    exit 1
}
