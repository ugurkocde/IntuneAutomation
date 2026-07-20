<#
.TITLE
    Get VPP License Report

.SYNOPSIS
    Reports Apple VPP app license utilization and flags apps and tokens that are close to exhaustion or expiry.

.DESCRIPTION
    This script reads all Apple Volume Purchase Program tokens and VPP apps (iOS and
    macOS) from Intune and reports used versus total licenses per app, highlighting
    apps above a configurable utilization threshold. VPP token state and expiration
    are included because an expired token silently breaks app installs. Use it to
    buy licenses before users hit "installation failed" and to catch tokens that
    need renewal.

.TAGS
    Apps,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementApps.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\get-vpp-license-report.ps1
    Reports all VPP apps with their license utilization

.EXAMPLE
    .\get-vpp-license-report.ps1 -WarningThresholdPercent 80
    Flags apps that have used 80 percent or more of their licenses

.EXAMPLE
    .\get-vpp-license-report.ps1 -ExportToCsv
    Exports the license report to a timestamped CSV file

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Tenants without Apple VPP (Apps and Books) configured will report no tokens and no apps
    - License counts come from the iosVppApp and macOsVppApp usedLicenseCount / totalLicenseCount properties
    - Uses beta Graph endpoints because VPP app license properties are exposed there
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Utilization percentage above which an app is flagged")]
    [ValidateRange(1, 100)]
    [int]$WarningThresholdPercent = 90,

    [Parameter(Mandatory = $false, HelpMessage = "Days before token expiry to flag a VPP token")]
    [ValidateRange(1, 365)]
    [int]$TokenExpiryWarningDays = 30,

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
            "DeviceManagementApps.Read.All"
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
    # ----- VPP tokens -----
    Write-Information "Retrieving VPP tokens..." -InformationAction Continue
    $tokens = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/vppTokens"
    Write-Information "✓ Found $(@($tokens).Count) VPP token(s)" -InformationAction Continue

    # ----- VPP apps (iOS and macOS) -----
    Write-Information "Retrieving VPP apps..." -InformationAction Continue
    $iosVppApps = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.iosVppApp')"
    $macVppApps = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.macOsVppApp')"
    $vppApps = @($iosVppApps) + @($macVppApps)
    Write-Information "✓ Found $(@($vppApps).Count) VPP app(s)" -InformationAction Continue

    if (@($tokens).Count -eq 0 -and @($vppApps).Count -eq 0) {
        Write-Information "`nNo Apple VPP tokens or apps found - is Apple Apps and Books configured for this tenant?" -InformationAction Continue
        return
    }

    [System.Collections.Generic.List[Object]]$report = @()
    foreach ($app in $vppApps) {
        $total = [int]$app.totalLicenseCount
        $used = [int]$app.usedLicenseCount
        $utilization = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }

        $status = if ($total -eq 0) { "NoLicenses" }
        elseif ($utilization -ge 100) { "Exhausted" }
        elseif ($utilization -ge $WarningThresholdPercent) { "NearLimit" }
        else { "OK" }

        $platform = if ($app.'@odata.type' -like "*macOsVppApp") { "macOS" } else { "iOS" }

        $report.Add([PSCustomObject]@{
                AppName       = $app.displayName
                Platform      = $platform
                TokenAppleId  = $app.vppTokenAppleId
                UsedLicenses  = $used
                TotalLicenses = $total
                UtilizationPct = $utilization
                Status        = $status
                AppId         = $app.id
            })
    }

    # ----- Display results -----
    Write-Information "`nVPP LICENSE REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Warning threshold: $WarningThresholdPercent% | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Token health first - expired tokens break everything downstream
    if (@($tokens).Count -gt 0) {
        Write-Information "`nVPP tokens:" -InformationAction Continue
        foreach ($token in $tokens) {
            $expiry = if ($token.expirationDateTime) { [DateTime]::Parse($token.expirationDateTime.ToString()) } else { $null }
            $daysLeft = if ($expiry) { [math]::Round(($expiry - (Get-Date)).TotalDays, 0) } else { $null }

            $tokenLine = "  $($token.appleId) | state: $($token.state)"
            if ($null -ne $daysLeft) {
                $tokenLine += " | expires in $daysLeft days"
            }
            Write-Information $tokenLine -InformationAction Continue

            if ($token.state -ne "valid") {
                Write-Warning "  Token '$($token.appleId)' state is '$($token.state)' - VPP app installs may be failing"
            }
            elseif ($null -ne $daysLeft -and $daysLeft -le $TokenExpiryWarningDays) {
                Write-Warning "  Token '$($token.appleId)' expires in $daysLeft days - renew it in Apple Business Manager"
            }
        }
    }

    if ($report.Count -gt 0) {
        foreach ($statusGroup in ($report | Group-Object -Property Status | Sort-Object Name)) {
            Write-Information "`n[$($statusGroup.Name)] $($statusGroup.Count) app(s)" -InformationAction Continue
            foreach ($row in ($statusGroup.Group | Sort-Object UtilizationPct -Descending)) {
                Write-Information "  $($row.AppName) ($($row.Platform)): $($row.UsedLicenses)/$($row.TotalLicenses) licenses ($($row.UtilizationPct)%)" -InformationAction Continue
            }
        }
    }

    # Summary
    $flagged = @($report | Where-Object { $_.Status -in @("NearLimit", "Exhausted") })
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) VPP apps, $($flagged.Count) at or above $WarningThresholdPercent% utilization" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "VPP_License_Report_$timestamp.csv"
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
