<#
.TITLE
    Get Device Check-in Health

.SYNOPSIS
    Analyzes device sync cadence and highlights devices whose check-in behavior is degrading before they go stale.

.DESCRIPTION
    This script retrieves all Intune managed devices and buckets them by how recently
    they checked in: healthy (synced within the healthy threshold), drifting (missed
    the healthy window but not yet stale), and stale. Unlike a plain stale-device
    report, the drifting bucket surfaces devices that are on their way to becoming
    unmanaged - for example laptops that stopped syncing two weeks ago - while there
    is still time to intervene. Results include per-platform distribution and can be
    exported to CSV.

.TAGS
    Diagnostics,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-device-checkin-health.ps1
    Buckets devices as healthy (7 days), drifting (7-30 days), and stale (over 30 days)

.EXAMPLE
    .\get-device-checkin-health.ps1 -HealthyDays 3 -StaleDays 21
    Uses tighter thresholds: healthy within 3 days, stale after 21 days

.EXAMPLE
    .\get-device-checkin-health.ps1 -ExportToCsv
    Exports the full device list with health buckets to a timestamped CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Devices that never synced (no lastSyncDateTime) are reported in their own bucket
    - Complements get-stale-devices: this script focuses on the drifting middle band, not just the stale tail
    - Uses beta Graph endpoints for consistency with the rest of the library
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Days within which a device counts as healthy")]
    [ValidateRange(1, 90)]
    [int]$HealthyDays = 7,

    [Parameter(Mandatory = $false, HelpMessage = "Days after which a device counts as stale")]
    [ValidateRange(2, 365)]
    [int]$StaleDays = 30,

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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    if ($HealthyDays -ge $StaleDays) {
        throw "-HealthyDays ($HealthyDays) must be smaller than -StaleDays ($StaleDays)"
    }

    Write-Information "Retrieving managed devices..." -InformationAction Continue
    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,lastSyncDateTime,enrolledDateTime,userPrincipalName,complianceState,managementAgent,ownerType"
    Write-Information "✓ Found $(@($devices).Count) managed devices" -InformationAction Continue

    $now = Get-Date
    [System.Collections.Generic.List[Object]]$report = @()

    foreach ($device in $devices) {
        # Graph returns null lastSyncDateTime for brand-new or broken enrollments;
        # parsing without a guard would throw
        $lastSync = if ($device.lastSyncDateTime) { [DateTime]::Parse($device.lastSyncDateTime.ToString()) } else { $null }
        $enrolled = if ($device.enrolledDateTime) { [DateTime]::Parse($device.enrolledDateTime.ToString()) } else { $null }

        $daysSinceSync = if ($lastSync) { [math]::Round(($now - $lastSync).TotalDays, 1) } else { $null }

        $bucket = if ($null -eq $lastSync) {
            "Never synced"
        }
        elseif ($daysSinceSync -le $HealthyDays) {
            "Healthy"
        }
        elseif ($daysSinceSync -le $StaleDays) {
            "Drifting"
        }
        else {
            "Stale"
        }

        $report.Add([PSCustomObject]@{
                DeviceName      = $device.deviceName
                User            = $device.userPrincipalName
                OperatingSystem = $device.operatingSystem
                OsVersion       = $device.osVersion
                Ownership       = $device.ownerType
                ComplianceState = $device.complianceState
                LastSync        = if ($lastSync) { $lastSync.ToString("yyyy-MM-dd HH:mm") } else { "" }
                DaysSinceSync   = $daysSinceSync
                Enrolled        = if ($enrolled) { $enrolled.ToString("yyyy-MM-dd") } else { "" }
                HealthBucket    = $bucket
                DeviceId        = $device.id
            })
    }

    # ----- Display results -----
    Write-Information "`nDEVICE CHECK-IN HEALTH REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Thresholds: healthy <= $HealthyDays days, stale > $StaleDays days" -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    $bucketOrder = @("Healthy", "Drifting", "Stale", "Never synced")
    foreach ($bucketName in $bucketOrder) {
        $bucketDevices = @($report | Where-Object { $_.HealthBucket -eq $bucketName })
        if ($bucketDevices.Count -eq 0) { continue }

        Write-Information "`n$bucketName ($($bucketDevices.Count) devices)" -InformationAction Continue

        # The drifting bucket is the actionable one; list it in full detail
        if ($bucketName -in @("Drifting", "Stale", "Never synced")) {
            foreach ($row in ($bucketDevices | Sort-Object DaysSinceSync -Descending)) {
                $syncInfo = if ($null -ne $row.DaysSinceSync) { "$($row.DaysSinceSync) days ago" } else { "never" }
                Write-Information "  $($row.DeviceName) | $($row.OperatingSystem) | $($row.User) | last sync: $syncInfo" -InformationAction Continue
            }
        }
        else {
            foreach ($platformGroup in ($bucketDevices | Group-Object -Property OperatingSystem | Sort-Object Count -Descending)) {
                Write-Information "  $($platformGroup.Name): $($platformGroup.Count)" -InformationAction Continue
            }
        }
    }

    # Summary with percentage distribution
    $totalCount = $report.Count
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    foreach ($bucketName in $bucketOrder) {
        $bucketCount = @($report | Where-Object { $_.HealthBucket -eq $bucketName }).Count
        if ($totalCount -gt 0) {
            $percent = [math]::Round(($bucketCount / $totalCount) * 100, 1)
            Write-Information "$($bucketName): $bucketCount ($percent%)" -InformationAction Continue
        }
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Device_Checkin_Health_$timestamp.csv"
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
