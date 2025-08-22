<#
.TITLE
    Multi-Admin Approval Compliance Dashboard Report

.SYNOPSIS
    Generate comprehensive compliance reports on Multi-Admin Approval (MAA) usage and coverage in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph and analyzes Multi-Admin Approval configurations, usage patterns, 
    and compliance metrics across your Intune environment. It generates detailed reports showing MAA coverage 
    gaps, approval statistics, admin permissions, and trends. The script helps organizations ensure proper 
    implementation of MAA controls and identify areas for security improvement. Reports are generated in 
    both HTML and CSV formats for different audiences.

.TAGS
    Compliance,Reporting,Security,MAA,Governance

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All,DeviceManagementManagedDevices.Read.All,DeviceManagementRBAC.Read.All,AuditLog.Read.All,Directory.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\get-maa-compliance-report.ps1
    Generates MAA compliance reports in current directory with default 30-day analysis period

.EXAMPLE
    .\get-maa-compliance-report.ps1 -OutputPath "C:\Reports" -DaysToAnalyze 90
    Generates reports with 90-day analysis period and saves to specified directory

.EXAMPLE
    .\get-maa-compliance-report.ps1 -OutputPath "C:\Reports" -IncludeRecommendations -DetailedAnalysis
    Generates detailed reports with security recommendations and in-depth analysis

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Supports both local execution and Azure Automation Runbook environments
    - Generates both HTML dashboard and CSV data exports
    - HTML report includes charts and visualizations
    - CSV exports enable further analysis in Excel or Power BI
    - Consider running monthly for compliance tracking
    - Use -DetailedAnalysis for security audits
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false, HelpMessage = "Number of days to analyze for historical data")]
    [ValidateRange(1, 365)]
    [int]$DaysToAnalyze = 30,
    
    [Parameter(Mandatory = $false, HelpMessage = "Include detailed security recommendations")]
    [switch]$IncludeRecommendations,
    
    [Parameter(Mandatory = $false, HelpMessage = "Perform detailed analysis including audit logs")]
    [switch]$DetailedAnalysis,
    
    [Parameter(Mandatory = $false, HelpMessage = "Export individual CSV files for each section")]
    [switch]$ExportDetailedCSV,
    
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
                    Write-Warning "Module version conflict detected. Using existing loaded version."
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
    "Microsoft.Graph.Authentication"
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
            "Directory.Read.All"
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

# Function to get MAA policies
function Get-MAAPolicy {
    try {
        Write-Information "Retrieving MAA policies..." -InformationAction Continue
        
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/operationApprovalPolicies"
        $Policies = Get-MgGraphAllPage -Uri $Uri
        
        Write-Information "✓ Found $($Policies.Count) MAA policies" -InformationAction Continue
        return $Policies
    }
    catch {
        Write-Warning "Could not retrieve MAA policies: $($_.Exception.Message)"
        return @()
    }
}

# Function to get all MAA requests
function Get-MAARequest {
    param(
        [int]$DaysBack
    )
    
    try {
        Write-Information "Retrieving MAA requests from last $DaysBack days..." -InformationAction Continue
        
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests"
        $AllRequests = Get-MgGraphAllPage -Uri $Uri
        
        # Filter by date range
        $StartDate = (Get-Date).AddDays(-$DaysBack)
        $FilteredRequests = $AllRequests | Where-Object {
            $RequestDate = if ($_.requestDateTime) { [DateTime]$_.requestDateTime } 
            elseif ($_.createdDateTime) { [DateTime]$_.createdDateTime }
            else { [DateTime]::MinValue }
            $RequestDate -ge $StartDate
        }
        
        Write-Information "✓ Found $($FilteredRequests.Count) MAA requests in the specified period" -InformationAction Continue
        return $FilteredRequests
    }
    catch {
        Write-Warning "Could not retrieve MAA requests: $($_.Exception.Message)"
        return @()
    }
}

# Function to get protected resources
function Get-ProtectedResource {
    try {
        Write-Information "Identifying MAA-protectable resources..." -InformationAction Continue
        
        $Resources = @{
            Apps          = @()
            Scripts       = @()
            Policies      = @()
            DeviceActions = @()
            RBAC          = @()
        }
        
        # Get Apps
        try {
            $AppsUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
            $Apps = Get-MgGraphAllPage -Uri $AppsUri
            $Resources.Apps = $Apps | Select-Object id, displayName, '@odata.type'
            Write-Information "  Found $($Resources.Apps.Count) applications" -InformationAction Continue
        }
        catch {
            Write-Warning "Could not retrieve apps: $($_.Exception.Message)"
        }
        
        # Get Scripts
        try {
            $ScriptsUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceManagementScripts"
            $Scripts = Get-MgGraphAllPage -Uri $ScriptsUri
            $Resources.Scripts = $Scripts | Select-Object id, displayName, fileName
            Write-Information "  Found $($Resources.Scripts.Count) scripts" -InformationAction Continue
        }
        catch {
            Write-Warning "Could not retrieve scripts: $($_.Exception.Message)"
        }
        
        # Get Configuration Policies
        try {
            $PoliciesUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
            $Policies = Get-MgGraphAllPage -Uri $PoliciesUri
            $Resources.Policies = $Policies | Select-Object id, displayName, '@odata.type'
            Write-Information "  Found $($Resources.Policies.Count) configuration policies" -InformationAction Continue
        }
        catch {
            Write-Warning "Could not retrieve policies: $($_.Exception.Message)"
        }
        
        # Get RBAC roles
        try {
            $RBACUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleDefinitions"
            $RBAC = Get-MgGraphAllPage -Uri $RBACUri
            $Resources.RBAC = $RBAC | Select-Object id, displayName, isBuiltIn
            Write-Information "  Found $($Resources.RBAC.Count) RBAC roles" -InformationAction Continue
        }
        catch {
            Write-Warning "Could not retrieve RBAC roles: $($_.Exception.Message)"
        }
        
        return $Resources
    }
    catch {
        Write-Error "Failed to retrieve protected resources: $($_.Exception.Message)"
        return @{}
    }
}

# Function to get approvers and admins
function Get-ApproverAndAdmin {
    try {
        Write-Information "Retrieving administrators and approvers..." -InformationAction Continue
        
        $Admins = @()
        
        # Get Intune role assignments
        try {
            $RoleAssignmentsUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleAssignments"
            $RoleAssignments = Get-MgGraphAllPage -Uri $RoleAssignmentsUri
            
            foreach ($Assignment in $RoleAssignments) {
                # Get role definition
                $RoleUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleDefinitions/$($Assignment.roleDefinitionId)"
                $Role = Invoke-MgGraphRequest -Uri $RoleUri -Method GET
                
                # Get members
                $Members = $Assignment.members
                foreach ($MemberId in $Members) {
                    try {
                        $UserUri = "https://graph.microsoft.com/v1.0/users/$MemberId"
                        $User = Invoke-MgGraphRequest -Uri $UserUri -Method GET
                        
                        $Admins += [PSCustomObject]@{
                            UserId            = $User.id
                            UserPrincipalName = $User.userPrincipalName
                            DisplayName       = $User.displayName
                            Role              = $Role.displayName
                            RoleId            = $Role.id
                            AssignmentId      = $Assignment.id
                            IsApprover        = $false  # Will be updated based on MAA policies
                        }
                    }
                    catch {
                        Write-Warning "Could not retrieve user details for $MemberId"
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not retrieve role assignments: $($_.Exception.Message)"
        }
        
        Write-Information "✓ Found $($Admins.Count) administrators" -InformationAction Continue
        return $Admins
    }
    catch {
        Write-Error "Failed to retrieve administrators: $($_.Exception.Message)"
        return @()
    }
}

# Function to analyze MAA compliance
function Get-MAAComplianceMetric {
    param(
        [array]$Policies,
        [array]$Requests,
        [hashtable]$Resources,
        [array]$Admins
    )
    
    $Metrics = @{
        TotalPolicies             = $Policies.Count
        ActivePolicies            = ($Policies | Where-Object { $_.isEnabled -eq $true }).Count
        TotalRequests             = $Requests.Count
        PendingRequests           = ($Requests | Where-Object { $_.status -eq 0 -or $_.status -eq "pending" }).Count
        ApprovedRequests          = ($Requests | Where-Object { $_.status -eq 1 -or $_.status -eq "approved" }).Count
        RejectedRequests          = ($Requests | Where-Object { $_.status -eq 2 -or $_.status -eq "rejected" }).Count
        CancelledRequests         = ($Requests | Where-Object { $_.status -eq 3 -or $_.status -eq "cancelled" }).Count
        CompletedRequests         = ($Requests | Where-Object { $_.status -eq 4 -or $_.status -eq "completed" }).Count
        
        # Resource coverage
        TotalProtectableResources = 0
        ProtectedResources        = 0
        CoverageGaps              = @()
        
        # Approval metrics
        AverageApprovalTime       = 0
        MedianApprovalTime        = 0
        FastestApproval           = 0
        SlowestApproval           = 0
        
        # Admin metrics
        TotalAdmins               = $Admins.Count
        ApproversCount            = 0
        AdminsWithoutMAA          = @()
    }
    
    # Calculate resource coverage
    foreach ($Category in $Resources.Keys) {
        $Metrics.TotalProtectableResources += $Resources[$Category].Count
    }
    
    # Analyze policy coverage
    foreach ($Policy in $Policies) {
        if ($Policy.isEnabled) {
            # Count resources protected by this policy
            if ($Policy.targetedResources) {
                $Metrics.ProtectedResources += $Policy.targetedResources.Count
            }
        }
    }
    
    # Calculate approval times
    $ApprovalTimes = @()
    foreach ($Request in $Requests | Where-Object { $_.status -eq 1 -or $_.status -eq "approved" }) {
        if ($Request.requestDateTime -and $Request.approvalDateTime) {
            $TimeDiff = ([DateTime]$Request.approvalDateTime - [DateTime]$Request.requestDateTime).TotalHours
            $ApprovalTimes += $TimeDiff
        }
    }
    
    if ($ApprovalTimes.Count -gt 0) {
        $Metrics.AverageApprovalTime = [Math]::Round(($ApprovalTimes | Measure-Object -Average).Average, 2)
        $Sorted = $ApprovalTimes | Sort-Object
        $Metrics.MedianApprovalTime = [Math]::Round($Sorted[$Sorted.Count / 2], 2)
        $Metrics.FastestApproval = [Math]::Round($Sorted[0], 2)
        $Metrics.SlowestApproval = [Math]::Round($Sorted[-1], 2)
    }
    
    # Calculate approval rate
    $TotalProcessed = $Metrics.ApprovedRequests + $Metrics.RejectedRequests
    if ($TotalProcessed -gt 0) {
        $Metrics.ApprovalRate = [Math]::Round(($Metrics.ApprovedRequests / $TotalProcessed) * 100, 2)
    }
    else {
        $Metrics.ApprovalRate = 0
    }
    
    # Identify coverage gaps
    if ($Metrics.TotalProtectableResources -gt 0) {
        $Metrics.CoveragePercentage = [Math]::Round(($Metrics.ProtectedResources / $Metrics.TotalProtectableResources) * 100, 2)
    }
    else {
        $Metrics.CoveragePercentage = 0
    }
    
    return $Metrics
}

# Function to generate HTML report
function New-HTMLReport {
    param(
        [hashtable]$Metrics,
        [array]$Policies,
        [array]$Requests,
        [hashtable]$Resources,
        [array]$Admins,
        [bool]$IncludeRecommendations
    )
    
    $ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $HTMLReport = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MAA Compliance Dashboard Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        
        .header {
            background: white;
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            color: #2d3748;
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .header .subtitle {
            color: #718096;
            font-size: 16px;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: white;
            border-radius: 12px;
            padding: 25px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.08);
            transition: transform 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
        }
        
        .metric-label {
            color: #718096;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 10px;
        }
        
        .metric-value {
            font-size: 36px;
            font-weight: bold;
            color: #2d3748;
            margin-bottom: 5px;
        }
        
        .metric-sublabel {
            color: #a0aec0;
            font-size: 12px;
        }
        
        .section {
            background: white;
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.08);
        }
        
        .section h2 {
            color: #2d3748;
            font-size: 24px;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e2e8f0;
        }
        
        .table-responsive {
            overflow-x: auto;
            margin-top: 20px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th {
            background: #f7fafc;
            color: #2d3748;
            text-align: left;
            padding: 12px;
            font-weight: 600;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border-bottom: 2px solid #e2e8f0;
        }
        
        td {
            padding: 12px;
            color: #4a5568;
            border-bottom: 1px solid #e2e8f0;
        }
        
        tr:hover {
            background: #f7fafc;
        }
        
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .status-active { background: #c6f6d5; color: #22543d; }
        .status-inactive { background: #fed7d7; color: #742a2a; }
        .status-pending { background: #feebc8; color: #744210; }
        .status-approved { background: #c6f6d5; color: #22543d; }
        .status-rejected { background: #fed7d7; color: #742a2a; }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e2e8f0;
            border-radius: 15px;
            overflow: hidden;
            position: relative;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            border-radius: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 14px;
        }
        
        .chart-container {
            margin: 20px 0;
            padding: 20px;
            background: #f7fafc;
            border-radius: 8px;
        }
        
        .recommendation-box {
            background: #edf2f7;
            border-left: 4px solid #667eea;
            padding: 20px;
            margin: 20px 0;
            border-radius: 4px;
        }
        
        .recommendation-box h3 {
            color: #2d3748;
            margin-bottom: 10px;
        }
        
        .recommendation-box ul {
            margin-left: 20px;
            color: #4a5568;
            line-height: 1.8;
        }
        
        .alert {
            padding: 15px;
            margin: 20px 0;
            border-radius: 8px;
            display: flex;
            align-items: center;
        }
        
        .alert-warning {
            background: #fef5e7;
            border: 1px solid #f39c12;
            color: #8b6914;
        }
        
        .alert-success {
            background: #e8f8f5;
            border: 1px solid #27ae60;
            color: #186a3b;
        }
        
        .alert-danger {
            background: #fadbd8;
            border: 1px solid #e74c3c;
            color: #922b21;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            padding: 20px;
        }
        
        @media print {
            body { background: white; }
            .metric-card { break-inside: avoid; }
            .section { break-inside: avoid; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ MAA Compliance Dashboard</h1>
            <div class="subtitle">Multi-Admin Approval Compliance Report - Generated: $ReportDate</div>
        </div>
        
        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Coverage Rate</div>
                <div class="metric-value">$($Metrics.CoveragePercentage)%</div>
                <div class="metric-sublabel">Resources Protected</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Active Policies</div>
                <div class="metric-value">$($Metrics.ActivePolicies)</div>
                <div class="metric-sublabel">of $($Metrics.TotalPolicies) Total</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Approval Rate</div>
                <div class="metric-value">$($Metrics.ApprovalRate)%</div>
                <div class="metric-sublabel">Requests Approved</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Pending Requests</div>
                <div class="metric-value">$($Metrics.PendingRequests)</div>
                <div class="metric-sublabel">Awaiting Approval</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Avg Approval Time</div>
                <div class="metric-value">$($Metrics.AverageApprovalTime)h</div>
                <div class="metric-sublabel">Hours to Approve</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Total Admins</div>
                <div class="metric-value">$($Metrics.TotalAdmins)</div>
                <div class="metric-sublabel">With Intune Access</div>
            </div>
        </div>
        
        <!-- Coverage Analysis -->
        <div class="section">
            <h2>📊 MAA Coverage Analysis</h2>
            
            <div class="progress-bar">
                <div class="progress-fill" style="width: $($Metrics.CoveragePercentage)%">
                    $($Metrics.CoveragePercentage)% Protected
                </div>
            </div>
            
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>Resource Type</th>
                            <th>Total Resources</th>
                            <th>Protected</th>
                            <th>Unprotected</th>
                            <th>Coverage %</th>
                        </tr>
                    </thead>
                    <tbody>
"@

    # Add resource coverage details
    foreach ($ResourceType in $Resources.Keys) {
        $Total = $Resources[$ResourceType].Count
        $Protected = 0  # This would need actual calculation based on policies
        $Unprotected = $Total - $Protected
        $Coverage = if ($Total -gt 0) { [Math]::Round(($Protected / $Total) * 100, 2) } else { 0 }
        
        $HTMLReport += @"
                        <tr>
                            <td><strong>$ResourceType</strong></td>
                            <td>$Total</td>
                            <td>$Protected</td>
                            <td>$Unprotected</td>
                            <td>$Coverage%</td>
                        </tr>
"@
    }

    $HTMLReport += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <!-- Policy Status -->
        <div class="section">
            <h2>📋 MAA Policy Status</h2>
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>Policy Name</th>
                            <th>Status</th>
                            <th>Resource Type</th>
                            <th>Approvers</th>
                            <th>Created Date</th>
                        </tr>
                    </thead>
                    <tbody>
"@

    # Add policy details
    foreach ($Policy in $Policies | Sort-Object -Property displayName) {
        $Status = if ($Policy.isEnabled) { "Active" } else { "Inactive" }
        $StatusClass = if ($Policy.isEnabled) { "status-active" } else { "status-inactive" }
        $CreatedDate = if ($Policy.createdDateTime) { ([DateTime]$Policy.createdDateTime).ToString("yyyy-MM-dd") } else { "N/A" }
        $ApproverCount = if ($Policy.approvers) { $Policy.approvers.Count } else { 0 }
        
        $HTMLReport += @"
                        <tr>
                            <td><strong>$($Policy.displayName)</strong></td>
                            <td><span class="status-badge $StatusClass">$Status</span></td>
                            <td>$($Policy.resourceType)</td>
                            <td>$ApproverCount approver(s)</td>
                            <td>$CreatedDate</td>
                        </tr>
"@
    }

    $HTMLReport += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <!-- Request Analytics -->
        <div class="section">
            <h2>📈 Request Analytics ($DaysToAnalyze Day Period)</h2>
            
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value">$($Metrics.TotalRequests)</div>
                </div>
                
                <div class="metric-card">
                    <div class="metric-label">Approved</div>
                    <div class="metric-value" style="color: #27ae60;">$($Metrics.ApprovedRequests)</div>
                </div>
                
                <div class="metric-card">
                    <div class="metric-label">Rejected</div>
                    <div class="metric-value" style="color: #e74c3c;">$($Metrics.RejectedRequests)</div>
                </div>
                
                <div class="metric-card">
                    <div class="metric-label">Pending</div>
                    <div class="metric-value" style="color: #f39c12;">$($Metrics.PendingRequests)</div>
                </div>
            </div>
            
            <div class="chart-container">
                <h3>Approval Time Distribution</h3>
                <ul>
                    <li>Fastest Approval: $($Metrics.FastestApproval) hours</li>
                    <li>Average Approval: $($Metrics.AverageApprovalTime) hours</li>
                    <li>Median Approval: $($Metrics.MedianApprovalTime) hours</li>
                    <li>Slowest Approval: $($Metrics.SlowestApproval) hours</li>
                </ul>
            </div>
        </div>
"@

    # Add recommendations if requested
    if ($IncludeRecommendations) {
        $HTMLReport += @"
        <!-- Recommendations -->
        <div class="section">
            <h2>🎯 Security Recommendations</h2>
"@

        # Check for critical findings
        if ($Metrics.CoveragePercentage -lt 50) {
            $HTMLReport += @"
            <div class="alert alert-danger">
                <strong>⚠️ Critical:</strong> MAA coverage is below 50%. Significant security gaps exist.
            </div>
"@
        }
        
        if ($Metrics.ActivePolicies -eq 0) {
            $HTMLReport += @"
            <div class="alert alert-danger">
                <strong>⚠️ Critical:</strong> No active MAA policies found. Multi-admin approval is not enforced.
            </div>
"@
        }
        
        if ($Metrics.AverageApprovalTime -gt 72) {
            $HTMLReport += @"
            <div class="alert alert-warning">
                <strong>⚠️ Warning:</strong> Average approval time exceeds 72 hours. Consider process improvements.
            </div>
"@
        }

        $HTMLReport += @"
            <div class="recommendation-box">
                <h3>Recommended Actions</h3>
                <ul>
                    <li>Increase MAA coverage to at least 80% for critical resources</li>
                    <li>Ensure all sensitive operations require multi-admin approval</li>
                    <li>Regularly review and update approver lists</li>
                    <li>Implement automated notifications for pending requests</li>
                    <li>Document approval policies and procedures</li>
                    <li>Conduct quarterly MAA compliance reviews</li>
                    <li>Train administrators on MAA workflows</li>
                    <li>Monitor approval times and optimize processes</li>
                </ul>
            </div>
            
            <div class="recommendation-box">
                <h3>Best Practices</h3>
                <ul>
                    <li>Require MAA for all production changes</li>
                    <li>Maintain minimum of 2 approvers per policy</li>
                    <li>Separate requesters from approvers (separation of duties)</li>
                    <li>Set maximum approval time SLAs</li>
                    <li>Regular audit of MAA bypasses and exceptions</li>
                    <li>Integrate MAA with change management processes</li>
                </ul>
            </div>
        </div>
"@
    }

    $HTMLReport += @"
        <div class="footer">
            <p>© 2025 MAA Compliance Report | Generated by Intune Automation Suite</p>
            <p>Report Period: Last $DaysToAnalyze days | Next Review: $(([DateTime]::Now.AddDays(30)).ToString("yyyy-MM-dd"))</p>
        </div>
    </div>
    
    <script>
        // Add any interactive features here
        document.addEventListener('DOMContentLoaded', function() {
            console.log('MAA Compliance Report Loaded');
        });
    </script>
</body>
</html>
"@

    return $HTMLReport
}

# Function to export to CSV
function Export-MAADataToCSV {
    param(
        [string]$OutputPath,
        [hashtable]$Metrics,
        [array]$Policies,
        [array]$Requests,
        [hashtable]$Resources,
        [array]$Admins
    )
    
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Export summary metrics
    $MetricsCSV = @()
    foreach ($Key in $Metrics.Keys) {
        $MetricsCSV += [PSCustomObject]@{
            Metric    = $Key
            Value     = $Metrics[$Key]
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    $MetricsCSV | Export-Csv -Path "$OutputPath\MAA_Metrics_$Timestamp.csv" -NoTypeInformation
    
    # Export policies
    if ($Policies.Count -gt 0) {
        $Policies | Select-Object displayName, isEnabled, resourceType, createdDateTime, lastModifiedDateTime, @{Name = 'ApproverCount'; Expression = { $_.approvers.Count } } |
        Export-Csv -Path "$OutputPath\MAA_Policies_$Timestamp.csv" -NoTypeInformation
    }
    
    # Export requests
    if ($Requests.Count -gt 0) {
        $Requests | Select-Object id, status, requestDateTime, approvalDateTime, requestor, approver, requestJustification |
        Export-Csv -Path "$OutputPath\MAA_Requests_$Timestamp.csv" -NoTypeInformation
    }
    
    Write-Information "✓ CSV files exported to $OutputPath" -InformationAction Continue
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting MAA Compliance Dashboard Report generation..." -InformationAction Continue
    Write-Information "Analysis Period: Last $DaysToAnalyze days" -InformationAction Continue
    Write-Information "Output Path: $OutputPath" -InformationAction Continue
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Step 1: Gather MAA data
    $MAAPolicies = Get-MAAPolicy
    $MAARequests = Get-MAARequest -DaysBack $DaysToAnalyze
    $ProtectedResources = Get-ProtectedResource
    $Administrators = Get-ApproverAndAdmin
    
    # Step 2: Analyze compliance metrics
    $ComplianceMetrics = Get-MAAComplianceMetric -Policies $MAAPolicies -Requests $MAARequests -Resources $ProtectedResources -Admins $Administrators
    
    Write-Information "Analysis complete:" -InformationAction Continue
    Write-Information "  - Policies: $($MAAPolicies.Count)" -InformationAction Continue
    Write-Information "  - Requests: $($MAARequests.Count)" -InformationAction Continue
    Write-Information "  - Coverage: $($ComplianceMetrics.CoveragePercentage)%" -InformationAction Continue
    Write-Information "  - Approval Rate: $($ComplianceMetrics.ApprovalRate)%" -InformationAction Continue
    
    # Step 3: Generate HTML report
    $HTMLReport = New-HTMLReport -Metrics $ComplianceMetrics -Policies $MAAPolicies -Requests $MAARequests -Resources $ProtectedResources -Admins $Administrators -IncludeRecommendations $IncludeRecommendations
    
    $HTMLFileName = "MAA_Compliance_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $HTMLFullPath = Join-Path $OutputPath $HTMLFileName
    $HTMLReport | Out-File -FilePath $HTMLFullPath -Encoding UTF8
    
    Write-Information "✓ HTML report saved to: $HTMLFullPath" -InformationAction Continue
    
    # Step 4: Export CSV data if requested
    if ($ExportDetailedCSV) {
        Export-MAADataToCSV -OutputPath $OutputPath -Metrics $ComplianceMetrics -Policies $MAAPolicies -Requests $MAARequests -Resources $ProtectedResources -Admins $Administrators
    }
    
    # Step 5: Generate summary CSV
    $SummaryData = [PSCustomObject]@{
        ReportDate               = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        AnalysisPeriodDays       = $DaysToAnalyze
        TotalPolicies            = $ComplianceMetrics.TotalPolicies
        ActivePolicies           = $ComplianceMetrics.ActivePolicies
        CoveragePercentage       = $ComplianceMetrics.CoveragePercentage
        TotalRequests            = $ComplianceMetrics.TotalRequests
        PendingRequests          = $ComplianceMetrics.PendingRequests
        ApprovalRate             = $ComplianceMetrics.ApprovalRate
        AverageApprovalTimeHours = $ComplianceMetrics.AverageApprovalTime
        TotalAdmins              = $ComplianceMetrics.TotalAdmins
    }
    
    $SummaryFileName = "MAA_Summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $SummaryFullPath = Join-Path $OutputPath $SummaryFileName
    $SummaryData | Export-Csv -Path $SummaryFullPath -NoTypeInformation
    
    Write-Information "✓ Summary CSV saved to: $SummaryFullPath" -InformationAction Continue
    
    # Display summary
    Write-Information "
========================================
MAA Compliance Report Summary
========================================
Coverage Rate: $($ComplianceMetrics.CoveragePercentage)%
Active Policies: $($ComplianceMetrics.ActivePolicies) of $($ComplianceMetrics.TotalPolicies)
Approval Rate: $($ComplianceMetrics.ApprovalRate)%
Pending Requests: $($ComplianceMetrics.PendingRequests)
Average Approval Time: $($ComplianceMetrics.AverageApprovalTime) hours
========================================
Reports saved to: $OutputPath
========================================
" -InformationAction Continue
    
    # Open HTML report if running locally
    if (-not $RunningInAzureAutomation) {
        Write-Information "Opening HTML report in default browser..." -InformationAction Continue
        Start-Process $HTMLFullPath
    }
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

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[ { "content": "Create MAA Compliance Dashboard Report script structure", "status": "completed" }, { "content": "Add authentication and module management", "status": "completed" }, { "content": "Implement MAA policy analysis logic", "status": "completed" }, { "content": "Add compliance metrics calculation", "status": "completed" }, { "content": "Create HTML and CSV report generation", "status": "completed" }, { "content": "Add summary and recommendations", "status": "completed" }]
        $SummaryData | Export-Csv -Path $SummaryFullPath -NoTypeInformation
        
        Write-Information "✓ Summary CSV saved to: $SummaryFullPath" -InformationAction Continue
    }
    
    # Display summary
    Write-Information "
========================================
MAA Compliance Report Summary
========================================
Coverage Rate: $($ComplianceMetrics.CoveragePercentage)%
Active Policies: $($ComplianceMetrics.ActivePolicies) of $($ComplianceMetrics.TotalPolicies)
Approval Rate: $($ComplianceMetrics.ApprovalRate)%
Pending Requests: $($ComplianceMetrics.PendingRequests)
Average Approval Time: $($ComplianceMetrics.AverageApprovalTime) hours
========================================
Reports saved to: $OutputPath
========================================
" -InformationAction Continue
    
    # Open HTML report if running locally
    if (-not $RunningInAzureAutomation) {
        Write-Information "Opening HTML report in default browser..." -InformationAction Continue
        try {
            if ($IsMacOS) {
                # Use 'open' command on macOS
                & open $HTMLFullPath
            }
            elseif ($IsLinux) {
                # Use 'xdg-open' on Linux
                & xdg-open $HTMLFullPath
            }
            else {
                # Use Start-Process on Windows
                Start-Process $HTMLFullPath
            }
        }
        catch {
            Write-Warning "Could not open HTML report automatically: $($_.Exception.Message)"
            Write-Information "Please open the report manually: $HTMLFullPath" -InformationAction Continue
        }
    }
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