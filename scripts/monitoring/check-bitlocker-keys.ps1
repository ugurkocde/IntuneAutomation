<#
.TITLE
    BitLocker Key Storage Checker

.SYNOPSIS
    Monitor and verify that BitLocker recovery keys for Windows devices are properly stored in Entra ID.

.DESCRIPTION
    This script connects to Microsoft Graph API, retrieves all Windows devices from Intune,
    and checks if each device has BitLocker recovery keys stored in Entra ID. The script
    provides detailed reporting on compliance status, identifies devices without stored keys,
    and exports comprehensive results to CSV format for further analysis. This helps ensure
    proper BitLocker key escrow for data recovery scenarios.

.TAGS
    Monitoring,Security

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,BitlockerKey.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-29

.EXAMPLE
    .\check-bitlocker-keys.ps1
    Generates BitLocker key storage report for all Windows devices in Intune

.EXAMPLE
    .\check-bitlocker-keys.ps1 -OutputPath "C:\Reports" -OnlyShowMissing
    Saves report to specified directory and shows only devices missing BitLocker keys

.EXAMPLE
    .\check-bitlocker-keys.ps1 -IncludeLastSync -ExportJson
    Includes last sync information and exports results in JSON format as well

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - BitLocker keys are automatically escrowed to Entra ID when properly configured
    - Devices must be Azure AD joined or Hybrid Azure AD joined for key escrow
    - Consider configuring BitLocker policies to enforce key escrow
    - Regular monitoring helps ensure compliance with data protection requirements
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false, HelpMessage = "Only show devices missing BitLocker keys")]
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
            "BitlockerKey.Read.All"
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

# Function to check BitLocker key availability for a device
function Test-BitLockerKeyAvailability {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AzureADDeviceId,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName = "Unknown"
    )

    if ([string]::IsNullOrWhiteSpace($AzureADDeviceId)) {
        Write-Verbose "Device $DeviceName has no Azure AD Device ID"
        return @{
            HasKey   = $false
            KeyCount = 0
            Status   = "No Azure AD Device ID"
        }
    }

    try {
        $keyIdUri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$AzureADDeviceId'"
        $keyIdResponse = Invoke-MgGraphRequest -Uri $keyIdUri -Method GET

        $keyCount = $keyIdResponse.value.Count
        $hasKey = $keyCount -gt 0

        return @{
            HasKey   = $hasKey
            KeyCount = $keyCount
            Status   = if ($hasKey) { "Key Available" } else { "No Key Found" }
        }
    }
    catch {
        Write-Warning "Error checking BitLocker key for device $DeviceName : $($_.Exception.Message)"
        return @{
            HasKey   = $false
            KeyCount = 0
            Status   = "Error Checking"
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
    Write-Information "Starting BitLocker key storage check..." -InformationAction Continue
    
    # Validate output path
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Information "Created output directory: $OutputPath" -InformationAction Continue
    }
    
    # Get all Windows devices from Intune
    Write-Information "Retrieving Windows devices from Intune..." -InformationAction Continue
    $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'"
    $devices = Get-MgGraphPaginatedData -Uri $devicesUri
    
    if ($devices.Count -eq 0) {
        Write-Warning "No Windows devices found in Intune"
        return
    }
    
    Write-Information "Found $($devices.Count) Windows devices. Checking BitLocker key status..." -InformationAction Continue
    
    $results = @()
    $processedCount = 0
    
    foreach ($device in $devices) {
        $processedCount++
        
        if ($ShowProgress) {
            $percentComplete = [math]::Round(($processedCount / $devices.Count) * 100, 1)
            Write-Progress -Activity "Checking BitLocker Keys" -Status "Processing device: $($device.deviceName)" -PercentComplete $percentComplete
        }
        
        # Check BitLocker key availability
        $bitlockerCheck = Test-BitLockerKeyAvailability -AzureADDeviceId $device.azureADDeviceId -DeviceName $device.deviceName
        
        # Prepare result object
        $deviceResult = [PSCustomObject]@{
            DeviceName                  = $device.deviceName
            SerialNumber                = $device.serialNumber
            Model                       = $device.model
            Manufacturer                = $device.manufacturer
            OSVersion                   = $device.osVersion
            AzureADDeviceId             = $device.azureADDeviceId
            "BitLocker Key in Entra ID" = if ($bitlockerCheck.HasKey) { "Yes" } else { "No" }
            "Key Count"                 = $bitlockerCheck.KeyCount
            Status                      = $bitlockerCheck.Status
            ComplianceState             = $device.complianceState
            EncryptionState             = $device.encryptionState
        }
        
        # Add last sync information if requested
        if ($IncludeLastSync) {
            $deviceResult | Add-Member -MemberType NoteProperty -Name "Last Sync" -Value $device.lastSyncDateTime.ToString("yyyy-MM-dd HH:mm")
            $deviceResult | Add-Member -MemberType NoteProperty -Name "Sync Status" -Value (Format-LastSyncDate -LastSyncDateTime $device.lastSyncDateTime)
        }
        
        # Add to results (filter if only showing missing keys)
        if (-not $OnlyShowMissing -or -not $bitlockerCheck.HasKey) {
            $results += $deviceResult
        }
    }
    
    if ($ShowProgress) {
        Write-Progress -Activity "Checking BitLocker Keys" -Completed
    }
    
    # Display results
    Write-Information "`nBitLocker Key Storage Results:" -InformationAction Continue
    $results | Format-Table -AutoSize
    
    # Calculate and display summary statistics
    $totalDevices = $devices.Count
    $devicesWithKeys = ($devices | ForEach-Object { 
            $check = Test-BitLockerKeyAvailability -AzureADDeviceId $_.azureADDeviceId
            $check.HasKey 
        } | Where-Object { $_ -eq $true }).Count
    $devicesWithoutKeys = $totalDevices - $devicesWithKeys
    $compliancePercentage = [math]::Round(($devicesWithKeys / $totalDevices) * 100, 1)
    
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "BitLocker Key Storage Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Total Windows devices in Intune: $totalDevices" -InformationAction Continue
    Write-Information "Devices with BitLocker keys in Entra ID: $devicesWithKeys" -InformationAction Continue  
    Write-Information "Devices without BitLocker keys: $devicesWithoutKeys" -InformationAction Continue
    Write-Information "Compliance percentage: $compliancePercentage%" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    
    # Export results to CSV
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $OutputPath "BitLocker-Key-Storage-Report-$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Information "✓ Results exported to: $csvPath" -InformationAction Continue
    
    # Export to JSON if requested
    if ($ExportJson) {
        $jsonPath = Join-Path $OutputPath "BitLocker-Key-Storage-Report-$timestamp.json"
        $jsonData = @{
            GeneratedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Summary       = @{
                TotalDevices         = $totalDevices
                DevicesWithKeys      = $devicesWithKeys
                DevicesWithoutKeys   = $devicesWithoutKeys
                CompliancePercentage = $compliancePercentage
            }
            Devices       = $results
        }
        $jsonData | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath
        Write-Information "✓ Results exported to JSON: $jsonPath" -InformationAction Continue
    }
    
    # Show devices without keys if any exist and not in OnlyShowMissing mode
    if ($devicesWithoutKeys -gt 0 -and -not $OnlyShowMissing) {
        Write-Information "`nDevices without BitLocker keys in Entra ID:" -InformationAction Continue
        $devicesWithoutKeysList = $results | Where-Object { $_."BitLocker Key in Entra ID" -eq "No" } | Select-Object DeviceName, SerialNumber, Status
        $devicesWithoutKeysList | Format-Table -AutoSize
    }
    
    Write-Information "✓ BitLocker key storage check completed successfully" -InformationAction Continue
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
Script: BitLocker Key Storage Checker
Total Devices Processed: $($devices.Count)
Devices with Keys: $devicesWithKeys
Compliance Rate: $compliancePercentage%
Report Location: $OutputPath
Status: Completed
========================================
" -InformationAction Continue 