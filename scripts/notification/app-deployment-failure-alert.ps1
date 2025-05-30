<#
.TITLE
    App Deployment Failure Alert Notification

.SYNOPSIS
    Automated runbook to monitor application deployment failures in Intune and send email alerts for deployment issues.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors application 
    deployment status in Microsoft Intune and identifies applications with high failure rates or 
    deployment issues. It tracks deployment success rates, identifies required applications with 
    failures, and sends email notifications to administrators with detailed deployment reports. 
    The script helps maintain application availability and user productivity by proactively alerting 
    on deployment failures and providing actionable insights for remediation.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All,DeviceManagementManagedDevices.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-30

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Daily

.CATEGORY
    Notification

.EXAMPLE
    .\app-deployment-failure-alert.ps1 -FailureThresholdPercent 20 -EmailRecipients "admin@company.com"
    Alerts when app deployment failure rate exceeds 20% and sends notifications to admin@company.com

.EXAMPLE
    .\app-deployment-failure-alert.ps1 -FailureThresholdPercent 15 -EmailRecipients "admin@company.com,appsupport@company.com"
    Alerts when app deployment failure rate exceeds 15% and sends notifications to multiple recipients

.NOTES
    - Requires Microsoft.Graph.Authentication and Microsoft.Graph.Mail modules
    - For Azure Automation, configure Managed Identity with required permissions
    - Uses Microsoft Graph Mail API for email notifications only
    - Recommended to run as scheduled runbook (daily)
    - Consider your organization's application deployment requirements when setting threshold
    - Review application packages and deployment settings based on findings
    - Critical for maintaining application availability and user productivity
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Maximum acceptable failure percentage for app deployments")]
    [ValidateRange(5, 50)]
    [int]$FailureThresholdPercent,
    
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to send notifications")]
    [ValidateNotNullOrEmpty()]
    [string]$EmailRecipients,
    
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
                $errorMessage = @"
Module '$ModuleName' is not available in this Azure Automation Account.

To resolve this issue:
1. Go to Azure Portal
2. Navigate to your Automation Account
3. Go to 'Modules' > 'Browse Gallery'
4. Search for '$ModuleName'
5. Click 'Import' and wait for installation to complete

Required modules for this script:
- Microsoft.Graph.Authentication
- Microsoft.Graph.Mail
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
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }
        
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
$RequiredModuleList = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Mail"
)

try {
    Initialize-RequiredModule -ModuleNames $RequiredModuleList -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
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
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        Write-Information "Connecting to Microsoft Graph with interactive authentication..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementApps.Read.All",
            "DeviceManagementManagedDevices.Read.All",
            "Mail.Send"
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

function Get-AppType {
    param([string]$ODataType)
    
    switch ($ODataType) {
        "#microsoft.graph.win32LobApp" { return "Win32 App" }
        "#microsoft.graph.microsoftStoreForBusinessApp" { return "Store App" }
        "#microsoft.graph.webApp" { return "Web App" }
        "#microsoft.graph.officeSuiteApp" { return "Office Suite" }
        "#microsoft.graph.winGetApp" { return "WinGet App" }
        "#microsoft.graph.iosLobApp" { return "iOS LOB App" }
        "#microsoft.graph.iosStoreApp" { return "iOS Store App" }
        "#microsoft.graph.androidManagedStoreApp" { return "Android Store App" }
        "#microsoft.graph.androidLobApp" { return "Android LOB App" }
        "#microsoft.graph.macOSLobApp" { return "macOS LOB App" }
        "#microsoft.graph.macOSOfficeSuiteApp" { return "macOS Office Suite" }
        default { return "Other" }
    }
}

function Get-InstallIntentDisplay {
    param([string]$Intent)
    
    switch ($Intent) {
        "required" { return "Required" }
        "available" { return "Available" }
        "uninstall" { return "Uninstall" }
        "availableWithoutEnrollment" { return "Available (No Enrollment)" }
        default { return $Intent }
    }
}

function Get-InstallStateDisplay {
    param([string]$InstallState)
    
    switch ($InstallState) {
        "installed" { return "Installed" }
        "failed" { return "Failed" }
        "notInstalled" { return "Not Installed" }
        "uninstallFailed" { return "Uninstall Failed" }
        "pendingInstall" { return "Pending Install" }
        "unknown" { return "Unknown" }
        "notApplicable" { return "Not Applicable" }
        default { return $InstallState }
    }
}

function Get-DeploymentSeverity {
    param([string]$InstallState, [string]$Intent)
    
    if ($Intent -eq "required") {
        switch ($InstallState) {
            "failed" { return "Critical" }
            "uninstallFailed" { return "Critical" }
            "pendingInstall" { return "Warning" }
            "notInstalled" { return "Warning" }
            "installed" { return "Success" }
            default { return "Info" }
        }
    }
    else {
        switch ($InstallState) {
            "failed" { return "Warning" }
            "uninstallFailed" { return "Warning" }
            "installed" { return "Success" }
            default { return "Info" }
        }
    }
}

function Send-EmailNotification {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Recipients,
        [string]$Subject,
        [string]$Body
    )
    
    try {
        foreach ($Recipient in $Recipients) {
            $Message = @{
                subject      = $Subject
                body         = @{
                    contentType = "HTML"
                    content     = $Body
                }
                toRecipients = @(
                    @{
                        emailAddress = @{
                            address = $Recipient
                        }
                    }
                )
            }
            
            $RequestBody = @{
                message = $Message
            } | ConvertTo-Json -Depth 10
            
            if ($PSCmdlet.ShouldProcess($Recipient, "Send Email Notification")) {
                $Uri = "https://graph.microsoft.com/v1.0/me/sendMail"
                Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $RequestBody -ContentType "application/json"
                Write-Information "✓ Email sent to $Recipient via Microsoft Graph" -InformationAction Continue
            }
        }
    }
    catch {
        Write-Error "Failed to send email notification: $($_.Exception.Message)"
    }
}

function New-EmailBody {
    param(
        [array]$AllApps,
        [array]$FailedApps,
        [array]$RequiredFailedApps,
        [hashtable]$AppStats,
        [int]$FailureThreshold
    )
    
    $TotalApps = $AllApps.Count
    $AppsWithFailures = ($AllApps | Where-Object { $_.FailureCount -gt 0 }).Count
    $OverallFailureRate = if ($AppStats.TotalDeployments -gt 0) { 
        [math]::Round(($AppStats.TotalFailures / $AppStats.TotalDeployments) * 100, 1) 
    }
    else { 0 }
    
    $AppTypeSummary = $FailedApps | Group-Object AppType | Sort-Object Count -Descending
    $PlatformSummary = $FailedApps | Group-Object TargetPlatform | Sort-Object Count -Descending
    
    $Body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; }
        .header { background-color: #0078d4; color: white; padding: 15px; border-radius: 5px; }
        .summary { background-color: #f8f9fa; padding: 15px; margin: 15px 0; border-radius: 5px; border-left: 4px solid #0078d4; }
        .critical { background-color: #fdf2f2; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        .warning { background-color: #fffbf0; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .success { background-color: #e8f5e8; border-left: 4px solid #28a745; padding: 10px; margin: 10px 0; }
        .info { background-color: #e7f3ff; border-left: 4px solid #17a2b8; padding: 10px; margin: 10px 0; }
        .app-item { margin: 5px 0; padding: 8px; background-color: white; border-radius: 3px; font-size: 14px; }
        .category-summary { margin: 10px 0; padding: 8px; background-color: #f0f0f0; border-radius: 3px; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 15px 0; }
        .stat-card { background-color: white; padding: 15px; border-radius: 5px; text-align: center; border: 1px solid #ddd; }
        .failure-meter { width: 100%; height: 20px; background-color: #e0e0e0; border-radius: 10px; margin: 10px 0; position: relative; }
        .failure-fill { height: 100%; border-radius: 10px; transition: width 0.3s ease; }
        .failure-text { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-weight: bold; color: white; text-shadow: 1px 1px 1px rgba(0,0,0,0.5); }
        .progress-bar { width: 100%; height: 8px; background-color: #e0e0e0; border-radius: 4px; margin: 5px 0; }
        .progress-fill { height: 100%; border-radius: 4px; }
        h2 { color: #333; }
        h3 { color: #555; margin-top: 20px; }
        .status-icon { font-size: 16px; margin-right: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .center { text-align: center; }
        .right { text-align: right; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📱 App Deployment Failure Alert</h1>
        <p>Failure threshold: $FailureThreshold% | Current overall rate: $OverallFailureRate%</p>
    </div>
    
    <div class="summary">
        <h2>Application Deployment Overview</h2>
        <div class="failure-meter">
            <div class="failure-fill" style="width: $(if ($OverallFailureRate -gt 100) { 100 } else { $OverallFailureRate })%; background-color: $(if ($OverallFailureRate -le $FailureThreshold) { '#28a745' } elseif ($OverallFailureRate -le ($FailureThreshold * 1.5)) { '#ffc107' } else { '#dc3545' });"></div>
            <div class="failure-text">$OverallFailureRate%</div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3 style="margin: 0; color: #0078d4;">$TotalApps</h3>
                <p style="margin: 5px 0;">Total Applications</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #dc3545;">$AppsWithFailures</h3>
                <p style="margin: 5px 0;">Apps with Failures</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #ffc107;">$($RequiredFailedApps.Count)</h3>
                <p style="margin: 5px 0;">Required Apps Failing</p>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3 style="margin: 0; color: #17a2b8;">$($AppStats.TotalDeployments)</h3>
                <p style="margin: 5px 0;">Total Deployments</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #28a745;">$($AppStats.TotalSuccesses)</h3>
                <p style="margin: 5px 0;">Successful Installs</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #dc3545;">$($AppStats.TotalFailures)</h3>
                <p style="margin: 5px 0;">Failed Installs</p>
            </div>
        </div>
    </div>
"@

    if ($RequiredFailedApps.Count -gt 0) {
        $Body += @"
    <div class="critical">
        <h3><span class="status-icon">🚨</span>Required Applications with Failures - Critical Impact ($($RequiredFailedApps.Count) apps)</h3>
        <p>These required applications are failing to install and may impact user productivity:</p>
        
        <table>
            <tr>
                <th>Application Name</th>
                <th>App Type</th>
                <th>Platform</th>
                <th>Total Deployments</th>
                <th>Failures</th>
                <th>Failure Rate</th>
                <th>Success Rate</th>
            </tr>
"@
        
        foreach ($App in ($RequiredFailedApps | Sort-Object FailureRate -Descending | Select-Object -First 15)) {
            $SuccessRate = [math]::Round((($App.TotalDeployments - $App.FailureCount) / $App.TotalDeployments) * 100, 1)
            $Body += @"
            <tr>
                <td>$($App.AppName)</td>
                <td>$($App.AppType)</td>
                <td>$($App.TargetPlatform)</td>
                <td class="center">$($App.TotalDeployments)</td>
                <td class="center">$($App.FailureCount)</td>
                <td class="center" style="color: #dc3545; font-weight: bold;">$($App.FailureRate)%</td>
                <td class="center">
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: $SuccessRate%; background-color: $(if ($SuccessRate -ge 90) { '#28a745' } elseif ($SuccessRate -ge 70) { '#ffc107' } else { '#dc3545' });"></div>
                    </div>
                    $SuccessRate%
                </td>
            </tr>
"@
        }
        
        if ($RequiredFailedApps.Count -gt 15) {
            $Body += @"
            <tr>
                <td colspan="7" class="center"><em>... and $($RequiredFailedApps.Count - 15) more required applications with failures</em></td>
            </tr>
"@
        }
        
        $Body += "</table></div>"
    }

    if ($FailedApps.Count -gt $RequiredFailedApps.Count) {
        $AvailableFailedApps = $FailedApps | Where-Object { $_.InstallIntent -ne "Required" }
        $Body += @"
    <div class="warning">
        <h3><span class="status-icon">⚠️</span>Available Applications with Failures ($($AvailableFailedApps.Count) apps)</h3>
        <p>These available applications have deployment failures that may affect user experience:</p>
        
        <table>
            <tr>
                <th>Application Name</th>
                <th>App Type</th>
                <th>Install Intent</th>
                <th>Platform</th>
                <th>Failures</th>
                <th>Failure Rate</th>
            </tr>
"@
        
        foreach ($App in ($AvailableFailedApps | Sort-Object FailureRate -Descending | Select-Object -First 10)) {
            $Body += @"
            <tr>
                <td>$($App.AppName)</td>
                <td>$($App.AppType)</td>
                <td>$($App.InstallIntentDisplay)</td>
                <td>$($App.TargetPlatform)</td>
                <td class="center">$($App.FailureCount)</td>
                <td class="center" style="color: #ffc107; font-weight: bold;">$($App.FailureRate)%</td>
            </tr>
"@
        }
        
        if ($AvailableFailedApps.Count -gt 10) {
            $Body += @"
            <tr>
                <td colspan="6" class="center"><em>... and $($AvailableFailedApps.Count - 10) more available applications with failures</em></td>
            </tr>
"@
        }
        
        $Body += "</table></div>"
    }

    if ($AppTypeSummary.Count -gt 0) {
        $Body += @"
    <div class="info">
        <h3><span class="status-icon">📊</span>Failure Analysis by App Type</h3>
"@
        foreach ($AppType in $AppTypeSummary) {
            $Body += @"
        <div class="category-summary">
            <strong>$($AppType.Name):</strong> $($AppType.Count) applications with failures
        </div>
"@
        }
        $Body += "</div>"
    }

    if ($PlatformSummary.Count -gt 0) {
        $Body += @"
    <div class="info">
        <h3><span class="status-icon">🖥️</span>Failure Analysis by Platform</h3>
"@
        foreach ($Platform in $PlatformSummary) {
            $Body += @"
        <div class="category-summary">
            <strong>$($Platform.Name):</strong> $($Platform.Count) applications with failures
        </div>
"@
        }
        $Body += "</div>"
    }

    $Body += @"
    <div class="$(if ($OverallFailureRate -le $FailureThreshold) { 'success' } else { 'critical' })">
        <h3><span class="status-icon">💡</span>Deployment Improvement Recommendations</h3>
        <h4>Immediate Actions:</h4>
        <ul>
            <li><strong>Prioritize Required Apps:</strong> Focus on fixing required applications first as they have the highest business impact</li>
            <li><strong>Review App Packages:</strong> Check application packages for corruption or compatibility issues</li>
            <li><strong>Validate Dependencies:</strong> Ensure all application dependencies are properly installed</li>
            <li><strong>Check Target Requirements:</strong> Verify device requirements match application specifications</li>
        </ul>
        
        <h4>Technical Investigation:</h4>
        <ul>
            <li><strong>Review Install Logs:</strong> Examine detailed installation logs for root cause analysis</li>
            <li><strong>Test Deployment Groups:</strong> Validate deployments with smaller test groups first</li>
            <li><strong>Network Connectivity:</strong> Ensure devices have reliable connectivity for large app downloads</li>
            <li><strong>Storage Space:</strong> Verify target devices have sufficient storage for installations</li>
        </ul>
        
        <h4>Process Improvements:</h4>
        <ul>
            <li><strong>Staging Deployments:</strong> Implement phased rollouts for better failure detection</li>
            <li><strong>Monitoring Enhancement:</strong> Set up proactive monitoring for deployment status</li>
            <li><strong>User Communication:</strong> Inform users about application issues and expected resolution times</li>
            <li><strong>Rollback Plans:</strong> Prepare rollback procedures for problematic deployments</li>
        </ul>
    </div>
    
    <div class="footer">
        <p><strong>Next Steps:</strong></p>
        <ol>
            <li>Investigate required applications with highest failure rates first</li>
            <li>Use the existing application reports to get detailed deployment status</li>
            <li>Review application packages and deployment settings for problematic apps</li>
            <li>Consider implementing staged deployments for better failure management</li>
        </ol>
        <p><em>This is an automated notification from your Intune monitoring system.</em></p>
        <p><em>Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</em></p>
    </div>
</body>
</html>
"@

    return $Body
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting app deployment failure monitoring..." -InformationAction Continue
    
    # Parse email recipients
    $EmailRecipientList = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    
    if ($EmailRecipientList.Count -eq 0) {
        throw "No valid email recipients provided"
    }
    
    Write-Information "Email recipients: $($EmailRecipientList -join ', ')" -InformationAction Continue
    Write-Information "Failure threshold: $FailureThresholdPercent%" -InformationAction Continue
    
    # Initialize results arrays
    $AllApps = @()
    $FailedApps = @()
    $RequiredFailedApps = @()
    
    # Initialize statistics
    $AppStats = @{
        TotalDeployments = 0
        TotalSuccesses   = 0
        TotalFailures    = 0
        TotalPending     = 0
    }
    
    # ========================================================================
    # GET ALL MOBILE APPLICATIONS
    # ========================================================================
    
    Write-Information "Retrieving mobile applications..." -InformationAction Continue
    
    try {
        $AppsUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
        $Apps = Get-MgGraphAllPage -Uri $AppsUri
        Write-Information "Found $($Apps.Count) applications" -InformationAction Continue
        
        foreach ($App in $Apps) {
            try {
                # Skip built-in and system apps
                if ($App.isFeatured -eq $true -or $App.isBuiltIn -eq $true) {
                    Write-Verbose "Skipping built-in/featured app: $($App.displayName)"
                    continue
                }
                
                # Skip apps without essential information
                if (-not $App.id -or -not $App.displayName) {
                    Write-Verbose "Skipping app with missing essential data"
                    continue
                }
                
                Write-Verbose "Processing app: $($App.displayName)"
                
                # Get app install status for this application
                $AppInstallStatusUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($App.id)/deviceStatuses"
                $InstallStatuses = Get-MgGraphAllPage -Uri $AppInstallStatusUri
                
                # Get app assignments to determine install intent
                $AppAssignmentsUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($App.id)/assignments"
                $Assignments = Get-MgGraphAllPage -Uri $AppAssignmentsUri
                
                # Determine primary install intent (prioritize required)
                $InstallIntent = "available"
                $TargetPlatform = "Unknown"
                
                if ($Assignments) {
                    foreach ($Assignment in $Assignments) {
                        if ($Assignment.intent -eq "required") {
                            $InstallIntent = "required"
                            break
                        }
                        elseif ($Assignment.intent -eq "available" -and $InstallIntent -ne "required") {
                            $InstallIntent = "available"
                        }
                    }
                }
                
                # Determine target platform from app type
                switch -Regex ($App.'@odata.type') {
                    "win32|office" { $TargetPlatform = "Windows" }
                    "ios" { $TargetPlatform = "iOS" }
                    "android" { $TargetPlatform = "Android" }
                    "macOS" { $TargetPlatform = "macOS" }
                    "web" { $TargetPlatform = "Web" }
                    default { $TargetPlatform = "Cross-Platform" }
                }
                
                # Calculate deployment statistics
                $TotalDeployments = $InstallStatuses.Count
                $SuccessfulInstalls = ($InstallStatuses | Where-Object { $_.installState -eq "installed" }).Count
                $FailedInstalls = ($InstallStatuses | Where-Object { $_.installState -in @("failed", "uninstallFailed") }).Count
                $PendingInstalls = ($InstallStatuses | Where-Object { $_.installState -eq "pendingInstall" }).Count
                
                $FailureRate = if ($TotalDeployments -gt 0) { 
                    [math]::Round(($FailedInstalls / $TotalDeployments) * 100, 1) 
                }
                else { 0 }
                
                $AppType = Get-AppType -ODataType $App.'@odata.type'
                $InstallIntentDisplay = Get-InstallIntentDisplay -Intent $InstallIntent
                
                $AppInfo = [PSCustomObject]@{
                    AppId                = $App.id
                    AppName              = $App.displayName
                    AppType              = $AppType
                    TargetPlatform       = $TargetPlatform
                    InstallIntent        = $InstallIntent
                    InstallIntentDisplay = $InstallIntentDisplay
                    Publisher            = $App.publisher
                    TotalDeployments     = $TotalDeployments
                    SuccessfulInstalls   = $SuccessfulInstalls
                    FailedInstalls       = $FailedInstalls
                    FailureCount         = $FailedInstalls
                    PendingInstalls      = $PendingInstalls
                    FailureRate          = $FailureRate
                    CreatedDateTime      = if ($App.createdDateTime) { [datetime]$App.createdDateTime } else { $null }
                    LastModifiedDateTime = if ($App.lastModifiedDateTime) { [datetime]$App.lastModifiedDateTime } else { $null }
                }
                
                # Update overall statistics
                $AppStats.TotalDeployments += $TotalDeployments
                $AppStats.TotalSuccesses += $SuccessfulInstalls
                $AppStats.TotalFailures += $FailedInstalls
                $AppStats.TotalPending += $PendingInstalls
                
                $AllApps += $AppInfo
                
                # Categorize apps with failures
                if ($FailedInstalls -gt 0 -and $FailureRate -gt $FailureThresholdPercent) {
                    $FailedApps += $AppInfo
                    
                    if ($InstallIntent -eq "required") {
                        $RequiredFailedApps += $AppInfo
                    }
                }
            }
            catch {
                Write-Verbose "Error processing app '$($App.displayName)' (ID: $($App.id)): $($_.Exception.Message)"
                continue
            }
        }
        
        Write-Information "✓ Processed $($AllApps.Count) applications successfully" -InformationAction Continue
        Write-Information "  • Applications with failures: $($FailedApps.Count)" -InformationAction Continue
        Write-Information "  • Required apps with failures: $($RequiredFailedApps.Count)" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to retrieve mobile applications: $($_.Exception.Message)"
        exit 1
    }
    
    # ========================================================================
    # CALCULATE OVERALL STATISTICS
    # ========================================================================
    
    $OverallFailureRate = if ($AppStats.TotalDeployments -gt 0) { 
        [math]::Round(($AppStats.TotalFailures / $AppStats.TotalDeployments) * 100, 1) 
    }
    else { 0 }
    
    Write-Information "  • Total deployments: $($AppStats.TotalDeployments)" -InformationAction Continue
    Write-Information "  • Successful installs: $($AppStats.TotalSuccesses)" -InformationAction Continue
    Write-Information "  • Failed installs: $($AppStats.TotalFailures)" -InformationAction Continue
    Write-Information "  • Overall failure rate: $OverallFailureRate%" -InformationAction Continue
    
    # ========================================================================
    # SEND NOTIFICATIONS IF DEPLOYMENT FAILURES DETECTED
    # ========================================================================
    
    $RequiresNotification = ($OverallFailureRate -gt $FailureThresholdPercent) -or 
                           ($RequiredFailedApps.Count -gt 0) -or 
                           ($FailedApps.Count -gt 0)
    
    if ($RequiresNotification) {
        Write-Information "Preparing email notification for app deployment failures..." -InformationAction Continue
        
        $Subject = if ($RequiredFailedApps.Count -gt 0) {
            "[Intune Alert] CRITICAL: $($RequiredFailedApps.Count) Required App(s) Failing to Deploy"
        }
        elseif ($OverallFailureRate -gt $FailureThresholdPercent) {
            "[Intune Alert] APP DEPLOYMENT ISSUES: $OverallFailureRate% Failure Rate (Threshold: $FailureThresholdPercent%)"
        }
        else {
            "[Intune Alert] APPLICATION MONITORING: $($FailedApps.Count) App(s) with Deployment Failures"
        }
        
        $EmailBody = New-EmailBody -AllApps $AllApps -FailedApps $FailedApps -RequiredFailedApps $RequiredFailedApps -AppStats $AppStats -FailureThreshold $FailureThresholdPercent
        
        Send-EmailNotification -Recipients $EmailRecipientList -Subject $Subject -Body $EmailBody
        
        Write-Information "✓ Email notification sent to $($EmailRecipientList.Count) recipients" -InformationAction Continue
    }
    else {
        Write-Information "✓ No significant app deployment failures detected. All applications are deploying successfully." -InformationAction Continue
    }
    
    # ========================================================================
    # DISPLAY SUMMARY
    # ========================================================================
    
    Write-Information "`n📱 APP DEPLOYMENT FAILURE MONITORING SUMMARY" -InformationAction Continue
    Write-Information "=============================================" -InformationAction Continue
    Write-Information "Total Applications: $($AllApps.Count)" -InformationAction Continue
    Write-Information "Failure Threshold: $FailureThresholdPercent%" -InformationAction Continue
    Write-Information "Overall Failure Rate: $OverallFailureRate%" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    Write-Information "Deployment Statistics:" -InformationAction Continue
    Write-Information "  • Total Deployments: $($AppStats.TotalDeployments)" -InformationAction Continue
    Write-Information "  • Successful: $($AppStats.TotalSuccesses)" -InformationAction Continue
    Write-Information "  • Failed: $($AppStats.TotalFailures)" -InformationAction Continue
    Write-Information "  • Pending: $($AppStats.TotalPending)" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    Write-Information "Applications with Issues:" -InformationAction Continue
    Write-Information "  • Apps with failures: $($FailedApps.Count)" -InformationAction Continue
    Write-Information "  • Required apps failing: $($RequiredFailedApps.Count)" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    if ($RequiredFailedApps.Count -gt 0) {
        Write-Information "Top Required Apps with Failures:" -InformationAction Continue
        $TopRequiredFailed = $RequiredFailedApps | Sort-Object FailureRate -Descending | Select-Object -First 5
        foreach ($App in $TopRequiredFailed) {
            Write-Information "  🔸 $($App.AppName) ($($App.AppType)) - $($App.FailureRate)% failure rate" -InformationAction Continue
        }
        Write-Information "" -InformationAction Continue
    }
    
    $StatusIcon = if ($OverallFailureRate -le $FailureThresholdPercent -and $RequiredFailedApps.Count -eq 0) { "✅" } else { "⚠️" }
    Write-Information "$StatusIcon Deployment Status: $(if ($OverallFailureRate -le $FailureThresholdPercent -and $RequiredFailedApps.Count -eq 0) { 'HEALTHY' } else { 'ISSUES DETECTED' })" -InformationAction Continue
    
    Write-Information "`n✓ App deployment failure monitoring completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Silently ignore disconnect errors as they're not critical
        Write-Verbose "Disconnect error (ignored): $($_.Exception.Message)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Script Execution Summary
========================================
Script: App Deployment Failure Alert
Total Applications Analyzed: $($AllApps.Count)
Overall Failure Rate: $OverallFailureRate%
Failure Threshold: $FailureThresholdPercent%
Total Deployments: $($AppStats.TotalDeployments)
Failed Deployments: $($AppStats.TotalFailures)
Apps with Failures: $($FailedApps.Count)
Required Apps Failing: $($RequiredFailedApps.Count)
Email Recipients: $($EmailRecipientList.Count)
Status: Completed
========================================
" -InformationAction Continue