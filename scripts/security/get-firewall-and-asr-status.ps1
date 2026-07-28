<#
.TITLE
    Get Firewall and ASR Status

.SYNOPSIS
    Reports endpoint security policy coverage for firewall, attack surface reduction, and antivirus across the tenant.

.DESCRIPTION
    This script inventories all endpoint security policies (settings catalog policies
    with an endpoint security template plus legacy security intents) and reports the
    coverage per discipline: firewall, attack surface reduction, antivirus, disk
    encryption, EDR, and account protection. It flags disciplines with no assigned
    policy and lists unassigned endpoint security policies. Combined with the device
    count this shows whether the tenant's Windows fleet actually has firewall and ASR
    enforcement or just unassigned policy objects.

.TAGS
    Security,Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.1

.CHANGELOG
    1.1 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.0 - Initial release

.LASTUPDATE
    2026-07-28

.EXAMPLE
    .\get-firewall-and-asr-status.ps1
    Shows endpoint security policy coverage per discipline

.EXAMPLE
    .\get-firewall-and-asr-status.ps1 -ExportToCsv
    Exports the coverage report to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Endpoint security policies are settings catalog policies whose templateReference.templateFamily starts with endpointSecurity; template family filtering happens client-side because the server-side filter is unreliable on this surface
    - Legacy endpoint security intents (deviceManagement/intents) are included for older tenants
    - Coverage means at least one assigned policy per discipline; per-device applicability is not evaluated
    - Uses beta Graph endpoints because settings catalog templates and intents are exposed there
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
        Write-Output "Connecting to Microsoft Graph..."
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Output "✓ Successfully connected to Microsoft Graph"
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

function Get-DisciplineLabel {
    param([string]$TemplateFamily)

    switch -Wildcard ($TemplateFamily) {
        "*Firewall*" { "Firewall" }
        "*AttackSurfaceReduction*" { "Attack Surface Reduction" }
        "*Antivirus*" { "Antivirus" }
        "*DiskEncryption*" { "Disk Encryption" }
        "*EndpointDetectionAndResponse*" { "EDR" }
        "*AccountProtection*" { "Account Protection" }
        "*EndpointPrivilegeManagement*" { "Endpoint Privilege Management" }
        "*ApplicationControl*" { "App Control" }
        default { $TemplateFamily }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Retrieving settings catalog policies..."
    $allPolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments"

    # Server-side templateFamily filters behave inconsistently, so filter locally
    $securityPolicies = @($allPolicies | Where-Object {
            $_.templateReference -and $_.templateReference.templateFamily -like "endpointSecurity*"
        })
    Write-Output "✓ Found $($securityPolicies.Count) endpoint security policies (of $(@($allPolicies).Count) settings catalog policies)"

    Write-Output "Retrieving legacy security intents..."
    $intents = @()
    try {
        $intents = @(Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/intents?`$select=id,displayName,templateId,isAssigned")
        Write-Output "✓ Found $($intents.Count) legacy intents"
    }
    catch {
        Write-Warning "Could not read legacy intents: $($_.Exception.Message)"
    }

    Write-Output "Counting Windows devices..."
    $windowsDevices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=id"
    $windowsDeviceCount = @($windowsDevices).Count
    Write-Output "✓ $windowsDeviceCount Windows devices enrolled"

    # ----- Build per-policy rows -----
    [System.Collections.Generic.List[Object]]$report = @()

    foreach ($policy in $securityPolicies) {
        $discipline = Get-DisciplineLabel -TemplateFamily $policy.templateReference.templateFamily
        $report.Add([PSCustomObject]@{
                PolicyName   = $policy.name
                Discipline   = $discipline
                Source       = "Settings Catalog"
                Template     = $policy.templateReference.templateDisplayName
                Platforms    = $policy.platforms
                IsAssigned   = (@($policy.assignments).Count -gt 0)
                Assignments  = @($policy.assignments).Count
                PolicyId     = $policy.id
            })
    }

    foreach ($intent in $intents) {
        $report.Add([PSCustomObject]@{
                PolicyName   = $intent.displayName
                Discipline   = "Legacy Intent"
                Source       = "Intent (legacy)"
                Template     = $intent.templateId
                Platforms    = ""
                IsAssigned   = [bool]$intent.isAssigned
                Assignments  = ""
                PolicyId     = $intent.id
            })
    }

    # ----- Display results -----
    Write-Output "`nFIREWALL AND ASR STATUS"
    Write-Output ("=" * 50)
    Write-Output "Windows devices enrolled: $windowsDeviceCount | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output ("=" * 50)

    # Coverage per core discipline
    $coreDisciplines = @("Firewall", "Attack Surface Reduction", "Antivirus", "Disk Encryption", "EDR", "Account Protection")
    Write-Output "`nCoverage per discipline:"
    [System.Collections.Generic.List[string]]$gaps = @()

    foreach ($discipline in $coreDisciplines) {
        $disciplinePolicies = @($report | Where-Object { $_.Discipline -eq $discipline })
        $assigned = @($disciplinePolicies | Where-Object { $_.IsAssigned })

        if ($assigned.Count -gt 0) {
            Write-Output "  [COVERED] $($discipline): $($assigned.Count) assigned policy/policies"
        }
        elseif ($disciplinePolicies.Count -gt 0) {
            Write-Output "  [GAP] $($discipline): $($disciplinePolicies.Count) policy/policies exist but none is assigned"
            $gaps.Add($discipline)
        }
        else {
            Write-Output "  [GAP] $($discipline): no policy exists"
            $gaps.Add($discipline)
        }
    }

    # Policy details
    if ($report.Count -gt 0) {
        Write-Output "`nAll endpoint security policies:"
        foreach ($disciplineGroup in ($report | Group-Object -Property Discipline | Sort-Object Name)) {
            Write-Output "`n  $($disciplineGroup.Name):"
            foreach ($row in ($disciplineGroup.Group | Sort-Object PolicyName)) {
                $assignedLabel = if ($row.IsAssigned) { "assigned" } else { "NOT ASSIGNED" }
                Write-Output "    $($row.PolicyName) [$assignedLabel] ($($row.Source))"
            }
        }
    }

    # Summary
    $unassignedCount = @($report | Where-Object { -not $_.IsAssigned }).Count
    Write-Output "`n"
    Write-Output ("=" * 50)
    Write-Output "Summary: $($report.Count) endpoint security policies | $unassignedCount unassigned | gaps: $(if ($gaps.Count -gt 0) { $gaps -join ', ' } else { 'none' })"
    if ($gaps -contains "Firewall" -or $gaps -contains "Attack Surface Reduction") {
        Write-Warning "Firewall or ASR has no assigned policy - $windowsDeviceCount Windows devices are running on local defaults"
    }
    Write-Output ("=" * 50)

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Endpoint_Security_Coverage_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Output "✓ CSV report saved: $csvPath"
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
