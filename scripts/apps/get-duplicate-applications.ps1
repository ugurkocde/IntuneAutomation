<#
.TITLE
    Duplicate Applications Report

.SYNOPSIS
    Identify and report duplicate applications across all managed devices in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves all applications uploaded to Intune,
    and identifies potential duplicate applications. Duplicates are identified by applications with the same
    name but different publishers or name variations. The script generates detailed reports
    showing duplicate applications and their variations to help with application cleanup
    and standardization efforts.

.TAGS
    Apps,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-29

.EXAMPLE
    .\get-duplicate-applications.ps1
    Generates duplicate applications report for all Intune applications

.EXAMPLE
    .\get-duplicate-applications.ps1 -OutputPath "C:\Reports"
    Generates duplicate applications report and saves to specified directory

.EXAMPLE
    .\get-duplicate-applications.ps1 -ForceModuleInstall
    Forces module installation without prompting and generates the report

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - Reports are saved in both CSV and HTML formats
    - Analyzes applications uploaded to Intune, not device-installed applications
    - Duplicate detection criteria:
      * Same application name with different publishers
      * Applications with name variations (case differences, extra spaces, etc.)
      * Same application name with different app types
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Output directory for reports")]
    [string]$OutputPath = ".",
    
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
            "DeviceManagementApps.Read.All"
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
            
            # Show progress for large datasets
            if ($RequestCount % 10 -eq 0) {
                Write-Information "." -InformationAction Continue
            }
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

# Function to normalize application names for comparison
function Get-NormalizedAppName {
    param([string]$AppName)
    
    # Remove common suffixes and prefixes
    $normalized = $AppName -replace '\s*(x64|x86|32-bit|64-bit|\(.*?\))\s*', ''
    $normalized = $normalized -replace '\s+', ' '
    $normalized = $normalized.Trim()
    
    return $normalized.ToLower()
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting duplicate applications detection..." -InformationAction Continue
    
    # Get all Intune applications
    Write-Information "Retrieving Intune applications..." -InformationAction Continue
    $appsUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
    $intuneApps = Get-MgGraphAllPage -Uri $appsUri
    Write-Information "`n✓ Found $($intuneApps.Count) Intune applications" -InformationAction Continue
    
    # Create application inventory array
    $applicationInventory = @()
    $totalApplications = 0
    
    foreach ($app in $intuneApps) {
        # Skip if no display name
        if ([string]::IsNullOrWhiteSpace($app.displayName)) { continue }
        
        # Create application inventory entry
        $appEntry = [PSCustomObject]@{
            ApplicationName      = $app.displayName
            ApplicationId        = $app.id
            Publisher            = if ($app.publisher) { $app.publisher } else { "Unknown" }
            AppType              = $app.'@odata.type'
            Description          = $app.description
            CreatedDateTime      = $app.createdDateTime
            LastModifiedDateTime = $app.lastModifiedDateTime
            NormalizedName       = Get-NormalizedAppName -AppName $app.displayName
        }
        
        $applicationInventory += $appEntry
        $totalApplications++
    }
    
    # ============================================================================
    # DUPLICATE DETECTION LOGIC
    # ============================================================================
    
    Write-Information "Analyzing applications for duplicates..." -InformationAction Continue
    
    # Group applications by normalized name to find potential duplicates
    $appGroups = $applicationInventory | Group-Object NormalizedName
    
    # Filter groups that have multiple variations or meet minimum device count
    $duplicateGroups = @()
    
    foreach ($group in $appGroups) {
        # Skip if only one app in group (not a duplicate)
        if ($group.Count -lt 2) { continue }
        
        # Check for different publishers and names
        $publishers = $group.Group | Group-Object Publisher | Where-Object { $_.Name -ne "Unknown" }
        $originalNames = $group.Group | Group-Object ApplicationName
        $appTypes = $group.Group | Group-Object AppType
        
        $isDuplicate = $false
        $duplicateType = @()
        
        # Multiple publishers for same app name
        if ($publishers.Count -gt 1) {
            $isDuplicate = $true
            $duplicateType += "Multiple Publishers"
        }
        
        # Multiple original names (case differences, extra spaces, etc.)
        if ($originalNames.Count -gt 1) {
            $isDuplicate = $true
            $duplicateType += "Name Variations"
        }
        
        # Multiple app types for same name
        if ($appTypes.Count -gt 1) {
            $isDuplicate = $true
            $duplicateType += "Multiple App Types"
        }
        
        if ($isDuplicate) {
            $duplicateInfo = [PSCustomObject]@{
                NormalizedName = $group.Name
                OriginalNames  = ($originalNames | ForEach-Object { $_.Name }) -join "; "
                Publishers     = ($publishers | ForEach-Object { $_.Name }) -join "; "
                AppTypes       = ($appTypes | ForEach-Object { $_.Name }) -join "; "
                AppCount       = $group.Count
                DuplicateType  = $duplicateType -join ", "
                Applications   = $group.Group
            }
            $duplicateGroups += $duplicateInfo
        }
    }
    
    # Sort duplicates by app count (descending)
    $duplicateGroups = $duplicateGroups | Sort-Object AppCount -Descending
    
    Write-Information "✓ Found $($duplicateGroups.Count) duplicate application groups:" -InformationAction Continue
    
    # Display duplicate app names in console
    if ($duplicateGroups.Count -gt 0) {
        foreach ($duplicate in $duplicateGroups) {
            Write-Information "  • $($duplicate.OriginalNames) ($($duplicate.DuplicateType))" -InformationAction Continue
        }
    }
    
    # ============================================================================
    # GENERATE REPORTS
    # ============================================================================
    
    # Generate timestamp for file names
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $csvPath = Join-Path $OutputPath "Intune_Duplicate_Applications_Report_$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "Intune_Duplicate_Applications_Report_$timestamp.html"
    
    # Prepare detailed CSV data
    $csvData = @()
    foreach ($duplicate in $duplicateGroups) {
        foreach ($app in $duplicate.Applications) {
            $csvData += [PSCustomObject]@{
                DuplicateGroup       = $duplicate.NormalizedName
                DuplicateType        = $duplicate.DuplicateType
                ApplicationName      = $app.ApplicationName
                ApplicationId        = $app.ApplicationId
                Publisher            = $app.Publisher
                AppType              = $app.AppType
                Description          = $app.Description
                CreatedDateTime      = $app.CreatedDateTime
                LastModifiedDateTime = $app.LastModifiedDateTime
                GroupAppCount        = $duplicate.AppCount
            }
        }
    }
    
    # Export to CSV
    try {
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to save CSV report: $($_.Exception.Message)"
    }
    
    # Generate HTML report
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Intune Duplicate Applications Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #d32f2f; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .summary-item { text-align: center; padding: 10px; background-color: #f8f9fa; border-radius: 4px; }
        .summary-number { font-size: 24px; font-weight: bold; color: #d32f2f; }
        .duplicate-group { background-color: white; margin-bottom: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }
        .duplicate-header { background-color: #ffebee; padding: 15px; border-bottom: 1px solid #e1e5e9; }
        .duplicate-title { font-size: 18px; font-weight: bold; color: #d32f2f; margin-bottom: 5px; }
        .duplicate-meta { color: #666; font-size: 14px; }
        .duplicate-details { padding: 15px; }
        table { width: 100%; border-collapse: collapse; }
        th { background-color: #f5f5f5; padding: 8px; text-align: left; font-weight: 600; border-bottom: 1px solid #ddd; }
        td { padding: 8px; border-bottom: 1px solid #eee; }
        tr:nth-child(even) { background-color: #fafafa; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: bold; }
        .badge-version { background-color: #e3f2fd; color: #1976d2; }
        .badge-publisher { background-color: #f3e5f5; color: #7b1fa2; }
        .badge-name { background-color: #e8f5e8; color: #388e3c; }
        .badge-fuzzy { background-color: #fff3e0; color: #f57c00; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
        .no-duplicates { text-align: center; padding: 40px; color: #4caf50; font-size: 18px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Intune Duplicate Applications Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-number">$($duplicateGroups.Count)</div>
                <div>Duplicate Groups Found</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$(($duplicateGroups | Measure-Object AppCount -Sum).Sum)</div>
                <div>Total Duplicate Apps</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$($intuneApps.Count)</div>
                <div>Total Intune Apps Scanned</div>
            </div>
        </div>
    </div>
"@

        if ($duplicateGroups.Count -eq 0) {
            $htmlContent += @"
    <div class="no-duplicates">
        <h2>🎉 No Duplicate Applications Found!</h2>
        <p>Your environment appears to be clean of duplicate applications based on the current criteria.</p>
    </div>
"@
        }
        else {
            $htmlContent += "<h2>Duplicate Application Groups</h2>"
            
            foreach ($duplicate in $duplicateGroups) {
                $badgeClass = switch -Regex ($duplicate.DuplicateType) {
                    "Multiple Publishers" { "badge-publisher" }
                    "Name Variations" { "badge-name" }
                    "Multiple App Types" { "badge-version" }
                    default { "badge-publisher" }
                }
                
                $htmlContent += @"
    <div class="duplicate-group">
        <div class="duplicate-header">
            <div class="duplicate-title">$($duplicate.OriginalNames)</div>
            <div class="duplicate-meta">
                <span class="badge $badgeClass">$($duplicate.DuplicateType)</span>
                • $($duplicate.AppCount) duplicate apps
            </div>
        </div>
        <div class="duplicate-details">
            <p><strong>Publishers:</strong> $($duplicate.Publishers)</p>
            <p><strong>App Types:</strong> $($duplicate.AppTypes)</p>
        </div>
    </div>
"@
            }
        }

        $htmlContent += @"
    <div class="footer">
        <p>Report generated by Intune Automation Script</p>
        <p>Detection criteria: Name variations, Multiple publishers, Multiple app types</p>
    </div>
</body>
</html>
"@

        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Information "✓ HTML report saved: $htmlPath" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to generate HTML report: $($_.Exception.Message)"
    }
    
    Write-Information "✓ Duplicate applications analysis completed successfully" -InformationAction Continue
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
        Write-Verbose "Graph disconnect completed (connection may have already been closed)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Duplicate Applications Report Summary
========================================
Total Intune Apps Scanned: $($intuneApps.Count)
Total Applications Processed: $totalApplications
Duplicate Groups Found: $($duplicateGroups.Count)
Reports Generated: CSV and HTML
Output Directory: $OutputPath
========================================
" -InformationAction Continue 