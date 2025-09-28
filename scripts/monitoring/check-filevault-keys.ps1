<#
.TITLE
    FileVault Key Storage Checker

.SYNOPSIS
    Monitor and verify that FileVault recovery keys for macOS devices are properly stored in Intune.

.DESCRIPTION
    This script connects to Microsoft Graph API, retrieves all macOS devices from Intune,
    and checks if each device has FileVault recovery keys stored in Intune. The script
    provides detailed reporting on compliance status, identifies devices without stored keys,
    and exports comprehensive results to CSV format for further analysis. This helps ensure
    proper FileVault key escrow for data recovery scenarios.

.TAGS
    Monitoring,Security

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-09-22

.EXAMPLE
    .\check-filevault-keys.ps1
    Generates FileVault key storage report for all macOS devices in Intune

.EXAMPLE
    .\check-filevault-keys.ps1 -OutputPath "C:\Reports" -OnlyShowMissing
    Saves report to specified directory and shows only devices missing FileVault keys

.EXAMPLE
    .\check-filevault-keys.ps1 -IncludeLastSync -ExportJson
    Includes last sync information and exports results in JSON format as well

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - FileVault keys are automatically escrowed to Intune when properly configured
    - Devices must be enrolled in Intune and have FileVault policy applied
    - Consider configuring FileVault policies to enforce key escrow
    - Regular monitoring helps ensure compliance with data protection requirements
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Only show devices missing FileVault keys")]
    [switch]$OnlyShowMissing,

    [Parameter(Mandatory = $false, HelpMessage = "Include last sync date information")]
    [switch]$IncludeLastSync,

    [Parameter(Mandatory = $false, HelpMessage = "Export results in JSON format as well")]
    [switch]$ExportJson,

    [Parameter(Mandatory = $false, HelpMessage = "Show progress during processing")]
    [switch]$ShowProgress,

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
            "DeviceManagementManagedDevices.Read.All",
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

# Function to check FileVault key availability for a device
function Test-FileVaultKeyAvailability {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName = "Unknown",
        [Parameter(Mandatory = $false)]
        [string]$OwnerType = "unknown"
    )

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        Write-Verbose "Device $DeviceName has no Device ID"
        return @{
            HasKey   = $false
            KeyAvailable = $false
            Status   = "No Device ID"
            ErrorDetails = $null
        }
    }

    try {
        # Use the getFileVaultKey endpoint
        $keyUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/getFileVaultKey"
        $keyResponse = Invoke-MgGraphRequest -Uri $keyUri -Method GET

        # Check if response contains a recovery key
        if ($keyResponse -and $keyResponse.value) {
            return @{
                HasKey   = $true
                KeyAvailable = $true
                Status   = "Key Available"
                ErrorDetails = $null
            }
        }
        else {
            return @{
                HasKey   = $false
                KeyAvailable = $false
                Status   = "No Key Found"
                ErrorDetails = $null
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message

        # Handle specific error cases
        if ($errorMessage -like "*404*" -or $errorMessage -like "*Not Found*") {
            return @{
                HasKey   = $false
                KeyAvailable = $false
                Status   = "No Key Stored"
                ErrorDetails = "FileVault key not found in Intune"
            }
        }
        elseif ($errorMessage -like "*403*" -or $errorMessage -like "*Forbidden*") {
            return @{
                HasKey   = $false
                KeyAvailable = $false
                Status   = "Access Denied"
                ErrorDetails = "Insufficient permissions"
            }
        }
        elseif ($errorMessage -like "*BadRequest*" -or $errorMessage -like "*400*") {
            # BadRequest typically indicates personal device or unsupported operation
            if ($OwnerType -eq "personal") {
                return @{
                    HasKey   = $false
                    KeyAvailable = $false
                    Status   = "Personal Device"
                    ErrorDetails = "FileVault keys not accessible for personal devices"
                }
            }
            else {
                return @{
                    HasKey   = $false
                    KeyAvailable = $false
                    Status   = "Not Supported"
                    ErrorDetails = "FileVault key retrieval not supported for this device"
                }
            }
        }
        elseif ($errorMessage -like "*Personal*") {
            return @{
                HasKey   = $false
                KeyAvailable = $false
                Status   = "Personal Device"
                ErrorDetails = "Cannot retrieve key for personal device"
            }
        }
        else {
            Write-Verbose "Error checking FileVault key for device $DeviceName : $errorMessage"
            return @{
                HasKey   = $false
                KeyAvailable = $false
                Status   = "Error Checking"
                ErrorDetails = $errorMessage
            }
        }
    }
}

# Function to format device last sync date
function Format-LastSyncDate {
    param([datetime]$LastSyncDateTime)

    if ($LastSyncDateTime -eq [datetime]::MinValue) {
        return "Never"
    }

    $daysSinceSync = (Get-Date) - $LastSyncDateTime

    if ($daysSinceSync.TotalDays -lt 1) {
        return "Today"
    }
    elseif ($daysSinceSync.TotalDays -lt 2) {
        return "Yesterday"
    }
    else {
        return "$([math]::Round($daysSinceSync.TotalDays)) days ago"
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting FileVault key storage check..." -InformationAction Continue

    # Validate output path
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Information "Created output directory: $OutputPath" -InformationAction Continue
    }

    # Get all macOS devices from Intune
    Write-Information "Retrieving macOS devices from Intune..." -InformationAction Continue
    $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'macOS'"
    $devices = Get-MgGraphPaginatedData -Uri $devicesUri

    if ($devices.Count -eq 0) {
        Write-Warning "No macOS devices found in Intune"
        return
    }

    Write-Information "Found $($devices.Count) macOS devices. Checking FileVault key status..." -InformationAction Continue

    $results = @()
    $processedCount = 0

    foreach ($device in $devices) {
        $processedCount++

        if ($ShowProgress) {
            $percentComplete = [math]::Round(($processedCount / $devices.Count) * 100, 1)
            Write-Progress -Activity "Checking FileVault Keys" -Status "Processing device: $($device.deviceName)" -PercentComplete $percentComplete
        }

        # Check FileVault key availability
        $filevaultCheck = Test-FileVaultKeyAvailability -DeviceId $device.id -DeviceName $device.deviceName -OwnerType $device.ownerType

        # Prepare result object
        $deviceResult = [PSCustomObject]@{
            DeviceName                  = $device.deviceName
            SerialNumber                = $device.serialNumber
            Model                       = $device.model
            Manufacturer                = $device.manufacturer
            OSVersion                   = $device.osVersion
            DeviceId                    = $device.id
            "FileVault Key in Intune"   = if ($filevaultCheck.HasKey) { "Yes" } else { "No" }
            Status                      = $filevaultCheck.Status
            ComplianceState             = $device.complianceState
            EncryptionState             = $device.isEncrypted
            ManagementState             = $device.managementState
            OwnerType                   = $device.ownerType
        }

        # Add error details if present
        if ($filevaultCheck.ErrorDetails) {
            $deviceResult | Add-Member -MemberType NoteProperty -Name "Error Details" -Value $filevaultCheck.ErrorDetails
        }

        # Add last sync information if requested
        if ($IncludeLastSync) {
            $deviceResult | Add-Member -MemberType NoteProperty -Name "Last Sync" -Value $device.lastSyncDateTime.ToString("yyyy-MM-dd HH:mm")
            $deviceResult | Add-Member -MemberType NoteProperty -Name "Sync Status" -Value (Format-LastSyncDate -LastSyncDateTime $device.lastSyncDateTime)
        }

        # Add to results (filter if only showing missing keys)
        if (-not $OnlyShowMissing -or -not $filevaultCheck.HasKey) {
            $results += $deviceResult
        }
    }

    if ($ShowProgress) {
        Write-Progress -Activity "Checking FileVault Keys" -Completed
    }

    # Display results
    Write-Information "`nFileVault Key Storage Results:" -InformationAction Continue
    $results | Format-Table -AutoSize

    # Calculate and display summary statistics
    $totalDevices = $devices.Count
    $devicesWithKeys = ($results | Where-Object { $_."FileVault Key in Intune" -eq "Yes" }).Count
    $devicesWithoutKeys = ($results | Where-Object { $_."FileVault Key in Intune" -eq "No" }).Count
    $personalDevices = ($results | Where-Object { $_.Status -eq "Personal Device" }).Count
    $errorDevices = ($results | Where-Object { $_.Status -eq "Error Checking" }).Count

    if ($totalDevices -gt 0) {
        $compliancePercentage = [math]::Round(($devicesWithKeys / $totalDevices) * 100, 1)
    }
    else {
        $compliancePercentage = 0
    }

    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "FileVault Key Storage Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total macOS devices in Intune: $totalDevices" -InformationAction Continue
    Write-Information "Devices with FileVault keys in Intune: $devicesWithKeys" -InformationAction Continue
    Write-Information "Devices without FileVault keys: $devicesWithoutKeys" -InformationAction Continue
    if ($personalDevices -gt 0) {
        Write-Information "Personal devices (keys not accessible): $personalDevices" -InformationAction Continue
    }
    if ($errorDevices -gt 0) {
        Write-Information "Devices with errors: $errorDevices" -InformationAction Continue
    }
    Write-Information "Compliance percentage: $compliancePercentage%" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue

    # Export results to CSV
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $OutputPath "FileVault-Key-Storage-Report-$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
    Write-Information "✓ Results exported to: $csvPath" -InformationAction Continue

    # Export to JSON if requested
    if ($ExportJson) {
        $jsonPath = Join-Path $OutputPath "FileVault-Key-Storage-Report-$timestamp.json"
        $jsonData = @{
            GeneratedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Summary       = @{
                TotalDevices         = $totalDevices
                DevicesWithKeys      = $devicesWithKeys
                DevicesWithoutKeys   = $devicesWithoutKeys
                PersonalDevices      = $personalDevices
                ErrorDevices         = $errorDevices
                CompliancePercentage = $compliancePercentage
            }
            Devices       = $results
        }
        $jsonData | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath
        Write-Information "✓ Results exported to JSON: $jsonPath" -InformationAction Continue
    }

    # Show devices without keys if any exist and not in OnlyShowMissing mode
    if ($devicesWithoutKeys -gt 0 -and -not $OnlyShowMissing) {
        Write-Information "`nDevices without FileVault keys in Intune:" -InformationAction Continue
        $devicesWithoutKeysList = $results | Where-Object { $_."FileVault Key in Intune" -eq "No" } | Select-Object DeviceName, SerialNumber, Status, OwnerType
        $devicesWithoutKeysList | Format-Table -AutoSize
    }

    Write-Information "✓ FileVault key storage check completed successfully" -InformationAction Continue
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

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Script Execution Summary
========================================
Script: FileVault Key Storage Checker
Total Devices Processed: $($devices.Count)
Devices with Keys: $devicesWithKeys
Compliance Rate: $compliancePercentage%
Report Location: $OutputPath
Status: Completed
========================================
" -InformationAction Continue