<#
.TITLE
    Get Intune Audit Logs

.SYNOPSIS
    Retrieves and displays audit log entries from Microsoft Intune with filtering and export options.

.DESCRIPTION
    This script connects to Microsoft Graph to retrieve audit log entries from Intune,
    showing administrative actions, configuration changes, and other tracked activities.
    It provides detailed information about who performed actions, what was changed,
    when it occurred, and the result. Supports filtering by date range, user, and
    activity type, with options to export results to CSV or HTML format.

.TAGS
    Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All,DeviceManagementConfiguration.Read.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-06-23

.EXAMPLE
    .\get-intune-audit-logs.ps1
    Displays the last 20 audit log entries

.EXAMPLE
    .\get-intune-audit-logs.ps1 -NumberOfEntries 50 -DaysBack 7
    Shows the last 50 audit entries from the past 7 days

.EXAMPLE
    .\get-intune-audit-logs.ps1 -FilterByUser "admin@company.com" -ExportToCsv
    Shows all audit entries for a specific user and exports to CSV

.EXAMPLE
    .\get-intune-audit-logs.ps1 -FilterByActivity "*Policy*" -ExportToHtml -OpenReport
    Shows audit entries related to policy changes and opens HTML report

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Audit logs are retained for 30 days in Intune
    - Uses beta endpoint for comprehensive audit data
    - Results are sorted by timestamp (newest first)
    - Supports wildcards in activity and user filters
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Number of audit entries to retrieve")]
    [ValidateRange(1, 1000)]
    [int]$NumberOfEntries = 20,
    
    [Parameter(Mandatory = $false, HelpMessage = "Number of days back to search")]
    [ValidateRange(1, 30)]
    [int]$DaysBack = 30,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by user (supports wildcards)")]
    [string]$FilterByUser,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by activity name (supports wildcards)")]
    [string]$FilterByActivity,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by category")]
    [ValidateSet("Application", "Device", "Role", "User", "Policy", "Compliance", "Enrollment", "All")]
    [string]$FilterByCategory = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Show only failed operations")]
    [switch]$OnlyFailures,
    
    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [switch]$ExportToCsv,
    
    [Parameter(Mandatory = $false, HelpMessage = "Export results to HTML")]
    [switch]$ExportToHtml,
    
    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false, HelpMessage = "Open HTML report after generation")]
    [switch]$OpenReport,
    
    [Parameter(Mandatory = $false, HelpMessage = "Show detailed properties for each entry")]
    [switch]$DetailedView,
    
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
                throw "Module '$ModuleName' is not available in Azure Automation"
            }
            else {
                Write-Information "Module '$ModuleName' not found. Installing..." -InformationAction Continue
                
                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }
                
                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }
                    
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }
        
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
}

# Detect execution environment
$IsAzureAutomation = $null -ne $PSPrivateMetadata.JobId.Guid

# Initialize required modules
$RequiredModules = @("Microsoft.Graph.Authentication")

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
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementApps.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        )
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
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
        [string]$Uri,
        [int]$Top = 0,
        [int]$DelayMs = 100
    )
    
    $allResults = @()
    $nextLink = $Uri
    $requestCount = 0
    $retrievedCount = 0
    
    do {
        try {
            if ($requestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
            
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            $requestCount++
            
            if ($response.value) {
                if ($Top -gt 0) {
                    $remaining = $Top - $retrievedCount
                    if ($remaining -le 0) { break }
                    
                    $toTake = [Math]::Min($response.value.Count, $remaining)
                    $allResults += $response.value[0..($toTake - 1)]
                    $retrievedCount += $toTake
                }
                else {
                    $allResults += $response.value
                    $retrievedCount += $response.value.Count
                }
            }
            
            $nextLink = $response.'@odata.nextLink'
            
            if ($requestCount % 10 -eq 0) {
                Write-Verbose "Retrieved $retrievedCount audit entries..."
            }
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data: $($_.Exception.Message)"
            break
        }
    } while ($nextLink -and ($Top -eq 0 -or $retrievedCount -lt $Top))
    
    return $allResults
}

function Get-CategoryFromActivity {
    param([string]$ActivityName)
    
    switch -Wildcard ($ActivityName) {
        "*Application*" { return "Application" }
        "*App*" { return "Application" }
        "*Device*" { return "Device" }
        "*Role*" { return "Role" }
        "*User*" { return "User" }
        "*Policy*" { return "Policy" }
        "*Compliance*" { return "Compliance" }
        "*Enrollment*" { return "Enrollment" }
        default { return "Other" }
    }
}

function Format-AuditEntry {
    param($Entry)
    
    $timestamp = [DateTime]::Parse($Entry.activityDateTime).ToLocalTime()
    $actor = if ($Entry.actor.userPrincipalName) { $Entry.actor.userPrincipalName } else { $Entry.actor.applicationDisplayName }
    $result = if ($Entry.activityResult -eq "Success") { "✓" } else { "✗" }
    $resultColor = if ($Entry.activityResult -eq "Success") { "Green" } else { "Red" }
    
    # Extract resource information
    $resources = @()
    foreach ($resource in $Entry.resources) {
        if ($resource.displayName) {
            $resources += $resource.displayName
        }
    }
    $resourceText = if ($resources.Count -gt 0) { $resources -join ", " } else { "N/A" }
    
    # Build output
    $output = @{
        Timestamp    = $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
        Actor        = $actor
        Activity     = $Entry.displayName
        Category     = $Entry.category
        Resources    = $resourceText
        Result       = $Entry.activityResult
        ResultSymbol = $result
        ResultColor  = $resultColor
    }
    
    if ($DetailedView -and $Entry.activityOperationType) {
        $output.OperationType = $Entry.activityOperationType
    }
    
    return $output
}

function Export-AuditToHtml {
    param($AuditEntries, $FilePath)
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Intune Audit Log Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .filters { background-color: #e3f2fd; padding: 10px; border-radius: 4px; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px 12px; border-bottom: 1px solid #e1e5e9; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e3f2fd; }
        .success { color: #28a745; font-weight: bold; }
        .failure { color: #dc3545; font-weight: bold; }
        .timestamp { color: #6c757d; }
        .category { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 12px; background-color: #e1e5e9; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Intune Audit Log Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p>Total Entries: $($AuditEntries.Count)</p>
        <p>Date Range: $($AuditEntries[-1].Timestamp) to $($AuditEntries[0].Timestamp)</p>
"@

    if ($FilterByUser -or $FilterByActivity -or $FilterByCategory -ne "All") {
        $htmlContent += @"
        <div class="filters">
            <strong>Applied Filters:</strong>
"@
        if ($FilterByUser) { $htmlContent += " User: $FilterByUser |" }
        if ($FilterByActivity) { $htmlContent += " Activity: $FilterByActivity |" }
        if ($FilterByCategory -ne "All") { $htmlContent += " Category: $FilterByCategory |" }
        $htmlContent = $htmlContent.TrimEnd(" |") + "</div>"
    }

    $htmlContent += @"
    </div>
    
    <table>
        <thead>
            <tr>
                <th>Timestamp</th>
                <th>User/Application</th>
                <th>Activity</th>
                <th>Category</th>
                <th>Resources</th>
                <th>Result</th>
            </tr>
        </thead>
        <tbody>
"@

    foreach ($entry in $AuditEntries) {
        $resultClass = if ($entry.Result -eq "Success") { "success" } else { "failure" }
        $htmlContent += @"
            <tr>
                <td class="timestamp">$($entry.Timestamp)</td>
                <td>$($entry.Actor)</td>
                <td>$($entry.Activity)</td>
                <td><span class="category">$($entry.Category)</span></td>
                <td>$($entry.Resources)</td>
                <td class="$resultClass">$($entry.ResultSymbol) $($entry.Result)</td>
            </tr>
"@
    }

    $htmlContent += @"
        </tbody>
    </table>
    
    <div class="footer">
        <p>Report generated by Intune Audit Log Script v1.0</p>
    </div>
</body>
</html>
"@

    $htmlContent | Out-File -FilePath $FilePath -Encoding UTF8
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving Intune audit logs..." -InformationAction Continue
    
    # Calculate date filter
    $startDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
    $dateFilter = "activityDateTime ge $startDate"
    
    # Build filter query
    $filters = @($dateFilter)
    
    if ($OnlyFailures) {
        $filters += "activityResult eq 'Failure'"
    }
    
    # Construct URI
    $baseUri = "https://graph.microsoft.com/beta/deviceManagement/auditEvents"
    $filterQuery = $filters -join " and "
    $uri = "$baseUri`?`$filter=$filterQuery&`$orderby=activityDateTime desc"
    
    if ($NumberOfEntries -lt 100) {
        $uri += "&`$top=$NumberOfEntries"
    }
    
    Write-Verbose "Query URI: $uri"
    
    # Get audit events
    $auditEvents = Get-MgGraphAllPages -Uri $uri -Top $NumberOfEntries
    
    Write-Information "✓ Retrieved $($auditEvents.Count) audit entries" -InformationAction Continue
    
    # Apply additional filters
    if ($FilterByUser) {
        $auditEvents = $auditEvents | Where-Object { 
            $_.actor.userPrincipalName -like $FilterByUser -or 
            $_.actor.applicationDisplayName -like $FilterByUser 
        }
    }
    
    if ($FilterByActivity) {
        $auditEvents = $auditEvents | Where-Object { $_.displayName -like $FilterByActivity }
    }
    
    if ($FilterByCategory -ne "All") {
        $auditEvents = $auditEvents | Where-Object { $_.category -eq $FilterByCategory }
    }
    
    # Format entries
    $formattedEntries = @()
    foreach ($auditEvent in $auditEvents) {
        $formattedEntries += Format-AuditEntry -Entry $auditEvent
    }
    
    # Display results
    if ($formattedEntries.Count -eq 0) {
        Write-Information "No audit entries found matching the specified criteria." -InformationAction Continue
    }
    else {
        Write-Information "`n📋 INTUNE AUDIT LOG ENTRIES" -InformationAction Continue
        Write-Information ("=" * 80) -InformationAction Continue
        
        foreach ($entry in $formattedEntries) {
            Write-Information "`n[$($entry.Timestamp)] $($entry.ResultSymbol) $($entry.Activity)" -InformationAction Continue
            
            Write-Information "   Actor: $($entry.Actor)" -InformationAction Continue
            
            Write-Information "   Category: $($entry.Category)" -InformationAction Continue
            
            Write-Information "   Resources: $($entry.Resources)" -InformationAction Continue
            
            if ($DetailedView -and $entry.OperationType) {
                Write-Information "   Operation: $($entry.OperationType)" -InformationAction Continue
            }
        }
        
        Write-Information "`n" -InformationAction Continue
        Write-Information ("=" * 80) -InformationAction Continue
        Write-Information "Total entries displayed: $($formattedEntries.Count)" -InformationAction Continue
    }
    
    # Export if requested
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    
    if ($ExportToCsv) {
        $csvPath = Join-Path $OutputPath "Intune_Audit_Log_$timestamp.csv"
        $formattedEntries | Select-Object Timestamp, Actor, Activity, Category, Resources, Result | 
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
    
    if ($ExportToHtml) {
        $htmlPath = Join-Path $OutputPath "Intune_Audit_Log_$timestamp.html"
        Export-AuditToHtml -AuditEntries $formattedEntries -FilePath $htmlPath
        Write-Information "✓ HTML report saved: $htmlPath" -InformationAction Continue
        
        if ($OpenReport) {
            Start-Process $htmlPath
        }
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}