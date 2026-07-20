<#
.TITLE
    Winget App Updates Detection Script

.SYNOPSIS
    Detects third-party applications with available winget upgrades.

.DESCRIPTION
    Resolves winget in SYSTEM context and lists available application upgrades.
    Returns exit code 1 when more than the allowed number of upgradable apps is
    found, triggering the paired remediation that upgrades them silently. Apps with
    unknown installed versions are excluded because winget cannot safely upgrade
    them.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-winget-updates.ps1

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
    .\detect-winget-updates-available.ps1
    Returns exit 1 if any app has a pending winget upgrade

.NOTES
    - Runs in SYSTEM context via Intune Remediations; winget is resolved from the DesktopAppInstaller package folder because SYSTEM has no winget alias
    - Requires Windows 10 1809+ with App Installer (winget) present
    - Apps listed in $ExcludedIds are ignored; add IDs of apps managed by other update mechanisms
#>

$ErrorActionPreference = "Stop"

# Winget package IDs to ignore (managed elsewhere, e.g. by Intune apps or auto-updaters)
$ExcludedIds = @(
    "Microsoft.Office",
    "Microsoft.Teams"
)

function Resolve-WingetPath {
    # SYSTEM context has no winget alias; resolve the packaged exe directly
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
        Write-Output "winget is not installed on this device - nothing to check."
        exit 0
    }

    # --include-unknown is deliberately NOT used: unknown-version apps cannot be upgraded safely
    $output = & $winget upgrade --accept-source-agreements --disable-interactivity 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0 -and $output -notmatch "upgrades available") {
        # Exit code is non-zero when no upgrades exist; treat known "no upgrades" output as compliant
        if ($output -match "No installed package found|No available upgrade") {
            Write-Output "No winget upgrades available."
            exit 0
        }
    }

    # Parse the table: lines after the dashed separator, columns Name Id Version Available Source
    $lines = $output -split "`r?`n"
    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-{5,}') { $separatorIndex = $i; break }
    }

    if ($separatorIndex -lt 0) {
        Write-Output "No winget upgrades available."
        exit 0
    }

    $upgradableApps = [System.Collections.Generic.List[string]]::new()
    for ($i = $separatorIndex + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if (-not $line) { continue }
        if ($line -match '^\d+ upgrades? available') { continue }
        if ($line -match 'require explicit targeting|cannot be determined') { break }

        # Column widths vary by locale; match the package ID as the token
        # shaped like Publisher.Product instead of splitting by position
        $packageId = ($line -split '\s+' | Where-Object { $_ -match '^[\w-]+(\.[\w-]+)+$' } | Select-Object -First 1)

        if ($packageId -and ($ExcludedIds -notcontains $packageId)) {
            $upgradableApps.Add($packageId)
        }
    }

    if ($upgradableApps.Count -gt 0) {
        Write-Output "Upgrades available for $($upgradableApps.Count) app(s): $($upgradableApps -join ', ')"
        exit 1
    }

    Write-Output "No winget upgrades available."
    exit 0
}
catch {
    Write-Error $_
    exit 2
}
