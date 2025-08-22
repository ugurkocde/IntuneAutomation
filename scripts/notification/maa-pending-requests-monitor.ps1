<#
.TITLE
    Multi-Admin Approval Pending Requests Monitor

.SYNOPSIS
    Automated runbook to monitor Multi-Admin Approval (MAA) pending requests in Intune and send email alerts to approvers.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors Multi-Admin Approval 
    requests in Microsoft Intune and identifies pending approval requests. It tracks new requests, monitors 
    request age, identifies approvers, and sends email notifications to administrators with detailed request 
    information and direct links to the Intune portal. The script helps maintain security compliance by ensuring 
    timely review of administrative changes and provides visibility into the MAA approval workflow.

    Key Features:
    - Monitors all MAA pending requests across protected resources
    - Tracks request age and highlights urgent requests
    - Identifies and notifies appropriate approvers
    - Provides direct links to Intune portal for quick action
    - Tracks previously notified requests to avoid spam
    - Sends escalation alerts for aging requests
    - Supports both Azure Automation runbook and local execution
    - HTML formatted email reports with actionable insights
    - Uses Microsoft Graph Mail API exclusively

.TAGS
    Notification,Security,RunbookOnly,Email,Monitoring,MAA,Compliance

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All,DeviceManagementManagedDevices.Read.All,DeviceManagementRBAC.Read.All,AuditLog.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Hourly

.CATEGORY
    Notification

.EXAMPLE
    .\maa-pending-requests-monitor.ps1 -EmailRecipients "security@company.com" -UrgentThresholdHours 24
    Monitors MAA requests and alerts security team, marking requests older than 24 hours as urgent

.EXAMPLE
    .\maa-pending-requests-monitor.ps1 -EmailRecipients "admin@company.com,security@company.com" -UrgentThresholdHours 48 -EscalationThresholdHours 72
    Monitors MAA requests with multiple recipients and escalation for requests older than 72 hours

.NOTES
    - Requires Microsoft.Graph.Authentication and Microsoft.Graph.Mail modules
    - For Azure Automation, configure Managed Identity with required permissions
    - This script is designed specifically for Azure Automation runbooks
    - Email notifications are sent via Microsoft Graph Mail API
    - Recommended to run hourly to ensure timely notifications
    - Stores state in Azure Automation variables to track notified requests
    - Critical for maintaining MAA compliance and security posture
#>

[CmdletBinding()]
param(
    # Email recipients for notifications
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to receive notifications")]
    [ValidateScript({
            if ($_ -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(,[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})*$') {
                $true
            }
            else {
                throw "Please provide valid email addresses separated by commas"
            }
        })]
    [string]$EmailRecipients,
    
    # Threshold for marking requests as urgent
    [Parameter(Mandatory = $false, HelpMessage = "Hours before marking a request as urgent")]
    [ValidateRange(1, 168)]
    [int]$UrgentThresholdHours = 24,
    
    # Threshold for escalation alerts
    [Parameter(Mandatory = $false, HelpMessage = "Hours before sending escalation alerts")]
    [ValidateRange(1, 720)]
    [int]$EscalationThresholdHours = 72,
    
    # Include approved/rejected requests in summary
    [Parameter(Mandatory = $false, HelpMessage = "Include recently processed requests in notification")]
    [switch]$IncludeProcessedRequests,
    
    # Force notification even if no new requests
    [Parameter(Mandatory = $false, HelpMessage = "Send notification even if no new pending requests")]
    [switch]$ForceNotification,
    
    # Force module installation without prompting
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
        
        # Check if module is already loaded
        $loadedModule = Get-Module -Name $ModuleName
        if ($loadedModule) {
            Write-Verbose "Module '$ModuleName' is already loaded (version $($loadedModule.Version))"
            continue
        }
        
        # Check if module is available
        $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1
        
        if (-not $module) {
            if ($IsAutomationEnvironment) {
                $errorMessage = @"
Module '$ModuleName' is not available in this Azure Automation Account.
Please install it from the Browse Gallery in the Azure portal.
Required modules: $($ModuleNames -join ', ')
"@
                Write-Error $errorMessage
                throw "Required module not found: $ModuleName"
            }
            else {
                Write-Information "Module '$ModuleName' not found. Installing..." -InformationAction Continue
                
                if (-not $ForceInstall) {
                    $response = Read-Host "Module '$ModuleName' is required but not installed. Install it now? (Y/N)"
                    if ($response -ne 'Y' -and $response -ne 'y') {
                        Write-Error "Module installation cancelled. Cannot proceed without required module."
                        exit 1
                    }
                }
                
                try {
                    Write-Information "Installing module: $ModuleName" -InformationAction Continue
                    Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                    Write-Information "✓ Successfully installed module: $ModuleName" -InformationAction Continue
                    
                    # Refresh available modules
                    $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1
                }
                catch {
                    Write-Error "Failed to install module '$ModuleName': $($_.Exception.Message)"
                    Write-Error "Please install manually: Install-Module -Name $ModuleName -Scope CurrentUser"
                    exit 1
                }
            }
        }
        
        # Import module only if not already loaded
        if (-not (Get-Module -Name $ModuleName)) {
            try {
                Import-Module $ModuleName -ErrorAction Stop
                Write-Verbose "✓ Successfully imported module: $ModuleName"
            }
            catch {
                # If import fails due to version conflict, try removing and re-importing
                if ($_.Exception.Message -like "*Assembly with same name is already loaded*") {
                    Write-Warning "Module version conflict detected. Attempting to resolve..."
                    try {
                        Remove-Module $ModuleName -ErrorAction SilentlyContinue
                        Import-Module $ModuleName -ErrorAction Stop
                        Write-Verbose "✓ Successfully resolved and imported module: $ModuleName"
                    }
                    catch {
                        Write-Warning "Could not resolve module conflict for '$ModuleName'. Using existing loaded version."
                    }
                }
                else {
                    Write-Error "Failed to import module '$ModuleName': $($_.Exception.Message)"
                    exit 1
                }
            }
        }
    }
}

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if running in Azure Automation
$RunningInAzureAutomation = $null -ne $env:AUTOMATION_ASSET_ACCOUNTID

# Required modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Mail"
)

# Initialize required modules
Initialize-RequiredModule -ModuleNames $RequiredModules -IsAutomationEnvironment $RunningInAzureAutomation -ForceInstall $ForceModuleInstall

# Connect to Microsoft Graph
try {
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    
    if ($RunningInAzureAutomation) {
        # Use Managed Identity in Azure Automation
        Connect-MgGraph -Identity -NoWelcome
        Write-Information "✓ Connected to Microsoft Graph using Managed Identity" -InformationAction Continue
    }
    else {
        # Use interactive authentication for local execution
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementApps.Read.All",
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementRBAC.Read.All",
            "AuditLog.Read.All",
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
    Subject     = "[MAA ALERT] Pending Approval Requests Require Action"
    FromAddress = "noreply@yourdomain.com"
    Priority    = "High"
}

# Portal URLs
$IntunePortalBaseUrl = "https://intune.microsoft.com"
$MAARequestsUrl = "$IntunePortalBaseUrl/#view/Microsoft_Intune_DeviceSettings/MultiAdminApprovalMenu/~/received"

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
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
        }
    } while ($NextLink)
    
    return $AllResults
}

# Function to get MAA pending requests
function Get-MAAPendingRequest {
    try {
        Write-Information "Retrieving MAA pending requests..." -InformationAction Continue
        
        $PendingRequests = @()
        
        # Get all operation approval requests from the correct endpoint
        try {
            $Uri = "https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests"
            Write-Information "Querying MAA requests from: $Uri" -InformationAction Continue
            
            $AllRequests = Get-MgGraphAllPage -Uri $Uri -DelayMs 200
            
            foreach ($Request in $AllRequests) {
                # Check if request is pending (status = 0 or status field indicates pending)
                # MAA request statuses: 0 = Pending, 1 = Approved, 2 = Rejected, 3 = Cancelled, 4 = Completed
                if ($Request.status -eq 0 -or $Request.status -eq "pending" -or $Request.status -eq "needsApproval") {
                    
                    # Calculate age and expiry
                    $RequestDateTime = if ($Request.requestDateTime) { [DateTime]$Request.requestDateTime } 
                    elseif ($Request.createdDateTime) { [DateTime]$Request.createdDateTime }
                    else { [DateTime]::Now }
                    
                    $AgeInHours = [Math]::Round(((Get-Date) - $RequestDateTime).TotalHours, 1)
                    $DaysUntilExpiry = [Math]::Round((30 - ((Get-Date) - $RequestDateTime).TotalDays), 1)
                    
                    # Get requester information
                    $RequesterName = if ($Request.requester.displayName) { $Request.requester.displayName }
                    elseif ($Request.requestor.displayName) { $Request.requestor.displayName }
                    else { "Unknown" }
                    
                    $RequesterEmail = if ($Request.requester.userPrincipalName) { $Request.requester.userPrincipalName }
                    elseif ($Request.requestor.userPrincipalName) { $Request.requestor.userPrincipalName }
                    elseif ($Request.requester.mail) { $Request.requester.mail }
                    else { "Unknown" }
                    
                    # Get resource information
                    $ResourceName = if ($Request.requestedOperationDisplayName) { $Request.requestedOperationDisplayName }
                    elseif ($Request.displayName) { $Request.displayName }
                    elseif ($Request.operationDisplayName) { $Request.operationDisplayName }
                    else { "Unknown Operation" }
                    
                    $ResourceType = if ($Request.requestedResourceType) { $Request.requestedResourceType }
                    elseif ($Request.resourceType) { $Request.resourceType }
                    elseif ($Request.operationType) { $Request.operationType }
                    else { "Unknown" }
                    
                    $PendingRequest = [PSCustomObject]@{
                        Id                    = $Request.id
                        RequestTime           = $RequestDateTime
                        RequestedBy           = $RequesterEmail
                        RequestedByName       = $RequesterName
                        ResourceType          = $ResourceType
                        ResourceName          = $ResourceName
                        BusinessJustification = if ($Request.requestJustification) { $Request.requestJustification } 
                        elseif ($Request.justification) { $Request.justification }
                        else { "No justification provided" }
                        Status                = "Pending"
                        AgeInHours            = $AgeInHours
                        DaysUntilExpiry       = $DaysUntilExpiry
                        ApprovalPolicy        = if ($Request.approvalPolicyId) { $Request.approvalPolicyId } else { "N/A" }
                    }
                    
                    $PendingRequests += $PendingRequest
                }
            }
            
            Write-Information "✓ Found $($PendingRequests.Count) pending MAA requests" -InformationAction Continue
        }
        catch {
            Write-Warning "Could not retrieve MAA requests: $($_.Exception.Message)"
            
            # Fallback: Try to get from audit logs
            try {
                Write-Information "Attempting fallback to audit logs..." -InformationAction Continue
                $StartDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
                $Filter = "activityDateTime ge $StartDate"
                
                $AuditLogs = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$Filter&`$top=100"
                
                foreach ($Log in $AuditLogs) {
                    # Look for multi-admin approval related activities
                    if ($Log.activityDisplayName -like "*Multi*Admin*" -or 
                        $Log.activityDisplayName -like "*Approval*Request*" -or
                        $Log.category -eq "Policy" -and $Log.result -eq "pending") {
                        
                        $PendingRequest = [PSCustomObject]@{
                            Id                    = $Log.id
                            RequestTime           = [DateTime]$Log.activityDateTime
                            RequestedBy           = if ($Log.initiatedBy.user.userPrincipalName) { $Log.initiatedBy.user.userPrincipalName } else { "Unknown" }
                            RequestedByName       = if ($Log.initiatedBy.user.displayName) { $Log.initiatedBy.user.displayName } else { "Unknown" }
                            ResourceType          = if ($Log.targetResources[0].type) { $Log.targetResources[0].type } else { "Policy" }
                            ResourceName          = if ($Log.targetResources[0].displayName) { $Log.targetResources[0].displayName } else { $Log.activityDisplayName }
                            BusinessJustification = "See audit log for details"
                            Status                = "Pending"
                            AgeInHours            = [Math]::Round(((Get-Date) - [DateTime]$Log.activityDateTime).TotalHours, 1)
                            DaysUntilExpiry       = [Math]::Round((30 - ((Get-Date) - [DateTime]$Log.activityDateTime).TotalDays), 1)
                            ApprovalPolicy        = "N/A"
                        }
                        
                        $PendingRequests += $PendingRequest
                    }
                }
            }
            catch {
                Write-Warning "Fallback to audit logs also failed: $($_.Exception.Message)"
            }
        }
        
        # Get operation approval policies for additional context if needed
        try {
            $PoliciesUri = "https://graph.microsoft.com/beta/deviceManagement/operationApprovalPolicies"
            Write-Information "Retrieving MAA policies from: $PoliciesUri" -InformationAction Continue
            $Policies = Get-MgGraphAllPage -Uri $PoliciesUri -DelayMs 200
            
            # Add policy information to requests if available
            foreach ($Request in $PendingRequests) {
                if ($Request.ApprovalPolicy -ne "N/A") {
                    $Policy = $Policies | Where-Object { $_.id -eq $Request.ApprovalPolicy }
                    if ($Policy) {
                        $Request | Add-Member -NotePropertyName "PolicyName" -NotePropertyValue $Policy.displayName -Force
                    }
                }
            }
        }
        catch {
            Write-Information "Could not retrieve MAA policies (non-critical): $($_.Exception.Message)" -InformationAction Continue
        }
        
        return $PendingRequests
    }
    catch {
        Write-Error "Failed to retrieve MAA pending requests: $($_.Exception.Message)"
        return @()
    }
}

# Function to get recently processed requests
function Get-ProcessedRequest {
    param(
        [int]$HoursBack = 24
    )
    
    try {
        Write-Information "Retrieving recently processed MAA requests..." -InformationAction Continue
        
        $ProcessedRequests = @()
        $StartDate = (Get-Date).AddHours(-$HoursBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $Filter = "activityDateTime ge $StartDate and category eq 'Policy' and (result eq 'success' or result eq 'failure')"
        
        $AuditLogs = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$Filter&`$orderby=activityDateTime desc"
        
        foreach ($Log in $AuditLogs) {
            if ($Log.activityDisplayName -like "*approval*") {
                $Request = [PSCustomObject]@{
                    Id            = $Log.id
                    ProcessedTime = [DateTime]$Log.activityDateTime
                    RequestedBy   = $Log.initiatedBy.user.userPrincipalName
                    ApprovedBy    = $Log.targetResources[0].userPrincipalName
                    ResourceName  = $Log.targetResources[0].displayName
                    Result        = if ($Log.result -eq "success") { "Approved" } else { "Rejected" }
                    ApproverNotes = $Log.additionalDetails | Where-Object { $_.key -eq "approverNotes" } | Select-Object -ExpandProperty value
                }
                $ProcessedRequests += $Request
            }
        }
        
        return $ProcessedRequests
    }
    catch {
        Write-Warning "Failed to retrieve processed requests: $($_.Exception.Message)"
        return @()
    }
}

# Function to get stored notification state
function Get-NotificationState {
    if ($RunningInAzureAutomation) {
        try {
            $State = Get-AutomationVariable -Name "MAANotificationState"
            return $State | ConvertFrom-Json
        }
        catch {
            return @{ NotifiedRequests = @(); LastRun = (Get-Date).ToString() }
        }
    }
    else {
        # For local testing, use a temp file
        $StateFile = "$env:TEMP\maa-notification-state.json"
        if (Test-Path $StateFile) {
            return Get-Content $StateFile | ConvertFrom-Json
        }
        return @{ NotifiedRequests = @(); LastRun = (Get-Date).ToString() }
    }
}

# Function to save notification state
function Set-NotificationState {
    param($State)
    
    if ($RunningInAzureAutomation) {
        try {
            Set-AutomationVariable -Name "MAANotificationState" -Value ($State | ConvertTo-Json -Compress)
        }
        catch {
            Write-Warning "Could not save notification state: $($_.Exception.Message)"
        }
    }
    else {
        # For local testing, use a temp file
        $StateFile = "$env:TEMP\maa-notification-state.json"
        $State | ConvertTo-Json | Set-Content $StateFile
    }
}

# Function to create HTML email body
function New-EmailBody {
    param(
        [array]$PendingRequests,
        [array]$ProcessedRequests,
        [hashtable]$Summary
    )
    
    $UrgentColor = "#dc3545"
    $WarningColor = "#ffc107"
    $NormalColor = "#28a745"
    
    $EmailBody = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MAA Pending Requests Alert</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background-color: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 28px; font-weight: 300; }
        .header .subtitle { margin: 10px 0 0 0; opacity: 0.9; font-size: 16px; }
        .content { padding: 30px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: #f8f9fa; border-left: 4px solid #667eea; padding: 20px; border-radius: 4px; }
        .summary-card h3 { margin: 0 0 10px 0; color: #2c3e50; font-size: 14px; text-transform: uppercase; letter-spacing: 1px; }
        .summary-card .value { font-size: 32px; font-weight: bold; color: #667eea; margin: 0; }
        .summary-card .label { color: #7f8c8d; font-size: 14px; }
        .alert-section { margin: 30px 0; }
        .alert-section h2 { color: #2c3e50; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; }
        .request-card { background: #fff; border: 1px solid #dee2e6; border-radius: 6px; padding: 20px; margin: 15px 0; }
        .request-card.urgent { border-left: 4px solid $UrgentColor; background: #fff5f5; }
        .request-card.warning { border-left: 4px solid $WarningColor; background: #fffbf0; }
        .request-card.normal { border-left: 4px solid $NormalColor; }
        .request-header { display: flex; justify-content: space-between; align-items: start; margin-bottom: 15px; }
        .request-title { font-weight: bold; color: #2c3e50; font-size: 16px; }
        .request-age { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: bold; }
        .age-urgent { background: $UrgentColor; color: white; }
        .age-warning { background: $WarningColor; color: #333; }
        .age-normal { background: $NormalColor; color: white; }
        .request-details { color: #6c757d; font-size: 14px; line-height: 1.6; }
        .request-details strong { color: #495057; }
        .justification-box { background: #f8f9fa; padding: 12px; border-radius: 4px; margin: 10px 0; font-style: italic; }
        .action-button { display: inline-block; background: #667eea; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; margin-top: 15px; }
        .action-button:hover { background: #5a67d8; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #6c757d; font-size: 12px; }
        .processed-section { background: #f0f4f8; border-radius: 6px; padding: 20px; margin: 20px 0; }
        .processed-item { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #dee2e6; }
        .processed-item:last-child { border-bottom: none; }
        .approved { color: $NormalColor; font-weight: bold; }
        .rejected { color: $UrgentColor; font-weight: bold; }
        .expiry-warning { background: #fff3cd; border: 1px solid #ffc107; color: #856404; padding: 10px; border-radius: 4px; margin: 10px 0; }
        .timestamp { color: #6c757d; font-size: 12px; text-align: right; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔔 Multi-Admin Approval Alert</h1>
            <div class="subtitle">Pending requests require your immediate attention</div>
        </div>
        
        <div class="content">
            <div class="summary-grid">
                <div class="summary-card">
                    <h3>Pending Requests</h3>
                    <div class="value">$($Summary.TotalPending)</div>
                    <div class="label">Awaiting Approval</div>
                </div>
                <div class="summary-card">
                    <h3>Urgent Requests</h3>
                    <div class="value">$($Summary.UrgentCount)</div>
                    <div class="label">&gt; $UrgentThresholdHours hours old</div>
                </div>
                <div class="summary-card">
                    <h3>Escalated</h3>
                    <div class="value">$($Summary.EscalatedCount)</div>
                    <div class="label">&gt; $EscalationThresholdHours hours old</div>
                </div>
                <div class="summary-card">
                    <h3>Expiring Soon</h3>
                    <div class="value">$($Summary.ExpiringSoon)</div>
                    <div class="label">&lt; 7 days remaining</div>
                </div>
            </div>
"@

    # Add pending requests section
    if ($PendingRequests.Count -gt 0) {
        $EmailBody += @"
            <div class="alert-section">
                <h2>⏳ Pending Approval Requests</h2>
"@
        
        foreach ($Request in $PendingRequests | Sort-Object -Property AgeInHours -Descending) {
            $AgeClass = if ($Request.AgeInHours -gt $EscalationThresholdHours) { "urgent" }
            elseif ($Request.AgeInHours -gt $UrgentThresholdHours) { "warning" }
            else { "normal" }
            
            $AgeLabel = if ($Request.AgeInHours -gt $EscalationThresholdHours) { "age-urgent" }
            elseif ($Request.AgeInHours -gt $UrgentThresholdHours) { "age-warning" }
            else { "age-normal" }
            
            $EmailBody += @"
                <div class="request-card $AgeClass">
                    <div class="request-header">
                        <div class="request-title">$($Request.ResourceName)</div>
                        <span class="request-age $AgeLabel">$($Request.AgeInHours) hours old</span>
                    </div>
                    <div class="request-details">
                        <strong>Resource Type:</strong> $($Request.ResourceType)<br>
                        <strong>Requested By:</strong> $($Request.RequestedByName) ($($Request.RequestedBy))<br>
                        <strong>Request Time:</strong> $($Request.RequestTime.ToString("yyyy-MM-dd HH:mm:ss"))<br>
                        <strong>Days Until Expiry:</strong> $($Request.DaysUntilExpiry) days
"@
            
            if ($Request.BusinessJustification) {
                $EmailBody += @"
                        <div class="justification-box">
                            <strong>Business Justification:</strong><br>
                            $($Request.BusinessJustification)
                        </div>
"@
            }
            
            if ($Request.DaysUntilExpiry -lt 7) {
                $EmailBody += @"
                        <div class="expiry-warning">
                            ⚠️ This request will expire in $($Request.DaysUntilExpiry) days
                        </div>
"@
            }
            
            $EmailBody += @"
                    </div>
                </div>
"@
        }
        
        $EmailBody += @"
                <a href="$MAARequestsUrl" class="action-button">Review Pending Requests in Intune Portal</a>
            </div>
"@
    }
    else {
        $EmailBody += @"
            <div class="alert-section">
                <h2>✅ No Pending Requests</h2>
                <p>There are currently no MAA requests awaiting approval.</p>
            </div>
"@
    }
    
    # Add processed requests section if requested
    if ($IncludeProcessedRequests -and $ProcessedRequests.Count -gt 0) {
        $EmailBody += @"
            <div class="processed-section">
                <h3>📋 Recently Processed Requests (Last 24 Hours)</h3>
"@
        
        foreach ($Request in $ProcessedRequests | Sort-Object -Property ProcessedTime -Descending) {
            $StatusClass = if ($Request.Result -eq "Approved") { "approved" } else { "rejected" }
            $EmailBody += @"
                <div class="processed-item">
                    <div>
                        <strong>$($Request.ResourceName)</strong><br>
                        <span style="font-size: 12px; color: #6c757d;">
                            Requested by: $($Request.RequestedBy) | 
                            Processed: $($Request.ProcessedTime.ToString("yyyy-MM-dd HH:mm"))
                        </span>
                    </div>
                    <div class="$StatusClass">$($Request.Result)</div>
                </div>
"@
        }
        
        $EmailBody += @"
            </div>
"@
    }
    
    # Add recommendations
    $EmailBody += @"
            <div class="processed-section">
                <h3>📋 Recommended Actions</h3>
                <ul style="color: #495057; line-height: 1.8;">
                    <li>Review all pending requests promptly to maintain security compliance</li>
                    <li>Urgent requests (red) should be reviewed immediately</li>
                    <li>Verify business justifications align with organizational policies</li>
                    <li>Consider the security implications before approving changes</li>
                    <li>Document any concerns or questions in the approver notes</li>
                    <li>Requests expire after 30 days and will need to be resubmitted</li>
                </ul>
            </div>
            
            <div class="timestamp">
                Report generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
            </div>
        </div>
        
        <div class="footer">
            This is an automated notification from your Intune MAA monitoring system.<br>
            For questions about specific requests, contact the requester directly.<br>
            <a href="$MAARequestsUrl" style="color: #667eea;">Access MAA Portal</a>
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
            subject      = $Subject
            body         = @{
                contentType = "HTML"
                content     = $Body
            }
            toRecipients = $ToRecipients
            importance   = $EmailConfig.Priority.ToLower()
        }
        
        # Send email using Microsoft Graph
        $RequestBody = @{
            message         = $Message
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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting MAA Pending Requests Monitor..." -InformationAction Continue
    Write-Information "Urgent Threshold: $UrgentThresholdHours hours" -InformationAction Continue
    Write-Information "Escalation Threshold: $EscalationThresholdHours hours" -InformationAction Continue
    Write-Information "Email Recipients: $EmailRecipients" -InformationAction Continue
    
    # Get notification state
    $NotificationState = Get-NotificationState
    
    # Step 1: Get pending MAA requests
    $PendingRequests = Get-MAAPendingRequest
    
    # Step 2: Get recently processed requests if requested
    $ProcessedRequests = @()
    if ($IncludeProcessedRequests) {
        $ProcessedRequests = Get-ProcessedRequest -HoursBack 24
    }
    
    # Step 3: Analyze requests
    $Summary = @{
        TotalPending   = $PendingRequests.Count
        UrgentCount    = ($PendingRequests | Where-Object { $_.AgeInHours -gt $UrgentThresholdHours -and $_.AgeInHours -le $EscalationThresholdHours }).Count
        EscalatedCount = ($PendingRequests | Where-Object { $_.AgeInHours -gt $EscalationThresholdHours }).Count
        ExpiringSoon   = ($PendingRequests | Where-Object { $_.DaysUntilExpiry -lt 7 }).Count
        ProcessedCount = $ProcessedRequests.Count
    }
    
    Write-Information "Analysis complete: $($Summary.TotalPending) pending, $($Summary.UrgentCount) urgent, $($Summary.EscalatedCount) escalated" -InformationAction Continue
    
    # Step 4: Determine if notification should be sent
    $NewRequests = @()
    $NotifiedIds = $NotificationState.NotifiedRequests
    
    foreach ($Request in $PendingRequests) {
        if ($Request.Id -notin $NotifiedIds) {
            $NewRequests += $Request
        }
    }
    
    $ShouldSendNotification = $false
    $NotificationReason = ""
    
    if ($NewRequests.Count -gt 0) {
        $ShouldSendNotification = $true
        $NotificationReason = "New requests detected"
    }
    elseif ($Summary.EscalatedCount -gt 0) {
        $ShouldSendNotification = $true
        $NotificationReason = "Escalated requests require attention"
    }
    elseif ($Summary.ExpiringSoon -gt 0) {
        $ShouldSendNotification = $true
        $NotificationReason = "Requests expiring soon"
    }
    elseif ($ForceNotification) {
        $ShouldSendNotification = $true
        $NotificationReason = "Forced notification"
    }
    
    if (-not $ShouldSendNotification) {
        Write-Information "✓ No notification needed. No new or urgent requests." -InformationAction Continue
        exit 0
    }
    
    # Step 5: Create and send email notification
    Write-Information "Sending notification: $NotificationReason" -InformationAction Continue
    
    # Prepare email subject
    $AlertLevel = if ($Summary.EscalatedCount -gt 0) { "ESCALATED" }
    elseif ($Summary.UrgentCount -gt 0) { "URGENT" }
    else { "ACTION REQUIRED" }
    
    $Subject = "[$AlertLevel] MAA - $($Summary.TotalPending) Pending Approval Requests"
    
    if ($Summary.EscalatedCount -gt 0) {
        $Subject += " - $($Summary.EscalatedCount) ESCALATED"
    }
    
    # Generate email body
    $EmailBody = New-EmailBody -PendingRequests $PendingRequests -ProcessedRequests $ProcessedRequests -Summary $Summary
    
    # Parse email recipients
    $Recipients = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() }
    
    # Send email notification
    $EmailSent = Send-EmailNotification -Body $EmailBody -Recipients $Recipients -Subject $Subject
    
    if ($EmailSent) {
        Write-Information "✓ Notification sent successfully" -InformationAction Continue
        
        # Update notification state
        $NotificationState.NotifiedRequests = $PendingRequests.Id
        $NotificationState.LastRun = (Get-Date).ToString()
        $NotificationState.LastNotification = (Get-Date).ToString()
        Set-NotificationState -State $NotificationState
    }
    else {
        Write-Error "Failed to send email notification"
        exit 1
    }
    
    Write-Information "✓ MAA Pending Requests Monitor completed successfully" -InformationAction Continue
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
MAA Monitoring Summary
========================================
Total Pending Requests: $($Summary.TotalPending)
Urgent Requests: $($Summary.UrgentCount)
Escalated Requests: $($Summary.EscalatedCount)
Expiring Soon: $($Summary.ExpiringSoon)
Processed (24h): $($Summary.ProcessedCount)
Notification Sent: $(if ($ShouldSendNotification) { 'Yes' } else { 'No' })
Recipients: $EmailRecipients
========================================
" -InformationAction Continue