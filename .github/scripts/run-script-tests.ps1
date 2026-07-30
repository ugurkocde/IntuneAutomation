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
#   runbookLogging Script-scope status messages use a stream captured by Azure Automation
#   runbookContract Azure-import-safe parameters, beta Graph endpoints, and declared scopes
#   emailSafety   No hardcoded mailbox or recipient addresses
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

function Test-RunbookLogging {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors
    )

    if (@($errors).Count -gt 0) {
        return @{ status = 'skip'; findings = @() }
    }

    $findings = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Write-Information'
        }, $true) | Where-Object {
            $parent = $_.Parent
            $insideFunction = $false

            while ($parent) {
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    $insideFunction = $true
                    break
                }
                $parent = $parent.Parent
            }

            -not $insideFunction
        } | ForEach-Object {
            @{
                line = $_.Extent.StartLineNumber
                reason = 'Write-Information at script scope is not stored in published Azure Automation job history. Use Write-Output for script progress, outcomes, and summaries.'
            }
        }
    )

    return @{
        status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
        findings = $findings
    }
}

function Get-RunbookEligibility {
    param([string]$Path)

    $relativePath = $Path.Replace($RepoRoot, '').TrimStart([IO.Path]::DirectorySeparatorChar).Replace('\','/')
    if ($relativePath -match '^scripts/remediation/') {
        return @{ eligible = $false; reason = 'Intune remediation scripts are endpoint scripts, not Azure Automation runbooks.' }
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $block = Get-CommentBlock $content
    if ($block -match '(?im)^\s*\.EXECUTION\s*\r?\n\s*LocalOnly\s*$') {
        return @{ eligible = $false; reason = 'Script metadata declares LocalOnly execution.' }
    }

    return @{ eligible = $true; reason = '' }
}

function Test-RunbookContract {
    param([string]$Path)

    $eligibility = Get-RunbookEligibility -Path $Path
    if (-not $eligibility.eligible) {
        return @{ status = 'skip'; eligible = $false; findings = @(); reason = $eligibility.reason }
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) {
        return @{ status = 'skip'; eligible = $true; findings = @() }
    }

    $content = Get-Content -Path $Path -Raw
    $stripped = Remove-Comments -Content $content
    $findings = @()

    if ($ast.ParamBlock -and $ast.ParamBlock.Extent.Text -match '\bParameterSetName\s*=|\bDefaultParameterSetName\s*=') {
        $findings += @{
            line = $ast.ParamBlock.Extent.StartLineNumber
            reason = 'Azure Automation does not support parameter sets in imported runbooks. Use optional inputs and explicit mutual-exclusion validation.'
        }
    }

    if ($ast.ParamBlock) {
        foreach ($parameter in $ast.ParamBlock.Parameters) {
            if ($parameter.StaticType -eq [System.Management.Automation.SwitchParameter]) {
                $findings += @{
                    line = $parameter.Extent.StartLineNumber
                    reason = "Public runbook parameter '$($parameter.Name.VariablePath.UserPath)' uses [switch]. Azure portal values bind as strings, so use a validated string and normalize it."
                }
            }
        }
    }

    if (
        $stripped -match '\$forceModuleInstallRaw\s*=\s*\[string\]\$ForceModuleInstall' -and
        $stripped -notmatch 'Remove-Variable\s+-Name\s+ForceModuleInstall'
    ) {
        $findings += @{
            line = 1
            reason = 'ForceModuleInstall is declared as [string] but normalized in place. Remove the typed parameter variable before assigning a Boolean, otherwise PowerShell keeps the value as a string and [bool] binding fails.'
        }
    }

    if (
        $stripped -match '\$runbookBooleanRaw\s*=\s*\[string\]\(Get-Variable\s+-Name\s+\$runbookBooleanParameter' -and
        $stripped -notmatch 'Remove-Variable\s+-Name\s+\$runbookBooleanParameter'
    ) {
        $findings += @{
            line = 1
            reason = 'Portal-safe Boolean parameters are normalized in place while still type-constrained as [string]. Remove each typed parameter variable before assigning the normalized Boolean value.'
        }
    }

    foreach ($match in [regex]::Matches($stripped, 'https://graph\.microsoft\.com/v1\.0', 'IgnoreCase')) {
        $line = ($stripped.Substring(0, $match.Index) -split "`n").Count
        $findings += @{
            line = $line
            reason = 'Repository Graph calls must use the beta endpoint so local and runbook execution use the same API contract.'
        }
    }

    if ($stripped -match '(?s)Write-Warning\s+"Error fetching data[^"]*".{0,120}\bbreak\b') {
        $findings += @{
            line = 1
            reason = 'A Graph paging helper converts a required fetch failure into partial or empty data. Throw after retry exhaustion so the runbook cannot report false success.'
        }
    }

    if ($stripped -match 'if\s*\(\s*\$[Rr]esponse\.value\s*\)') {
        $findings += @{
            line = 1
            reason = 'A Graph paging helper tests collection truthiness. Empty value arrays must still be treated as collections, otherwise the response envelope is reported as one result.'
        }
    }

    if ($stripped -match 'if\s*\(\s*@\(\$(?:DeviceNames|DeviceIds)\)\.Count\s+-gt\s+0\s*\)') {
        $findings += @{
            line = 1
            reason = 'Azure Automation can bind an omitted string-array parameter as an array containing an empty string. Remove blank elements before target-count validation.'
        }
    }

    $metadataBlock = Get-CommentBlock $content
    $declaredPermissions = @()
    if ($metadataBlock -match '(?im)^\s*\.PERMISSIONS\s*\r?\n\s*(.+)$') {
        $declaredPermissions = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $usedPermissions = @(
        [regex]::Matches($stripped, "['`"]([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)['`"]") |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -match '\.(Read|ReadBasic|ReadWrite|PrivilegedOperations)\.All$|^Mail\.Send$' } |
            Sort-Object -Unique
    )
    foreach ($permission in $usedPermissions) {
        if ($permission -notin $declaredPermissions) {
            $findings += @{
                line = 1
                reason = "Microsoft Graph permission '$permission' is used for local authentication but is missing from .PERMISSIONS metadata."
            }
        }
    }

    if ($stripped -match '/sendMail\b' -and 'Mail.Send' -notin $declaredPermissions) {
        $findings += @{ line = 1; reason = 'The script calls sendMail but .PERMISSIONS does not declare Mail.Send.' }
    }

    return @{
        status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
        eligible = $true
        findings = $findings
    }
}

function Test-EmailSafety {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    $findings = @(
        [regex]::Matches(
            $content,
            '(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b'
        ) | Where-Object {
            $_.Value -notmatch '(?i)@odata\.'
        } | ForEach-Object {
            @{
                line = ($content.Substring(0, $_.Index) -split "`n").Count
                match = $_.Value
                reason = 'Email addresses must be supplied at runtime or through external configuration, including examples and templates.'
            }
        }
    )

    return @{
        status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
        findings = $findings
    }
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
$templateFiles = Get-ChildItem -Path (Join-Path $RepoRoot 'templates') -Filter '*.ps1'

$templateFailures = @()
foreach ($templateFile in $templateFiles) {
    $templateParse = Test-Parse $templateFile.FullName
    if ($templateParse.status -eq 'fail') {
        $templateFailures += @{
            path = $templateFile.FullName
            reason = 'PowerShell parse failure'
        }
        continue
    }

    $templateLogging = Test-RunbookLogging $templateFile.FullName
    foreach ($finding in $templateLogging.findings) {
        $templateFailures += @{
            path = $templateFile.FullName
            line = $finding.line
            reason = $finding.reason
        }
    }

    $templateEmailSafety = Test-EmailSafety $templateFile.FullName
    foreach ($finding in $templateEmailSafety.findings) {
        $templateFailures += @{
            path = $templateFile.FullName
            line = $finding.line
            reason = $finding.reason
        }
    }
}

$emailSafetyFiles = @(
    Get-ChildItem -Path $RepoRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[/\\](?:\.git|node_modules|build|dist|coverage)[/\\]' -and
            (
                [string]::IsNullOrEmpty($_.Extension) -or
                $_.Extension -in @(
                    '.config', '.cs', '.css', '.csv', '.env', '.example', '.html',
                    '.ini', '.js', '.json', '.jsx', '.md', '.mdx', '.mjs', '.ps1',
                    '.sh', '.svg', '.toml', '.ts', '.tsx', '.txt', '.xml', '.yaml',
                    '.yml'
                )
            )
        }
)
foreach ($emailSafetyFile in $emailSafetyFiles) {
    $emailSafety = Test-EmailSafety $emailSafetyFile.FullName
    foreach ($finding in $emailSafety.findings) {
        $templateFailures += @{
            path = $emailSafetyFile.FullName
            line = $finding.line
            reason = $finding.reason
        }
    }
}

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
    $runbookLogging = if ($parse.status -eq 'pass') { Test-RunbookLogging $f.FullName } else { @{ status = 'skip'; findings = @() } }
    $runbookContract = if ($parse.status -eq 'pass') { Test-RunbookContract $f.FullName } else { @{ status = 'skip'; findings = @() } }
    $emailSafety = Test-EmailSafety $f.FullName
    $moduleDeps   = Test-ModuleDeps   $f.FullName

    $tiers = [ordered]@{
        parse        = $parse
        lint         = $lint
        metadata     = $metadata
        runbookReady = $runbookReady
        runbookLogging = $runbookLogging
        runbookContract = $runbookContract
        emailSafety = $emailSafety
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
    [void]$summary.AppendLine('| Script | Parse | Lint | Metadata | Runbook-ready | Logging | Contract | Email safety | Module deps | Overall |')
    [void]$summary.AppendLine('|---|---|---|---|---|---|---|---|---|---|')
    foreach ($name in $results.Keys) {
        $r = $results[$name]
        if ($r.type -ne 'PowerShell') { continue }
        $cells = @('parse','lint','metadata','runbookReady','runbookLogging','runbookContract','emailSafety','moduleDeps') | ForEach-Object {
            $s = $r.tests.$_.status
            if ($s -eq 'pass') { 'pass' } elseif ($s -eq 'skip') { 'skip' } else { '**FAIL**' }
        }
        $overallCell = if ($r.overall -eq 'pass') { 'pass' } else { '**FAIL**' }
        [void]$summary.AppendLine("| $name | $($cells[0]) | $($cells[1]) | $($cells[2]) | $($cells[3]) | $($cells[4]) | $($cells[5]) | $($cells[6]) | $($cells[7]) | $overallCell |")
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
        foreach ($tier in @('parse','lint','metadata','runbookReady','runbookLogging','runbookContract','emailSafety','moduleDeps')) {
            $t = $r.tests.$tier
            if ($t.status -eq 'fail') {
                [void]$summary.AppendLine("- **$tier**:")
                switch ($tier) {
                    'parse'        { foreach ($e in $t.errors)   { [void]$summary.AppendLine("    - L$($e.line): $($e.message)") } }
                    'lint'         { foreach ($d in $t.details)  { [void]$summary.AppendLine("    - L$($d.line) [$($d.rule)]: $($d.message)") } }
                    'metadata'     { [void]$summary.AppendLine("    - Missing fields: $($t.missing -join ', ')") }
                    'runbookReady' { foreach ($f in $t.findings) { [void]$summary.AppendLine("    - L$($f.line) [$($f.match)]: $($f.reason)") } }
                    'runbookLogging' { foreach ($f in $t.findings) { [void]$summary.AppendLine("    - L$($f.line): $($f.reason)") } }
                    'runbookContract' { foreach ($f in $t.findings) { [void]$summary.AppendLine("    - L$($f.line): $($f.reason)") } }
                    'emailSafety' { foreach ($f in $t.findings) { [void]$summary.AppendLine("    - L$($f.line) [$($f.match)]: $($f.reason)") } }
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
if ($templateFailures.Count -gt 0) {
    foreach ($failure in $templateFailures) {
        Write-Output "FAIL: $($failure.path):$($failure.line) $($failure.reason)"
    }
    exit 1
}

$parseFails = ($results.Values | Where-Object { $_.type -eq 'PowerShell' -and $_.tests.parse.status -eq 'fail' }).Count
if ($parseFails -gt 0) {
    Write-Host "FAIL: $parseFails script(s) failed parse check - this blocks the workflow"
    exit 1
}

$loggingFails = ($results.Values | Where-Object {
    $_.type -eq 'PowerShell' -and $_.tests.runbookLogging.status -eq 'fail'
}).Count
if ($loggingFails -gt 0) {
    Write-Output "FAIL: $loggingFails script(s) use Write-Information at script scope"
    exit 1
}

$contractFails = ($results.Values | Where-Object {
    $_.type -eq 'PowerShell' -and $_.tests.runbookContract.status -eq 'fail'
}).Count
if ($contractFails -gt 0) {
    Write-Output "FAIL: $contractFails runbook-eligible script(s) violate the Azure Automation contract"
    exit 1
}

$emailSafetyFails = ($results.Values | Where-Object {
    $_.type -eq 'PowerShell' -and $_.tests.emailSafety.status -eq 'fail'
}).Count
if ($emailSafetyFails -gt 0) {
    Write-Output "FAIL: $emailSafetyFails script(s) contain hardcoded email address literals"
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
