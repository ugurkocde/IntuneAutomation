<#
.TITLE
    Device Compliance Report

.SYNOPSIS
    Generate a comprehensive device compliance report for managed devices in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves managed devices and their compliance status,
    and generates a detailed report in both CSV and HTML formats. The report includes device details,
    compliance status, and summary statistics.

.TAGS
    Devices,Compliance,Reporting

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
    2025-05-29

.EXAMPLE
    .\get-device-compliance-report.ps1
    Generates compliance reports for all managed devices

.EXAMPLE
    .\get-device-compliance-report.ps1 -OutputPath "C:\Reports"
    Generates reports and saves them to the specified directory

.EXAMPLE
    .\get-device-compliance-report.ps1 -ForceModuleInstall
    Generates reports and forces module installation without prompting

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - Large tenants may take several minutes to complete
    - Reports are saved in both CSV and HTML formats
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
#>

[CmdletBinding()]
param(
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
        
        # Check if module is available
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
                # Local environment - attempt to install
                Write-Information "Module '$ModuleName' not found. Attempting to install..." -InformationAction Continue
                
                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }
                
                try {
                    # Check if running as administrator for AllUsers scope
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }
                    
                    Write-Information "Installing '$ModuleName' in scope '$scope'..." -InformationAction Continue
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }
        
        # Import the module
        try {
            Write-Verbose "Importing module: $ModuleName"
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Verbose "✓ Successfully imported '$ModuleName'"
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
        # Azure Automation - Use Managed Identity
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        # Local execution - Use interactive authentication
        Write-Information "Connecting to Microsoft Graph with interactive authentication..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All"
        )
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
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
            # Add delay to respect rate limits
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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting device compliance report generation..." -InformationAction Continue

    # Get all managed devices
    Write-Information "Retrieving managed devices..." -InformationAction Continue
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    Write-Information "✓ Found $($devices.Count) managed devices" -InformationAction Continue

    # Get compliance policies
    try {
        Write-Information "Retrieving compliance policies..." -InformationAction Continue
        $compliancePolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies"
        Write-Information "✓ Found $($compliancePolicies.Count) compliance policies" -InformationAction Continue
    }
    catch {
        Write-Warning "Could not retrieve compliance policies: $($_.Exception.Message)"
        $compliancePolicies = @()
    }

    # Create report array
    $report = @()
    $processedCount = 0

    Write-Information "Processing device compliance data..." -InformationAction Continue

    foreach ($device in $devices) {
        $processedCount++
        Write-Progress -Activity "Processing Devices" -Status "Processing device $processedCount of $($devices.Count)" -PercentComplete (($processedCount / $devices.Count) * 100)
        
        try {
            # Get device compliance details
            $complianceUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$($device.id)')/deviceCompliancePolicyStates"
            $deviceCompliance = Get-MgGraphAllPage -Uri $complianceUri
            
            # Calculate compliance summary
            $compliantPolicies = ($deviceCompliance | Where-Object { $_.state -eq "compliant" }).Count
            $nonCompliantPolicies = ($deviceCompliance | Where-Object { $_.state -eq "nonCompliant" }).Count
            $errorPolicies = ($deviceCompliance | Where-Object { $_.state -eq "error" }).Count
            $totalPolicies = $deviceCompliance.Count
            
            # Determine overall compliance status
            $overallCompliance = if ($nonCompliantPolicies -gt 0 -or $errorPolicies -gt 0) { 
                "Non-Compliant" 
            }
            elseif ($compliantPolicies -gt 0) { 
                "Compliant" 
            }
            else { 
                "Unknown" 
            }
            
            # Calculate days since last sync
            $daysSinceSync = if ($device.lastSyncDateTime) {
                [math]::Round(((Get-Date) - [DateTime]$device.lastSyncDateTime).TotalDays, 1)
            }
            else {
                "Never"
            }
            
            # Create device report object
            $deviceInfo = [PSCustomObject]@{
                DeviceName                              = $device.deviceName
                UserPrincipalName                       = $device.userPrincipalName
                UserDisplayName                         = $device.userDisplayName
                OperatingSystem                         = $device.operatingSystem
                OSVersion                               = $device.osVersion
                Model                                   = $device.model
                Manufacturer                            = $device.manufacturer
                SerialNumber                            = $device.serialNumber
                OverallCompliance                       = $overallCompliance
                CompliantPolicies                       = $compliantPolicies
                NonCompliantPolicies                    = $nonCompliantPolicies
                ErrorPolicies                           = $errorPolicies
                TotalPolicies                           = $totalPolicies
                LastSyncDateTime                        = $device.lastSyncDateTime
                DaysSinceLastSync                       = $daysSinceSync
                EnrolledDateTime                        = $device.enrolledDateTime
                ManagementState                         = $device.managementState
                OwnerType                               = $device.managedDeviceOwnerType
                ComplianceGracePeriodExpirationDateTime = $device.complianceGracePeriodExpirationDateTime
                DeviceId                                = $device.id
            }
            
            $report += $deviceInfo
            
        }
        catch {
            Write-Warning "Error processing device $($device.deviceName): $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Processing Devices" -Completed

    # Generate timestamp for file names
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $csvPath = Join-Path $OutputPath "Intune_Device_Compliance_Report_$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "Intune_Device_Compliance_Report_$timestamp.html"

    # Export to CSV
    try {
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to save CSV report: $($_.Exception.Message)"
    }

    # Generate HTML report
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Intune Device Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .summary-item { text-align: center; padding: 10px; background-color: #f8f9fa; border-radius: 4px; }
        .summary-number { font-size: 24px; font-weight: bold; color: #0078d4; }
        table { width: 100%; border-collapse: collapse; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px 12px; border-bottom: 1px solid #e1e5e9; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e3f2fd; }
        .compliant { color: #28a745; font-weight: bold; }
        .non-compliant { color: #dc3545; font-weight: bold; }
        .unknown { color: #6c757d; font-weight: bold; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Intune Device Compliance Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-number">$($report.Count)</div>
                <div>Total Devices</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$(($report | Where-Object { $_.OverallCompliance -eq 'Compliant' }).Count)</div>
                <div>Compliant Devices</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$(($report | Where-Object { $_.OverallCompliance -eq 'Non-Compliant' }).Count)</div>
                <div>Non-Compliant Devices</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$(($report | Where-Object { $_.DaysSinceLastSync -ne 'Never' -and [double]$_.DaysSinceLastSync -gt 7 }).Count)</div>
                <div>Stale Devices (>7 days)</div>
            </div>
        </div>
    </div>
"@

        # Add table
        $htmlContent += "<table><thead><tr>"
        $htmlContent += "<th>Device Name</th><th>User</th><th>OS</th><th>Compliance Status</th><th>Compliant Policies</th><th>Non-Compliant Policies</th><th>Last Sync</th><th>Days Since Sync</th>"
        $htmlContent += "</tr></thead><tbody>"
        
        foreach ($device in $report | Sort-Object DeviceName) {
            $complianceClass = switch ($device.OverallCompliance) {
                "Compliant" { "compliant" }
                "Non-Compliant" { "non-compliant" }
                default { "unknown" }
            }
            
            $htmlContent += "<tr>"
            $htmlContent += "<td>$($device.DeviceName)</td>"
            $htmlContent += "<td>$($device.UserDisplayName)</td>"
            $htmlContent += "<td>$($device.OperatingSystem) $($device.OSVersion)</td>"
            $htmlContent += "<td class='$complianceClass'>$($device.OverallCompliance)</td>"
            $htmlContent += "<td>$($device.CompliantPolicies)</td>"
            $htmlContent += "<td>$($device.NonCompliantPolicies)</td>"
            $htmlContent += "<td>$($device.LastSyncDateTime)</td>"
            $htmlContent += "<td>$($device.DaysSinceLastSync)</td>"
            $htmlContent += "</tr>"
        }
        
        $htmlContent += "</tbody></table>"
        $htmlContent += "<div class='footer'>Report generated by Intune Device Compliance Script v1.0</div>"
        $htmlContent += "</body></html>"
        
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Information "✓ HTML report saved: $htmlPath" -InformationAction Continue
        
        if ($OpenReport -and -not $IsAzureAutomation) {
            Start-Process $htmlPath
        }
        
    }
    catch {
        Write-Error "Failed to generate HTML report: $($_.Exception.Message)"
    }

    # Display summary
    Write-Information "`n" -InformationAction Continue
    Write-Information "📊 COMPLIANCE REPORT SUMMARY" -InformationAction Continue
    Write-Information "================================" -InformationAction Continue
    Write-Information "Total Devices: $($report.Count)" -InformationAction Continue
    Write-Information "Compliant Devices: $(($report | Where-Object { $_.OverallCompliance -eq 'Compliant' }).Count)" -InformationAction Continue
    Write-Information "Non-Compliant Devices: $(($report | Where-Object { $_.OverallCompliance -eq 'Non-Compliant' }).Count)" -InformationAction Continue
    Write-Information "Unknown Status: $(($report | Where-Object { $_.OverallCompliance -eq 'Unknown' }).Count)" -InformationAction Continue
    Write-Information "Stale Devices (>7 days): $(($report | Where-Object { $_.DaysSinceLastSync -ne 'Never' -and [double]$_.DaysSinceLastSync -gt 7 }).Count)" -InformationAction Continue

    Write-Information "`nReports saved to:" -InformationAction Continue
    Write-Information "📄 CSV: $csvPath" -InformationAction Continue
    Write-Information "🌐 HTML: $htmlPath" -InformationAction Continue

    Write-Information "`n🎉 Device compliance report generation completed successfully!" -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Ignore disconnection errors - this is expected behavior when already disconnected
        Write-Verbose "Graph disconnection completed (may have already been disconnected)"
    }
} 