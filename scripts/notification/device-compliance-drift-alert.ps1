<#
.TITLE
    Device Compliance Drift Alert Notification

.SYNOPSIS
    Automated runbook to monitor device compliance drift in Intune and send email alerts for compliance deterioration.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook that monitors device compliance
    status in Microsoft Intune and identifies devices that have fallen out of compliance. It tracks compliance
    trends, identifies patterns of compliance deterioration, and sends email notifications to administrators
    with detailed compliance reports. The script helps maintain security posture by proactively alerting on
    compliance drift and providing actionable insights for remediation.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementConfiguration.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - Mail now sends from a mandatory SenderUPN mailbox via /users/{upn}/sendMail (app-only managed identity cannot use /me); send failures now fail the run; per-device policy state calls are paced and fetch failures are summarized in a warning; device listing uses select; pagination helper preserves single-item arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing); assigned compliance policy is now resolved via per-device deviceCompliancePolicyStates for reported devices
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Daily

.CATEGORY
    Notification

.EXAMPLE
    .\device-compliance-drift-alert.ps1 -ComplianceThresholdPercent 85 -EmailRecipients "<recipient-address>" -SenderUPN "<sender-upn>"
    Alerts when overall compliance falls below 85% and sends notifications to <recipient-address>

.EXAMPLE
    .\device-compliance-drift-alert.ps1 -ComplianceThresholdPercent 90 -EmailRecipients "<recipient-address>,<security-recipient-address>" -SenderUPN "<sender-upn>"
    Alerts when overall compliance falls below 90% and sends notifications to multiple recipients

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - For Azure Automation, configure Managed Identity with required permissions
    - Uses Microsoft Graph Mail API for email notifications only, sent from the SenderUPN mailbox
    - The Automation account's managed identity requires Mail.Send permission for the SenderUPN mailbox
    - Recommended to run as scheduled runbook (daily)
    - Consider your organization's compliance requirements when setting threshold
    - Review compliance policies and device configurations based on findings
    - Critical for maintaining security posture and regulatory compliance
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Minimum compliance percentage threshold to trigger alerts")]
    [ValidateRange(50, 100)]
    [int]$ComplianceThresholdPercent,

    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to send notifications")]
    [ValidateNotNullOrEmpty()]
    [string]$EmailRecipients,

    [Parameter(Mandatory = $true, HelpMessage = "Mailbox UPN used as the notification sender (managed identity needs Mail.Send permission for it)")]
    [ValidateNotNullOrEmpty()]
    [string]$SenderUPN,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
if ([string]::IsNullOrWhiteSpace($forceModuleInstallRaw)) {
    $ForceModuleInstall = $false
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("true", "1", '$true')) {
    $ForceModuleInstall = $true
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("false", "0", '$false')) {
    $ForceModuleInstall = $false
}
else {
    throw "Parameter 'ForceModuleInstall' accepts only true, false, 1, 0, $true, or $false."
}

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
                $errorMessage = @"
Module '$ModuleName' is not available in this Azure Automation Account.

To resolve this issue:
1. Go to Azure Portal
2. Navigate to your Automation Account
3. Go to 'Modules' > 'Browse Gallery'
4. Search for '$ModuleName'
5. Click 'Import' and wait for installation to complete

Required modules for this script:
- Microsoft.Graph.Authentication
"@
                throw $errorMessage
            }
            else {
                Write-Information "Module '$ModuleName' not found. Attempting to install..." -InformationAction Continue

                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }

                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

                    Write-Information "Installing '$ModuleName' in scope '$scope'..." -InformationAction Continue
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }

        try {
            Write-Verbose "Importing module: $ModuleName"
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Verbose "✓ Successfully imported '$ModuleName'"
        }
        catch {
            throw "Failed to import module '$ModuleName': $($_.Exception.Message)"
        }
    }
}

# Detect execution environment
if ($PSPrivateMetadata.JobId.Guid) {
    Write-Output "Running inside Azure Automation Runbook"
    $IsAzureAutomation = $true
}
else {
    Write-Output "Running locally in IDE or terminal"
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModuleList = @(
    "Microsoft.Graph.Authentication"
)

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModuleList += "MgGraphCommunity"
}

try {
    Initialize-RequiredModule -ModuleNames $RequiredModuleList -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
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
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        Write-Output "Connecting to Microsoft Graph with interactive authentication..."
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "Mail.Send"
        )

        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph"
    }
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
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $AllResults = @()
    $NextLink = $Uri
    $RequestCount = 0

    do {
        try {
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
            throw "Error fetching data from $NextLink : $($_.Exception.Message)"
        }
    } while ($NextLink)

    # Comma keeps PowerShell from unrolling a single-item array on return
    return , $AllResults
}

function Get-DevicePlatform {
    param([string]$OperatingSystem)

    switch -Regex ($OperatingSystem) {
        "^Windows" { return "Windows" }
        "^iOS" { return "iOS" }
        "^iPadOS" { return "iPadOS" }
        "^Android" { return "Android" }
        "^macOS" { return "macOS" }
        "^ChromeOS" { return "ChromeOS" }
        default { return "Other" }
    }
}

function Get-ComplianceStatus {
    param([string]$ComplianceState)

    switch ($ComplianceState) {
        "compliant" { return "Compliant" }
        "noncompliant" { return "Non-Compliant" }
        "conflict" { return "Conflict" }
        "error" { return "Error" }
        "unknown" { return "Unknown" }
        "notApplicable" { return "Not Applicable" }
        "inGracePeriod" { return "Grace Period" }
        default { return "Unknown" }
    }
}

function Get-ComplianceSeverity {
    param([string]$ComplianceState)

    switch ($ComplianceState) {
        "compliant" { return "Success" }
        "noncompliant" { return "Critical" }
        "conflict" { return "Warning" }
        "error" { return "Critical" }
        "inGracePeriod" { return "Warning" }
        default { return "Info" }
    }
}

function Format-TimeSpan {
    param([datetime]$Date)

    $TimeSpan = (Get-Date) - $Date

    if ($TimeSpan.TotalDays -lt 1) {
        return "Today"
    }
    elseif ($TimeSpan.TotalDays -lt 2) {
        return "1 day ago"
    }
    else {
        return "$([math]::Round($TimeSpan.TotalDays)) days ago"
    }
}

function Send-EmailNotification {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Recipients,
        [string]$Subject,
        [string]$Body
    )

    try {
        foreach ($Recipient in $Recipients) {
            $Message = @{
                subject      = $Subject
                body         = @{
                    contentType = "HTML"
                    content     = $Body
                }
                toRecipients = @(
                    @{
                        emailAddress = @{
                            address = $Recipient
                        }
                    }
                )
            }

            $RequestBody = @{
                message = $Message
            } | ConvertTo-Json -Depth 10

            if ($PSCmdlet.ShouldProcess($Recipient, "Send Email Notification")) {
                $Uri = "https://graph.microsoft.com/beta/users/$SenderUPN/sendMail"
                Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $RequestBody -ContentType "application/json" | Out-Null
                Write-Information "✓ Email sent to $Recipient via Microsoft Graph" -InformationAction Continue
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to send email notification: $($_.Exception.Message)"
        return $false
    }
}

# Function creates email content, does not change system state
function New-EmailBody {
    param(
        [array]$AllDevices,
        [array]$NonCompliantDevices,
        [array]$ConflictDevices,
        [array]$ErrorDevices,
        [array]$GracePeriodDevices,
        [int]$ComplianceThreshold
    )

    $TotalDevices = $AllDevices.Count
    $CompliantDevices = $AllDevices | Where-Object { $_.ComplianceStatus -eq "Compliant" }
    $CompliancePercentage = if ($TotalDevices -gt 0) { [math]::Round(($CompliantDevices.Count / $TotalDevices) * 100, 1) } else { 0 }

    $PlatformSummary = $NonCompliantDevices | Group-Object Platform | Sort-Object Name
    $PolicySummary = $NonCompliantDevices | Group-Object AssignedCompliancePolicy | Sort-Object Name

    $Body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; }
        .header { background-color: #0078d4; color: white; padding: 15px; border-radius: 5px; }
        .summary { background-color: #f8f9fa; padding: 15px; margin: 15px 0; border-radius: 5px; border-left: 4px solid #0078d4; }
        .critical { background-color: #fdf2f2; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        .warning { background-color: #fffbf0; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .success { background-color: #e8f5e8; border-left: 4px solid #28a745; padding: 10px; margin: 10px 0; }
        .info { background-color: #e7f3ff; border-left: 4px solid #17a2b8; padding: 10px; margin: 10px 0; }
        .device-item { margin: 5px 0; padding: 8px; background-color: white; border-radius: 3px; font-size: 14px; }
        .platform-summary { margin: 10px 0; padding: 8px; background-color: #f0f0f0; border-radius: 3px; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
        .stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 15px 0; }
        .stat-card { background-color: white; padding: 15px; border-radius: 5px; text-align: center; border: 1px solid #ddd; }
        .compliance-meter { width: 100%; height: 20px; background-color: #e0e0e0; border-radius: 10px; margin: 10px 0; position: relative; }
        .compliance-fill { height: 100%; border-radius: 10px; transition: width 0.3s ease; }
        .compliance-text { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-weight: bold; color: white; text-shadow: 1px 1px 1px rgba(0,0,0,0.5); }
        h2 { color: #333; }
        h3 { color: #555; margin-top: 20px; }
        .status-icon { font-size: 16px; margin-right: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .center { text-align: center; }
        .trend-indicator { font-weight: bold; font-size: 18px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ Device Compliance Drift Alert</h1>
        <p>Compliance threshold: $ComplianceThreshold% | Current: $CompliancePercentage%</p>
    </div>

    <div class="summary">
        <h2>Compliance Overview</h2>
        <div class="compliance-meter">
            <div class="compliance-fill" style="width: $CompliancePercentage%; background-color: $(if ($CompliancePercentage -ge $ComplianceThreshold) { '#28a745' } elseif ($CompliancePercentage -ge ($ComplianceThreshold * 0.8)) { '#ffc107' } else { '#dc3545' });"></div>
            <div class="compliance-text">$CompliancePercentage%</div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3 style="margin: 0; color: #28a745;">$($CompliantDevices.Count)</h3>
                <p style="margin: 5px 0;">Compliant Devices</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #dc3545;">$($NonCompliantDevices.Count)</h3>
                <p style="margin: 5px 0;">Non-Compliant</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #0078d4;">$TotalDevices</h3>
                <p style="margin: 5px 0;">Total Devices</p>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3 style="margin: 0; color: #ffc107;">$($ConflictDevices.Count)</h3>
                <p style="margin: 5px 0;">Conflicts</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #dc3545;">$($ErrorDevices.Count)</h3>
                <p style="margin: 5px 0;">Errors</p>
            </div>
            <div class="stat-card">
                <h3 style="margin: 0; color: #17a2b8;">$($GracePeriodDevices.Count)</h3>
                <p style="margin: 5px 0;">Grace Period</p>
            </div>
        </div>
    </div>
"@

    if ($NonCompliantDevices.Count -gt 0) {
        $Body += @"
    <div class="critical">
        <h3><span class="status-icon">🚨</span>Non-Compliant Devices - Immediate Attention Required ($($NonCompliantDevices.Count) devices)</h3>

        <h4>Platform Breakdown:</h4>
"@
        foreach ($Platform in $PlatformSummary) {
            $Body += @"
        <div class="platform-summary">
            <strong>$($Platform.Name):</strong> $($Platform.Count) devices
        </div>
"@
        }

        if ($PolicySummary.Count -gt 0) {
            $Body += @"
        <h4>Policy Breakdown:</h4>
"@
            foreach ($Policy in $PolicySummary) {
                $PolicyName = if ($Policy.Name) { $Policy.Name } else { "No Policy Assigned" }
                $Body += @"
        <div class="platform-summary">
            <strong>${PolicyName}:</strong> $($Policy.Count) devices
        </div>
"@
            }
        }

        $Body += @"
        <h4>Device Details:</h4>
        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Compliance Policy</th>
                <th>Last Check-in</th>
                <th>Days Since Check-in</th>
            </tr>
"@

        foreach ($Device in ($NonCompliantDevices | Sort-Object LastSyncDateTime -Descending | Select-Object -First 20)) {
            $DaysSinceSync = if ($Device.LastSyncDateTime) { ((Get-Date) - $Device.LastSyncDateTime).Days } else { "Unknown" }
            $PolicyName = if ($Device.AssignedCompliancePolicy) { $Device.AssignedCompliancePolicy } else { "No Policy" }
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$PolicyName</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm'))</td>
                <td class="center">$DaysSinceSync</td>
            </tr>
"@
        }

        if ($NonCompliantDevices.Count -gt 20) {
            $Body += @"
            <tr>
                <td colspan="6" class="center"><em>... and $($NonCompliantDevices.Count - 20) more devices</em></td>
            </tr>
"@
        }

        $Body += "</table></div>"
    }

    if ($ConflictDevices.Count -gt 0) {
        $Body += @"
    <div class="warning">
        <h3><span class="status-icon">⚠️</span>Devices with Policy Conflicts ($($ConflictDevices.Count) devices)</h3>
        <p>These devices have conflicting compliance policies that need resolution:</p>

        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Last Check-in</th>
            </tr>
"@

        foreach ($Device in ($ConflictDevices | Sort-Object LastSyncDateTime -Descending | Select-Object -First 10)) {
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm'))</td>
            </tr>
"@
        }

        if ($ConflictDevices.Count -gt 10) {
            $Body += @"
            <tr>
                <td colspan="4" class="center"><em>... and $($ConflictDevices.Count - 10) more devices</em></td>
            </tr>
"@
        }

        $Body += "</table></div>"
    }

    if ($ErrorDevices.Count -gt 0) {
        $Body += @"
    <div class="critical">
        <h3><span class="status-icon">❌</span>Devices with Compliance Errors ($($ErrorDevices.Count) devices)</h3>
        <p>These devices are experiencing errors in compliance evaluation:</p>

        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Last Check-in</th>
            </tr>
"@

        foreach ($Device in ($ErrorDevices | Sort-Object LastSyncDateTime -Descending | Select-Object -First 10)) {
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm'))</td>
            </tr>
"@
        }

        if ($ErrorDevices.Count -gt 10) {
            $Body += @"
            <tr>
                <td colspan="4" class="center"><em>... and $($ErrorDevices.Count - 10) more devices</em></td>
            </tr>
"@
        }

        $Body += "</table></div>"
    }

    if ($GracePeriodDevices.Count -gt 0) {
        $Body += @"
    <div class="info">
        <h3><span class="status-icon">⏰</span>Devices in Grace Period ($($GracePeriodDevices.Count) devices)</h3>
        <p>These devices are currently in grace period and will become non-compliant soon:</p>

        <table>
            <tr>
                <th>Device Name</th>
                <th>Platform</th>
                <th>User</th>
                <th>Last Check-in</th>
            </tr>
"@

        foreach ($Device in ($GracePeriodDevices | Sort-Object LastSyncDateTime -Descending | Select-Object -First 10)) {
            $Body += @"
            <tr>
                <td>$($Device.DeviceName)</td>
                <td>$($Device.Platform)</td>
                <td>$($Device.UserDisplayName)</td>
                <td>$($Device.LastSyncDateTime.ToString('yyyy-MM-dd HH:mm'))</td>
            </tr>
"@
        }

        if ($GracePeriodDevices.Count -gt 10) {
            $Body += @"
            <tr>
                <td colspan="4" class="center"><em>... and $($GracePeriodDevices.Count - 10) more devices</em></td>
            </tr>
"@
        }

        $Body += "</table></div>"
    }

    $Body += @"
    <div class="$(if ($CompliancePercentage -ge $ComplianceThreshold) { 'success' } else { 'critical' })">
        <h3><span class="status-icon">💡</span>Compliance Improvement Recommendations</h3>
        <h4>Immediate Actions:</h4>
        <ul>
            <li><strong>Review Non-Compliant Devices:</strong> Focus on devices that have been non-compliant the longest</li>
            <li><strong>Resolve Policy Conflicts:</strong> Address devices with conflicting compliance policies</li>
            <li><strong>Fix Compliance Errors:</strong> Investigate and resolve devices showing compliance evaluation errors</li>
            <li><strong>Monitor Grace Period:</strong> Proactively address devices in grace period before they become non-compliant</li>
        </ul>

        <h4>Policy Review:</h4>
        <ul>
            <li><strong>Compliance Policy Effectiveness:</strong> Review policies with high non-compliance rates</li>
            <li><strong>Policy Assignment:</strong> Ensure appropriate policies are assigned to device groups</li>
            <li><strong>Grace Period Settings:</strong> Adjust grace periods based on organizational needs</li>
            <li><strong>Remediation Actions:</strong> Configure automatic remediation where possible</li>
        </ul>

        <h4>User Communication:</h4>
        <ul>
            <li><strong>End User Education:</strong> Provide guidance on maintaining device compliance</li>
            <li><strong>Self-Service Options:</strong> Enable users to resolve common compliance issues</li>
            <li><strong>Clear Messaging:</strong> Ensure compliance notifications are actionable and clear</li>
        </ul>
    </div>

    <div class="footer">
        <p><strong>Next Steps:</strong></p>
        <ol>
            <li>Prioritize non-compliant devices by business criticality and security risk</li>
            <li>Use the existing device compliance script to get detailed compliance reports</li>
            <li>Review and update compliance policies based on common failure patterns</li>
            <li>Set up regular compliance monitoring and trend analysis</li>
        </ol>
        <p><em>This is an automated notification from your Intune monitoring system.</em></p>
        <p><em>Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</em></p>
    </div>
</body>
</html>
"@

    return $Body
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Starting device compliance drift monitoring..."

    # Parse email recipients
    $EmailRecipientList = $EmailRecipients -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    if ($EmailRecipientList.Count -eq 0) {
        throw "No valid email recipients provided"
    }

    Write-Output "Email recipients: $($EmailRecipientList -join ', ')"
    Write-Output "Compliance threshold: $ComplianceThresholdPercent%"

    # Initialize results arrays
    $AllDevices = @()
    $NonCompliantDevices = @()
    $ConflictDevices = @()
    $ErrorDevices = @()
    $GracePeriodDevices = @()
    $CompliancePolicies = @()
    $NotificationFailed = $false
    $PolicyStateFetchFailures = 0

    # ========================================================================
    # GET COMPLIANCE POLICIES
    # ========================================================================

    Write-Output "Retrieving compliance policies..."

    try {
        $PoliciesUri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"
        $CompliancePolicies = Get-MgGraphAllPage -Uri $PoliciesUri
        Write-Output "Found $($CompliancePolicies.Count) compliance policies"
    }
    catch {
        Write-Warning "Failed to retrieve compliance policies: $($_.Exception.Message)"
    }

    # ========================================================================
    # GET ALL MANAGED DEVICES WITH COMPLIANCE STATUS
    # ========================================================================

    Write-Output "Retrieving managed devices with compliance status..."

    try {
        $DevicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,userDisplayName,userPrincipalName,lastSyncDateTime,enrolledDateTime,complianceState,managementState,serialNumber,model,manufacturer,jailBroken,managementAgent"
        $Devices = Get-MgGraphAllPage -Uri $DevicesUri
        Write-Output "Found $($Devices.Count) managed devices"

        foreach ($Device in $Devices) {
            try {
                # Skip devices without essential information
                if (-not $Device.id) {
                    Write-Verbose "Skipping device with missing ID"
                    continue
                }

                $LastSyncDateTime = if ($Device.lastSyncDateTime) { [datetime]$Device.lastSyncDateTime } else { [datetime]::MinValue }
                $EnrolledDateTime = if ($Device.enrolledDateTime) { [datetime]$Device.enrolledDateTime } else { $null }
                $Platform = Get-DevicePlatform -OperatingSystem $Device.operatingSystem
                $ComplianceStatus = Get-ComplianceStatus -ComplianceState $Device.complianceState
                $ComplianceSeverity = Get-ComplianceSeverity -ComplianceState $Device.complianceState

                # Try to get the assigned compliance policy (fetched per device, only for reported states, to avoid throttling)
                $AssignedPolicy = "Unknown"
                if ($Device.complianceState -in @("noncompliant", "conflict", "error", "inGracePeriod")) {
                    try {
                        $PolicyStatesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($Device.id)')/deviceCompliancePolicyStates"
                        $PolicyStates = Get-MgGraphAllPage -Uri $PolicyStatesUri
                        $NonCompliantPolicies = @($PolicyStates | Where-Object { $_.state -eq "noncompliant" -and $_.displayName })
                        if ($NonCompliantPolicies.Count -gt 0) {
                            $AssignedPolicy = ($NonCompliantPolicies.displayName | Select-Object -Unique) -join "; "
                        }
                    }
                    catch {
                        $PolicyStateFetchFailures++
                        Write-Verbose "Could not retrieve compliance policy states for device $($Device.id): $($_.Exception.Message)"
                    }

                    # Pace per-device policy state calls to avoid throttling
                    Start-Sleep -Milliseconds 100
                }

                $DeviceInfo = [PSCustomObject]@{
                    DeviceId                 = $Device.id
                    DeviceName               = if ($Device.deviceName) { $Device.deviceName } else { "Unknown" }
                    Platform                 = $Platform
                    OperatingSystem          = $Device.operatingSystem
                    OSVersion                = $Device.osVersion
                    UserDisplayName          = if ($Device.userDisplayName) { $Device.userDisplayName } else { "Unassigned" }
                    UserPrincipalName        = if ($Device.userPrincipalName) { $Device.userPrincipalName } else { "N/A" }
                    LastSyncDateTime         = $LastSyncDateTime
                    EnrolledDateTime         = $EnrolledDateTime
                    ComplianceState          = $Device.complianceState
                    ComplianceStatus         = $ComplianceStatus
                    ComplianceSeverity       = $ComplianceSeverity
                    AssignedCompliancePolicy = $AssignedPolicy
                    ManagementState          = if ($Device.managementState) { $Device.managementState } else { "Unknown" }
                    SerialNumber             = $Device.serialNumber
                    Model                    = $Device.model
                    Manufacturer             = $Device.manufacturer
                    JailBroken               = $Device.jailBroken
                    ManagementAgent          = $Device.managementAgent
                }

                $AllDevices += $DeviceInfo

                # Categorize devices based on compliance status
                switch ($Device.complianceState) {
                    "noncompliant" { $NonCompliantDevices += $DeviceInfo }
                    "conflict" { $ConflictDevices += $DeviceInfo }
                    "error" { $ErrorDevices += $DeviceInfo }
                    "inGracePeriod" { $GracePeriodDevices += $DeviceInfo }
                }
            }
            catch {
                Write-Verbose "Error processing device (ID: $($Device.id)): $($_.Exception.Message)"
                continue
            }
        }

        Write-Output "✓ Processed $($AllDevices.Count) devices successfully"

        if ($PolicyStateFetchFailures -gt 0) {
            Write-Warning "Could not retrieve compliance policy states for $PolicyStateFetchFailures device(s); their assigned policy is reported as Unknown"
        }
    }
    catch {
        Write-Error "Failed to retrieve managed devices: $($_.Exception.Message)"
        exit 1
    }

    # ========================================================================
    # CALCULATE COMPLIANCE STATISTICS
    # ========================================================================

    $TotalDevices = $AllDevices.Count
    $CompliantDevices = $AllDevices | Where-Object { $_.ComplianceStatus -eq "Compliant" }
    $CompliancePercentage = if ($TotalDevices -gt 0) { [math]::Round(($CompliantDevices.Count / $TotalDevices) * 100, 1) } else { 0 }

    $ComplianceStats = @{
        TotalDevices         = $TotalDevices
        CompliantDevices     = $CompliantDevices.Count
        NonCompliantDevices  = $NonCompliantDevices.Count
        ConflictDevices      = $ConflictDevices.Count
        ErrorDevices         = $ErrorDevices.Count
        GracePeriodDevices   = $GracePeriodDevices.Count
        CompliancePercentage = $CompliancePercentage
        ThresholdMet         = $CompliancePercentage -ge $ComplianceThresholdPercent
    }

    Write-Output "  • Compliant devices: $($CompliantDevices.Count) ($CompliancePercentage%)"
    Write-Output "  • Non-compliant devices: $($NonCompliantDevices.Count)"
    Write-Output "  • Conflict devices: $($ConflictDevices.Count)"
    Write-Output "  • Error devices: $($ErrorDevices.Count)"
    Write-Output "  • Grace period devices: $($GracePeriodDevices.Count)"

    # ========================================================================
    # SEND NOTIFICATIONS IF COMPLIANCE DRIFT DETECTED
    # ========================================================================

    $RequiresNotification = ($CompliancePercentage -lt $ComplianceThresholdPercent) -or
                           ($NonCompliantDevices.Count -gt 0) -or
                           ($ConflictDevices.Count -gt 0) -or
                           ($ErrorDevices.Count -gt 0)

    if ($RequiresNotification) {
        Write-Output "Preparing email notification for compliance drift..."

        $Subject = if ($CompliancePercentage -lt $ComplianceThresholdPercent) {
            "[Intune Alert] COMPLIANCE DRIFT: $CompliancePercentage% Below Threshold ($ComplianceThresholdPercent%)"
        }
        elseif ($NonCompliantDevices.Count -gt 0) {
            "[Intune Alert] COMPLIANCE ISSUES: $($NonCompliantDevices.Count) Non-Compliant Device(s)"
        }
        else {
            "[Intune Alert] COMPLIANCE MONITORING: Policy Conflicts and Errors Detected"
        }

        $EmailBody = New-EmailBody -AllDevices $AllDevices -NonCompliantDevices $NonCompliantDevices -ConflictDevices $ConflictDevices -ErrorDevices $ErrorDevices -GracePeriodDevices $GracePeriodDevices -ComplianceThreshold $ComplianceThresholdPercent

        $EmailSent = Send-EmailNotification -Recipients $EmailRecipientList -Subject $Subject -Body $EmailBody

        if ($EmailSent) {
            Write-Output "✓ Email notification sent to $($EmailRecipientList.Count) recipients"
        }
        else {
            Write-Warning "Email notification could not be delivered to all recipients"
            $NotificationFailed = $true
        }
    }
    else {
        Write-Output "✓ No compliance drift detected. All devices meet compliance requirements."
    }

    # ========================================================================
    # DISPLAY SUMMARY
    # ========================================================================

    Write-Output "`n🛡️ DEVICE COMPLIANCE DRIFT MONITORING SUMMARY"
    Write-Output "==============================================="
    Write-Output "Total Managed Devices: $TotalDevices"
    Write-Output "Compliance Threshold: $ComplianceThresholdPercent%"
    Write-Output "Current Compliance: $CompliancePercentage%"
    Write-Output ""

    Write-Output "Compliance Status Breakdown:"
    Write-Output "  • Compliant: $($CompliantDevices.Count) ($CompliancePercentage%)"
    Write-Output "  • Non-Compliant: $($NonCompliantDevices.Count)"
    Write-Output "  • Conflicts: $($ConflictDevices.Count)"
    Write-Output "  • Errors: $($ErrorDevices.Count)"
    Write-Output "  • Grace Period: $($GracePeriodDevices.Count)"
    Write-Output ""

    if ($NonCompliantDevices.Count -gt 0) {
        Write-Output "Platform Breakdown (Non-Compliant Devices):"
        $PlatformGroups = $NonCompliantDevices | Group-Object Platform | Sort-Object Name
        foreach ($Group in $PlatformGroups) {
            Write-Output "  • $($Group.Name): $($Group.Count) devices"
        }
        Write-Output ""
    }

    $StatusIcon = if ($CompliancePercentage -ge $ComplianceThresholdPercent) { "✅" } else { "⚠️" }
    Write-Output "$StatusIcon Compliance Status: $(if ($CompliancePercentage -ge $ComplianceThresholdPercent) { 'MEETING THRESHOLD' } else { 'BELOW THRESHOLD' })"

    Write-Output "`n✓ Device compliance drift monitoring completed successfully"
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Output "Disconnected from Microsoft Graph"
    }
    catch {
        # Silently ignore disconnect errors as they're not critical
        Write-Verbose "Disconnect error (ignored): $($_.Exception.Message)"
    }
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Output "
========================================
Script Execution Summary
========================================
Script: Device Compliance Drift Alert
Total Devices Analyzed: $($AllDevices.Count)
Compliance Percentage: $CompliancePercentage%
Compliance Threshold: $ComplianceThresholdPercent%
Non-Compliant Devices: $($NonCompliantDevices.Count)
Conflict Devices: $($ConflictDevices.Count)
Error Devices: $($ErrorDevices.Count)
Grace Period Devices: $($GracePeriodDevices.Count)
Email Recipients: $($EmailRecipientList.Count)
Status: Completed
========================================
"

# Fail the run if notification delivery failed
if ($NotificationFailed) {
    exit 1
}
