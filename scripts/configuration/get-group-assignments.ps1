<#
.TITLE
    Get Group Assignments

.SYNOPSIS
    Lists everything Intune assigns to a specific Entra ID group: profiles, policies, scripts, and apps.

.DESCRIPTION
    This script takes an Entra ID group (by display name or object ID) and scans all
    major Intune assignment surfaces to show exactly what that group receives:
    device configuration profiles, settings catalog policies, compliance policies,
    administrative template (ADMX) policies, platform scripts, remediation scripts,
    and applications with their install intents. Exclusion assignments are flagged,
    and tenant-wide All Users / All Devices assignments can be included to show the
    complete effective surface for members of the group.

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
    .\get-group-assignments.ps1 -GroupName "Sales Devices"
    Lists everything assigned to the group named Sales Devices

.EXAMPLE
    .\get-group-assignments.ps1 -GroupId "d0eea876-63b4-4e74-bff8-d11daf12b2f3" -IncludeTenantWide
    Lists group assignments plus tenant-wide All Users / All Devices assignments

.EXAMPLE
    .\get-group-assignments.ps1 -GroupName "Pilot Users" -ExportToCsv
    Exports the group's assignment list to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses beta Graph endpoints because several Intune assignment surfaces are not exposed on v1.0
    - Group name lookup must match exactly one group; use -GroupId when names are ambiguous
    - Nested group inheritance is not evaluated; only direct assignments to the given group are shown
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(DefaultParameterSetName = "ByName")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByName", HelpMessage = "Display name of the Entra ID group")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $true, ParameterSetName = "ById", HelpMessage = "Object ID of the Entra ID group")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupId,

    [Parameter(Mandatory = $false, HelpMessage = "Also list tenant-wide All Users / All Devices assignments")]
    [switch]$IncludeTenantWide,

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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    # ----- Resolve the group -----
    if ($PSCmdlet.ParameterSetName -eq "ByName") {
        Write-Information "Resolving group '$GroupName'..." -InformationAction Continue
        $escapedName = $GroupName -replace "'", "''"
        $groups = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq '$escapedName'&`$select=id,displayName"

        if (@($groups).Count -eq 0) {
            throw "No group found with display name '$GroupName'"
        }
        if (@($groups).Count -gt 1) {
            throw "Multiple groups found with display name '$GroupName' - use -GroupId instead"
        }

        $group = @($groups)[0]
        $GroupId = $group.id
    }
    else {
        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/${GroupId}?`$select=id,displayName" -Method GET
    }

    Write-Information "✓ Group: $($group.displayName) ($GroupId)" -InformationAction Continue

    # ----- Scan all assignment surfaces -----
    $surfaceDefinitions = @(
        @{ Label = "Configuration Profile"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "Settings Catalog Policy"; Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments"; NameProperty = "name" },
        @{ Label = "Compliance Policy"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "Administrative Template"; Uri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "PowerShell Script"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "Shell Script (macOS)"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "Remediation Script"; Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$expand=assignments"; NameProperty = "displayName" },
        @{ Label = "Application"; Uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=assignments"; NameProperty = "displayName" }
    )

    [System.Collections.Generic.List[Object]]$results = @()

    foreach ($surface in $surfaceDefinitions) {
        Write-Information "Scanning: $($surface.Label)..." -InformationAction Continue
        $objects = Get-MgGraphAllPage -Uri $surface.Uri

        foreach ($object in $objects) {
            foreach ($assignment in @($object.assignments)) {
                $target = $assignment.target
                $targetODataType = [string]$target.'@odata.type'

                $isGroupMatch = $target.groupId -eq $GroupId
                $isTenantWide = $targetODataType -like "*allDevicesAssignmentTarget" -or $targetODataType -like "*allLicensedUsersAssignmentTarget"

                if (-not $isGroupMatch -and -not ($IncludeTenantWide -and $isTenantWide)) {
                    continue
                }

                $assignmentKind = if ($targetODataType -like "*exclusionGroupAssignmentTarget") {
                    "Excluded"
                }
                elseif ($targetODataType -like "*allDevicesAssignmentTarget") {
                    "All Devices"
                }
                elseif ($targetODataType -like "*allLicensedUsersAssignmentTarget") {
                    "All Users"
                }
                else {
                    "Included"
                }

                $results.Add([PSCustomObject]@{
                        Surface    = $surface.Label
                        Name       = $object.($surface.NameProperty)
                        ObjectId   = $object.id
                        Assignment = $assignmentKind
                        Intent     = if ($assignment.intent) { $assignment.intent } else { "" }
                        FilterMode = if ($target.deviceAndAppManagementAssignmentFilterType -and $target.deviceAndAppManagementAssignmentFilterType -ne "none") { $target.deviceAndAppManagementAssignmentFilterType } else { "" }
                    })
            }
        }
    }

    # ----- Display results -----
    Write-Information "`nASSIGNMENTS FOR GROUP: $($group.displayName)" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($results.Count -eq 0) {
        Write-Information "`nNothing is assigned to this group." -InformationAction Continue
        if (-not $IncludeTenantWide) {
            Write-Information "Tip: run with -IncludeTenantWide to also see All Users / All Devices assignments." -InformationAction Continue
        }
    }
    else {
        foreach ($surfaceGroup in ($results | Group-Object -Property Surface | Sort-Object Name)) {
            Write-Information "`n$($surfaceGroup.Name) ($($surfaceGroup.Count))" -InformationAction Continue
            foreach ($row in ($surfaceGroup.Group | Sort-Object Name)) {
                $details = $row.Assignment
                if ($row.Intent) { $details += ", intent: $($row.Intent)" }
                if ($row.FilterMode) { $details += ", filter: $($row.FilterMode)" }
                Write-Information "  $($row.Name) [$details]" -InformationAction Continue
            }
        }
    }

    # Summary
    $excludedCount = @($results | Where-Object { $_.Assignment -eq "Excluded" }).Count
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($results.Count) assignments ($excludedCount exclusions)" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $safeGroupName = ($group.displayName -replace '[\\/:*?"<>|]', '_')
        $csvPath = Join-Path $OutputPath "Group_Assignments_${safeGroupName}_$timestamp.csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
