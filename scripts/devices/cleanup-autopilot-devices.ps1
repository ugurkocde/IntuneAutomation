<#
.TITLE
    Cleanup Orphaned Autopilot Devices

.SYNOPSIS
    Remove devices from Autopilot that are no longer managed in Intune

.DESCRIPTION
    This script connects to Microsoft Graph and identifies Windows Autopilot devices that are
    registered in the Autopilot service but are no longer present as managed devices in Intune.
    These orphaned devices can accumulate over time when devices are retired, reimaged, or
    replaced without proper cleanup of the Autopilot registration.

    The script provides options to preview orphaned devices before removal and supports
    batch operations with confirmation prompts for safety. It helps maintain a clean
    Autopilot device inventory and prevents potential enrollment issues.

.TAGS
    Operational,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementServiceConfig.ReadWrite.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Treat 0001-01-01 last contact as Never, require -Force for removals in Azure Automation, suppress progress bars in runbooks, and limit Graph list calls with select
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\cleanup-autopilot-devices.ps1 -PreviewOnly "true"
    Shows orphaned Autopilot devices without removing them

.EXAMPLE
    .\cleanup-autopilot-devices.ps1 -RemoveOrphaned "true" -ExportPath "C:\Reports\removed-autopilot-devices.csv"
    Removes orphaned devices and exports the list to CSV

.EXAMPLE
    .\cleanup-autopilot-devices.ps1 -RemoveOrphaned "true" -Force "true" -ShowProgressBar "true"
    Removes orphaned devices without confirmation prompts, with progress display

.EXAMPLE
    .\cleanup-autopilot-devices.ps1 -PreviewOnly "true" -ForceModuleInstall "true"
    Shows orphaned devices and forces module installation without prompting

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses Connect-MgGraph and Invoke-MgGraphRequest for all Graph operations
    - Only processes Windows Autopilot devices
    - Comparison is based on device serial numbers
    - Use -PreviewOnly first to review devices before removal
    - Large environments may take several minutes to process
    - Consider running during maintenance windows
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Only preview orphaned devices without removing them")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$PreviewOnly,

    [Parameter(Mandatory = $false, HelpMessage = "Remove orphaned Autopilot devices")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$RemoveOrphaned,

    [Parameter(Mandatory = $false, HelpMessage = "Skip confirmation prompts when removing devices")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV file path")]
    [string]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "Show progress bar during processing")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ShowProgressBar,

    [Parameter(Mandatory = $false, HelpMessage = "Include additional device details in output")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeDetails,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
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
foreach ($runbookBooleanParameter in @('PreviewOnly', 'RemoveOrphaned', 'Force', 'ShowProgressBar', 'IncludeDetails')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)

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
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

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
        # Azure Automation - Use Managed Identity
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        # Local execution - WAM-free interactive sign-in via MgGraphCommunity
        Write-Output "Connecting to Microsoft Graph with interactive authentication..."
        $Scopes = @(
            "DeviceManagementServiceConfig.ReadWrite.All",
            "DeviceManagementManagedDevices.Read.All"
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
            throw "Error fetching data from $NextLink : $($_.Exception.Message)"
        }
    } while ($NextLink)

    return $AllResults
}

# Function to get all Autopilot devices
function Get-AutopilotDevice {
    try {
        Write-Information "Retrieving Autopilot devices..." -InformationAction Continue
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
        $AutopilotDevices = Get-MgGraphAllPage -Uri $Uri
        Write-Information "✓ Retrieved $($AutopilotDevices.Count) Autopilot devices" -InformationAction Continue
        return $AutopilotDevices
    }
    catch {
        throw "Failed to retrieve Autopilot devices: $($_.Exception.Message)"
    }
}

# Function to get all Intune managed devices
function Get-IntuneDevice {
    try {
        Write-Information "Retrieving Intune managed devices..." -InformationAction Continue
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=id,serialNumber"
        $IntuneDevices = Get-MgGraphAllPage -Uri $Uri
        Write-Information "✓ Retrieved $($IntuneDevices.Count) Windows managed devices" -InformationAction Continue
        return $IntuneDevices
    }
    catch {
        throw "Failed to retrieve Intune managed devices: $($_.Exception.Message)"
    }
}

# Function to find orphaned Autopilot devices
function Find-OrphanedAutopilotDevice {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AutopilotDevices,
        [Parameter(Mandatory = $true)]
        [array]$IntuneDevices
    )

    Write-Information "Analyzing devices to find orphaned Autopilot registrations..." -InformationAction Continue

    # Create hashtable of Intune device serial numbers for fast lookup
    $IntuneSerialNumbers = @{}
    foreach ($Device in $IntuneDevices) {
        if (-not [string]::IsNullOrEmpty($Device.serialNumber)) {
            $IntuneSerialNumbers[$Device.serialNumber.ToUpper()] = $true
        }
    }

    $OrphanedDevices = @()
    $ProcessedCount = 0

    foreach ($AutopilotDevice in $AutopilotDevices) {
        $ProcessedCount++

        if ($ShowProgressBar -and -not $IsAzureAutomation) {
            $PercentComplete = [math]::Round(($ProcessedCount / $AutopilotDevices.Count) * 100)
            Write-Progress -Activity "Analyzing Autopilot devices" -Status "Processing device $ProcessedCount of $($AutopilotDevices.Count)" -PercentComplete $PercentComplete
        }

        # Check if Autopilot device serial number exists in Intune
        $SerialNumber = $AutopilotDevice.serialNumber
        if (-not [string]::IsNullOrEmpty($SerialNumber) -and -not $IntuneSerialNumbers.ContainsKey($SerialNumber.ToUpper())) {
            $OrphanedDevices += $AutopilotDevice
        }
    }

    if ($ShowProgressBar -and -not $IsAzureAutomation) {
        Write-Progress -Activity "Analyzing Autopilot devices" -Completed
    }

    Write-Information "✓ Found $($OrphanedDevices.Count) orphaned Autopilot devices" -InformationAction Continue
    return $OrphanedDevices
}

# Function to format Autopilot device information
function Format-AutopilotDeviceInfo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails
    )

    $DeviceInfo = [PSCustomObject]@{
        SerialNumber          = $Device.serialNumber
        Model                 = $Device.model
        Manufacturer          = $Device.manufacturer
        ProductKey            = $Device.productKey
        GroupTag              = $Device.groupTag
        PurchaseOrderId       = $Device.purchaseOrderIdentifier
        EnrollmentState       = $Device.enrollmentState
        LastContactedDateTime = if ($Device.lastContactedDateTime -and $Device.lastContactedDateTime -ne "0001-01-01T00:00:00Z") {
            ([DateTime]::Parse($Device.lastContactedDateTime)).ToString("yyyy-MM-dd HH:mm:ss")
        }
        else {
            "Never"
        }
        Id                    = $Device.id
    }

    if (-not $IncludeDetails) {
        $DeviceInfo = $DeviceInfo | Select-Object SerialNumber, Model, Manufacturer, GroupTag, EnrollmentState, LastContactedDateTime
    }

    return $DeviceInfo
}

# Function to remove Autopilot device
function Remove-AutopilotDevice {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber
    )

    # Create a meaningful identifier for logging
    $DeviceIdentifier = if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
        "Serial: $SerialNumber"
    }
    else {
        "ID: $DeviceId"
    }

    if ($PSCmdlet.ShouldProcess($DeviceIdentifier, "Remove Autopilot Device")) {
        try {
            $Uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$DeviceId"
            Invoke-MgGraphRequest -Uri $Uri -Method DELETE
            Write-Information "✓ Removed Autopilot device: $DeviceIdentifier" -InformationAction Continue
            return $true
        }
        catch {
            Write-Warning "✗ Failed to remove Autopilot device '$DeviceIdentifier': $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-Information "Skipped removal of Autopilot device: $DeviceIdentifier" -InformationAction Continue
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    # Validate parameters
    if (-not $PreviewOnly -and -not $RemoveOrphaned) {
        Write-Warning "No action specified. Use -PreviewOnly to preview orphaned devices or -RemoveOrphaned to remove them."
        Write-Output "Use 'Get-Help .\cleanup-autopilot-devices.ps1 -Examples' for usage examples."
        exit 0
    }

    if ($RemoveOrphaned -and $PreviewOnly) {
        Write-Warning "Cannot use both -PreviewOnly and -RemoveOrphaned switches. Choose one action."
        exit 1
    }

    Write-Output "Starting Autopilot device cleanup..."
    Write-Output "Configuration:"
    Write-Output "  - Mode: $(if ($PreviewOnly) { 'Preview Only' } else { 'Remove Orphaned Devices' })"
    Write-Output "  - Force removal: $($Force)"
    Write-Output "  - Include details: $($IncludeDetails)"

    # Get all Autopilot devices
    $AutopilotDevices = Get-AutopilotDevice
    if ($AutopilotDevices.Count -eq 0) {
        Write-Output "No Autopilot devices found. Exiting."
        exit 0
    }

    # Get all Intune managed devices
    $IntuneDevices = Get-IntuneDevice

    # Find orphaned Autopilot devices
    $OrphanedDevices = Find-OrphanedAutopilotDevice -AutopilotDevices $AutopilotDevices -IntuneDevices $IntuneDevices

    # Display results
    Write-Output ""
    Write-Output "========================================"
    Write-Output "AUTOPILOT CLEANUP REPORT"
    Write-Output "========================================"
    Write-Output "Total Autopilot devices: $($AutopilotDevices.Count)"
    Write-Output "Total Intune Windows devices: $($IntuneDevices.Count)"
    Write-Output "Orphaned Autopilot devices: $($OrphanedDevices.Count)"
    Write-Output "========================================"
    Write-Output ""

    if ($OrphanedDevices.Count -gt 0) {
        # Format device information for display
        $FormattedDevices = @()
        foreach ($Device in $OrphanedDevices) {
            $FormattedDevices += Format-AutopilotDeviceInfo -Device $Device -IncludeDetails:$IncludeDetails
        }

        # Display orphaned devices
        Write-Output "Orphaned Autopilot devices found:"
        $FormattedDevices | Sort-Object SerialNumber | Format-Table -AutoSize

        # Export to CSV if path specified
        if ($ExportPath) {
            try {
                $FormattedDevices | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
                Write-Output "✓ Results exported to: $ExportPath"
            }
            catch {
                Write-Warning "Failed to export to CSV: $($_.Exception.Message)"
            }
        }

        # Remove orphaned devices if requested
        if ($RemoveOrphaned) {
            Write-Output ""

            if ($IsAzureAutomation -and -not $Force) {
                Write-Error "Removing devices in Azure Automation requires the -Force parameter. No devices were removed."
                exit 1
            }

            if (-not $Force -and -not $IsAzureAutomation) {
                $Confirmation = Read-Host "Do you want to remove $($OrphanedDevices.Count) orphaned Autopilot devices? (y/N)"
                if ($Confirmation -notmatch '^[Yy]') {
                    Write-Output "Operation cancelled by user."
                    exit 0
                }
            }

            Write-Output "Removing orphaned Autopilot devices..."
            $RemovedCount = 0
            $FailedCount = 0
            $ProcessedCount = 0

            foreach ($Device in $OrphanedDevices) {
                $ProcessedCount++

                if ($ShowProgressBar -and -not $IsAzureAutomation) {
                    $PercentComplete = [math]::Round(($ProcessedCount / $OrphanedDevices.Count) * 100)
                    Write-Progress -Activity "Removing Autopilot devices" -Status "Processing device $ProcessedCount of $($OrphanedDevices.Count)" -PercentComplete $PercentComplete
                }

                $Success = Remove-AutopilotDevice -DeviceId $Device.id -SerialNumber $Device.serialNumber
                if ($Success) {
                    $RemovedCount++
                }
                else {
                    $FailedCount++
                }

                # Add small delay to avoid rate limiting
                Start-Sleep -Milliseconds 200
            }

            if ($ShowProgressBar -and -not $IsAzureAutomation) {
                Write-Progress -Activity "Removing Autopilot devices" -Completed
            }

            Write-Output ""
            Write-Output "✓ Removal completed"
            Write-Output "  - Successfully removed: $RemovedCount devices"
            Write-Output "  - Failed to remove: $FailedCount devices"
        }
    }
    else {
        Write-Output "No orphaned Autopilot devices found. All Autopilot devices have corresponding Intune managed devices."
    }

    Write-Output "✓ Script completed successfully"
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    try {
        Disconnect-MgGraph | Out-Null
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        # Ignore disconnection errors - this is expected behavior when already disconnected
        Write-Verbose "Graph disconnection completed (may have already been disconnected)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

$SummaryMode = if ($PreviewOnly) { "Preview" } else { "Cleanup" }
$SummaryDevices = if ($OrphanedDevices) { $OrphanedDevices.Count } else { 0 }

Write-Output "
========================================
Script Execution Summary
========================================
Script: Cleanup Orphaned Autopilot Devices
Mode: $SummaryMode
Autopilot Devices: $($AutopilotDevices.Count)
Orphaned Devices Found: $SummaryDevices
Status: Completed
========================================
"
