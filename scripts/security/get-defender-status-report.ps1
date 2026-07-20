<#
.TITLE
    Get Defender Status Report

.SYNOPSIS
    Reports Microsoft Defender health across all Windows devices: protection state, signature age, and devices needing attention.

.DESCRIPTION
    This script reads the tenant-wide device protection overview and the per-device
    Windows protection state to report Microsoft Defender health: real-time
    protection, tamper protection, malware protection, signature currency, overdue
    scans, pending reboots, and devices whose state is not clean. Use it to find the
    machines where Defender is silently off or outdated before they become incident
    tickets.

.TAGS
    Security,Monitoring

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
    .\get-defender-status-report.ps1
    Reports Defender health for all Windows devices

.EXAMPLE
    .\get-defender-status-report.ps1 -OnlyIssues
    Lists only devices with at least one Defender health issue

.EXAMPLE
    .\get-defender-status-report.ps1 -ExportToCsv
    Exports the full per-device Defender state to a timestamped CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Protection state is fetched per device (one request each); large tenants take a few minutes
    - Devices that never reported protection state are listed separately
    - Uses beta Graph endpoints because windowsProtectionState is exposed there
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Show only devices with Defender issues")]
    [switch]$OnlyIssues,

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

function Get-DefenderIssue {
    param([object]$ProtectionState)

    $issues = [System.Collections.Generic.List[string]]::new()

    if ($ProtectionState.malwareProtectionEnabled -ne $true) { $issues.Add("Malware protection disabled") }
    if ($ProtectionState.realTimeProtectionEnabled -ne $true) { $issues.Add("Real-time protection disabled") }
    if ($ProtectionState.tamperProtectionEnabled -ne $true) { $issues.Add("Tamper protection disabled") }
    if ($ProtectionState.signatureUpdateOverdue -eq $true) { $issues.Add("Signature update overdue") }
    if ($ProtectionState.quickScanOverdue -eq $true) { $issues.Add("Quick scan overdue") }
    if ($ProtectionState.fullScanOverdue -eq $true) { $issues.Add("Full scan overdue") }
    if ($ProtectionState.rebootRequired -eq $true) { $issues.Add("Reboot required") }
    if ($ProtectionState.deviceState -and $ProtectionState.deviceState -ne "clean") { $issues.Add("Device state: $($ProtectionState.deviceState)") }

    return @($issues)
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    # Tenant-wide overview first - cheap and gives immediate context
    Write-Information "Retrieving tenant protection overview..." -InformationAction Continue
    $overview = $null
    try {
        $overview = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceProtectionOverview" -Method GET
    }
    catch {
        Write-Warning "Could not read the device protection overview: $($_.Exception.Message)"
    }

    Write-Information "Retrieving Windows devices..." -InformationAction Continue
    $windowsDevices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'&`$select=id,deviceName,userPrincipalName,lastSyncDateTime"
    Write-Information "✓ Found $(@($windowsDevices).Count) Windows devices - fetching protection state per device..." -InformationAction Continue

    [System.Collections.Generic.List[Object]]$report = @()
    $noStateCount = 0
    $processedCount = 0

    foreach ($device in $windowsDevices) {
        $processedCount++
        if ($processedCount % 50 -eq 0) {
            Write-Information "  Processed $processedCount of $(@($windowsDevices).Count)..." -InformationAction Continue
        }

        $protectionState = $null
        try {
            Start-Sleep -Milliseconds 100
            $protectionState = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/windowsProtectionState" -Method GET
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                try {
                    $protectionState = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/windowsProtectionState" -Method GET
                }
                catch {
                    Write-Verbose "No protection state for '$($device.deviceName)': $($_.Exception.Message)"
                }
            }
            else {
                Write-Verbose "No protection state for '$($device.deviceName)': $($_.Exception.Message)"
            }
        }

        if (-not $protectionState -or -not $protectionState.lastReportedDateTime) {
            $noStateCount++
            $report.Add([PSCustomObject]@{
                    DeviceName         = $device.deviceName
                    User               = $device.userPrincipalName
                    DeviceState        = "NotReported"
                    RealTimeProtection = ""
                    TamperProtection   = ""
                    SignatureVersion   = ""
                    SignatureOverdue   = ""
                    LastReported       = ""
                    Issues             = "No Defender state reported"
                    IssueCount         = 1
                })
            continue
        }

        $issues = Get-DefenderIssue -ProtectionState $protectionState
        $lastReported = if ($protectionState.lastReportedDateTime) { [DateTime]::Parse($protectionState.lastReportedDateTime.ToString()) } else { $null }

        $report.Add([PSCustomObject]@{
                DeviceName         = $device.deviceName
                User               = $device.userPrincipalName
                DeviceState        = $protectionState.deviceState
                RealTimeProtection = $protectionState.realTimeProtectionEnabled
                TamperProtection   = $protectionState.tamperProtectionEnabled
                SignatureVersion   = $protectionState.signatureVersion
                SignatureOverdue   = $protectionState.signatureUpdateOverdue
                LastReported       = if ($lastReported) { $lastReported.ToString("yyyy-MM-dd HH:mm") } else { "" }
                Issues             = ($issues -join "; ")
                IssueCount         = $issues.Count
            })
    }

    # ----- Display results -----
    Write-Information "`nDEFENDER STATUS REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    if ($overview) {
        Write-Information "`nTenant overview:" -InformationAction Continue
        Write-Information "  Reporting devices:        $($overview.totalReportedDeviceCount)" -InformationAction Continue
        Write-Information "  Clean:                    $($overview.cleanDeviceCount)" -InformationAction Continue
        Write-Information "  Critical failures:        $($overview.criticalFailuresDeviceCount)" -InformationAction Continue
        Write-Information "  Pending signature update: $($overview.pendingSignatureUpdateDeviceCount)" -InformationAction Continue
        Write-Information "  Pending restart:          $($overview.pendingRestartDeviceCount)" -InformationAction Continue
        Write-Information "  Inactive agent:           $($overview.inactiveThreatAgentDeviceCount)" -InformationAction Continue
    }

    $devicesWithIssues = @($report | Where-Object { $_.IssueCount -gt 0 })
    $healthyDevices = @($report | Where-Object { $_.IssueCount -eq 0 })

    if ($devicesWithIssues.Count -gt 0) {
        Write-Information "`nDevices with issues ($($devicesWithIssues.Count)):" -InformationAction Continue
        foreach ($row in ($devicesWithIssues | Sort-Object IssueCount -Descending)) {
            Write-Information "  $($row.DeviceName) | $($row.User)" -InformationAction Continue
            Write-Information "    $($row.Issues)" -InformationAction Continue
        }
    }

    if (-not $OnlyIssues -and $healthyDevices.Count -gt 0) {
        Write-Information "`nHealthy devices ($($healthyDevices.Count)):" -InformationAction Continue
        foreach ($row in ($healthyDevices | Sort-Object DeviceName)) {
            Write-Information "  $($row.DeviceName) | signatures $($row.SignatureVersion) | reported $($row.LastReported)" -InformationAction Continue
        }
    }

    # Summary
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) Windows devices | $($healthyDevices.Count) healthy | $($devicesWithIssues.Count) with issues | $noStateCount never reported" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Defender_Status_$timestamp.csv"
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
