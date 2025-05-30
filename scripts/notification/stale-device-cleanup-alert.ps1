<#
.TITLE
    Stale Device Cleanup Alert Notification

.SYNOPSIS
    Automated runbook to monitor stale devices in Intune and send email alerts for cleanup recommendations.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors devices in 
    Microsoft Intune that haven't checked in for a specified number of days. It identifies stale 
    devices across different platforms (Windows, iOS, Android, macOS) and sends email notifications 
    to administrators with cleanup recommendations. The script helps maintain a clean device inventory 
    and optimize licensing costs by identifying devices that may no longer be in use.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,Mail.Send

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
    Weekly

.CATEGORY
    Notification

.EXAMPLE
    .\stale-device-cleanup-alert.ps1 -StaleAfterDays 90 -EmailRecipients "admin@company.com"
    Identifies devices that haven't checked in for 90+ days and sends alerts to admin@company.com

.EXAMPLE
    .\stale-device-cleanup-alert.ps1 -StaleAfterDays 60 -EmailRecipients "admin@company.com,security@company.com"
    Identifies devices that haven't checked in for 60+ days and sends alerts to multiple recipients

.NOTES
    - Requires Microsoft.Graph.Authentication and Microsoft.Graph.Mail modules
    - For Azure Automation, configure Managed Identity with required permissions
    - Uses Microsoft Graph Mail API for email notifications only
    - Recommended to run as scheduled runbook (weekly or monthly)
    - Consider your organization's device usage patterns when setting staleness threshold
    - Review cleanup recommendations before taking action on devices
    - Critical for maintaining accurate device inventory and license optimization
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Number of days since last check-in to consider a device stale")]
    [ValidateRange(7, 365)]
    [int]$StaleAfterDays,
    
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

function Get-DevicePlatform {
    param([string]$OperatingSystem)
    
    switch -Regex ($OperatingSystem) {
        "^Windows" { return "Windows" }
        "^iOS" { return "iOS" }
        "^iPadOS" { return "iPadOS" }
        "^Android" { return "Android" }
        "^macOS" { return "macOS" }
        "^ChromeOS" { return "ChromeOS" }
        default { return "Other" }
    }
}

function Get-DeviceStatus {
    param(
        [datetime]$LastSyncDateTime,
        [int]$StaleThreshold
    )
    
    $DaysSinceLastSync = ((Get-Date) - $LastSyncDateTime).Days
    
    if ($DaysSinceLastSync -gt $StaleThreshold) {
        return "Stale"
    }
    elseif ($DaysSinceLastSync -gt ($StaleThreshold * 0.8)) {
        return "Warning"
    }
    else {
        return "Active"
    }
}

function Format-TimeSpan {
    param([datetime]$Date)
    
    $TimeSpan = (Get-Date) - $Date
    
    if ($TimeSpan.TotalDays -lt 1) {
        return "Today"
    }
    elseif ($TimeSpan.TotalDays -lt 2) {
        return "1 day ago"
    }
    else {
        return "$([math]::Round($TimeSpan.TotalDays)) days ago"
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

# Function creates email content, does not change system state
function New-EmailBody {
    param(
        [array]$AllDevices,
        [array]$StaleDevices,
        [array]$WarningDevices,
        [int]$StaleThreshold
    )
    
    $PlatformSummary = $StaleDevices | Group-Object Platform | Sort-Object Name
    $TotalDevices = $AllDevices.Count
    $StaleCount = $StaleDevices.Count
    $WarningCount = $WarningDevices.Count
    $ActiveCount = $TotalDevices - $StaleCount - $WarningCount
    
    $Body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; }
        .header { background-color: #0078d4; color: white; padding: 15px; border-radius: 5px; }
        .summary { background-color: #f8f9fa; padding: 15px; margin: 15px 0; border-radius: 5px; border-left: 4px solid #0078d4; }
        .stale { background-color: #fdf2f2; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        .warning { background-color: #fffbf0; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .recommendations { background-color: #e8f5e8; border-left: 4px solid #28a745; padding: 10px; margin: 10px 0; }
        .device-item { margin: 5px 0; padding: 8px; background-color: white; border-radius: 3px; font-size: 14px; }
        .platform-summary { margin: 10px 0; padding: 8px; background-color: #f0f0f0; border-radius: 3px; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
        .stats-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin: 15px 0; }
        .stat-card { background-color: white; padding: 15px; border-radius: 5px; text-align: center; border: 1px solid #ddd; }
        h2 { color: #333; }
        h3 { color: #555; margin-top: 20px; }
        .status-icon { font-size: 16px; margin-right: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .center { text-align: center; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧹 Stale Device Cleanup Alert</h1>
        <p>Devices inactive for $StaleThreshold+ days requiring attention</p>
    </div>
    
    <div class="summary">
        <h2>Device Inventory Summary</h2>
        <div class="stats-grid">
            <div class="stat-card">
                <h3 style="margin: 0; color: #28a745;">$ActiveCount</h3>
                <p style="margin: 5px 0;">Active Devices</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #ffc107;">$WarningCount</h3>
                <p style="margin: 5px 0;">Warning Devices</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #dc3545;">$StaleCount</h3>
                <p style="margin: 5px 0;">Stale Devices</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #0078d4;">$TotalDevices</h3>
                <p style="margin: 5px 0;">Total Devices</p>
            </div>
        </div>
    </div>
"@

    if ($StaleCount -gt 0) {
        $Body += @"
    <div class="stale">
        <h3><span class="status-icon">🚨</span>Stale Devices - Cleanup Recommended ($StaleCount devices)</h3>
        
        <h4>Platform Breakdown:</h4>
"@
        foreach ($Platform in $PlatformSummary) {
            $Body += @"
        <div class="platform-summary">
            <strong>$($Platform.Name):</strong> $($Platform.Count) devices
        </div>
"@
        }

        $Body += @"
        <h4>Device Details:</h4>
        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Last Check-in</th>
                <th>Days Inactive</th>
                <th>Compliance</th>
            </tr>
"@
        
        foreach ($Device in ($StaleDevices | Sort-Object DaysSinceLastSync -Descending | Select-Object -First 20)) {
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd'))</td>
                <td class="center">$($Device.DaysSinceLastSync)</td>
                <td>$($Device.ComplianceState)</td>
            </tr>
"@
        }
        
        if ($StaleDevices.Count -gt 20) {
            $Body += @"
            <tr>
                <td colspan="6" class="center"><em>... and $($StaleDevices.Count - 20) more devices</em></td>
            </tr>
"@
        }
        
        $Body += "</table></div>"
    }

    if ($WarningCount -gt 0) {
        $Body += @"
    <div class="warning">
        <h3><span class="status-icon">⚠️</span>Warning Devices - Monitor Closely ($WarningCount devices)</h3>
        <p>These devices are approaching the staleness threshold and should be monitored:</p>
        
        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Last Check-in</th>
                <th>Days Inactive</th>
            </tr>
"@
        
        foreach ($Device in ($WarningDevices | Sort-Object DaysSinceLastSync -Descending | Select-Object -First 10)) {
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd'))</td>
                <td class="center">$($Device.DaysSinceLastSync)</td>
            </tr>
"@
        }
        
        if ($WarningDevices.Count -gt 10) {
            $Body += @"
            <tr>
                <td colspan="5" class="center"><em>... and $($WarningDevices.Count - 10) more devices</em></td>
            </tr>
"@
        }
        
        $Body += "</table></div>"
    }

    $Body += @"
    <div class="recommendations">
        <h3><span class="status-icon">💡</span>Cleanup Recommendations</h3>
        <h4>Before Taking Action:</h4>
        <ul>
            <li><strong>Verify Device Status:</strong> Contact device users to confirm devices are truly inactive</li>
            <li><strong>Check Recent Activity:</strong> Review device logs for any recent activity not reflected in Intune</li>
            <li><strong>Consider Seasonal Patterns:</strong> Account for vacation periods, temporary leave, or project cycles</li>
            <li><strong>Backup Important Data:</strong> Ensure any critical data is backed up before device removal</li>
        </ul>
        
        <h4>Cleanup Actions:</h4>
        <ul>
            <li><strong>Retire Devices:</strong> For devices confirmed as no longer in use</li>
            <li><strong>Remove from Intune:</strong> Clean up device records and free up licenses</li>
            <li><strong>Update Asset Inventory:</strong> Reflect changes in your asset management system</li>
            <li><strong>Review Policies:</strong> Update device-based policies and group memberships</li>
        </ul>
        
        <h4>License Impact:</h4>
        <p><strong>Potential License Savings:</strong> Removing $StaleCount stale devices could free up Intune licenses for new device enrollments.</p>
    </div>
    
    <div class="footer">
        <p><strong>Next Steps:</strong></p>
        <ol>
            <li>Review the stale device list and verify device status with users</li>
            <li>Use the existing stale device cleanup script in your automation repository</li>
            <li>Monitor device activity for the warning devices over the next few weeks</li>
            <li>Update your device management policies based on usage patterns</li>
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
    Write-Information "Starting stale device cleanup monitoring..." -InformationAction Continue
    
    # Parse email recipients
    $EmailRecipientList = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    
    if ($EmailRecipientList.Count -eq 0) {
        throw "No valid email recipients provided"
    }
    
    Write-Information "Email recipients: $($EmailRecipientList -join ', ')" -InformationAction Continue
    Write-Information "Stale device threshold: $StaleAfterDays days" -InformationAction Continue
    
    # Initialize results arrays
    $AllDevices = @()
    $StaleDevices = @()
    $WarningDevices = @()
    
    # Calculate cutoff date for stale devices
    $StaleThresholdDate = (Get-Date).AddDays(-$StaleAfterDays)
    $WarningThresholdDate = (Get-Date).AddDays( - ($StaleAfterDays * 0.8))
    
    Write-Information "Stale threshold date: $($StaleThresholdDate.ToString('yyyy-MM-dd'))" -InformationAction Continue
    Write-Information "Warning threshold date: $($WarningThresholdDate.ToString('yyyy-MM-dd'))" -InformationAction Continue
    
    # ========================================================================
    # GET ALL MANAGED DEVICES
    # ========================================================================
    
    Write-Information "Retrieving all managed devices from Intune..." -InformationAction Continue
    
    try {
        $DevicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        $Devices = Get-MgGraphAllPage -Uri $DevicesUri
        Write-Information "Found $($Devices.Count) managed devices" -InformationAction Continue
        
        foreach ($Device in $Devices) {
            try {
                # Skip devices without essential information
                if (-not $Device.lastSyncDateTime -or -not $Device.id) {
                    Write-Verbose "Skipping device with missing essential data (ID: $($Device.id))"
                    continue
                }
                
                $LastSyncDateTime = [datetime]$Device.lastSyncDateTime
                $EnrolledDateTime = if ($Device.enrolledDateTime) { [datetime]$Device.enrolledDateTime } else { $null }
                $DaysSinceLastSync = ((Get-Date) - $LastSyncDateTime).Days
                $Platform = Get-DevicePlatform -OperatingSystem $Device.operatingSystem
                $DeviceStatus = Get-DeviceStatus -LastSyncDateTime $LastSyncDateTime -StaleThreshold $StaleAfterDays
                
                $DeviceInfo = [PSCustomObject]@{
                    DeviceId          = $Device.id
                    DeviceName        = if ($Device.deviceName) { $Device.deviceName } else { "Unknown" }
                    Platform          = $Platform
                    OperatingSystem   = $Device.operatingSystem
                    OSVersion         = $Device.osVersion
                    UserDisplayName   = if ($Device.userDisplayName) { $Device.userDisplayName } else { "Unassigned" }
                    UserPrincipalName = if ($Device.userPrincipalName) { $Device.userPrincipalName } else { "N/A" }
                    LastSyncDateTime  = $LastSyncDateTime
                    EnrolledDateTime  = $EnrolledDateTime
                    DaysSinceLastSync = $DaysSinceLastSync
                    LastSyncStatus    = Format-TimeSpan -Date $LastSyncDateTime
                    ComplianceState   = if ($Device.complianceState) { $Device.complianceState } else { "Unknown" }
                    ManagementState   = if ($Device.managementState) { $Device.managementState } else { "Unknown" }
                    DeviceStatus      = $DeviceStatus
                    SerialNumber      = $Device.serialNumber
                    Model             = $Device.model
                    Manufacturer      = $Device.manufacturer
                }
                
                $AllDevices += $DeviceInfo
                
                # Categorize devices based on status
                if ($DeviceStatus -eq "Stale") {
                    $StaleDevices += $DeviceInfo
                }
                elseif ($DeviceStatus -eq "Warning") {
                    $WarningDevices += $DeviceInfo
                }
            }
            catch {
                Write-Verbose "Error processing device (ID: $($Device.id)): $($_.Exception.Message)"
                continue
            }
        }
        
        Write-Information "✓ Processed $($AllDevices.Count) devices successfully" -InformationAction Continue
        Write-Information "  • Active devices: $(($AllDevices | Where-Object { $_.DeviceStatus -eq 'Active' }).Count)" -InformationAction Continue
        Write-Information "  • Warning devices: $($WarningDevices.Count)" -InformationAction Continue
        Write-Information "  • Stale devices: $($StaleDevices.Count)" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to retrieve managed devices: $($_.Exception.Message)"
        exit 1
    }
    
    # ========================================================================
    # SEND NOTIFICATIONS IF STALE DEVICES FOUND
    # ========================================================================
    
    if ($StaleDevices.Count -gt 0 -or $WarningDevices.Count -gt 0) {
        Write-Information "Preparing email notification for device cleanup..." -InformationAction Continue
        
        $Subject = if ($StaleDevices.Count -gt 0) {
            "[Intune Alert] CLEANUP REQUIRED: $($StaleDevices.Count) Stale Device(s) Found"
        }
        else {
            "[Intune Alert] WARNING: $($WarningDevices.Count) Device(s) Approaching Staleness"
        }
        
        $EmailBody = New-EmailBody -AllDevices $AllDevices -StaleDevices $StaleDevices -WarningDevices $WarningDevices -StaleThreshold $StaleAfterDays
        
        Send-EmailNotification -Recipients $EmailRecipientList -Subject $Subject -Body $EmailBody
        
        Write-Information "✓ Email notification sent to $($EmailRecipientList.Count) recipients" -InformationAction Continue
    }
    else {
        Write-Information "✓ No stale or warning devices found. All devices are actively checking in." -InformationAction Continue
    }
    
    # ========================================================================
    # DISPLAY SUMMARY
    # ========================================================================
    
    Write-Information "`n🧹 STALE DEVICE CLEANUP MONITORING SUMMARY" -InformationAction Continue
    Write-Information "===========================================" -InformationAction Continue
    Write-Information "Total Managed Devices: $($AllDevices.Count)" -InformationAction Continue
    Write-Information "Stale Threshold: $StaleAfterDays days" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    $ActiveCount = ($AllDevices | Where-Object { $_.DeviceStatus -eq "Active" }).Count
    Write-Information "Device Status Breakdown:" -InformationAction Continue
    Write-Information "  • Active: $ActiveCount" -InformationAction Continue
    Write-Information "  • Warning: $($WarningDevices.Count)" -InformationAction Continue
    Write-Information "  • Stale: $($StaleDevices.Count)" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    if ($StaleDevices.Count -gt 0) {
        Write-Information "Platform Breakdown (Stale Devices):" -InformationAction Continue
        $PlatformGroups = $StaleDevices | Group-Object Platform | Sort-Object Name
        foreach ($Group in $PlatformGroups) {
            Write-Information "  • $($Group.Name): $($Group.Count) devices" -InformationAction Continue
        }
        Write-Information "" -InformationAction Continue
    }
    
    if ($StaleDevices.Count -gt 0) {
        Write-Information "Top 5 Oldest Stale Devices:" -InformationAction Continue
        $TopStaleDevices = $StaleDevices | Sort-Object DaysSinceLastSync -Descending | Select-Object -First 5
        foreach ($Device in $TopStaleDevices) {
            Write-Information "  🔸 $($Device.DeviceName) ($($Device.Platform)) - $($Device.DaysSinceLastSync) days" -InformationAction Continue
        }
    }
    
    Write-Information "`n✓ Stale device cleanup monitoring completed successfully" -InformationAction Continue
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
Script: Stale Device Cleanup Alert
Total Devices Analyzed: $($AllDevices.Count)
Stale Devices Found: $($StaleDevices.Count)
Warning Devices Found: $($WarningDevices.Count)
Email Recipients: $($EmailRecipientList.Count)
Staleness Threshold: $StaleAfterDays days
Status: Completed
========================================
" -InformationAction Continue