<#
.TITLE
    Get Intune Role Assignments

.SYNOPSIS
    Lists all Intune role assignments showing who has which roles for security auditing.

.DESCRIPTION
    This script connects to Microsoft Graph to retrieve all Intune role definitions
    and their assignments, providing a clear view of who has administrative access
    to Intune. It shows both built-in and custom roles, the assigned users/groups,
    assignment dates, and scopes. Perfect for security audits and access reviews.

.TAGS
    Security

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementRBAC.Read.All,User.Read.All,Group.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Assignments now resolve their parent role via per-assignment $expand=roleDefinition (RoleName/RoleType were hardcoded to Unknown before); roles-with-assignments count and -ShowEmptyRoles listing are now accurate; added $select to role definition and principal lookups; principal lookups retry once after 60 seconds on throttling
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\get-intune-role-assignments.ps1
    Shows all Intune role assignments

.EXAMPLE
    .\get-intune-role-assignments.ps1 -ShowEmptyRoles "true"
    Shows all roles including those with no current assignments

.EXAMPLE
    .\get-intune-role-assignments.ps1 -ExportToCsv "true"
    Exports the role assignments report to a CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Shows both built-in and custom Intune roles
    - Resolves user and group names for assignments
    - Assignment dates may not be available for older assignments
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Show roles with no assignments")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ShowEmptyRoles,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

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
foreach ($runbookBooleanParameter in @('ShowEmptyRoles', 'ExportToCsv')) {
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
            "DeviceManagementRBAC.Read.All",
            "User.Read.All",
            "Group.Read.All"
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
            throw "Error fetching data: $($_.Exception.Message)"
        }
    } while ($nextLink)

    return $allResults
}

function Get-PrincipalName {
    param(
        [string]$PrincipalId,
        [string]$PrincipalType
    )

    if ($PrincipalType -eq "user") {
        $uri = "https://graph.microsoft.com/beta/users/${PrincipalId}?`$select=id,displayName,userPrincipalName,mail"
    }
    elseif ($PrincipalType -eq "group") {
        $uri = "https://graph.microsoft.com/beta/groups/${PrincipalId}?`$select=id,displayName,mail"
    }
    else {
        return @{
            DisplayName = $PrincipalId
            Email       = ""
            Type        = "Unknown"
        }
    }

    try {
        try {
            $principal = Invoke-MgGraphRequest -Uri $uri -Method GET
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                $principal = Invoke-MgGraphRequest -Uri $uri -Method GET
            }
            else {
                throw
            }
        }

        if ($PrincipalType -eq "user") {
            return @{
                DisplayName = $principal.displayName
                Email       = $principal.userPrincipalName
                Type        = "User"
            }
        }
        return @{
            DisplayName = $principal.displayName
            Email       = $principal.mail
            Type        = "Group"
        }
    }
    catch {
        Write-Verbose "Could not resolve principal ${PrincipalId}: $($_.Exception.Message)"
        return @{
            DisplayName = $PrincipalId
            Email       = ""
            Type        = $PrincipalType
        }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Retrieving Intune role definitions..."

    # Get all role definitions first
    $roleDefinitionsUri = "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions?`$select=id,displayName,description,isBuiltIn"
    $roleDefinitions = Get-MgGraphAllPage -Uri $roleDefinitionsUri

    Write-Output "✓ Found $($roleDefinitions.Count) role definitions"

    # Create role lookup table
    $roleLookup = @{}
    foreach ($role in $roleDefinitions) {
        $roleLookup[$role.id] = $role
    }

    # Get all role assignments directly
    Write-Output "Retrieving role assignments..."
    $roleAssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/roleAssignments"
    $roleAssignments = Get-MgGraphAllPage -Uri $roleAssignmentsUri

    Write-Output "✓ Found $($roleAssignments.Count) role assignments"

    # Process assignments
    [System.Collections.Generic.List[Object]]$allAssignments = @()
    $totalAssignments = 0
    $rolesWithAssignments = 0
    $processedRoles = @{}

    Write-Output "Processing assignments..."

    foreach ($assignment in $roleAssignments) {
        Write-Verbose "Processing assignment: $($assignment.displayName)"

        # The list endpoint does not link assignments to their role definition,
        # so fetch each assignment individually with $expand=roleDefinition
        $roleDefinition = $null
        try {
            $assignmentDetailUri = "https://graph.microsoft.com/beta/deviceManagement/roleAssignments/$($assignment.id)?`$expand=roleDefinition"
            $assignmentDetail = Invoke-MgGraphRequest -Uri $assignmentDetailUri -Method GET
            $roleDefinition = $assignmentDetail.roleDefinition
        }
        catch {
            Write-Warning "Could not resolve role definition for assignment '$($assignment.displayName)': $($_.Exception.Message)"
        }

        # Prefer the definition from the lookup table so the record matches the definitions list
        if ($roleDefinition -and $roleLookup.ContainsKey($roleDefinition.id)) {
            $roleDefinition = $roleLookup[$roleDefinition.id]
        }

        # Create assignment record
        $assignmentRecord = @{
            RoleId         = if ($roleDefinition) { $roleDefinition.id } else { "" }
            RoleName       = if ($roleDefinition) { $roleDefinition.displayName } else { "Unknown Role" }
            RoleType       = if ($roleDefinition) { if ($roleDefinition.isBuiltIn) { "Built-in" } else { "Custom" } } else { "Assignment" }
            Description    = $assignment.description
            AssignmentId   = $assignment.id
            AssignmentName = $assignment.displayName
            Scope          = if ($assignment.resourceScopes) { $assignment.resourceScopes -join "; " } else { "All" }
            Members        = @()
        }

        if ($roleDefinition) {
            $processedRoles[$roleDefinition.id] = $true
        }

        # Process members
        if ($assignment.members) {
            foreach ($memberId in $assignment.members) {
                # First try as user, then as group
                $principalInfo = Get-PrincipalName -PrincipalId $memberId -PrincipalType "user"

                # If user lookup failed, try as group
                if ($principalInfo.DisplayName -eq $memberId) {
                    $groupInfo = Get-PrincipalName -PrincipalId $memberId -PrincipalType "group"
                    if ($groupInfo.DisplayName -ne $memberId) {
                        $principalInfo = $groupInfo
                    }
                }

                $assignmentRecord.Members += $principalInfo
            }
        }

        $allAssignments.Add($assignmentRecord)
        $totalAssignments++
    }

    # Add roles without assignments if ShowEmptyRoles is specified
    if ($ShowEmptyRoles) {
        foreach ($role in $roleDefinitions) {
            if (-not $processedRoles.ContainsKey($role.id)) {
                $allAssignments.Add(@{
                    RoleId         = $role.id
                    RoleName       = $role.displayName
                    RoleType       = if ($role.isBuiltIn) { "Built-in" } else { "Custom" }
                    Description    = $role.description
                    AssignmentId   = ""
                    AssignmentName = "No assignments"
                    Scope          = ""
                    Members        = @()
                })
            }
        }
    }

    # Count unique roles with assignments
    $rolesWithAssignments = $processedRoles.Count

    # Display results
    Write-Output "`n🔐 INTUNE ROLE ASSIGNMENTS REPORT"
    Write-Output ("=" * 50)
    Write-Output "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output ("=" * 50)

    # Group by role for display
    $groupedAssignments = $allAssignments | Group-Object -Property RoleName

    foreach ($roleGroup in $groupedAssignments | Sort-Object Name) {
        $firstAssignment = $roleGroup.Group[0]

        $roleColor = if ($firstAssignment.RoleType -eq "Built-in") { "Cyan" } else { "Yellow" }
        Write-Output "`n[$($firstAssignment.RoleType)] $($roleGroup.Name)"

        if ($firstAssignment.Description) {
            Write-Output "  Description: $($firstAssignment.Description)"
        }

        foreach ($assignment in $roleGroup.Group) {
            if ($assignment.AssignmentName -ne "No assignments") {
                Write-Output "  Assignment: $($assignment.AssignmentName)"

                if ($assignment.Members.Count -gt 0) {
                    foreach ($member in $assignment.Members) {
                        $memberInfo = "    • $($member.DisplayName) "
                        if ($member.Email) {
                            $memberInfo += "($($member.Email)) "
                        }
                        $memberInfo += "- $($member.Type)"
                        Write-Output $memberInfo
                    }
                }
                else {
                    Write-Output "    • Direct assignment (check portal for members)"
                }

                if ($assignment.Scope) {
                    Write-Output "    Scope: $($assignment.Scope)"
                }
            }
            else {
                Write-Output "  • No current assignments"
            }
        }
    }

    # Summary
    Write-Output "`n"
    Write-Output ("=" * 50)
    Write-Output "Summary: $($roleDefinitions.Count) roles, $rolesWithAssignments roles with assignments, $totalAssignments total assignments"
    Write-Output ("=" * 50)

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Intune_Role_Assignments_$timestamp.csv"

        # Flatten the data for CSV export
        [System.Collections.Generic.List[Object]]$csvData = @()
        foreach ($assignment in $allAssignments) {
            if ($assignment.Members.Count -gt 0) {
                foreach ($member in $assignment.Members) {
                    $csvData.Add([PSCustomObject]@{
                        RoleName       = $assignment.RoleName
                        RoleType       = $assignment.RoleType
                        AssignmentName = $assignment.AssignmentName
                        MemberName     = $member.DisplayName
                        MemberEmail    = $member.Email
                        MemberType     = $member.Type
                        Scope          = $assignment.Scope
                    })
                }
            }
            else {
                $csvData.Add([PSCustomObject]@{
                    RoleName       = $assignment.RoleName
                    RoleType       = $assignment.RoleType
                    AssignmentName = $assignment.AssignmentName
                    MemberName     = "No members"
                    MemberEmail    = ""
                    MemberType     = ""
                    Scope          = $assignment.Scope
                })
            }
        }

        $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
