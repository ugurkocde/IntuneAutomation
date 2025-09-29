<#
.TITLE
    Restart Devices

.SYNOPSIS
    Trigger remote restart operations on specific managed devices in Intune or devices in an Entra ID group.

.DESCRIPTION
    This script connects to Microsoft Graph and triggers remote restart operations on targeted devices.
    You can target devices by specific names, device IDs, or by Entra ID group membership.
    The script provides real-time feedback on restart operations and handles errors gracefully.
    All operations include confirmation prompts to prevent accidental restarts.

.TAGS
    Operational,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.PrivilegedOperations.All,DeviceManagementManagedDevices.Read.All,Group.Read.All,GroupMember.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-09-29

.EXAMPLE
    .\restart-devices.ps1 -DeviceNames "LAPTOP001","DESKTOP002"
    Restarts specific devices by name

.EXAMPLE
    .\restart-devices.ps1 -DeviceIds "12345678-1234-1234-1234-123456789012","87654321-4321-4321-4321-210987654321"
    Restarts specific devices by their Intune device IDs

.EXAMPLE
    .\restart-devices.ps1 -EntraGroupName "IT Department Devices"
    Restarts all devices belonging to users in the specified Entra ID group

.EXAMPLE
    .\restart-devices.ps1 -DeviceNames "LAPTOP001" -Force
    Restarts a specific device without confirmation prompt

.NOTES
    - Supports both local execution and Azure Automation Runbook environments
    - Automatically detects execution environment and uses appropriate authentication method
    - Local execution: Uses interactive authentication with specified scopes
    - Azure Automation: Uses Managed Identity authentication
    - Requires Microsoft.Graph.Authentication module (auto-installs if missing in local environment)
    - Use -ForceModuleInstall to skip installation prompts in local environment
    - Requires appropriate permissions in Azure AD
    - Restart operations are triggered immediately but may take 5-30 minutes to execute
    - Devices will restart within 5 minutes when users are logged in
    - Confirmation prompts are shown unless -Force parameter is used
    - Use with caution as this will interrupt user work
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
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [int]$RestartDelaySeconds = 2,

    [Parameter(Mandatory = $false, HelpMessage = 'Force module installation without prompting')]
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
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
                    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }

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
    Write-Output 'Running inside Azure Automation Runbook'
    $IsAzureAutomation = $true
}
else {
    Write-Information 'Running locally in IDE or terminal' -InformationAction Continue
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModules = @(
    'Microsoft.Graph.Authentication'
)

try {
    Initialize-RequiredModule -ModuleNames $RequiredModules -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
    Write-Verbose '✓ All required modules are available'
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
        Write-Output 'Connecting to Microsoft Graph using Managed Identity...'
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
        Write-Output '✓ Successfully connected to Microsoft Graph using Managed Identity'
    }
    else {
        # Local execution - Use interactive authentication
        Write-Information 'Connecting to Microsoft Graph with interactive authentication...' -InformationAction Continue

        $scopes = @('DeviceManagementManagedDevices.PrivilegedOperations.All', 'DeviceManagementManagedDevices.Read.All')

        if ($PSCmdlet.ParameterSetName -eq 'EntraGroup') {
            $scopes += @('Group.Read.All', 'GroupMember.Read.All')
        }
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
        Write-Information '✓ Successfully connected to Microsoft Graph' -InformationAction Continue
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

    [System.Collections.Generic.List[PSCustomObject]]$allResults = @()
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
                $response.value | ForEach-Object {
                    $allResults.Add($_)
                }
            }
            else {
                $allResults.Add($response)
            }

            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like '*429*' -or $_.Exception.Message -like '*throttled*') {
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

# Function to trigger device restart
function Invoke-DeviceRestart {
    param(
        [string]$DeviceId,
        [string]$DeviceName
    )

    try {
        $restartUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$DeviceId')/rebootNow"
        Invoke-MgGraphRequest -Uri $restartUri -Method POST
        Write-Information "✓ Restart triggered successfully for device: $DeviceName" -InformationAction Continue
        return $true
    }
    catch {
        Write-Information "✗ Failed to restart device $DeviceName : $($_.Exception.Message)" -InformationAction Continue
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
        $groups = @(Get-MgGraphAllPage -Uri $groupUri)

        if ($groups.Count -eq 0) {
            throw "Group '$GroupName' not found"
        }
        elseif ($groups.Count -gt 1) {
            throw "Multiple groups found with name '$GroupName'. Please use a more specific name."
        }

        $group = $groups[0]
        Write-Information "✓ Found group: $($group.displayName) (ID: $($group.id))" -InformationAction Continue

        # Get group members
        Write-Information 'Retrieving group members...' -InformationAction Continue
        $membersUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members"
        $members = @(Get-MgGraphAllPage -Uri $membersUri)

        Write-Information "✓ Found $($members.Count) members in group" -InformationAction Continue

        # Get all managed devices
        Write-Information 'Retrieving managed devices...' -InformationAction Continue
        $devicesUri = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices'
        $allDevices = @(Get-MgGraphAllPage -Uri $devicesUri)

        # Filter devices by group members
        [System.Collections.Generic.List[PSCustomObject]]$targetDevices = @()
        foreach ($device in $allDevices) {
            if ($device.id) {
                # Test if device.id is in members
                $deviceInGroup = $members.deviceID.contains($device.azureADDeviceId)
                if ($deviceInGroup) {
                    $targetDevices.Add($device)
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

# Function to display device information
function Show-DeviceDetail {
    param([array]$Devices)

    Write-Information "`nDEVICE DETAILS" -InformationAction Continue
    Write-Information "===============" -InformationAction Continue

    foreach ($device in $Devices) {
        $lastSeen = if ($device.lastSyncDateTime) {
            [DateTime]$device.lastSyncDateTime
        }
        else {
            "Never"
        }

        Write-Information "Device: $($device.deviceName)" -InformationAction Continue
        Write-Information "  User: $($device.userPrincipalName)" -InformationAction Continue
        Write-Information "  OS: $($device.operatingSystem) $($device.osVersion)" -InformationAction Continue
        Write-Information "  Model: $($device.model)" -InformationAction Continue
        Write-Information "  Last Seen: $lastSeen" -InformationAction Continue
        Write-Information "  ID: $($device.id)" -InformationAction Continue
        Write-Information "" -InformationAction Continue
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
            Write-Information 'Retrieving devices by names...' -InformationAction Continue
            $devicesUri = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices'
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
            Write-Information 'Retrieving devices by IDs...' -InformationAction Continue
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
        Write-Warning 'No target devices found. Exiting.'
        $null = Disconnect-MgGraph
        exit 0
    }

    # Display target information
    Write-Information "`nDEVICE RESTART OPERATION" -InformationAction Continue
    Write-Information "=========================" -InformationAction Continue
    Write-Information "Total devices to restart: $($targetDevices.Count)" -InformationAction Continue
    Write-Information "Operation: Remote Restart" -InformationAction Continue

    # Show device details
    Show-DeviceDetail -Devices $targetDevices

    # Confirmation prompt unless Force is specified
    if (-not $Force -and -not $IsAzureAutomation) {
        Write-Information "`nCONFIRMATION REQUIRED" -InformationAction Continue
        Write-Information "This operation will restart $($targetDevices.Count) device(s)." -InformationAction Continue
        Write-Information "This will interrupt user work and should be coordinated with affected users." -InformationAction Continue

        $confirmation = Read-Host "`nType 'CONFIRM' to proceed with the restart operation"

        if ($confirmation -ne 'CONFIRM') {
            Write-Information "Operation cancelled by user." -InformationAction Continue
            $null = Disconnect-MgGraph
            exit 0
        }
    }

    # Process restart operations
    $successfulRestarts = 0
    $failedRestarts = 0
    $processedDevices = 0

    Write-Information "`nProcessing device restart operations..." -InformationAction Continue

    foreach ($device in $targetDevices) {
        $processedDevices++
        Write-Progress -Activity 'Restarting Devices' -Status "Processing device $processedDevices of $($targetDevices.Count): $($device.deviceName)" -PercentComplete (($processedDevices / $targetDevices.Count) * 100)

        $restartSuccessful = Invoke-DeviceRestart -DeviceId $device.id -DeviceName $device.deviceName

        if ($restartSuccessful) {
            $successfulRestarts++
        }
        else {
            $failedRestarts++
        }

        # Add delay between restart operations to avoid overwhelming the service
        if ($processedDevices -lt $targetDevices.Count) {
            Start-Sleep -Seconds $RestartDelaySeconds
        }
    }

    Write-Progress -Activity 'Restarting Devices' -Completed

    # Display final summary
    Write-Information "`nRESTART OPERATION SUMMARY" -InformationAction Continue
    Write-Information "=========================" -InformationAction Continue
    Write-Information "Total Devices Processed: $($targetDevices.Count)" -InformationAction Continue
    Write-Information "Successful Restarts: $successfulRestarts" -InformationAction Continue
    Write-Information "Failed Restarts: $failedRestarts" -InformationAction Continue

    # Show failed devices if any
    if ($failedRestarts -gt 0) {
        Write-Information "`nFailed restart operations require manual review." -InformationAction Continue
    }

    if ($successfulRestarts -gt 0) {
        Write-Information "`n$successfulRestarts device(s) have been scheduled for restart." -InformationAction Continue
        Write-Information "Note: Devices will restart within 5-30 minutes depending on sync status." -InformationAction Continue
    }

    Write-Information "`nDevice restart operation completed successfully!" -InformationAction Continue

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    try {
        $null = Disconnect-MgGraph
        Write-Information '✓ Disconnected from Microsoft Graph' -InformationAction Continue
    }
    catch {
        # Ignore disconnection errors - this is expected behavior when already disconnected
        Write-Verbose 'Graph disconnection completed (may have already been disconnected)'
    }
}