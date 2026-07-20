<#
.TITLE
    Get App Assignment Conflicts

.SYNOPSIS
    Detects conflicting Intune app assignments: required versus uninstall, and groups that are both included and excluded.

.DESCRIPTION
    This script analyzes every Intune app's assignments and reports conflicts that
    produce unpredictable install behavior: the same app targeted with required and
    uninstall intent, the same group both included and excluded on one app, and the
    same group receiving the app with different intents. Group names are resolved so
    the report is directly actionable. These conflicts commonly appear after mergers
    of app deployments or copy-pasted assignment changes and are hard to spot in the
    portal.

.TAGS
    Apps,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All,Group.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-app-assignment-conflicts.ps1
    Reports all app assignment conflicts in the console

.EXAMPLE
    .\get-app-assignment-conflicts.ps1 -ExportToCsv
    Exports the conflict report to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Required + available for the same group is reported as informational, not a conflict (required wins by design)
    - Nested group membership is not evaluated; only direct assignment targets are compared
    - Uses beta Graph endpoints for the app assignment surface
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
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

    if (-not $GroupId) { return "" }
    if ($script:GroupNameCache.ContainsKey($GroupId)) { return $script:GroupNameCache[$GroupId] }

    $name = $GroupId
    try {
        $group = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/${GroupId}?`$select=displayName" -Method GET
        if ($group.displayName) { $name = $group.displayName }
    }
    catch {
        Write-Verbose "Could not resolve group ${GroupId}: $($_.Exception.Message)"
    }

    $script:GroupNameCache[$GroupId] = $name
    return $name
}

function Get-TargetKey {
    param([object]$Target)

    # Normalize every assignment target to a comparable key
    switch -Wildcard ([string]$Target.'@odata.type') {
        "*allDevicesAssignmentTarget" { return "AllDevices" }
        "*allLicensedUsersAssignmentTarget" { return "AllUsers" }
        default { return [string]$Target.groupId }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving apps with assignments..." -InformationAction Continue
    $apps = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=assignments"

    $assignedApps = @($apps | Where-Object { @($_.assignments).Count -gt 0 })
    Write-Information "✓ Found $($assignedApps.Count) apps with assignments (of $(@($apps).Count) total)" -InformationAction Continue

    [System.Collections.Generic.List[Object]]$conflicts = @()

    foreach ($app in $assignedApps) {
        $assignments = @($app.assignments)

        # Build per-target views of intent and include/exclude
        $includedTargets = @{}
        $excludedTargets = @{}
        $intents = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($assignment in $assignments) {
            $target = $assignment.target
            $targetKey = Get-TargetKey -Target $target
            if (-not $targetKey) { continue }

            $intent = [string]$assignment.intent
            $null = $intents.Add($intent)

            if ([string]$target.'@odata.type' -like "*exclusionGroupAssignmentTarget") {
                $excludedTargets[$targetKey] = $intent
            }
            else {
                if (-not $includedTargets.ContainsKey($targetKey)) {
                    $includedTargets[$targetKey] = [System.Collections.Generic.List[string]]::new()
                }
                $includedTargets[$targetKey].Add($intent)
            }
        }

        $appType = ([string]$app.'@odata.type') -replace "#microsoft.graph.", ""

        # Conflict 1: required and uninstall on the same app
        if ($intents.Contains("required") -and $intents.Contains("uninstall")) {
            $conflicts.Add([PSCustomObject]@{
                    AppName      = $app.displayName
                    AppType      = $appType
                    ConflictType = "RequiredAndUninstall"
                    Details      = "App is deployed with intent 'required' and 'uninstall' at the same time - install outcome depends on target overlap"
                    Group        = ""
                    AppId        = $app.id
                })
        }

        # Conflict 2: same group both included and excluded
        foreach ($targetKey in $includedTargets.Keys) {
            if ($excludedTargets.ContainsKey($targetKey)) {
                $groupName = Resolve-GroupName -GroupId $targetKey
                $conflicts.Add([PSCustomObject]@{
                        AppName      = $app.displayName
                        AppType      = $appType
                        ConflictType = "IncludedAndExcluded"
                        Details      = "Group is both an include target ($($includedTargets[$targetKey] -join ', ')) and an exclude target"
                        Group        = $groupName
                        AppId        = $app.id
                    })
            }
        }

        # Conflict 3: same group targeted with multiple different intents
        foreach ($targetKey in $includedTargets.Keys) {
            $groupIntents = @($includedTargets[$targetKey] | Select-Object -Unique)
            if ($groupIntents.Count -gt 1) {
                $groupName = Resolve-GroupName -GroupId $targetKey
                $severity = if ($groupIntents -contains "uninstall") { "MixedIntentWithUninstall" } else { "MixedIntent" }
                $conflicts.Add([PSCustomObject]@{
                        AppName      = $app.displayName
                        AppType      = $appType
                        ConflictType = $severity
                        Details      = "Same target has intents: $($groupIntents -join ', ')"
                        Group        = $groupName
                        AppId        = $app.id
                    })
            }
        }
    }

    # ----- Display results -----
    Write-Information "`nAPP ASSIGNMENT CONFLICT REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($conflicts.Count -eq 0) {
        Write-Information "`nNo assignment conflicts found." -InformationAction Continue
    }
    else {
        foreach ($conflictGroup in ($conflicts | Group-Object -Property ConflictType | Sort-Object Name)) {
            Write-Information "`n[$($conflictGroup.Name)] $($conflictGroup.Count) finding(s)" -InformationAction Continue
            foreach ($row in ($conflictGroup.Group | Sort-Object AppName)) {
                $line = "  $($row.AppName)"
                if ($row.Group) { $line += " | group: $($row.Group)" }
                Write-Information $line -InformationAction Continue
                Write-Information "    $($row.Details)" -InformationAction Continue
            }
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($assignedApps.Count) assigned apps analyzed, $($conflicts.Count) conflicts found" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "App_Assignment_Conflicts_$timestamp.csv"
        $conflicts | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
