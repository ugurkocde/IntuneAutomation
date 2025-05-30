<#
.TITLE
    [Your Notification Script Title - Brief descriptive name]

.SYNOPSIS
    Automated runbook to monitor [specific Intune aspect] and send email alerts for [specific conditions].

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors [specific functionality] 
    in Microsoft Intune and identifies [specific conditions to monitor]. It tracks [what it tracks], 
    identifies [what it identifies], and sends email notifications to administrators with detailed reports. 
    The script helps maintain [benefit] by proactively alerting on [conditions] and providing actionable 
    insights for remediation.

    Key Features:
    - Monitors [specific aspect] across [scope]
    - Configurable [threshold/condition] (description)
    - Email notifications with detailed [type] reports
    - [Platform/category]-specific analysis
    - [Additional feature 1]
    - [Additional feature 2]
    - Supports both Azure Automation runbook and local execution
    - HTML formatted email reports with actionable insights
    - Uses Microsoft Graph Mail API exclusively

.TAGS
    Notification,[YourCategory],RunbookOnly,Email,Monitoring,[AdditionalTags]

.MINROLE
    Intune Administrator

.PERMISSIONS
    [Required.Graph.Permissions],Mail.Send

.AUTHOR
    [Your Name]

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Daily

.CATEGORY
    Notification

.EXAMPLE
    .\your-notification-script.ps1 -ThresholdParameter 85 -EmailRecipients "admin@company.com"
    [Description of what this example does]

.EXAMPLE
    .\your-notification-script.ps1 -ThresholdParameter 90 -EmailRecipients "admin@company.com,security@company.com"
    [Description of what this example does with multiple recipients]

.NOTES
    - Requires Microsoft.Graph.Authentication and Microsoft.Graph.Mail modules
    - For Azure Automation, configure Managed Identity with required permissions
    - This script is designed specifically for Azure Automation runbooks
    - Email notifications are sent via Microsoft Graph Mail API
    - Customize the HTML email template in the New-EmailBody function
    - Adjust monitoring thresholds based on your organization's requirements
#>

[CmdletBinding()]
param(
    # Main threshold parameter - customize based on your monitoring needs
    [Parameter(Mandatory = $true, HelpMessage = "Threshold value that triggers notifications (e.g., percentage, number of days, count)")]
    [ValidateRange(1, 100)]
    [int]$ThresholdParameter,
    
    # Email recipients for notifications
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to receive notifications")]
    [ValidateScript({
        if ($_ -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(,[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})*$') {
            $true
        } else {
            throw "Please provide valid email addresses separated by commas"
        }
    })]
    [string]$EmailRecipients,
    
    # Optional: Additional filtering parameter
    [Parameter(Mandatory = $false, HelpMessage = "Optional filter for specific platforms, categories, etc.")]
    [ValidateSet("All", "Windows", "iOS", "Android", "macOS")]
    [string]$PlatformFilter = "All"
)

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if running in Azure Automation
$RunningInAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Check if required modules are installed
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Mail"
    # Add other required Graph modules based on your monitoring needs
    # "Microsoft.Graph.DeviceManagement",
    # "Microsoft.Graph.Applications",
    # "Microsoft.Graph.Users"
)

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        if ($RunningInAzureAutomation) {
            Write-Error "$Module module is not available in this Azure Automation Account. Please install it from the Browse Gallery in the Azure portal."
        } else {
            Write-Error "$Module module is required. Install it using: Install-Module $Module -Scope CurrentUser"
        }
        exit 1
    }
}

# Import required modules
foreach ($Module in $RequiredModules) {
    try {
        Import-Module $Module -Force
        Write-Information "✓ Imported module: $Module" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to import module $Module : $($_.Exception.Message)"
        exit 1
    }
}

# Connect to Microsoft Graph
try {
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    
    if ($RunningInAzureAutomation) {
        # Use Managed Identity in Azure Automation
        Connect-MgGraph -Identity -NoWelcome
        Write-Information "✓ Connected to Microsoft Graph using Managed Identity" -InformationAction Continue
    } else {
        # Use interactive authentication for local execution
        $Scopes = @(
            # Add your required permissions here - customize based on your monitoring needs
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "Mail.Send"
        )
        Connect-MgGraph -Scopes $Scopes -NoWelcome
        Write-Information "✓ Connected to Microsoft Graph with interactive authentication" -InformationAction Continue
    }
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# CONFIGURATION
# ============================================================================

# Email configuration
$EmailConfig = @{
    Subject = "[ALERT] [Your Organization] - [Alert Type] Detected"
    FromAddress = "noreply@yourdomain.com"  # Update with your organization's address
    Priority = "High"  # Options: Low, Normal, High
}

# Monitoring configuration - customize based on your needs
$MonitoringConfig = @{
    ThresholdValue = $ThresholdParameter
    PlatformFilter = $PlatformFilter
    # Add more configuration options as needed
    WarningThreshold = $ThresholdParameter + 10  # Example: warning threshold
    CriticalThreshold = $ThresholdParameter
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API with error handling
function Get-MgGraphAllPages {
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
            
            # Show progress for long-running operations
            if ($RequestCount % 10 -eq 0) {
                Write-Information "Processed $RequestCount API pages, retrieved $($AllResults.Count) items..." -InformationAction Continue
            }
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
        }
    } while ($NextLink)
    
    Write-Information "✓ Retrieved $($AllResults.Count) total items from Graph API" -InformationAction Continue
    return $AllResults
}

# Function to create HTML email body - customize this extensively for your use case
function New-EmailBody {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AlertData,
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )
    
    # Determine alert level based on your criteria
    $AlertLevel = if ($Summary.CriticalCount -gt 0) { "Critical" } 
                  elseif ($Summary.WarningCount -gt 0) { "Warning" } 
                  else { "Info" }
    
    $AlertColor = switch ($AlertLevel) {
        "Critical" { "#dc3545" }
        "Warning" { "#ffc107" }
        "Info" { "#28a745" }
    }
    
    $EmailBody = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$($EmailConfig.Subject)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background-color: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, $AlertColor 0%, #6c5ce7 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 28px; font-weight: 300; }
        .header .subtitle { margin: 10px 0 0 0; opacity: 0.9; font-size: 16px; }
        .content { padding: 30px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: #f8f9fa; border-left: 4px solid $AlertColor; padding: 20px; border-radius: 4px; }
        .summary-card h3 { margin: 0 0 10px 0; color: #2c3e50; font-size: 14px; text-transform: uppercase; letter-spacing: 1px; }
        .summary-card .value { font-size: 32px; font-weight: bold; color: $AlertColor; margin: 0; }
        .summary-card .label { color: #7f8c8d; font-size: 14px; }
        .alert-section { margin: 30px 0; }
        .alert-section h2 { color: #2c3e50; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; }
        .alert-item { background: #fff; border: 1px solid #dee2e6; border-radius: 6px; padding: 15px; margin: 10px 0; }
        .alert-item.critical { border-left: 4px solid #dc3545; }
        .alert-item.warning { border-left: 4px solid #ffc107; }
        .alert-item .item-title { font-weight: bold; color: #2c3e50; margin-bottom: 5px; }
        .alert-item .item-details { color: #6c757d; font-size: 14px; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #6c757d; font-size: 12px; }
        .recommendations { background: #e8f4fd; border: 1px solid #bee5eb; border-radius: 6px; padding: 20px; margin: 20px 0; }
        .recommendations h3 { color: #0c5460; margin-top: 0; }
        .recommendations ul { color: #0c5460; }
        .timestamp { color: #6c757d; font-size: 12px; text-align: right; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔔 [Your Alert Type] Alert</h1>
            <div class="subtitle">Proactive monitoring detected conditions requiring attention</div>
        </div>
        
        <div class="content">
            <div class="summary-grid">
                <div class="summary-card">
                    <h3>Alert Level</h3>
                    <div class="value">$AlertLevel</div>
                    <div class="label">Current Status</div>
                </div>
                <div class="summary-card">
                    <h3>Critical Items</h3>
                    <div class="value">$($Summary.CriticalCount)</div>
                    <div class="label">Require Immediate Action</div>
                </div>
                <div class="summary-card">
                    <h3>Warning Items</h3>
                    <div class="value">$($Summary.WarningCount)</div>
                    <div class="label">Need Attention</div>
                </div>
                <div class="summary-card">
                    <h3>Total Monitored</h3>
                    <div class="value">$($Summary.TotalCount)</div>
                    <div class="label">Items Checked</div>
                </div>
            </div>
            
            <div class="alert-section">
                <h2>🚨 Critical Issues</h2>
"@

    # Add critical items to email body
    $CriticalItems = $AlertData | Where-Object { $_.Level -eq "Critical" }
    if ($CriticalItems.Count -gt 0) {
        foreach ($Item in $CriticalItems) {
            $EmailBody += @"
                <div class="alert-item critical">
                    <div class="item-title">$($Item.Title)</div>
                    <div class="item-details">$($Item.Details)</div>
                </div>
"@
        }
    } else {
        $EmailBody += "<p>✅ No critical issues detected.</p>"
    }

    # Add warning items to email body
    $WarningItems = $AlertData | Where-Object { $_.Level -eq "Warning" }
    $EmailBody += @"
            </div>
            
            <div class="alert-section">
                <h2>⚠️ Warning Items</h2>
"@

    if ($WarningItems.Count -gt 0) {
        foreach ($Item in $WarningItems) {
            $EmailBody += @"
                <div class="alert-item warning">
                    <div class="item-title">$($Item.Title)</div>
                    <div class="item-details">$($Item.Details)</div>
                </div>
"@
        }
    } else {
        $EmailBody += "<p>✅ No warning items detected.</p>"
    }

    # Add recommendations section
    $EmailBody += @"
            </div>
            
            <div class="recommendations">
                <h3>📋 Recommended Actions</h3>
                <ul>
                    <li>Review and address critical issues immediately</li>
                    <li>Plan remediation for warning items</li>
                    <li>Monitor trends over the next few days</li>
                    <li>Update thresholds if needed based on your organization's requirements</li>
                    <!-- Add specific recommendations based on your monitoring type -->
                </ul>
            </div>
            
            <div class="timestamp">
                Report generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
            </div>
        </div>
        
        <div class="footer">
            This is an automated notification from your Intune monitoring system.<br>
            For questions or issues, please contact your IT administrator.
        </div>
    </div>
</body>
</html>
"@

    return $EmailBody
}

# Function to send email notification
function Send-EmailNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [Parameter(Mandatory = $true)]
        [array]$Recipients,
        [Parameter(Mandatory = $true)]
        [string]$Subject
    )
    
    try {
        Write-Information "Preparing email notification..." -InformationAction Continue
        
        # Prepare recipients array
        $ToRecipients = @()
        foreach ($Recipient in $Recipients) {
            $ToRecipients += @{
                emailAddress = @{
                    address = $Recipient.Trim()
                }
            }
        }
        
        # Prepare email message
        $Message = @{
            subject = $Subject
            body = @{
                contentType = "HTML"
                content = $Body
            }
            toRecipients = $ToRecipients
            importance = $EmailConfig.Priority.ToLower()
        }
        
        # Send email using Microsoft Graph
        $RequestBody = @{
            message = $Message
            saveToSentItems = $false
        } | ConvertTo-Json -Depth 10
        
        $Uri = "https://graph.microsoft.com/v1.0/me/sendMail"
        Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $RequestBody -ContentType "application/json"
        
        Write-Information "✓ Email notification sent successfully to: $($Recipients -join ', ')" -InformationAction Continue
        return $true
    }
    catch {
        Write-Error "Failed to send email notification: $($_.Exception.Message)"
        return $false
    }
}

# Function to perform your specific monitoring logic - CUSTOMIZE THIS EXTENSIVELY
function Get-MonitoringData {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )
    
    try {
        Write-Information "Gathering monitoring data..." -InformationAction Continue
        
        # REPLACE THIS SECTION WITH YOUR SPECIFIC MONITORING LOGIC
        # Examples of what you might monitor:
        
        # Example 1: Monitor device compliance
        # $Devices = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        
        # Example 2: Monitor application assignments
        # $Apps = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
        
        # Example 3: Monitor certificate expiration
        # $Certificates = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
        
        # For this template, we'll create sample data
        $MonitoringResults = @()
        
        # Simulate some monitoring results
        for ($i = 1; $i -le 10; $i++) {
            $Status = if ($i -le 2) { "Critical" } elseif ($i -le 5) { "Warning" } else { "OK" }
            
            $MonitoringResults += [PSCustomObject]@{
                Name = "Sample Item $i"
                Status = $Status
                Value = Get-Random -Minimum 1 -Maximum 100
                LastChecked = (Get-Date).AddHours(-$i)
                Platform = @("Windows", "iOS", "Android", "macOS") | Get-Random
                Details = "Sample details for item $i"
            }
        }
        
        Write-Information "✓ Retrieved $($MonitoringResults.Count) monitoring items" -InformationAction Continue
        return $MonitoringResults
    }
    catch {
        Write-Error "Failed to gather monitoring data: $($_.Exception.Message)"
        return @()
    }
}

# Function to analyze data and determine alerts - CUSTOMIZE BASED ON YOUR CRITERIA
function Get-AlertAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        [array]$MonitoringData,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )
    
    $AlertData = @()
    $Summary = @{
        TotalCount = $MonitoringData.Count
        CriticalCount = 0
        WarningCount = 0
        HealthyCount = 0
    }
    
    # Apply platform filter if specified
    if ($Config.PlatformFilter -ne "All") {
        $MonitoringData = $MonitoringData | Where-Object { $_.Platform -eq $Config.PlatformFilter }
        Write-Information "Applied platform filter: $($Config.PlatformFilter). $($MonitoringData.Count) items remaining." -InformationAction Continue
    }
    
    foreach ($Item in $MonitoringData) {
        # CUSTOMIZE THIS LOGIC BASED ON YOUR MONITORING CRITERIA
        
        # Example criteria - replace with your specific conditions
        $Level = "Info"
        $ShouldAlert = $false
        
        if ($Item.Status -eq "Critical") {
            $Level = "Critical"
            $ShouldAlert = $true
            $Summary.CriticalCount++
        }
        elseif ($Item.Status -eq "Warning") {
            $Level = "Warning"
            $ShouldAlert = $true
            $Summary.WarningCount++
        }
        else {
            $Summary.HealthyCount++
        }
        
        if ($ShouldAlert) {
            $AlertData += [PSCustomObject]@{
                Title = "Alert: $($Item.Name)"
                Details = "Status: $($Item.Status) | Platform: $($Item.Platform) | Value: $($Item.Value) | Last Checked: $($Item.LastChecked)"
                Level = $Level
                ItemName = $Item.Name
                Platform = $Item.Platform
                Value = $Item.Value
            }
        }
    }
    
    return @{
        AlertData = $AlertData
        Summary = $Summary
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting [Your Alert Type] monitoring..." -InformationAction Continue
    Write-Information "Threshold Parameter: $ThresholdParameter" -InformationAction Continue
    Write-Information "Platform Filter: $PlatformFilter" -InformationAction Continue
    Write-Information "Email Recipients: $EmailRecipients" -InformationAction Continue
    
    # Step 1: Gather monitoring data
    $MonitoringData = Get-MonitoringData -Config $MonitoringConfig
    
    if ($MonitoringData.Count -eq 0) {
        Write-Information "No monitoring data found. Exiting without sending notifications." -InformationAction Continue
        exit 0
    }
    
    # Step 2: Analyze data and determine alerts
    $Analysis = Get-AlertAnalysis -MonitoringData $MonitoringData -Config $MonitoringConfig
    $AlertData = $Analysis.AlertData
    $Summary = $Analysis.Summary
    
    Write-Information "Analysis complete: $($Summary.CriticalCount) critical, $($Summary.WarningCount) warning, $($Summary.HealthyCount) healthy" -InformationAction Continue
    
    # Step 3: Determine if notification should be sent
    $ShouldSendNotification = $Summary.CriticalCount -gt 0 -or $Summary.WarningCount -gt 0
    
    if (-not $ShouldSendNotification) {
        Write-Information "✓ No issues detected. No notification needed." -InformationAction Continue
        exit 0
    }
    
    # Step 4: Create and send email notification
    Write-Information "Issues detected. Preparing email notification..." -InformationAction Continue
    
    # Prepare email subject
    $AlertLevel = if ($Summary.CriticalCount -gt 0) { "CRITICAL" } else { "WARNING" }
    $Subject = "[$AlertLevel] [Your Organization] - [Your Alert Type] Alert - $($Summary.CriticalCount) Critical, $($Summary.WarningCount) Warning"
    
    # Generate email body
    $EmailBody = New-EmailBody -AlertData $AlertData -Summary $Summary
    
    # Parse email recipients
    $Recipients = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() }
    
    # Send email notification
    $EmailSent = Send-EmailNotification -Body $EmailBody -Recipients $Recipients -Subject $Subject
    
    if ($EmailSent) {
        Write-Information "✓ Notification sent successfully" -InformationAction Continue
    } else {
        Write-Error "Failed to send email notification"
        exit 1
    }
    
    Write-Information "✓ [Your Alert Type] monitoring completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Ignore disconnect errors
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
[Your Alert Type] Monitoring Summary
========================================
Threshold: $ThresholdParameter
Platform Filter: $PlatformFilter
Total Items Monitored: $($Summary.TotalCount)
Critical Issues: $($Summary.CriticalCount)
Warning Issues: $($Summary.WarningCount)
Healthy Items: $($Summary.HealthyCount)
Notification Sent: $(if ($ShouldSendNotification) { 'Yes' } else { 'No' })
Recipients: $EmailRecipients
========================================
" -InformationAction Continue