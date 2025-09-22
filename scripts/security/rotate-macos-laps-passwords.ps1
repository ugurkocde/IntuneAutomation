<#
.TITLE
    Rotate macOS LAPS Passwords

.SYNOPSIS
    Rotates Local Administrator Password Solution (LAPS) passwords for macOS devices in Intune using Graph API.

.DESCRIPTION
    This script connects to Intune via Microsoft Graph API and rotates the LAPS passwords for managed macOS devices.
    The script retrieves all macOS devices from Intune and triggers LAPS password rotation for each device.
    It provides real-time feedback on the rotation process, handles errors gracefully, and generates detailed reports.
    The script supports filtering by device groups, individual devices, or processing all macOS devices.

.TAGS
    Security,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-09-22

.EXAMPLE
    .\rotate-macos-laps-passwords.ps1
    Rotates LAPS passwords for all macOS devices in Intune

.EXAMPLE
    .\rotate-macos-laps-passwords.ps1 -DeviceName "MacBook-001"
    Rotates LAPS password for a specific device

.EXAMPLE
    .\rotate-macos-laps-passwords.ps1 -DelaySeconds 5 -ExportReport
    Rotates LAPS passwords with a 5-second delay between operations and exports results

.EXAMPLE
    .\rotate-macos-laps-passwords.ps1 -TestMode -DeviceLimit 5
    Runs in test mode, processing only 5 devices without actual rotation

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - LAPS must be configured and enabled for macOS devices in Intune
    - The rotation is triggered immediately but may take time to complete on the device
    - Personal devices cannot have their LAPS passwords rotated
    - The new password will be available in Intune after successful rotation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specific device name to rotate LAPS password")]
    [string]$DeviceName,

    [Parameter(Mandatory = $false, HelpMessage = "Specific device ID to rotate LAPS password")]
    [string]$DeviceId,

    [Parameter(Mandatory = $false, HelpMessage = "Delay in seconds between LAPS rotation operations")]
    [int]$DelaySeconds = 2,

    [Parameter(Mandatory = $false, HelpMessage = "Export rotation results to CSV")]
    [switch]$ExportReport,

    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Test mode - show what would be rotated without making changes")]
    [switch]$TestMode,

    [Parameter(Mandatory = $false, HelpMessage = "Limit number of devices to process (useful for testing)")]
    [int]$DeviceLimit = 0,

    [Parameter(Mandatory = $false, HelpMessage = "Show progress during processing")]
    [switch]$ShowProgress,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall,

    [Parameter(Mandatory = $false, HelpMessage = "Skip confirmation prompt before rotation")]
    [switch]$Force
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
$RequiredModuleList = @(
    "Microsoft.Graph.Authentication"
)

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
        # Local execution - Use interactive authentication
        Write-Information "Connecting to Microsoft Graph with interactive authentication..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.ReadWrite.All",
            "DeviceManagementConfiguration.Read.All"
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

    return $AllResult
}

# Function to rotate LAPS password for a device
function Invoke-LAPSPasswordRotation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,
        [string]$OwnerType = "unknown",
        [bool]$TestMode = $false
    )

    $result = [PSCustomObject]@{
        DeviceName = $DeviceName
        DeviceId = $DeviceId
        OwnerType = $OwnerType
        Status = "Pending"
        Message = ""
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    # Check if device is personal
    if ($OwnerType -eq "personal") {
        $result.Status = "Skipped"
        $result.Message = "Personal device - LAPS rotation not supported"
        return $result
    }

    if ($TestMode) {
        $result.Status = "Test Mode"
        $result.Message = "Would rotate LAPS password (test mode)"
        return $result
    }

    try {
        # Construct the URI for LAPS password rotation
        $rotateUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/rotateLocalAdminPassword"

        # Send POST request to rotate LAPS password
        $response = Invoke-MgGraphRequest -Uri $rotateUri -Method POST

        $result.Status = "Success"
        $result.Message = "LAPS password rotation initiated successfully"
    }
    catch {
        $errorMessage = $_.Exception.Message

        # Handle specific error cases
        if ($errorMessage -like "*404*" -or $errorMessage -like "*Not Found*") {
            $result.Status = "Failed"
            $result.Message = "Device not found or LAPS not configured"
        }
        elseif ($errorMessage -like "*403*" -or $errorMessage -like "*Forbidden*") {
            $result.Status = "Failed"
            $result.Message = "Access denied - insufficient permissions"
        }
        elseif ($errorMessage -like "*BadRequest*" -or $errorMessage -like "*400*") {
            $result.Status = "Failed"
            $result.Message = "LAPS rotation not supported for this device"
        }
        else {
            $result.Status = "Error"
            $result.Message = $errorMessage
        }
    }

    return $result
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting macOS LAPS password rotation..." -InformationAction Continue

    # Validate output path if export is requested
    if ($ExportReport) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-Information "Created output directory: $OutputPath" -InformationAction Continue
        }
    }

    # Build filter for retrieving devices
    $filter = "operatingSystem eq 'macOS'"

    # Get devices based on parameters
    if ($DeviceId) {
        Write-Information "Retrieving device with ID: $DeviceId" -InformationAction Continue
        $deviceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')"
        try {
            $device = Invoke-MgGraphRequest -Uri $deviceUri -Method GET
            $devices = @($device)
        }
        catch {
            Write-Error "Failed to retrieve device with ID '$DeviceId': $_"
            exit 1
        }
    }
    elseif ($DeviceName) {
        Write-Information "Retrieving device: $DeviceName" -InformationAction Continue
        $deviceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=$filter and deviceName eq '$DeviceName'"
        $devices = Get-MgGraphPaginatedData -Uri $deviceUri

        if ($devices.Count -eq 0) {
            Write-Error "Device '$DeviceName' not found"
            exit 1
        }
    }
    else {
        Write-Information "Retrieving all macOS devices from Intune..." -InformationAction Continue
        $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=$filter"
        $devices = Get-MgGraphPaginatedData -Uri $devicesUri
    }

    if ($devices.Count -eq 0) {
        Write-Warning "No macOS devices found"
        return
    }

    # Apply device limit if specified
    if ($DeviceLimit -gt 0 -and $devices.Count -gt $DeviceLimit) {
        Write-Information "Limiting processing to $DeviceLimit devices (out of $($devices.Count) total)" -InformationAction Continue
        $devices = $devices | Select-Object -First $DeviceLimit
    }

    Write-Information "Found $($devices.Count) macOS device(s) to process" -InformationAction Continue

    # Show test mode warning
    if ($TestMode) {
        Write-Warning "RUNNING IN TEST MODE - No actual LAPS passwords will be rotated"
    }

    # Confirmation prompt unless Force is specified
    if (-not $Force -and -not $TestMode) {
        Write-Information "`nYou are about to rotate LAPS passwords for $($devices.Count) device(s)." -InformationAction Continue
        $confirmation = Read-Host "Do you want to continue? (Y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Information "Operation cancelled by user" -InformationAction Continue
            return
        }
    }

    # Process devices
    $results = @()
    $processedCount = 0
    $successCount = 0
    $failedCount = 0
    $skippedCount = 0

    foreach ($device in $devices) {
        $processedCount++

        if ($ShowProgress) {
            $percentComplete = [math]::Round(($processedCount / $devices.Count) * 100, 1)
            Write-Progress -Activity "Rotating LAPS Passwords" -Status "Processing: $($device.deviceName)" -PercentComplete $percentComplete
        }

        Write-Information "[$processedCount/$($devices.Count)] Processing: $($device.deviceName)" -InformationAction Continue

        # Rotate LAPS password
        $rotationResult = Invoke-LAPSPasswordRotation -DeviceId $device.id -DeviceName $device.deviceName -OwnerType $device.ownerType -TestMode $TestMode

        # Update counters
        switch ($rotationResult.Status) {
            "Success" { $successCount++ }
            "Failed" { $failedCount++ }
            "Error" { $failedCount++ }
            "Skipped" { $skippedCount++ }
            "Test Mode" { $successCount++ }
        }

        # Display result
        $statusSymbol = switch ($rotationResult.Status) {
            "Success" { "✓" }
            "Failed" { "✗" }
            "Error" { "✗" }
            "Skipped" { "⊘" }
            "Test Mode" { "ℹ" }
            default { "-" }
        }

        Write-Information "  $statusSymbol Status: $($rotationResult.Status) - $($rotationResult.Message)" -InformationAction Continue

        # Add additional device information to result
        $rotationResult | Add-Member -MemberType NoteProperty -Name "SerialNumber" -Value $device.serialNumber
        $rotationResult | Add-Member -MemberType NoteProperty -Name "OSVersion" -Value $device.osVersion
        $rotationResult | Add-Member -MemberType NoteProperty -Name "LastSyncDateTime" -Value $device.lastSyncDateTime
        $rotationResult | Add-Member -MemberType NoteProperty -Name "ComplianceState" -Value $device.complianceState

        $results += $rotationResult

        # Add delay between operations (except for last device)
        if ($processedCount -lt $devices.Count -and $DelaySeconds -gt 0) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    if ($ShowProgress) {
        Write-Progress -Activity "Rotating LAPS Passwords" -Completed
    }

    # Display summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "LAPS Password Rotation Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total devices processed: $processedCount" -InformationAction Continue
    Write-Information "Successful rotations: $successCount" -InformationAction Continue
    Write-Information "Failed rotations: $failedCount" -InformationAction Continue
    Write-Information "Skipped devices: $skippedCount" -InformationAction Continue
    if ($TestMode) {
        Write-Information "Mode: TEST MODE (no actual changes made)" -InformationAction Continue
    }
    Write-Information "========================================" -InformationAction Continue

    # Export results if requested
    if ($ExportReport) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvPath = Join-Path $OutputPath "LAPS-Rotation-Report-$timestamp.csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Information "✓ Results exported to: $csvPath" -InformationAction Continue

        # Also export failed devices separately if any
        if ($failedCount -gt 0) {
            $failedPath = Join-Path $OutputPath "LAPS-Rotation-Failed-$timestamp.csv"
            $results | Where-Object { $_.Status -in @("Failed", "Error") } | Export-Csv -Path $failedPath -NoTypeInformation
            Write-Information "✓ Failed devices exported to: $failedPath" -InformationAction Continue
        }
    }

    # Show failed devices if any
    if ($failedCount -gt 0) {
        Write-Information "`nFailed devices:" -InformationAction Continue
        $results | Where-Object { $_.Status -in @("Failed", "Error") } |
            Select-Object DeviceName, Status, Message |
            Format-Table -AutoSize
    }

    Write-Information "✓ LAPS password rotation completed" -InformationAction Continue
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
        Write-Verbose "Unable to disconnect from Microsoft Graph: $($_.Exception.Message)"
    }
}