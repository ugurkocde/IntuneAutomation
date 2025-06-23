<#
.TITLE
    Create App-Based Entra ID Groups

.SYNOPSIS
    Creates Entra ID groups based on applications installed on Intune-managed devices.

.DESCRIPTION
    This script queries Intune-managed devices to identify which applications are installed,
    then creates or updates Entra ID groups containing devices with specific applications.
    It supports multiple detection methods including detected apps and deployment status,
    handles all app types (Win32, Store, LOB, Web apps), and provides flexible group
    creation options. Perfect for dynamic device targeting based on installed software.

.TAGS
    Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementApps.Read.All,Group.ReadWrite.All,Directory.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-06-23

.EXAMPLE
    .\create-app-based-groups.ps1 -ApplicationName "TeamViewer"
    Creates a group named "Devices-With-TeamViewer" containing all devices with TeamViewer installed

.EXAMPLE
    .\create-app-based-groups.ps1 -ApplicationName "Microsoft*" -GroupPrefix "SW-" -GroupSuffix "-Installed"
    Creates groups for all Microsoft apps with custom naming (e.g., "SW-Microsoft Teams-Installed")

.EXAMPLE
    .\create-app-based-groups.ps1 -ApplicationName "Chrome" -MinimumVersion "120.0" -UpdateExisting
    Creates/updates a group with devices having Chrome version 120.0 or higher

.EXAMPLE
    .\create-app-based-groups.ps1 -ApplicationName "*" -FilterByType "Win32" -DryRun
    Preview groups that would be created for all Win32 applications

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Supports wildcards in application names
    - Can create multiple groups in a single run
    - Uses both detected apps and deployment status for comprehensive coverage
    - Groups are created as security groups by default
    - Device limit per group is 100,000 (Entra ID limitation)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Application name or pattern (supports wildcards)")]
    [string]$ApplicationName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Prefix for group names")]
    [string]$GroupPrefix = "Devices-With-",
    
    [Parameter(Mandatory = $false, HelpMessage = "Suffix for group names")]
    [string]$GroupSuffix = "",
    
    [Parameter(Mandatory = $false, HelpMessage = "Update existing groups instead of creating new")]
    [switch]$UpdateExisting,
    
    [Parameter(Mandatory = $false, HelpMessage = "Minimum application version")]
    [string]$MinimumVersion,
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by app type (Win32, Store, LOB, Web, etc.)")]
    [ValidateSet("Win32", "Store", "LOB", "Web", "iOS", "Android", "macOS", "All")]
    [string]$FilterByType = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Filter by device platform")]
    [ValidateSet("Windows", "iOS", "Android", "macOS", "All")]
    [string]$FilterByPlatform = "All",
    
    [Parameter(Mandatory = $false, HelpMessage = "Only include devices with successful installations")]
    [switch]$OnlySuccessfulInstalls,
    
    [Parameter(Mandatory = $false, HelpMessage = "Preview changes without creating groups")]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false, HelpMessage = "Maximum devices to process (0 = all)")]
    [int]$MaxDevices = 0,
    
    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall
)

# ============================================================================
# ENVIRONMENT DETECTION AND SETUP
# ============================================================================

function Initialize-RequiredModule {
    param(
        [string[]]$ModuleNames,
        [bool]$IsAutomationEnvironment,
        [bool]$ForceInstall = $false
    )
    
    foreach ($ModuleName in $ModuleNames) {
        Write-Verbose "Checking module: $ModuleName"
        
        $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1
        
        if (-not $module) {
            if ($IsAutomationEnvironment) {
                throw "Module '$ModuleName' is not available in Azure Automation"
            }
            else {
                Write-Information "Module '$ModuleName' not found. Installing..." -InformationAction Continue
                
                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }
                
                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }
                    
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }
        
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
}

# Detect execution environment
$IsAzureAutomation = $null -ne $PSPrivateMetadata.JobId.Guid

# Initialize required modules
$RequiredModules = @("Microsoft.Graph.Authentication")

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
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementApps.Read.All", 
            "Group.ReadWrite.All",
            "Directory.Read.All"
        )
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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
            
            if ($requestCount % 10 -eq 0) {
                Write-Information "." -InformationAction Continue
            }
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data: $($_.Exception.Message)"
            break
        }
    } while ($nextLink)
    
    return $allResults
}

function Get-AppTypeFromODataType {
    param([string]$ODataType)
    
    switch ($ODataType) {
        "#microsoft.graph.win32LobApp" { return "Win32" }
        "#microsoft.graph.microsoftStoreForBusinessApp" { return "Store" }
        "#microsoft.graph.webApp" { return "Web" }
        "#microsoft.graph.officeSuiteApp" { return "Office" }
        "#microsoft.graph.winGetApp" { return "WinGet" }
        "#microsoft.graph.iosLobApp" { return "iOS" }
        "#microsoft.graph.iosStoreApp" { return "iOS" }
        "#microsoft.graph.androidManagedStoreApp" { return "Android" }
        "#microsoft.graph.androidLobApp" { return "Android" }
        "#microsoft.graph.macOSLobApp" { return "macOS" }
        "#microsoft.graph.macOSOfficeSuiteApp" { return "macOS" }
        default { return "Other" }
    }
}

function Compare-Version {
    param(
        [string]$Version1,
        [string]$Version2
    )
    
    try {
        $v1 = [Version]$Version1
        $v2 = [Version]$Version2
        return $v1 -ge $v2
    }
    catch {
        # Fallback to string comparison if version parsing fails
        return $Version1 -ge $Version2
    }
}

function Get-SanitizedGroupName {
    param([string]$AppName)
    
    # Remove invalid characters for group names
    $sanitized = $AppName -replace '[^\w\s-]', ''
    $sanitized = $sanitized -replace '\s+', '-'
    $sanitized = $sanitized -replace '-+', '-'
    $sanitized = $sanitized.Trim('-')
    
    # Ensure the name is not too long (max 256 chars for Entra ID)
    $maxLength = 256 - $GroupPrefix.Length - $GroupSuffix.Length
    if ($sanitized.Length -gt $maxLength) {
        $sanitized = $sanitized.Substring(0, $maxLength)
    }
    
    return "${GroupPrefix}${sanitized}${GroupSuffix}"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting app-based group creation process..." -InformationAction Continue
    
    # Get all managed devices
    Write-Information "Retrieving managed devices..." -InformationAction Continue
    $devicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    if ($MaxDevices -gt 0) {
        $devicesUri += "?`$top=$MaxDevices"
    }
    
    $devices = Get-MgGraphAllPages -Uri $devicesUri
    
    # Filter by platform if specified
    if ($FilterByPlatform -ne "All") {
        $devices = $devices | Where-Object { 
            $_.operatingSystem -like "$FilterByPlatform*" 
        }
    }
    
    Write-Information "`n✓ Found $($devices.Count) managed devices" -InformationAction Continue
    
    # Dictionary to store app->devices mapping
    $appDeviceMap = @{}
    $processedDevices = 0
    
    # Process devices to get detected apps
    Write-Information "Processing device applications..." -InformationAction Continue
    
    foreach ($device in $devices) {
        $processedDevices++
        Write-Progress -Activity "Processing Devices" -Status "$processedDevices of $($devices.Count)" -PercentComplete (($processedDevices / $devices.Count) * 100)
        
        try {
            # Get detected apps for the device
            $deviceAppsUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)?`$expand=detectedApps"
            $deviceWithApps = Invoke-MgGraphRequest -Uri $deviceAppsUri -Method GET
            
            if ($deviceWithApps.detectedApps) {
                foreach ($app in $deviceWithApps.detectedApps) {
                    # Check if app matches the filter
                    if ($app.displayName -like $ApplicationName) {
                        # Check version if specified
                        if ($MinimumVersion -and $app.version) {
                            if (-not (Compare-Version -Version1 $app.version -Version2 $MinimumVersion)) {
                                continue
                            }
                        }
                        
                        # Add device to app mapping
                        $appKey = $app.displayName
                        if (-not $appDeviceMap.ContainsKey($appKey)) {
                            $appDeviceMap[$appKey] = @{
                                Devices    = @()
                                Versions   = @{}
                                Publishers = @{}
                            }
                        }
                        
                        $appDeviceMap[$appKey].Devices += @{
                            DeviceId   = $device.id
                            DeviceName = $device.deviceName
                            Platform   = $device.operatingSystem
                            User       = $device.userPrincipalName
                            Version    = $app.version
                            Publisher  = $app.publisher
                        }
                        
                        # Track versions and publishers
                        if ($app.version) {
                            $appDeviceMap[$appKey].Versions[$app.version] = ($appDeviceMap[$appKey].Versions[$app.version] ?? 0) + 1
                        }
                        if ($app.publisher) {
                            $appDeviceMap[$appKey].Publishers[$app.publisher] = ($appDeviceMap[$appKey].Publishers[$app.publisher] ?? 0) + 1
                        }
                    }
                }
            }
            
            Start-Sleep -Milliseconds 50
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                $processedDevices--
                continue
            }
            Write-Warning "Error processing device $($device.deviceName): $($_.Exception.Message)"
        }
    }
    
    Write-Progress -Activity "Processing Devices" -Completed
    
    # Get deployed apps if we need additional coverage
    if ($FilterByType -ne "All" -or $OnlySuccessfulInstalls) {
        Write-Information "Retrieving deployed application data..." -InformationAction Continue
        $appsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
        $deployedApps = Get-MgGraphAllPages -Uri $appsUri
        
        foreach ($app in $deployedApps) {
            if ($app.displayName -like $ApplicationName) {
                $appType = Get-AppTypeFromODataType -ODataType $app.'@odata.type'
                
                # Filter by type if specified
                if ($FilterByType -ne "All" -and $appType -ne $FilterByType) {
                    continue
                }
                
                # Get device installation status
                $statusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/deviceStatuses"
                $deviceStatuses = Get-MgGraphAllPages -Uri $statusUri
                
                foreach ($status in $deviceStatuses) {
                    # Filter by installation status if specified
                    if ($OnlySuccessfulInstalls -and $status.installState -ne "installed") {
                        continue
                    }
                    
                    # Find matching device
                    $matchingDevice = $devices | Where-Object { $_.id -eq $status.deviceId }
                    if ($matchingDevice) {
                        $appKey = $app.displayName
                        if (-not $appDeviceMap.ContainsKey($appKey)) {
                            $appDeviceMap[$appKey] = @{
                                Devices    = @()
                                Versions   = @{}
                                Publishers = @{}
                                AppType    = $appType
                            }
                        }
                        
                        # Check if device already added
                        $existingDevice = $appDeviceMap[$appKey].Devices | Where-Object { $_.DeviceId -eq $matchingDevice.id }
                        if (-not $existingDevice) {
                            $appDeviceMap[$appKey].Devices += @{
                                DeviceId     = $matchingDevice.id
                                DeviceName   = $matchingDevice.deviceName
                                Platform     = $matchingDevice.operatingSystem
                                User         = $matchingDevice.userPrincipalName
                                InstallState = $status.installState
                                AppType      = $appType
                            }
                        }
                    }
                }
            }
        }
    }
    
    # Create or update groups
    Write-Information "`nProcessing groups for $($appDeviceMap.Count) applications..." -InformationAction Continue
    $groupsCreated = 0
    $groupsUpdated = 0
    $totalDevicesProcessed = 0
    
    foreach ($appName in $appDeviceMap.Keys) {
        $appInfo = $appDeviceMap[$appName]
        $uniqueDevices = $appInfo.Devices | Select-Object -Property DeviceId -Unique
        $deviceCount = $uniqueDevices.Count
        
        if ($deviceCount -eq 0) {
            continue
        }
        
        $groupName = Get-SanitizedGroupName -AppName $appName
        Write-Information "`nProcessing: $appName ($deviceCount devices in Intune)" -InformationAction Continue
        
        if ($DryRun) {
            Write-Information "  [DRY RUN] Would create/update group: $groupName" -InformationAction Continue
            Write-Information "  Total devices with app: $deviceCount" -InformationAction Continue
            
            # Show device names
            Write-Information "  Devices to be added:" -InformationAction Continue
            foreach ($device in $appInfo.Devices) {
                Write-Information "    • $($device.DeviceName) ($($device.Platform))" -InformationAction Continue
            }
            
            if ($appInfo.Versions.Count -gt 0) {
                Write-Information "  Versions found: $($appInfo.Versions.Keys -join ', ')" -InformationAction Continue
            }
            $totalDevicesProcessed += $deviceCount
            continue
        }
        
        # Check if group exists
        $existingGroup = $null
        try {
            $groupFilter = "displayName eq '$groupName'"
            $existingGroups = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$groupFilter" -Method GET
            $existingGroup = $existingGroups.value | Select-Object -First 1
        }
        catch {
            Write-Verbose "No existing group found with name: $groupName"
        }
        
        if ($existingGroup -and -not $UpdateExisting) {
            Write-Warning "  Group '$groupName' already exists. Use -UpdateExisting to update it."
            continue
        }
        
        # Prepare member list - need to get Entra ID device object IDs
        $memberIds = @()
        $entraDevices = @()
        
        if ($uniqueDevices.Count -gt 0) {
            Write-Verbose "Looking up Entra ID device objects for $($uniqueDevices.Count) devices..."
            
            foreach ($device in $uniqueDevices) {
                try {
                    # Get the Intune device details first
                    $intuneDevice = $devices | Where-Object { $_.id -eq $device.DeviceId } | Select-Object -First 1
                    
                    if ($intuneDevice -and $intuneDevice.azureADDeviceId) {
                        # Look up the device in Entra ID by Azure AD Device ID
                        $filter = "deviceId eq '$($intuneDevice.azureADDeviceId)'"
                        $entraDeviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=$filter"
                        $entraDeviceResponse = Invoke-MgGraphRequest -Uri $entraDeviceUri -Method GET
                        
                        if ($entraDeviceResponse.value -and $entraDeviceResponse.value.Count -gt 0) {
                            $entraDevice = $entraDeviceResponse.value[0]
                            $memberIds += "https://graph.microsoft.com/v1.0/directoryObjects/$($entraDevice.id)"
                            $entraDevices += @{
                                IntuneDeviceId = $device.DeviceId
                                EntraDeviceId  = $entraDevice.id
                                DeviceName     = $intuneDevice.deviceName
                            }
                            Write-Verbose "Found Entra ID device: $($intuneDevice.deviceName) -> $($entraDevice.id)"
                        }
                        else {
                            Write-Warning "Device not found in Entra ID: $($intuneDevice.deviceName) (Azure AD Device ID: $($intuneDevice.azureADDeviceId))"
                        }
                    }
                    else {
                        Write-Warning "No Azure AD Device ID for: $($intuneDevice.deviceName)"
                    }
                }
                catch {
                    Write-Warning "Error looking up Entra ID device for $($intuneDevice.deviceName): $($_.Exception.Message)"
                }
            }
            
            Write-Verbose "Found $($memberIds.Count) devices in Entra ID out of $($uniqueDevices.Count) Intune devices"
        }
        
        if ($existingGroup -and $UpdateExisting) {
            # Update existing group
            if ($PSCmdlet.ShouldProcess($groupName, "Update group members")) {
                try {
                    # Get current members
                    $currentMembersUri = "https://graph.microsoft.com/v1.0/groups/$($existingGroup.id)/members"
                    $currentMembers = Get-MgGraphAllPages -Uri $currentMembersUri
                    $currentMemberIds = $currentMembers | ForEach-Object { $_.id }
                    
                    # Calculate additions and removals - use Entra device IDs
                    $entraDeviceIds = $entraDevices | ForEach-Object { $_.EntraDeviceId }
                    $deviceIdsToAdd = $entraDeviceIds | Where-Object { $_ -notin $currentMemberIds }
                    $deviceIdsToRemove = $currentMemberIds | Where-Object { $_ -notin $entraDeviceIds }
                    
                    # Add new members
                    if ($deviceIdsToAdd.Count -gt 0) {
                        # Add members in batches
                        $batchSize = 20
                        for ($i = 0; $i -lt $deviceIdsToAdd.Count; $i += $batchSize) {
                            $batch = $deviceIdsToAdd[$i..([Math]::Min($i + $batchSize - 1, $deviceIdsToAdd.Count - 1))]
                            $addBody = @{
                                "members@odata.bind" = $batch | ForEach-Object {
                                    "https://graph.microsoft.com/v1.0/directoryObjects/$_"
                                }
                            } | ConvertTo-Json -Depth 10
                            
                            Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$($existingGroup.id)" -Method PATCH -Body $addBody -ContentType "application/json"
                            Write-Verbose "Added batch of $($batch.Count) members"
                        }
                    }
                    
                    # Remove old members
                    foreach ($memberId in $deviceIdsToRemove) {
                        $removeUri = "https://graph.microsoft.com/v1.0/groups/$($existingGroup.id)/members/$memberId/`$ref"
                        Invoke-MgGraphRequest -Uri $removeUri -Method DELETE
                    }
                    
                    Write-Information "  ✓ Updated group: $groupName (Added: $($deviceIdsToAdd.Count), Removed: $($deviceIdsToRemove.Count))" -InformationAction Continue
                    
                    # Display added devices
                    if ($deviceIdsToAdd.Count -gt 0) {
                        Write-Information "  Added devices:" -InformationAction Continue
                        foreach ($deviceId in $deviceIdsToAdd) {
                            $deviceInfo = $entraDevices | Where-Object { $_.EntraDeviceId -eq $deviceId } | Select-Object -First 1
                            if ($deviceInfo) {
                                Write-Information "    • $($deviceInfo.DeviceName)" -InformationAction Continue
                            }
                        }
                    }
                    
                    $groupsUpdated++
                }
                catch {
                    Write-Error "  ✗ Failed to update group: $($_.Exception.Message)"
                }
            }
        }
        else {
            # Create new group
            if ($PSCmdlet.ShouldProcess($groupName, "Create new group")) {
                try {
                    # Create group without members first
                    $groupBody = @{
                        displayName     = $groupName
                        mailEnabled     = $false
                        mailNickname    = $groupName -replace '[^a-zA-Z0-9]', ''
                        securityEnabled = $true
                        description     = "Devices with $appName installed (Created by Intune Automation)"
                    } | ConvertTo-Json -Depth 10
                    
                    $newGroup = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups" -Method POST -Body $groupBody -ContentType "application/json"
                    Write-Information "  ✓ Created group: $groupName" -InformationAction Continue
                    Write-Information "  Group ID: $($newGroup.id)" -InformationAction Continue
                    
                    # Add members to the group if any
                    if ($memberIds.Count -gt 0) {
                        try {
                            # Add members in batches of 20 (Graph API limitation)
                            $batchSize = 20
                            for ($i = 0; $i -lt $memberIds.Count; $i += $batchSize) {
                                $batch = $memberIds[$i..([Math]::Min($i + $batchSize - 1, $memberIds.Count - 1))]
                                $addMembersBody = @{
                                    "members@odata.bind" = $batch
                                } | ConvertTo-Json -Depth 10
                                
                                Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$($newGroup.id)" -Method PATCH -Body $addMembersBody -ContentType "application/json"
                                Write-Verbose "Added batch of $($batch.Count) members"
                            }
                            Write-Information "  ✓ Added $($memberIds.Count) devices to group" -InformationAction Continue
                            
                            # Display added devices
                            Write-Information "  Added devices:" -InformationAction Continue
                            foreach ($device in $entraDevices) {
                                Write-Information "    • $($device.DeviceName)" -InformationAction Continue
                            }
                        }
                        catch {
                            Write-Warning "  Group created but failed to add members: $($_.Exception.Message)"
                        }
                    }
                    
                    $groupsCreated++
                }
                catch {
                    Write-Error "  ✗ Failed to create group: $($_.Exception.Message)"
                    Write-Verbose "Group body: $groupBody"
                }
            }
        }
        
        $totalDevicesProcessed += $deviceCount
    }
    
    # Display summary
    Write-Information "`n📊 APP-BASED GROUP CREATION SUMMARY" -InformationAction Continue
    Write-Information "===================================" -InformationAction Continue
    Write-Information "Applications matched: $($appDeviceMap.Count)" -InformationAction Continue
    Write-Information "Total devices processed: $totalDevicesProcessed" -InformationAction Continue
    Write-Information "Groups created: $groupsCreated" -InformationAction Continue
    Write-Information "Groups updated: $groupsUpdated" -InformationAction Continue
    
    if ($DryRun) {
        Write-Information "`n[DRY RUN] No changes were made" -InformationAction Continue
    }
    
    # Display top apps by device count
    if ($appDeviceMap.Count -gt 0) {
        Write-Information "`nTop Applications by Device Count:" -InformationAction Continue
        $appDeviceMap.GetEnumerator() | 
        Sort-Object { $_.Value.Devices.Count } -Descending | 
        Select-Object -First 10 |
        ForEach-Object {
            $deviceCount = ($_.Value.Devices | Select-Object -Property DeviceId -Unique).Count
            Write-Information "  • $($_.Key): $deviceCount devices" -InformationAction Continue
        }
    }
    
    Write-Information "`n🎉 App-based group creation completed successfully!" -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}