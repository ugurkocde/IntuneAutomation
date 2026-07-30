<#
.TITLE
    Windows Update Failure Alert Notification

.SYNOPSIS
    Automated runbook that monitors Windows Update ring deployment errors and emails administrators the failing devices.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook. It scans
    all Windows Update rings (Windows Update for Business configurations), collects
    per-device deployment status, and sends an email report when devices are in an
    error or conflict state. Feature update profiles past or near their end-of-support
    date are included as warnings. This surfaces silently failing update deployments
    before they turn into unpatched device populations.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.2

.CHANGELOG
    1.2 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.1 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Weekly

.CATEGORY
    Notification

.EXAMPLE
    .\windows-update-failure-alert.ps1 -EmailRecipients "<recipient-address>" -SenderUPN "<sender-upn>"
    Scans update rings and emails the failure report to <recipient-address>

.EXAMPLE
    .\windows-update-failure-alert.ps1 -EmailRecipients "<recipient-address>,<operations-recipient-address>" -SenderUPN "<sender-upn>" -AlwaysSend "true"
    Sends the report to multiple recipients even when no failures were found

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - For Azure Automation, configure Managed Identity with the required permissions
    - The Automation account's managed identity requires Mail.Send permission for the SenderUPN mailbox
    - By default the email is only sent when at least one device error or profile warning exists; use -AlwaysSend for a weekly status mail
    - Uses beta Graph endpoints because update ring device statuses are exposed there
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated list of email addresses to send notifications")]
    [ValidateNotNullOrEmpty()]
    [string]$EmailRecipients,

    [Parameter(Mandatory = $true, HelpMessage = "Mailbox UPN used as the notification sender (managed identity needs Mail.Send permission for it)")]
    [ValidateNotNullOrEmpty()]
    [string]$SenderUPN,

    [Parameter(Mandatory = $false, HelpMessage = "Send the report even when no failures were found")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$AlwaysSend,

    [Parameter(Mandatory = $false, HelpMessage = "Days before feature update end-of-support to include a warning")]
    [ValidateRange(1, 730)]
    [int]$EndOfSupportWarningDays = 180,

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

# Azure Automation supplies portal parameter values as strings. Normalize the
# public boolean parameters once so local and runbook execution use real booleans.
foreach ($runbookBooleanParameter in @('AlwaysSend')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)

    if ([string]::IsNullOrWhiteSpace($runbookBooleanRaw)) {
        Set-Variable -Name $runbookBooleanParameter -Value $false
        continue
    }

    switch ($runbookBooleanRaw.Trim().ToLowerInvariant()) {
        { $_ -in @("true", "1", '$true') } {
            Set-Variable -Name $runbookBooleanParameter -Value $true
        }
        { $_ -in @("false", "0", '$false') } {
            Set-Variable -Name $runbookBooleanParameter -Value $false
        }
        default {
            throw "Parameter '$runbookBooleanParameter' accepts only true, false, 1, 0, $true, or $false."
        }
    }
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
        Write-Output "Connecting to Microsoft Graph..."
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All",
            "Mail.Send"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Output "✓ Successfully connected to Microsoft Graph"
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
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            throw "Error fetching data from $NextLink : $($_.Exception.Message)"
        }
    } while ($NextLink)

    # Comma keeps PowerShell from unrolling a single-item array on return
    return , $AllResults
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
        [array]$RingErrors,
        [array]$ProfileWarnings,
        [int]$RingCount
    )

    $errorRows = ""
    foreach ($row in $RingErrors) {
        $errorRows += @"
            <tr>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.RingName))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.DeviceName))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.UserPrincipalName))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.Status))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode([string]$row.LastReported))</td>
            </tr>
"@
    }

    $warningRows = ""
    foreach ($row in $ProfileWarnings) {
        $warningRows += @"
            <tr>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.ProfileName))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.Warning))</td>
            </tr>
"@
    }

    $errorSection = if ($RingErrors.Count -gt 0) {
        @"
        <h3>Devices with update deployment errors ($($RingErrors.Count))</h3>
        <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
            <tr style="background-color: #f2f2f2;">
                <th>Update Ring</th><th>Device</th><th>User</th><th>Status</th><th>Last Reported</th>
            </tr>
            $errorRows
        </table>
"@
    }
    else {
        "<p>No devices are in an error state for any update ring.</p>"
    }

    $warningSection = if ($ProfileWarnings.Count -gt 0) {
        @"
        <h3>Feature update profile warnings ($($ProfileWarnings.Count))</h3>
        <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
            <tr style="background-color: #f2f2f2;">
                <th>Profile</th><th>Warning</th>
            </tr>
            $warningRows
        </table>
"@
    }
    else {
        ""
    }

    return @"
<html>
<body style="font-family: Segoe UI, Arial, sans-serif;">
    <h2>Windows Update Failure Report</h2>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Update rings scanned: $RingCount</p>
    $errorSection
    $warningSection
    <p style="color: #666; font-size: 12px;">Generated automatically by the IntuneAutomation windows-update-failure-alert runbook.</p>
</body>
</html>
"@
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Scanning Windows Update rings..."

    $allConfigurations = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    $updateRings = @($allConfigurations | Where-Object { $_.'@odata.type' -like "*windowsUpdateForBusinessConfiguration" })
    Write-Output "✓ Found $($updateRings.Count) update rings"

    [System.Collections.Generic.List[Object]]$ringErrors = @()

    foreach ($ring in $updateRings) {
        $deviceStatuses = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($ring.id)/deviceStatuses"

        foreach ($status in @($deviceStatuses)) {
            if ($status.status -in @("error", "conflict")) {
                $lastReported = if ($status.lastReportedDateTime) { [DateTime]::Parse($status.lastReportedDateTime.ToString()).ToString("yyyy-MM-dd HH:mm") } else { "" }
                $ringErrors.Add([PSCustomObject]@{
                        RingName          = $ring.displayName
                        DeviceName        = $status.deviceDisplayName
                        UserPrincipalName = $status.userPrincipalName
                        Status            = $status.status
                        LastReported      = $lastReported
                    })
            }
        }
    }
    Write-Output "✓ Found $($ringErrors.Count) device error(s) across all rings"

    # Feature update profiles near or past end of support
    [System.Collections.Generic.List[Object]]$profileWarnings = @()
    $featureProfiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles"

    foreach ($featureProfile in @($featureProfiles)) {
        if (-not $featureProfile.endOfSupportDate) { continue }
        $endOfSupport = [DateTime]::Parse($featureProfile.endOfSupportDate.ToString())
        $daysLeft = [math]::Round(($endOfSupport - (Get-Date)).TotalDays, 0)

        if ($daysLeft -lt 0) {
            $profileWarnings.Add([PSCustomObject]@{
                    ProfileName = $featureProfile.displayName
                    Warning     = "Target version '$($featureProfile.featureUpdateVersion)' is PAST end of support ($($endOfSupport.ToString('yyyy-MM-dd')))"
                })
        }
        elseif ($daysLeft -le $EndOfSupportWarningDays) {
            $profileWarnings.Add([PSCustomObject]@{
                    ProfileName = $featureProfile.displayName
                    Warning     = "Target version '$($featureProfile.featureUpdateVersion)' reaches end of support in $daysLeft days ($($endOfSupport.ToString('yyyy-MM-dd')))"
                })
        }
    }

    # ----- Send notification -----
    $totalFindings = $ringErrors.Count + $profileWarnings.Count

    if ($totalFindings -eq 0 -and -not $AlwaysSend) {
        Write-Output "No update failures or profile warnings found - no email sent (use -AlwaysSend for status mails)"
    }
    else {
        $recipients = @($EmailRecipients -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $subject = if ($totalFindings -gt 0) {
            "Intune Alert: $($ringErrors.Count) Windows Update deployment errors"
        }
        else {
            "Intune Status: Windows Update deployments healthy"
        }

        $body = New-EmailBody -RingErrors @($ringErrors) -ProfileWarnings @($profileWarnings) -RingCount $updateRings.Count

        $sendResult = Send-EmailNotification -Recipients $recipients -Subject $subject -Body $body
        if (-not $sendResult) {
            throw "Email notification failed"
        }
    }

    # Summary
    Write-Output "`n========================================"
    Write-Output "Windows Update Failure Alert Summary"
    Write-Output "========================================"
    Write-Output "Update rings scanned:  $($updateRings.Count)"
    Write-Output "Device errors found:   $($ringErrors.Count)"
    Write-Output "Profile warnings:      $($profileWarnings.Count)"
    Write-Output "========================================"
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
