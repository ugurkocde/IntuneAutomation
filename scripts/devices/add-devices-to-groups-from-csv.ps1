<#
.TITLE
    Add Devices to Entra ID Groups from CSV

.SYNOPSIS
    Adds Intune-managed devices to Entra ID groups based on a CSV file input.

.DESCRIPTION
    This script reads a CSV file containing device identifiers and group names, then adds
    the specified devices to their corresponding Entra ID groups. It supports multiple
    device identifiers (Device Name, Serial Number, Azure AD Device ID) for flexible
    device matching and can add devices to multiple groups.

    The script validates that devices exist in Intune before processing, checks for
    existing group memberships to avoid duplicates, and can create new groups with
    user confirmation. A dry-run mode allows previewing changes before execution.

.TAGS
    Operational,Devices

.PLATFORM
    Windows

.MINROLE
    Intune Administrator

.PERMISSIONS
    Group.ReadWrite.All,DeviceManagementManagedDevices.Read.All,Directory.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\add-devices-to-groups-from-csv.ps1 -GenerateTemplate
    Creates a template CSV file using your system's default delimiter (automatically comma for US, semicolon for Europe)

.EXAMPLE
    .\add-devices-to-groups-from-csv.ps1 -GenerateTemplate -TemplatePath "C:\templates\mytemplate.csv"
    Creates a template CSV file at the specified path with system default delimiter

.EXAMPLE
    .\add-devices-to-groups-from-csv.ps1 -CsvPath "C:\devices.csv"
    Reads the CSV file and adds devices to specified groups

.EXAMPLE
    .\add-devices-to-groups-from-csv.ps1 -CsvPath "C:\devices.csv" -DryRun
    Preview what changes would be made without actually making them

.EXAMPLE
    .\add-devices-to-groups-from-csv.ps1 -CsvPath "C:\devices.csv" -CreateMissingGroups -Force
    Add devices to groups and automatically create missing groups without prompting

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - CSV file should contain columns: DeviceName, SerialNumber, DeviceId (Azure AD), GroupName
    - At least one device identifier (DeviceName, SerialNumber, or DeviceId) must be provided per row
    - The GroupName column is required for all rows
    - Devices already in target groups will be skipped
    - Device matching priority: DeviceId > SerialNumber > DeviceName
    - CSV import: Automatically detects comma or semicolon delimiters
    - Template generation: Automatically uses your system's regional delimiter (comma for US/UK, semicolon for Europe)
    - Templates will open correctly in Excel on the system where they were generated

    CSV Format Example:
    DeviceName,SerialNumber,DeviceId,GroupName
    DESKTOP-ABC123,VMW12345,,IT-Department-Devices
    ,VMW67890,,Finance-Devices
    ,,a1b2c3d4-e5f6-7890-abcd-ef1234567890,Executive-Devices
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Path to the CSV file containing device and group information")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_ -PathType Leaf)) {
            throw "CSV file not found at path: $_"
        }
        return $true
    })]
    [string]$CsvPath,

    [Parameter(Mandatory = $false, HelpMessage = "Generate a CSV template file")]
    [switch]$GenerateTemplate,

    [Parameter(Mandatory = $false, HelpMessage = "Path for the generated template file")]
    [string]$TemplatePath = "device-group-template.csv",

    [Parameter(Mandatory = $false, HelpMessage = "Preview changes without making them")]
    [switch]$DryRun,

    [Parameter(Mandatory = $false, HelpMessage = "Automatically create missing groups without prompting")]
    [switch]$CreateMissingGroups,

    [Parameter(Mandatory = $false, HelpMessage = "Skip confirmation prompts")]
    [switch]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall
)

# ============================================================================
# TEMPLATE GENERATION
# ============================================================================

if ($GenerateTemplate) {
    try {
        Write-Information "Generating CSV template file..." -InformationAction Continue

        # Use system's default list separator
        $csvDelimiter = (Get-Culture).TextInfo.ListSeparator
        Write-Information "Using system delimiter: '$csvDelimiter' (comma for US, semicolon for Europe)" -InformationAction Continue

        # Create template data with examples
        $templateData = @(
            [PSCustomObject]@{
                DeviceName   = "DESKTOP-ABC123"
                SerialNumber = "VMW12345"
                DeviceId     = ""
                GroupName    = "IT-Department-Devices"
            },
            [PSCustomObject]@{
                DeviceName   = ""
                SerialNumber = "VMW67890"
                DeviceId     = ""
                GroupName    = "Finance-Devices"
            },
            [PSCustomObject]@{
                DeviceName   = ""
                SerialNumber = ""
                DeviceId     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                GroupName    = "Executive-Devices"
            },
            [PSCustomObject]@{
                DeviceName   = "LAPTOP-XYZ789"
                SerialNumber = ""
                DeviceId     = ""
                GroupName    = "IT-Department-Devices"
            }
        )

        # Export to CSV with system delimiter
        $templateData | Export-Csv -Path $TemplatePath -NoTypeInformation -Encoding UTF8 -Delimiter $csvDelimiter

        Write-Information "Successfully created template file: $TemplatePath" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Information "Template includes examples showing:" -InformationAction Continue
        Write-Information "  - Using DeviceName and SerialNumber together" -InformationAction Continue
        Write-Information "  - Using only SerialNumber" -InformationAction Continue
        Write-Information "  - Using only DeviceId (Azure AD Device ID)" -InformationAction Continue
        Write-Information "  - Using only DeviceName" -InformationAction Continue
        Write-Information "  - Multiple devices assigned to the same group" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Information "Notes:" -InformationAction Continue
        Write-Information "  - At least one device identifier must be provided per row" -InformationAction Continue
        Write-Information "  - GroupName is required for all rows" -InformationAction Continue
        Write-Information "  - Device matching priority: DeviceId > SerialNumber > DeviceName" -InformationAction Continue

        exit 0
    }
    catch {
        Write-Error "Failed to generate template: $($_.Exception.Message)"
        exit 1
    }
}

# Validate that CsvPath is provided when not generating template
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    Write-Error "The -CsvPath parameter is required. Use -GenerateTemplate to create a template file first."
    exit 1
}

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
                    Write-Information "Successfully installed '$ModuleName'" -InformationAction Continue
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
    Write-Verbose "All required modules are available"
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
            "Group.ReadWrite.All",
            "DeviceManagementManagedDevices.Read.All",
            "Directory.Read.All"
        )
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Information "Successfully connected to Microsoft Graph" -InformationAction Continue
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

function Import-DeviceCsv {
    param(
        [string]$Path
    )

    try {
        Write-Information "Reading CSV file: $Path" -InformationAction Continue

        # Try to detect the delimiter by reading the first line
        $firstLine = Get-Content -Path $Path -First 1
        $delimiter = if ($firstLine -match ',') { ',' } else { ';' }

        Write-Verbose "Using delimiter: $delimiter"
        $csvData = Import-Csv -Path $Path -Delimiter $delimiter -ErrorAction Stop

        if (-not $csvData) {
            throw "CSV file is empty or could not be read"
        }

        # Validate required columns
        $requiredColumn = "GroupName"
        $csvHeaders = $csvData[0].PSObject.Properties.Name

        if ($requiredColumn -notin $csvHeaders) {
            throw "CSV file must contain a '$requiredColumn' column"
        }

        # Check for at least one device identifier column
        $identifierColumns = @("DeviceName", "SerialNumber", "DeviceId")
        $hasIdentifier = $false
        foreach ($col in $identifierColumns) {
            if ($col -in $csvHeaders) {
                $hasIdentifier = $true
                break
            }
        }

        if (-not $hasIdentifier) {
            throw "CSV file must contain at least one device identifier column: DeviceName, SerialNumber, or DeviceId"
        }

        # Validate each row has at least one identifier
        $rowNumber = 1
        foreach ($row in $csvData) {
            $rowNumber++
            $hasValue = $false

            foreach ($col in $identifierColumns) {
                if ($row.PSObject.Properties.Name -contains $col -and -not [string]::IsNullOrWhiteSpace($row.$col)) {
                    $hasValue = $true
                    break
                }
            }

            if (-not $hasValue) {
                Write-Warning "Row $rowNumber has no device identifier (DeviceName, SerialNumber, or DeviceId)"
            }

            if ([string]::IsNullOrWhiteSpace($row.GroupName)) {
                Write-Warning "Row $rowNumber has no GroupName specified"
            }
        }

        Write-Information "Successfully imported $($csvData.Count) rows from CSV" -InformationAction Continue
        return $csvData
    }
    catch {
        throw "Failed to import CSV file: $($_.Exception.Message)"
    }
}

function Find-IntuneDevice {
    param(
        [object]$CsvRow,
        [array]$AllDevices
    )

    # Try DeviceId first (most precise)
    if (-not [string]::IsNullOrWhiteSpace($CsvRow.DeviceId)) {
        $device = $AllDevices | Where-Object { $_.azureADDeviceId -eq $CsvRow.DeviceId } | Select-Object -First 1
        if ($device) {
            return $device
        }
    }

    # Try SerialNumber next
    if (-not [string]::IsNullOrWhiteSpace($CsvRow.SerialNumber)) {
        $device = $AllDevices | Where-Object { $_.serialNumber -eq $CsvRow.SerialNumber } | Select-Object -First 1
        if ($device) {
            return $device
        }
    }

    # Try DeviceName last
    if (-not [string]::IsNullOrWhiteSpace($CsvRow.DeviceName)) {
        $device = $AllDevices | Where-Object { $_.deviceName -eq $CsvRow.DeviceName } | Select-Object -First 1
        if ($device) {
            return $device
        }
    }

    return $null
}

function Get-EntraIdDevice {
    param(
        [string]$AzureAdDeviceId
    )

    try {
        $filter = "deviceId eq '$AzureAdDeviceId'"
        $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=$filter"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET

        if ($response.value -and $response.value.Count -gt 0) {
            return $response.value[0]
        }

        return $null
    }
    catch {
        Write-Warning "Error looking up Entra ID device for Azure AD Device ID $AzureAdDeviceId : $($_.Exception.Message)"
        return $null
    }
}

function Get-EntraIdGroup {
    param(
        [string]$GroupName
    )

    try {
        $filter = "displayName eq '$GroupName'"
        $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=$filter"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET

        if ($response.value -and $response.value.Count -gt 0) {
            return $response.value[0]
        }

        return $null
    }
    catch {
        Write-Warning "Error looking up group '$GroupName': $($_.Exception.Message)"
        return $null
    }
}

function Test-DeviceInGroup {
    param(
        [string]$GroupId,
        [string]$DeviceId
    )

    try {
        $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members"
        $members = Get-MgGraphAllPage -Uri $uri

        return ($members.id -contains $DeviceId)
    }
    catch {
        Write-Warning "Error checking group membership: $($_.Exception.Message)"
        return $false
    }
}

function New-EntraIdGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$GroupName
    )

    if ($PSCmdlet.ShouldProcess($GroupName, "Create new Entra ID group")) {
        try {
            $mailNickname = $GroupName -replace '[^a-zA-Z0-9]', ''

            $groupBody = @{
                displayName     = $GroupName
                mailEnabled     = $false
                mailNickname    = $mailNickname
                securityEnabled = $true
                description     = "Device group created by Intune Automation"
            } | ConvertTo-Json -Depth 10

            $newGroup = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups" -Method POST -Body $groupBody -ContentType "application/json"
            Write-Information "Created group: $GroupName" -InformationAction Continue
            return $newGroup
        }
        catch {
            Write-Error "Failed to create group '$GroupName': $($_.Exception.Message)"
            return $null
        }
    }

    return $null
}

function Add-DeviceToGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$GroupId,
        [string]$DeviceId,
        [string]$DeviceName,
        [string]$GroupName
    )

    if ($PSCmdlet.ShouldProcess("$DeviceName to $GroupName", "Add device to group")) {
        try {
            $addBody = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$DeviceId"
            } | ConvertTo-Json

            $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/`$ref"
            Invoke-MgGraphRequest -Uri $uri -Method POST -Body $addBody -ContentType "application/json"

            return $true
        }
        catch {
            Write-Warning "Failed to add device '$DeviceName' to group '$GroupName': $($_.Exception.Message)"
            return $false
        }
    }

    return $false
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting device-to-group assignment from CSV..." -InformationAction Continue

    if ($DryRun) {
        Write-Information "[DRY RUN MODE] No changes will be made" -InformationAction Continue
    }

    # Import CSV data
    $csvData = Import-DeviceCsv -Path $CsvPath

    # Get all Intune managed devices
    Write-Information "Retrieving all Intune managed devices..." -InformationAction Continue
    $allDevices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    Write-Information "Found $($allDevices.Count) managed devices" -InformationAction Continue

    # Track statistics
    $stats = @{
        TotalRows            = $csvData.Count
        DevicesFound         = 0
        DevicesNotFound      = 0
        GroupsProcessed      = 0
        GroupsCreated        = 0
        DevicesAdded         = 0
        DevicesSkipped       = 0
        Errors               = 0
    }

    # Group CSV rows by GroupName for efficient processing
    $groupedData = $csvData | Group-Object -Property GroupName

    # Check which groups exist
    Write-Information "Checking group existence..." -InformationAction Continue
    $groupCache = @{}
    $missingGroups = @()

    foreach ($groupData in $groupedData) {
        $groupName = $groupData.Name

        if ([string]::IsNullOrWhiteSpace($groupName)) {
            continue
        }

        $group = Get-EntraIdGroup -GroupName $groupName

        if ($group) {
            $groupCache[$groupName] = $group
            Write-Verbose "Group exists: $groupName"
        }
        else {
            $missingGroups += $groupName
            Write-Verbose "Group not found: $groupName"
        }
    }

    # Handle missing groups
    if ($missingGroups.Count -gt 0) {
        Write-Information "`nThe following groups do not exist:" -InformationAction Continue
        foreach ($groupName in $missingGroups) {
            Write-Information "  - $groupName" -InformationAction Continue
        }

        if ($DryRun) {
            Write-Information "`n[DRY RUN] Would need to create $($missingGroups.Count) groups" -InformationAction Continue
        }
        else {
            $shouldCreate = $CreateMissingGroups

            if (-not $shouldCreate -and -not $Force -and -not $IsAzureAutomation) {
                $response = Read-Host "`nDo you want to create these $($missingGroups.Count) missing groups? (Y/N)"
                $shouldCreate = $response -match '^[Yy]'
            }

            if ($shouldCreate) {
                Write-Information "Creating missing groups..." -InformationAction Continue
                foreach ($groupName in $missingGroups) {
                    $newGroup = New-EntraIdGroup -GroupName $groupName
                    if ($newGroup) {
                        $groupCache[$groupName] = $newGroup
                        $stats.GroupsCreated++
                    }
                    else {
                        $stats.Errors++
                    }
                }
            }
            else {
                Write-Warning "Groups will not be created. Devices targeting missing groups will be skipped."
            }
        }
    }

    # Process each row in the CSV
    Write-Information "`nProcessing device assignments..." -InformationAction Continue
    $processedCount = 0

    foreach ($row in $csvData) {
        $processedCount++
        Write-Progress -Activity "Processing CSV rows" -Status "$processedCount of $($csvData.Count)" -PercentComplete (($processedCount / $csvData.Count) * 100)

        $groupName = $row.GroupName

        if ([string]::IsNullOrWhiteSpace($groupName)) {
            Write-Warning "Row ${processedCount}: No group name specified, skipping"
            $stats.Errors++
            continue
        }

        # Check if group exists in cache
        if (-not $groupCache.ContainsKey($groupName)) {
            Write-Warning "Row ${processedCount}: Group '$groupName' not found and not created, skipping"
            $stats.Errors++
            continue
        }

        $group = $groupCache[$groupName]

        # Find the device
        $device = Find-IntuneDevice -CsvRow $row -AllDevices $allDevices

        if (-not $device) {
            $identifier = if (-not [string]::IsNullOrWhiteSpace($row.DeviceId)) { "DeviceId: $($row.DeviceId)" }
            elseif (-not [string]::IsNullOrWhiteSpace($row.SerialNumber)) { "SerialNumber: $($row.SerialNumber)" }
            elseif (-not [string]::IsNullOrWhiteSpace($row.DeviceName)) { "DeviceName: $($row.DeviceName)" }
            else { "Unknown" }

            Write-Warning "Row $processedCount : Device not found ($identifier)"
            $stats.DevicesNotFound++
            continue
        }

        $stats.DevicesFound++

        # Get Entra ID device object
        $entraDevice = Get-EntraIdDevice -AzureAdDeviceId $device.azureADDeviceId

        if (-not $entraDevice) {
            Write-Warning "Row $processedCount : Device '$($device.deviceName)' not found in Entra ID"
            $stats.Errors++
            continue
        }

        # Check if device is already in the group
        $isInGroup = Test-DeviceInGroup -GroupId $group.id -DeviceId $entraDevice.id

        if ($isInGroup) {
            Write-Verbose "Device '$($device.deviceName)' is already in group '$groupName', skipping"
            $stats.DevicesSkipped++
            continue
        }

        # Add device to group
        if ($DryRun) {
            Write-Information "[DRY RUN] Would add device '$($device.deviceName)' to group '$groupName'" -InformationAction Continue
            $stats.DevicesAdded++
        }
        else {
            $success = Add-DeviceToGroup -GroupId $group.id -DeviceId $entraDevice.id -DeviceName $device.deviceName -GroupName $groupName

            if ($success) {
                Write-Information "Added device '$($device.deviceName)' to group '$groupName'" -InformationAction Continue
                $stats.DevicesAdded++
            }
            else {
                $stats.Errors++
            }
        }

        # Small delay to avoid rate limiting
        Start-Sleep -Milliseconds 100
    }

    Write-Progress -Activity "Processing CSV rows" -Completed

    # Display summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "DEVICE-TO-GROUP ASSIGNMENT SUMMARY" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "CSV rows processed: $($stats.TotalRows)" -InformationAction Continue
    Write-Information "Devices found in Intune: $($stats.DevicesFound)" -InformationAction Continue
    Write-Information "Devices not found: $($stats.DevicesNotFound)" -InformationAction Continue
    Write-Information "Groups created: $($stats.GroupsCreated)" -InformationAction Continue
    Write-Information "Devices added to groups: $($stats.DevicesAdded)" -InformationAction Continue
    Write-Information "Devices skipped (already in group): $($stats.DevicesSkipped)" -InformationAction Continue
    Write-Information "Errors: $($stats.Errors)" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue

    if ($DryRun) {
        Write-Information "`n[DRY RUN] No changes were made" -InformationAction Continue
    }

    Write-Information "`nScript completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph | Out-Null
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
