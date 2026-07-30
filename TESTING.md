# Script Testing

Every PowerShell and shell script in this repository is automatically tested on every push to `main` and once per day. Test results are published to two artifacts in the repository root and are consumed by the website to display per-script trust badges.

## What gets tested

PowerShell scripts run through eight quality tiers. Shell scripts run through ShellCheck.

| Tier | What it checks | What it catches |
|---|---|---|
| **Parse** | The script can be parsed by the PowerShell AST parser. | Syntax errors, stray non-PowerShell content, malformed control flow. A failure here blocks the workflow. |
| **Lint** | PSScriptAnalyzer at Error + Warning severity, with the project's curated rule exclusions. | Common bug patterns, unused variables, unsafe constructs, missing error handling. |
| **Metadata** | Required comment-based help fields are present: `.TITLE`, `.SYNOPSIS`, `.DESCRIPTION`, `.TAGS`, `.PERMISSIONS`, `.AUTHOR`, `.VERSION`. | Missing documentation, undeclared permissions, scripts without version history. |
| **Runbook-ready** | No interactive cmdlets (`Read-Host`, `Out-GridView`) in code that would execute inside an Azure Automation runbook. Interactive cmdlets are allowed when the script also branches on `$IsAutomationEnvironment` / `$RunningInAzureAutomation`. | Scripts that prompt for input or open GUI windows, which silently break when deployed as a runbook. |
| **Runbook logging** | Script-scope status uses streams preserved in Automation job history. | Progress and final status that disappear after a job completes. |
| **Runbook contract** | Eligible scripts avoid parameter sets and switch parameters, use beta Graph endpoints, and keep local scopes aligned with `.PERMISSIONS`. | Azure import failures, portal parameter binding errors, API drift, and missing managed-identity permissions. |
| **Email safety** | Scripts, templates, and supporting documentation contain no email address literals. | Personal or example addresses accidentally shipped as defaults or copied into production. |
| **Module deps** | Static `Import-Module` references resolve to known module families (`Microsoft.Graph.*`, `Az.*`, `ExchangeOnlineManagement`, `MicrosoftTeams`, `AzureAD`). | Typos in module names, references to modules that don't exist in the Azure Automation runtime. |

Shell scripts run through one tier:

| Tier | What it checks |
|---|---|
| **ShellCheck** | Issue count from `shellcheck -f json` must be zero. |

## How it runs

The runner lives at [`.github/scripts/run-script-tests.ps1`](.github/scripts/run-script-tests.ps1) and is invoked by [`.github/workflows/script-analysis.yml`](.github/workflows/script-analysis.yml).

You can run it locally:

```powershell
pwsh .github/scripts/run-script-tests.ps1
```

Pass `-GateOnLint` to also fail the run on lint errors (defaults to off so the workflow only hard-fails on parse errors).

## Artifacts

Two JSON files are committed back to `main` after a successful run:

- **`testresults.json`** - flat shape, one row per script, with overall pass/fail. Kept for backwards compatibility.
- **`script-tests.json`** - structured per-tier results, used by the website to render trust badges:

  ```json
  {
    "generated": "2026-05-11T03:11:29Z",
    "scripts": {
      "get-maa-compliance-report.ps1": {
        "path": "scripts/compliance/get-maa-compliance-report.ps1",
        "type": "PowerShell",
        "lastTested": "2026-05-11T03:11:29Z",
        "tests": {
          "parse":        { "status": "pass" },
          "lint":         { "status": "pass", "issues": 0 },
          "metadata":     { "status": "pass" },
          "runbookReady": { "status": "pass" },
          "runbookLogging": { "status": "pass" },
          "runbookContract": { "status": "pass" },
          "emailSafety": { "status": "pass" },
          "moduleDeps":   { "status": "pass" }
        },
        "overall": "pass"
      }
    }
  }
  ```

Each tier status is one of `pass`, `fail`, or `skip`. The overall status is `pass` only if no tier is `fail`.

## What is not tested

The CI does **not** run scripts against a live tenant because the repository has no tenant credentials or safe, disposable fixtures. The repository does validate the generated ARM templates, runbook import contract, parameter types, endpoint version, permission declarations, logging, and email safety. Live smoke testing remains a separate certification step for safe read-only scripts.

## Adding a new script

To make sure a new script passes all tiers from the start:

1. Start from one of the templates in [`templates/`](templates/).
2. Fill in all required metadata fields in the comment-based help block.
3. If the script has any interactive prompts (`Read-Host`, etc.), wrap them in `if (-not $IsAutomationEnvironment) { ... }` so they never run inside a runbook.
4. Only `Import-Module` from the families listed in [`run-script-tests.ps1`](.github/scripts/run-script-tests.ps1) (`$KnownModulePrefixes`). If you need a new module family, add it to the allowlist in the same PR as the script.
5. Run the test runner locally before opening a PR.
