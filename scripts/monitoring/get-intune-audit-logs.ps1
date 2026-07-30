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
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Malformed audit entries are now skipped with a warning instead of aborting the report; date filter is built from UTC; output directory is created automatically before exports; removed unused Get-CategoryFromActivity function; pagination helper keeps single-item results as arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing); report auto-open failures no longer abort the script
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\get-intune-audit-logs.ps1
    Displays the last 20 audit log entries

.EXAMPLE
    .\get-intune-audit-logs.ps1 -NumberOfEntries 50 -DaysBack 7
    Shows the last 50 audit entries from the past 7 days

.EXAMPLE
    .\get-intune-audit-logs.ps1 -FilterByUser "<recipient-address>" -ExportToCsv "true"
    Shows all audit entries for a specific user and exports to CSV

.EXAMPLE
    .\get-intune-audit-logs.ps1 -FilterByActivity "*Policy*" -ExportToHtml "true" -OpenReport "true"
    Shows audit entries related to policy changes and opens HTML report

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Audit logs are retained for 30 days in Intune
    - Uses beta endpoint for comprehensive audit data
    - Results are sorted by timestamp (newest first)
    - Supports wildcards in activity and user filters
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
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
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$OnlyFailures,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to HTML")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportToHtml,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Open HTML report after generation")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$OpenReport,

    [Parameter(Mandatory = $false, HelpMessage = "Show detailed properties for each entry")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$DetailedView,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
Remove-Variable -Name ForceModuleInstall
if ([string]::IsNullOrWhiteSpace($forceModuleInstallRaw)) {
    $ForceModuleInstall = $false
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("true", "1", '$true')) {
    $ForceModuleInstall = $true
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("false", "0", '$false')) {
    $ForceModuleInstall = $false
}
else {
    throw "Parameter 'ForceModuleInstall' accepts only true, false, 1, 0, $true, or $false."
}

# Azure Automation supplies portal parameter values as strings. Normalize the
# public boolean parameters once so local and runbook execution use real booleans.
foreach ($runbookBooleanParameter in @('OnlyFailures', 'ExportToCsv', 'ExportToHtml', 'OpenReport', 'DetailedView')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)
    Remove-Variable -Name $runbookBooleanParameter

    if ([string]::IsNullOrWhiteSpace($runbookBooleanRaw)) {
        Set-Variable -Name $runbookBooleanParameter -Value $false
        continue
    }

    switch ($runbookBooleanRaw.Trim().ToLowerInvariant()) {
        { $_ -in @("true", "1", '$true') } {
            Set-Variable -Name $runbookBooleanParameter -Value $true
        }
        { $_ -in @("false", "0", '$false') } {
            Set-Variable -Name $runbookBooleanParameter -Value $false
        }
        default {
            throw "Parameter '$runbookBooleanParameter' accepts only true, false, 1, 0, $true, or $false."
        }
    }
}

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

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

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
        Write-Output "Connecting to Microsoft Graph..."
        $Scopes = @(
            "DeviceManagementApps.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Output "✓ Successfully connected to Microsoft Graph"
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
            throw "Error fetching data: $($_.Exception.Message)"
        }
    } while ($nextLink -and ($Top -eq 0 -or $retrievedCount -lt $Top))

    # Comma prevents unrolling so single-element results stay arrays
    return , $allResults
}

function Format-AuditEntry {
    param($Entry)

    # fix issue with timestamp parsing
    if ($Entry.activityDateTime -is [DateTime]) {
        $timestamp = $Entry.activityDateTime.ToLocalTime()
    }
    else {
        $timestamp = [DateTime]::ParseExact($Entry.activityDateTime, @("MM/dd/yyyy HH:mm:ss", "yyyy-MM-ddTHH:mm:ss", "yyyy-MM-ddTHH:mm:ssZ", "yyyy-MM-ddTHH:mm:ss.fffffffZ"), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime()
    }

    $actor = if ($Entry.actor.userPrincipalName) { $Entry.actor.userPrincipalName } else { $Entry.actor.applicationDisplayName }
    $result = if ($Entry.activityResult -eq "Success") { "✓" } else { "✗" }
    $resultColor = if ($Entry.activityResult -eq "Success") { "Green" } else { "Red" }

    # Extract resource information

    [System.Collections.Generic.List[Object]]$resources = @()
    foreach ($resource in $Entry.resources) {
        if ($resource.displayName) {
            $resources.Add($resource.displayName)
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
    Write-Output "Retrieving Intune audit logs..."

    # Calculate date filter in UTC so it matches Graph timestamps
    $startDate = (Get-Date).ToUniversalTime().AddDays(-$DaysBack).ToString("yyyy-MM-dd")
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
    $auditEvents = Get-MgGraphAllPage -Uri $uri -Top $NumberOfEntries

    Write-Output "✓ Retrieved $($auditEvents.Count) audit entries"

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

    # Format entries; skip malformed records instead of aborting the report
    $formattedEntries = @()
    foreach ($auditEvent in $auditEvents) {
        try {
            $formattedEntries += Format-AuditEntry -Entry $auditEvent
        }
        catch {
            Write-Warning "Skipping malformed audit entry '$($auditEvent.id)': $($_.Exception.Message)"
        }
    }

    # Display results
    if ($formattedEntries.Count -eq 0) {
        Write-Output "No audit entries found matching the specified criteria."
    }
    else {
        Write-Output "`n📋 INTUNE AUDIT LOG ENTRIES"
        Write-Output ("=" * 80)

        foreach ($entry in $formattedEntries) {
            Write-Output "`n[$($entry.Timestamp)] $($entry.ResultSymbol) $($entry.Activity)"

            Write-Output "   Actor: $($entry.Actor)"

            Write-Output "   Category: $($entry.Category)"

            Write-Output "   Resources: $($entry.Resources)"

            if ($DetailedView -and $entry.OperationType) {
                Write-Output "   Operation: $($entry.OperationType)"
            }
        }

        Write-Output "`n"
        Write-Output ("=" * 80)
        Write-Output "Total entries displayed: $($formattedEntries.Count)"
    }

    # Export if requested
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    # Create output directory if it does not exist
    if (($ExportToCsv -or $ExportToHtml) -and -not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Output "Created output directory: $OutputPath"
    }

    if ($ExportToCsv) {
        $csvPath = Join-Path $OutputPath "Intune_Audit_Log_$timestamp.csv"
        $formattedEntries | Select-Object Timestamp, Actor, Activity, Category, Resources, Result |
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Output "✓ CSV report saved: $csvPath"
    }

    if ($ExportToHtml) {
        $htmlPath = Join-Path $OutputPath "Intune_Audit_Log_$timestamp.html"
        Export-AuditToHtml -AuditEntries $formattedEntries -FilePath $htmlPath
        Write-Output "✓ HTML report saved: $htmlPath"

        if ($OpenReport) {
            try {
                Start-Process $htmlPath
            }
            catch {
                Write-Warning "Could not open the report automatically: $($_.Exception.Message)"
            }
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
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
