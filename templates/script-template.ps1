<#
.TITLE
    [Script Title - Brief descriptive name]

.SYNOPSIS
    [One-line description of what the script does]

.DESCRIPTION
    [Detailed description of the script's functionality, purpose, and use cases.
    Explain what the script accomplishes and any important considerations.
    Include information about prerequisites, dependencies, or special requirements.]

.TAGS
    [Category],[Subcategory] (e.g., Operational,Devices or Security,Compliance)

.PLATFORM
    Windows

.MINROLE
    [Minimum Intune/Azure AD role required - e.g., Intune Administrator, Global Administrator]

.PERMISSIONS
    [Required Microsoft Graph permissions - comma separated list]

.AUTHOR
    [Your Name]

.VERSION
    [Version number - start with 1.0]

.CHANGELOG
    [Version] - [Description of changes]
    1.0 - Initial release

.EXAMPLE
    [Script filename] [parameters]
    [Description of what this example does]

.EXAMPLE
    [Script filename] [different parameters]
    [Description of what this example does]

.NOTES
    [Additional notes, requirements, or important information]
    - [Any special requirements or dependencies]
    - [Performance considerations]
    - [Known limitations]
    - [Links to relevant documentation]
#>

[CmdletBinding()]
param(
    # Define your parameters here
    # Use proper parameter attributes and validation
    [Parameter(Mandatory = $true, HelpMessage = "Description of this parameter")]
    [ValidateNotNullOrEmpty()]
    [string]$RequiredParameter,
    
    [Parameter(Mandatory = $false, HelpMessage = "Description of this optional parameter")]
    [string]$OptionalParameter = "DefaultValue",
    
    [Parameter(Mandatory = $false)]
    [switch]$SwitchParameter
)

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if required modules are installed
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
    # Add other required modules here
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
        # Add your required permissions here
        "Permission.ReadWrite.All"
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

# Add your custom helper functions here
function Invoke-CustomFunction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Parameter
    )
    
    try {
        # Your function logic here
        Write-Information "Processing: $Parameter" -InformationAction Continue
        
        # Return result
        return $true
    }
    catch {
        Write-Error "Error in custom function: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting script execution..." -InformationAction Continue
    
    # Validate parameters
    if ([string]::IsNullOrWhiteSpace($RequiredParameter)) {
        throw "Required parameter cannot be empty"
    }
    
    # Main script logic goes here
    Write-Information "Processing with parameter: $RequiredParameter" -InformationAction Continue
    
    # Example API call
    # $Results = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/your-endpoint"
    
    # Process results
    # foreach ($Item in $Results) {
    #     $Success = Invoke-CustomFunction -Parameter $Item.property
    #     if ($Success) {
    #         Write-Information "✓ Successfully processed: $($Item.displayName)" -InformationAction Continue
    #     }
    #     else {
    #         Write-Warning "✗ Failed to process: $($Item.displayName)"
    #     }
    # }
    
    Write-Information "✓ Script completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
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
Script: [Script Name]
Parameters: $RequiredParameter
Status: Completed
========================================
" -InformationAction Continue 