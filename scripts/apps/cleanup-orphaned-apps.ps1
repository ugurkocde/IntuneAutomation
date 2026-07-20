<#
.TITLE
    Cleanup Orphaned Apps

.SYNOPSIS
    Finds Intune apps that have no assignments or are superseded by newer versions, and optionally deletes them.

.DESCRIPTION
    This script scans the Intune app catalog for cleanup candidates: apps with no
    assignments at all, and Win32 apps that a newer app supersedes. Old installer
    versions and abandoned test apps accumulate quickly and clutter the catalog. By
    default the script only reports; deletion requires the -Remove switch, supports
    -WhatIf preview, and prompts per app. Deleting an app from Intune does not
    uninstall it from devices that already have it.

.TAGS
    Apps,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\cleanup-orphaned-apps.ps1
    Reports unassigned and superseded apps without deleting anything

.EXAMPLE
    .\cleanup-orphaned-apps.ps1 -OlderThanDays 90
    Only reports apps created more than 90 days ago

.EXAMPLE
    .\cleanup-orphaned-apps.ps1 -Remove -WhatIf
    Shows exactly which apps would be deleted, without deleting them

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Superseded means another Win32 app declares a supersedence relationship to this app (supersedingAppCount > 0)
    - Deleting an app does not uninstall it from devices; it removes the deployment object
    - Recently created apps are excluded by default (-OlderThanDays 30) to avoid flagging work in progress
    - Uses beta Graph endpoints because supersedence counts are exposed there
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Only consider apps created more than this many days ago")]
    [ValidateRange(0, 3650)]
    [int]$OlderThanDays = 30,

    [Parameter(Mandatory = $false, HelpMessage = "Delete the reported apps instead of only reporting")]
    [switch]$Remove,

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
            "DeviceManagementApps.ReadWrite.All"
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
    Write-Information "Retrieving app catalog with assignments..." -InformationAction Continue
    $apps = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=assignments"
    Write-Information "✓ Found $(@($apps).Count) apps" -InformationAction Continue

    $cutoffDate = (Get-Date).AddDays(-$OlderThanDays)
    [System.Collections.Generic.List[Object]]$report = @()
    $deleted = 0
    $deleteFailed = 0

    foreach ($app in $apps) {
        $created = if ($app.createdDateTime) { [DateTime]::Parse($app.createdDateTime.ToString()) } else { $null }

        # Recently created apps are probably still being set up
        if ($created -and $created -gt $cutoffDate) {
            continue
        }

        $isUnassigned = (@($app.assignments).Count -eq 0)
        $isSuperseded = ([int]$app.supersedingAppCount -gt 0)

        if (-not $isUnassigned -and -not $isSuperseded) {
            continue
        }

        $reason = if ($isUnassigned -and $isSuperseded) { "Unassigned + Superseded" }
        elseif ($isSuperseded) { "Superseded" }
        else { "Unassigned" }

        $appType = ([string]$app.'@odata.type') -replace "#microsoft.graph.", ""

        $action = "Reported"
        if ($Remove) {
            if ($PSCmdlet.ShouldProcess("$($app.displayName) ($appType, $reason)", "Delete Intune app")) {
                try {
                    Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)" -Method DELETE
                    Write-Information "✓ Deleted: $($app.displayName)" -InformationAction Continue
                    $action = "Deleted"
                    $deleted++
                }
                catch {
                    Write-Warning "Failed to delete '$($app.displayName)': $($_.Exception.Message)"
                    $action = "DeleteFailed"
                    $deleteFailed++
                }
            }
            else {
                $action = "Skipped"
            }
        }

        $report.Add([PSCustomObject]@{
                AppName    = $app.displayName
                AppType    = $appType
                Publisher  = $app.publisher
                Reason     = $reason
                Created    = if ($created) { $created.ToString("yyyy-MM-dd") } else { "" }
                Superseded = $isSuperseded
                AppId      = $app.id
                Action     = $action
            })
    }

    # ----- Display results -----
    Write-Information "`nORPHANED APP REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Age filter: created more than $OlderThanDays days ago" -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($report.Count -eq 0) {
        Write-Information "`nNo orphaned or superseded apps found." -InformationAction Continue
    }
    else {
        foreach ($reasonGroup in ($report | Group-Object -Property Reason | Sort-Object Name)) {
            Write-Information "`n$($reasonGroup.Name) ($($reasonGroup.Count) apps)" -InformationAction Continue
            foreach ($row in ($reasonGroup.Group | Sort-Object AppName)) {
                Write-Information "  $($row.AppName) [$($row.AppType)] created $($row.Created) - $($row.Action)" -InformationAction Continue
            }
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) cleanup candidates of $(@($apps).Count) total apps" -InformationAction Continue
    if ($Remove) {
        Write-Information "Deleted: $deleted | Failed: $deleteFailed" -InformationAction Continue
    }
    elseif ($report.Count -gt 0) {
        Write-Information "Run again with -Remove to delete (add -WhatIf for a dry run). Deleting does NOT uninstall from devices." -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Orphaned_Apps_$timestamp.csv"
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
