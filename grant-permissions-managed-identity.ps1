param(
    [Parameter(Mandatory = $true, HelpMessage = "Display name of the User Assigned Managed Identity")]
    [string]$ManagedIdentityDisplayName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Custom permissions to assign (if not provided, default Intune permissions will be used)")]
    [string[]]$CustomPermissions = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "Enable verbose logging")]
    [switch]$EnableVerboseLogging,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip module installation check")]
    [switch]$SkipModuleCheck
)

#------------------------------------------------------------------------------
# Configuration and Variables
#------------------------------------------------------------------------------

# Default Intune permissions if no custom permissions are provided
$DefaultIntunePermissions = @(
    "DeviceManagementManagedDevices.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementConfiguration.Read.All",
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementApps.Read.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementServiceConfig.Read.All",
    "DeviceManagementRBAC.ReadWrite.All",
    "DeviceManagementManagedDevices.PrivilegedOperations.All",
    "BitlockerKey.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All"
)

# Use custom permissions if provided, otherwise use default Intune permissions
$PermissionsToAssign = if ($CustomPermissions.Count -gt 0) { $CustomPermissions } else { $DefaultIntunePermissions }

# Microsoft Graph App ID (constant)
$GraphAppId = "00000003-0000-0000-c000-000000000000"

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Error $logMessage }
        "WARNING" { Write-Warning $logMessage }
        "VERBOSE" { if ($EnableVerboseLogging) { Write-Host $logMessage -ForegroundColor Cyan } }
        default { Write-Host $logMessage -ForegroundColor Green }
    }
}

function Install-RequiredModule {
    param(
        [string]$ModuleName
    )
    
    try {
        Write-Log "Checking for module: $ModuleName" -Level "VERBOSE"
        
        if (-not(Get-Module -ListAvailable -Name $ModuleName)) {
            Write-Log "Installing module: $ModuleName"
            Install-Module -Name $ModuleName -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
        }
        
        Write-Log "Importing module: $ModuleName" -Level "VERBOSE"
        Import-Module $ModuleName -ErrorAction Stop
        Write-Log "Successfully loaded module: $ModuleName"
        
    }
    catch {
        Write-Log "Failed to install/import module $ModuleName`: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Connect-ToServices {
    try {
        Write-Log "Connecting to Azure Account..."
        Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
        
        Write-Log "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All" -UseDeviceCode -ErrorAction Stop
        
        Write-Log "Successfully connected to Azure and Microsoft Graph"
        
    }
    catch {
        Write-Log "Failed to connect to services: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Get-ManagedIdentityServicePrincipal {
    param([string]$DisplayName)
    
    try {
        Write-Log "Looking for managed identity: $DisplayName"
        $managedIdentity = Get-AzADServicePrincipal -DisplayName $DisplayName -ErrorAction Stop
        
        if (-not $managedIdentity) {
            throw "Managed Identity with display name '$DisplayName' not found"
        }
        
        Write-Log "Found managed identity: $($managedIdentity.DisplayName) (ID: $($managedIdentity.Id))"
        return $managedIdentity
        
    }
    catch {
        Write-Log "Failed to retrieve managed identity: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Get-GraphServicePrincipal {
    try {
        Write-Log "Getting Microsoft Graph service principal..."
        $graphSPN = Get-MgServicePrincipal -Filter "AppId eq '$GraphAppId'" -ErrorAction Stop
        
        if (-not $graphSPN) {
            throw "Microsoft Graph service principal not found"
        }
        
        Write-Log "Found Microsoft Graph service principal (ID: $($graphSPN.Id))"
        return $graphSPN
        
    }
    catch {
        Write-Log "Failed to retrieve Graph service principal: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Grant-AppRoleAssignment {
    param(
        [object]$ManagedIdentity,
        [object]$GraphServicePrincipal,
        [string[]]$Permissions
    )
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($permission in $Permissions) {
        try {
            Write-Log "Processing permission: $permission" -Level "VERBOSE"
            
            # Find the app role for this permission
            $appRole = $GraphServicePrincipal.AppRoles | 
            Where-Object { $_.Value -eq $permission -and $_.AllowedMemberTypes -contains "Application" }
            
            if (-not $appRole) {
                Write-Log "App role not found for permission: $permission" -Level "WARNING"
                $failureCount++
                continue
            }
            
            # Check if assignment already exists
            $existingAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentity.Id | 
            Where-Object { $_.AppRoleId -eq $appRole.Id -and $_.ResourceId -eq $GraphServicePrincipal.Id }
            
            if ($existingAssignment) {
                Write-Log "Permission '$permission' already assigned, skipping..." -Level "VERBOSE"
                $successCount++
                continue
            }
            
            # Create the app role assignment
            $bodyParam = @{
                PrincipalId = $ManagedIdentity.Id
                ResourceId  = $GraphServicePrincipal.Id
                AppRoleId   = $appRole.Id
            }
            
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentity.Id -BodyParameter $bodyParam -ErrorAction Stop
            Write-Log "Successfully assigned permission: $permission"
            $successCount++
            
        }
        catch {
            Write-Log "Failed to assign permission '$permission': $($_.Exception.Message)" -Level "ERROR"
            $failureCount++
        }
    }
    
    Write-Log "Permission assignment completed. Success: $successCount, Failures: $failureCount"
    
    if ($failureCount -gt 0) {
        Write-Log "Some permissions failed to assign. Please review the errors above." -Level "WARNING"
    }
}

#------------------------------------------------------------------------------
# Main Script Execution
#------------------------------------------------------------------------------

try {
    Write-Log "Starting Managed Identity Permission Assignment Script"
    Write-Log "Target Managed Identity: $ManagedIdentityDisplayName"
    Write-Log "Permissions to assign: $($PermissionsToAssign -join ', ')"
    
    # Install required modules
    if (-not $SkipModuleCheck) {
        Write-Log "Installing/checking required modules..."
        $requiredModules = @("Az.Accounts", "Az.Resources", "Microsoft.Graph.Applications")
        
        foreach ($module in $requiredModules) {
            Install-RequiredModule -ModuleName $module
        }
    }
    else {
        Write-Log "Skipping module installation check as requested"
    }
    
    # Connect to services
    Connect-ToServices
    
    # Get the managed identity
    $managedIdentity = Get-ManagedIdentityServicePrincipal -DisplayName $ManagedIdentityDisplayName
    
    # Get the Microsoft Graph service principal
    $graphServicePrincipal = Get-GraphServicePrincipal
    
    # Grant permissions
    Grant-AppRoleAssignment -ManagedIdentity $managedIdentity -GraphServicePrincipal $graphServicePrincipal -Permissions $PermissionsToAssign
    
    Write-Log "Script completed successfully!"
    
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

#------------------------------------------------------------------------------
# Example Usage:
#------------------------------------------------------------------------------
<#
# Basic usage with default Intune permissions:
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "MyIntuneAutomation"

# With custom permissions:
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "MyAutomation" -CustomPermissions @("User.Read.All", "Group.Read.All")

# With verbose logging:
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "MyAutomation" -EnableVerboseLogging

# Skip module check (if modules are already installed):
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "MyAutomation" -SkipModuleCheck
#>