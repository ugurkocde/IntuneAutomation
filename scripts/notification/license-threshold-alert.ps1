<#
.TITLE
    License Threshold Alert Notification

.SYNOPSIS
    Automated runbook that emails administrators when Intune-capable license SKUs approach exhaustion.

.DESCRIPTION
    This script is designed to run as a scheduled Azure Automation runbook. It reads
    the tenant's subscribed SKUs, identifies the ones that include an Intune service
    plan, and compares consumed against purchased units. When utilization crosses the
    configured threshold (default 90 percent) or a SKU is suspended or in warning
    state, administrators get an email before new users fail to enroll for lack of a
    license. Non-Intune SKUs can be included with a switch for a full license
    overview.

.TAGS
    Notification

.MINROLE
    Intune Administrator

.PERMISSIONS
    Organization.Read.All,Mail.Send

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
    .\license-threshold-alert.ps1 -EmailRecipients "admin@company.com" -SenderUPN "intune-alerts@company.com"
    Alerts when any Intune-capable SKU passes 90 percent utilization

.EXAMPLE
    .\license-threshold-alert.ps1 -ThresholdPercent 80 -IncludeAllSkus -EmailRecipients "admin@company.com" -SenderUPN "intune-alerts@company.com"
    Alerts at 80 percent utilization across every SKU in the tenant

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - For Azure Automation, configure Managed Identity with the required permissions
    - The Automation account's managed identity requires Mail.Send permission for the SenderUPN mailbox
    - Intune-capable SKUs are detected by an INTUNE_A service plan; trial and locked-out units are not counted as available
    - subscribedSkus is a v1.0 endpoint and readable with Organization.Read.All
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

    [Parameter(Mandatory = $false, HelpMessage = "Utilization percentage that triggers the alert")]
    [ValidateRange(1, 100)]
    [int]$ThresholdPercent = 90,

    [Parameter(Mandatory = $false, HelpMessage = "Include SKUs without an Intune service plan")]
    [switch]$IncludeAllSkus,

    [Parameter(Mandatory = $false, HelpMessage = "Send the report even when no SKU crosses the threshold")]
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
            "Organization.Read.All",
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
        [array]$SkuReport,
        [int]$Threshold
    )

    $rows = ""
    foreach ($row in ($SkuReport | Sort-Object UtilizationPct -Descending)) {
        $highlight = if ($row.Flagged) { " style=`"background-color: #fdecea;`"" } else { "" }
        $rows += @"
            <tr$highlight>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.SkuPartNumber))</td>
                <td>$($row.Consumed)</td>
                <td>$($row.Enabled)</td>
                <td>$($row.UtilizationPct)%</td>
                <td>$($row.Available)</td>
                <td>$([System.Net.WebUtility]::HtmlEncode($row.Health))</td>
            </tr>
"@
    }

    return @"
<html>
<body style="font-family: Segoe UI, Arial, sans-serif;">
    <h2>License Threshold Report</h2>
    <p>Alert threshold: $Threshold% | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse;">
        <tr style="background-color: #f2f2f2;">
            <th>SKU</th><th>Consumed</th><th>Purchased</th><th>Utilization</th><th>Available</th><th>Health</th>
        </tr>
        $rows
    </table>
    <p style="color: #666; font-size: 12px;">Generated automatically by the IntuneAutomation license-threshold-alert runbook.</p>
</body>
</html>
"@
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving subscribed SKUs..." -InformationAction Continue
    $skus = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/v1.0/subscribedSkus?`$select=skuPartNumber,skuId,consumedUnits,prepaidUnits,servicePlans,capabilityStatus"

    [System.Collections.Generic.List[Object]]$skuReport = @()

    foreach ($sku in @($skus)) {
        # Intune-capable SKUs carry the INTUNE_A user service plan
        $hasIntunePlan = @($sku.servicePlans | Where-Object { $_.servicePlanName -like "INTUNE_A*" }).Count -gt 0
        if (-not $hasIntunePlan -and -not $IncludeAllSkus) { continue }

        $enabled = [int]$sku.prepaidUnits.enabled
        $consumed = [int]$sku.consumedUnits
        $suspended = [int]$sku.prepaidUnits.suspended
        $warning = [int]$sku.prepaidUnits.warning

        # SKUs with zero purchasable units (e.g. fully locked-out trials) cannot be utilized
        if ($enabled -eq 0 -and $consumed -eq 0) { continue }

        $utilization = if ($enabled -gt 0) { [math]::Round(($consumed / $enabled) * 100, 1) } else { 100 }
        $available = $enabled - $consumed

        $health = "OK"
        if ($suspended -gt 0) { $health = "Suspended units: $suspended" }
        elseif ($warning -gt 0) { $health = "Units in warning (grace period): $warning" }
        elseif ($enabled -eq 0) { $health = "No enabled units" }

        $flagged = ($utilization -ge $ThresholdPercent) -or ($health -ne "OK")

        $skuReport.Add([PSCustomObject]@{
                SkuPartNumber  = $sku.skuPartNumber
                IntuneCapable  = $hasIntunePlan
                Consumed       = $consumed
                Enabled        = $enabled
                Available      = $available
                UtilizationPct = $utilization
                Health         = $health
                Flagged        = $flagged
            })
    }

    $flaggedSkus = @($skuReport | Where-Object { $_.Flagged })
    Write-Information "✓ Analyzed $($skuReport.Count) SKU(s), $($flaggedSkus.Count) above threshold or unhealthy" -InformationAction Continue

    # ----- Send notification -----
    if ($flaggedSkus.Count -eq 0 -and -not $AlwaysSend) {
        Write-Information "No SKU crossed the $ThresholdPercent% threshold - no email sent (use -AlwaysSend for status mails)" -InformationAction Continue
    }
    else {
        $recipients = @($EmailRecipients -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $subject = if ($flaggedSkus.Count -gt 0) {
            "Intune Alert: $($flaggedSkus.Count) license SKU(s) above $ThresholdPercent% utilization"
        }
        else {
            "Intune Status: license utilization healthy"
        }

        $body = New-EmailBody -SkuReport @($skuReport) -Threshold $ThresholdPercent

        $sendResult = Send-EmailNotification -Recipients $recipients -Subject $subject -Body $body
        if (-not $sendResult) {
            throw "Email notification failed"
        }
    }

    # Summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "License Threshold Alert Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    foreach ($row in ($skuReport | Sort-Object UtilizationPct -Descending)) {
        $flagLabel = if ($row.Flagged) { " [FLAGGED]" } else { "" }
        Write-Information "$($row.SkuPartNumber): $($row.Consumed)/$($row.Enabled) ($($row.UtilizationPct)%)$flagLabel" -InformationAction Continue
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
