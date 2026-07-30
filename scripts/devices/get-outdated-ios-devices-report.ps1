<#
.TITLE
    Get Outdated iOS Devices Report

.SYNOPSIS
    Reports Intune-managed iOS devices running a major version older than the latest two releases.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves Intune-managed iOS devices, including
    their assigned user and last check-in date. Devices with an iOS major version
    lower than the older of the two supported major releases are exported to a
    timestamped CSV file. The supported major versions can be updated by parameter
    when Apple releases a new major version.

.TAGS
    Monitoring,Devices

.PLATFORM
    Cross-platform

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All

.AUTHOR
    AI Generated (IntuneAutomation.com)

.VERSION
    1.1

.CHANGELOG
    1.1 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\get-outdated-ios-devices-report.ps1
    Reports devices below iOS 18 and exports the results to the current directory.

.EXAMPLE
    .\get-outdated-ios-devices-report.ps1 -OutputPath "C:\Reports"
    Exports the timestamped CSV report to C:\Reports.

.EXAMPLE
    .\get-outdated-ios-devices-report.ps1 -LatestMajorVersion 27 -PreviousMajorVersion 26
    Uses iOS 27 and iOS 26 as the latest two major releases.

.NOTES
    - Requires Microsoft.Graph.Authentication and, for local runs, MgGraphCommunity.
    - Defaults to iOS 26 and iOS 18, the two released major branches as of 2026-07-29.
    - A device is outdated when its parsed major version is lower than the older supported major.
    - Devices with a missing or unrecognized OS version are excluded and reported as warnings.
    - Azure Automation managed identity needs DeviceManagementManagedDevices.Read.All.
    - Local interactive sign-in uses MgGraphCommunity to avoid mandatory WAM authentication.
#>

#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "The latest released iOS major version")]
    [ValidateRange(1, 99)]
    [int]$LatestMajorVersion = 26,

    [Parameter(Mandatory = $false, HelpMessage = "The previous released iOS major version")]
    [ValidateRange(1, 99)]
    [int]$PreviousMajorVersion = 18,

    [Parameter(Mandatory = $false, HelpMessage = "Directory where the timestamped CSV report will be saved")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
Remove-Variable -Name ForceModuleInstall
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ModuleNames,

        [Parameter(Mandatory = $true)]
        [bool]$IsAutomationEnvironment,

        [Parameter(Mandatory = $false)]
        [bool]$ForceInstall = $false
    )

    foreach ($moduleName in $ModuleNames) {
        $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1

        if (-not $module) {
            if ($IsAutomationEnvironment) {
                throw "Module '$moduleName' is not available in Azure Automation."
            }

            Write-Information "Module '$moduleName' was not found." -InformationAction Continue

            if (-not $ForceInstall) {
                $response = Read-Host "Install module '$moduleName'? (Y/N)"
                if ($response -notmatch '^[Yy]') {
                    throw "Module '$moduleName' is required, but installation was declined."
                }
            }

            try {
                $installScope = "CurrentUser"

                if ($IsWindows) {
                    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                        [Security.Principal.WindowsBuiltInRole]::Administrator
                    )
                    if ($isAdministrator) {
                        $installScope = "AllUsers"
                    }
                }

                Install-Module -Name $moduleName -Scope $installScope -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                Write-Information "Installed module '$moduleName'." -InformationAction Continue
            }
            catch {
                throw "Failed to install module '$moduleName': $($_.Exception.Message)"
            }
        }

        try {
            Import-Module -Name $moduleName -Force -ErrorAction Stop
        }
        catch {
            throw "Failed to import module '$moduleName': $($_.Exception.Message)"
        }
    }
}

$IsAzureAutomation = $null -ne $PSPrivateMetadata.JobId.Guid
$RequiredModules = @("Microsoft.Graph.Authentication")

if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

try {
    Initialize-RequiredModule `
        -ModuleNames $RequiredModules `
        -IsAutomationEnvironment $IsAzureAutomation `
        -ForceInstall $ForceModuleInstall
}
catch {
    Write-Error "Module initialization failed: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

try {
    if ($IsAzureAutomation) {
        Write-Output "Connecting to Microsoft Graph using managed identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Output "Connecting to Microsoft Graph using interactive authentication..."
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }

    Write-Output "Connected to Microsoft Graph."
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-MgGraphAllPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 60000)]
        [int]$DelayMs = 100,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$MaxRetryCount = 3
    )

    [System.Collections.Generic.List[object]]$allResults = @()
    $nextLink = $Uri
    $requestCount = 0

    do {
        if ($requestCount -gt 0 -and $DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }

        $retryCount = 0

        while ($true) {
            try {
                $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET -ErrorAction Stop
                $requestCount++
                break
            }
            catch {
                $isThrottled = $_.Exception.Message -match '429|Too Many Requests|throttl'

                if (-not $isThrottled -or $retryCount -ge $MaxRetryCount) {
                    throw "Microsoft Graph request failed for '$nextLink': $($_.Exception.Message)"
                }

                $retryCount++
                Write-Information "Rate limit reached. Waiting 60 seconds before retry $retryCount of $MaxRetryCount." -InformationAction Continue
                Start-Sleep -Seconds 60
            }
        }

        if ($null -ne $response.value) {
            foreach ($item in @($response.value)) {
                $allResults.Add($item)
            }
        }
        else {
            $allResults.Add($response)
        }

        $nextLink = $response.'@odata.nextLink'
    } while ($nextLink)

    return $allResults
}

function ConvertTo-IosMajorVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$OsVersion
    )

    if ([string]::IsNullOrWhiteSpace($OsVersion)) {
        return $null
    }

    $versionMatch = [regex]::Match($OsVersion.Trim(), '^(\d+)')
    if (-not $versionMatch.Success) {
        return $null
    }

    return [int]$versionMatch.Groups[1].Value
}

function Resolve-ReportDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (Test-Path -LiteralPath $resolvedPath) {
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
            throw "OutputPath must be a directory: $resolvedPath"
        }
    }
    else {
        $null = New-Item -Path $resolvedPath -ItemType Directory -Force -ErrorAction Stop
    }

    return $resolvedPath
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

[System.Collections.Generic.List[object]]$report = @()
$csvPath = $null
$totalIosDevices = 0
$unrecognizedVersionCount = 0

try {
    $supportedMajors = @(@($LatestMajorVersion, $PreviousMajorVersion) | Sort-Object -Unique -Descending)
    if ($supportedMajors.Count -ne 2) {
        throw "LatestMajorVersion and PreviousMajorVersion must be distinct."
    }

    $oldestSupportedMajor = ($supportedMajors | Measure-Object -Minimum).Minimum
    Write-Output "Supported iOS major versions: $($supportedMajors -join ', ')"
    Write-Output "Devices below iOS $oldestSupportedMajor will be reported."

    $selectFields = @(
        "id",
        "azureADDeviceId",
        "deviceName",
        "operatingSystem",
        "osVersion",
        "userId",
        "userDisplayName",
        "userPrincipalName",
        "lastSyncDateTime",
        "serialNumber",
        "manufacturer",
        "model",
        "managedDeviceOwnerType",
        "complianceState"
    ) -join ","

    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?" +
        "`$filter=operatingSystem eq 'iOS'&" +
        "`$select=$selectFields&" +
        "`$top=999"

    Write-Output "Retrieving iOS devices from Intune..."
    $iosDevices = @(Get-MgGraphAllPage -Uri $uri)
    $totalIosDevices = $iosDevices.Count
    Write-Output "Retrieved $totalIosDevices iOS device(s)."

    foreach ($device in $iosDevices) {
        $majorVersion = ConvertTo-IosMajorVersion -OsVersion $device.osVersion

        if ($null -eq $majorVersion) {
            $unrecognizedVersionCount++
            Write-Warning "Skipping device '$($device.deviceName)' because OS version '$($device.osVersion)' could not be parsed."
            continue
        }

        if ($majorVersion -ge $oldestSupportedMajor) {
            continue
        }

        $lastCheckIn = if ($device.lastSyncDateTime) {
            try {
                [DateTimeOffset]::Parse($device.lastSyncDateTime)
            }
            catch {
                Write-Warning "Device '$($device.deviceName)' has an invalid last check-in date: $($device.lastSyncDateTime)"
                $null
            }
        }
        else {
            $null
        }

        $lastCheckInUtc = if ($null -ne $lastCheckIn) {
            $lastCheckIn.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        else {
            $null
        }

        $daysSinceLastCheckIn = if ($null -ne $lastCheckIn) {
            [math]::Max(
                0,
                [math]::Floor(([DateTimeOffset]::UtcNow - $lastCheckIn.ToUniversalTime()).TotalDays)
            )
        }
        else {
            $null
        }

        $report.Add([PSCustomObject]@{
                DeviceName                  = $device.deviceName
                OSVersion                   = $device.osVersion
                OSMajorVersion              = $majorVersion
                OldestSupportedMajorVersion = $oldestSupportedMajor
                AssignedUserDisplayName     = $device.userDisplayName
                AssignedUserPrincipalName   = $device.userPrincipalName
                LastCheckInDateUtc           = $lastCheckInUtc
                DaysSinceLastCheckIn         = $daysSinceLastCheckIn
                SerialNumber                = $device.serialNumber
                Manufacturer                = $device.manufacturer
                Model                       = $device.model
                Ownership                   = $device.managedDeviceOwnerType
                ComplianceState             = $device.complianceState
                AssignedUserId              = $device.userId
                ManagedDeviceId             = $device.id
                EntraDeviceId               = $device.azureADDeviceId
            })
    }

    $sortedReport = @($report | Sort-Object OSMajorVersion, OSVersion, DeviceName)
    $report = [System.Collections.Generic.List[object]]@($sortedReport)

    $reportDirectory = Resolve-ReportDirectory -Path $OutputPath
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $csvPath = Join-Path -Path $reportDirectory -ChildPath "Outdated_iOS_Devices_$timestamp.csv"

    if ($report.Count -gt 0) {
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    }
    else {
        $emptyReport = [PSCustomObject][ordered]@{
            DeviceName                  = $null
            OSVersion                   = $null
            OSMajorVersion              = $null
            OldestSupportedMajorVersion = $null
            AssignedUserDisplayName     = $null
            AssignedUserPrincipalName   = $null
            LastCheckInDateUtc           = $null
            DaysSinceLastCheckIn         = $null
            SerialNumber                = $null
            Manufacturer                = $null
            Model                       = $null
            Ownership                   = $null
            ComplianceState             = $null
            AssignedUserId              = $null
            ManagedDeviceId             = $null
            EntraDeviceId               = $null
        }
        $header = ($emptyReport | ConvertTo-Csv -NoTypeInformation)[0]
        Set-Content -LiteralPath $csvPath -Value $header -Encoding UTF8 -ErrorAction Stop
    }

    Write-Output "CSV report saved: $csvPath"
    Write-Output "Report summary:"
    Write-Output "  iOS devices evaluated: $totalIosDevices"
    Write-Output "  Outdated devices found: $($report.Count)"
    Write-Output "  Unrecognized OS versions skipped: $unrecognizedVersionCount"
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
}

$report
