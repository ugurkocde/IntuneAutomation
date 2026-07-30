#!/usr/bin/env pwsh

param(
    [string]$ScriptsRoot = "scripts",
    [string]$OutputDirectory = "azure-templates",
    [string]$RegistryPath = "azure-deployment-templates.json",
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = "ugurkocde/intuneautomation"
}

Add-Type -AssemblyName System.Web

function Get-ScriptMetadata {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw
    $metadata = @{}
    if ($content -match '(?s)<#(.*?)#>') {
        $commentBlock = $Matches[1]
        foreach ($field in @('TITLE', 'SYNOPSIS', 'DESCRIPTION', 'TAGS', 'PERMISSIONS', 'AUTHOR', 'VERSION', 'MINROLE', 'EXECUTION')) {
            if ($commentBlock -match "(?m)^\s*\.$field\s*\r?\n\s*(.+?)(?=\r?\n\s*\.|$)") {
                $metadata[$field] = $Matches[1].Trim()
            }
        }
    }
    return $metadata
}

function Test-RunbookEligible {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][hashtable]$Metadata
    )

    if ($RelativePath -match '^scripts/remediation/') { return $false }
    if ($Metadata.EXECUTION -eq 'LocalOnly') { return $false }
    return $true
}

function New-AzureRunbookTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptId,
        [Parameter(Mandatory = $true)][hashtable]$Metadata,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )

    $description = if ($Metadata.DESCRIPTION) {
        ($Metadata.DESCRIPTION -split '\r?\n' | Select-Object -First 1).Trim()
    }
    else {
        "IntuneAutomation runbook: $ScriptId"
    }
    $permissions = @(
        if ($Metadata.PERMISSIONS) {
            $Metadata.PERMISSIONS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
    )

    $accountLocationExpression = "[if(parameters('createAutomationAccount'), parameters('newAutomationAccountLocation'), reference(resourceId('Microsoft.Automation/automationAccounts', parameters('automationAccountName')), '2024-10-23', 'Full').location)]"
    $scriptUri = "https://raw.githubusercontent.com/$Repository/$Branch/$ScriptPath"
    $innerTemplate = [ordered]@{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters = [ordered]@{
            accountLocation = @{ type = "string" }
            automationAccountName = @{ type = "string" }
            runtimeEnvironmentName = @{ type = "string" }
            createRuntimeEnvironment = @{ type = "bool" }
            graphAuthenticationModuleVersion = @{ type = "string" }
            runbookName = @{ type = "string" }
            runbookDescription = @{ type = "string" }
        }
        variables = @{
            graphAuthenticationPackageUri = "[format('https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/{0}', parameters('graphAuthenticationModuleVersion'))]"
        }
        resources = @(
            @{
                condition = "[parameters('createRuntimeEnvironment')]"
                type = "Microsoft.Automation/automationAccounts/runtimeEnvironments"
                apiVersion = "2024-10-23"
                name = "[format('{0}/{1}', parameters('automationAccountName'), parameters('runtimeEnvironmentName'))]"
                location = "[parameters('accountLocation')]"
                properties = @{
                    description = "IntuneAutomation PowerShell 7.4 runtime"
                    runtime = @{
                        language = "PowerShell"
                        version = "7.4"
                    }
                    defaultPackages = @{
                        Az = "12.3.0"
                    }
                }
            },
            @{
                condition = "[parameters('createRuntimeEnvironment')]"
                type = "Microsoft.Automation/automationAccounts/runtimeEnvironments/packages"
                apiVersion = "2024-10-23"
                name = "[format('{0}/{1}/Microsoft.Graph.Authentication', parameters('automationAccountName'), parameters('runtimeEnvironmentName'))]"
                location = "[parameters('accountLocation')]"
                dependsOn = @(
                    "[resourceId('Microsoft.Automation/automationAccounts/runtimeEnvironments', parameters('automationAccountName'), parameters('runtimeEnvironmentName'))]"
                )
                properties = @{
                    contentLink = @{
                        uri = "[variables('graphAuthenticationPackageUri')]"
                        version = "[parameters('graphAuthenticationModuleVersion')]"
                    }
                }
            },
            @{
                type = "Microsoft.Automation/automationAccounts/runbooks"
                apiVersion = "2024-10-23"
                name = "[format('{0}/{1}', parameters('automationAccountName'), parameters('runbookName'))]"
                location = "[parameters('accountLocation')]"
                dependsOn = @(
                    "[resourceId('Microsoft.Automation/automationAccounts/runtimeEnvironments', parameters('automationAccountName'), parameters('runtimeEnvironmentName'))]",
                    "[resourceId('Microsoft.Automation/automationAccounts/runtimeEnvironments/packages', parameters('automationAccountName'), parameters('runtimeEnvironmentName'), 'Microsoft.Graph.Authentication')]"
                )
                properties = @{
                    runbookType = "PowerShell"
                    runtimeEnvironment = "[parameters('runtimeEnvironmentName')]"
                    logProgress = $false
                    logVerbose = $false
                    description = "[parameters('runbookDescription')]"
                    publishContentLink = @{ uri = $scriptUri }
                }
            }
        )
    }

    return [ordered]@{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "2.0.0.0"
        parameters = [ordered]@{
            automationAccountName = @{
                type = "string"
                metadata = @{
                    description = "Name of an existing Azure Automation account, or the name to create when createAutomationAccount is true."
                }
            }
            createAutomationAccount = @{
                type = "bool"
                defaultValue = $false
                metadata = @{
                    description = "Create a new Automation account. Leave false to reuse an account in the selected resource group without modifying its identity or region."
                }
            }
            newAutomationAccountLocation = @{
                type = "string"
                defaultValue = "[resourceGroup().location]"
                metadata = @{
                    description = "Used only when createAutomationAccount is true. Existing accounts always use their current Azure region."
                }
            }
            runtimeEnvironmentName = @{
                type = "string"
                defaultValue = "IntuneAutomation-PS74"
                metadata = @{
                    description = "PowerShell 7.4 Runtime Environment to create or associate with the runbook."
                }
            }
            createRuntimeEnvironment = @{
                type = "bool"
                defaultValue = $true
                metadata = @{
                    description = "Create or update the PowerShell 7.4 Runtime Environment and Microsoft.Graph.Authentication package. Set false only when the named environment already exists and contains that package."
                }
            }
            graphAuthenticationModuleVersion = @{
                type = "string"
                defaultValue = "2.38.1"
                metadata = @{
                    description = "Microsoft.Graph.Authentication package version imported when createRuntimeEnvironment is true."
                }
            }
            runbookName = @{
                type = "string"
                defaultValue = $ScriptId
                metadata = @{
                    description = "Name of the runbook to create or update."
                }
            }
            runbookDescription = @{
                type = "string"
                defaultValue = $description
                metadata = @{
                    description = "Description stored on the Azure Automation runbook."
                }
            }
        }
        variables = @{ scriptUri = $scriptUri }
        resources = @(
            @{
                condition = "[parameters('createAutomationAccount')]"
                type = "Microsoft.Automation/automationAccounts"
                apiVersion = "2024-10-23"
                name = "[parameters('automationAccountName')]"
                location = "[parameters('newAutomationAccountLocation')]"
                identity = @{ type = "SystemAssigned" }
                properties = @{ sku = @{ name = "Basic" } }
            },
            @{
                type = "Microsoft.Resources/deployments"
                apiVersion = "2025-04-01"
                name = "configureRunbook"
                dependsOn = @(
                    "[resourceId('Microsoft.Automation/automationAccounts', parameters('automationAccountName'))]"
                )
                properties = @{
                    mode = "Incremental"
                    expressionEvaluationOptions = @{ scope = "inner" }
                    parameters = @{
                        accountLocation = @{ value = $accountLocationExpression }
                        automationAccountName = @{ value = "[parameters('automationAccountName')]" }
                        runtimeEnvironmentName = @{ value = "[parameters('runtimeEnvironmentName')]" }
                        createRuntimeEnvironment = @{ value = "[parameters('createRuntimeEnvironment')]" }
                        graphAuthenticationModuleVersion = @{ value = "[parameters('graphAuthenticationModuleVersion')]" }
                        runbookName = @{ value = "[parameters('runbookName')]" }
                        runbookDescription = @{ value = "[parameters('runbookDescription')]" }
                    }
                    template = $innerTemplate
                }
            }
        )
        outputs = [ordered]@{
            runbookName = @{
                type = "string"
                value = "[parameters('runbookName')]"
            }
            automationAccountName = @{
                type = "string"
                value = "[parameters('automationAccountName')]"
            }
            automationAccountLocation = @{
                type = "string"
                value = $accountLocationExpression
            }
            runtimeEnvironmentName = @{
                type = "string"
                value = "[parameters('runtimeEnvironmentName')]"
            }
            requiredGraphPermissions = @{
                type = "array"
                value = $permissions
            }
            runbookUrl = @{
                type = "string"
                value = "[concat('https://portal.azure.com/#@', subscription().tenantId, '/resource/subscriptions/', subscription().subscriptionId, '/resourceGroups/', resourceGroup().name, '/providers/Microsoft.Automation/automationAccounts/', parameters('automationAccountName'), '/runbooks/', parameters('runbookName'))]"
            }
            scriptSourceUrl = @{
                type = "string"
                value = "[variables('scriptUri')]"
            }
            deploymentInstructions = @{
                type = "string"
                value = "The runbook is published and linked to the selected PowerShell Runtime Environment. Grant only the required Microsoft Graph application permissions shown in requiredGraphPermissions to the Automation account managed identity, then test the runbook with explicit parameters."
            }
        }
    }
}

if (Test-Path -Path $OutputDirectory) {
    Remove-Item -Path $OutputDirectory -Recurse -Force
}
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

$generatedAt = if ($env:SOURCE_DATE) {
    ([datetime]$env:SOURCE_DATE).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
else {
    (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$registry = [ordered]@{
    generated = $generatedAt
    runtime = "PowerShell 7.4"
    templates = [ordered]@{}
}

$scriptFiles = Get-ChildItem -Path $ScriptsRoot -Recurse -Filter "*.ps1" | Sort-Object FullName
$generatedCount = 0
$excludedCount = 0

foreach ($scriptFile in $scriptFiles) {
    $relativePath = $scriptFile.FullName.Replace((Get-Location).Path + [IO.Path]::DirectorySeparatorChar, "").Replace('\', '/')
    $metadata = Get-ScriptMetadata -FilePath $scriptFile.FullName
    if (-not (Test-RunbookEligible -RelativePath $relativePath -Metadata $metadata)) {
        Write-Output "Excluded from runbook templates: $relativePath"
        $excludedCount++
        continue
    }

    $scriptId = [IO.Path]::GetFileNameWithoutExtension($scriptFile.Name)
    $template = New-AzureRunbookTemplate -ScriptId $scriptId -Metadata $metadata -ScriptPath $relativePath
    $templateFileName = "$scriptId-azure-deployment.json"
    $templatePath = Join-Path $OutputDirectory $templateFileName
    $template | ConvertTo-Json -Depth 30 | Set-Content -Path $templatePath -Encoding utf8

    $templateUrl = "https://raw.githubusercontent.com/$Repository/$Branch/$OutputDirectory/$templateFileName"
    $registry.templates[$scriptId] = [ordered]@{
        title = $metadata.TITLE
        description = $metadata.DESCRIPTION
        tags = @($metadata.TAGS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        permissions = @($metadata.PERMISSIONS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        author = $metadata.AUTHOR
        version = $metadata.VERSION
        runtime = "PowerShell 7.4"
        supportsExistingAutomationAccount = $true
        templateUrl = $templateUrl
        deployUrl = "https://portal.azure.com/#create/Microsoft.Template/uri/$([System.Web.HttpUtility]::UrlEncode($templateUrl))"
        scriptPath = $relativePath
    }
    $generatedCount++
    Write-Output "Generated template: $scriptId"
}

$registry | ConvertTo-Json -Depth 20 | Set-Content -Path $RegistryPath -Encoding utf8
Write-Output "Generated $generatedCount runbook templates. Excluded $excludedCount non-runbook PowerShell scripts."
