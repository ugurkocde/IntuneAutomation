<#
.TITLE
    Unassigned Policies Monitor

.SYNOPSIS
    Identify and report on all unassigned policies in Microsoft Intune.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all device configuration policies
    configured in Intune, then checks which policies have no assignments to users, groups,
    or devices. Unassigned policies represent potential configuration drift, unused resources,
    or incomplete policy deployment. The script generates detailed reports in CSV format,
    highlighting unassigned policies with creation dates, policy types, and recommendations.
    This helps administrators maintain clean policy governance and identify policies that
    may need assignment or removal.

.TAGS
    Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Added a small delay between per-policy assignment checks to respect rate limits; policy list queries now select only needed fields; output directory is created automatically before the CSV export; pagination helper keeps single-item results as arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\check-unassigned-policies.ps1
    Generates a report of all unassigned policies

.EXAMPLE
    .\check-unassigned-policies.ps1 -OutputPath "C:\Reports" -IncludeDetails "true"
    Generates a detailed report and saves to specified directory

.EXAMPLE
    .\check-unassigned-policies.ps1 -CreatedWithinDays 7
    Generates report for policies created in the last 7 days

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Requires appropriate permissions in Azure AD
    - Checks all policy types: Device Configuration, Settings Catalog, Administrative Templates
    - Unassigned policies may indicate incomplete deployment or unused configurations
    - Regular monitoring helps maintain policy governance and compliance
    - Consider removing or assigning policies that have been unassigned for extended periods
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Include detailed policy information")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeDetails,

    [Parameter(Mandatory = $false, HelpMessage = "Show only policies created in the last N days")]
    [ValidateRange(1, 365)]
    [int]$CreatedWithinDays = 0,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
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
foreach ($runbookBooleanParameter in @('IncludeDetails')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)

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
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph"
    }
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API
function Get-MgGraphAllPage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $AllResults = @()
    $NextLink = $Uri
    $RequestCount = 0

    do {
        try {
            # Add delay to respect rate limits
            if ($RequestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $Response = Invoke-MgGraphRequest -Uri $NextLink -Method GET
            $RequestCount++

            if ($Response.value) {
                $AllResults += $Response.value
            }
            else {
                $AllResults += $Response
            }

            $NextLink = $Response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            throw "Error fetching data from $NextLink : $($_.Exception.Message)"
        }
    } while ($NextLink)

    # Comma prevents unrolling so single-element results stay arrays
    return , $AllResults
}

# Function to get policy assignments
function Get-PolicyAssignment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyType
    )

    try {
        switch ($PolicyType) {
            "DeviceConfiguration" {
                $AssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('$PolicyId')/assignments"
            }
            "ConfigurationPolicy" {
                $AssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assignments"
            }
            "GroupPolicyConfiguration" {
                $AssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$PolicyId')/assignments"
            }
            default {
                $AssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('$PolicyId')/assignments"
            }
        }

        $Assignments = Get-MgGraphAllPage -Uri $AssignmentsUri
        return $Assignments
    }
    catch {
        Write-Warning "Failed to get assignments for policy $PolicyId : $($_.Exception.Message)"
        return @()
    }
}

# Function to determine policy risk level
function Get-PolicyRiskLevel {
    param(
        [string]$PolicyName,
        [datetime]$CreatedDateTime,
        [string]$PolicyType
    )

    $DaysOld = (Get-Date) - $CreatedDateTime

    # High risk: Security-related policies that are unassigned
    if ($PolicyName -match "(Security|Firewall|BitLocker|Defender|Encryption|Password|PIN)") {
        return "High"
    }

    # High risk: Compliance policies that are unassigned
    if ($PolicyType -match "(Compliance|DeviceCompliance)") {
        return "High"
    }

    # Medium risk: Policies older than 30 days
    if ($DaysOld.Days -gt 30) {
        return "Medium"
    }

    # Low risk: Recently created policies
    return "Low"
}

# Function to format policy details
function Format-PolicyDetail {
    param(
        [object]$Policy,
        [string]$PolicyType
    )

    $Details = @()

    if ($PolicyType -eq "ConfigurationPolicy" -and $Policy.templateReference) {
        $Details += "Template: $($Policy.templateReference.templateDisplayName)"
        $Details += "Template Version: $($Policy.templateReference.templateDisplayVersion)"
    }

    if ($Policy.platforms) {
        $Details += "Platforms: $($Policy.platforms -join ', ')"
    }

    if ($Policy.technologies) {
        $Details += "Technologies: $($Policy.technologies -join ', ')"
    }

    if ($Policy.settingCount) {
        $Details += "Settings Count: $($Policy.settingCount)"
    }

    return $Details -join "; "
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Starting unassigned policies analysis..."

    # Calculate filter date if specified
    $FilterDate = $null
    if ($CreatedWithinDays -gt 0) {
        $FilterDate = (Get-Date).AddDays(-$CreatedWithinDays)
        Write-Output "Filtering policies created after: $($FilterDate.ToString('yyyy-MM-dd'))"
    }

    # ========================================================================
    # GET ALL DEVICE CONFIGURATION POLICIES
    # ========================================================================

    Write-Output "Retrieving device configuration policies..."

    $AllUnassignedPolicies = @()

    try {
        # Get traditional device configuration policies
        $DeviceConfigUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,description,createdDateTime,lastModifiedDateTime"
        $DeviceConfigurations = Get-MgGraphAllPage -Uri $DeviceConfigUri
        Write-Output "Retrieved $($DeviceConfigurations.Count) device configuration policies"

        # Get Settings Catalog policies (settings catalog uses name instead of displayName)
        $ConfigPoliciesUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name,description,createdDateTime,lastModifiedDateTime,templateReference,platforms,technologies,settingCount"
        $ConfigurationPolicies = Get-MgGraphAllPage -Uri $ConfigPoliciesUri
        Write-Output "Retrieved $($ConfigurationPolicies.Count) settings catalog policies"

        # Get Administrative Templates (Group Policy Configurations)
        $GroupPolicyUri = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$select=id,displayName,description,createdDateTime,lastModifiedDateTime"
        $GroupPolicyConfigurations = Get-MgGraphAllPage -Uri $GroupPolicyUri
        Write-Output "Retrieved $($GroupPolicyConfigurations.Count) administrative template policies"
    }
    catch {
        Write-Error "Failed to retrieve policies: $($_.Exception.Message)"
        exit 1
    }

    # ========================================================================
    # CHECK ASSIGNMENTS FOR EACH POLICY TYPE
    # ========================================================================

    Write-Output "Checking policy assignments..."

    # Check Device Configuration Policies
    Write-Output "Analyzing device configuration policies..."
    foreach ($Policy in $DeviceConfigurations) {
        try {
            # Apply date filter if specified
            if ($FilterDate -and $Policy.createdDateTime) {
                $CreatedDate = [datetime]$Policy.createdDateTime
                if ($CreatedDate -lt $FilterDate) {
                    continue
                }
            }

            # Delay between per-policy assignment checks to respect rate limits
            Start-Sleep -Milliseconds 100
            $Assignments = Get-PolicyAssignment -PolicyId $Policy.id -PolicyType "DeviceConfiguration"

            if ($Assignments.Count -eq 0) {
                $RiskLevel = Get-PolicyRiskLevel -PolicyName $Policy.displayName -CreatedDateTime ([datetime]$Policy.createdDateTime) -PolicyType "DeviceConfiguration"
                $Details = if ($IncludeDetails) { Format-PolicyDetail -Policy $Policy -PolicyType "DeviceConfiguration" } else { "" }

                $UnassignedPolicy = [PSCustomObject]@{
                    PolicyName      = $Policy.displayName
                    PolicyType      = "Device Configuration"
                    PolicySubType   = $Policy.'@odata.type' -replace '#microsoft.graph.', ''
                    CreatedDateTime = $Policy.createdDateTime
                    LastModified    = $Policy.lastModifiedDateTime
                    RiskLevel       = $RiskLevel
                    Description     = $Policy.description
                    Details         = $Details
                    PolicyId        = $Policy.id
                }
                $AllUnassignedPolicies += $UnassignedPolicy
            }
        }
        catch {
            Write-Warning "Error processing device configuration policy '$($Policy.displayName)': $($_.Exception.Message)"
            continue
        }
    }

    # Check Settings Catalog Policies
    Write-Output "Analyzing settings catalog policies..."
    foreach ($Policy in $ConfigurationPolicies) {
        try {
            # Apply date filter if specified
            if ($FilterDate -and $Policy.createdDateTime) {
                $CreatedDate = [datetime]$Policy.createdDateTime
                if ($CreatedDate -lt $FilterDate) {
                    continue
                }
            }

            # Delay between per-policy assignment checks to respect rate limits
            Start-Sleep -Milliseconds 100
            $Assignments = Get-PolicyAssignment -PolicyId $Policy.id -PolicyType "ConfigurationPolicy"

            if ($Assignments.Count -eq 0) {
                $RiskLevel = Get-PolicyRiskLevel -PolicyName $Policy.name -CreatedDateTime ([datetime]$Policy.createdDateTime) -PolicyType "ConfigurationPolicy"
                $Details = if ($IncludeDetails) { Format-PolicyDetail -Policy $Policy -PolicyType "ConfigurationPolicy" } else { "" }

                $UnassignedPolicy = [PSCustomObject]@{
                    PolicyName      = $Policy.name
                    PolicyType      = "Settings Catalog"
                    PolicySubType   = if ($Policy.templateReference) { $Policy.templateReference.templateDisplayName } else { "Custom" }
                    CreatedDateTime = $Policy.createdDateTime
                    LastModified    = $Policy.lastModifiedDateTime
                    RiskLevel       = $RiskLevel
                    Description     = $Policy.description
                    Details         = $Details
                    PolicyId        = $Policy.id
                }
                $AllUnassignedPolicies += $UnassignedPolicy
            }
        }
        catch {
            Write-Warning "Error processing settings catalog policy '$($Policy.name)': $($_.Exception.Message)"
            continue
        }
    }

    # Check Administrative Template Policies
    Write-Output "Analyzing administrative template policies..."
    foreach ($Policy in $GroupPolicyConfigurations) {
        try {
            # Apply date filter if specified
            if ($FilterDate -and $Policy.createdDateTime) {
                $CreatedDate = [datetime]$Policy.createdDateTime
                if ($CreatedDate -lt $FilterDate) {
                    continue
                }
            }

            # Delay between per-policy assignment checks to respect rate limits
            Start-Sleep -Milliseconds 100
            $Assignments = Get-PolicyAssignment -PolicyId $Policy.id -PolicyType "GroupPolicyConfiguration"

            if ($Assignments.Count -eq 0) {
                $RiskLevel = Get-PolicyRiskLevel -PolicyName $Policy.displayName -CreatedDateTime ([datetime]$Policy.createdDateTime) -PolicyType "GroupPolicyConfiguration"
                $Details = if ($IncludeDetails) { Format-PolicyDetail -Policy $Policy -PolicyType "GroupPolicyConfiguration" } else { "" }

                $UnassignedPolicy = [PSCustomObject]@{
                    PolicyName      = $Policy.displayName
                    PolicyType      = "Administrative Template"
                    PolicySubType   = "Group Policy"
                    CreatedDateTime = $Policy.createdDateTime
                    LastModified    = $Policy.lastModifiedDateTime
                    RiskLevel       = $RiskLevel
                    Description     = $Policy.description
                    Details         = $Details
                    PolicyId        = $Policy.id
                }
                $AllUnassignedPolicies += $UnassignedPolicy
            }
        }
        catch {
            Write-Warning "Error processing administrative template policy '$($Policy.displayName)': $($_.Exception.Message)"
            continue
        }
    }

    # ========================================================================
    # DISPLAY RESULTS
    # ========================================================================

    Write-Output "`n========================================"
    Write-Output "UNASSIGNED POLICIES ANALYSIS RESULTS"
    Write-Output "========================================"

    if ($AllUnassignedPolicies.Count -eq 0) {
        Write-Output "✓ No unassigned policies found!"
        if ($FilterDate) {
            Write-Output "  (Checked policies created after $($FilterDate.ToString('yyyy-MM-dd')))"
        }
    }
    else {
        Write-Output "Found $($AllUnassignedPolicies.Count) unassigned policies:"

        # Group by risk level
        $HighRisk = $AllUnassignedPolicies | Where-Object { $_.RiskLevel -eq "High" }
        $MediumRisk = $AllUnassignedPolicies | Where-Object { $_.RiskLevel -eq "Medium" }
        $LowRisk = $AllUnassignedPolicies | Where-Object { $_.RiskLevel -eq "Low" }

        Write-Output "`nRisk Level Summary:"
        Write-Output "  High Risk: $($HighRisk.Count) policies"
        Write-Output "  Medium Risk: $($MediumRisk.Count) policies"
        Write-Output "  Low Risk: $($LowRisk.Count) policies"

        # Display top 10 unassigned policies
        Write-Output "`nTop 10 Unassigned Policies (by risk level):"
        $TopPolicies = $AllUnassignedPolicies | Sort-Object @{Expression = {
                switch ($_.RiskLevel) {
                    "High" { 1 }
                    "Medium" { 2 }
                    "Low" { 3 }
                }
            }
        }, CreatedDateTime | Select-Object -First 10

        $PolicyNumber = 1
        foreach ($Policy in $TopPolicies) {
            Write-Output "`n[$PolicyNumber] $($Policy.PolicyName)"
            Write-Output "  Type: $($Policy.PolicyType) ($($Policy.PolicySubType))"
            Write-Output "  Created: $($Policy.CreatedDateTime)"
            Write-Output "  Risk Level: $($Policy.RiskLevel)"
            if ($Policy.Description) {
                Write-Output "  Description: $($Policy.Description)"
            }
            if ($IncludeDetails -and $Policy.Details) {
                Write-Output "  Details: $($Policy.Details)"
            }
            $PolicyNumber++
        }
    }

    # ========================================================================
    # EXPORT TO CSV
    # ========================================================================

    if ($AllUnassignedPolicies.Count -gt 0) {
        # Create output directory if it does not exist
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-Output "Created output directory: $OutputPath"
        }

        $OutputFile = Join-Path -Path $OutputPath -ChildPath "UnassignedPolicies_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        try {
            $AllUnassignedPolicies | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            Write-Output "✓ Report exported to: $OutputFile"
        }
        catch {
            Write-Warning "Failed to export CSV report: $($_.Exception.Message)"
        }
    }

    Write-Output "`n✓ Unassigned policies analysis completed successfully"
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Output "Disconnected from Microsoft Graph"
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $($_.Exception.Message)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Output "
========================================
Script Execution Summary
========================================
Script: Unassigned Policies Monitor
Total Policies Checked: $($DeviceConfigurations.Count + $ConfigurationPolicies.Count + $GroupPolicyConfigurations.Count)
Unassigned Policies Found: $($AllUnassignedPolicies.Count)
Status: Completed
========================================
"
