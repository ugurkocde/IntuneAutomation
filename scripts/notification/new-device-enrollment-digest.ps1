<#
.TITLE
    New Device Enrollment Digest Notification

.SYNOPSIS
    Automated runbook that emails a digest of newly enrolled Intune devices with platform and ownership breakdown.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook. It
    collects all devices enrolled into Intune within the reporting window (default
    7 days), breaks them down by platform, ownership, and enrollment type, and sends
    a digest email to administrators. The digest gives visibility into enrollment
    activity: unexpected spikes, personal devices appearing in a corporate-only
    environment, or platforms that should not be enrolling at all.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,Mail.Send

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXECUTION
    RunbookOnly

.OUTPUT
    Email

.SCHEDULE
    Weekly

.CATEGORY
    Notification

.EXAMPLE
    .\new-device-enrollment-digest.ps1 -EmailRecipients "admin@company.com" -SenderUPN "intune-alerts@company.com"
    Emails the last 7 days of new enrollments to admin@company.com

.EXAMPLE
    .\new-device-enrollment-digest.ps1 -DaysBack 1 -EmailRecipients "admin@company.com" -SenderUPN "intune-alerts@company.com" -AlwaysSend
    Daily digest that is sent even on days without new enrollments

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - For Azure Automation, configure Managed Identity with the required permissions
    - The Automation account's managed identity requires Mail.Send permission for the SenderUPN mailbox
    - By default no email is sent when there are no new enrollments; use -AlwaysSend to always get the digest
    - Uses beta Graph endpoints for consistency with the rest of the library
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

    [Parameter(Mandatory = $false, HelpMessage = "How many days back to include enrollments")]
    [ValidateRange(1, 90)]
    [int]$DaysBack = 7,

    [Parameter(Mandatory = $false, HelpMessage = "Send the digest even when no devices enrolled in the window")]
    [switch]$AlwaysSend,

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
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "Mail.Send"
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
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
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
                $Uri = "https://graph.microsoft.com/v1.0/users/$SenderUPN/sendMail"
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
        [array]$NewDevices,
        [int]$WindowDays
    )

    $platformSummary = ""
    foreach ($group in ($NewDevices | Group-Object Platform | Sort-Object Count -Descending)) {
        $platformSummary += "<li>$([System.Net.WebUtility]::HtmlEncode($group.Name)): $($group.Count)</li>"
    }

    $ownershipSummary = ""
    foreach ($group in ($NewDevices | Group-Object Ownership | Sort-Object Count -Descending)) {
        $ownershipSummary += "<li>$([System.Net.WebUtility]::HtmlEncode($group.Name)): $($group.Count)</li>"
    }

    $deviceRows = ""
    foreach ($device in ($NewDevices | Sort-Object Enrolled -Descending)) {
        $deviceRows += @"
            <tr>
                <td>$([System.Net.WebUtility]::HtmlEncode($device.DeviceName))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($device.User))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($device.Platform))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($device.Ownership))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($device.EnrollmentType))</td>
                <td>$([System.Net.WebUtility]::HtmlEncode([string]$device.Enrolled))</td>
            </tr>
"@
    }

    $deviceSection = if ($NewDevices.Count -gt 0) {
        @"
        <h3>New devices ($($NewDevices.Count))</h3>
        <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
            <tr style="background-color: #f2f2f2;">
                <th>Device</th><th>User</th><th>Platform</th><th>Ownership</th><th>Enrollment Type</th><th>Enrolled</th>
            </tr>
            $deviceRows
        </table>
"@
    }
    else {
        "<p>No devices enrolled in the reporting window.</p>"
    }

    return @"
<html>
<body style="font-family: Segoe UI, Arial, sans-serif;">
    <h2>New Device Enrollment Digest</h2>
    <p>Window: last $WindowDays days | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
    <h3>By platform</h3>
    <ul>$platformSummary</ul>
    <h3>By ownership</h3>
    <ul>$ownershipSummary</ul>
    $deviceSection
    <p style="color: #666; font-size: 12px;">Generated automatically by the IntuneAutomation new-device-enrollment-digest runbook.</p>
</body>
</html>
"@
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    $cutoff = (Get-Date).AddDays(-$DaysBack)
    Write-Information "Collecting devices enrolled since $($cutoff.ToString('yyyy-MM-dd'))..." -InformationAction Continue

    $devices = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,ownerType,deviceEnrollmentType,enrolledDateTime,userPrincipalName"

    [System.Collections.Generic.List[Object]]$newDevices = @()
    foreach ($device in @($devices)) {
        # New enrollments can have a null enrolledDateTime for a short window
        $enrolled = if ($device.enrolledDateTime) { [DateTime]::Parse($device.enrolledDateTime.ToString()) } else { $null }
        if (-not $enrolled -or $enrolled -lt $cutoff) { continue }

        $newDevices.Add([PSCustomObject]@{
                DeviceName     = $device.deviceName
                User           = $device.userPrincipalName
                Platform       = $device.operatingSystem
                OsVersion      = $device.osVersion
                Ownership      = $device.ownerType
                EnrollmentType = $device.deviceEnrollmentType
                Enrolled       = $enrolled.ToString("yyyy-MM-dd HH:mm")
            })
    }

    Write-Information "✓ Found $($newDevices.Count) new enrollment(s) in the last $DaysBack days" -InformationAction Continue

    # ----- Send notification -----
    if ($newDevices.Count -eq 0 -and -not $AlwaysSend) {
        Write-Information "No new enrollments - no email sent (use -AlwaysSend for empty digests)" -InformationAction Continue
    }
    else {
        $recipients = @($EmailRecipients -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $subject = "Intune Digest: $($newDevices.Count) new device enrollment(s) in the last $DaysBack days"
        $body = New-EmailBody -NewDevices @($newDevices) -WindowDays $DaysBack

        $sendResult = Send-EmailNotification -Recipients $recipients -Subject $subject -Body $body
        if (-not $sendResult) {
            throw "Email notification failed"
        }
    }

    # Summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "Enrollment Digest Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Window:          last $DaysBack days" -InformationAction Continue
    Write-Information "New enrollments: $($newDevices.Count)" -InformationAction Continue
    foreach ($group in ($newDevices | Group-Object Platform | Sort-Object Count -Descending)) {
        Write-Information "  $($group.Name): $($group.Count)" -InformationAction Continue
    }
    Write-Information "========================================" -InformationAction Continue
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
