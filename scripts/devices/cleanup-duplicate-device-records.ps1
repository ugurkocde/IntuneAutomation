<#
.TITLE
    Cleanup Duplicate Intune Device Records

.SYNOPSIS
    Finds Intune managed-device records that share a serial number and optionally removes the older stale duplicates.

.DESCRIPTION
    This script groups all Intune managed devices by serial number and identifies
    duplicates - typically left behind by re-enrollment, OS reinstalls, or Autopilot
    resets. For every duplicate set it keeps the record with the most recent sync and
    marks the older records for cleanup. By default the script only reports; deletion
    requires the -Remove switch and is preview-safe via -WhatIf. Removing a device
    record from Intune does not wipe the device; it only deletes the stale management
    object.

    Scope is limited to Intune managed-device records returned by
    /deviceManagement/managedDevices. The script does not inspect or delete Microsoft
    Entra device objects or Windows Autopilot registrations. Duplicate-looking Entra
    objects can be expected with Hybrid Autopilot deployments and must not be treated
    as stale Intune records.

.TAGS
    Devices,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.3

.CHANGELOG
    1.3 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.2 - Clarified that only Intune managed-device records are evaluated and removed
    1.1 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\cleanup-duplicate-device-records.ps1
    Reports duplicate Intune managed-device records without deleting anything

.EXAMPLE
    .\cleanup-duplicate-device-records.ps1 -Remove "true" -WhatIf
    Shows exactly which Intune managed-device records would be deleted, without deleting them

.EXAMPLE
    .\cleanup-duplicate-device-records.ps1 -Remove "true"
    Deletes the older duplicate Intune managed-device records after an interactive confirmation

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Only Intune managed-device records are evaluated
    - Microsoft Entra device objects and Windows Autopilot registrations are never evaluated or deleted
    - Hybrid Autopilot deployments can create expected duplicate-looking Entra device objects
    - The newest record per serial number (by lastSyncDateTime, falling back to enrolledDateTime) is always kept
    - Devices with empty or placeholder serial numbers (e.g. "Defaultstring") are excluded from duplicate matching
    - Deleting an Intune device record does not wipe or retire the physical device
    - Uses beta Graph endpoints for consistency with the rest of the library
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Delete the older duplicate Intune managed-device records instead of only reporting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$Remove,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
if ([string]::IsNullOrWhiteSpace($forceModuleInstallRaw)) {
    $ForceModuleInstall = $false
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("true", "1", '$true')) {
    $ForceModuleInstall = $true
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("false", "0", '$false')) {
    $ForceModuleInstall = $false
}
else {
    throw "Parameter 'ForceModuleInstall' accepts only true, false, 1, 0, $true, or $false."
}

# Azure Automation supplies portal parameter values as strings. Normalize the
# public boolean parameters once so local and runbook execution use real booleans.
foreach ($runbookBooleanParameter in @('Remove', 'ExportToCsv')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)

    if ([string]::IsNullOrWhiteSpace($runbookBooleanRaw)) {
        Set-Variable -Name $runbookBooleanParameter -Value $false
        continue
    }

    switch ($runbookBooleanRaw.Trim().ToLowerInvariant()) {
        { $_ -in @("true", "1", '$true') } {
            Set-Variable -Name $runbookBooleanParameter -Value $true
        }
        { $_ -in @("false", "0", '$false') } {
            Set-Variable -Name $runbookBooleanParameter -Value $false
        }
        default {
            throw "Parameter '$runbookBooleanParameter' accepts only true, false, 1, 0, $true, or $false."
        }
    }
}

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
        Write-Output "Connecting to Microsoft Graph..."
        $Scopes = @(
            "DeviceManagementManagedDevices.ReadWrite.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Output "✓ Successfully connected to Microsoft Graph"
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
            throw "Error fetching data: $($_.Exception.Message)"
        }
    } while ($nextLink)

    return $allResults
}

function Get-EffectiveTimestamp {
    param([object]$Device)

    # lastSyncDateTime is the best liveness signal; fall back to enrollment time
    if ($Device.lastSyncDateTime) {
        return [DateTime]::Parse($Device.lastSyncDateTime.ToString())
    }
    if ($Device.enrolledDateTime) {
        return [DateTime]::Parse($Device.enrolledDateTime.ToString())
    }
    return [DateTime]::MinValue
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Scope: Intune managed-device records only."
    Write-Output "Microsoft Entra device objects and Windows Autopilot registrations are not evaluated or removed."
    Write-Output "Retrieving Intune managed devices..."
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,serialNumber,operatingSystem,model,manufacturer,lastSyncDateTime,enrolledDateTime,userPrincipalName,managementAgent"
    Write-Output "✓ Found $(@($devices).Count) Intune managed devices"

    # Placeholder serials would create false duplicate groups
    $invalidSerials = @("", "defaultstring", "tobefilledbyoem", "systemserialnumber", "0", "none", "unknown")
    $devicesWithSerial = @($devices | Where-Object {
            $_.serialNumber -and ($invalidSerials -notcontains $_.serialNumber.ToLowerInvariant().Trim())
        })

    $duplicateGroups = @($devicesWithSerial | Group-Object -Property { $_.serialNumber.Trim() } | Where-Object { $_.Count -gt 1 })

    if ($duplicateGroups.Count -eq 0) {
        Write-Output "`nNo duplicate Intune managed-device records found."
        return
    }

    Write-Output "✓ Found $($duplicateGroups.Count) serial number(s) with duplicate Intune managed-device records"

    [System.Collections.Generic.List[Object]]$report = @()
    $deleted = 0
    $deleteFailed = 0

    Write-Output "`nDUPLICATE INTUNE MANAGED-DEVICE RECORDS"
    Write-Output ("=" * 50)

    foreach ($group in $duplicateGroups) {
        $sorted = @($group.Group | Sort-Object -Property @{ Expression = { Get-EffectiveTimestamp -Device $_ } } -Descending)
        $keeper = $sorted[0]
        $stale = @($sorted | Select-Object -Skip 1)

        Write-Output "`nSerial: $($group.Name)"
        Write-Output "  KEEP:   $($keeper.deviceName) | last sync $($keeper.lastSyncDateTime) | $($keeper.userPrincipalName)"

        foreach ($staleDevice in $stale) {
            Write-Output "  REMOVE: $($staleDevice.deviceName) | last sync $($staleDevice.lastSyncDateTime) | $($staleDevice.userPrincipalName)"

            $action = "Reported"
            if ($Remove) {
                if ($PSCmdlet.ShouldProcess("$($staleDevice.deviceName) ($($staleDevice.id))", "Delete Intune device record")) {
                    try {
                        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($staleDevice.id)" -Method DELETE
                        Write-Output "    ✓ Deleted"
                        $action = "Deleted"
                        $deleted++
                    }
                    catch {
                        Write-Warning "    Failed to delete '$($staleDevice.deviceName)': $($_.Exception.Message)"
                        $action = "DeleteFailed"
                        $deleteFailed++
                    }
                }
                else {
                    $action = "Skipped"
                }
            }

            $report.Add([PSCustomObject]@{
                    SerialNumber   = $group.Name
                    DeviceName     = $staleDevice.deviceName
                    DeviceId       = $staleDevice.id
                    User           = $staleDevice.userPrincipalName
                    LastSync       = $staleDevice.lastSyncDateTime
                    KeptDeviceName = $keeper.deviceName
                    KeptDeviceId   = $keeper.id
                    Action         = $action
                })
        }
    }

    # Summary
    $totalStale = $report.Count
    Write-Output "`n"
    Write-Output ("=" * 50)
    Write-Output "Summary: $($duplicateGroups.Count) duplicate serials, $totalStale stale Intune managed-device records"
    if ($Remove) {
        Write-Output "Deleted: $deleted | Failed: $deleteFailed"
    }
    else {
        Write-Output "Run again with -Remove to delete the stale records (add -WhatIf for a dry run)"
    }
    Write-Output ("=" * 50)

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Duplicate_Device_Records_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Output "✓ CSV report saved: $csvPath"
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
