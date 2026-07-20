<#
.TITLE
    Get Windows 11 Readiness Report

.SYNOPSIS
    Reports Windows 11 upgrade readiness for all Windows devices using Endpoint Analytics hardware signals.

.DESCRIPTION
    This script reads the Endpoint Analytics work-from-anywhere device data to report
    which Windows devices are eligible for Windows 11 and which hardware checks are
    blocking the rest: TPM, Secure Boot, RAM, storage, processor family, speed, core
    count, and 64-bit capability. It shows the tenant-level readiness summary plus a
    per-device breakdown of failed checks, so upgrade waves and hardware refresh
    budgets can be planned from real inventory data.

.TAGS
    Devices,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-windows11-readiness-report.ps1
    Shows the tenant readiness summary and all devices with failed upgrade checks

.EXAMPLE
    .\get-windows11-readiness-report.ps1 -ExportToCsv
    Exports the full per-device readiness data to a timestamped CSV file

.EXAMPLE
    .\get-windows11-readiness-report.ps1 -OnlyBlocked
    Lists only devices that are not eligible for the Windows 11 upgrade

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Endpoint Analytics must be enabled and collecting data; without it the report is empty
    - Devices need to report analytics data for up to 24 hours after enrollment before appearing
    - Uses beta Graph endpoints because the work-from-anywhere analytics surface is not exposed on v1.0
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Show only devices that are blocked from upgrading")]
    [switch]$OnlyBlocked,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [switch]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall
)

# ============================================================================
# ENVIRONMENT DETECTION AND SETUP
# ============================================================================

function Initialize-RequiredModule {
    param(
        [string[]]$ModuleNames,
        [bool]$IsAutomationEnvironment,
        [bool]$ForceInstall = $false
    )

    foreach ($ModuleName in $ModuleNames) {
        Write-Verbose "Checking module: $ModuleName"

        $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1

        if (-not $module) {
            if ($IsAutomationEnvironment) {
                throw "Module '$ModuleName' is not available in Azure Automation"
            }
            else {
                Write-Information "Module '$ModuleName' not found. Installing..." -InformationAction Continue

                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }

                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }

        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
}

# Detect execution environment
$IsAzureAutomation = $null -ne $PSPrivateMetadata.JobId.Guid

# Initialize required modules
$RequiredModules = @("Microsoft.Graph.Authentication")

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

try {
    Initialize-RequiredModule -ModuleNames $RequiredModules -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
    Write-Verbose "✓ All required modules are available"
}
catch {
    Write-Error "Module initialization failed: $_"
    exit 1
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

try {
    if ($IsAzureAutomation) {
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-MgGraphAllPage {
    param(
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $allResults = @()
    $nextLink = $Uri

    do {
        try {
            if ($allResults.Count -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET

            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }

            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data: $($_.Exception.Message)"
            break
        }
    } while ($nextLink)

    return $allResults
}

function Get-FailedCheck {
    param([object]$Device)

    # Each check property is TRUE when the check FAILED
    $checkMap = [ordered]@{
        osCheckFailed                 = "OS version"
        processor64BitCheckFailed     = "64-bit processor"
        processorFamilyCheckFailed    = "Processor family"
        processorCoreCountCheckFailed = "Processor core count"
        processorSpeedCheckFailed     = "Processor speed"
        ramCheckFailed                = "RAM"
        secureBootCheckFailed         = "Secure Boot"
        storageCheckFailed            = "Storage"
        tpmCheckFailed                = "TPM 2.0"
    }

    $failed = foreach ($check in $checkMap.Keys) {
        if ($Device.$check -eq $true) { $checkMap[$check] }
    }

    return @($failed)
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    # Tenant-level readiness summary
    Write-Information "Retrieving tenant hardware readiness summary..." -InformationAction Continue
    $readinessSummary = $null
    try {
        $readinessSummary = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsWorkFromAnywhereHardwareReadinessMetric" -Method GET
    }
    catch {
        Write-Warning "Could not read the hardware readiness summary: $($_.Exception.Message)"
    }

    # Per-device work-from-anywhere data
    Write-Information "Retrieving per-device readiness data..." -InformationAction Continue
    $selectFields = "id,deviceName,serialNumber,manufacturer,model,ownership,managedBy,osDescription,osVersion,upgradeEligibility,osCheckFailed,processor64BitCheckFailed,processorFamilyCheckFailed,processorCoreCountCheckFailed,processorSpeedCheckFailed,ramCheckFailed,secureBootCheckFailed,storageCheckFailed,tpmCheckFailed"
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsWorkFromAnywhereMetrics/allDevices/metricDevices?`$select=$selectFields"

    if (@($devices).Count -eq 0) {
        Write-Warning "No work-from-anywhere analytics data found. Endpoint Analytics may not be enabled, or devices have not reported yet."
        return
    }
    Write-Information "✓ Found analytics data for $(@($devices).Count) devices" -InformationAction Continue

    [System.Collections.Generic.List[Object]]$report = @()
    foreach ($device in $devices) {
        $failedChecks = Get-FailedCheck -Device $device

        $report.Add([PSCustomObject]@{
                DeviceName         = $device.deviceName
                SerialNumber       = $device.serialNumber
                Manufacturer       = $device.manufacturer
                Model              = $device.model
                Ownership          = $device.ownership
                OsDescription      = $device.osDescription
                OsVersion          = $device.osVersion
                UpgradeEligibility = $device.upgradeEligibility
                FailedChecks       = ($failedChecks -join "; ")
                FailedCheckCount   = $failedChecks.Count
            })
    }

    if ($OnlyBlocked) {
        $report = [System.Collections.Generic.List[Object]]@($report | Where-Object { $_.UpgradeEligibility -notin @("capable", "upgraded") })
    }

    # ----- Display results -----
    Write-Information "`nWINDOWS 11 READINESS REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($readinessSummary) {
        Write-Information "`nTenant summary (Endpoint Analytics):" -InformationAction Continue
        Write-Information "  Total devices:    $($readinessSummary.totalDeviceCount)" -InformationAction Continue
        Write-Information "  Upgrade eligible: $($readinessSummary.upgradeEligibleDeviceCount)" -InformationAction Continue
    }

    foreach ($eligibilityGroup in ($report | Group-Object -Property UpgradeEligibility | Sort-Object Name)) {
        $groupLabel = if ($eligibilityGroup.Name) { $eligibilityGroup.Name } else { "unknown" }
        Write-Information "`n[$groupLabel] $($eligibilityGroup.Count) device(s)" -InformationAction Continue

        foreach ($row in ($eligibilityGroup.Group | Sort-Object FailedCheckCount -Descending)) {
            $line = "  $($row.DeviceName) | $($row.Manufacturer) $($row.Model) | $($row.OsVersion)"
            if ($row.FailedChecks) {
                $line += " | blocked by: $($row.FailedChecks)"
            }
            Write-Information $line -InformationAction Continue
        }
    }

    # Summary of the most common blockers
    $blockedDevices = @($report | Where-Object { $_.FailedCheckCount -gt 0 })
    if ($blockedDevices.Count -gt 0) {
        Write-Information "`nMost common blocking checks:" -InformationAction Continue
        $allFailures = $blockedDevices | ForEach-Object { $_.FailedChecks -split "; " }
        foreach ($failureGroup in ($allFailures | Group-Object | Sort-Object Count -Descending)) {
            Write-Information "  $($failureGroup.Name): $($failureGroup.Count) devices" -InformationAction Continue
        }
    }

    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) devices reported, $($blockedDevices.Count) with failed hardware checks" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Windows11_Readiness_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
