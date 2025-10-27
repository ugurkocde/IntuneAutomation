<#
.TITLE
    Application Installation Status Report

.SYNOPSIS
    Generate a comprehensive application installation status report for all managed applications in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves all managed applications and their installation status
    across all devices, and generates detailed reports in both CSV and HTML formats. The report includes
    installation state (installed, pending, failed, not applicable), error codes, device details,
    and summary statistics to help identify and troubleshoot application deployment issues.

.TAGS
    Apps,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-09-29

.EXAMPLE
    .\get-app-installation-status-report.ps1
    Generates application installation status report for all applications

.EXAMPLE
    .\get-app-installation-status-report.ps1 -FilterByInstallState "failed"
    Generates report showing only failed application installations

.EXAMPLE
    .\get-app-installation-status-report.ps1 -FilterByPlatform "Windows" -OutputPath "C:\Reports"
    Generates report for Windows applications and saves to specified directory

.EXAMPLE
    .\get-app-installation-status-report.ps1 -FilterByAppName "Microsoft 365" -OpenReport
    Generates report filtered by application name and opens the HTML report

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Requires appropriate permissions in Azure AD
    - Large tenants may take considerable time to complete due to API rate limits
    - Reports are saved in both CSV and HTML formats
    - Uses beta endpoint for comprehensive installation status data
    - Supports filtering by install state (installed, pending, failed, notApplicable)
    - Supports filtering by platform (Windows, iOS, Android, macOS)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "installed", "failed", "pending", "notApplicable", "error")]
    [string]$FilterByInstallState = "all",

    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "Windows", "iOS", "Android", "macOS")]
    [string]$FilterByPlatform = "all",

    [Parameter(Mandatory = $false)]
    [string]$FilterByAppName = "",

    [Parameter(Mandatory = $false)]
    [switch]$OpenReport,

    [Parameter(Mandatory = $false)]
    [int]$MaxApps = 0,

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
            "DeviceManagementApps.Read.All",
            "DeviceManagementManagedDevices.Read.All"
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

# Function to get all pages of results with rate limiting
function Get-MgGraphAllPage {
    param(
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $allResults = @()
    $nextLink = $Uri
    $requestCount = 0

    do {
        try {
            # Add delay to respect rate limits
            if ($requestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            $requestCount++

            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }

            $nextLink = $response.'@odata.nextLink'

            # Show progress for large datasets
            if ($requestCount % 10 -eq 0) {
                Write-Verbose "Fetched $($allResults.Count) items so far..."
            }
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $nextLink : $($_.Exception.Message)"
            break
        }
    } while ($nextLink)

    return $allResults
}

# Function to map install state codes to human-readable status
function Get-InstallStateDisplay {
    param([string]$State)

    switch ($State) {
        "installed" { return "Installed" }
        "failed" { return "Failed" }
        "notApplicable" { return "Not Applicable" }
        "unknown" { return "Unknown" }
        "available" { return "Available" }
        "notInstalled" { return "Not Installed" }
        "uninstallFailed" { return "Uninstall Failed" }
        "pendingInstall" { return "Pending Install" }
        default { return $State }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting application installation status report generation..." -InformationAction Continue

    # Get all mobile apps
    Write-Information "Retrieving managed applications..." -InformationAction Continue
    $appsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

    if ($MaxApps -gt 0) {
        $appsUri += "?`$top=$MaxApps"
    }

    $allApps = Get-MgGraphAllPage -Uri $appsUri

    # Filter apps if needed
    if ($FilterByAppName) {
        $allApps = $allApps | Where-Object { $_.displayName -like "*$FilterByAppName*" }
    }

    Write-Information "✓ Found $($allApps.Count) managed applications" -InformationAction Continue

    # Create installation status collection
    $installationStatusList = @()
    $processedApps = 0

    Write-Information "Processing application installation status..." -InformationAction Continue

    foreach ($app in $allApps) {
        $processedApps++
        Write-Progress -Activity "Processing Application Installation Status" -Status "Processing app $processedApps of $($allApps.Count): $($app.displayName)" -PercentComplete (($processedApps / $allApps.Count) * 100)

        try {
            # Get device statuses for this app using the beta endpoint
            $deviceStatusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/deviceStatuses"
            $deviceStatuses = Get-MgGraphAllPage -Uri $deviceStatusUri

            foreach ($status in $deviceStatuses) {
                # Apply filters
                if ($FilterByInstallState -ne "all" -and $status.installState -ne $FilterByInstallState) {
                    continue
                }

                # Skip if no device name (orphaned status)
                if (-not $status.deviceName) {
                    continue
                }

                # Create status entry
                $statusEntry = [PSCustomObject]@{
                    ApplicationName       = $app.displayName
                    ApplicationId         = $app.id
                    ApplicationType       = $app.'@odata.type' -replace '#microsoft.graph.', ''
                    Publisher             = if ($app.publisher) { $app.publisher } else { "Unknown" }
                    DeviceName            = $status.deviceName
                    DeviceId              = $status.deviceId
                    UserName              = $status.userName
                    UserPrincipalName     = $status.userPrincipalName
                    Platform              = $status.platform
                    InstallState          = Get-InstallStateDisplay -State $status.installState
                    InstallStateRaw       = $status.installState
                    InstallStateDetail    = if ($status.installStateDetail) { $status.installStateDetail } else { "N/A" }
                    ErrorCode             = if ($status.errorCode) { $status.errorCode } else { "N/A" }
                    LastModifiedDateTime  = $status.lastSyncDateTime
                    AppVersion            = if ($status.appVersion) { $status.appVersion } else { "Unknown" }
                    OSVersion             = if ($status.osVersion) { $status.osVersion } else { "Unknown" }
                    OSDescription         = if ($status.osDescription) { $status.osDescription } else { "Unknown" }
                }

                # Apply platform filter
                if ($FilterByPlatform -ne "all" -and $statusEntry.Platform -ne $FilterByPlatform) {
                    continue
                }

                $installationStatusList += $statusEntry
            }

            # Add small delay to respect rate limits
            Start-Sleep -Milliseconds 200
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                $processedApps--
                continue
            }
            Write-Warning "Error processing app $($app.displayName): $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "Processing Application Installation Status" -Completed

    if ($installationStatusList.Count -eq 0) {
        Write-Warning "No installation status records found matching the specified filters."
        Write-Information "Try adjusting your filter parameters or check if applications are deployed to devices." -InformationAction Continue
        Disconnect-MgGraph | Out-Null
        exit 0
    }

    # Generate summary statistics
    $totalInstallations = $installationStatusList.Count
    $successfulInstalls = ($installationStatusList | Where-Object { $_.InstallStateRaw -eq "installed" }).Count
    $failedInstalls = ($installationStatusList | Where-Object { $_.InstallStateRaw -eq "failed" }).Count
    $pendingInstalls = ($installationStatusList | Where-Object { $_.InstallStateRaw -like "*pending*" }).Count
    $uniqueApps = ($installationStatusList | Group-Object ApplicationName).Count
    $uniqueDevices = ($installationStatusList | Group-Object DeviceName).Count

    $successRate = if ($totalInstallations -gt 0) { [math]::Round(($successfulInstalls / $totalInstallations) * 100, 2) } else { 0 }
    $failureRate = if ($totalInstallations -gt 0) { [math]::Round(($failedInstalls / $totalInstallations) * 100, 2) } else { 0 }

    # Get top failed apps
    $topFailedApps = $installationStatusList |
        Where-Object { $_.InstallStateRaw -eq "failed" } |
        Group-Object ApplicationName |
        ForEach-Object {
            [PSCustomObject]@{
                ApplicationName = $_.Name
                FailureCount    = $_.Count
                UniqueDevices   = ($_.Group | Group-Object DeviceName).Count
            }
        } |
        Sort-Object FailureCount -Descending |
        Select-Object -First 10

    # Get installation status by platform
    $statusByPlatform = $installationStatusList |
        Group-Object Platform |
        ForEach-Object {
            $platformData = $_.Group
            [PSCustomObject]@{
                Platform    = $_.Name
                Total       = $platformData.Count
                Installed   = ($platformData | Where-Object { $_.InstallStateRaw -eq "installed" }).Count
                Failed      = ($platformData | Where-Object { $_.InstallStateRaw -eq "failed" }).Count
                Pending     = ($platformData | Where-Object { $_.InstallStateRaw -like "*pending*" }).Count
                SuccessRate = if ($platformData.Count -gt 0) { [math]::Round((($platformData | Where-Object { $_.InstallStateRaw -eq "installed" }).Count / $platformData.Count) * 100, 2) } else { 0 }
            }
        } |
        Sort-Object Total -Descending

    # Generate timestamp for file names
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $csvPath = Join-Path $OutputPath "Intune_App_Installation_Status_Report_$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "Intune_App_Installation_Status_Report_$timestamp.html"

    # Export to CSV
    try {
        $installationStatusList | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
    <title>Intune Application Installation Status Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .summary-item { text-align: center; padding: 10px; background-color: #f8f9fa; border-radius: 4px; }
        .summary-number { font-size: 24px; font-weight: bold; color: #0078d4; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .danger { color: #dc3545; }
        .top-lists { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
        .top-list { background-color: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .top-list h3 { margin-top: 0; color: #0078d4; }
        .top-item { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #e1e5e9; }
        .top-item:last-child { border-bottom: none; }
        table { width: 100%; border-collapse: collapse; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; position: sticky; top: 0; }
        td { padding: 10px 12px; border-bottom: 1px solid #e1e5e9; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e3f2fd; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
        .filter-info { background-color: #fff3cd; border: 1px solid #ffeaa7; padding: 10px; border-radius: 4px; margin-bottom: 20px; }
        .status-badge { padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
        .status-installed { background-color: #d4edda; color: #155724; }
        .status-failed { background-color: #f8d7da; color: #721c24; }
        .status-pending { background-color: #fff3cd; color: #856404; }
        .status-other { background-color: #e2e3e5; color: #383d41; }
        .progress-bar { width: 100%; height: 20px; background-color: #e9ecef; border-radius: 4px; overflow: hidden; }
        .progress-fill { height: 100%; background-color: #28a745; text-align: center; color: white; font-size: 12px; line-height: 20px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Intune Application Installation Status Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
    </div>
"@

        # Add filter information if filters were applied
        if ($FilterByInstallState -ne "all" -or $FilterByPlatform -ne "all" -or $FilterByAppName -or $MaxApps -gt 0) {
            $htmlContent += "<div class='filter-info'><strong>Applied Filters:</strong> "
            if ($FilterByInstallState -ne "all") { $htmlContent += "Install State: $FilterByInstallState | " }
            if ($FilterByPlatform -ne "all") { $htmlContent += "Platform: $FilterByPlatform | " }
            if ($FilterByAppName) { $htmlContent += "Application: $FilterByAppName | " }
            if ($MaxApps -gt 0) { $htmlContent += "Max Apps: $MaxApps | " }
            $htmlContent = $htmlContent.TrimEnd(" | ") + "</div>"
        }

        $htmlContent += @"
    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-number">$totalInstallations</div>
                <div>Total Installation Records</div>
            </div>
            <div class="summary-item">
                <div class="summary-number success">$successfulInstalls</div>
                <div>Successful Installations</div>
            </div>
            <div class="summary-item">
                <div class="summary-number danger">$failedInstalls</div>
                <div>Failed Installations</div>
            </div>
            <div class="summary-item">
                <div class="summary-number warning">$pendingInstalls</div>
                <div>Pending Installations</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$uniqueApps</div>
                <div>Unique Applications</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$uniqueDevices</div>
                <div>Unique Devices</div>
            </div>
        </div>

        <h3>Success Rate</h3>
        <div class="progress-bar">
            <div class="progress-fill" style="width: $successRate%">$successRate%</div>
        </div>
        <p style="text-align: center; margin-top: 10px;">Failure Rate: <span class="danger">$failureRate%</span></p>

        <div class="top-lists">
            <div class="top-list">
                <h3>Top 10 Failed Applications</h3>
"@

        if ($topFailedApps) {
            foreach ($app in $topFailedApps) {
                $htmlContent += "<div class='top-item'><span>$($app.ApplicationName)</span><span class='danger'>$($app.FailureCount) failures</span></div>"
            }
        }
        else {
            $htmlContent += "<p>No failed installations found.</p>"
        }

        $htmlContent += @"
            </div>
            <div class="top-list">
                <h3>Status by Platform</h3>
"@

        foreach ($platform in $statusByPlatform) {
            $htmlContent += @"
                <div class='top-item'>
                    <span><strong>$($platform.Platform)</strong></span>
                    <span>$($platform.SuccessRate)% success</span>
                </div>
                <div style='font-size: 12px; color: #6c757d; padding-left: 10px; margin-bottom: 10px;'>
                    Installed: $($platform.Installed) | Failed: $($platform.Failed) | Pending: $($platform.Pending)
                </div>
"@
        }

        $htmlContent += @"
            </div>
        </div>
    </div>

    <div class="summary">
        <h2>Detailed Installation Status</h2>
        <table>
            <thead>
                <tr>
                    <th>Application</th>
                    <th>Device</th>
                    <th>User</th>
                    <th>Platform</th>
                    <th>Status</th>
                    <th>Error Code</th>
                    <th>Last Modified</th>
                </tr>
            </thead>
            <tbody>
"@

        foreach ($status in $installationStatusList | Sort-Object ApplicationName, DeviceName) {
            $statusClass = switch ($status.InstallStateRaw) {
                "installed" { "status-installed" }
                "failed" { "status-failed" }
                { $_ -like "*pending*" } { "status-pending" }
                default { "status-other" }
            }

            $htmlContent += @"
                <tr>
                    <td>$($status.ApplicationName)</td>
                    <td>$($status.DeviceName)</td>
                    <td>$($status.UserName)</td>
                    <td>$($status.Platform)</td>
                    <td><span class="status-badge $statusClass">$($status.InstallState)</span></td>
                    <td>$($status.ErrorCode)</td>
                    <td>$($status.LastModifiedDateTime)</td>
                </tr>
"@
        }

        $htmlContent += @"
            </tbody>
        </table>
    </div>

    <div class='footer'>Report generated by Intune Application Installation Status Script v1.0</div>
</body>
</html>
"@

        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Information "✓ HTML report saved: $htmlPath" -InformationAction Continue

        if ($OpenReport) {
            Start-Process $htmlPath
        }
    }
    catch {
        Write-Error "Failed to generate HTML report: $($_.Exception.Message)"
    }

    # Display summary
    Write-Output ""
    Write-Information "APPLICATION INSTALLATION STATUS SUMMARY" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total Installation Records: $totalInstallations" -InformationAction Continue
    Write-Information "Successful Installations: $successfulInstalls ($successRate%)" -InformationAction Continue
    Write-Information "Failed Installations: $failedInstalls ($failureRate%)" -InformationAction Continue
    Write-Information "Pending Installations: $pendingInstalls" -InformationAction Continue
    Write-Information "Unique Applications: $uniqueApps" -InformationAction Continue
    Write-Information "Unique Devices: $uniqueDevices" -InformationAction Continue

    if ($topFailedApps -and $topFailedApps.Count -gt 0) {
        Write-Information "`nTop 5 Failed Applications:" -InformationAction Continue
        $topFailedApps | Select-Object -First 5 | ForEach-Object {
            Write-Information "  $($_.ApplicationName): $($_.FailureCount) failures on $($_.UniqueDevices) devices" -InformationAction Continue
        }
    }

    Write-Information "`nReports saved to:" -InformationAction Continue
    Write-Information "CSV: $csvPath" -InformationAction Continue
    Write-Information "HTML: $htmlPath" -InformationAction Continue

    Write-Information "`nApplication installation status report generation completed successfully!" -InformationAction Continue
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