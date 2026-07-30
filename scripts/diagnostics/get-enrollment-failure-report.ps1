<#
.TITLE
    Get Enrollment Failure Report

.SYNOPSIS
    Reports Intune enrollment failures and Autopilot deployment events with plain-language failure explanations.

.DESCRIPTION
    This script retrieves enrollment troubleshooting events and Windows Autopilot
    deployment events from Microsoft Graph, groups the failures by category, and
    translates Intune's failure categories into plain-language explanations with
    typical fixes. Use it to spot enrollment restriction blocks, authentication
    problems, or licensing issues across the tenant instead of clicking through
    the troubleshooting portal user by user.

.TAGS
    Diagnostics,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementServiceConfig.Read.All,User.Read.All

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

.EXAMPLE
    .\get-enrollment-failure-report.ps1
    Reports enrollment failures from the last 30 days

.EXAMPLE
    .\get-enrollment-failure-report.ps1 -DaysBack 7 -ExportToCsv "true"
    Reports the last week of enrollment failures and exports them to CSV

.EXAMPLE
    .\get-enrollment-failure-report.ps1 -IncludeAutopilotEvents "true"
    Also lists Windows Autopilot deployment events with their deployment state

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Enrollment troubleshooting events are retained by Intune for a limited period; older failures may no longer be available
    - User principal names are resolved from the userId on the event where possible
    - Uses beta Graph endpoints for troubleshooting and Autopilot events
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "How many days back to report")]
    [ValidateRange(1, 180)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory = $false, HelpMessage = "Also include Windows Autopilot deployment events")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeAutopilotEvents,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

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
foreach ($runbookBooleanParameter in @('IncludeAutopilotEvents', 'ExportToCsv')) {
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
        Write-Output "Connecting to Microsoft Graph..."
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementServiceConfig.Read.All",
            "User.Read.All"
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
            throw "Error fetching data: $($_.Exception.Message)"
        }
    } while ($nextLink)

    return $allResults
}

$script:UserNameCache = @{}

function Resolve-UserName {
    param([string]$UserId)

    if ([string]::IsNullOrWhiteSpace($UserId)) { return "" }
    if ($script:UserNameCache.ContainsKey($UserId)) { return $script:UserNameCache[$UserId] }

    $name = $UserId
    try {
        $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/users/${UserId}?`$select=userPrincipalName" -Method GET
        if ($user.userPrincipalName) { $name = $user.userPrincipalName }
    }
    catch {
        Write-Verbose "Could not resolve user ${UserId}: $($_.Exception.Message)"
    }

    $script:UserNameCache[$UserId] = $name
    return $name
}

function Get-FailureExplanation {
    param([string]$FailureCategory)

    # Plain-language translation of the deviceEnrollmentFailureReason categories
    switch ($FailureCategory) {
        "authentication" { "Sign-in to the enrollment service failed. Check the user's credentials, MFA state, and Conditional Access prompts during enrollment." }
        "authorization" { "The account is not allowed to enroll. Check Intune license assignment and MDM user scope in Entra ID mobility settings." }
        "accountValidation" { "The account failed validation. Check whether the user exists, is enabled, and belongs to the expected tenant." }
        "userValidation" { "The user could not be validated for enrollment. Check license assignment and the MDM user scope." }
        "deviceNotSupported" { "The device platform or OS version is not supported. Check platform restrictions and minimum OS requirements." }
        "inMaintenance" { "The enrollment service was in maintenance. Ask the user to retry later." }
        "badRequest" { "The enrollment request was malformed. Usually a client-side glitch; retrying or re-provisioning the device typically resolves it." }
        "featureNotSupported" { "An enrollment feature used by the device is not supported for this tenant or platform." }
        "enrollmentRestrictionsEnforced" { "An enrollment restriction blocked the device, such as a platform block, personal device block, or device limit." }
        "clientDisconnected" { "The device disconnected mid-enrollment. Check network connectivity and retry." }
        "userAbandonment" { "The user abandoned enrollment before it completed. Ask them to run through the full flow again." }
        default { "Unknown failure category. Inspect the raw failure reason and correlation ID." }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    $cutoffDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")

    Write-Output "Retrieving enrollment troubleshooting events (last $DaysBack days)..."
    $events = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/troubleshootingEvents?`$filter=eventDateTime ge $cutoffDate"

    # The collection mixes event types; enrollment failures carry failureCategory
    $enrollmentEvents = @($events | Where-Object { $_.'@odata.type' -like "*enrollmentTroubleshootingEvent" -or $_.failureCategory })
    Write-Output "✓ Found $($enrollmentEvents.Count) enrollment events (of $(@($events).Count) troubleshooting events)"

    [System.Collections.Generic.List[Object]]$report = @()

    foreach ($failureEvent in $enrollmentEvents) {
        $eventTime = if ($failureEvent.eventDateTime) { [DateTime]::Parse($failureEvent.eventDateTime.ToString()) } else { $null }

        $report.Add([PSCustomObject]@{
                EventTime       = if ($eventTime) { $eventTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
                User            = Resolve-UserName -UserId $failureEvent.userId
                OperatingSystem = $failureEvent.operatingSystem
                OsVersion       = $failureEvent.osVersion
                EnrollmentType  = $failureEvent.enrollmentType
                FailureCategory = $failureEvent.failureCategory
                FailureReason   = $failureEvent.failureReason
                Explanation     = Get-FailureExplanation -FailureCategory $failureEvent.failureCategory
                CorrelationId   = $failureEvent.correlationId
            })
    }

    # ----- Autopilot events (optional) -----
    [System.Collections.Generic.List[Object]]$autopilotReport = @()
    if ($IncludeAutopilotEvents) {
        Write-Output "Retrieving Autopilot deployment events..."
        $autopilotEvents = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/autopilotEvents"

        foreach ($autopilotEvent in $autopilotEvents) {
            $eventTime = if ($autopilotEvent.deploymentStartDateTime) { [DateTime]::Parse($autopilotEvent.deploymentStartDateTime.ToString()) } else { $null }
            if ($eventTime -and $eventTime -lt (Get-Date).AddDays(-$DaysBack)) { continue }

            $autopilotReport.Add([PSCustomObject]@{
                    DeploymentStart = if ($eventTime) { $eventTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
                    SerialNumber    = $autopilotEvent.deviceSerialNumber
                    DeviceId        = $autopilotEvent.deviceId
                    DeploymentState = $autopilotEvent.deploymentState
                    OsVersion       = $autopilotEvent.osVersion
                    UserPrincipal   = $autopilotEvent.userPrincipalName
                    EnrollmentState = $autopilotEvent.enrollmentState
                })
        }
        Write-Output "✓ Found $($autopilotReport.Count) Autopilot events in the window"
    }

    # ----- Display results -----
    Write-Output "`nENROLLMENT FAILURE REPORT"
    Write-Output ("=" * 50)
    Write-Output "Window: last $DaysBack days | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output ("=" * 50)

    if ($report.Count -eq 0) {
        Write-Output "`nNo enrollment failures recorded in the window."
    }
    else {
        foreach ($categoryGroup in ($report | Group-Object -Property FailureCategory | Sort-Object Count -Descending)) {
            $categoryLabel = if ($categoryGroup.Name) { $categoryGroup.Name } else { "uncategorized" }
            Write-Output "`n[$categoryLabel] $($categoryGroup.Count) failure(s)"
            Write-Output "  Explanation: $(Get-FailureExplanation -FailureCategory $categoryGroup.Name)"

            foreach ($row in ($categoryGroup.Group | Sort-Object EventTime -Descending)) {
                $detail = "  $($row.EventTime) | $($row.User) | $($row.OperatingSystem) $($row.OsVersion) | $($row.EnrollmentType)"
                Write-Output $detail
                if ($row.FailureReason) {
                    Write-Output "    Reason: $($row.FailureReason)"
                }
            }
        }
    }

    if ($IncludeAutopilotEvents -and $autopilotReport.Count -gt 0) {
        Write-Output "`nAUTOPILOT DEPLOYMENT EVENTS"
        Write-Output ("=" * 50)
        foreach ($row in ($autopilotReport | Sort-Object DeploymentStart -Descending)) {
            Write-Output "  $($row.DeploymentStart) | $($row.SerialNumber) | state: $($row.DeploymentState) | $($row.UserPrincipal)"
        }
    }

    # Summary
    Write-Output "`n"
    Write-Output ("=" * 50)
    Write-Output "Summary: $($report.Count) enrollment failures$(if ($IncludeAutopilotEvents) { ", $($autopilotReport.Count) Autopilot events" })"
    Write-Output ("=" * 50)

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Enrollment_Failures_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Output "✓ CSV report saved: $csvPath"

        if ($IncludeAutopilotEvents -and $autopilotReport.Count -gt 0) {
            $autopilotCsvPath = Join-Path $OutputPath "Autopilot_Events_$timestamp.csv"
            $autopilotReport | Export-Csv -Path $autopilotCsvPath -NoTypeInformation -Encoding UTF8
            Write-Output "✓ CSV report saved: $autopilotCsvPath"
        }
    }
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
