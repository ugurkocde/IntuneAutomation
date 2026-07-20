<#
.TITLE
    Get Windows LAPS Audit

.SYNOPSIS
    Audits Windows LAPS password escrow: which devices have a backed-up local admin password and how old it is.

.DESCRIPTION
    This script lists all device local credential records escrowed by Windows LAPS in
    Entra ID and cross-references them with Intune Windows devices. It reports which
    devices have no escrowed local administrator password at all, and which have
    passwords older than the rotation threshold - both signs that the LAPS policy is
    not applying. Only credential metadata (device name, backup time) is read; actual
    passwords are never retrieved by this script.

.TAGS
    Security,Compliance

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceLocalCredential.ReadBasic.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-windows-laps-audit.ps1
    Audits LAPS escrow state for all Windows devices with a 60-day age threshold

.EXAMPLE
    .\get-windows-laps-audit.ps1 -MaxPasswordAgeDays 30 -ExportToCsv
    Flags passwords older than 30 days and exports the audit to CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Reading LAPS credential metadata is limited to specific roles; Intune Administrator is one of the allowed roles
    - This script uses DeviceLocalCredential.ReadBasic.All and never retrieves password values
    - Devices are matched between the LAPS store and Intune via the Entra device ID
    - Uses beta Graph endpoints for the device local credentials surface
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Password age in days above which escrow is flagged as stale")]
    [ValidateRange(1, 365)]
    [int]$MaxPasswordAgeDays = 60,

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
            "DeviceLocalCredential.ReadBasic.All",
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
    Write-Information "Retrieving Windows LAPS credential records..." -InformationAction Continue
    $lapsRecords = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/directory/deviceLocalCredentials?`$select=id,deviceName,lastBackupDateTime"
    Write-Information "✓ Found $(@($lapsRecords).Count) escrowed LAPS records" -InformationAction Continue

    Write-Information "Retrieving Intune Windows devices..." -InformationAction Continue
    $windowsDevices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=id,deviceName,azureADDeviceId,lastSyncDateTime,userPrincipalName"
    Write-Information "✓ Found $(@($windowsDevices).Count) Windows devices" -InformationAction Continue

    # LAPS record id is the Entra device ID; index for the cross-reference
    $lapsByDeviceId = @{}
    foreach ($record in $lapsRecords) {
        $lapsByDeviceId[$record.id] = $record
    }

    $now = Get-Date
    [System.Collections.Generic.List[Object]]$report = @()

    foreach ($device in $windowsDevices) {
        $lapsRecord = if ($device.azureADDeviceId -and $lapsByDeviceId.ContainsKey($device.azureADDeviceId)) {
            $lapsByDeviceId[$device.azureADDeviceId]
        }
        else {
            $null
        }

        $lastBackup = if ($lapsRecord -and $lapsRecord.lastBackupDateTime) {
            [DateTime]::Parse($lapsRecord.lastBackupDateTime.ToString())
        }
        else {
            $null
        }

        $ageDays = if ($lastBackup) { [math]::Round(($now - $lastBackup).TotalDays, 1) } else { $null }

        $status = if (-not $lapsRecord) { "NotEscrowed" }
        elseif ($null -eq $ageDays) { "EscrowedNoTimestamp" }
        elseif ($ageDays -gt $MaxPasswordAgeDays) { "Stale" }
        else { "Healthy" }

        $report.Add([PSCustomObject]@{
                DeviceName     = $device.deviceName
                User           = $device.userPrincipalName
                EntraDeviceId  = $device.azureADDeviceId
                LastBackup     = if ($lastBackup) { $lastBackup.ToString("yyyy-MM-dd HH:mm") } else { "" }
                PasswordAgeDays = $ageDays
                Status         = $status
            })
    }

    # ----- Display results -----
    Write-Information "`nWINDOWS LAPS AUDIT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Stale threshold: $MaxPasswordAgeDays days | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    $statusOrder = @("NotEscrowed", "Stale", "EscrowedNoTimestamp", "Healthy")
    foreach ($statusName in $statusOrder) {
        $statusDevices = @($report | Where-Object { $_.Status -eq $statusName })
        if ($statusDevices.Count -eq 0) { continue }

        Write-Information "`n[$statusName] $($statusDevices.Count) device(s)" -InformationAction Continue

        if ($statusName -ne "Healthy") {
            foreach ($row in ($statusDevices | Sort-Object DeviceName)) {
                $line = "  $($row.DeviceName) | $($row.User)"
                if ($row.LastBackup) { $line += " | last backup: $($row.LastBackup) ($($row.PasswordAgeDays) days)" }
                Write-Information $line -InformationAction Continue
            }
        }
    }

    if (@($report | Where-Object { $_.Status -eq "NotEscrowed" }).Count -gt 0) {
        Write-Information "`nDevices without escrow either have no Windows LAPS policy assigned or have not rotated since policy assignment." -InformationAction Continue
    }

    # Summary
    $escrowedCount = @($report | Where-Object { $_.Status -ne "NotEscrowed" }).Count
    $staleCount = @($report | Where-Object { $_.Status -eq "Stale" }).Count
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $(@($windowsDevices).Count) Windows devices | $escrowedCount escrowed | $staleCount stale | $(@($windowsDevices).Count - $escrowedCount) not escrowed" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Windows_LAPS_Audit_$timestamp.csv"
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
