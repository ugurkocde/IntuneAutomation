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
    1.3

.CHANGELOG
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Added a confirmation prompt before tenant-wide rotation (skippable with -Force; Azure Automation runbooks now require -Force); rotation calls retry once after 60 seconds on throttling
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-28

.EXAMPLE
    .\rotate-bitlocker-keys.ps1
    Rotates BitLocker keys for all Windows devices in Intune

.EXAMPLE
    .\rotate-bitlocker-keys.ps1 -DelaySeconds 5
    Rotates BitLocker keys with a 5-second delay between operations

.EXAMPLE
    .\rotate-bitlocker-keys.ps1 -Force
    Rotates BitLocker keys without the confirmation prompt (required when running as an Azure Automation runbook)

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - Local runs prompt for confirmation before rotating unless -Force is specified; Azure Automation runbooks require -Force
    - BitLocker key rotation is triggered immediately but may take time to complete on the device
    - The script will show real-time progress and results
    - Only Windows devices with BitLocker enabled will be processed
    - Disclaimer: This script is provided AS IS without warranty of any kind. Use it at your own risk.
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Delay in seconds between BitLocker key rotation operations")]
    [int]$DelaySeconds = 2,
    
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
            "DeviceManagementManagedDevices.ReadWrite.All"
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
        # Retry once after throttling before treating the rotation as failed
        if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
            Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
            Start-Sleep -Seconds 60
            try {
                Invoke-MgGraphRequest -Method POST -Uri $rotateUri -ContentType "application/json"

                Write-Information "✓ Successfully rotated BitLocker keys for device: $DeviceName" -InformationAction Continue
                return $true
            }
            catch {
                Write-Warning "✗ Failed to rotate BitLocker keys for device $DeviceName : $($_.Exception.Message)"
                return $false
            }
        }
        Write-Warning "✗ Failed to rotate BitLocker keys for device $DeviceName : $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Starting BitLocker key rotation process..."
    
    # Get all managed Windows devices from Intune
    Write-Output "Retrieving all Windows devices from Intune..."
    $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem&`$filter=operatingSystem eq 'Windows'"
    $managedDevices = Get-MgGraphAllPage -Uri $devicesUri
    
    if ($managedDevices.Count -eq 0) {
        Write-Warning "No Windows devices found in Intune."
        exit 0
    }
    
    Write-Output "✓ Found $($managedDevices.Count) Windows devices"

    # Confirmation gate: local runs prompt unless -Force; Azure Automation
    # cannot prompt, so -Force is required there
    if (-not $Force) {
        if ($IsAzureAutomation) {
            Write-Error "Azure Automation runs cannot prompt for confirmation. Re-run with -Force to rotate BitLocker keys for $($managedDevices.Count) device(s)."
            exit 1
        }
        Write-Output "`nYou are about to rotate BitLocker keys for $($managedDevices.Count) device(s)."
        $confirmation = Read-Host "Do you want to continue? (Y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Output "Operation cancelled by user"
            exit 0
        }
    }

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
        
        Write-Output "[$currentDevice/$totalDevices] Processing device: $deviceName"
        
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
    Write-Output "`n"
    Write-Output "============================================"
    Write-Output "BitLocker Key Rotation Summary"
    Write-Output "============================================"
    Write-Output "Total devices processed: $totalDevices"
    Write-Output "Successful rotations: $successCount"
    Write-Output "Failed rotations: $failureCount"
    Write-Output "Success rate: $([math]::Round(($successCount / $totalDevices) * 100, 2))%"
    Write-Output "============================================"
    
    Write-Output "✓ BitLocker key rotation process completed"
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
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