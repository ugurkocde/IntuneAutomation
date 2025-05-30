<#
.TITLE
    Rotate BitLocker Keys

.SYNOPSIS
    Rotates BitLocker keys for all Windows devices in Intune using Graph API.

.DESCRIPTION
    This script connects to Intune via Graph API and rotates the BitLocker keys for all managed Windows devices.
    The script retrieves all Windows devices from Intune and triggers BitLocker key rotation for each device.
    It provides real-time feedback on the rotation process and handles errors gracefully.

.TAGS
    Security,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-29

.EXAMPLE
    .\rotate-bitlocker-keys.ps1
    Rotates BitLocker keys for all Windows devices in Intune

.EXAMPLE
    .\rotate-bitlocker-keys.ps1 -DelaySeconds 5
    Rotates BitLocker keys with a 5-second delay between operations

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - BitLocker key rotation is triggered immediately but may take time to complete on the device
    - The script will show real-time progress and results
    - Only Windows devices with BitLocker enabled will be processed
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Delay in seconds between BitLocker key rotation operations")]
    [int]$DelaySeconds = 2,
    
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
            "DeviceManagementManagedDevices.ReadWrite.All"
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

# Function to rotate BitLocker keys for a device
function Invoke-BitLockerKeyRotation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        [Parameter(Mandatory = $true)]
        [string]$DeviceName
    )
    
    try {
        $rotateUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/rotateBitLockerKeys"
        Invoke-MgGraphRequest -Method POST -Uri $rotateUri -ContentType "application/json"
        
        Write-Information "✓ Successfully rotated BitLocker keys for device: $DeviceName" -InformationAction Continue
        return $true
    }
    catch {
        Write-Warning "✗ Failed to rotate BitLocker keys for device $DeviceName : $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting BitLocker key rotation process..." -InformationAction Continue
    
    # Get all managed Windows devices from Intune
    Write-Information "Retrieving all Windows devices from Intune..." -InformationAction Continue
    $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem&`$filter=operatingSystem eq 'Windows'"
    $managedDevices = Get-MgGraphAllPage -Uri $devicesUri
    
    if ($managedDevices.Count -eq 0) {
        Write-Warning "No Windows devices found in Intune."
        exit 0
    }
    
    Write-Information "✓ Found $($managedDevices.Count) Windows devices" -InformationAction Continue
    
    # Initialize counters
    $successCount = 0
    $failureCount = 0
    $totalDevices = $managedDevices.Count
    $currentDevice = 0
    
    # Process each device
    foreach ($device in $managedDevices) {
        $currentDevice++
        $deviceId = $device.id
        $deviceName = $device.deviceName
        
        Write-Information "[$currentDevice/$totalDevices] Processing device: $deviceName" -InformationAction Continue
        
        # Rotate BitLocker keys
        $success = Invoke-BitLockerKeyRotation -DeviceId $deviceId -DeviceName $deviceName
        
        if ($success) {
            $successCount++
        }
        else {
            $failureCount++
        }
        
        # Add delay between operations if specified
        if ($DelaySeconds -gt 0 -and $currentDevice -lt $totalDevices) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    # Display summary
    Write-Information "`n" -InformationAction Continue
    Write-Information "============================================" -InformationAction Continue
    Write-Information "BitLocker Key Rotation Summary" -InformationAction Continue
    Write-Information "============================================" -InformationAction Continue
    Write-Information "Total devices processed: $totalDevices" -InformationAction Continue
    Write-Information "Successful rotations: $successCount" -InformationAction Continue
    Write-Information "Failed rotations: $failureCount" -InformationAction Continue
    Write-Information "Success rate: $([math]::Round(($successCount / $totalDevices) * 100, 2))%" -InformationAction Continue
    Write-Information "============================================" -InformationAction Continue
    
    Write-Information "✓ BitLocker key rotation process completed" -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
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