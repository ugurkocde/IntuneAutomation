<#
.TITLE
    Get Assignment Matrix Report

.SYNOPSIS
    Builds a who-gets-what matrix of every Intune policy, profile, script, and app mapped to its assignment targets and filters.

.DESCRIPTION
    This script connects to Microsoft Graph and collects assignments across the major
    Intune surfaces: device configuration profiles, settings catalog policies,
    compliance policies, administrative template (ADMX) policies, platform scripts,
    remediation scripts, and applications. Every assignment is flattened into one row
    showing the target (group, all users, all devices, or exclusion), the resolved
    group name, the assignment filter with its mode, and the install intent for apps.
    The result answers "what does this group actually get" and "what targets this
    device population" in a single CSV.

.TAGS
    Configuration,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All,Group.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-assignment-matrix-report.ps1
    Shows the assignment matrix for all surfaces in the console

.EXAMPLE
    .\get-assignment-matrix-report.ps1 -ExportToCsv
    Exports the full assignment matrix to a timestamped CSV file

.EXAMPLE
    .\get-assignment-matrix-report.ps1 -Surfaces Apps,CompliancePolicies -IncludeUnassigned
    Reports only apps and compliance policies, including objects that have no assignments

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses beta Graph endpoints because several Intune assignment surfaces are not exposed on v1.0
    - Apps without assignments are skipped unless -IncludeUnassigned is used (the app catalog contains many built-in unassigned entries)
    - Group names are resolved once and cached; deleted groups show as their object ID
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Assignment surfaces to include")]
    [ValidateSet("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts", "Remediations", "Apps")]
    [string[]]$Surfaces = @("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts", "Remediations", "Apps"),

    [Parameter(Mandatory = $false, HelpMessage = "Include objects that have no assignments")]
    [switch]$IncludeUnassigned,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [switch]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

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
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementApps.Read.All",
            "Group.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
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

    do {
        try {
            if ($allResults.Count -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET

            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }

            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data: $($_.Exception.Message)"
            break
        }
    } while ($nextLink)

    return $allResults
}

$script:GroupNameCache = @{}

function Resolve-GroupName {
    param([string]$GroupId)

    if ($script:GroupNameCache.ContainsKey($GroupId)) {
        return $script:GroupNameCache[$GroupId]
    }

    $name = $GroupId
    try {
        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/${GroupId}?`$select=displayName" -Method GET
        if ($group.displayName) {
            $name = $group.displayName
        }
    }
    catch {
        Write-Verbose "Could not resolve group ${GroupId}: $($_.Exception.Message)"
    }

    $script:GroupNameCache[$GroupId] = $name
    return $name
}

function ConvertTo-AssignmentRow {
    param(
        [string]$SurfaceName,
        [string]$ObjectName,
        [string]$ObjectId,
        [object]$Assignment,
        [hashtable]$FilterLookup
    )

    $target = $Assignment.target
    $targetType = switch -Wildcard ($target.'@odata.type') {
        "*allDevicesAssignmentTarget" { "All Devices" }
        "*allLicensedUsersAssignmentTarget" { "All Users" }
        "*exclusionGroupAssignmentTarget" { "Excluded Group" }
        "*groupAssignmentTarget" { "Included Group" }
        default { $target.'@odata.type' -replace "#microsoft.graph.", "" }
    }

    $groupName = ""
    if ($target.groupId) {
        $groupName = Resolve-GroupName -GroupId $target.groupId
    }

    $filterName = ""
    $filterType = ""
    if ($target.deviceAndAppManagementAssignmentFilterId -and $target.deviceAndAppManagementAssignmentFilterType -ne "none") {
        $filterType = $target.deviceAndAppManagementAssignmentFilterType
        $filterName = if ($FilterLookup.ContainsKey($target.deviceAndAppManagementAssignmentFilterId)) {
            $FilterLookup[$target.deviceAndAppManagementAssignmentFilterId]
        }
        else {
            $target.deviceAndAppManagementAssignmentFilterId
        }
    }

    return [PSCustomObject]@{
        Surface    = $SurfaceName
        Name       = $ObjectName
        ObjectId   = $ObjectId
        TargetType = $targetType
        GroupName  = $groupName
        GroupId    = if ($target.groupId) { $target.groupId } else { "" }
        Intent     = if ($Assignment.intent) { $Assignment.intent } else { "" }
        FilterName = $filterName
        FilterMode = $filterType
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Building assignment matrix..." -InformationAction Continue

    # Filter names are needed for every row, so fetch them once up front
    $filterLookup = @{}
    try {
        $filters = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters?`$select=id,displayName"
        foreach ($filter in $filters) {
            $filterLookup[$filter.id] = $filter.displayName
        }
        Write-Information "✓ Loaded $(@($filters).Count) assignment filters" -InformationAction Continue
    }
    catch {
        Write-Warning "Could not load assignment filters, filter names will show as IDs: $($_.Exception.Message)"
    }

    # Each surface definition: list endpoint plus how to read the display name
    $surfaceDefinitions = @(
        @{ Key = "DeviceConfigurations"; Label = "Configuration Profile"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "SettingsCatalog"; Label = "Settings Catalog Policy"; Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments"; NameProperty = "name" },
        @{ Key = "CompliancePolicies"; Label = "Compliance Policy"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "AdmxPolicies"; Label = "Administrative Template"; Uri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "PlatformScripts"; Label = "PowerShell Script"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "PlatformScripts"; Label = "Shell Script (macOS)"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "Remediations"; Label = "Remediation Script"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Key = "Apps"; Label = "Application"; Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=assignments"; NameProperty = "displayName" }
    )

    [System.Collections.Generic.List[Object]]$matrix = @()
    $unassignedCount = 0

    foreach ($surface in $surfaceDefinitions) {
        if ($Surfaces -notcontains $surface.Key) {
            continue
        }

        Write-Information "Collecting: $($surface.Label)..." -InformationAction Continue
        $objects = Get-MgGraphAllPage -Uri $surface.Uri

        foreach ($object in $objects) {
            $objectName = $object.($surface.NameProperty)
            $assignments = @($object.assignments)

            if ($assignments.Count -eq 0) {
                $unassignedCount++
                if ($IncludeUnassigned) {
                    $matrix.Add([PSCustomObject]@{
                            Surface    = $surface.Label
                            Name       = $objectName
                            ObjectId   = $object.id
                            TargetType = "Not assigned"
                            GroupName  = ""
                            GroupId    = ""
                            Intent     = ""
                            FilterName = ""
                            FilterMode = ""
                        })
                }
                continue
            }

            foreach ($assignment in $assignments) {
                $matrix.Add((ConvertTo-AssignmentRow -SurfaceName $surface.Label -ObjectName $objectName -ObjectId $object.id -Assignment $assignment -FilterLookup $filterLookup))
            }
        }

        Write-Information "✓ $($surface.Label): $(@($objects).Count) objects" -InformationAction Continue
    }

    # Display results grouped by surface
    Write-Information "`nASSIGNMENT MATRIX" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    foreach ($surfaceGroup in ($matrix | Group-Object -Property Surface | Sort-Object Name)) {
        Write-Information "`n$($surfaceGroup.Name) ($($surfaceGroup.Count) assignments)" -InformationAction Continue

        foreach ($row in ($surfaceGroup.Group | Sort-Object Name)) {
            $targetInfo = $row.TargetType
            if ($row.GroupName) { $targetInfo += ": $($row.GroupName)" }
            if ($row.Intent) { $targetInfo += " [$($row.Intent)]" }
            if ($row.FilterName) { $targetInfo += " (filter: $($row.FilterName)/$($row.FilterMode))" }
            Write-Information "  $($row.Name) -> $targetInfo" -InformationAction Continue
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($matrix.Count) assignment rows, $($script:GroupNameCache.Count) unique groups, $unassignedCount unassigned objects" -InformationAction Continue
    if (-not $IncludeUnassigned -and $unassignedCount -gt 0) {
        Write-Information "Tip: run with -IncludeUnassigned to list the $unassignedCount unassigned objects" -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Intune_Assignment_Matrix_$timestamp.csv"
        $matrix | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
