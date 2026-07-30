<#
.TITLE
    Wipe Devices

.SYNOPSIS
    Perform remote wipe operations on specific managed devices in Intune or devices in an Entra ID group.

.DESCRIPTION
    This script connects to Microsoft Graph and triggers remote wipe operations on targeted devices.
    You can target devices by specific names, device IDs, or by Entra ID group membership.
    The script provides options for selective wipe (remove company data) or full wipe (factory reset).
    All operations include confirmation prompts to prevent accidental data loss.

.TAGS
    Operational,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.PrivilegedOperations.All,DeviceManagementManagedDevices.Read.All,GroupMember.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.5

.CHANGELOG
    1.5 - Added a portal-safe DryRun mode and records an empty target group as a successful no-op
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Added -WhatIf dry run support; Azure Automation now requires -Force instead of hanging on a prompt; exit code 1 when any wipe fails; 429 retry with 60s wait on wipe calls; PIN now applies only to macOS devices with a warning otherwise; group lookup failures abort with a distinct error; list-based result accumulation; added $select to managed device queries
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing); added DeviceManagementManagedDevices.PrivilegedOperations.All scope required by the Graph action (calls previously always failed with 403)
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\wipe-devices.ps1 -DeviceNames "LAPTOP001","DESKTOP002" -WipeType Selective
    Performs selective wipe on specific devices by name

.EXAMPLE
    .\wipe-devices.ps1 -DeviceIds "12345678-1234-1234-1234-123456789012" -WipeType Full -Force "true"
    Performs full wipe on a specific device by ID without confirmation

.EXAMPLE
    .\wipe-devices.ps1 -EntraGroupName "Compromised Devices" -WipeType Selective
    Performs selective wipe on all devices belonging to users in the specified group

.EXAMPLE
    .\wipe-devices.ps1 -DeviceNames "LAPTOP001" -WipeType Full -KeepEnrollmentData "true" -PIN "123456"
    Performs full wipe while keeping enrollment data and using a PIN for device unlock

.EXAMPLE
    .\wipe-devices.ps1 -EntraGroupName "Compromised Devices" -WipeType Selective -DryRun "true"
    Lists the target devices without sending a wipe action

.NOTES
    - Supports both local execution and Azure Automation Runbook environments
    - Automatically detects execution environment and uses appropriate authentication method
    - Local execution: Uses interactive authentication with specified scopes
    - Azure Automation: Uses Managed Identity authentication
    - Requires Microsoft.Graph.Authentication module (auto-installs if missing in local environment)
    - Use -ForceModuleInstall to skip installation prompts in local environment
    - Requires appropriate permissions in Azure AD
    - CAUTION: Full wipe will completely reset the device to factory settings
    - Selective wipe removes only company data and apps
    - Operations cannot be undone - use with extreme caution
    - Confirmation prompts are shown unless -Force parameter is used
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

    [Parameter(Mandatory = $true)]
    [ValidateSet('Selective', 'Full')]
    [string]$WipeType,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Preview target devices without wiping them")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$KeepEnrollmentData,

    [Parameter(Mandatory = $false)]
    [string]$PIN,

    [Parameter(Mandatory = $false)]
    [int]$WipeDelaySeconds = 3,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
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
foreach ($runbookBooleanParameter in @('Force', 'DryRun', 'KeepEnrollmentData')) {
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

$selectedTargets = @(
    if (@($DeviceNames).Count -gt 0) { 'DeviceNames' }
    if (@($DeviceIds).Count -gt 0) { 'DeviceIds' }
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

# Azure Automation runs are unattended - require -Force so the script cannot hang on a confirmation prompt
if ($IsAzureAutomation -and -not $Force -and -not $DryRun) {
    Write-Error "-Force is required for unattended wipe in Azure Automation"
    exit 1
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
        $scopes = @("DeviceManagementManagedDevices.PrivilegedOperations.All", "DeviceManagementManagedDevices.Read.All")
        if ($TargetMode -eq 'EntraGroup') {
            $scopes += "GroupMember.Read.All"
        }
        Connect-MgGraphCommunity -Scopes $scopes -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph"
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
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            throw "Error fetching data from $nextLink : $($_.Exception.Message)"
        }
    } while ($nextLink)

    return $allResults
}

# Function to trigger device wipe
function Invoke-DeviceWipe {
    param(
        [string]$DeviceId,
        [string]$DeviceName,
        [string]$WipeType,
        [bool]$KeepEnrollmentData,
        [string]$PIN,
        [string]$OperatingSystem
    )

    try {
        # Prepare wipe request body
        $wipeBody = @{
            keepEnrollmentData = $KeepEnrollmentData
        }

        # Add PIN if provided for full wipe (macOsUnlockCode applies to macOS devices only)
        if ($WipeType -eq 'Full' -and -not [string]::IsNullOrEmpty($PIN)) {
            if ($OperatingSystem -eq 'macOS') {
                $wipeBody['useProtectedWipe'] = $true
                $wipeBody['macOsUnlockCode'] = $PIN
            }
            else {
                Write-Warning "PIN applies only to macOS devices and will be ignored for $DeviceName ($OperatingSystem)"
            }
        }

        # Determine endpoint based on wipe type
        if ($WipeType -eq 'Selective') {
            $wipeUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/retire"
        }
        else {
            $wipeUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/wipe"
        }

        Invoke-MgGraphRequest -Uri $wipeUri -Method POST -Body ($wipeBody | ConvertTo-Json)
        Write-Information "✓ $WipeType wipe initiated for device: $DeviceName" -InformationAction Continue
        return $true
    }
    catch {
        if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
            Write-Information "Rate limit hit for device $DeviceName, waiting 60 seconds before retry..." -InformationAction Continue
            Start-Sleep -Seconds 60
            try {
                Invoke-MgGraphRequest -Uri $wipeUri -Method POST -Body ($wipeBody | ConvertTo-Json)
                Write-Information "✓ $WipeType wipe initiated for device: $DeviceName" -InformationAction Continue
                return $true
            }
            catch {
                Write-Information "✗ Failed to wipe device $DeviceName after retry: $($_.Exception.Message)" -InformationAction Continue
                return $false
            }
        }
        Write-Information "✗ Failed to wipe device $DeviceName : $($_.Exception.Message)" -InformationAction Continue
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
        Write-Information "Retrieving group members..." -InformationAction Continue
        $membersUri = "https://graph.microsoft.com/beta/groups/$($group.id)/members"
        $members = @(Get-MgGraphAllPage -Uri $membersUri)

        Write-Information "✓ Found $($members.Count) members in group" -InformationAction Continue

        # Get all managed devices
        Write-Information "Retrieving managed devices..." -InformationAction Continue
        $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,osVersion,model,lastSyncDateTime"
        $allDevices = @(Get-MgGraphAllPage -Uri $devicesUri)

        # Filter devices by group members
        [System.Collections.Generic.List[PSCustomObject]]$targetDevices = @()
        foreach ($device in $allDevices) {
            if ($device.userPrincipalName) {
                $userInGroup = $members | Where-Object { $_.userPrincipalName -eq $device.userPrincipalName -or $_.mail -eq $device.userPrincipalName }
                if ($userInGroup) {
                    $targetDevices.Add($device)
                }
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

    Write-Information "`n📱 DEVICE DETAILS" -InformationAction Continue
    Write-Information "=================" -InformationAction Continue

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
            Write-Output "Retrieving devices by names..."
            $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,osVersion,model,lastSyncDateTime"
            $allDevices = @(Get-MgGraphAllPage -Uri $devicesUri)

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
            Write-Output "Retrieving devices by IDs..."
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
            $targetDevices = @(Get-DevicesByEntraGroup -GroupName $EntraGroupName)
        }
    }

    if ($targetDevices.Count -eq 0) {
        Write-Output "No target devices found. No wipe action is required."
        Disconnect-MgGraph | Out-Null
        exit 0
    }

    # Display target information
    Write-Output "`n🚨 DEVICE WIPE OPERATION"
    Write-Output "========================="
    Write-Output "Wipe Type: $WipeType"
    Write-Output "Total devices to process: $($targetDevices.Count)"
    Write-Output "Keep Enrollment Data: $KeepEnrollmentData"

    if ($WipeType -eq 'Full') {
        Write-Output "⚠️  WARNING: Full wipe will completely erase all data on these devices!"
    }
    else {
        Write-Output "ℹ️  Selective wipe will remove only company data and apps"
    }

    # Show device details
    Show-DeviceDetail -Devices $targetDevices

    if ($DryRun) {
        Write-Output "✓ Dry run completed. No wipe actions were sent."
        Disconnect-MgGraph | Out-Null
        exit 0
    }

    # Confirmation prompt for local runs unless Force or WhatIf is specified
    # (Azure Automation without -Force already exited during environment detection)
    if (-not $Force -and -not $WhatIfPreference) {
        Write-Output "`n🛑 CONFIRMATION REQUIRED"
        Write-Output "This operation will perform a $($WipeType.ToLower()) wipe on $($targetDevices.Count) device(s)."

        if ($WipeType -eq 'Full') {
            Write-Output "⚠️  THIS WILL PERMANENTLY DELETE ALL DATA ON THE DEVICES!"
        }

        $confirmation = Read-Host "`nType 'CONFIRM' to proceed with the wipe operation"

        if ($confirmation -ne 'CONFIRM') {
            Write-Output "Operation cancelled by user."
            Disconnect-MgGraph | Out-Null
            exit 0
        }
    }

    # Process wipe operations
    $successfulWipes = 0
    $failedWipes = 0
    $processedDevices = 0

    Write-Output "`n🔄 Processing device wipe operations..."

    foreach ($device in $targetDevices) {
        $processedDevices++
        Write-Progress -Activity "Wiping Devices" -Status "Processing device $processedDevices of $($targetDevices.Count): $($device.deviceName)" -PercentComplete (($processedDevices / $targetDevices.Count) * 100)

        if ($PSCmdlet.ShouldProcess($device.deviceName, "$WipeType wipe")) {
            $wipeSuccessful = Invoke-DeviceWipe -DeviceId $device.id -DeviceName $device.deviceName -WipeType $WipeType -KeepEnrollmentData $KeepEnrollmentData -PIN $PIN -OperatingSystem $device.operatingSystem

            if ($wipeSuccessful) {
                $successfulWipes++
            }
            else {
                $failedWipes++
            }
        }

        # Add delay between wipe operations
        if ($processedDevices -lt $targetDevices.Count) {
            Start-Sleep -Seconds $WipeDelaySeconds
        }
    }

    Write-Progress -Activity "Wiping Devices" -Completed

    # Display final summary
    Write-Output "`n🔄 WIPE OPERATION SUMMARY"
    Write-Output "========================="
    Write-Output "Wipe Type: $WipeType"
    Write-Output "Total Devices Processed: $($targetDevices.Count)"
    Write-Output "Successful Wipes: $successfulWipes"
    Write-Output "Failed Wipes: $failedWipes"

    # Show failed devices if any
    if ($failedWipes -gt 0) {
        Write-Output "`n❌ Failed wipe operations require manual review."
        exit 1
    }

    if ($successfulWipes -gt 0) {
        Write-Output "`n✅ $successfulWipes device(s) have been scheduled for $($WipeType.ToLower()) wipe."
        Write-Output "📋 Note: Wipe operations may take several minutes to complete on the devices."
    }

    Write-Output "`n🎉 Device wipe operation completed!"

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
