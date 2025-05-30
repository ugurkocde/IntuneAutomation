<#
.TITLE
    Sync Devices

.SYNOPSIS
    Trigger synchronization on specific managed devices in Intune or devices in an Entra ID group.

.DESCRIPTION
    This script connects to Microsoft Graph and triggers synchronization operations on targeted devices.
    You can target devices by specific names, device IDs, or by Entra ID group membership.
    The script provides real-time feedback on sync operations and handles errors gracefully.

.TAGS
    Operational,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementManagedDevices.Read.All,Group.Read.All,GroupMember.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-05-29

.EXAMPLE
    .\sync-devices.ps1 -DeviceNames "LAPTOP001","DESKTOP002"
    Synchronizes specific devices by name

.EXAMPLE
    .\sync-devices.ps1 -DeviceIds "12345678-1234-1234-1234-123456789012","87654321-4321-4321-4321-210987654321"
    Synchronizes specific devices by their Intune device IDs

.EXAMPLE
    .\sync-devices.ps1 -EntraGroupName "IT Department Devices"
    Synchronizes all devices belonging to users in the specified Entra ID group

.EXAMPLE
    .\sync-devices.ps1 -EntraGroupName "Sales Team" -ForceSync
    Forces synchronization of all devices for users in the Sales Team group

.NOTES
    - Supports both local execution and Azure Automation Runbook environments
    - Automatically detects execution environment and uses appropriate authentication method
    - Local execution: Uses interactive authentication with specified scopes
    - Azure Automation: Uses Managed Identity authentication
    - Requires Microsoft.Graph.Authentication module (auto-installs if missing in local environment)
    - Use -ForceModuleInstall to skip installation prompts in local environment
    - Requires appropriate permissions in Azure AD
    - Sync operations are triggered immediately but may take time to complete on the device
    - Use -ForceSync to override the 1-hour sync threshold
    - The script will show real-time progress and results
#>

[CmdletBinding(DefaultParameterSetName = 'DeviceNames')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'DeviceNames')]
    [string[]]$DeviceNames,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'DeviceIds')]
    [string[]]$DeviceIds,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'EntraGroup')]
    [string]$EntraGroupName,
    
    [Parameter(Mandatory = $false)]
    [switch]$ForceSync,
    
    [Parameter(Mandatory = $false)]
    [int]$SyncDelaySeconds = 2,
    
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
        $scopes = @("DeviceManagementManagedDevices.ReadWrite.All", "DeviceManagementManagedDevices.Read.All")
        if ($PSCmdlet.ParameterSetName -eq 'EntraGroup') {
            $scopes += @("Group.Read.All", "GroupMember.Read.All")
        }
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
        Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
    }
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# Function to get all pages of results
function Get-MgGraphAllPage {
    param(
        [string]$Uri,
        [int]$DelayMs = 100
    )
    
    $allResults = @()
    $nextLink = $Uri
    $requestCount = 0
    
    do {
        try {
            # Add delay to respect rate limits
            if ($requestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
            
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            $requestCount++
            
            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }
            
            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $nextLink : $($_.Exception.Message)"
            break
        }
    } while ($nextLink)
    
    return $allResults
}

# Function to trigger device sync
function Invoke-DeviceSync {
    param(
        [string]$DeviceId,
        [string]$DeviceName
    )
    
    try {
        $syncUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$DeviceId')/syncDevice"
        Invoke-MgGraphRequest -Uri $syncUri -Method POST
        Write-Information "✓ Sync triggered successfully for device: $DeviceName" -InformationAction Continue
        return $true
    }
    catch {
        Write-Information "✗ Failed to sync device $DeviceName : $($_.Exception.Message)" -InformationAction Continue
        return $false
    }
}

# Function to get devices by Entra ID group
function Get-DevicesByEntraGroup {
    param([string]$GroupName)
    
    try {
        Write-Information "Finding Entra ID group: $GroupName..." -InformationAction Continue
        
        # Find the group
        $groupUri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'"
        $groups = Get-MgGraphAllPage -Uri $groupUri
        
        if ($groups.Count -eq 0) {
            throw "Group '$GroupName' not found"
        }
        elseif ($groups.Count -gt 1) {
            throw "Multiple groups found with name '$GroupName'. Please use a more specific name."
        }
        
        $group = $groups[0]
        Write-Information "✓ Found group: $($group.displayName) (ID: $($group.id))" -InformationAction Continue
        
        # Get group members
        Write-Information "Retrieving group members..." -InformationAction Continue
        $membersUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members"
        $members = Get-MgGraphAllPage -Uri $membersUri
        
        Write-Information "✓ Found $($members.Count) members in group" -InformationAction Continue
        
        # Get all managed devices
        Write-Information "Retrieving managed devices..." -InformationAction Continue
        $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        $allDevices = Get-MgGraphAllPage -Uri $devicesUri
        
        # Filter devices by group members
        $targetDevices = @()
        foreach ($device in $allDevices) {
            if ($device.userPrincipalName) {
                $userInGroup = $members | Where-Object { $_.userPrincipalName -eq $device.userPrincipalName -or $_.mail -eq $device.userPrincipalName }
                if ($userInGroup) {
                    $targetDevices += $device
                }
            }
        }
        
        Write-Information "✓ Found $($targetDevices.Count) devices belonging to group members" -InformationAction Continue
        return $targetDevices
    }
    catch {
        Write-Error "Failed to get devices by Entra ID group: $($_.Exception.Message)"
        return @()
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    # Get target devices based on parameter set
    $targetDevices = @()

    switch ($PSCmdlet.ParameterSetName) {
        'DeviceNames' {
            Write-Information "Retrieving devices by names..." -InformationAction Continue
            $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
            $allDevices = Get-MgGraphAllPage -Uri $devicesUri
            
            foreach ($deviceName in $DeviceNames) {
                $matchingDevices = $allDevices | Where-Object { $_.deviceName -eq $deviceName }
                if ($matchingDevices) {
                    $targetDevices += $matchingDevices
                    Write-Information "✓ Found device: $deviceName" -InformationAction Continue
                }
                else {
                    Write-Warning "Device not found: $deviceName"
                }
            }
        }
        
        'DeviceIds' {
            Write-Information "Retrieving devices by IDs..." -InformationAction Continue
            foreach ($deviceId in $DeviceIds) {
                try {
                    $deviceUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId"
                    $device = Invoke-MgGraphRequest -Uri $deviceUri -Method GET
                    $targetDevices += $device
                    Write-Information "✓ Found device: $($device.deviceName)" -InformationAction Continue
                }
                catch {
                    Write-Warning "Device not found with ID: $deviceId"
                }
            }
        }
        
        'EntraGroup' {
            $targetDevices = Get-DevicesByEntraGroup -GroupName $EntraGroupName
        }
    }

    if ($targetDevices.Count -eq 0) {
        Write-Warning "No target devices found. Exiting."
        Disconnect-MgGraph | Out-Null
        exit 0
    }

    # Display target information
    Write-Information "`n📱 TARGET DEVICES SUMMARY" -InformationAction Continue
    Write-Information "=========================" -InformationAction Continue
    Write-Information "Total devices to process: $($targetDevices.Count)" -InformationAction Continue

    # Process sync operations
    $successfulSyncs = 0
    $failedSyncs = 0
    $skippedSyncs = 0
    $processedDevices = 0

    Write-Information "`nProcessing device synchronization..." -InformationAction Continue

    foreach ($device in $targetDevices) {
        $processedDevices++
        Write-Progress -Activity "Synchronizing Devices" -Status "Processing device $processedDevices of $($targetDevices.Count): $($device.deviceName)" -PercentComplete (($processedDevices / $targetDevices.Count) * 100)
        
        # Calculate time since last sync
        $hoursSinceSync = if ($device.lastSyncDateTime) {
            [math]::Round(((Get-Date) - [DateTime]$device.lastSyncDateTime).TotalHours, 1)
        }
        else {
            999
        }
        
        # Determine if sync should be triggered
        $shouldSync = $ForceSync -or $hoursSinceSync -gt 1 -or $null -eq $device.lastSyncDateTime
        
        if ($shouldSync) {
            $syncSuccessful = Invoke-DeviceSync -DeviceId $device.id -DeviceName $device.deviceName
            
            if ($syncSuccessful) {
                $successfulSyncs++
            }
            else {
                $failedSyncs++
            }
            
            # Add delay between sync operations to avoid overwhelming the service
            if ($processedDevices -lt $targetDevices.Count) {
                Start-Sleep -Seconds $SyncDelaySeconds
            }
        }
        else {
            Write-Information "⏭️  Skipping $($device.deviceName) - synced $hoursSinceSync hours ago" -InformationAction Continue
            $skippedSyncs++
        }
    }

    Write-Progress -Activity "Synchronizing Devices" -Completed

    # Display final summary
    Write-Information "`n🔄 SYNC OPERATION SUMMARY" -InformationAction Continue
    Write-Information "=========================" -InformationAction Continue
    Write-Information "Total Devices Processed: $($targetDevices.Count)" -InformationAction Continue
    Write-Information "Successful Syncs: $successfulSyncs" -InformationAction Continue
    Write-Information "Failed Syncs: $failedSyncs" -InformationAction Continue
    Write-Information "Skipped Devices: $skippedSyncs" -InformationAction Continue

    # Show failed devices if any
    if ($failedSyncs -gt 0) {
        Write-Information "`n❌ Failed sync operations require manual review." -InformationAction Continue
    }

    Write-Information "`n🎉 Device synchronization completed successfully!" -InformationAction Continue

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
