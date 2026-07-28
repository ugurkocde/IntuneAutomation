<#
.TITLE
    Apple Token Validity Checker

.SYNOPSIS
    Monitor and report on the validity and expiration status of Apple DEP tokens and Push Notification Certificates in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all Apple Device Enrollment Program (DEP) tokens 
    and Apple Push Notification Certificates configured in Intune. It checks their validity status, 
    expiration dates, and sync status to help administrators proactively manage Apple Business Manager 
    integrations. The script generates detailed reports in CSV format, highlighting tokens and certificates 
    that are expired, expiring soon, or have sync issues.

.TAGS
    Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementServiceConfig.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.3

.CHANGELOG
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Output directory is now created automatically before the CSV export; pagination helper keeps single-item results as arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-28

.EXAMPLE
    .\check-apple-token-validity.ps1
    Generates Apple token validity reports for all DEP tokens and Push Notification Certificates

.EXAMPLE
    .\check-apple-token-validity.ps1 -OutputPath "C:\Reports" -ExpirationWarningDays 60
    Generates reports with 60-day expiration warning and saves to specified directory

.EXAMPLE
    .\check-apple-token-validity.ps1 -OnlyShowProblems -SendEmailAlert
    Shows only problematic tokens and certificates and sends email alerts for critical issues

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - DEP tokens are valid for one year from creation
    - Apple Push Notification Certificates are valid for one year from creation
    - Automatic sync occurs daily, manual sync can be triggered
    - Critical for maintaining iOS/macOS device and app management
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false, HelpMessage = "Number of days before expiration to show warnings")]
    [ValidateRange(1, 365)]
    [int]$ExpirationWarningDays = 30,
    
    [Parameter(Mandatory = $false, HelpMessage = "Only show tokens with problems")]
    [switch]$OnlyShowProblems,
    
    [Parameter(Mandatory = $false, HelpMessage = "Send email alert for critical issues")]
    [switch]$SendEmailAlert,
    
    [Parameter(Mandatory = $false, HelpMessage = "Email address to send alerts to")]
    [string]$AlertEmailAddress = "",
    
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
        # Azure Automation - Use Managed Identity
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        # Local execution - WAM-free interactive sign-in via MgGraphCommunity
        Write-Output "Connecting to Microsoft Graph with interactive authentication..."
        $Scopes = @(
            "DeviceManagementServiceConfig.Read.All",
            "DeviceManagementConfiguration.Read.All"
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

# Function to get all pages of results from Graph API
function Get-MgGraphPaginatedData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [int]$DelayMs = 100
    )
    
    $AllResult = @()
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
                $AllResult += $Response.value
            }
            else {
                $AllResult += $Response
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

    # Comma prevents unrolling so single-element results stay arrays
    return , $AllResult
}

# Function to determine token health status
function Get-TokenHealthStatus {
    param(
        [string]$State,
        [datetime]$ExpirationDate,
        [string]$LastSyncStatus,
        [int]$WarningDays
    )
    
    $DaysUntilExpiration = ($ExpirationDate - (Get-Date)).Days
    
    # Determine overall health
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

# Function to format time span
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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Starting Apple token validity check..."
    
    # Initialize results arrays
    $AllTokens = @()
    $CriticalIssues = @()
    
    # ========================================================================
    # GET DEP TOKENS (ENROLLMENT PROGRAM TOKENS)
    # ========================================================================
    
    Write-Output "Retrieving Apple DEP tokens..."
    
    try {
        $DepTokensUri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings"
        $DepTokens = Get-MgGraphPaginatedData -Uri $DepTokensUri
        Write-Output "Retrieving $($DepTokens.Count) DEP token entries..."
        
        $ValidDepTokenCount = 0
        foreach ($Token in $DepTokens) {
            try {
                # Skip if essential fields are missing
                if (-not $Token.tokenExpirationDateTime -or -not $Token.id) {
                    Write-Verbose "Skipping DEP token entry with missing essential fields (ID: $($Token.id))"
                    continue
                }
                
                $ExpirationDate = [datetime]$Token.tokenExpirationDateTime
                $LastSyncDate = if ($Token.lastSuccessfulSyncDateTime) { [datetime]$Token.lastSuccessfulSyncDateTime } else { $null }
                
                # DEP tokens don't have the same state enum as VPP, so we determine state based on expiration
                $State = if ($ExpirationDate -lt (Get-Date)) { "expired" } else { "valid" }
                $LastSyncStatus = if ($Token.lastSyncErrorCode -eq 0 -or $null -eq $Token.lastSyncErrorCode) { "completed" } else { "failed" }
                
                $HealthStatus = Get-TokenHealthStatus -State $State -ExpirationDate $ExpirationDate -LastSyncStatus $LastSyncStatus -WarningDays $ExpirationWarningDays
                
                $TokenInfo = [PSCustomObject]@{
                    TokenType            = "DEP"
                    TokenName            = if ($Token.tokenName) { $Token.tokenName } else { "Unknown DEP Token" }
                    AppleId              = if ($Token.appleIdentifier) { $Token.appleIdentifier } else { "Unknown" }
                    State                = $State
                    AccountType          = if ($Token.tokenType) { $Token.tokenType } else { "Unknown" }
                    CountryRegion        = "N/A"
                    ExpirationDateTime   = $ExpirationDate
                    DaysUntilExpiration  = ($ExpirationDate - (Get-Date)).Days
                    ExpirationStatus     = Format-TimeSpan -Date $ExpirationDate
                    LastSyncDateTime     = $LastSyncDate
                    LastSyncStatus       = $LastSyncStatus
                    AutoUpdateApps       = "N/A"
                    HealthStatus         = $HealthStatus
                    TokenId              = $Token.id
                    LastModifiedDateTime = if ($Token.lastModifiedDateTime) { [datetime]$Token.lastModifiedDateTime } else { $null }
                }
                
                $AllTokens += $TokenInfo
                $ValidDepTokenCount++
                
                # Track critical issues
                if ($HealthStatus -eq "Critical") {
                    $CriticalIssues += $TokenInfo
                }
            }
            catch {
                Write-Verbose "Error processing DEP token (ID: $($Token.id)): $($_.Exception.Message)"
                continue
            }
        }
        
        Write-Output "✓ Found $ValidDepTokenCount valid DEP tokens"
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
            Write-Output "✓ Found Apple Push Notification Certificate"
            
            $ExpirationDate = [datetime]$ApnsCert.expirationDateTime
            $LastModifiedDate = if ($ApnsCert.lastModifiedDateTime) { [datetime]$ApnsCert.lastModifiedDateTime } else { $null }
            
            # Determine certificate state based on expiration and upload status
            $State = if ($ExpirationDate -lt (Get-Date)) { 
                "expired" 
            }
            elseif ([string]::IsNullOrEmpty($ApnsCert.certificateUploadFailureReason)) { 
                "valid" 
            }
            else { 
                "invalid" 
            }
            
            # Determine sync status based on certificate upload status and failure reason
            $LastSyncStatus = if ([string]::IsNullOrEmpty($ApnsCert.certificateUploadFailureReason)) { "completed" } else { "failed" }
            
            # Debug output to help understand the actual certificate status
            Write-Verbose "APNS Certificate Debug Info:"
            Write-Verbose "  Upload Status: '$($ApnsCert.certificateUploadStatus)'"
            Write-Verbose "  Failure Reason: '$($ApnsCert.certificateUploadFailureReason)'"
            Write-Verbose "  Has Certificate: $([bool]$ApnsCert.certificate)"
            Write-Verbose "  Determined State: '$State'"
            
            $HealthStatus = Get-TokenHealthStatus -State $State -ExpirationDate $ExpirationDate -LastSyncStatus $LastSyncStatus -WarningDays $ExpirationWarningDays
            
            $TokenInfo = [PSCustomObject]@{
                TokenType                      = "APNS"
                TokenName                      = "Apple Push Notification Certificate"
                AppleId                        = $ApnsCert.appleIdentifier
                State                          = $State
                AccountType                    = "Push Certificate"
                CountryRegion                  = "N/A"
                ExpirationDateTime             = $ExpirationDate
                DaysUntilExpiration            = ($ExpirationDate - (Get-Date)).Days
                ExpirationStatus               = Format-TimeSpan -Date $ExpirationDate
                LastSyncDateTime               = $LastModifiedDate
                LastSyncStatus                 = $LastSyncStatus
                AutoUpdateApps                 = "N/A"
                HealthStatus                   = $HealthStatus
                TokenId                        = $ApnsCert.id
                LastModifiedDateTime           = $LastModifiedDate
                TopicIdentifier                = $ApnsCert.topicIdentifier
                CertificateUploadStatus        = $ApnsCert.certificateUploadStatus
                CertificateUploadFailureReason = $ApnsCert.certificateUploadFailureReason
                CertificateSerialNumber        = $ApnsCert.certificateSerialNumber
            }
            
            $AllTokens += $TokenInfo
            
            # Track critical issues
            if ($HealthStatus -eq "Critical") {
                $CriticalIssues += $TokenInfo
            }
        }
        else {
            Write-Output "ℹ️ No Apple Push Notification Certificate found"
        }
    }
    catch {
        Write-Warning "Failed to retrieve Apple Push Notification Certificate: $($_.Exception.Message)"
    }
    
    # ========================================================================
    # FILTER RESULTS IF REQUESTED
    # ========================================================================
    
    $ReportTokens = if ($OnlyShowProblems) {
        $AllTokens | Where-Object { $_.HealthStatus -in @("Critical", "Warning") }
    }
    else {
        $AllTokens
    }
    
    # ========================================================================
    # GENERATE CSV REPORT
    # ========================================================================
    
    # Create output directory if it does not exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Output "Created output directory: $OutputPath"
    }

    # Generate timestamp for file names
    $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $CsvPath = Join-Path $OutputPath "Apple_Token_Validity_Report_$Timestamp.csv"
    
    # Export to CSV
    try {
        $ReportTokens | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Output "✓ CSV report saved: $CsvPath"
    }
    catch {
        Write-Error "Failed to generate CSV report: $($_.Exception.Message)"
    }
    
    # ========================================================================
    # SEND EMAIL ALERTS IF REQUESTED
    # ========================================================================
    
    if ($SendEmailAlert -and $CriticalIssues.Count -gt 0 -and $AlertEmailAddress) {
        Write-Output "Sending email alert for critical issues..."
        # Note: Email functionality would require additional modules and configuration
        # This is a placeholder for future implementation
        Write-Warning "Email alert functionality requires additional configuration (SMTP settings, etc.)"
    }
    
    # ========================================================================
    # DISPLAY DETAILED CONSOLE OUTPUT
    # ========================================================================
    
    Write-Output "`n🍎 APPLE TOKEN & CERTIFICATE VALIDITY SUMMARY"
    Write-Output "=============================================="
    Write-Output "Total Items: $($AllTokens.Count)"
    Write-Output "  • DEP Tokens: $(($AllTokens | Where-Object { $_.TokenType -eq 'DEP' }).Count)"
    Write-Output "  • APNS Certificates: $(($AllTokens | Where-Object { $_.TokenType -eq 'APNS' }).Count)"
    Write-Output ""
    
    # Health Status Summary
    $HealthyCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
    $WarningCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Warning" }).Count
    $CriticalCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Critical" }).Count
    $UnknownCount = ($AllTokens | Where-Object { $_.HealthStatus -eq "Unknown" }).Count
    
    Write-Output "Health Status:"
    Write-Output "  • Healthy: $HealthyCount"
    Write-Output "  • Warning: $WarningCount"
    Write-Output "  • Critical: $CriticalCount"
    Write-Output "  • Unknown: $UnknownCount"
    
    # Display detailed token information
    if ($ReportTokens.Count -gt 0) {
        Write-Output "`n📋 TOKEN DETAILS:"
        Write-Output "================="
        
        foreach ($Token in ($ReportTokens | Sort-Object HealthStatus, DaysUntilExpiration)) {
            $StatusIcon = switch ($Token.HealthStatus) {
                "Healthy" { "✅" }
                "Warning" { "⚠️" }
                "Critical" { "❌" }
                default { "❓" }
            }
            
            $ItemType = if ($Token.TokenType -eq "APNS") { "Certificate" } else { "Token" }
            Write-Output "`n$StatusIcon $($Token.TokenType) $ItemType : $($Token.TokenName)"
            Write-Output "   Apple ID: $($Token.AppleId)"
            Write-Output "   Status: $($Token.State)"
            Write-Output "   Health: $($Token.HealthStatus)"
            Write-Output "   Expires: $($Token.ExpirationDateTime.ToString('yyyy-MM-dd')) ($($Token.ExpirationStatus))"
            Write-Output "   Last Modified: $(if ($Token.LastSyncDateTime) { $Token.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm') } else { 'Never' })"
            Write-Output "   Status: $($Token.LastSyncStatus)"
            
            if ($Token.TokenType -eq "APNS") {
                Write-Output "   Topic Identifier: $($Token.TopicIdentifier)"
                Write-Output "   Upload Status: $($Token.CertificateUploadStatus)"
                Write-Output "   Serial Number: $($Token.CertificateSerialNumber)"
                if ($Token.CertificateUploadFailureReason) {
                    Write-Output "   Upload Failure Reason: $($Token.CertificateUploadFailureReason)"
                }
            }
        }
    }
    
    # Critical Issues Alert
    if ($CriticalIssues.Count -gt 0) {
        Write-Output "`n⚠️  CRITICAL ISSUES DETECTED:"
        Write-Output "============================="
        foreach ($Issue in $CriticalIssues) {
            Write-Output "❌ $($Issue.TokenName) ($($Issue.TokenType))"
            Write-Output "   Issue: $($Issue.State)"
            Write-Output "   Expires: $($Issue.ExpirationStatus)"
            Write-Output "   Action Required: $(if ($Issue.State -eq 'expired') { 'Replace token immediately' } elseif ($Issue.State -eq 'invalid') { 'Check Apple Business Manager configuration' } else { 'Investigate sync issues' })"
            Write-Output ""
        }
    }
    
    # Recommendations
    Write-Output "`n📋 RECOMMENDATIONS:"
    Write-Output "==================="
    
    $ExpiringTokens = $AllTokens | Where-Object { $_.DaysUntilExpiration -le $ExpirationWarningDays -and $_.DaysUntilExpiration -gt 0 }
    if ($ExpiringTokens.Count -gt 0) {
        Write-Output "🔄 Renew $($ExpiringTokens.Count) token(s) expiring within $ExpirationWarningDays days:"
        foreach ($Token in $ExpiringTokens) {
            Write-Output "   • $($Token.TokenName) ($($Token.TokenType)) - expires in $($Token.DaysUntilExpiration) days"
        }
        Write-Output ""
    }
    
    $FailedSyncTokens = $AllTokens | Where-Object { $_.LastSyncStatus -eq "failed" }
    if ($FailedSyncTokens.Count -gt 0) {
        Write-Output "🔍 Investigate $($FailedSyncTokens.Count) token(s) with failed sync status:"
        foreach ($Token in $FailedSyncTokens) {
            Write-Output "   • $($Token.TokenName) ($($Token.TokenType))"
        }
        Write-Output ""
    }
    
    $ExpiredTokens = $AllTokens | Where-Object { $_.DaysUntilExpiration -le 0 }
    if ($ExpiredTokens.Count -gt 0) {
        Write-Output "🚨 Replace $($ExpiredTokens.Count) expired token(s) immediately:"
        foreach ($Token in $ExpiredTokens) {
            Write-Output "   • $($Token.TokenName) ($($Token.TokenType)) - expired $([math]::Abs($Token.DaysUntilExpiration)) days ago"
        }
        Write-Output ""
    }
    
    if ($HealthyCount -eq $AllTokens.Count) {
        Write-Output "✅ All tokens are healthy! No action required."
    }
    
    Write-Output "`nReport saved to:"
    Write-Output "📄 CSV: $CsvPath"
    
    Write-Output "`n✓ Apple token validity check completed successfully"
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Output "Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Disconnect operation completed with warnings (this is expected behavior)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Output "
========================================
Script Execution Summary
========================================
Script: Apple Token & Certificate Validity Checker
Total Items Checked: $($AllTokens.Count)
  • DEP Tokens: $(($AllTokens | Where-Object { $_.TokenType -eq 'DEP' }).Count)
  • APNS Certificates: $(($AllTokens | Where-Object { $_.TokenType -eq 'APNS' }).Count)
Critical Issues: $($CriticalIssues.Count)
Status: Completed
========================================
"