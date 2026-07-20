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
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-windows-update-compliance-report.ps1
    Reports update rings, feature updates, quality and driver update profiles

.EXAMPLE
    .\get-windows-update-compliance-report.ps1 -EndOfSupportWarningDays 120 -ExportToCsv
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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    [System.Collections.Generic.List[Object]]$report = @()

    # ----- Update rings -----
    Write-Information "Retrieving update rings..." -InformationAction Continue
    $allConfigurations = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"
    $updateRings = @($allConfigurations | Where-Object { $_.'@odata.type' -like "*windowsUpdateForBusinessConfiguration" })
    Write-Information "✓ Found $($updateRings.Count) update rings" -InformationAction Continue

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
    Write-Information "Retrieving feature update profiles..." -InformationAction Continue
    $featureProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?`$expand=assignments"
    Write-Information "✓ Found $(@($featureProfiles).Count) feature update profiles" -InformationAction Continue

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
    Write-Information "Retrieving quality update profiles..." -InformationAction Continue
    $qualityProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles?`$expand=assignments"
    Write-Information "✓ Found $(@($qualityProfiles).Count) quality update profiles" -InformationAction Continue

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
    Write-Information "Retrieving driver update profiles..." -InformationAction Continue
    $driverProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles?`$expand=assignments"
    Write-Information "✓ Found $(@($driverProfiles).Count) driver update profiles" -InformationAction Continue

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
    Write-Information "`nWINDOWS UPDATE COMPLIANCE REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    foreach ($areaGroup in ($report | Group-Object -Property Area)) {
        Write-Information "`n$($areaGroup.Name) ($($areaGroup.Count)):" -InformationAction Continue
        foreach ($row in ($areaGroup.Group | Sort-Object Name)) {
            $assignedLabel = if ($row.IsAssigned) { "assigned" } else { "NOT ASSIGNED" }
            $line = "  $($row.Name) [$assignedLabel]"
            if ($row.Flag) { $line += " [$($row.Flag)]" }
            Write-Information $line -InformationAction Continue
            Write-Information "    $($row.Detail)" -InformationAction Continue
            if ($row.Area -eq "Update Ring") {
                Write-Information "    Devices: $($row.DeviceSuccess) ok, $($row.DeviceErrors) errors, $($row.DeviceOther) other" -InformationAction Continue
            }
        }
    }

    if ($report.Count -eq 0) {
        Write-Information "`nNo Windows Update configuration found in this tenant." -InformationAction Continue
    }

    # Summary
    $flaggedRows = @($report | Where-Object { $_.Flag })
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) update deployment objects | $($flaggedRows.Count) flagged" -InformationAction Continue
    foreach ($row in $flaggedRows) {
        Write-Information "  [$($row.Flag)] $($row.Area): $($row.Name)" -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Windows_Update_Compliance_$timestamp.csv"
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
