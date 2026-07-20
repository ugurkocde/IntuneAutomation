<#
.TITLE
    Get Policy Drift Report

.SYNOPSIS
    Compares current Intune policies against a baseline backup and reports every added, removed, or changed policy.

.DESCRIPTION
    This script takes a baseline folder created by backup-intune-configuration.ps1 and
    compares the tenant's current state against it: settings catalog policies (full
    setting bodies), classic device configuration profiles, and compliance policies.
    Policies are matched by object ID, and their configuration is compared as
    normalized JSON with volatile properties (timestamps, versions) removed. The
    report shows policies that were added, deleted, or modified since the baseline,
    making unreviewed configuration drift visible for change control.

.TAGS
    Configuration,Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-policy-drift-report.ps1 -BaselinePath ".\IntuneConfigBackup_2026-07-01_08-00-00"
    Compares the current tenant state against the July 1st baseline

.EXAMPLE
    .\get-policy-drift-report.ps1 -BaselinePath ".\IntuneConfigBackup_2026-07-01_08-00-00" -ExportToCsv
    Exports the drift report to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - The baseline must be a folder created by backup-intune-configuration.ps1
    - Policies are matched by ID, so a policy that was deleted and recreated appears as one deletion plus one addition
    - Timestamps, version counters, and assignment state are excluded from the comparison; only configuration content counts as drift
    - Uses beta Graph endpoints because the full Intune configuration surface is not exposed on v1.0
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to a baseline folder created by backup-intune-configuration.ps1")]
    [ValidateNotNullOrEmpty()]
    [string]$BaselinePath,

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
            "DeviceManagementConfiguration.Read.All"
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

function ConvertTo-NormalizedJson {
    param([object]$InputObject)

    # Volatile properties change without any admin action; excluding them keeps
    # the comparison focused on actual configuration content
    $volatileProperties = @(
        "lastModifiedDateTime", "createdDateTime", "version", "settingCount",
        "assignments", "supportsScopeTags", "priorityMetaData", "creationSource"
    )

    $clone = $InputObject | ConvertTo-Json -Depth 30 | ConvertFrom-Json

    foreach ($property in $volatileProperties) {
        if ($clone.PSObject.Properties[$property]) {
            $clone.PSObject.Properties.Remove($property)
        }
    }
    foreach ($property in @($clone.PSObject.Properties.Name)) {
        if ($property -like "*@odata.context" -or $property -like "*@odata.count") {
            $clone.PSObject.Properties.Remove($property)
        }
    }

    return ($clone | ConvertTo-Json -Depth 30)
}

function Compare-PolicyArea {
    param(
        [string]$AreaLabel,
        [string]$BaselineFolder,
        [object[]]$CurrentPolicies,
        [string]$NameProperty
    )

    $rows = [System.Collections.Generic.List[Object]]::new()

    $baselineFiles = @()
    $folder = Join-Path $BaselinePath $BaselineFolder
    if (Test-Path $folder) {
        $baselineFiles = @(Get-ChildItem -Path $folder -Filter "*.json" -File)
    }
    else {
        Write-Warning "Baseline folder '$BaselineFolder' not found - every current $AreaLabel will appear as added"
    }

    $baselineById = @{}
    foreach ($file in $baselineFiles) {
        $baselineObject = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
        if ($baselineObject.id) {
            $baselineById[$baselineObject.id] = $baselineObject
        }
    }

    $currentById = @{}
    foreach ($policy in $CurrentPolicies) {
        $currentById[$policy.id] = $policy
    }

    # Added and modified
    foreach ($policy in $CurrentPolicies) {
        $policyName = $policy.$NameProperty
        if (-not $baselineById.ContainsKey($policy.id)) {
            $rows.Add([PSCustomObject]@{
                    Area         = $AreaLabel
                    Name         = $policyName
                    ObjectId     = $policy.id
                    ChangeType   = "Added"
                    LastModified = $policy.lastModifiedDateTime
                })
            continue
        }

        $baselineJson = ConvertTo-NormalizedJson -InputObject $baselineById[$policy.id]
        $currentJson = ConvertTo-NormalizedJson -InputObject $policy
        if ($baselineJson -ne $currentJson) {
            $rows.Add([PSCustomObject]@{
                    Area         = $AreaLabel
                    Name         = $policyName
                    ObjectId     = $policy.id
                    ChangeType   = "Modified"
                    LastModified = $policy.lastModifiedDateTime
                })
        }
    }

    # Deleted
    foreach ($baselineId in $baselineById.Keys) {
        if (-not $currentById.ContainsKey($baselineId)) {
            $baselineObject = $baselineById[$baselineId]
            $rows.Add([PSCustomObject]@{
                    Area         = $AreaLabel
                    Name         = $baselineObject.$NameProperty
                    ObjectId     = $baselineId
                    ChangeType   = "Deleted"
                    LastModified = ""
                })
        }
    }

    return $rows
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    if (-not (Test-Path $BaselinePath)) {
        throw "Baseline path '$BaselinePath' does not exist"
    }

    $manifestPath = Join-Path $BaselinePath "manifest.json"
    if (Test-Path $manifestPath) {
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        Write-Information "Baseline taken: $($manifest.backupDate)" -InformationAction Continue
    }
    else {
        Write-Warning "No manifest.json found - is '$BaselinePath' a backup created by backup-intune-configuration.ps1?"
    }

    Write-Information "Fetching current tenant state..." -InformationAction Continue

    # Settings catalog policies need their setting bodies for a meaningful comparison
    $settingsCatalogPolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
    foreach ($policy in $settingsCatalogPolicies) {
        $settings = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/settings"
        $policy | Add-Member -MemberType NoteProperty -Name "settings" -Value @($settings) -Force
    }
    Write-Information "✓ Loaded $(@($settingsCatalogPolicies).Count) settings catalog policies" -InformationAction Continue

    $deviceConfigurations = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    Write-Information "✓ Loaded $(@($deviceConfigurations).Count) device configuration profiles" -InformationAction Continue

    $compliancePolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
    Write-Information "✓ Loaded $(@($compliancePolicies).Count) compliance policies" -InformationAction Continue

    # ----- Compare against baseline -----
    Write-Information "Comparing against baseline..." -InformationAction Continue

    [System.Collections.Generic.List[Object]]$drift = @()
    $drift.AddRange((Compare-PolicyArea -AreaLabel "Settings Catalog" -BaselineFolder "SettingsCatalog" -CurrentPolicies @($settingsCatalogPolicies) -NameProperty "name"))
    $drift.AddRange((Compare-PolicyArea -AreaLabel "Configuration Profile" -BaselineFolder "DeviceConfigurations" -CurrentPolicies @($deviceConfigurations) -NameProperty "displayName"))
    $drift.AddRange((Compare-PolicyArea -AreaLabel "Compliance Policy" -BaselineFolder "CompliancePolicies" -CurrentPolicies @($compliancePolicies) -NameProperty "displayName"))

    # ----- Display results -----
    Write-Information "`nPOLICY DRIFT REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Baseline: $BaselinePath" -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($drift.Count -eq 0) {
        Write-Information "`nNo drift detected - the tenant matches the baseline." -InformationAction Continue
    }
    else {
        foreach ($changeGroup in ($drift | Group-Object -Property ChangeType | Sort-Object Name)) {
            Write-Information "`n$($changeGroup.Name) ($($changeGroup.Count))" -InformationAction Continue
            foreach ($row in ($changeGroup.Group | Sort-Object Area, Name)) {
                $detail = "  [$($row.Area)] $($row.Name)"
                if ($row.LastModified -and $row.ChangeType -eq "Modified") {
                    $detail += " (modified: $($row.LastModified))"
                }
                Write-Information $detail -InformationAction Continue
            }
        }
    }

    # Summary
    $addedCount = @($drift | Where-Object { $_.ChangeType -eq "Added" }).Count
    $modifiedCount = @($drift | Where-Object { $_.ChangeType -eq "Modified" }).Count
    $deletedCount = @($drift | Where-Object { $_.ChangeType -eq "Deleted" }).Count

    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $addedCount added, $modifiedCount modified, $deletedCount deleted" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Intune_Policy_Drift_$timestamp.csv"
        $drift | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
