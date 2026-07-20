<#
.TITLE
    Restore Intune Configuration

.SYNOPSIS
    Restores Intune configuration profiles, compliance policies, ADMX policies, and platform scripts from a JSON backup created by backup-intune-configuration.

.DESCRIPTION
    This script reads a backup folder produced by backup-intune-configuration.ps1 and
    recreates the exported objects in the target tenant: device configuration profiles,
    settings catalog policies, compliance policies, administrative template (ADMX)
    policies with their definition values, and platform scripts. Objects are always
    created as new entries (no in-place overwrite), read-only properties are stripped
    from the payloads, and every create supports -WhatIf preview. Assignment restore is
    optional and off by default because group IDs from the source tenant may not exist
    in the target tenant.

.TAGS
    Configuration

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\restore-intune-configuration.ps1 -BackupPath ".\IntuneConfigBackup_2026-07-20_10-00-00" -WhatIf
    Previews everything that would be created without writing to the tenant

.EXAMPLE
    .\restore-intune-configuration.ps1 -BackupPath ".\IntuneConfigBackup_2026-07-20_10-00-00" -Areas CompliancePolicies
    Restores only the compliance policies from the backup

.EXAMPLE
    .\restore-intune-configuration.ps1 -BackupPath ".\IntuneConfigBackup_2026-07-20_10-00-00" -RestoreAssignments
    Restores all areas including group assignments (same-tenant restore)

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Uses beta Graph endpoints because the full Intune configuration surface is not exposed on v1.0
    - Objects are created as new entries; existing policies with the same name are not touched, so a re-run creates duplicates
    - Compliance policies are created with their exported scheduledActionsForRule; if a backup predates that field, a default block rule is added because Graph rejects policies without one
    - Secret values (encrypted OMA-URI settings, passwords, certificates) are never present in Graph exports and must be re-entered manually after restore
    - ADMX presentation values referencing definitions that do not exist in the target tenant are skipped with a warning
    - Assignment restore requires the original group IDs to exist in the target tenant; failures are reported per policy and do not stop the restore
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to a folder created by backup-intune-configuration.ps1")]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath,

    [Parameter(Mandatory = $false, HelpMessage = "Configuration areas to restore")]
    [ValidateSet("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts")]
    [string[]]$Areas = @("DeviceConfigurations", "SettingsCatalog", "CompliancePolicies", "AdmxPolicies", "PlatformScripts"),

    [Parameter(Mandatory = $false, HelpMessage = "Also restore group assignments (requires source group IDs to exist)")]
    [switch]$RestoreAssignments,

    [Parameter(Mandatory = $false, HelpMessage = "Prefix added to restored object names, e.g. 'Restored - '")]
    [string]$NamePrefix = "",

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
            "DeviceManagementConfiguration.ReadWrite.All"
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

function ConvertTo-Hashtable {
    param([object]$InputObject)

    # ConvertFrom-Json gives PSCustomObjects; Graph payloads are easier to
    # sanitize as nested hashtables
    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable -InputObject $_ })
    }

    if ($InputObject -is [PSCustomObject]) {
        $hash = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }

    return $InputObject
}

function Remove-ReadOnlyProperty {
    param(
        [hashtable]$Payload,
        [string[]]$ExtraProperties = @()
    )

    $readOnly = @(
        "id", "createdDateTime", "lastModifiedDateTime", "version",
        "assignments", "assignments@odata.context", "@odata.context",
        "settingCount", "priorityMetaData", "supportsScopeTags",
        "creationSource", "policyConfigurationIngestionType",
        "scriptSurface", "definitionValues", "settings@odata.context"
    ) + $ExtraProperties

    foreach ($property in $readOnly) {
        $Payload.Remove($property)
    }

    # Expanded navigation annotations (xyz@odata.context) are metadata, not payload
    foreach ($key in @($Payload.Keys)) {
        if ($key -like "*@odata.context" -or $key -like "*@odata.count") {
            $Payload.Remove($key)
        }
    }

    return $Payload
}

function Invoke-AssignmentRestore {
    param(
        [string]$AssignUri,
        [string]$AssignmentsPropertyName,
        [object[]]$Assignments,
        [string]$DisplayName
    )

    if (-not $Assignments -or @($Assignments).Count -eq 0) {
        return
    }

    $cleanAssignments = foreach ($assignment in $Assignments) {
        $a = ConvertTo-Hashtable -InputObject $assignment
        $a.Remove("id")
        $a.Remove("sourceId")
        $a
    }

    $body = @{ $AssignmentsPropertyName = @($cleanAssignments) }

    try {
        $null = Invoke-MgGraphRequest -Uri $AssignUri -Method POST -Body ($body | ConvertTo-Json -Depth 15) -ContentType "application/json"
        Write-Information "  ✓ Restored $(@($cleanAssignments).Count) assignments for '$DisplayName'" -InformationAction Continue
    }
    catch {
        Write-Warning "  Could not restore assignments for '$DisplayName' (groups may not exist in this tenant): $($_.Exception.Message)"
    }
}

function Get-BackupFile {
    param([string]$AreaFolder)

    $folder = Join-Path $BackupPath $AreaFolder
    if (-not (Test-Path $folder)) {
        Write-Warning "Backup folder '$AreaFolder' not found in $BackupPath - skipping"
        return @()
    }

    return @(Get-ChildItem -Path $folder -Filter "*.json" -File)
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    if (-not (Test-Path $BackupPath)) {
        throw "Backup path '$BackupPath' does not exist"
    }

    Write-Information "Starting Intune configuration restore from: $BackupPath" -InformationAction Continue

    $restored = 0
    $failed = 0

    # ----- Classic device configuration profiles -----
    if ($Areas -contains "DeviceConfigurations") {
        foreach ($file in (Get-BackupFile -AreaFolder "DeviceConfigurations")) {
            $source = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $displayName = "$NamePrefix$($source.displayName)"
            $assignments = $source.assignments

            $payload = Remove-ReadOnlyProperty -Payload (ConvertTo-Hashtable -InputObject $source)
            $payload.displayName = $displayName

            if ($PSCmdlet.ShouldProcess($displayName, "Create device configuration profile")) {
                try {
                    $created = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -Method POST -Body ($payload | ConvertTo-Json -Depth 25) -ContentType "application/json"
                    Write-Information "✓ Created profile: $displayName" -InformationAction Continue
                    $restored++

                    if ($RestoreAssignments) {
                        Invoke-AssignmentRestore -AssignUri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($created.id)/assign" -AssignmentsPropertyName "assignments" -Assignments $assignments -DisplayName $displayName
                    }
                }
                catch {
                    Write-Warning "Failed to create profile '$displayName': $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    # ----- Settings catalog policies -----
    if ($Areas -contains "SettingsCatalog") {
        foreach ($file in (Get-BackupFile -AreaFolder "SettingsCatalog")) {
            $source = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $displayName = "$NamePrefix$($source.name)"
            $assignments = $source.assignments

            $settings = foreach ($setting in @($source.settings)) {
                $s = ConvertTo-Hashtable -InputObject $setting
                $s.Remove("id")
                $s
            }

            $payload = @{
                name         = $displayName
                description  = [string]$source.description
                platforms    = $source.platforms
                technologies = $source.technologies
                settings     = @($settings)
            }
            if ($source.roleScopeTagIds) { $payload.roleScopeTagIds = @($source.roleScopeTagIds) }
            if ($source.templateReference -and $source.templateReference.templateId) {
                $payload.templateReference = @{ templateId = $source.templateReference.templateId }
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create settings catalog policy")) {
                try {
                    $created = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Method POST -Body ($payload | ConvertTo-Json -Depth 30) -ContentType "application/json"
                    Write-Information "✓ Created settings catalog policy: $displayName" -InformationAction Continue
                    $restored++

                    if ($RestoreAssignments) {
                        Invoke-AssignmentRestore -AssignUri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($created.id)/assign" -AssignmentsPropertyName "assignments" -Assignments $assignments -DisplayName $displayName
                    }
                }
                catch {
                    Write-Warning "Failed to create settings catalog policy '$displayName': $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    # ----- Compliance policies -----
    if ($Areas -contains "CompliancePolicies") {
        foreach ($file in (Get-BackupFile -AreaFolder "CompliancePolicies")) {
            $source = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $displayName = "$NamePrefix$($source.displayName)"
            $assignments = $source.assignments

            $payload = Remove-ReadOnlyProperty -Payload (ConvertTo-Hashtable -InputObject $source) -ExtraProperties @("deviceCompliancePolicyScript")
            $payload.displayName = $displayName

            # Graph rejects compliance policies created without a scheduled action rule
            if ($payload.scheduledActionsForRule) {
                $payload.scheduledActionsForRule = @(foreach ($rule in @($payload.scheduledActionsForRule)) {
                        $rule.Remove("id")
                        if ($rule.scheduledActionConfigurations) {
                            $rule.scheduledActionConfigurations = @(foreach ($config in @($rule.scheduledActionConfigurations)) {
                                    $config.Remove("id")
                                    $config
                                })
                        }
                        $rule
                    })
            }
            else {
                $payload.scheduledActionsForRule = @(
                    @{
                        ruleName                      = "PasswordRequired"
                        scheduledActionConfigurations = @(
                            @{ actionType = "block"; gracePeriodHours = 0; notificationTemplateId = ""; notificationMessageCCList = @() }
                        )
                    }
                )
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create compliance policy")) {
                try {
                    $created = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" -Method POST -Body ($payload | ConvertTo-Json -Depth 25) -ContentType "application/json"
                    Write-Information "✓ Created compliance policy: $displayName" -InformationAction Continue
                    $restored++

                    if ($RestoreAssignments) {
                        Invoke-AssignmentRestore -AssignUri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($created.id)/assign" -AssignmentsPropertyName "assignments" -Assignments $assignments -DisplayName $displayName
                    }
                }
                catch {
                    Write-Warning "Failed to create compliance policy '$displayName': $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    # ----- Administrative template (ADMX) policies -----
    if ($Areas -contains "AdmxPolicies") {
        foreach ($file in (Get-BackupFile -AreaFolder "AdmxPolicies")) {
            $source = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $displayName = "$NamePrefix$($source.displayName)"
            $assignments = $source.assignments

            $payload = @{
                displayName = $displayName
                description = [string]$source.description
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create administrative template policy")) {
                try {
                    $created = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations" -Method POST -Body ($payload | ConvertTo-Json) -ContentType "application/json"
                    Write-Information "✓ Created administrative template policy: $displayName" -InformationAction Continue
                    $restored++

                    # Definition values are created one by one against the new policy
                    foreach ($definitionValue in @($source.definitionValues)) {
                        if (-not $definitionValue.definition -or -not $definitionValue.definition.id) {
                            Write-Warning "  Skipping a definition value without definition reference in '$displayName'"
                            continue
                        }

                        $dvPayload = @{
                            enabled                 = [bool]$definitionValue.enabled
                            "definition@odata.bind" = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($definitionValue.definition.id)')"
                        }

                        if ($definitionValue.presentationValues) {
                            $dvPayload.presentationValues = @(foreach ($presentationValue in @($definitionValue.presentationValues)) {
                                    $pv = ConvertTo-Hashtable -InputObject $presentationValue
                                    $presentationId = $null
                                    if ($presentationValue.presentation -and $presentationValue.presentation.id) {
                                        $presentationId = $presentationValue.presentation.id
                                    }
                                    $pv.Remove("id")
                                    $pv.Remove("createdDateTime")
                                    $pv.Remove("lastModifiedDateTime")
                                    $pv.Remove("presentation")
                                    if ($presentationId) {
                                        $pv["presentation@odata.bind"] = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($definitionValue.definition.id)')/presentations('$presentationId')"
                                    }
                                    $pv
                                })
                        }

                        try {
                            $null = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($created.id)/definitionValues" -Method POST -Body ($dvPayload | ConvertTo-Json -Depth 15) -ContentType "application/json"
                        }
                        catch {
                            Write-Warning "  Could not restore setting '$($definitionValue.definition.displayName)' in '$displayName': $($_.Exception.Message)"
                        }
                    }

                    if ($RestoreAssignments) {
                        Invoke-AssignmentRestore -AssignUri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($created.id)/assign" -AssignmentsPropertyName "assignments" -Assignments $assignments -DisplayName $displayName
                    }
                }
                catch {
                    Write-Warning "Failed to create administrative template policy '$displayName': $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    # ----- Platform scripts -----
    if ($Areas -contains "PlatformScripts") {
        foreach ($file in (Get-BackupFile -AreaFolder "PlatformScripts")) {
            $source = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $displayName = "$NamePrefix$($source.displayName)"
            $assignments = $source.assignments
            $surface = if ($source.scriptSurface) { $source.scriptSurface } else { "deviceManagementScripts" }

            if (-not $source.scriptContent) {
                Write-Warning "Skipping platform script '$displayName': backup contains no script content (was -SkipScriptContent used?)"
                continue
            }

            $payload = Remove-ReadOnlyProperty -Payload (ConvertTo-Hashtable -InputObject $source)
            $payload.displayName = $displayName

            if ($PSCmdlet.ShouldProcess($displayName, "Create platform script ($surface)")) {
                try {
                    $created = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/$surface" -Method POST -Body ($payload | ConvertTo-Json -Depth 10) -ContentType "application/json"
                    Write-Information "✓ Created platform script: $displayName" -InformationAction Continue
                    $restored++

                    if ($RestoreAssignments) {
                        # Both script surfaces use the same assign action property name
                        Invoke-AssignmentRestore -AssignUri "https://graph.microsoft.com/beta/deviceManagement/$surface/$($created.id)/assign" -AssignmentsPropertyName "deviceManagementScriptAssignments" -Assignments $assignments -DisplayName $displayName
                    }
                }
                catch {
                    Write-Warning "Failed to create platform script '$displayName': $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    # ----- Summary -----
    Write-Information "`n========================================" -InformationAction Continue
    Write-Information "Restore Summary" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue
    Write-Information "Objects created: $restored" -InformationAction Continue
    Write-Information "Objects failed:  $failed" -InformationAction Continue
    Write-Information "========================================" -InformationAction Continue

    if ($failed -gt 0) {
        Write-Warning "Some objects failed to restore - review the warnings above"
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
