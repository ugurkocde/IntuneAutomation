<#
.TITLE
    Get Compliance Policy Coverage

.SYNOPSIS
    Finds device platforms in the tenant that no assigned compliance policy covers.

.DESCRIPTION
    This script compares the platforms of all enrolled Intune devices against the
    platforms targeted by assigned compliance policies. Platforms with enrolled
    devices but no assigned compliance policy are a real gap: those devices report
    as compliant by default (or fall to the built-in policy) and can slip through
    Conditional Access checks. The report also lists compliance policies that exist
    but are not assigned to anything, and the device count per platform so gaps can
    be prioritized.

.TAGS
    Security,Compliance

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-compliance-policy-coverage.ps1
    Shows the platform coverage matrix and any gaps

.EXAMPLE
    .\get-compliance-policy-coverage.ps1 -ExportToCsv
    Exports the coverage report to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Policy platform is derived from the policy's OData type (windows10CompliancePolicy targets Windows, etc.)
    - A platform counts as covered when at least one policy for it has at least one assignment; group scoping within the platform is not evaluated
    - Check the tenant's "Mark devices with no compliance policy assigned as" setting: if it is set to Compliant, uncovered platforms silently pass Conditional Access
    - Uses beta Graph endpoints for consistency with the rest of the library
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
            "DeviceManagementManagedDevices.Read.All"
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

function Get-PolicyPlatform {
    param([string]$ODataType)

    # Compliance policy types map 1:1 to platforms
    switch -Wildcard ($ODataType) {
        "*windows10CompliancePolicy" { "Windows" }
        "*windows81CompliancePolicy" { "Windows" }
        "*macOSCompliancePolicy" { "macOS" }
        "*iosCompliancePolicy" { "iOS/iPadOS" }
        "*androidCompliancePolicy" { "Android" }
        "*androidWorkProfileCompliancePolicy" { "Android" }
        "*androidDeviceOwnerCompliancePolicy" { "Android" }
        "*aospDeviceOwnerCompliancePolicy" { "Android" }
        "*linuxCompliancePolicy" { "Linux" }
        default { ($ODataType -replace "#microsoft.graph.", "") -replace "CompliancePolicy", "" }
    }
}

function Get-DevicePlatform {
    param([string]$OperatingSystem)

    switch -Wildcard ($OperatingSystem) {
        "Windows*" { "Windows" }
        "macOS*" { "macOS" }
        "iOS*" { "iOS/iPadOS" }
        "iPadOS*" { "iOS/iPadOS" }
        "Android*" { "Android" }
        "Linux*" { "Linux" }
        default { $OperatingSystem }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving compliance policies with assignments..." -InformationAction Continue
    $policies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=assignments"
    Write-Information "✓ Found $(@($policies).Count) compliance policies" -InformationAction Continue

    Write-Information "Retrieving managed devices..." -InformationAction Continue
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,operatingSystem,complianceState"
    Write-Information "✓ Found $(@($devices).Count) managed devices" -InformationAction Continue

    # Device counts per platform
    $devicePlatforms = @{}
    foreach ($device in $devices) {
        $platform = Get-DevicePlatform -OperatingSystem ([string]$device.operatingSystem)
        if (-not $devicePlatforms.ContainsKey($platform)) { $devicePlatforms[$platform] = 0 }
        $devicePlatforms[$platform]++
    }

    # Assigned policy counts per platform
    $platformPolicies = @{}
    [System.Collections.Generic.List[Object]]$unassignedPolicies = @()

    foreach ($policy in $policies) {
        $platform = Get-PolicyPlatform -ODataType ([string]$policy.'@odata.type')
        $isAssigned = (@($policy.assignments).Count -gt 0)

        if ($isAssigned) {
            if (-not $platformPolicies.ContainsKey($platform)) {
                $platformPolicies[$platform] = [System.Collections.Generic.List[string]]::new()
            }
            $platformPolicies[$platform].Add($policy.displayName)
        }
        else {
            $unassignedPolicies.Add([PSCustomObject]@{
                    PolicyName = $policy.displayName
                    Platform   = $platform
                })
        }
    }

    # Build coverage matrix
    [System.Collections.Generic.List[Object]]$report = @()
    foreach ($platform in ($devicePlatforms.Keys | Sort-Object)) {
        $assignedPolicyNames = if ($platformPolicies.ContainsKey($platform)) { @($platformPolicies[$platform]) } else { @() }
        $noncompliantCount = @($devices | Where-Object { (Get-DevicePlatform -OperatingSystem ([string]$_.operatingSystem)) -eq $platform -and $_.complianceState -eq "noncompliant" }).Count

        $report.Add([PSCustomObject]@{
                Platform           = $platform
                DeviceCount        = $devicePlatforms[$platform]
                NoncompliantCount  = $noncompliantCount
                AssignedPolicies   = $assignedPolicyNames.Count
                PolicyNames        = ($assignedPolicyNames -join "; ")
                CoverageStatus     = if ($assignedPolicyNames.Count -gt 0) { "Covered" } else { "NOT COVERED" }
            })
    }

    # ----- Display results -----
    Write-Information "`nCOMPLIANCE POLICY COVERAGE" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    foreach ($row in $report) {
        Write-Information "`n[$($row.CoverageStatus)] $($row.Platform)" -InformationAction Continue
        Write-Information "  Devices: $($row.DeviceCount) ($($row.NoncompliantCount) noncompliant)" -InformationAction Continue
        if ($row.AssignedPolicies -gt 0) {
            Write-Information "  Assigned policies: $($row.PolicyNames)" -InformationAction Continue
        }
        else {
            Write-Information "  No assigned compliance policy targets this platform" -InformationAction Continue
        }
    }

    if ($unassignedPolicies.Count -gt 0) {
        Write-Information "`nUnassigned compliance policies:" -InformationAction Continue
        foreach ($row in ($unassignedPolicies | Sort-Object Platform, PolicyName)) {
            Write-Information "  $($row.PolicyName) [$($row.Platform)]" -InformationAction Continue
        }
    }

    # Summary
    $gapPlatforms = @($report | Where-Object { $_.CoverageStatus -eq "NOT COVERED" })
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) platforms with devices, $($gapPlatforms.Count) without compliance coverage, $($unassignedPolicies.Count) unassigned policies" -InformationAction Continue
    if ($gapPlatforms.Count -gt 0) {
        Write-Information "Gap platforms: $(($gapPlatforms | ForEach-Object { $_.Platform }) -join ', ')" -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Compliance_Coverage_$timestamp.csv"
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
