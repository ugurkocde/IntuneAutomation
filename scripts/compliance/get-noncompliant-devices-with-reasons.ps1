<#
.TITLE
    Non-Compliant Devices with Reasons Report

.SYNOPSIS
    Identify all non-compliant devices in Intune and the specific setting(s) that caused each failure.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves every managed device whose compliance state
    is non-compliant (and optionally error / in grace period), then drills into each device's
    compliance policy states and the underlying setting states to surface the exact reason a device
    is non-compliant. For every failing setting it reports the owning policy, the setting name, the
    reported state, the current value, and any error code/description. Results are exported to both
    CSV (one row per failing setting) and a summary HTML report.

.TAGS
    Compliance,Devices,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.1

.CHANGELOG
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing); report auto-open failures no longer abort the script
    1.0 - Initial release

.LASTUPDATE
    2026-07-19

.EXAMPLE
    .\get-noncompliant-devices-with-reasons.ps1
    Reports all non-compliant devices and the settings that caused the failure

.EXAMPLE
    .\get-noncompliant-devices-with-reasons.ps1 -ComplianceStates noncompliant,error,inGracePeriod
    Includes devices in error and grace-period states in addition to non-compliant ones

.EXAMPLE
    .\get-noncompliant-devices-with-reasons.ps1 -OutputPath "C:\Reports" -OpenReport
    Saves the reports to the specified directory and opens the HTML report when finished

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Entra ID
    - Uses the Microsoft Graph beta endpoint to retrieve setting-level compliance detail
    - The CSV contains one row per failing setting; a device with multiple reasons appears on multiple rows
    - Devices flagged non-compliant with no setting-level detail (e.g. recently enrolled or not yet
      evaluated) are reported with a placeholder reason so they are not silently dropped
    - Large tenants may take several minutes: the script makes additional Graph calls per device
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Compliance states to include in the report")]
    [ValidateSet("noncompliant", "error", "inGracePeriod", "conflict", "unknown")]
    [string[]]$ComplianceStates = @("noncompliant"),

    [Parameter(Mandatory = $false, HelpMessage = "Output directory for the reports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Open the HTML report after generation")]
    [switch]$OpenReport,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall
)

# ============================================================================
# ENVIRONMENT DETECTION AND SETUP
# ============================================================================

function Initialize-RequiredModule {
    <#
    .SYNOPSIS
    Ensures required modules are available and loaded
    #>
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
                $errorMessage = @"
Module '$ModuleName' is not available in this Azure Automation Account.

To resolve this issue:
1. Go to Azure Portal
2. Navigate to your Automation Account
3. Go to 'Modules' > 'Browse Gallery'
4. Search for '$ModuleName'
5. Click 'Import' and wait for installation to complete

Alternative: Use PowerShell to import the module:
Import-Module Az.Automation
Import-AzAutomationModule -AutomationAccountName "YourAccount" -ResourceGroupName "YourRG" -Name "$ModuleName"
"@
                throw $errorMessage
            }
            else {
                Write-Information "Module '$ModuleName' not found. Attempting to install..." -InformationAction Continue

                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }

                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

                    Write-Information "Installing '$ModuleName' in scope '$scope'..." -InformationAction Continue
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }

        try {
            Write-Verbose "Importing module: $ModuleName"
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Verbose "Successfully imported '$ModuleName'"
        }
        catch {
            throw "Failed to import module '$ModuleName': $($_.Exception.Message)"
        }
    }
}

# Detect execution environment
if ($PSPrivateMetadata.JobId.Guid) {
    Write-Output "Running inside Azure Automation Runbook"
    $IsAzureAutomation = $true
}
else {
    Write-Information "Running locally in IDE or terminal" -InformationAction Continue
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

try {
    Initialize-RequiredModule -ModuleNames $RequiredModules -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
    Write-Verbose "All required modules are available"
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
        Write-Output "Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        Write-Information "Connecting to Microsoft Graph with interactive authentication..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Information "Successfully connected to Microsoft Graph" -InformationAction Continue
    }
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API
function Get-MgGraphAllPage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $AllResults = @()
    $NextLink = $Uri
    $RequestCount = 0

    do {
        try {
            if ($RequestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $Response = Invoke-MgGraphRequest -Uri $NextLink -Method GET
            $RequestCount++

            if ($Response.value) {
                $AllResults += $Response.value
            }
            else {
                $AllResults += $Response
            }

            $NextLink = $Response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
        }
    } while ($NextLink)

    return $AllResults
}

# HTML-encode a value for safe rendering in the report
function ConvertTo-HtmlSafe {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [System.Web.HttpUtility]::HtmlEncode([string]$Value)
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting non-compliant device reason report..." -InformationAction Continue

    # Load System.Web for HTML encoding (available in Windows PowerShell and PowerShell 7+)
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    # Build a server-side filter for the requested compliance states
    $filterClause = ($ComplianceStates | ForEach-Object { "complianceState eq '$_'" }) -join " or "
    $deviceSelect = "id,deviceName,operatingSystem,osVersion,complianceState,userPrincipalName,userDisplayName,managedDeviceOwnerType,lastSyncDateTime,complianceGracePeriodExpirationDateTime"
    $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=$filterClause&`$select=$deviceSelect"

    Write-Information "Retrieving devices in state(s): $($ComplianceStates -join ', ')..." -InformationAction Continue
    $devices = Get-MgGraphAllPage -Uri $devicesUri
    Write-Information "Found $($devices.Count) device(s) matching the requested compliance state(s)" -InformationAction Continue

    $report = @()
    $processedCount = 0

    foreach ($device in $devices) {
        $processedCount++
        Write-Progress -Activity "Analyzing non-compliant devices" -Status "Device $processedCount of $($devices.Count): $($device.deviceName)" -PercentComplete (($processedCount / [math]::Max($devices.Count, 1)) * 100)

        # Common device fields reused for every emitted row
        $gracePeriodExpiry = if ($device.complianceGracePeriodExpirationDateTime) {
            $device.complianceGracePeriodExpirationDateTime
        }
        else { $null }

        try {
            $policyStatesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')/deviceCompliancePolicyStates"
            $policyStates = Get-MgGraphAllPage -Uri $policyStatesUri

            # Only the policies that are not compliant contribute reasons
            $failingPolicies = $policyStates | Where-Object { $_.state -ne "compliant" -and $_.state -ne "notApplicable" }

            $deviceReasonCount = 0

            foreach ($policy in $failingPolicies) {
                try {
                    $settingStatesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')/deviceCompliancePolicyStates/$($policy.id)/settingStates"
                    $settingStates = Get-MgGraphAllPage -Uri $settingStatesUri

                    # Surface only the settings that actually failed
                    $failingSettings = $settingStates | Where-Object { $_.state -ne "compliant" -and $_.state -ne "notApplicable" }

                    foreach ($setting in $failingSettings) {
                        $deviceReasonCount++

                        # settingName is frequently null on beta; fall back to the setting identifier
                        $reason = if (-not [string]::IsNullOrWhiteSpace($setting.settingName)) {
                            $setting.settingName
                        }
                        else {
                            $setting.setting
                        }

                        $sourcePolicy = if ($setting.sources -and $setting.sources.Count -gt 0) {
                            ($setting.sources | ForEach-Object { $_.displayName } | Where-Object { $_ } | Select-Object -Unique) -join "; "
                        }
                        else {
                            $policy.displayName
                        }

                        $report += [PSCustomObject]@{
                            DeviceName              = $device.deviceName
                            UserPrincipalName       = $device.userPrincipalName
                            UserDisplayName         = $device.userDisplayName
                            OperatingSystem         = $device.operatingSystem
                            OSVersion               = $device.osVersion
                            OwnerType               = $device.managedDeviceOwnerType
                            DeviceComplianceState   = $device.complianceState
                            PolicyName              = $sourcePolicy
                            PolicyState             = $policy.state
                            Reason                  = $reason
                            SettingId               = $setting.setting
                            SettingState            = $setting.state
                            CurrentValue            = $setting.currentValue
                            ErrorCode               = $setting.errorCode
                            ErrorDescription        = $setting.errorDescription
                            GracePeriodExpiration   = $gracePeriodExpiry
                            LastSyncDateTime        = $device.lastSyncDateTime
                            DeviceId                = $device.id
                        }
                    }
                }
                catch {
                    Write-Warning "Error retrieving setting states for device '$($device.deviceName)' policy '$($policy.displayName)': $($_.Exception.Message)"
                }
            }

            # Device is flagged but no setting-level reason was returned - do not drop it silently
            if ($deviceReasonCount -eq 0) {
                $report += [PSCustomObject]@{
                    DeviceName              = $device.deviceName
                    UserPrincipalName       = $device.userPrincipalName
                    UserDisplayName         = $device.userDisplayName
                    OperatingSystem         = $device.operatingSystem
                    OSVersion               = $device.osVersion
                    OwnerType               = $device.managedDeviceOwnerType
                    DeviceComplianceState   = $device.complianceState
                    PolicyName              = "(none reported)"
                    PolicyState             = ($failingPolicies | Select-Object -First 1 -ExpandProperty state -ErrorAction SilentlyContinue)
                    Reason                  = "No setting-level detail reported (device may be recently enrolled, in grace period, or not yet evaluated)"
                    SettingId               = ""
                    SettingState            = ""
                    CurrentValue            = ""
                    ErrorCode               = ""
                    ErrorDescription        = ""
                    GracePeriodExpiration   = $gracePeriodExpiry
                    LastSyncDateTime        = $device.lastSyncDateTime
                    DeviceId                = $device.id
                }
            }
        }
        catch {
            Write-Warning "Error processing device '$($device.deviceName)': $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Analyzing non-compliant devices" -Completed

    # Generate timestamp for file names
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $csvPath = Join-Path $OutputPath "Intune_NonCompliant_Devices_Reasons_$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "Intune_NonCompliant_Devices_Reasons_$timestamp.html"

    # Export to CSV
    try {
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "CSV report saved: $csvPath" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to save CSV report: $($_.Exception.Message)"
    }

    # Summary metrics
    $distinctDevices = ($report | Select-Object -ExpandProperty DeviceId -Unique).Count
    $totalReasons = ($report | Where-Object { $_.SettingId -ne "" }).Count

    # Top reasons across the estate
    $topReasons = $report |
        Where-Object { $_.SettingId -ne "" } |
        Group-Object Reason |
        Sort-Object Count -Descending |
        Select-Object -First 10

    # Generate HTML report
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Intune Non-Compliant Devices - Reasons Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .summary-item { text-align: center; padding: 10px; background-color: #f8f9fa; border-radius: 4px; }
        .summary-number { font-size: 24px; font-weight: bold; color: #dc3545; }
        h2 { color: #323130; }
        table { width: 100%; border-collapse: collapse; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 24px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px 12px; border-bottom: 1px solid #e1e5e9; vertical-align: top; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #fdeaea; }
        .state-noncompliant { color: #dc3545; font-weight: bold; }
        .state-error { color: #b35900; font-weight: bold; }
        .reason { font-family: 'Consolas', 'Courier New', monospace; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Intune Non-Compliant Devices - Reasons Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
        <p>States included: $([System.Web.HttpUtility]::HtmlEncode(($ComplianceStates -join ', ')))</p>
    </div>

    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-number">$distinctDevices</div>
                <div>Affected Devices</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$totalReasons</div>
                <div>Total Failing Settings</div>
            </div>
        </div>
    </div>
"@

        # Top reasons table
        if ($topReasons) {
            $htmlContent += "<h2>Top Non-Compliance Reasons</h2>"
            $htmlContent += "<table><thead><tr><th>Reason / Setting</th><th>Device Count</th></tr></thead><tbody>"
            foreach ($r in $topReasons) {
                $htmlContent += "<tr><td class='reason'>$(ConvertTo-HtmlSafe $r.Name)</td><td>$($r.Count)</td></tr>"
            }
            $htmlContent += "</tbody></table>"
        }

        # Detail table
        $htmlContent += "<h2>Detail - One Row per Failing Setting</h2>"
        $htmlContent += "<table><thead><tr>"
        $htmlContent += "<th>Device</th><th>User</th><th>OS</th><th>Policy</th><th>Reason / Setting</th><th>State</th><th>Current Value</th><th>Error</th>"
        $htmlContent += "</tr></thead><tbody>"

        foreach ($row in $report | Sort-Object DeviceName, PolicyName, Reason) {
            $stateClass = switch ($row.SettingState) {
                "nonCompliant" { "state-noncompliant" }
                "error" { "state-error" }
                default { "" }
            }
            $errorText = if ($row.ErrorCode -and $row.ErrorCode -ne 0) { "$($row.ErrorCode): $($row.ErrorDescription)" } else { "" }

            $htmlContent += "<tr>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe $row.DeviceName)</td>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe $row.UserPrincipalName)</td>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe ("{0} {1}" -f $row.OperatingSystem, $row.OSVersion))</td>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe $row.PolicyName)</td>"
            $htmlContent += "<td class='reason'>$(ConvertTo-HtmlSafe $row.Reason)</td>"
            $htmlContent += "<td class='$stateClass'>$(ConvertTo-HtmlSafe $row.SettingState)</td>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe $row.CurrentValue)</td>"
            $htmlContent += "<td>$(ConvertTo-HtmlSafe $errorText)</td>"
            $htmlContent += "</tr>"
        }

        $htmlContent += "</tbody></table>"
        $htmlContent += "<div class='footer'>Report generated by Intune Non-Compliant Devices with Reasons Script v1.0</div>"
        $htmlContent += "</body></html>"

        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Information "HTML report saved: $htmlPath" -InformationAction Continue

        if ($OpenReport -and -not $IsAzureAutomation) {
            try {
                Start-Process $htmlPath
            }
            catch {
                Write-Warning "Could not open the report automatically: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Error "Failed to generate HTML report: $($_.Exception.Message)"
    }

    # Display summary
    Write-Information "`n" -InformationAction Continue
    Write-Information "NON-COMPLIANT DEVICE REASON SUMMARY" -InformationAction Continue
    Write-Information "====================================" -InformationAction Continue
    Write-Information "States included: $($ComplianceStates -join ', ')" -InformationAction Continue
    Write-Information "Affected devices: $distinctDevices" -InformationAction Continue
    Write-Information "Total failing settings: $totalReasons" -InformationAction Continue

    if ($topReasons) {
        Write-Information "`nTop reasons:" -InformationAction Continue
        foreach ($r in $topReasons) {
            Write-Information ("  {0,-4} {1}" -f $r.Count, $r.Name) -InformationAction Continue
        }
    }

    Write-Information "`nReports saved to:" -InformationAction Continue
    Write-Information "CSV:  $csvPath" -InformationAction Continue
    Write-Information "HTML: $htmlPath" -InformationAction Continue

    Write-Information "`nNon-compliant device reason report completed successfully." -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed (may have already been disconnected)"
    }
}
