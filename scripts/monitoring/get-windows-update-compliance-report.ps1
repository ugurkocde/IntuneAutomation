<#
.TITLE
    Get Windows Update Compliance Report

.SYNOPSIS
    Reports Windows Update deployment state: update rings with per-device status, feature update profiles, quality and driver update profiles.

.DESCRIPTION
    This script inventories the tenant's Windows Update configuration and its
    deployment health: update rings (Windows Update for Business configurations)
    with per-device success and error status, feature update profiles with their
    target version and end-of-support date, expedited quality update profiles, and
    driver update profiles. It flags rings with device errors, feature update
    targets approaching end of support, and profiles without assignments.

.TAGS
    Monitoring,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.2

.CHANGELOG
    1.2 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.1 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\get-windows-update-compliance-report.ps1
    Reports update rings, feature updates, quality and driver update profiles

.EXAMPLE
    .\get-windows-update-compliance-report.ps1 -EndOfSupportWarningDays 120 -ExportToCsv "true"
    Flags feature update targets within 120 days of end of support and exports to CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Update rings are deviceConfigurations of type windowsUpdateForBusinessConfiguration; per-device status comes from each ring's deviceStatuses
    - This reports deployment state from Intune's perspective; per-device patch level detail lives in Windows Update for Business reports (Log Analytics)
    - Uses beta Graph endpoints because feature/quality/driver update profiles are not exposed on v1.0
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Days before feature update end-of-support to raise a warning")]
    [ValidateRange(1, 730)]
    [int]$EndOfSupportWarningDays = 180,

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
Remove-Variable -Name ForceModuleInstall
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
foreach ($runbookBooleanParameter in @('ExportToCsv')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)
    Remove-Variable -Name $runbookBooleanParameter

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
            "DeviceManagementConfiguration.Read.All"
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

            if ($null -ne $response.value) {
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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    [System.Collections.Generic.List[Object]]$report = @()

    # ----- Update rings -----
    Write-Output "Retrieving update rings..."
    $allConfigurations = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"
    $updateRings = @($allConfigurations | Where-Object { $_.'@odata.type' -like "*windowsUpdateForBusinessConfiguration" })
    Write-Output "✓ Found $($updateRings.Count) update rings"

    foreach ($ring in $updateRings) {
        # Per-device deployment status for the ring
        $deviceStatuses = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($ring.id)/deviceStatuses"
        $statusGroups = @($deviceStatuses) | Group-Object -Property status

        $successCount = 0
        $errorCount = 0
        $otherCount = 0
        foreach ($group in $statusGroups) {
            switch ($group.Name) {
                { $_ -in @("compliant", "succeeded") } { $successCount += $group.Count }
                { $_ -in @("error", "conflict", "nonCompliant") } { $errorCount += $group.Count }
                default { $otherCount += $group.Count }
            }
        }

        $report.Add([PSCustomObject]@{
                Area          = "Update Ring"
                Name          = $ring.displayName
                Detail        = "Quality deferral: $($ring.qualityUpdatesDeferralPeriodInDays)d | Feature deferral: $($ring.featureUpdatesDeferralPeriodInDays)d"
                IsAssigned    = (@($ring.assignments).Count -gt 0)
                DeviceSuccess = $successCount
                DeviceErrors  = $errorCount
                DeviceOther   = $otherCount
                Flag          = if ($errorCount -gt 0) { "DeviceErrors" } elseif (@($ring.assignments).Count -eq 0) { "NotAssigned" } else { "" }
            })
    }

    # ----- Feature update profiles -----
    Write-Output "Retrieving feature update profiles..."
    $featureProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?`$expand=assignments"
    Write-Output "✓ Found $(@($featureProfiles).Count) feature update profiles"

    foreach ($featureProfile in $featureProfiles) {
        $endOfSupport = if ($featureProfile.endOfSupportDate) { [DateTime]::Parse($featureProfile.endOfSupportDate.ToString()) } else { $null }
        $daysToEos = if ($endOfSupport) { [math]::Round(($endOfSupport - (Get-Date)).TotalDays, 0) } else { $null }

        $flag = ""
        if (@($featureProfile.assignments).Count -eq 0) { $flag = "NotAssigned" }
        elseif ($null -ne $daysToEos -and $daysToEos -lt 0) { $flag = "PastEndOfSupport" }
        elseif ($null -ne $daysToEos -and $daysToEos -le $EndOfSupportWarningDays) { $flag = "NearEndOfSupport" }

        $detail = "Target: $($featureProfile.featureUpdateVersion)"
        if ($null -ne $daysToEos) { $detail += " | end of support in $daysToEos days" }

        $report.Add([PSCustomObject]@{
                Area          = "Feature Update"
                Name          = $featureProfile.displayName
                Detail        = $detail
                IsAssigned    = (@($featureProfile.assignments).Count -gt 0)
                DeviceSuccess = ""
                DeviceErrors  = ""
                DeviceOther   = ""
                Flag          = $flag
            })
    }

    # ----- Quality update profiles (expedite) -----
    Write-Output "Retrieving quality update profiles..."
    $qualityProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles?`$expand=assignments"
    Write-Output "✓ Found $(@($qualityProfiles).Count) quality update profiles"

    foreach ($qualityProfile in $qualityProfiles) {
        $report.Add([PSCustomObject]@{
                Area          = "Quality Update (Expedite)"
                Name          = $qualityProfile.displayName
                Detail        = "Release: $($qualityProfile.expeditedUpdateSettings.qualityUpdateRelease)"
                IsAssigned    = (@($qualityProfile.assignments).Count -gt 0)
                DeviceSuccess = ""
                DeviceErrors  = ""
                DeviceOther   = ""
                Flag          = if (@($qualityProfile.assignments).Count -eq 0) { "NotAssigned" } else { "" }
            })
    }

    # ----- Driver update profiles -----
    Write-Output "Retrieving driver update profiles..."
    $driverProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles?`$expand=assignments"
    Write-Output "✓ Found $(@($driverProfiles).Count) driver update profiles"

    foreach ($driverProfile in $driverProfiles) {
        $report.Add([PSCustomObject]@{
                Area          = "Driver Update"
                Name          = $driverProfile.displayName
                Detail        = "Approval: $($driverProfile.approvalType) | new drivers pending: $($driverProfile.newUpdates)"
                IsAssigned    = (@($driverProfile.assignments).Count -gt 0)
                DeviceSuccess = ""
                DeviceErrors  = ""
                DeviceOther   = ""
                Flag          = if (@($driverProfile.assignments).Count -eq 0) { "NotAssigned" } elseif ([int]$driverProfile.newUpdates -gt 0) { "DriversPendingApproval" } else { "" }
            })
    }

    # ----- Display results -----
    Write-Output "`nWINDOWS UPDATE COMPLIANCE REPORT"
    Write-Output ("=" * 50)
    Write-Output "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output ("=" * 50)

    foreach ($areaGroup in ($report | Group-Object -Property Area)) {
        Write-Output "`n$($areaGroup.Name) ($($areaGroup.Count)):"
        foreach ($row in ($areaGroup.Group | Sort-Object Name)) {
            $assignedLabel = if ($row.IsAssigned) { "assigned" } else { "NOT ASSIGNED" }
            $line = "  $($row.Name) [$assignedLabel]"
            if ($row.Flag) { $line += " [$($row.Flag)]" }
            Write-Output $line
            Write-Output "    $($row.Detail)"
            if ($row.Area -eq "Update Ring") {
                Write-Output "    Devices: $($row.DeviceSuccess) ok, $($row.DeviceErrors) errors, $($row.DeviceOther) other"
            }
        }
    }

    if ($report.Count -eq 0) {
        Write-Output "`nNo Windows Update configuration found in this tenant."
    }

    # Summary
    $flaggedRows = @($report | Where-Object { $_.Flag })
    Write-Output "`n"
    Write-Output ("=" * 50)
    Write-Output "Summary: $($report.Count) update deployment objects | $($flaggedRows.Count) flagged"
    foreach ($row in $flaggedRows) {
        Write-Output "  [$($row.Flag)] $($row.Area): $($row.Name)"
    }
    Write-Output ("=" * 50)

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Windows_Update_Compliance_$timestamp.csv"
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
