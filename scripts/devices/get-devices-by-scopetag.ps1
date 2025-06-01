<#
.TITLE
    Get Devices by Scope Tag Report

.SYNOPSIS
    Generates comprehensive device reports filtered by Scope Tags with CSV and HTML export options

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all managed devices from Intune,
    filtering them by specified Scope Tags. It generates detailed reports showing device 
    status, owner information, enrollment profiles, compliance state, and other critical 
    data. The script supports both CSV and HTML output formats, with the HTML report 
    featuring a management-friendly styled interface.
    
    Ideal for multi-school environments or organizations using Scope Tags for 
    administrative delegation, this script helps analyze device distribution and 
    status across different organizational units.

.TAGS
    Devices,Compliance

.MINROLE
    Intune Service Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementRBAC.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-06-01

.EXAMPLE
    .\get-devices-by-scopetag.ps1 -IncludeScopeTag "School_A"
    Gets all devices with the "School_A" scope tag and exports CSV and HTML reports to current directory

.EXAMPLE
    .\get-devices-by-scopetag.ps1 -IncludeScopeTag "School_A,School_B" -ExportPath "C:\Reports"
    Gets devices from School_A and School_B, exports to both CSV and HTML in the specified directory

.EXAMPLE
    .\get-devices-by-scopetag.ps1 -ExcludeScopeTag "Default" -ExportPath "C:\Reports"
    Gets all devices except those with only the "Default" scope tag

.EXAMPLE
    .\get-devices-by-scopetag.ps1 -IncludeScopeTag "School_A" -Platform "Windows" -ComplianceState "Compliant"
    Gets only compliant Windows devices from School_A

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses Connect-MgGraph and Invoke-MgGraphRequest for all Graph operations
    - The script makes individual API calls for each device to retrieve scope tag information
    - Large environments may take several minutes to process due to individual device lookups
    - HTML report includes sorting and filtering capabilities
    - CSV export includes all device details for further analysis
    - Scope Tags must match exactly (case-sensitive)
    - Devices can have multiple scope tags assigned
    - The beta API endpoint is required to retrieve scope tag information
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated list of Scope Tags to include")]
    [string]$IncludeScopeTag,
    
    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated list of Scope Tags to exclude")]
    [string]$ExcludeScopeTag,
    
    [Parameter(Mandatory = $false, HelpMessage = "Directory path for CSV and HTML exports (defaults to current directory)")]
    [string]$ExportPath = (Get-Location).Path,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by specific platform (Windows, iOS, Android, macOS)")]
    [ValidateSet("Windows", "iOS", "Android", "macOS", "All")]
    [string]$Platform = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by compliance state")]
    [ValidateSet("Compliant", "NonCompliant", "Unknown", "All")]
    [string]$ComplianceState = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Show progress bar during processing")]
    [switch]$ShowProgressBar,
    
    [Parameter(Mandatory = $false, HelpMessage = "Include detailed device information")]
    [switch]$IncludeDetails,
    
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
    Write-Information "Running locally in IDE or terminal" -InformationAction Continue
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

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
        # Azure Automation - Use Managed Identity
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        # Local execution - Use interactive authentication
        Write-Information "Connecting to Microsoft Graph with interactive authentication..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementRBAC.Read.All"
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

# Function to fetch all scope tag details once
function Get-AllScopeTagDetail {
    Write-Verbose "Fetching all scope tag details..."
    $Uri = "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
    $scopeTagsResponse = Invoke-MgGraphRequest -Uri $Uri -Method GET

    $scopeTagDetails = @{
        "0" = @{
            DisplayName = "Default"
            Description = "Default scope tag"
        }
    }
    
    foreach ($scopeTag in $scopeTagsResponse.value) {
        $scopeTagDetails[$scopeTag.id] = @{
            DisplayName = $scopeTag.displayName
            Description = $scopeTag.description
        }
    }
    
    Write-Verbose "Retrieved $($scopeTagDetails.Count) scope tags"
    return $scopeTagDetails
}

# Function to get scope tag names from IDs using cached data
function Get-ScopeTagName {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ScopeTagIds,
        [Parameter(Mandatory = $true)]
        [hashtable]$ScopeTagCache
    )
    
    $ScopeTagNames = @()
    
    foreach ($TagId in $ScopeTagIds) {
        if ($ScopeTagCache.ContainsKey($TagId)) {
            $ScopeTagNames += $ScopeTagCache[$TagId].DisplayName
        }
        else {
            Write-Verbose "Unknown scope tag ID: $TagId"
            $ScopeTagNames += "Unknown ($TagId)"
        }
    }
    
    return $ScopeTagNames -join ", "
}

# Function to format device information
function Format-DeviceInfo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,
        [Parameter(Mandatory = $true)]
        [hashtable]$ScopeTagCache,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails
    )
    
    # Get scope tag names
    $ScopeTagNames = if ($Device.roleScopeTagIds -and $Device.roleScopeTagIds.Count -gt 0) {
        Get-ScopeTagName -ScopeTagIds $Device.roleScopeTagIds -ScopeTagCache $ScopeTagCache
    }
    else {
        "None"
    }
    
    # Format dates
    $LastCheckIn = if ($Device.lastSyncDateTime -and $Device.lastSyncDateTime -ne "0001-01-01T00:00:00Z") {
        ([DateTime]::Parse($Device.lastSyncDateTime)).ToString("yyyy-MM-dd HH:mm:ss")
    }
    else {
        "Never"
    }
    
    $EnrollmentDate = if ($Device.enrolledDateTime -and $Device.enrolledDateTime -ne "0001-01-01T00:00:00Z") {
        ([DateTime]::Parse($Device.enrolledDateTime)).ToString("yyyy-MM-dd")
    }
    else {
        "Unknown"
    }
    
    # Get user principal name
    $UserPrincipalName = if ($Device.userPrincipalName) {
        $Device.userPrincipalName
    }
    else {
        "No User Assigned"
    }
    
    # Get enrollment profile name
    $EnrollmentProfile = if ($Device.enrollmentProfileName) {
        $Device.enrollmentProfileName
    }
    else {
        "Direct Enrollment"
    }
    
    # Build device info object
    $DeviceInfo = [PSCustomObject]@{
        ScopeTags         = $ScopeTagNames
        DeviceName        = $Device.deviceName
        Platform          = $Device.operatingSystem
        OSVersion         = $Device.osVersion
        Owner             = $UserPrincipalName
        EnrollmentProfile = $EnrollmentProfile
        LastCheckIn       = $LastCheckIn
        ComplianceState   = $Device.complianceState
        EnrollmentDate    = $EnrollmentDate
        SerialNumber      = $Device.serialNumber
        Model             = $Device.model
        Manufacturer      = $Device.manufacturer
        ManagementState   = $Device.managementState
        Ownership         = $Device.managedDeviceOwnerType
        DeviceId          = $Device.id
        AzureADDeviceId   = $Device.azureADDeviceId
        EnrollmentType    = $Device.deviceEnrollmentType
        AutoPilotEnrolled = $Device.autopilotEnrolled
        IsEncrypted       = $Device.isEncrypted
        TotalStorageSpace = if ($Device.totalStorageSpaceInBytes) { 
            [math]::Round($Device.totalStorageSpaceInBytes / 1GB, 2).ToString() + " GB" 
        }
        else { "Unknown" }
        FreeStorageSpace  = if ($Device.freeStorageSpaceInBytes) { 
            [math]::Round($Device.freeStorageSpaceInBytes / 1GB, 2).ToString() + " GB" 
        }
        else { "Unknown" }
    }
    
    if (-not $IncludeDetails) {
        $DeviceInfo = $DeviceInfo | Select-Object ScopeTags, DeviceName, Platform, OSVersion, Owner, 
        EnrollmentProfile, LastCheckIn, ComplianceState, EnrollmentDate
    }
    
    return $DeviceInfo
}

# Function to test if device matches scope tag criteria
function Test-DeviceScopeTag {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,
        [Parameter(Mandatory = $true)]
        [hashtable]$ScopeTagCache,
        [string[]]$IncludeTags,
        [string[]]$ExcludeTags
    )
    
    # Get device's scope tag names
    $DeviceScopeTags = if ($Device.roleScopeTagIds -and $Device.roleScopeTagIds.Count -gt 0) {
        $TagNames = @()
        foreach ($TagId in $Device.roleScopeTagIds) {
            if ($ScopeTagCache.ContainsKey($TagId)) {
                $TagNames += $ScopeTagCache[$TagId].DisplayName
            }
        }
        $TagNames
    }
    else {
        @()
    }
    
    # Check exclude tags first
    if ($ExcludeTags -and $ExcludeTags.Count -gt 0) {
        foreach ($ExcludeTag in $ExcludeTags) {
            if ($DeviceScopeTags -contains $ExcludeTag) {
                return $false
            }
        }
    }
    
    # Check include tags
    if ($IncludeTags -and $IncludeTags.Count -gt 0) {
        foreach ($IncludeTag in $IncludeTags) {
            if ($DeviceScopeTags -contains $IncludeTag) {
                return $true
            }
        }
        return $false
    }
    
    # If no include tags specified, include all (unless excluded)
    return $true
}

# Function to generate HTML report
function New-HTMLReport {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Devices,
        [Parameter(Mandatory = $true)]
        [string]$ReportPath,
        [string[]]$IncludeTags,
        [string[]]$ExcludeTags
    )
    
    $ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $TotalDevices = $Devices.Count
    
    # Group devices by various categories
    $DevicesByPlatform = $Devices | Group-Object Platform
    $DevicesByCompliance = $Devices | Group-Object ComplianceState
    $DevicesByScopeTag = $Devices | Group-Object ScopeTags
    
    # Build HTML content
    $HTMLContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Intune Devices by Scope Tag Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078d4;
            margin-bottom: 10px;
        }
        .report-info {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 6px;
            border-left: 4px solid #0078d4;
        }
        .summary-card h3 {
            margin: 0 0 15px 0;
            color: #333;
            font-size: 16px;
        }
        .summary-card .value {
            font-size: 28px;
            font-weight: bold;
            color: #0078d4;
        }
        .filters {
            margin-bottom: 20px;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 6px;
        }
        .filter-group {
            display: inline-block;
            margin-right: 20px;
        }
        .filter-group label {
            margin-right: 8px;
            font-weight: 500;
        }
        .filter-group select, .filter-group input {
            padding: 6px 12px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
            font-size: 14px;
        }
        th {
            background-color: #0078d4;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 500;
            position: sticky;
            top: 0;
            z-index: 10;
        }
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #eee;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        .compliant {
            color: #107c10;
            font-weight: 500;
        }
        .noncompliant {
            color: #d83b01;
            font-weight: 500;
        }
        .unknown {
            color: #5c5c5c;
            font-weight: 500;
        }
        .platform-windows {
            color: #0078d4;
        }
        .platform-ios {
            color: #333;
        }
        .platform-android {
            color: #3ddc84;
        }
        .platform-macos {
            color: #555;
        }
        .export-buttons {
            margin-bottom: 20px;
        }
        .export-buttons button {
            background-color: #0078d4;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
            margin-right: 10px;
            font-size: 14px;
        }
        .export-buttons button:hover {
            background-color: #106ebe;
        }
        .chart-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .chart-box {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 6px;
            text-align: center;
        }
        .no-data {
            text-align: center;
            padding: 40px;
            color: #666;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Intune Devices by Scope Tag Report</h1>
        <div class="report-info">
            Generated on: $ReportDate<br>
            Total Devices: $TotalDevices<br>
"@

    if ($IncludeTags) {
        $HTMLContent += "            Included Scope Tags: $($IncludeTags -join ', ')<br>`n"
    }
    if ($ExcludeTags) {
        $HTMLContent += "            Excluded Scope Tags: $($ExcludeTags -join ', ')<br>`n"
    }

    $HTMLContent += @"
        </div>

        <div class="summary-cards">
            <div class="summary-card">
                <h3>Total Devices</h3>
                <div class="value">$TotalDevices</div>
            </div>
"@

    # Add platform summary cards
    foreach ($Platform in $DevicesByPlatform) {
        $HTMLContent += @"
            <div class="summary-card">
                <h3>$($Platform.Name) Devices</h3>
                <div class="value">$($Platform.Count)</div>
            </div>
"@
    }

    $HTMLContent += @"
        </div>

        <div class="filters">
            <div class="filter-group">
                <label>Search:</label>
                <input type="text" id="searchInput" placeholder="Search devices..." onkeyup="filterTable()">
            </div>
            <div class="filter-group">
                <label>Platform:</label>
                <select id="platformFilter" onchange="filterTable()">
                    <option value="">All Platforms</option>
"@

    foreach ($Platform in $DevicesByPlatform) {
        $HTMLContent += "                    <option value=`"$($Platform.Name)`">$($Platform.Name)</option>`n"
    }

    $HTMLContent += @"
                </select>
            </div>
            <div class="filter-group">
                <label>Compliance:</label>
                <select id="complianceFilter" onchange="filterTable()">
                    <option value="">All States</option>
                    <option value="compliant">Compliant</option>
                    <option value="noncompliant">Non-Compliant</option>
                    <option value="unknown">Unknown</option>
                </select>
            </div>
            <div class="filter-group">
                <label>Scope Tag:</label>
                <select id="scopeTagFilter" onchange="filterTable()">
                    <option value="">All Scope Tags</option>
"@

    foreach ($ScopeTag in $DevicesByScopeTag | Sort-Object Name) {
        $HTMLContent += "                    <option value=`"$($ScopeTag.Name)`">$($ScopeTag.Name) ($($ScopeTag.Count))</option>`n"
    }

    $HTMLContent += @"
                </select>
            </div>
        </div>

        <div class="export-buttons">
            <button onclick="exportTableToCSV('device-report.csv')">Export Visible Data to CSV</button>
            <button onclick="window.print()">Print Report</button>
        </div>

"@

    if ($Devices.Count -gt 0) {
        $HTMLContent += @"
        <table id="deviceTable">
            <thead>
                <tr>
                    <th>Scope Tags</th>
                    <th>Device Name</th>
                    <th>Platform</th>
                    <th>OS Version</th>
                    <th>Owner</th>
                    <th>Enrollment Profile</th>
                    <th>Last Check-In</th>
                    <th>Compliance</th>
                    <th>Enrolled Date</th>
                </tr>
            </thead>
            <tbody>
"@

        foreach ($Device in $Devices | Sort-Object ScopeTags, DeviceName) {
            $ComplianceClass = switch ($Device.ComplianceState) {
                "compliant" { "compliant" }
                "noncompliant" { "noncompliant" }
                default { "unknown" }
            }
            
            $PlatformClass = "platform-$($Device.Platform.ToLower())"
            
            $HTMLContent += @"
                <tr>
                    <td>$($Device.ScopeTags)</td>
                    <td>$($Device.DeviceName)</td>
                    <td class="$PlatformClass">$($Device.Platform)</td>
                    <td>$($Device.OSVersion)</td>
                    <td>$($Device.Owner)</td>
                    <td>$($Device.EnrollmentProfile)</td>
                    <td>$($Device.LastCheckIn)</td>
                    <td class="$ComplianceClass">$($Device.ComplianceState)</td>
                    <td>$($Device.EnrollmentDate)</td>
                </tr>
"@
        }

        $HTMLContent += @"
            </tbody>
        </table>
"@
    }
    else {
        $HTMLContent += @"
        <div class="no-data">
            No devices found matching the specified criteria.
        </div>
"@
    }

    $HTMLContent += @"
    </div>

    <script>
        function filterTable() {
            const searchInput = document.getElementById('searchInput').value.toLowerCase();
            const platformFilter = document.getElementById('platformFilter').value.toLowerCase();
            const complianceFilter = document.getElementById('complianceFilter').value.toLowerCase();
            const scopeTagFilter = document.getElementById('scopeTagFilter').value.toLowerCase();
            
            const table = document.getElementById('deviceTable');
            const tr = table.getElementsByTagName('tr');
            
            for (let i = 1; i < tr.length; i++) {
                const scopeTag = tr[i].getElementsByTagName('td')[0].textContent.toLowerCase();
                const deviceName = tr[i].getElementsByTagName('td')[1].textContent.toLowerCase();
                const platform = tr[i].getElementsByTagName('td')[2].textContent.toLowerCase();
                const owner = tr[i].getElementsByTagName('td')[4].textContent.toLowerCase();
                const compliance = tr[i].getElementsByTagName('td')[7].textContent.toLowerCase();
                
                const matchesSearch = deviceName.includes(searchInput) || owner.includes(searchInput) || scopeTag.includes(searchInput);
                const matchesPlatform = !platformFilter || platform === platformFilter;
                const matchesCompliance = !complianceFilter || compliance === complianceFilter;
                const matchesScopeTag = !scopeTagFilter || scopeTag === scopeTagFilter;
                
                if (matchesSearch && matchesPlatform && matchesCompliance && matchesScopeTag) {
                    tr[i].style.display = '';
                } else {
                    tr[i].style.display = 'none';
                }
            }
        }
        
        function exportTableToCSV(filename) {
            const table = document.getElementById('deviceTable');
            const rows = Array.from(table.querySelectorAll('tr:not([style*="display: none"])'));
            
            const csv = rows.map(row => {
                const cells = Array.from(row.querySelectorAll('th, td'));
                return cells.map(cell => {
                    let text = cell.textContent.replace(/"/g, '""');
                    return `"${text}"`;
                }).join(',');
            }).join('\n');
            
            const blob = new Blob([csv], { type: 'text/csv' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.setAttribute('hidden', '');
            a.setAttribute('href', url);
            a.setAttribute('download', filename);
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
        }
    </script>
</body>
</html>
"@

    # Write HTML file
    try {
        $HTMLContent | Out-File -FilePath $ReportPath -Encoding UTF8
        Write-Information "✓ HTML report saved to: $ReportPath" -InformationAction Continue
    }
    catch {
        Write-Warning "Failed to save HTML report: $($_.Exception.Message)"
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting device report generation..." -InformationAction Continue
    
    # Parse scope tags
    $IncludeTags = if ($IncludeScopeTag) { $IncludeScopeTag -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    $ExcludeTags = if ($ExcludeScopeTag) { $ExcludeScopeTag -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    
    Write-Information "Configuration:" -InformationAction Continue
    if ($IncludeTags.Count -gt 0) {
        Write-Information "  - Include Scope Tags: $($IncludeTags -join ', ')" -InformationAction Continue
    }
    if ($ExcludeTags.Count -gt 0) {
        Write-Information "  - Exclude Scope Tags: $($ExcludeTags -join ', ')" -InformationAction Continue
    }
    Write-Information "  - Platform filter: $Platform" -InformationAction Continue
    Write-Information "  - Compliance filter: $ComplianceState" -InformationAction Continue
    
    # Fetch all scope tag details upfront
    Write-Information "Fetching scope tag details..." -InformationAction Continue
    $ScopeTagCache = Get-AllScopeTagDetail
    Write-Information "✓ Retrieved $($ScopeTagCache.Count) scope tags" -InformationAction Continue
    
    # Build the API URI with platform filter using beta endpoint for full device details
    $BaseUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
    $FilterParts = @()
    
    if ($Platform -ne "All") {
        $FilterParts += "operatingSystem eq '$Platform'"
    }
    
    if ($ComplianceState -ne "All") {
        $FilterParts += "complianceState eq '$($ComplianceState.ToLower())'"
    }
    
    $Uri = if ($FilterParts.Count -gt 0) {
        "$BaseUri?`$filter=" + ($FilterParts -join ' and ')
    }
    else {
        $BaseUri
    }
    
    # Retrieve all managed devices
    Write-Information "Retrieving managed devices from Intune..." -InformationAction Continue
    $AllDevices = Get-MgGraphAllPage -Uri $Uri
    Write-Information "✓ Retrieved $($AllDevices.Count) devices" -InformationAction Continue
    
    # Process devices
    Write-Information "Processing devices..." -InformationAction Continue
    if ($AllDevices.Count -gt 100) {
        Write-Information "Note: Processing $($AllDevices.Count) devices with individual API calls for scope tags. This may take several minutes." -InformationAction Continue
    }
    $FilteredDevices = @()
    $ProcessedCount = 0
    
    foreach ($Device in $AllDevices) {
        $ProcessedCount++
        
        if ($ShowProgressBar) {
            $PercentComplete = [math]::Round(($ProcessedCount / $AllDevices.Count) * 100)
            Write-Progress -Activity "Processing devices" -Status "Device $ProcessedCount of $($AllDevices.Count)" -PercentComplete $PercentComplete
        }
        
        # Fetch full device details to get roleScopeTagIds
        try {
            $DeviceDetailsUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($Device.id)')"
            $DeviceDetails = Invoke-MgGraphRequest -Uri $DeviceDetailsUri -Method GET
            
            # Use the detailed device object which includes roleScopeTagIds
            if (Test-DeviceScopeTag -Device $DeviceDetails -ScopeTagCache $ScopeTagCache -IncludeTags $IncludeTags -ExcludeTags $ExcludeTags) {
                $FormattedDevice = Format-DeviceInfo -Device $DeviceDetails -ScopeTagCache $ScopeTagCache -IncludeDetails:$IncludeDetails
                $FilteredDevices += $FormattedDevice
            }
        }
        catch {
            Write-Warning "Could not retrieve details for device $($Device.deviceName): $($_.Exception.Message)"
        }
    }
    
    if ($ShowProgressBar) {
        Write-Progress -Activity "Processing devices" -Completed
    }
    
    # Display results
    Write-Information "✓ Processing completed" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "DEVICE REPORT BY SCOPE TAG" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total devices retrieved: $($AllDevices.Count)" -InformationAction Continue
    Write-Information "Devices matching criteria: $($FilteredDevices.Count)" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    if ($FilteredDevices.Count -gt 0) {
        # Group by scope tag for summary
        $ScopeTagSummary = $FilteredDevices | Group-Object ScopeTags | Sort-Object Count -Descending
        Write-Information "Devices by Scope Tag:" -InformationAction Continue
        foreach ($Group in $ScopeTagSummary) {
            Write-Information "  - $($Group.Name): $($Group.Count) devices" -InformationAction Continue
        }
        Write-Information "" -InformationAction Continue
        
        # Display the devices (limited view in console)
        $FilteredDevices | Select-Object -First 10 | Format-Table -AutoSize
        
        if ($FilteredDevices.Count -gt 10) {
            Write-Information "... and $($FilteredDevices.Count - 10) more devices" -InformationAction Continue
        }
        
        # Export reports
        # Ensure export directory exists
        if (-not (Test-Path $ExportPath)) {
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
        }
        
        # Generate filenames with timestamp
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $CSVFileName = "DeviceReport_ByScopeTag_$Timestamp.csv"
        $HTMLFileName = "DeviceReport_ByScopeTag_$Timestamp.html"
        
        $CSVPath = Join-Path $ExportPath $CSVFileName
        $HTMLPath = Join-Path $ExportPath $HTMLFileName
        
        # Export to CSV
        try {
            $FilteredDevices | Export-Csv -Path $CSVPath -NoTypeInformation
            Write-Information "✓ CSV report saved to: $CSVPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to export CSV: $($_.Exception.Message)"
        }
        
        # Generate HTML report
        New-HTMLReport -Devices $FilteredDevices -ReportPath $HTMLPath -IncludeTags $IncludeTags -ExcludeTags $ExcludeTags
    }
    else {
        Write-Information "No devices found matching the specified criteria." -InformationAction Continue
    }
    
    Write-Information "✓ Script completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Ignore disconnection errors
        Write-Verbose "Graph disconnection completed (may have already been disconnected)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Script Execution Summary
========================================
Script: Get Devices by Scope Tag Report
Parameters: 
  - Include Tags: $($IncludeTags -join ', ')
  - Exclude Tags: $($ExcludeTags -join ', ')
  - Platform: $Platform
  - Compliance: $ComplianceState
Devices Analyzed: $($AllDevices.Count)
Devices in Report: $($FilteredDevices.Count)
Status: Completed
========================================
" -InformationAction Continue