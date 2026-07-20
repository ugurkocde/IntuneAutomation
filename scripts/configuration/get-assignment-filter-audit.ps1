<#
.TITLE
    Get Assignment Filter Audit

.SYNOPSIS
    Audits Intune assignment filters and reports filters that are unused or duplicated.

.DESCRIPTION
    This script retrieves all Intune assignment filters and cross-references them
    against every assignment surface that can carry a filter: device configuration
    profiles, settings catalog policies, compliance policies, administrative template
    policies, platform scripts, remediation scripts, and applications. It reports
    which filters are actually referenced by at least one assignment, which are
    unused, and which filters duplicate each other (same platform and same rule),
    so stale or redundant filters can be cleaned up safely.

.TAGS
    Configuration,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-assignment-filter-audit.ps1
    Shows the filter audit in the console

.EXAMPLE
    .\get-assignment-filter-audit.ps1 -ExportToCsv
    Exports the filter audit to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses beta Graph endpoints because assignment filters are not exposed on v1.0
    - A filter is counted as used when at least one assignment references it in include or exclude mode
    - Duplicate detection compares platform plus whitespace-normalized rule text
    - The script only reports; deleting filters remains a manual decision
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
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementApps.Read.All"
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
    Write-Information "Retrieving assignment filters..." -InformationAction Continue
    $filters = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"

    if (@($filters).Count -eq 0) {
        Write-Information "No assignment filters exist in this tenant." -InformationAction Continue
        return
    }
    Write-Information "✓ Found $(@($filters).Count) assignment filters" -InformationAction Continue

    # ----- Collect filter references from every assignment surface -----
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

    # filterId -> list of "surface: object name (mode)" strings
    $filterUsage = @{}

    foreach ($surface in $surfaceDefinitions) {
        Write-Information "Scanning: $($surface.Label)..." -InformationAction Continue
        $objects = Get-MgGraphAllPage -Uri $surface.Uri

        foreach ($object in $objects) {
            foreach ($assignment in @($object.assignments)) {
                $target = $assignment.target
                $filterId = $target.deviceAndAppManagementAssignmentFilterId
                $filterMode = $target.deviceAndAppManagementAssignmentFilterType

                if ($filterId -and $filterMode -and $filterMode -ne "none") {
                    if (-not $filterUsage.ContainsKey($filterId)) {
                        $filterUsage[$filterId] = [System.Collections.Generic.List[string]]::new()
                    }
                    $filterUsage[$filterId].Add("$($surface.Label): $($object.($surface.NameProperty)) ($filterMode)")
                }
            }
        }
    }

    # ----- Detect duplicates (same platform + normalized rule) -----
    $duplicateLookup = @{}
    foreach ($filter in $filters) {
        $normalizedRule = ([string]$filter.rule -replace '\s+', ' ').Trim().ToLowerInvariant()
        $duplicateKey = "$($filter.platform)|$normalizedRule"
        if (-not $duplicateLookup.ContainsKey($duplicateKey)) {
            $duplicateLookup[$duplicateKey] = [System.Collections.Generic.List[string]]::new()
        }
        $duplicateLookup[$duplicateKey].Add($filter.displayName)
    }

    # ----- Build report -----
    [System.Collections.Generic.List[Object]]$report = @()
    foreach ($filter in $filters) {
        $usage = if ($filterUsage.ContainsKey($filter.id)) { $filterUsage[$filter.id] } else { @() }
        $normalizedRule = ([string]$filter.rule -replace '\s+', ' ').Trim().ToLowerInvariant()
        $duplicateKey = "$($filter.platform)|$normalizedRule"
        $duplicateNames = @($duplicateLookup[$duplicateKey] | Where-Object { $_ -ne $filter.displayName })

        $report.Add([PSCustomObject]@{
                FilterName     = $filter.displayName
                FilterId       = $filter.id
                Platform       = $filter.platform
                ManagementType = $filter.assignmentFilterManagementType
                Rule           = $filter.rule
                UsageCount     = @($usage).Count
                UsedBy         = (@($usage) -join "; ")
                IsUnused       = (@($usage).Count -eq 0)
                DuplicateOf    = ($duplicateNames -join "; ")
            })
    }

    # ----- Display results -----
    Write-Information "`nASSIGNMENT FILTER AUDIT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    $unusedFilters = @($report | Where-Object { $_.IsUnused })
    $duplicateFilters = @($report | Where-Object { $_.DuplicateOf })

    Write-Information "`nUsed filters:" -InformationAction Continue
    foreach ($row in ($report | Where-Object { -not $_.IsUnused } | Sort-Object FilterName)) {
        Write-Information "  $($row.FilterName) [$($row.Platform)] - $($row.UsageCount) references" -InformationAction Continue
        foreach ($reference in ($row.UsedBy -split "; ")) {
            Write-Information "    - $reference" -InformationAction Continue
        }
    }

    if ($unusedFilters.Count -gt 0) {
        Write-Information "`nUnused filters (candidates for cleanup):" -InformationAction Continue
        foreach ($row in ($unusedFilters | Sort-Object FilterName)) {
            Write-Information "  $($row.FilterName) [$($row.Platform)] - rule: $($row.Rule)" -InformationAction Continue
        }
    }

    if ($duplicateFilters.Count -gt 0) {
        Write-Information "`nDuplicate filters (same platform and rule):" -InformationAction Continue
        foreach ($row in ($duplicateFilters | Sort-Object FilterName)) {
            Write-Information "  $($row.FilterName) duplicates: $($row.DuplicateOf)" -InformationAction Continue
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $(@($filters).Count) filters, $($unusedFilters.Count) unused, $($duplicateFilters.Count) involved in duplicates" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Intune_Filter_Audit_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
