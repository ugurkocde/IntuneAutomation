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
    1.2

.CHANGELOG
    1.2 - Assignments now resolve their parent role via per-assignment $expand=roleDefinition (RoleName/RoleType were hardcoded to Unknown before); roles-with-assignments count and -ShowEmptyRoles listing are now accurate; added $select to role definition and principal lookups; principal lookups retry once after 60 seconds on throttling
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing)
    1.0 - Initial release

.LASTUPDATE
    2026-07-19

.EXAMPLE
    .\get-intune-role-assignments.ps1
    Shows all Intune role assignments

.EXAMPLE
    .\get-intune-role-assignments.ps1 -ShowEmptyRoles
    Shows all roles including those with no current assignments

.EXAMPLE
    .\get-intune-role-assignments.ps1 -ExportToCsv
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
    [switch]$ShowEmptyRoles,
    
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
            "DeviceManagementRBAC.Read.All",
            "User.Read.All",
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

function Get-PrincipalName {
    param(
        [string]$PrincipalId,
        [string]$PrincipalType
    )

    if ($PrincipalType -eq "user") {
        $uri = "https://graph.microsoft.com/v1.0/users/${PrincipalId}?`$select=id,displayName,userPrincipalName,mail"
    }
    elseif ($PrincipalType -eq "group") {
        $uri = "https://graph.microsoft.com/v1.0/groups/${PrincipalId}?`$select=id,displayName,mail"
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
    Write-Information "Retrieving Intune role definitions..." -InformationAction Continue
    
    # Get all role definitions first
    $roleDefinitionsUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleDefinitions?`$select=id,displayName,description,isBuiltIn"
    $roleDefinitions = Get-MgGraphAllPage -Uri $roleDefinitionsUri
    
    Write-Information "✓ Found $($roleDefinitions.Count) role definitions" -InformationAction Continue
    
    # Create role lookup table
    $roleLookup = @{}
    foreach ($role in $roleDefinitions) {
        $roleLookup[$role.id] = $role
    }
    
    # Get all role assignments directly
    Write-Information "Retrieving role assignments..." -InformationAction Continue
    $roleAssignmentsUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleAssignments"
    $roleAssignments = Get-MgGraphAllPage -Uri $roleAssignmentsUri
    
    Write-Information "✓ Found $($roleAssignments.Count) role assignments" -InformationAction Continue
    
    # Process assignments
    [System.Collections.Generic.List[Object]]$allAssignments = @()
    $totalAssignments = 0
    $rolesWithAssignments = 0
    $processedRoles = @{}
    
    Write-Information "Processing assignments..." -InformationAction Continue
    
    foreach ($assignment in $roleAssignments) {
        Write-Verbose "Processing assignment: $($assignment.displayName)"

        # The list endpoint does not link assignments to their role definition,
        # so fetch each assignment individually with $expand=roleDefinition
        $roleDefinition = $null
        try {
            $assignmentDetailUri = "https://graph.microsoft.com/v1.0/deviceManagement/roleAssignments/$($assignment.id)?`$expand=roleDefinition"
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
    Write-Information "`n🔐 INTUNE ROLE ASSIGNMENTS REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    
    # Group by role for display
    $groupedAssignments = $allAssignments | Group-Object -Property RoleName
    
    foreach ($roleGroup in $groupedAssignments | Sort-Object Name) {
        $firstAssignment = $roleGroup.Group[0]
        
        $roleColor = if ($firstAssignment.RoleType -eq "Built-in") { "Cyan" } else { "Yellow" }
        Write-Information "`n[$($firstAssignment.RoleType)] $($roleGroup.Name)" -InformationAction Continue
        
        if ($firstAssignment.Description) {
            Write-Information "  Description: $($firstAssignment.Description)" -InformationAction Continue
        }
        
        foreach ($assignment in $roleGroup.Group) {
            if ($assignment.AssignmentName -ne "No assignments") {
                Write-Information "  Assignment: $($assignment.AssignmentName)" -InformationAction Continue
                
                if ($assignment.Members.Count -gt 0) {
                    foreach ($member in $assignment.Members) {
                        $memberInfo = "    • $($member.DisplayName) "
                        if ($member.Email) {
                            $memberInfo += "($($member.Email)) "
                        }
                        $memberInfo += "- $($member.Type)"
                        Write-Information $memberInfo -InformationAction Continue
                    }
                }
                else {
                    Write-Information "    • Direct assignment (check portal for members)" -InformationAction Continue
                }
                
                if ($assignment.Scope) {
                    Write-Information "    Scope: $($assignment.Scope)" -InformationAction Continue
                }
            }
            else {
                Write-Information "  • No current assignments" -InformationAction Continue
            }
        }
    }
    
    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($roleDefinitions.Count) roles, $rolesWithAssignments roles with assignments, $totalAssignments total assignments" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    
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