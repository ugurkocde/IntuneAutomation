<#
.TITLE
    Unassigned Policies Report

.SYNOPSIS
    Identifies all Intune policies that have no group or user assignments

.DESCRIPTION
    This script connects to Microsoft Graph and analyzes all Intune policies to identify
    which ones have no assignments. It checks device configuration policies, device compliance
    policies, app protection policies, and Settings Catalog policies. The script provides a 
    comprehensive report showing policies that may be obsolete or forgotten, helping 
    administrators maintain a clean policy environment.

.TAGS
    Operational,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\get-unassigned-policies.ps1
    Displays all unassigned policies in the console

.EXAMPLE
    .\get-unassigned-policies.ps1 -ExportPath "C:\Reports\UnassignedPolicies.csv"
    Exports unassigned policies to a CSV file

.NOTES
    - Requires only Microsoft.Graph.Authentication module
    - Uses Connect-MgGraph and Invoke-MgGraphRequest for all Graph operations
    - Checks policy types: Device Configuration, Device Compliance, App Protection, Settings Catalog
    - Settings Catalog policies require beta Graph endpoint access
    - App Protection policies are considered assigned if they exist (different targeting model)
    - Policies with no assignments may indicate unused or forgotten configurations
    - Consider reviewing these policies for potential cleanup or assignment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Path to export the results to CSV file")]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false, HelpMessage = "Include detailed assignment information in output")]
    [switch]$IncludeDetails
)

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if required modules are installed
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Error "$Module module is required. Install it using: Install-Module $Module -Scope CurrentUser"
        exit 1
    }
}

# Import required modules
foreach ($Module in $RequiredModules) {
    Import-Module $Module
}

# Connect to Microsoft Graph
try {
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    $Scopes = @(
        "DeviceManagementConfiguration.Read.All",
        "DeviceManagementApps.Read.All",
        "DeviceManagementManagedDevices.Read.All"
    )
    Connect-MgGraph -Scopes $Scopes -NoWelcome
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API
function Get-MgGraphAllPages {
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
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
        }
    } while ($NextLink)
    
    return $AllResults
}

# Function to check if a policy has assignments
function Test-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyType
    )
    
    # Check if PolicyId is valid
    if ([string]::IsNullOrWhiteSpace($PolicyId)) {
        Write-Warning "PolicyId is empty or null for $PolicyType policy"
        return $false
    }
    
    try {
        # App Protection policies use a different targeting mechanism
        if ($PolicyType -eq "AppProtection") {
            # App Protection policies don't use traditional assignments
            # They are applied to applications and considered active if they exist
            try {
                # Verify the policy exists and is accessible
                $PolicyUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/managedAppPolicies/$PolicyId"
                $PolicyDetails = Invoke-MgGraphRequest -Uri $PolicyUri -Method GET
                
                # App Protection policies are considered "assigned" if they exist and are published
                # Most App Protection policies that exist are active/assigned to applications
                return $true
            }
            catch {
                # If we can't access the policy, it might not be properly configured
                return $false
            }
        }
        else {
            $AssignmentUri = switch ($PolicyType) {
                "DeviceConfiguration" { "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$PolicyId/assignments" }
                "DeviceCompliance" { "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$PolicyId/assignments" }
                "SettingsCatalog" { "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId/assignments" }
                default { return $false }
            }
            
            $Assignments = Get-MgGraphAllPages -Uri $AssignmentUri
            return $Assignments.Count -gt 0
        }
    }
    catch {
        Write-Warning "Could not check assignments for policy $PolicyId : $($_.Exception.Message)"
        return $false
    }
}

# Function to get policy details
function Get-PolicyDetails {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,
        [Parameter(Mandatory = $true)]
        [string]$PolicyType
    )
    
    # Settings Catalog policies use 'name' instead of 'displayName'
    $PolicyDisplayName = if ($PolicyType -eq "SettingsCatalog") {
        $Policy.name
    }
    else {
        $Policy.displayName
    }
    
    $Details = [PSCustomObject]@{
        PolicyType           = $PolicyType
        PolicyId             = $Policy.id
        DisplayName          = $PolicyDisplayName
        Description          = $Policy.description
        CreatedDateTime      = $Policy.createdDateTime
        LastModifiedDateTime = $Policy.lastModifiedDateTime
        Version              = $Policy.version
        HasAssignments       = $false
    }
    
    # Check for assignments
    $Details.HasAssignments = Test-PolicyAssignments -PolicyId $Policy.id -PolicyType $PolicyType
    
    return $Details
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting unassigned policies analysis..." -InformationAction Continue
    
    $UnassignedPolicies = @()
    $PolicyTypes = @(
        @{ Name = "DeviceConfiguration"; Uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" },
        @{ Name = "DeviceCompliance"; Uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" },
        @{ Name = "AppProtection"; Uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/managedAppPolicies" },
        @{ Name = "SettingsCatalog"; Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" }
    )
    
    foreach ($PolicyType in $PolicyTypes) {
        Write-Information "Analyzing $($PolicyType.Name) policies..." -InformationAction Continue
        
        try {
            $Policies = Get-MgGraphAllPages -Uri $PolicyType.Uri
            # Handle null or empty results
            if (-not $Policies) {
                $Policies = @()
            }
            Write-Information "Found $($Policies.Count) $($PolicyType.Name) policies" -InformationAction Continue
            
            foreach ($Policy in $Policies) {
                # Skip policies with empty or null IDs
                if ([string]::IsNullOrWhiteSpace($Policy.id)) {
                    $PolicyName = if ($PolicyType.Name -eq "SettingsCatalog") { $Policy.name } else { $Policy.displayName }
                    Write-Warning "Skipping policy with empty ID: $($PolicyName ?? 'Unknown')"
                    continue
                }
                
                $PolicyDetails = Get-PolicyDetails -Policy $Policy -PolicyType $PolicyType.Name
                
                # Get the correct display name for Settings Catalog vs other policies
                $DisplayName = if ($PolicyType.Name -eq "SettingsCatalog") {
                    $Policy.name
                }
                else {
                    $Policy.displayName
                }
                
                if (-not $PolicyDetails.HasAssignments) {
                    $UnassignedPolicies += $PolicyDetails
                    Write-Information "✗ Unassigned: $DisplayName ($($PolicyType.Name))" -InformationAction Continue
                }
                else {
                    Write-Information "✓ Assigned: $DisplayName ($($PolicyType.Name))" -InformationAction Continue
                }
            }
        }
        catch {
            Write-Warning "Error analyzing $($PolicyType.Name) policies: $($_.Exception.Message)"
        }
    }
    
    # Display results
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "UNASSIGNED POLICIES SUMMARY" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    
    if ($UnassignedPolicies.Count -eq 0) {
        Write-Information "✓ No unassigned policies found - all policies have assignments!" -InformationAction Continue
    }
    else {
        Write-Information "Found $($UnassignedPolicies.Count) policies without assignments:" -InformationAction Continue
        
        $GroupedPolicies = $UnassignedPolicies | Group-Object PolicyType
        foreach ($Group in $GroupedPolicies) {
            Write-Information "`n$($Group.Name) Policies ($($Group.Count)):" -InformationAction Continue
            foreach ($Policy in $Group.Group) {
                Write-Information "  - $($Policy.DisplayName)" -InformationAction Continue
                if ($IncludeDetails) {
                    Write-Information "    ID: $($Policy.PolicyId)" -InformationAction Continue
                    Write-Information "    Created: $($Policy.CreatedDateTime)" -InformationAction Continue
                    Write-Information "    Modified: $($Policy.LastModifiedDateTime)" -InformationAction Continue
                }
            }
        }
        
        # Export to CSV if path provided
        if ($ExportPath) {
            try {
                $UnassignedPolicies | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Information "`n✓ Results exported to: $ExportPath" -InformationAction Continue
            }
            catch {
                Write-Error "Failed to export results: $($_.Exception.Message)"
            }
        }
    }
    
    Write-Information "`n✓ Analysis completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Ignore disconnect errors
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Script Execution Summary
========================================
Script: Unassigned Policies Report
Total Unassigned Policies: $($UnassignedPolicies.Count)
Export Path: $($ExportPath ?? 'None')
Status: Completed
========================================
" -InformationAction Continue 