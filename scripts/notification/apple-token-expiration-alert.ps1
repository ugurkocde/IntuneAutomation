<#
.TITLE
    Apple Token Expiration Alert Notification

.SYNOPSIS
    Automated runbook to monitor Apple DEP tokens and VPP tokens expiration and send email alerts.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors the expiration 
    status of Apple Device Enrollment Program (DEP) tokens and Apple Push Notification Service (APNS) 
    certificates in Microsoft Intune. When tokens or certificates are approaching expiration or have 
    expired, the script sends email notifications to specified recipients using Microsoft Graph Mail API.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementServiceConfig.Read.All,DeviceManagementConfiguration.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.3

.CHANGELOG
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Mail now sends from a mandatory SenderUPN mailbox via /users/{upn}/sendMail (app-only managed identity cannot use /me); send failures now fail the run; APNS certificates without an expiration date are recorded as Unknown expiry instead of failing; pagination helper preserves single-item arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-28

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Daily

.CATEGORY
    Notification

.EXAMPLE
    .\apple-token-expiration-alert.ps1 -NotificationDays 30 -EmailRecipients "admin@company.com" -SenderUPN "intune-alerts@company.com"
    Checks for tokens expiring within 30 days and sends alerts to admin@company.com

.EXAMPLE
    .\apple-token-expiration-alert.ps1 -NotificationDays 7 -EmailRecipients "admin@company.com,security@company.com" -SenderUPN "intune-alerts@company.com"
    Checks for tokens expiring within 7 days and sends alerts to multiple recipients

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - For Azure Automation, configure Managed Identity with required permissions
    - Uses Microsoft Graph Mail API for email notifications only, sent from the SenderUPN mailbox
    - The Automation account's managed identity requires Mail.Send permission for the SenderUPN mailbox
    - Recommended to run as scheduled runbook (daily or weekly)
    - DEP tokens are valid for one year from creation
    - APNS certificates are valid for one year from creation
    - Critical for maintaining iOS/macOS device and app management continuity
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Number of days before expiration to trigger notifications")]
    [ValidateRange(1, 365)]
    [int]$NotificationDays,
    
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to send notifications")]
    [ValidateNotNullOrEmpty()]
    [string]$EmailRecipients,

    [Parameter(Mandatory = $true, HelpMessage = "Mailbox UPN used as the notification sender (managed identity needs Mail.Send permission for it)")]
    [ValidateNotNullOrEmpty()]
    [string]$SenderUPN,

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
    Write-Output "Running locally in IDE or terminal"
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModuleList = @(
    "Microsoft.Graph.Authentication"
)

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModuleList += "MgGraphCommunity"
}

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
        Write-Output "Connecting to Microsoft Graph with interactive authentication..."
        $Scopes = @(
            "DeviceManagementServiceConfig.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "Mail.Send"
        )
        
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph"
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

    # Comma keeps PowerShell from unrolling a single-item array on return
    return , $AllResults
}

function Get-TokenHealthStatus {
    param(
        [string]$State,
        [datetime]$ExpirationDate,
        [string]$LastSyncStatus,
        [int]$WarningDays
    )
    
    $DaysUntilExpiration = ($ExpirationDate - (Get-Date)).Days
    
    if ($State -eq "expired" -or $DaysUntilExpiration -le 0) {
        return "Critical"
    }
    elseif ($State -eq "invalid" -or $LastSyncStatus -eq "failed") {
        return "Critical"
    }
    elseif ($DaysUntilExpiration -le $WarningDays) {
        return "Warning"
    }
    elseif ($State -eq "valid" -and $LastSyncStatus -eq "completed") {
        return "Healthy"
    }
    else {
        return "Unknown"
    }
}

function Format-TimeSpan {
    param([datetime]$Date)
    
    $TimeSpan = $Date - (Get-Date)
    
    if ($TimeSpan.TotalDays -gt 0) {
        return "$([math]::Round($TimeSpan.TotalDays)) days"
    }
    elseif ($TimeSpan.TotalDays -gt -1) {
        return "Today"
    }
    else {
        return "$([math]::Abs([math]::Round($TimeSpan.TotalDays))) days ago"
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
                $Uri = "https://graph.microsoft.com/v1.0/users/$SenderUPN/sendMail"
                Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $RequestBody -ContentType "application/json" | Out-Null
                Write-Information "✓ Email sent to $Recipient via Microsoft Graph" -InformationAction Continue
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to send email notification: $($_.Exception.Message)"
        return $false
    }
}

# Function creates email content, does not change system state
function New-EmailBody {
    param(
        [array]$Tokens,
        [int]$NotificationDays
    )
    
    $CriticalTokens = $Tokens | Where-Object { $_.HealthStatus -eq "Critical" }
    $WarningTokens = $Tokens | Where-Object { $_.HealthStatus -eq "Warning" }
    $HealthyTokens = $Tokens | Where-Object { $_.HealthStatus -eq "Healthy" }
    
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
        .token-item { margin: 5px 0; padding: 8px; background-color: white; border-radius: 3px; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
        h2 { color: #333; }
        h3 { color: #555; margin-top: 20px; }
        .status-icon { font-size: 16px; margin-right: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🍎 Apple Token Expiration Alert</h1>
        <p>Notification threshold: $NotificationDays days</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Tokens/Certificates:</strong> $($Tokens.Count)</p>
        <p><strong>Critical Issues:</strong> $($CriticalTokens.Count) (Expired or Invalid)</p>
        <p><strong>Warning:</strong> $($WarningTokens.Count) (Expiring within $NotificationDays days)</p>
        <p><strong>Healthy:</strong> $($HealthyTokens.Count)</p>
    </div>
"@

    if ($CriticalTokens.Count -gt 0) {
        $Body += @"
    <div class="critical">
        <h3><span class="status-icon">❌</span>Critical Issues - Immediate Action Required</h3>
"@
        foreach ($Token in $CriticalTokens) {
            $Body += @"
        <div class="token-item">
            <strong>$($Token.TokenName)</strong> ($($Token.TokenType))<br>
            <strong>Apple ID:</strong> $($Token.AppleId)<br>
            <strong>Status:</strong> $($Token.State)<br>
            <strong>Expiration:</strong> $($Token.ExpirationDateTime.ToString('yyyy-MM-dd')) ($($Token.ExpirationStatus))<br>
            <strong>Action:</strong> $(if ($Token.State -eq 'expired') { 'Replace token immediately' } else { 'Check configuration and renew' })
        </div>
"@
        }
        $Body += "</div>"
    }

    if ($WarningTokens.Count -gt 0) {
        $Body += @"
    <div class="warning">
        <h3><span class="status-icon">⚠️</span>Expiring Soon - Plan Renewal</h3>
"@
        foreach ($Token in $WarningTokens) {
            $Body += @"
        <div class="token-item">
            <strong>$($Token.TokenName)</strong> ($($Token.TokenType))<br>
            <strong>Apple ID:</strong> $($Token.AppleId)<br>
            <strong>Expires:</strong> $($Token.ExpirationDateTime.ToString('yyyy-MM-dd')) ($($Token.ExpirationStatus))<br>
            <strong>Days Remaining:</strong> $($Token.DaysUntilExpiration)
        </div>
"@
        }
        $Body += "</div>"
    }

    $Body += @"
    <div class="footer">
        <p><strong>Next Steps:</strong></p>
        <ul>
            <li>For DEP tokens: Renew through Apple Business Manager</li>
            <li>For APNS certificates: Download new certificate from Apple Developer Portal</li>
            <li>Update tokens in Microsoft Intune portal</li>
        </ul>
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
    Write-Output "Starting Apple token expiration monitoring..."
    
    # Parse email recipients
    $EmailRecipientList = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    
    if ($EmailRecipientList.Count -eq 0) {
        throw "No valid email recipients provided"
    }
    
    Write-Output "Email recipients: $($EmailRecipientList -join ', ')"
    Write-Output "Notification threshold: $NotificationDays days"
    
    # Initialize results arrays
    $AllTokens = @()
    $TokensRequiringAttention = @()
    $NotificationFailed = $false
    
    # ========================================================================
    # GET DEP TOKENS
    # ========================================================================
    
    Write-Output "Retrieving Apple DEP tokens..."
    
    try {
        $DepTokensUri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings"
        $DepTokens = Get-MgGraphAllPage -Uri $DepTokensUri
        Write-Output "Found $($DepTokens.Count) DEP token entries"
        
        foreach ($Token in $DepTokens) {
            try {
                if (-not $Token.tokenExpirationDateTime -or -not $Token.id) {
                    continue
                }
                
                $ExpirationDate = [datetime]$Token.tokenExpirationDateTime
                $LastSyncDate = if ($Token.lastSuccessfulSyncDateTime) { [datetime]$Token.lastSuccessfulSyncDateTime } else { $null }
                
                $State = if ($ExpirationDate -lt (Get-Date)) { "expired" } else { "valid" }
                $LastSyncStatus = if ($Token.lastSyncErrorCode -eq 0 -or $null -eq $Token.lastSyncErrorCode) { "completed" } else { "failed" }
                
                $HealthStatus = Get-TokenHealthStatus -State $State -ExpirationDate $ExpirationDate -LastSyncStatus $LastSyncStatus -WarningDays $NotificationDays
                
                $TokenInfo = [PSCustomObject]@{
                    TokenType           = "DEP"
                    TokenName           = if ($Token.tokenName) { $Token.tokenName } else { "DEP Token" }
                    AppleId             = if ($Token.appleIdentifier) { $Token.appleIdentifier } else { "Unknown" }
                    State               = $State
                    ExpirationDateTime  = $ExpirationDate
                    DaysUntilExpiration = ($ExpirationDate - (Get-Date)).Days
                    ExpirationStatus    = Format-TimeSpan -Date $ExpirationDate
                    LastSyncDateTime    = $LastSyncDate
                    LastSyncStatus      = $LastSyncStatus
                    HealthStatus        = $HealthStatus
                    TokenId             = $Token.id
                }
                
                $AllTokens += $TokenInfo
                
                if ($HealthStatus -in @("Critical", "Warning")) {
                    $TokensRequiringAttention += $TokenInfo
                }
            }
            catch {
                Write-Verbose "Error processing DEP token (ID: $($Token.id)): $($_.Exception.Message)"
                continue
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve DEP tokens: $($_.Exception.Message)"
    }
    
    # ========================================================================
    # GET APPLE PUSH NOTIFICATION CERTIFICATE
    # ========================================================================
    
    Write-Output "Retrieving Apple Push Notification Certificate..."
    
    try {
        $ApnsCertUri = "https://graph.microsoft.com/v1.0/deviceManagement/applePushNotificationCertificate"
        $ApnsCert = Invoke-MgGraphRequest -Uri $ApnsCertUri -Method GET
        
        if ($ApnsCert) {
            $LastModifiedDate = if ($ApnsCert.lastModifiedDateTime) { [datetime]$ApnsCert.lastModifiedDateTime } else { $null }
            $LastSyncStatus = if ([string]::IsNullOrEmpty($ApnsCert.certificateUploadFailureReason)) { "completed" } else { "failed" }

            if ($ApnsCert.expirationDateTime) {
                $ExpirationDate = [datetime]$ApnsCert.expirationDateTime

                $State = if ($ExpirationDate -lt (Get-Date)) {
                    "expired"
                }
                elseif ([string]::IsNullOrEmpty($ApnsCert.certificateUploadFailureReason)) {
                    "valid"
                }
                else {
                    "invalid"
                }

                $HealthStatus = Get-TokenHealthStatus -State $State -ExpirationDate $ExpirationDate -LastSyncStatus $LastSyncStatus -WarningDays $NotificationDays

                $TokenInfo = [PSCustomObject]@{
                    TokenType           = "APNS"
                    TokenName           = "Apple Push Notification Certificate"
                    AppleId             = $ApnsCert.appleIdentifier
                    State               = $State
                    ExpirationDateTime  = $ExpirationDate
                    DaysUntilExpiration = ($ExpirationDate - (Get-Date)).Days
                    ExpirationStatus    = Format-TimeSpan -Date $ExpirationDate
                    LastSyncDateTime    = $LastModifiedDate
                    LastSyncStatus      = $LastSyncStatus
                    HealthStatus        = $HealthStatus
                    TokenId             = $ApnsCert.id
                }
            }
            else {
                # No expiration date reported - record the certificate instead of letting the cast throw
                $TokenInfo = [PSCustomObject]@{
                    TokenType           = "APNS"
                    TokenName           = "Apple Push Notification Certificate"
                    AppleId             = $ApnsCert.appleIdentifier
                    State               = "Unknown expiry"
                    ExpirationDateTime  = $null
                    DaysUntilExpiration = $null
                    ExpirationStatus    = "Unknown expiry"
                    LastSyncDateTime    = $LastModifiedDate
                    LastSyncStatus      = $LastSyncStatus
                    HealthStatus        = "Unknown"
                    TokenId             = $ApnsCert.id
                }
            }

            $AllTokens += $TokenInfo

            if ($TokenInfo.HealthStatus -in @("Critical", "Warning")) {
                $TokensRequiringAttention += $TokenInfo
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve Apple Push Notification Certificate: $($_.Exception.Message)"
    }
    
    # ========================================================================
    # SEND NOTIFICATIONS IF REQUIRED
    # ========================================================================
    
    if ($TokensRequiringAttention.Count -gt 0) {
        Write-Output "Preparing email notification..."
        
        $CriticalCount = ($TokensRequiringAttention | Where-Object { $_.HealthStatus -eq "Critical" }).Count
        $WarningCount = ($TokensRequiringAttention | Where-Object { $_.HealthStatus -eq "Warning" }).Count
        
        $Subject = if ($CriticalCount -gt 0) {
            "[Intune Alert] CRITICAL: $CriticalCount Apple Token(s) Expired/Invalid"
        }
        elseif ($WarningCount -gt 0) {
            "[Intune Alert] WARNING: $WarningCount Apple Token(s) Expiring Soon"
        }
        else {
            "[Intune Alert] Apple Token Status Report"
        }
        
        $EmailBody = New-EmailBody -Tokens $AllTokens -NotificationDays $NotificationDays
        
        $EmailSent = Send-EmailNotification -Recipients $EmailRecipientList -Subject $Subject -Body $EmailBody

        if ($EmailSent) {
            Write-Output "✓ Email notification sent to $($EmailRecipientList.Count) recipients"
        }
        else {
            Write-Warning "Email notification could not be delivered to all recipients"
            $NotificationFailed = $true
        }
    }
    else {
        Write-Output "✓ All tokens are healthy. No notification required."
    }
    
    # ========================================================================
    # DISPLAY SUMMARY
    # ========================================================================
    
    Write-Output "`n🍎 APPLE TOKEN EXPIRATION MONITORING SUMMARY"
    Write-Output "============================================="
    Write-Output "Total Tokens/Certificates: $($AllTokens.Count)"
    Write-Output "  • DEP Tokens: $(($AllTokens | Where-Object { $_.TokenType -eq 'DEP' }).Count)"
    Write-Output "  • APNS Certificates: $(($AllTokens | Where-Object { $_.TokenType -eq 'APNS' }).Count)"
    Write-Output ""
    
    $CriticalCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Critical" }).Count
    $WarningCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Warning" }).Count
    $HealthyCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
    
    Write-Output "Health Status:"
    Write-Output "  • Critical: $CriticalCount"
    Write-Output "  • Warning: $WarningCount"
    Write-Output "  • Healthy: $HealthyCount"
    Write-Output ""
    
    if ($TokensRequiringAttention.Count -gt 0) {
        Write-Output "Tokens Requiring Attention:"
        foreach ($Token in ($TokensRequiringAttention | Sort-Object HealthStatus, DaysUntilExpiration)) {
            $StatusIcon = if ($Token.HealthStatus -eq "Critical") { "❌" } else { "⚠️" }
            Write-Output "  $StatusIcon $($Token.TokenName) ($($Token.TokenType)) - $($Token.ExpirationStatus)"
        }
    }
    
    Write-Output "`n✓ Apple token expiration monitoring completed successfully"
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Output "Disconnected from Microsoft Graph"
    }
    catch {
        # Silently ignore disconnect errors as they're not critical
        Write-Verbose "Disconnect error (ignored): $($_.Exception.Message)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Output "
========================================
Script Execution Summary
========================================
Script: Apple Token Expiration Alert
Total Tokens Checked: $($AllTokens.Count)
Tokens Requiring Attention: $($TokensRequiringAttention.Count)
Email Recipients: $($EmailRecipientList.Count)
Notification Threshold: $NotificationDays days
Status: Completed
========================================
"

# Fail the run if notification delivery failed
if ($NotificationFailed) {
    exit 1
}