<#
.TITLE
    Backup Intune Configuration

.SYNOPSIS
    Exports Intune configuration profiles, compliance policies, ADMX policies, and platform scripts to JSON files for backup and versioning.

.DESCRIPTION
    This script connects to Microsoft Graph and exports the core Intune configuration
    surfaces to a timestamped backup folder: device configuration profiles, settings
    catalog policies (including their full setting bodies), compliance policies,
    administrative template (ADMX) policies with their definition values, Windows
    PowerShell scripts, and macOS shell scripts. Each object is written as one JSON
    file including its assignments, and a manifest summarizes the backup. The output
    is designed to be stored in source control for change tracking and used as input
    for the companion restore-intune-configuration script.

.TAGS
    Configuration

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\backup-intune-configuration.ps1
    Exports all supported configuration areas to a timestamped folder in the current directory

.EXAMPLE
    .\backup-intune-configuration.ps1 -OutputPath "C:\IntuneBackups" -Areas DeviceConfigurations,CompliancePolicies
    Exports only classic configuration profiles and compliance policies to C:\IntuneBackups

.EXAMPLE
    .\backup-intune-configuration.ps1 -SkipScriptContent
    Exports all areas but skips downloading the base64 script bodies of platform scripts

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses beta Graph endpoints because the full Intune configuration surface is not exposed on v1.0
    - Settings catalog setting bodies and ADMX definition values require one extra request per policy
    - Graph never returns secret values (encrypted OMA-URI settings, passwords, certificates) in exports; those settings appear with secret references only and must be re-entered manually after a restore
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Folder in which the timestamped backup folder is created")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Configuration areas to export")]
    [ValidateSet("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts")]
    [string[]]$Areas = @("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts"),

    [Parameter(Mandatory = $false, HelpMessage = "Skip downloading base64 script bodies of platform scripts")]
    [switch]$SkipScriptContent,

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
            "DeviceManagementConfiguration.Read.All"
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

function Get-SafeFileName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "unnamed"
    }

    $safe = $Name -replace '[\\/:*?"<>|]', '_'
    $safe = $safe.Trim().Trim('.')
    if ($safe.Length -gt 120) {
        $safe = $safe.Substring(0, 120)
    }
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed"
    }
    return $safe
}

function Export-BackupObject {
    param(
        [object]$InputObject,
        [string]$FolderPath,
        [string]$DisplayName,
        [string]$Id
    )

    $fileName = "$(Get-SafeFileName -Name $DisplayName)_$Id.json"
    $filePath = Join-Path $FolderPath $fileName
    $InputObject | ConvertTo-Json -Depth 25 | Out-File -FilePath $filePath -Encoding utf8
    return $fileName
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting Intune configuration backup..." -InformationAction Continue

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupRoot = Join-Path $OutputPath "IntuneConfigBackup_$timestamp"
    $null = New-Item -Path $backupRoot -ItemType Directory -Force

    $manifest = [ordered]@{
        backupDate    = (Get-Date -Format "o")
        areas         = @{}
        totalObjects  = 0
        backupVersion = "1.0"
    }

    # ----- Classic device configuration profiles -----
    if ($Areas -contains "DeviceConfigurations") {
        Write-Information "Exporting device configuration profiles..." -InformationAction Continue
        $folder = Join-Path $backupRoot "DeviceConfigurations"
        $null = New-Item -Path $folder -ItemType Directory -Force

        $profiles = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"
        foreach ($configProfile in $profiles) {
            $null = Export-BackupObject -InputObject $configProfile -FolderPath $folder -DisplayName $configProfile.displayName -Id $configProfile.id
        }

        $manifest.areas["DeviceConfigurations"] = @($profiles).Count
        $manifest.totalObjects += @($profiles).Count
        Write-Information "✓ Exported $(@($profiles).Count) device configuration profiles" -InformationAction Continue
    }

    # ----- Settings catalog policies -----
    if ($Areas -contains "SettingsCatalog") {
        Write-Information "Exporting settings catalog policies..." -InformationAction Continue
        $folder = Join-Path $backupRoot "SettingsCatalog"
        $null = New-Item -Path $folder -ItemType Directory -Force

        $policies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments"
        foreach ($policy in $policies) {
            # The list endpoint returns only a settingCount; the full setting bodies
            # live behind the per-policy settings navigation
            $settings = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/settings"
            $policy | Add-Member -MemberType NoteProperty -Name "settings" -Value @($settings) -Force

            $null = Export-BackupObject -InputObject $policy -FolderPath $folder -DisplayName $policy.name -Id $policy.id
        }

        $manifest.areas["SettingsCatalog"] = @($policies).Count
        $manifest.totalObjects += @($policies).Count
        Write-Information "✓ Exported $(@($policies).Count) settings catalog policies" -InformationAction Continue
    }

    # ----- Compliance policies -----
    if ($Areas -contains "CompliancePolicies") {
        Write-Information "Exporting compliance policies..." -InformationAction Continue
        $folder = Join-Path $backupRoot "CompliancePolicies"
        $null = New-Item -Path $folder -ItemType Directory -Force

        # scheduledActionsForRule must be expanded explicitly; recreating a policy
        # without it is rejected by Graph, so the backup would be incomplete
        $compliancePolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
        foreach ($policy in $compliancePolicies) {
            $null = Export-BackupObject -InputObject $policy -FolderPath $folder -DisplayName $policy.displayName -Id $policy.id
        }

        $manifest.areas["CompliancePolicies"] = @($compliancePolicies).Count
        $manifest.totalObjects += @($compliancePolicies).Count
        Write-Information "✓ Exported $(@($compliancePolicies).Count) compliance policies" -InformationAction Continue
    }

    # ----- Administrative template (ADMX) policies -----
    if ($Areas -contains "AdmxPolicies") {
        Write-Information "Exporting administrative template policies..." -InformationAction Continue
        $folder = Join-Path $backupRoot "AdmxPolicies"
        $null = New-Item -Path $folder -ItemType Directory -Force

        $admxPolicies = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments"
        foreach ($policy in $admxPolicies) {
            # Definition values carry the actual configured settings; the expanded
            # definition gives human-readable names for the restore/report side
            $definitionValues = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policy.id)/definitionValues?`$expand=definition(`$select=id,classType,displayName,categoryPath),presentationValues"
            $policy | Add-Member -MemberType NoteProperty -Name "definitionValues" -Value @($definitionValues) -Force

            $null = Export-BackupObject -InputObject $policy -FolderPath $folder -DisplayName $policy.displayName -Id $policy.id
        }

        $manifest.areas["AdmxPolicies"] = @($admxPolicies).Count
        $manifest.totalObjects += @($admxPolicies).Count
        Write-Information "✓ Exported $(@($admxPolicies).Count) administrative template policies" -InformationAction Continue
    }

    # ----- Platform scripts (Windows PowerShell + macOS shell) -----
    if ($Areas -contains "PlatformScripts") {
        Write-Information "Exporting platform scripts..." -InformationAction Continue
        $folder = Join-Path $backupRoot "PlatformScripts"
        $null = New-Item -Path $folder -ItemType Directory -Force

        $scriptSurfaces = @(
            @{ Name = "deviceManagementScripts"; Label = "Windows PowerShell scripts" },
            @{ Name = "deviceShellScripts"; Label = "macOS shell scripts" }
        )

        $scriptCount = 0
        foreach ($surface in $scriptSurfaces) {
            $platformScripts = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/$($surface.Name)?`$expand=assignments"

            foreach ($platformScript in $platformScripts) {
                # scriptContent is always null on the list endpoint; the single-object
                # GET returns the base64 body
                if (-not $SkipScriptContent) {
                    try {
                        $detail = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/$($surface.Name)/$($platformScript.id)" -Method GET
                        $platformScript.scriptContent = $detail.scriptContent
                    }
                    catch {
                        Write-Warning "Could not fetch script content for '$($platformScript.displayName)': $($_.Exception.Message)"
                    }
                }

                $platformScript | Add-Member -MemberType NoteProperty -Name "scriptSurface" -Value $surface.Name -Force
                $null = Export-BackupObject -InputObject $platformScript -FolderPath $folder -DisplayName $platformScript.displayName -Id $platformScript.id
                $scriptCount++
            }

            Write-Information "✓ Exported $(@($platformScripts).Count) $($surface.Label)" -InformationAction Continue
        }

        $manifest.areas["PlatformScripts"] = $scriptCount
        $manifest.totalObjects += $scriptCount
    }

    # ----- Manifest -----
    $manifestPath = Join-Path $backupRoot "manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding utf8

    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "Backup Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    foreach ($area in $manifest.areas.Keys) {
        Write-Information "$($area): $($manifest.areas[$area]) objects" -InformationAction Continue
    }
    Write-Information "Total: $($manifest.totalObjects) objects" -InformationAction Continue
    Write-Information "Backup folder: $backupRoot" -InformationAction Continue
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
