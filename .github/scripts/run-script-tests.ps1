#!/usr/bin/env pwsh
# Runs all script quality checks and emits two JSON artifacts:
#   - testresults.json   legacy flat shape (kept for back-compat)
#   - script-tests.json  structured per-tier shape consumed by the website
#
# Test tiers (PowerShell scripts):
#   parse         AST parse must succeed
#   lint          PSScriptAnalyzer Error+Warning at the project rule set
#   metadata      Required comment-based help fields present
#   runbookReady  No interactive cmdlets in the script body
#   moduleDeps    Literal Import-Module names resolve to known modules
#
# Shell scripts:
#   shellcheck    ShellCheck issue count = 0
#
# Exit codes:
#   0  parse passed for all scripts (lint failures are reported but do not fail unless -GateOnLint)
#   1  one or more scripts failed parse, or -GateOnLint and at least one lint failure

param(
    [string]$ScriptsRoot = "scripts",
    [string]$RepoRoot    = (Get-Location).Path,
    [switch]$GateOnLint
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}
Import-Module PSScriptAnalyzer

$RequiredMetadataFields = @('TITLE', 'SYNOPSIS', 'DESCRIPTION', 'TAGS', 'PERMISSIONS', 'AUTHOR', 'VERSION')

# Patterns that cannot run in an Azure Automation runbook.
# Conservative list: only cmdlets that are unambiguously interactive.
$RunbookForbiddenPatterns = @(
    @{ Pattern = '(?<![\w-])Read-Host\b';    Reason = 'Read-Host is interactive; runbooks have no stdin.' }
    @{ Pattern = '(?<![\w-])Out-GridView\b'; Reason = 'Out-GridView requires a GUI; not available in runbooks.' }
)

# Known module name prefixes used by these scripts.
$KnownModulePrefixes = @(
    'Microsoft.Graph',
    'Az.',
    'ExchangeOnlineManagement',
    'MicrosoftTeams',
    'AzureAD'
)

$ExcludedLintRules = @(
    'PSUseBOMForUnicodeEncodedFile',
    'PSUseDeclaredVarsMoreThanAssignments',
    'PSUseShouldProcessForStateChangingFunctions',
    'PSAvoidUsingEmptyCatchBlock',
    'PSReviewUnusedParameter'
)

function Test-Parse {
    param([string]$Path)
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
    $list = @($errors)
    if ($list.Count -gt 0) {
        return @{
            status = 'fail'
            errors = @($list | ForEach-Object {
                @{ line = $_.Extent.StartLineNumber; message = $_.Message }
            })
        }
    }
    return @{ status = 'pass'; errors = @() }
}

function Test-Lint {
    param([string]$Path)
    $results = Invoke-ScriptAnalyzer -Path $Path -Severity Error,Warning -ExcludeRule $ExcludedLintRules
    $count = @($results).Count
    return @{
        status  = if ($count -eq 0) { 'pass' } else { 'fail' }
        issues  = $count
        details = @($results | ForEach-Object {
            @{ rule = $_.RuleName; line = $_.Line; severity = "$($_.Severity)"; message = $_.Message }
        })
    }
}

function Get-CommentBlock {
    param([string]$Content)
    if ($Content -match '(?s)<#(.*?)#>') { return $Matches[1] }
    return $null
}

function Test-Metadata {
    param([string]$Path)
    $content = Get-Content $Path -Raw
    $block = Get-CommentBlock $content
    if (-not $block) {
        return @{ status = 'fail'; missing = $RequiredMetadataFields }
    }
    $missing = @()
    foreach ($field in $RequiredMetadataFields) {
        if ($block -notmatch "(?m)^\s*\.$field\s*\r?\n\s*\S") {
            $missing += $field
        }
    }
    return @{
        status  = if ($missing.Count -eq 0) { 'pass' } else { 'fail' }
        missing = $missing
    }
}

function Remove-Comments {
    param([string]$Content)
    $stripped = $Content -replace '(?ms)<#.*?#>', ''
    $stripped = $stripped -replace '(?m)#.*$', ''
    return $stripped
}

$EnvDetectionPattern = '\$IsAutomationEnvironment|\$RunningInAzureAutomation|AZUREPS_HOST_ENVIRONMENT|Get-AutomationVariable'

function Test-RunbookReady {
    param([string]$Path)
    $lines = Get-Content $Path
    $hasEnvDetection = (Get-Content $Path -Raw) -match $EnvDetectionPattern

    $inBlockComment = $false
    $findings = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $work = $line

        # Handle entering/leaving a <# ... #> block on this line
        if ($inBlockComment) {
            if ($work -match '#>') {
                $work = ($work -split '#>',2)[1]
                $inBlockComment = $false
            } else { continue }
        }
        while ($work -match '<#') {
            $before = ($work -split '<#',2)[0]
            $after  = ($work -split '<#',2)[1]
            if ($after -match '#>') {
                $work = $before + ($after -split '#>',2)[1]
            } else {
                $work = $before
                $inBlockComment = $true
                break
            }
        }

        # Strip line comment portion (naive: first unquoted #)
        if ($work -match '^[^"'']*#') {
            $work = ($work -split '#',2)[0]
        }

        foreach ($p in $RunbookForbiddenPatterns) {
            if ($work -match $p.Pattern) {
                $findings += @{
                    line   = $i + 1
                    match  = $Matches[0]
                    reason = $p.Reason
                }
            }
        }
    }

    if ($findings.Count -eq 0) {
        return @{ status = 'pass'; findings = @(); guarded = $hasEnvDetection }
    }
    if ($hasEnvDetection) {
        # Script differentiates between local and runbook context; interactive
        # cmdlets are assumed to be gated behind that check. Report as info.
        return @{ status = 'pass'; findings = $findings; guarded = $true; note = 'Interactive patterns present but the script has environment detection.' }
    }
    return @{ status = 'fail'; findings = $findings; guarded = $false }
}

function Test-ModuleDeps {
    param([string]$Path)
    $content  = Get-Content $Path -Raw
    $stripped = Remove-Comments $content

    $literalImports = @()
    # Import-Module Foo    (literal name, not $var)
    foreach ($m in [regex]::Matches($stripped, '(?m)^\s*Import-Module\s+(?:-Name\s+)?([A-Za-z][A-Za-z0-9_.\-]+)')) {
        $literalImports += $m.Groups[1].Value
    }
    # using module Foo
    foreach ($m in [regex]::Matches($stripped, '(?m)^\s*using\s+module\s+([A-Za-z][A-Za-z0-9_.\-]+)')) {
        $literalImports += $m.Groups[1].Value
    }
    $literalImports = @($literalImports | Sort-Object -Unique)

    $unknown = @()
    foreach ($mod in $literalImports) {
        $ok = $false
        foreach ($p in $KnownModulePrefixes) {
            if ($mod -like "$p*" -or $mod -eq $p) { $ok = $true; break }
        }
        if (-not $ok) { $unknown += $mod }
    }
    return @{
        status  = if ($unknown.Count -eq 0) { 'pass' } else { 'fail' }
        modules = $literalImports
        unknown = $unknown
    }
}

$psFiles = Get-ChildItem -Path $ScriptsRoot -Recurse -Filter '*.ps1'
$shFiles = Get-ChildItem -Path $ScriptsRoot -Recurse -Filter '*.sh'

$nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$nowMDY = (Get-Date).ToString('MM-dd-yyyy')

$results    = [ordered]@{}
$flatLegacy = @()

foreach ($f in $psFiles) {
    $rel = $f.FullName.Replace($RepoRoot, '').TrimStart([IO.Path]::DirectorySeparatorChar).Replace('\','/')

    $parse        = Test-Parse        $f.FullName
    $lint         = if ($parse.status -eq 'pass') { Test-Lint $f.FullName } else { @{ status = 'skip' } }
    $metadata     = Test-Metadata     $f.FullName
    $runbookReady = Test-RunbookReady $f.FullName
    $moduleDeps   = Test-ModuleDeps   $f.FullName

    $tiers = [ordered]@{
        parse        = $parse
        lint         = $lint
        metadata     = $metadata
        runbookReady = $runbookReady
        moduleDeps   = $moduleDeps
    }
    $hasFail = ($tiers.Values | Where-Object { $_.status -eq 'fail' }).Count -gt 0
    $overall = if ($hasFail) { 'fail' } else { 'pass' }

    $results[$f.Name] = [ordered]@{
        path       = $rel
        type       = 'PowerShell'
        lastTested = $nowIso
        tests      = $tiers
        overall    = $overall
    }
    $flatLegacy += [PSCustomObject]@{
        filename  = $f.Name
        result    = if ($overall -eq 'pass') { 'pass' } else { 'not passed' }
        timestamp = $nowMDY
        type      = 'PowerShell'
    }
}

$shellcheckAvailable = $null -ne (Get-Command shellcheck -ErrorAction SilentlyContinue)
if ($shFiles.Count -gt 0 -and -not $shellcheckAvailable) {
    Write-Host "Warning: shellcheck not on PATH - shell scripts will be reported as 'skip'"
}

foreach ($f in $shFiles) {
    $rel = $f.FullName.Replace($RepoRoot, '').TrimStart([IO.Path]::DirectorySeparatorChar).Replace('\','/')

    if ($shellcheckAvailable) {
        $raw = & shellcheck -f json $f.FullName 2>&1 | Out-String
        try { $scResults = $raw | ConvertFrom-Json } catch { $scResults = @() }
        $issues = @($scResults).Count
        $status = if ($issues -eq 0) { 'pass' } else { 'fail' }
    } else {
        $scResults = @()
        $issues   = 0
        $status   = 'skip'
    }

    $results[$f.Name] = [ordered]@{
        path       = $rel
        type       = 'Shell'
        lastTested = $nowIso
        tests      = [ordered]@{
            shellcheck = @{
                status  = $status
                issues  = $issues
                details = @($scResults | ForEach-Object {
                    @{ rule = "SC$($_.code)"; line = $_.line; severity = "$($_.level)"; message = $_.message }
                })
            }
        }
        overall = $status
    }
    $flatLegacy += [PSCustomObject]@{
        filename  = $f.Name
        result    = if ($status -eq 'pass') { 'pass' } else { 'not passed' }
        timestamp = $nowMDY
        type      = 'Shell'
    }
}

# Emit artifacts
$structured = [ordered]@{
    generated = $nowIso
    scripts   = $results
}
$structured | ConvertTo-Json -Depth 10 | Set-Content 'script-tests.json' -Encoding UTF8
$flatLegacy  | ConvertTo-Json -Depth 3  | Set-Content 'testresults.json' -Encoding UTF8

# GitHub Actions summary
$psResults = @($results.Values | Where-Object type -eq 'PowerShell')
$shResults = @($results.Values | Where-Object type -eq 'Shell')

$total   = $results.Count
$passed  = ($results.Values | Where-Object overall -eq 'pass').Count
$failed  = ($results.Values | Where-Object overall -eq 'fail').Count
$skipped = ($results.Values | Where-Object overall -eq 'skip').Count

$summary = [System.Text.StringBuilder]::new()
[void]$summary.AppendLine('# Script test results')
[void]$summary.AppendLine('')
[void]$summary.AppendLine("Total: $total - Passed: $passed - Failed: $failed - Skipped: $skipped")
[void]$summary.AppendLine('')

if ($psResults.Count -gt 0) {
    [void]$summary.AppendLine('## PowerShell')
    [void]$summary.AppendLine('')
    [void]$summary.AppendLine('| Script | Parse | Lint | Metadata | Runbook-ready | Module deps | Overall |')
    [void]$summary.AppendLine('|---|---|---|---|---|---|---|')
    foreach ($name in $results.Keys) {
        $r = $results[$name]
        if ($r.type -ne 'PowerShell') { continue }
        $cells = @('parse','lint','metadata','runbookReady','moduleDeps') | ForEach-Object {
            $s = $r.tests.$_.status
            if ($s -eq 'pass') { 'pass' } elseif ($s -eq 'skip') { 'skip' } else { '**FAIL**' }
        }
        $overallCell = if ($r.overall -eq 'pass') { 'pass' } else { '**FAIL**' }
        [void]$summary.AppendLine("| $name | $($cells[0]) | $($cells[1]) | $($cells[2]) | $($cells[3]) | $($cells[4]) | $overallCell |")
    }
    [void]$summary.AppendLine('')
}

if ($shResults.Count -gt 0) {
    [void]$summary.AppendLine('## Shell')
    [void]$summary.AppendLine('')
    [void]$summary.AppendLine('| Script | ShellCheck | Overall |')
    [void]$summary.AppendLine('|---|---|---|')
    foreach ($name in $results.Keys) {
        $r = $results[$name]
        if ($r.type -ne 'Shell') { continue }
        $cell = if ($r.tests.shellcheck.status -eq 'pass') { 'pass' } else { "**FAIL** ($($r.tests.shellcheck.issues) issues)" }
        $overallCell = if ($r.overall -eq 'pass') { 'pass' } else { '**FAIL**' }
        [void]$summary.AppendLine("| $name | $cell | $overallCell |")
    }
    [void]$summary.AppendLine('')
}

# Failure detail blocks
$failingPs = @($results.Keys | Where-Object { $results[$_].type -eq 'PowerShell' -and $results[$_].overall -eq 'fail' })
if ($failingPs.Count -gt 0) {
    [void]$summary.AppendLine('## Failures')
    [void]$summary.AppendLine('')
    foreach ($name in $failingPs) {
        $r = $results[$name]
        [void]$summary.AppendLine("### $name")
        foreach ($tier in @('parse','lint','metadata','runbookReady','moduleDeps')) {
            $t = $r.tests.$tier
            if ($t.status -eq 'fail') {
                [void]$summary.AppendLine("- **$tier**:")
                switch ($tier) {
                    'parse'        { foreach ($e in $t.errors)   { [void]$summary.AppendLine("    - L$($e.line): $($e.message)") } }
                    'lint'         { foreach ($d in $t.details)  { [void]$summary.AppendLine("    - L$($d.line) [$($d.rule)]: $($d.message)") } }
                    'metadata'     { [void]$summary.AppendLine("    - Missing fields: $($t.missing -join ', ')") }
                    'runbookReady' { foreach ($f in $t.findings) { [void]$summary.AppendLine("    - L$($f.line) [$($f.match)]: $($f.reason)") } }
                    'moduleDeps'   { [void]$summary.AppendLine("    - Unknown modules: $($t.unknown -join ', ')") }
                }
            }
        }
        [void]$summary.AppendLine('')
    }
}

if ($env:GITHUB_STEP_SUMMARY) {
    $summary.ToString() | Set-Content $env:GITHUB_STEP_SUMMARY -Encoding UTF8
}

Write-Host ""
Write-Host "Test summary: $passed passed, $failed failed, $skipped skipped (of $total scripts)"

# Gating
$parseFails = ($results.Values | Where-Object { $_.type -eq 'PowerShell' -and $_.tests.parse.status -eq 'fail' }).Count
if ($parseFails -gt 0) {
    Write-Host "FAIL: $parseFails script(s) failed parse check - this blocks the workflow"
    exit 1
}

if ($GateOnLint) {
    $lintFails = ($results.Values | Where-Object { $_.type -eq 'PowerShell' -and $_.tests.lint.status -eq 'fail' }).Count
    if ($lintFails -gt 0) {
        Write-Host "FAIL: $lintFails script(s) failed lint check (GateOnLint enabled)"
        exit 1
    }
}

exit 0
