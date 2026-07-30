#!/usr/bin/env pwsh

param(
    [string]$ScriptsRoot = "scripts",
    [string]$TemplateDirectory = "azure-templates",
    [string]$RegistryPath = "azure-deployment-templates.json"
)

$ErrorActionPreference = "Stop"
$failures = [System.Collections.Generic.List[string]]::new()

function Get-ExecutionMode {
    param([string]$Path)

    $content = Get-Content -Path $Path -Raw
    if ($content -match '(?im)^\s*\.EXECUTION\s*\r?\n\s*(\S+)\s*$') {
        return $Matches[1]
    }
    return ""
}

$eligibleScripts = @(
    Get-ChildItem -Path $ScriptsRoot -Recurse -Filter "*.ps1" |
        Where-Object {
            $_.FullName -notmatch "[\\/]remediation[\\/]" -and
            (Get-ExecutionMode -Path $_.FullName) -ne "LocalOnly"
        }
)
$templateFiles = @(Get-ChildItem -Path $TemplateDirectory -Filter "*-azure-deployment.json")

if ($templateFiles.Count -ne $eligibleScripts.Count) {
    $failures.Add("Expected $($eligibleScripts.Count) templates, found $($templateFiles.Count).")
}

$eligibleIds = @($eligibleScripts.BaseName)
foreach ($templateFile in $templateFiles) {
    $scriptId = $templateFile.BaseName -replace '-azure-deployment$', ''
    if ($scriptId -notin $eligibleIds) {
        $failures.Add("Template '$($templateFile.Name)' does not map to a runbook-eligible script.")
        continue
    }

    try {
        $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json -Depth 50
    }
    catch {
        $failures.Add("Template '$($templateFile.Name)' is invalid JSON: $($_.Exception.Message)")
        continue
    }

    $accountResource = @($template.resources | Where-Object type -eq "Microsoft.Automation/automationAccounts")
    $deploymentResource = @($template.resources | Where-Object type -eq "Microsoft.Resources/deployments")
    $innerResources = @(
        if ($deploymentResource.Count -eq 1) {
            $deploymentResource[0].properties.template.resources
        }
    )
    $runbookResource = @($innerResources | Where-Object type -eq "Microsoft.Automation/automationAccounts/runbooks")
    $runtimeResource = @($innerResources | Where-Object type -eq "Microsoft.Automation/automationAccounts/runtimeEnvironments")
    $packageResource = @($innerResources | Where-Object type -eq "Microsoft.Automation/automationAccounts/runtimeEnvironments/packages")

    if ($accountResource.Count -ne 1 -or $accountResource[0].condition -ne "[parameters('createAutomationAccount')]") {
        $failures.Add("Template '$($templateFile.Name)' does not conditionally create the Automation account.")
    }
    if ($deploymentResource.Count -ne 1) {
        $failures.Add("Template '$($templateFile.Name)' does not use a nested deployment for the resolved Automation account location.")
    }
    elseif (
        $deploymentResource[0].properties.parameters.accountLocation.value -notmatch "reference\(" -or
        $deploymentResource[0].properties.parameters.accountLocation.value -notmatch "'Full'"
    ) {
        $failures.Add("Template '$($templateFile.Name)' does not resolve the full existing Automation account resource before passing its location.")
    }
    if ($runbookResource.Count -ne 1 -or $runbookResource[0].properties.runtimeEnvironment -ne "[parameters('runtimeEnvironmentName')]") {
        $failures.Add("Template '$($templateFile.Name)' does not associate the runbook with the selected Runtime Environment.")
    }
    if ($runtimeResource.Count -ne 1 -or $runtimeResource[0].properties.runtime.version -ne "7.4") {
        $failures.Add("Template '$($templateFile.Name)' does not define PowerShell 7.4.")
    }
    if ($packageResource.Count -ne 1) {
        $failures.Add("Template '$($templateFile.Name)' does not provision Microsoft.Graph.Authentication.")
    }
    if ($template.parameters.createAutomationAccount.defaultValue -ne $false) {
        $failures.Add("Template '$($templateFile.Name)' must reuse an existing Automation account by default.")
    }
    if (-not $template.outputs.requiredGraphPermissions) {
        $failures.Add("Template '$($templateFile.Name)' does not expose required Graph permissions.")
    }
}

try {
    $registry = Get-Content -Path $RegistryPath -Raw | ConvertFrom-Json -Depth 50
    if (@($registry.templates.PSObject.Properties).Count -ne $eligibleScripts.Count) {
        $failures.Add("Template registry count does not match the eligible script count.")
    }
}
catch {
    $failures.Add("Template registry is invalid: $($_.Exception.Message)")
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}

Write-Output "Validated $($templateFiles.Count) Azure Automation templates."
