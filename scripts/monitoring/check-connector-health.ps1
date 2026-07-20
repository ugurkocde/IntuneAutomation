<#
.TITLE
    Check Connector Health

.SYNOPSIS
    One health report for every Intune tenant connector: Apple DEP/APNs/VPP, Managed Google Play, NDES, certificate connectors, and Mobile Threat Defense.

.DESCRIPTION
    This script checks the health of all tenant-level Intune connectors in a single
    run: Apple push notification certificate and DEP token expiry and sync state,
    VPP tokens, the Managed Google Play binding and app sync status, NDES and
    certificate connectors, and Mobile Threat Defense partner connectors with their
    heartbeat state. Every connector is scored healthy, warning, or critical, so a
    silent connector failure (expired token, stale sync, unresponsive partner)
    surfaces before users notice broken enrollments or app installs.

.TAGS
    Monitoring

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementServiceConfig.Read.All,DeviceManagementConfiguration.Read.All,DeviceManagementApps.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\check-connector-health.ps1
    Checks all connectors with a 30-day expiry warning window

.EXAMPLE
    .\check-connector-health.ps1 -ExpiryWarningDays 60 -ExportToCsv
    Uses a 60-day warning window and exports the report to CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Connectors that are not configured in the tenant are reported as NotConfigured, not as failures
    - Sync staleness thresholds: DEP sync older than 7 days and Google Play app sync older than 7 days raise warnings
    - Uses beta Graph endpoints because most connector surfaces are not exposed on v1.0
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Days before certificate/token expiry to raise a warning")]
    [ValidateRange(1, 365)]
    [int]$ExpiryWarningDays = 30,

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
            "DeviceManagementServiceConfig.Read.All",
            "DeviceManagementConfiguration.Read.All",
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

$script:ConnectorReport = [System.Collections.Generic.List[Object]]::new()

function Add-ConnectorResult {
    param(
        [string]$Connector,
        [string]$Instance,
        [string]$Status,
        [string]$Detail
    )

    $script:ConnectorReport.Add([PSCustomObject]@{
            Connector = $Connector
            Instance  = $Instance
            Status    = $Status
            Detail    = $Detail
        })
}

function Get-ExpiryStatus {
    param(
        [object]$ExpiryValue,
        [int]$WarningDays
    )

    if (-not $ExpiryValue) {
        return @{ Status = "Warning"; Detail = "No expiration date available" }
    }

    $expiry = [DateTime]::Parse($ExpiryValue.ToString())
    $daysLeft = [math]::Round(($expiry - (Get-Date)).TotalDays, 0)

    if ($daysLeft -lt 0) {
        return @{ Status = "Critical"; Detail = "EXPIRED $([math]::Abs($daysLeft)) days ago ($($expiry.ToString('yyyy-MM-dd')))" }
    }
    if ($daysLeft -le $WarningDays) {
        return @{ Status = "Warning"; Detail = "Expires in $daysLeft days ($($expiry.ToString('yyyy-MM-dd')))" }
    }
    return @{ Status = "Healthy"; Detail = "Expires in $daysLeft days ($($expiry.ToString('yyyy-MM-dd')))" }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    $staleSyncThreshold = (Get-Date).AddDays(-7)

    # ----- Apple push notification certificate -----
    Write-Information "Checking Apple MDM push certificate..." -InformationAction Continue
    try {
        $apns = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate" -Method GET
        if ($apns -and $apns.appleIdentifier) {
            $expiryInfo = Get-ExpiryStatus -ExpiryValue $apns.expirationDateTime -WarningDays $ExpiryWarningDays
            Add-ConnectorResult -Connector "Apple MDM Push Certificate" -Instance $apns.appleIdentifier -Status $expiryInfo.Status -Detail $expiryInfo.Detail
        }
        else {
            Add-ConnectorResult -Connector "Apple MDM Push Certificate" -Instance "-" -Status "NotConfigured" -Detail "No APNs certificate uploaded"
        }
    }
    catch {
        Add-ConnectorResult -Connector "Apple MDM Push Certificate" -Instance "-" -Status "NotConfigured" -Detail "Not configured or not readable"
    }

    # ----- Apple DEP tokens -----
    Write-Information "Checking Apple DEP tokens..." -InformationAction Continue
    try {
        $depTokens = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings"
        if (@($depTokens).Count -eq 0) {
            Add-ConnectorResult -Connector "Apple DEP Token" -Instance "-" -Status "NotConfigured" -Detail "No Automated Device Enrollment tokens"
        }
        foreach ($token in $depTokens) {
            $expiryInfo = Get-ExpiryStatus -ExpiryValue $token.tokenExpirationDateTime -WarningDays $ExpiryWarningDays
            $status = $expiryInfo.Status
            $detail = $expiryInfo.Detail

            # A valid token with a failing or stale sync is still broken
            $lastSync = if ($token.lastSuccessfulSyncDateTime) { [DateTime]::Parse($token.lastSuccessfulSyncDateTime.ToString()) } else { $null }
            if ($token.lastSyncErrorCode -and $token.lastSyncErrorCode -ne 0) {
                if ($status -eq "Healthy") { $status = "Warning" }
                $detail += " | last sync error code: $($token.lastSyncErrorCode)"
            }
            if ($lastSync -and $lastSync -lt $staleSyncThreshold) {
                if ($status -eq "Healthy") { $status = "Warning" }
                $detail += " | last successful sync: $($lastSync.ToString('yyyy-MM-dd'))"
            }

            Add-ConnectorResult -Connector "Apple DEP Token" -Instance $token.tokenName -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "Apple DEP Token" -Instance "-" -Status "Error" -Detail $_.Exception.Message
    }

    # ----- Apple VPP tokens -----
    Write-Information "Checking Apple VPP tokens..." -InformationAction Continue
    try {
        $vppTokens = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceAppManagement/vppTokens"
        if (@($vppTokens).Count -eq 0) {
            Add-ConnectorResult -Connector "Apple VPP Token" -Instance "-" -Status "NotConfigured" -Detail "No VPP tokens"
        }
        foreach ($token in $vppTokens) {
            $expiryInfo = Get-ExpiryStatus -ExpiryValue $token.expirationDateTime -WarningDays $ExpiryWarningDays
            $status = if ($token.state -ne "valid") { "Critical" } else { $expiryInfo.Status }
            $detail = "State: $($token.state) | $($expiryInfo.Detail)"
            Add-ConnectorResult -Connector "Apple VPP Token" -Instance $token.appleId -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "Apple VPP Token" -Instance "-" -Status "Error" -Detail $_.Exception.Message
    }

    # ----- Managed Google Play -----
    Write-Information "Checking Managed Google Play binding..." -InformationAction Continue
    try {
        $googlePlay = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/androidManagedStoreAccountEnterpriseSettings" -Method GET
        if ($googlePlay.bindStatus -eq "notBound") {
            Add-ConnectorResult -Connector "Managed Google Play" -Instance "-" -Status "NotConfigured" -Detail "Tenant is not bound to Managed Google Play"
        }
        else {
            $status = "Healthy"
            $detail = "Bind status: $($googlePlay.bindStatus) | app sync: $($googlePlay.lastAppSyncStatus)"

            if ($googlePlay.lastAppSyncStatus -notin @("success", "none")) {
                $status = "Warning"
            }
            $lastAppSync = if ($googlePlay.lastAppSyncDateTime) { [DateTime]::Parse($googlePlay.lastAppSyncDateTime.ToString()) } else { $null }
            if ($lastAppSync) {
                $detail += " | last sync: $($lastAppSync.ToString('yyyy-MM-dd'))"
                if ($lastAppSync -lt $staleSyncThreshold) { $status = "Warning" }
            }

            Add-ConnectorResult -Connector "Managed Google Play" -Instance $googlePlay.ownerOrganizationName -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "Managed Google Play" -Instance "-" -Status "Error" -Detail $_.Exception.Message
    }

    # ----- NDES connectors -----
    Write-Information "Checking NDES connectors..." -InformationAction Continue
    try {
        $ndesConnectors = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/ndesConnectors"
        if (@($ndesConnectors).Count -eq 0) {
            Add-ConnectorResult -Connector "NDES Connector" -Instance "-" -Status "NotConfigured" -Detail "No NDES connectors installed"
        }
        foreach ($connector in $ndesConnectors) {
            $status = if ($connector.state -eq "active") { "Healthy" } else { "Critical" }
            $lastConnection = if ($connector.lastConnectionDateTime) { [DateTime]::Parse($connector.lastConnectionDateTime.ToString()) } else { $null }
            $detail = "State: $($connector.state)"
            if ($lastConnection) {
                $detail += " | last connection: $($lastConnection.ToString('yyyy-MM-dd HH:mm'))"
                if ($lastConnection -lt $staleSyncThreshold -and $status -eq "Healthy") { $status = "Warning" }
            }
            Add-ConnectorResult -Connector "NDES Connector" -Instance $connector.displayName -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "NDES Connector" -Instance "-" -Status "Error" -Detail $_.Exception.Message
    }

    # ----- Certificate connectors -----
    Write-Information "Checking certificate connectors..." -InformationAction Continue
    try {
        # This surface returns errors in tenants that never installed a connector
        $certificateConnectors = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/certificateConnectorDetails"
        if (@($certificateConnectors).Count -eq 0) {
            Add-ConnectorResult -Connector "Certificate Connector" -Instance "-" -Status "NotConfigured" -Detail "No certificate connectors installed"
        }
        foreach ($connector in $certificateConnectors) {
            $lastCheckIn = if ($connector.lastCheckinDateTime) { [DateTime]::Parse($connector.lastCheckinDateTime.ToString()) } else { $null }
            $status = "Healthy"
            $detail = "Version: $($connector.connectorVersion)"
            if ($lastCheckIn) {
                $detail += " | last check-in: $($lastCheckIn.ToString('yyyy-MM-dd HH:mm'))"
                if ($lastCheckIn -lt $staleSyncThreshold) { $status = "Critical" }
            }
            Add-ConnectorResult -Connector "Certificate Connector" -Instance $connector.machineName -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "Certificate Connector" -Instance "-" -Status "NotConfigured" -Detail "No certificate connector infrastructure in this tenant"
    }

    # ----- Mobile Threat Defense connectors -----
    Write-Information "Checking Mobile Threat Defense connectors..." -InformationAction Continue
    try {
        $mtdConnectors = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors"
        if (@($mtdConnectors).Count -eq 0) {
            Add-ConnectorResult -Connector "Mobile Threat Defense" -Instance "-" -Status "NotConfigured" -Detail "No MTD connectors"
        }
        foreach ($connector in $mtdConnectors) {
            $status = switch ($connector.partnerState) {
                "available" { "Healthy" }
                "enabled" { "Healthy" }
                "unresponsive" { "Critical" }
                default { "Warning" }
            }
            $lastHeartbeat = if ($connector.lastHeartbeatDateTime) { [DateTime]::Parse($connector.lastHeartbeatDateTime.ToString()) } else { $null }
            $detail = "Partner state: $($connector.partnerState)"
            if ($lastHeartbeat) {
                $detail += " | last heartbeat: $($lastHeartbeat.ToString('yyyy-MM-dd HH:mm'))"
            }
            Add-ConnectorResult -Connector "Mobile Threat Defense" -Instance $connector.id -Status $status -Detail $detail
        }
    }
    catch {
        Add-ConnectorResult -Connector "Mobile Threat Defense" -Instance "-" -Status "Error" -Detail $_.Exception.Message
    }

    # ----- Display results -----
    Write-Information "`nCONNECTOR HEALTH REPORT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Warning window: $ExpiryWarningDays days | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    $statusOrder = @("Critical", "Warning", "Error", "Healthy", "NotConfigured")
    foreach ($statusName in $statusOrder) {
        $rows = @($script:ConnectorReport | Where-Object { $_.Status -eq $statusName })
        if ($rows.Count -eq 0) { continue }

        Write-Information "`n[$statusName]" -InformationAction Continue
        foreach ($row in $rows) {
            Write-Information "  $($row.Connector) | $($row.Instance)" -InformationAction Continue
            Write-Information "    $($row.Detail)" -InformationAction Continue
        }
    }

    # Summary
    $criticalCount = @($script:ConnectorReport | Where-Object { $_.Status -eq "Critical" }).Count
    $warningCount = @($script:ConnectorReport | Where-Object { $_.Status -eq "Warning" }).Count
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($script:ConnectorReport.Count) connector checks | $criticalCount critical | $warningCount warnings" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Connector_Health_$timestamp.csv"
        $script:ConnectorReport | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
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
