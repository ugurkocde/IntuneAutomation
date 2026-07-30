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
    DeviceManagementManagedDevices.PrivilegedOperations.All,DeviceManagementManagedDevices.Read.All,GroupMember.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.6

.CHANGELOG
    1.6 - Ignore empty string-array values supplied by Azure Automation when validating the selected target
    1.5 - Added a portal-safe DryRun mode and records an empty target group as a successful no-op
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Added -WhatIf dry run support; exit code 1 when any restart fails; 429 retry with 60s wait on restart calls; group matching now falls back to userPrincipalName/mail so user-membership groups work; group lookup failures abort with a distinct error; added $select to managed device queries
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

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
    .\restart-devices.ps1 -DeviceNames "LAPTOP001" -Force "true"
    Restarts a specific device without confirmation prompt

.EXAMPLE
    .\restart-devices.ps1 -EntraGroupName "IT Department Devices" -DryRun "true"
    Lists the target devices without sending a restart action

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
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$DeviceNames,

    [Parameter(Mandatory = $false)]
    [string[]]$DeviceIds,

    [Parameter(Mandatory = $false)]
    [string]$EntraGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Preview target devices without restarting them")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$DryRun,

    [Parameter(Mandatory = $false)]
    [int]$RestartDelaySeconds = 2,

    [Parameter(Mandatory = $false, HelpMessage = 'Force module installation without prompting')]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
Remove-Variable -Name ForceModuleInstall
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
foreach ($runbookBooleanParameter in @('Force', 'DryRun')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)
    Remove-Variable -Name $runbookBooleanParameter

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

$DeviceNames = @($DeviceNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$DeviceIds = @($DeviceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

$selectedTargets = @(
    if ($DeviceNames.Count -gt 0) { 'DeviceNames' }
    if ($DeviceIds.Count -gt 0) { 'DeviceIds' }
    if (-not [string]::IsNullOrWhiteSpace($EntraGroupName)) { 'EntraGroup' }
)
if ($selectedTargets.Count -ne 1) {
    throw "Specify exactly one target: DeviceNames, DeviceIds, or EntraGroupName."
}
$TargetMode = $selectedTargets[0]

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
    Write-Output 'Running locally in IDE or terminal'
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModules = @(
    'Microsoft.Graph.Authentication'
)

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

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
        # Local execution - WAM-free interactive sign-in via MgGraphCommunity
        Write-Output 'Connecting to Microsoft Graph with interactive authentication...'

        $scopes = @('DeviceManagementManagedDevices.PrivilegedOperations.All', 'DeviceManagementManagedDevices.Read.All')

        if ($TargetMode -eq 'EntraGroup') {
            $scopes += 'GroupMember.Read.All'
        }
        Connect-MgGraphCommunity -Scopes $scopes -NoWelcome -ErrorAction Stop
        Write-Output '✓ Successfully connected to Microsoft Graph'
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

            if ($null -ne $response.value) {
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
            throw "Error fetching data from $nextLink : $($_.Exception.Message)"
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
        $restartUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/rebootNow"
        Invoke-MgGraphRequest -Uri $restartUri -Method POST
        Write-Information "✓ Restart triggered successfully for device: $DeviceName" -InformationAction Continue
        return $true
    }
    catch {
        if ($_.Exception.Message -like '*429*' -or $_.Exception.Message -like '*throttled*') {
            Write-Information "Rate limit hit for device $DeviceName, waiting 60 seconds before retry..." -InformationAction Continue
            Start-Sleep -Seconds 60
            try {
                Invoke-MgGraphRequest -Uri $restartUri -Method POST
                Write-Information "✓ Restart triggered successfully for device: $DeviceName" -InformationAction Continue
                return $true
            }
            catch {
                Write-Information "✗ Failed to restart device $DeviceName after retry: $($_.Exception.Message)" -InformationAction Continue
                return $false
            }
        }
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
        $groupUri = "https://graph.microsoft.com/beta/groups?`$filter=displayName eq '$GroupName'"
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
        $membersUri = "https://graph.microsoft.com/beta/groups/$($group.id)/members"
        $members = @(Get-MgGraphAllPage -Uri $membersUri)

        Write-Information "✓ Found $($members.Count) members in group" -InformationAction Continue

        # Get all managed devices
        Write-Information 'Retrieving managed devices...' -InformationAction Continue
        $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,osVersion,model,lastSyncDateTime"
        $allDevices = @(Get-MgGraphAllPage -Uri $devicesUri)

        # Filter devices by group members (device membership first, then user membership fallback)
        [System.Collections.Generic.List[PSCustomObject]]$targetDevices = @()
        foreach ($device in $allDevices) {
            $deviceInGroup = $false
            if ($device.azureADDeviceId -and $members.deviceId -contains $device.azureADDeviceId) {
                $deviceInGroup = $true
            }
            elseif ($device.userPrincipalName) {
                $userInGroup = $members | Where-Object { $_.userPrincipalName -eq $device.userPrincipalName -or $_.mail -eq $device.userPrincipalName }
                if ($userInGroup) {
                    $deviceInGroup = $true
                }
            }
            if ($deviceInGroup) {
                $targetDevices.Add($device)
            }
        }

        Write-Information "✓ Found $($targetDevices.Count) devices belonging to group members" -InformationAction Continue
        return $targetDevices
    }
    catch {
        throw "Failed to get devices by Entra ID group: $($_.Exception.Message)"
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

    switch ($TargetMode) {
        'DeviceNames' {
            Write-Output 'Retrieving devices by names...'
            $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,osVersion,model,lastSyncDateTime"
            $allDevices = Get-MgGraphAllPage -Uri $devicesUri

            foreach ($deviceName in $DeviceNames) {
                $matchingDevices = $allDevices | Where-Object { $_.deviceName -eq $deviceName }
                if ($matchingDevices) {
                    $targetDevices += $matchingDevices
                    Write-Output "✓ Found device: $deviceName"
                }
                else {
                    Write-Warning "Device not found: $deviceName"
                }
            }
        }

        'DeviceIds' {
            Write-Output 'Retrieving devices by IDs...'
            foreach ($deviceId in $DeviceIds) {
                try {
                    $deviceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId`?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,osVersion,model,lastSyncDateTime"
                    $device = Invoke-MgGraphRequest -Uri $deviceUri -Method GET
                    $targetDevices += $device
                    Write-Output "✓ Found device: $($device.deviceName)"
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
        Write-Output 'No target devices found. No restart action is required.'
        $null = Disconnect-MgGraph
        exit 0
    }

    # Display target information
    Write-Output "`nDEVICE RESTART OPERATION"
    Write-Output "========================="
    Write-Output "Total devices to restart: $($targetDevices.Count)"
    Write-Output "Operation: Remote Restart"

    # Show device details
    Show-DeviceDetail -Devices $targetDevices

    if ($DryRun) {
        Write-Output "✓ Dry run completed. No restart actions were sent."
        $null = Disconnect-MgGraph
        exit 0
    }

    # Confirmation prompt unless Force or WhatIf is specified
    if (-not $Force -and -not $IsAzureAutomation -and -not $WhatIfPreference) {
        Write-Output "`nCONFIRMATION REQUIRED"
        Write-Output "This operation will restart $($targetDevices.Count) device(s)."
        Write-Output "This will interrupt user work and should be coordinated with affected users."

        $confirmation = Read-Host "`nType 'CONFIRM' to proceed with the restart operation"

        if ($confirmation -ne 'CONFIRM') {
            Write-Output "Operation cancelled by user."
            $null = Disconnect-MgGraph
            exit 0
        }
    }

    # Process restart operations
    $successfulRestarts = 0
    $failedRestarts = 0
    $processedDevices = 0

    Write-Output "`nProcessing device restart operations..."

    foreach ($device in $targetDevices) {
        $processedDevices++
        Write-Progress -Activity 'Restarting Devices' -Status "Processing device $processedDevices of $($targetDevices.Count): $($device.deviceName)" -PercentComplete (($processedDevices / $targetDevices.Count) * 100)

        if ($PSCmdlet.ShouldProcess($device.deviceName, 'Remote restart')) {
            $restartSuccessful = Invoke-DeviceRestart -DeviceId $device.id -DeviceName $device.deviceName

            if ($restartSuccessful) {
                $successfulRestarts++
            }
            else {
                $failedRestarts++
            }
        }

        # Add delay between restart operations to avoid overwhelming the service
        if ($processedDevices -lt $targetDevices.Count) {
            Start-Sleep -Seconds $RestartDelaySeconds
        }
    }

    Write-Progress -Activity 'Restarting Devices' -Completed

    # Display final summary
    Write-Output "`nRESTART OPERATION SUMMARY"
    Write-Output "========================="
    Write-Output "Total Devices Processed: $($targetDevices.Count)"
    Write-Output "Successful Restarts: $successfulRestarts"
    Write-Output "Failed Restarts: $failedRestarts"

    # Show failed devices if any
    if ($failedRestarts -gt 0) {
        Write-Output "`nFailed restart operations require manual review."
        exit 1
    }

    if ($successfulRestarts -gt 0) {
        Write-Output "`n$successfulRestarts device(s) have been scheduled for restart."
        Write-Output "Note: Devices will restart within 5-30 minutes depending on sync status."
    }

    Write-Output "`nDevice restart operation completed successfully!"

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    try {
        $null = Disconnect-MgGraph
        Write-Output '✓ Disconnected from Microsoft Graph'
    }
    catch {
        # Ignore disconnection errors - this is expected behavior when already disconnected
        Write-Verbose 'Graph disconnection completed (may have already been disconnected)'
    }
}
