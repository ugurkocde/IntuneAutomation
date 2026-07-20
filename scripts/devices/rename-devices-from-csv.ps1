<#
.TITLE
    Rename Devices from CSV

.SYNOPSIS
    Bulk-renames Intune Windows devices from a CSV mapping file using the setDeviceName remote action.

.DESCRIPTION
    This script reads a CSV file with DeviceName and NewName columns and triggers the
    Intune setDeviceName remote action for each matching Windows device. Every rename
    supports -WhatIf preview, name validation catches illegal computer names before
    any action is sent, and results are summarized per device. Devices are renamed on
    their next check-in; Windows devices typically need a restart for the new name to
    fully apply.

.TAGS
    Devices,Operational

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.PrivilegedOperations.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\rename-devices-from-csv.ps1 -CsvPath ".\renames.csv" -WhatIf
    Previews all renames without sending any action

.EXAMPLE
    .\rename-devices-from-csv.ps1 -CsvPath ".\renames.csv"
    Renames all devices listed in the CSV (columns: DeviceName,NewName)

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - CSV must contain the columns DeviceName (current Intune device name) and NewName
    - Windows computer names: max 15 characters, letters/digits/hyphens, not all digits
    - The rename applies at next device check-in; a restart completes it on Windows
    - setDeviceName requires the DeviceManagementManagedDevices.PrivilegedOperations.All scope
    - Uses beta Graph endpoints because the setDeviceName action is exposed there for all platforms
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to CSV file with DeviceName,NewName columns")]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

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
            "DeviceManagementManagedDevices.PrivilegedOperations.All",
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

function Test-ValidComputerName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name.Length -gt 15) { return $false }
    if ($Name -match '^[0-9]+$') { return $false }
    if ($Name -notmatch '^[A-Za-z0-9-]+$') { return $false }
    if ($Name.StartsWith("-") -or $Name.EndsWith("-")) { return $false }
    return $true
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file '$CsvPath' does not exist"
    }

    $renameEntries = @(Import-Csv -Path $CsvPath)
    if ($renameEntries.Count -eq 0) {
        throw "CSV file '$CsvPath' contains no rows"
    }

    $csvColumns = $renameEntries[0].PSObject.Properties.Name
    if ($csvColumns -notcontains "DeviceName" -or $csvColumns -notcontains "NewName") {
        throw "CSV must contain the columns 'DeviceName' and 'NewName' (found: $($csvColumns -join ', '))"
    }

    Write-Information "✓ Loaded $($renameEntries.Count) rename entries from CSV" -InformationAction Continue

    [System.Collections.Generic.List[Object]]$report = @()
    $renamed = 0
    $failed = 0
    $skipped = 0

    foreach ($entry in $renameEntries) {
        $currentName = $entry.DeviceName.Trim()
        $newName = $entry.NewName.Trim()

        # Validate before touching Graph so one bad row cannot burn an action
        if (-not (Test-ValidComputerName -Name $newName)) {
            Write-Warning "Skipping '$currentName': new name '$newName' is not a valid computer name (max 15 chars, letters/digits/hyphens, not all digits)"
            $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "InvalidName" })
            $skipped++
            continue
        }

        $escapedName = $currentName -replace "'", "''"
        $found = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$escapedName'&`$select=id,deviceName,operatingSystem"

        if (@($found).Count -eq 0) {
            Write-Warning "Skipping '$currentName': device not found in Intune"
            $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "NotFound" })
            $skipped++
            continue
        }
        if (@($found).Count -gt 1) {
            Write-Warning "Skipping '$currentName': $(@($found).Count) devices share this name - rename manually to avoid hitting the wrong one"
            $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "AmbiguousName" })
            $skipped++
            continue
        }

        $device = @($found)[0]

        if ($PSCmdlet.ShouldProcess("$currentName -> $newName", "Send setDeviceName action")) {
            try {
                $body = @{ deviceName = $newName } | ConvertTo-Json
                Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/setDeviceName" -Method POST -Body $body -ContentType "application/json"
                Write-Information "✓ Rename queued: $currentName -> $newName" -InformationAction Continue
                $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "Queued" })
                $renamed++
            }
            catch {
                Write-Warning "Failed to rename '$currentName': $($_.Exception.Message)"
                $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "Failed" })
                $failed++
            }
        }
        else {
            $report.Add([PSCustomObject]@{ DeviceName = $currentName; NewName = $newName; Result = "WhatIf" })
        }
    }

    # Summary
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "Rename Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "CSV entries:     $($renameEntries.Count)" -InformationAction Continue
    Write-Information "Renames queued:  $renamed" -InformationAction Continue
    Write-Information "Failed:          $failed" -InformationAction Continue
    Write-Information "Skipped:         $skipped" -InformationAction Continue
    Write-Information "Note: renames apply at next device check-in; Windows devices need a restart to complete" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvOutPath = Join-Path $OutputPath "Device_Rename_Results_$timestamp.csv"
        $report | Export-Csv -Path $csvOutPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvOutPath" -InformationAction Continue
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
