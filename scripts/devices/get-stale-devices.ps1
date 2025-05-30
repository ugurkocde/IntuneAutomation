<#
.TITLE
    Get Stale Intune Devices

.SYNOPSIS
    Identifies and reports on devices that haven't checked in to Intune within a specified timeframe

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all managed devices from Intune,
    then identifies devices that are considered "stale" based on their last check-in date.
    The script supports all device platforms (Windows, iOS, Android, macOS) and provides
    comprehensive reporting with options to export results to CSV format.
    
    Stale devices may indicate hardware that is no longer in use, devices that have been
    reimaged without proper cleanup, or devices experiencing connectivity issues.

.TAGS
    Operational,Devices

.MINROLE
    Intune Service Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-29

.EXAMPLE
    .\get-stale-devices.ps1 -DaysStale 30
    Gets all devices that haven't checked in for 30 days or more

.EXAMPLE
    .\get-stale-devices.ps1 -DaysStale 60 -Platform "Windows" -ExportPath "C:\Reports\stale-windows-devices.csv"
    Gets Windows devices that haven't checked in for 60 days and exports to CSV

.EXAMPLE
    .\get-stale-devices.ps1 -DaysStale 90 -IncludeNeverCheckedIn -ShowProgressBar
    Gets devices stale for 90+ days, includes devices that never checked in, with progress display

.EXAMPLE
    .\get-stale-devices.ps1 -DaysStale 30 -ForceModuleInstall
    Gets stale devices and forces module installation without prompting

.NOTES
    - Requires only Microsoft.Graph.Authentication module
    - Uses Connect-MgGraph and Invoke-MgGraphRequest for all Graph operations
    - Large environments may take several minutes to process
    - Consider running during off-hours for large tenant scans
    - Devices that have never checked in will show 'Never' as last check-in time
    - Corporate-owned devices vs personal devices are distinguished in the output
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Number of days since last check-in to consider a device stale")]
    [ValidateRange(1, 1000)]
    [int]$DaysStale,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by specific platform (Windows, iOS, Android, macOS)")]
    [ValidateSet("Windows", "iOS", "Android", "macOS", "All")]
    [string]$Platform = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Include devices that have never checked in")]
    [switch]$IncludeNeverCheckedIn,
    
    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV file path")]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false, HelpMessage = "Show progress bar during processing")]
    [switch]$ShowProgressBar,
    
    [Parameter(Mandatory = $false, HelpMessage = "Include additional device details in output")]
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
            "DeviceManagementManagedDevices.Read.All"
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
function Get-MgGraphAllResult {
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

# Function to determine if a device is stale
function Test-DeviceStale {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,
        [Parameter(Mandatory = $true)]
        [int]$DaysStale,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeNeverCheckedIn
    )
    
    $LastCheckIn = $Device.lastSyncDateTime
    $IsStale = $false
    
    if ([string]::IsNullOrEmpty($LastCheckIn) -or $LastCheckIn -eq "0001-01-01T00:00:00Z") {
        # Device has never checked in
        $IsStale = $IncludeNeverCheckedIn.IsPresent
    }
    else {
        $LastCheckInDate = [DateTime]::Parse($LastCheckIn)
        $DaysSinceLastCheckIn = (Get-Date) - $LastCheckInDate
        $IsStale = $DaysSinceLastCheckIn.Days -ge $DaysStale
    }
    
    return $IsStale
}

# Function to format device information
function Format-DeviceInfo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails
    )
    
    $LastCheckIn = $Device.lastSyncDateTime
    $FormattedLastCheckIn = if ([string]::IsNullOrEmpty($LastCheckIn) -or $LastCheckIn -eq "0001-01-01T00:00:00Z") {
        "Never"
    }
    else {
        ([DateTime]::Parse($LastCheckIn)).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    $DaysSinceCheckIn = if ($FormattedLastCheckIn -eq "Never") {
        "N/A"
    }
    else {
        [math]::Floor(((Get-Date) - [DateTime]::Parse($LastCheckIn)).TotalDays)
    }
    
    $DeviceInfo = [PSCustomObject]@{
        DeviceName       = $Device.deviceName
        Platform         = $Device.operatingSystem
        OSVersion        = $Device.osVersion
        LastCheckIn      = $FormattedLastCheckIn
        DaysSinceCheckIn = $DaysSinceCheckIn
        DeviceId         = $Device.id
        SerialNumber     = $Device.serialNumber
        Model            = $Device.model
        Manufacturer     = $Device.manufacturer
        EnrollmentType   = $Device.deviceEnrollmentType
        Ownership        = $Device.managedDeviceOwnerType
        ComplianceState  = $Device.complianceState
        ManagementState  = $Device.managementState
    }
    
    if (-not $IncludeDetails) {
        $DeviceInfo = $DeviceInfo | Select-Object DeviceName, Platform, OSVersion, LastCheckIn, DaysSinceCheckIn, Ownership, ComplianceState
    }
    
    return $DeviceInfo
}

# Function to get platform-specific OData filter
function Get-PlatformFilter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Platform
    )
    
    switch ($Platform) {
        "Windows" { return "operatingSystem eq 'Windows'" }
        "iOS" { return "operatingSystem eq 'iOS'" }
        "Android" { return "operatingSystem eq 'Android'" }
        "macOS" { return "operatingSystem eq 'macOS'" }
        "All" { return $null }
        default { return $null }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting stale device detection..." -InformationAction Continue
    Write-Information "Configuration:" -InformationAction Continue
    Write-Information "  - Days considered stale: $DaysStale" -InformationAction Continue
    Write-Information "  - Platform filter: $Platform" -InformationAction Continue
    Write-Information "  - Include never checked in: $($IncludeNeverCheckedIn.IsPresent)" -InformationAction Continue
    
    # Build the API URI with optional platform filter
    $BaseUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    $PlatformFilter = Get-PlatformFilter -Platform $Platform
    
    if ($PlatformFilter) {
        $Uri = "$BaseUri?`$filter=$PlatformFilter"
        Write-Information "  - Applying platform filter: $PlatformFilter" -InformationAction Continue
    }
    else {
        $Uri = $BaseUri
    }
    
    # Retrieve all managed devices
    Write-Information "Retrieving managed devices from Intune..." -InformationAction Continue
    $AllDevices = Get-MgGraphAllResult -Uri $Uri
    Write-Information "✓ Retrieved $($AllDevices.Count) devices" -InformationAction Continue
    
    # Process devices to find stale ones
    Write-Information "Analyzing devices for staleness..." -InformationAction Continue
    $StaleDevices = @()
    $ProcessedCount = 0
    
    foreach ($Device in $AllDevices) {
        $ProcessedCount++
        
        if ($ShowProgressBar) {
            $PercentComplete = [math]::Round(($ProcessedCount / $AllDevices.Count) * 100)
            Write-Progress -Activity "Analyzing devices" -Status "Processing device $ProcessedCount of $($AllDevices.Count)" -PercentComplete $PercentComplete
        }
        
        if (Test-DeviceStale -Device $Device -DaysStale $DaysStale -IncludeNeverCheckedIn:$IncludeNeverCheckedIn) {
            $FormattedDevice = Format-DeviceInfo -Device $Device -IncludeDetails:$IncludeDetails
            $StaleDevices += $FormattedDevice
        }
    }
    
    if ($ShowProgressBar) {
        Write-Progress -Activity "Analyzing devices" -Completed
    }
    
    # Display results
    Write-Information "✓ Analysis completed" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "STALE DEVICE REPORT" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total devices analyzed: $($AllDevices.Count)" -InformationAction Continue
    Write-Information "Stale devices found: $($StaleDevices.Count)" -InformationAction Continue
    Write-Information "Staleness threshold: $DaysStale days" -InformationAction Continue
    Write-Information "Platform filter: $Platform" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    
    if ($StaleDevices.Count -gt 0) {
        # Group by platform for summary
        $PlatformSummary = $StaleDevices | Group-Object Platform | Sort-Object Name
        Write-Information "Stale devices by platform:" -InformationAction Continue
        foreach ($Group in $PlatformSummary) {
            Write-Information "  - $($Group.Name): $($Group.Count) devices" -InformationAction Continue
        }
        Write-Information "" -InformationAction Continue
        
        # Display the stale devices
        $StaleDevices | Sort-Object Platform, DeviceName | Format-Table -AutoSize
        
        # Export to CSV if path specified
        if ($ExportPath) {
            try {
                $StaleDevices | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Information "✓ Results exported to: $ExportPath" -InformationAction Continue
            }
            catch {
                Write-Warning "Failed to export to CSV: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Information "No stale devices found matching the specified criteria." -InformationAction Continue
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
        # Ignore disconnection errors - this is expected behavior when already disconnected
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
Script: Get Stale Intune Devices
Parameters: DaysStale=$DaysStale, Platform=$Platform
Devices Analyzed: $($AllDevices.Count)
Stale Devices Found: $($StaleDevices.Count)
Status: Completed
========================================
" -InformationAction Continue 