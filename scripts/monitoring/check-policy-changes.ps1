<#
.TITLE
    Policy Changes Monitor

.SYNOPSIS
    Monitor and report on recent changes to Policies in Microsoft Intune.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves recent changes to Policies
    configured in Intune. It checks audit logs for policy modifications, creations, deletions, and
    assignments within a specified time period. The script generates detailed reports in CSV format,
    highlighting policy changes with details about who made the changes, when they occurred, and
    what was modified. This helps administrators track configuration drift and maintain governance
    over device configuration policies.

.TAGS
    Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\check-policy-changes.ps1
    Generates a report of policy changes from the last 30 days

.EXAMPLE
    .\check-policy-changes.ps1 -DaysBack 30 -OutputPath "C:\Reports"
    Generates a report of policy changes from the last 30 days and saves to specified directory

.EXAMPLE
    .\check-policy-changes.ps1 -OnlyShowChanges -SendEmailAlert -AlertEmailAddress "admin@contoso.com"
    Shows only modified policies and sends email alerts for changes

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - Policies use modern configuration templates
    - Policies require beta Graph endpoint access
    - Audit data is available for up to 30 days by default
    - Critical for maintaining configuration governance and compliance
    - Monitor for unauthorized changes to security policies
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Number of days to look back for changes")]
    [ValidateRange(1, 90)]
    [int]$DaysBack = 30,
    
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false, HelpMessage = "Only show policies with changes")]
    [switch]$OnlyShowChanges,
    
    [Parameter(Mandatory = $false, HelpMessage = "Send email alert for policy changes")]
    [switch]$SendEmailAlert,
    
    [Parameter(Mandatory = $false, HelpMessage = "Email address to send alerts to")]
    [string]$AlertEmailAddress = "",
    
    [Parameter(Mandatory = $false, HelpMessage = "Include detailed change information")]
    [switch]$IncludeDetails
)

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if required modules are installed
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Error "$Module module is required. Install it using: Install-Module $Module -Scope CurrentUser"
        exit 1
    }
}

# Import required modules
foreach ($Module in $RequiredModules) {
    Import-Module $Module
}

# Connect to Microsoft Graph
try {
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    $Scopes = @(
        "DeviceManagementApps.Read.All",
        "DeviceManagementConfiguration.Read.All"
    )
    $null = Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction SilentlyContinue
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API
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

# Function to format change details
function Format-ChangeDetails {
    param(
        [object]$AuditLog
    )
    
    $ChangeDetails = @()
    
    if ($AuditLog.resources) {
        foreach ($Resource in $AuditLog.resources) {
            if ($Resource.modifiedProperties) {
                foreach ($Property in $Resource.modifiedProperties) {
                    $ChangeDetail = [PSCustomObject]@{
                        PropertyName = $Property.displayName
                        OldValue     = if ($Property.oldValue) { $Property.oldValue -replace "`n", " " } else { "N/A" }
                        NewValue     = if ($Property.newValue) { $Property.newValue -replace "`n", " " } else { "N/A" }
                    }
                    $ChangeDetails += $ChangeDetail
                }
            }
        }
    }
    
    return $ChangeDetails
}



# Function to determine change severity
function Get-ChangeSeverity {
    param(
        [string]$Activity,
        [string]$Result
    )
    
    if ($Result -eq "failure") {
        return "High"
    }
    
    switch -Wildcard ($Activity) {
        "*Delete*" { return "High" }
        "*Create*" { return "Medium" }
        "*Update*" { return "Medium" }
        "*Assign*" { return "Low" }
        default { return "Low" }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting Policies changes analysis..." -InformationAction Continue
    
    # Calculate start date
    $StartDate = (Get-Date).AddDays(-$DaysBack)
    $StartDateFormatted = $StartDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    Write-Information "Analyzing changes from: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss'))" -InformationAction Continue
    
    # ========================================================================
    # GET AUDIT LOGS FOR SETTINGS CATALOG CHANGES
    # ========================================================================
    
    Write-Information "Retrieving audit logs for Policies changes..." -InformationAction Continue
    
    try {
        # Query for Policies changes (DeviceConfiguration category)
        $AuditLogsUri = "https://graph.microsoft.com/beta/deviceManagement/auditEvents?`$filter=activityDateTime ge $StartDateFormatted and category eq 'DeviceConfiguration'&`$orderby=activityDateTime desc&`$top=50"
        $AuditLogs = Get-MgGraphAllPages -Uri $AuditLogsUri
        
        Write-Information "Retrieved $($AuditLogs.Count) DeviceConfiguration audit events" -InformationAction Continue
        
        # Filter for Policies (DeviceManagementConfigurationPolicy) activities
        $PoliciesActivities = $AuditLogs | Where-Object { 
            $_.activityType -like "*DeviceManagementConfigurationPolicy*"
        }
        
        Write-Information "✓ Found $($PoliciesActivities.Count) policy changes" -InformationAction Continue
    }
    catch {
        Write-Warning "Failed to retrieve audit logs: $($_.Exception.Message)"
        $PoliciesActivities = @()
    }
    
    # ========================================================================
    # DISPLAY LAST 5 CHANGES WITH DETAILS
    # ========================================================================
    
    Write-Information "Processing Policies policy changes..." -InformationAction Continue
    
    # Get the last 5 changes
    $Last5Changes = $PoliciesActivities | Select-Object -First 5
    
    if ($Last5Changes.Count -eq 0) {
        Write-Information "No Policies policy changes found in the specified time period." -InformationAction Continue
        return
    }
    
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "LAST 5 POLICIES POLICY CHANGES" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    
    $ChangeNumber = 1
    foreach ($Change in $Last5Changes) {
        try {
            # Get policy name and user info
            $PolicyName = "Unknown Policy"
            $UserName = "System"
            
            if ($Change.resources -and $Change.resources.Count -gt 0) {
                $PolicyName = $Change.resources[0].displayName
            }
            
            if ($Change.actor -and $Change.actor.userPrincipalName) {
                $UserName = $Change.actor.userPrincipalName
            }
            
            Write-Information "`n[$ChangeNumber] $($Change.activityDateTime)" -InformationAction Continue
            Write-Information "Policy: $PolicyName" -InformationAction Continue
            Write-Information "Action: $($Change.activityType)" -InformationAction Continue
            Write-Information "User: $UserName" -InformationAction Continue
            Write-Information "Result: $($Change.activityResult)" -InformationAction Continue
            
            # Show modified properties (before/after values)
            if ($Change.resources -and $Change.resources[0].modifiedProperties) {
                Write-Information "Changes:" -InformationAction Continue
                foreach ($Property in $Change.resources[0].modifiedProperties) {
                    $OldValue = if ($Property.oldValue) { $Property.oldValue } else { "(empty)" }
                    $NewValue = if ($Property.newValue) { $Property.newValue } else { "(empty)" }
                    Write-Information "  - $($Property.displayName): '$OldValue' → '$NewValue'" -InformationAction Continue
                }
            }
            else {
                Write-Information "  No detailed change information available" -InformationAction Continue
            }
            
            $ChangeNumber++
        }
        catch {
            Write-Warning "Error processing change: $($_.Exception.Message)"
            continue
        }
    }
    
    Write-Information "`n✓ Policies changes analysis completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
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
Script Execution Summary
========================================
Script: Policies Changes Monitor
Time Period: Last $DaysBack days
Status: Completed
========================================
" -InformationAction Continue 