<#
.TITLE
    Fix Primary User Assignment

.SYNOPSIS
    Aligns each Windows device's Intune primary user with the user who actually logs on to it.

.DESCRIPTION
    This script compares every Windows device's Intune primary user with the most
    recent logged-on user reported by the device (usersLoggedOn). Devices where the
    primary user differs from the actual user - shared-device handovers, re-imaged
    machines, IT-technician enrollments - are reported, and with -Apply the primary
    user is updated via the users/`$ref assignment. A correct primary user matters for
    self-service portal access, user-targeted policy resolution, and license-based app
    delivery.

.TAGS
    Devices,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All,User.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\fix-primary-user-assignment.ps1
    Reports devices whose primary user does not match the last logged-on user

.EXAMPLE
    .\fix-primary-user-assignment.ps1 -Apply -WhatIf
    Previews the primary user changes without applying them

.EXAMPLE
    .\fix-primary-user-assignment.ps1 -Apply
    Updates the primary user on all mismatched devices

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Only Windows devices are processed; usersLoggedOn is not reliably populated on other platforms
    - Devices without logged-on user data or without a resolvable user are skipped
    - Uses beta Graph endpoints because usersLoggedOn is not exposed on v1.0
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Apply the primary user changes instead of only reporting")]
    [switch]$Apply,

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
            "DeviceManagementManagedDevices.ReadWrite.All",
            "User.Read.All"
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

$script:UserUpnCache = @{}

function Resolve-UserUpn {
    param([string]$UserId)

    if ([string]::IsNullOrWhiteSpace($UserId)) { return $null }
    if ($script:UserUpnCache.ContainsKey($UserId)) { return $script:UserUpnCache[$UserId] }

    $upn = $null
    try {
        $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/users/${UserId}?`$select=userPrincipalName,accountEnabled" -Method GET
        if ($user.accountEnabled) {
            $upn = $user.userPrincipalName
        }
    }
    catch {
        Write-Verbose "Could not resolve user ${UserId}: $($_.Exception.Message)"
    }

    $script:UserUpnCache[$UserId] = $upn
    return $upn
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving Windows devices with logged-on user data..." -InformationAction Continue
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=id,deviceName,userPrincipalName,userId,usersLoggedOn,lastSyncDateTime"
    Write-Information "✓ Found $(@($devices).Count) Windows devices" -InformationAction Continue

    [System.Collections.Generic.List[Object]]$report = @()
    $updated = 0
    $failed = 0
    $alreadyCorrect = 0
    $noData = 0

    foreach ($device in $devices) {
        $loggedOnUsers = @($device.usersLoggedOn)
        if ($loggedOnUsers.Count -eq 0) {
            $noData++
            continue
        }

        # usersLoggedOn entries carry userId + lastLogOnDateTime; take the most recent
        $mostRecent = $loggedOnUsers | Sort-Object -Property @{ Expression = { if ($_.lastLogOnDateTime) { [DateTime]::Parse($_.lastLogOnDateTime.ToString()) } else { [DateTime]::MinValue } } } -Descending | Select-Object -First 1

        $actualUserId = $mostRecent.userId
        if (-not $actualUserId) {
            $noData++
            continue
        }

        if ($actualUserId -eq $device.userId) {
            $alreadyCorrect++
            continue
        }

        $actualUserUpn = Resolve-UserUpn -UserId $actualUserId
        if (-not $actualUserUpn) {
            Write-Verbose "Skipping '$($device.deviceName)': logged-on user $actualUserId is not a resolvable enabled user"
            $noData++
            continue
        }

        $result = "Mismatch"
        if ($Apply) {
            if ($PSCmdlet.ShouldProcess("$($device.deviceName): $($device.userPrincipalName) -> $actualUserUpn", "Set primary user")) {
                try {
                    $body = @{ "@odata.id" = "https://graph.microsoft.com/beta/users/$actualUserId" } | ConvertTo-Json
                    Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/users/`$ref" -Method POST -Body $body -ContentType "application/json"
                    Write-Information "✓ Primary user updated on '$($device.deviceName)': $actualUserUpn" -InformationAction Continue
                    $result = "Updated"
                    $updated++
                }
                catch {
                    Write-Warning "Failed to update primary user on '$($device.deviceName)': $($_.Exception.Message)"
                    $result = "Failed"
                    $failed++
                }
            }
            else {
                $result = "WhatIf"
            }
        }

        $report.Add([PSCustomObject]@{
                DeviceName     = $device.deviceName
                DeviceId       = $device.id
                CurrentPrimary = $device.userPrincipalName
                ActualUser     = $actualUserUpn
                LastLogOn      = $mostRecent.lastLogOnDateTime
                Result         = $result
            })
    }

    # ----- Display results -----
    Write-Information "`nPRIMARY USER MISMATCH REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($report.Count -eq 0) {
        Write-Information "`nNo primary user mismatches found." -InformationAction Continue
    }
    else {
        foreach ($row in ($report | Sort-Object DeviceName)) {
            Write-Information "  $($row.DeviceName): primary '$($row.CurrentPrimary)' vs actual '$($row.ActualUser)' [$($row.Result)]" -InformationAction Continue
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $(@($devices).Count) Windows devices | $alreadyCorrect correct | $($report.Count) mismatched | $noData without usable logon data" -InformationAction Continue
    if ($Apply) {
        Write-Information "Updated: $updated | Failed: $failed" -InformationAction Continue
    }
    elseif ($report.Count -gt 0) {
        Write-Information "Run again with -Apply to update the primary users (add -WhatIf for a dry run)" -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Primary_User_Mismatches_$timestamp.csv"
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
