<#
.TITLE
    Collect Device Diagnostics

.SYNOPSIS
    Triggers remote diagnostics collection on Windows devices and downloads the resulting log packages.

.DESCRIPTION
    This script starts the Intune "Collect diagnostics" remote action on one or more
    Windows devices (by device name or Entra ID group), waits for the collection to
    complete, and downloads the resulting diagnostic ZIP packages to a local folder.
    It can also list and download previously completed collection requests without
    triggering a new one. This replaces clicking through the portal for every device
    when troubleshooting at scale.

.TAGS
    Diagnostics,Devices

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All,Group.Read.All,GroupMember.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\collect-device-diagnostics.ps1 -DeviceNames "PC-001","PC-002"
    Triggers diagnostics collection on two devices and downloads the packages when ready

.EXAMPLE
    .\collect-device-diagnostics.ps1 -GroupName "Support - Troubleshooting" -OutputPath "C:\DeviceLogs"
    Collects diagnostics from all Windows devices in the group and saves packages to C:\DeviceLogs

.EXAMPLE
    .\collect-device-diagnostics.ps1 -DeviceNames "PC-001" -DownloadExisting
    Skips triggering a new collection and downloads the most recent completed package instead

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Collect diagnostics is only supported on Windows 10/11 devices; other platforms are skipped
    - The device must be online to receive the action; collection typically completes within minutes but the script stops waiting after -TimeoutMinutes
    - Listing and creating log collection requests requires DeviceManagementManagedDevices.ReadWrite.All (Graph rejects read-only scopes for this surface)
    - Uses beta Graph endpoints for the log collection surface
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(DefaultParameterSetName = "ByDevice")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByDevice", HelpMessage = "Device names to collect diagnostics from")]
    [ValidateNotNullOrEmpty()]
    [string[]]$DeviceNames,

    [Parameter(Mandatory = $true, ParameterSetName = "ByGroup", HelpMessage = "Entra ID group whose Windows devices get diagnostics collected")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $false, HelpMessage = "Folder where diagnostic packages are saved")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Download the latest existing completed package instead of triggering a new collection")]
    [switch]$DownloadExisting,

    [Parameter(Mandatory = $false, HelpMessage = "Minutes to wait for collections to complete")]
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 15,

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
            "DeviceManagementManagedDevices.ReadWrite.All",
            "Group.Read.All",
            "GroupMember.Read.All"
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

function Get-TargetDevice {
    # Resolves the requested devices to Intune Windows managed devices
    $devices = [System.Collections.Generic.List[Object]]::new()

    if ($PSCmdlet.ParameterSetName -eq "ByDevice") {
        foreach ($deviceName in $DeviceNames) {
            $escapedName = $deviceName -replace "'", "''"
            $found = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$escapedName'&`$select=id,deviceName,operatingSystem,lastSyncDateTime"

            if (@($found).Count -eq 0) {
                Write-Warning "Device '$deviceName' not found in Intune"
                continue
            }
            foreach ($device in $found) {
                $devices.Add($device)
            }
        }
    }
    else {
        $escapedGroup = $GroupName -replace "'", "''"
        $groups = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq '$escapedGroup'&`$select=id,displayName"
        if (@($groups).Count -ne 1) {
            throw "Expected exactly one group named '$GroupName', found $(@($groups).Count)"
        }

        $members = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/groups/$(@($groups)[0].id)/members?`$select=id,displayName,deviceId"
        foreach ($member in $members) {
            if (-not $member.deviceId) { continue }

            # Group members are Entra device objects; map to Intune managed devices
            $managed = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$($member.deviceId)'&`$select=id,deviceName,operatingSystem,lastSyncDateTime"
            foreach ($device in $managed) {
                $devices.Add($device)
            }
        }
    }

    # Collect diagnostics is a Windows-only action
    $windowsDevices = @($devices | Where-Object { $_.operatingSystem -eq "Windows" })
    $skipped = @($devices).Count - $windowsDevices.Count
    if ($skipped -gt 0) {
        Write-Warning "Skipped $skipped non-Windows device(s) - collect diagnostics only supports Windows"
    }

    return $windowsDevices
}

function Save-DiagnosticPackage {
    param(
        [object]$Device,
        [object]$Request
    )

    try {
        $downloadResponse = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($Device.id)/logCollectionRequests/$($Request.id)/createDownloadUrl" -Method POST
        $downloadUrl = $downloadResponse.value

        if (-not $downloadUrl) {
            Write-Warning "No download URL returned for '$($Device.deviceName)'"
            return $false
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $zipPath = Join-Path $OutputPath "DeviceDiagnostics_$($Device.deviceName)_$timestamp.zip"

        # The download URL is a pre-authenticated Azure Storage link from Graph,
        # so a plain web request (not Invoke-MgGraphRequest) is correct here
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
        Write-Information "✓ Downloaded: $zipPath" -InformationAction Continue
        return $true
    }
    catch {
        Write-Warning "Failed to download package for '$($Device.deviceName)': $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    $null = New-Item -Path $OutputPath -ItemType Directory -Force

    Write-Information "Resolving target devices..." -InformationAction Continue
    $targetDevices = Get-TargetDevice

    if (@($targetDevices).Count -eq 0) {
        throw "No Windows devices found to collect diagnostics from"
    }
    Write-Information "✓ Targeting $(@($targetDevices).Count) Windows device(s)" -InformationAction Continue

    $downloaded = 0
    $failed = 0
    $pendingRequests = @{}

    if ($DownloadExisting) {
        # Download the newest completed package per device without triggering anything
        foreach ($device in $targetDevices) {
            $requests = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/logCollectionRequests"
            # The response entity carries receivedDateTimeUTC (not receivedDateTime)
            $latestCompleted = @($requests | Where-Object { $_.status -eq "completed" } | Sort-Object -Property @{ Expression = {
                        $timestamp = if ($_.receivedDateTimeUTC) { $_.receivedDateTimeUTC } else { $_.requestedDateTimeUTC }
                        if ($timestamp) { [DateTime]::Parse($timestamp.ToString()) } else { [DateTime]::MinValue }
                    } } -Descending) | Select-Object -First 1

            if (-not $latestCompleted) {
                Write-Warning "No completed log collection exists for '$($device.deviceName)' - run without -DownloadExisting to trigger one"
                $failed++
                continue
            }

            if (Save-DiagnosticPackage -Device $device -Request $latestCompleted) { $downloaded++ } else { $failed++ }
        }
    }
    else {
        # Trigger a new collection on every device
        foreach ($device in $targetDevices) {
            try {
                # The action parameter is a nested deviceLogCollectionRequest object,
                # not a flat string (Graph rejects { templateType = "predefined" })
                $body = @{ templateType = @{ templateType = "predefined" } } | ConvertTo-Json
                $request = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/createDeviceLogCollectionRequest" -Method POST -Body $body -ContentType "application/json"
                $pendingRequests[$device.id] = @{ Device = $device; RequestId = $request.id }
                Write-Information "✓ Collection triggered on '$($device.deviceName)'" -InformationAction Continue
            }
            catch {
                Write-Warning "Failed to trigger collection on '$($device.deviceName)': $($_.Exception.Message)"
                $failed++
            }
        }

        # Poll until requests complete or the timeout is reached
        if ($pendingRequests.Count -gt 0) {
            Write-Information "Waiting for $($pendingRequests.Count) collection(s) to complete (timeout: $TimeoutMinutes minutes)..." -InformationAction Continue
            $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

            while ($pendingRequests.Count -gt 0 -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 30

                foreach ($deviceId in @($pendingRequests.Keys)) {
                    $entry = $pendingRequests[$deviceId]
                    try {
                        $status = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/logCollectionRequests/$($entry.RequestId)" -Method GET

                        if ($status.status -eq "completed") {
                            if (Save-DiagnosticPackage -Device $entry.Device -Request $status) { $downloaded++ } else { $failed++ }
                            $pendingRequests.Remove($deviceId)
                        }
                        elseif ($status.status -eq "failed") {
                            Write-Warning "Collection failed on '$($entry.Device.deviceName)'"
                            $failed++
                            $pendingRequests.Remove($deviceId)
                        }
                    }
                    catch {
                        Write-Verbose "Status check pending for '$($entry.Device.deviceName)': $($_.Exception.Message)"
                    }
                }
            }

            foreach ($deviceId in @($pendingRequests.Keys)) {
                $entry = $pendingRequests[$deviceId]
                Write-Warning "Collection on '$($entry.Device.deviceName)' did not complete within $TimeoutMinutes minutes - the device may be offline. Re-run later with -DownloadExisting to fetch the package."
            }
        }
    }

    # Summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "Diagnostics Collection Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Devices targeted:  $(@($targetDevices).Count)" -InformationAction Continue
    Write-Information "Packages saved:    $downloaded" -InformationAction Continue
    Write-Information "Failures/timeouts: $($failed + $pendingRequests.Count)" -InformationAction Continue
    Write-Information "Output folder:     $OutputPath" -InformationAction Continue
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
