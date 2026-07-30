# Azure Automation runbook certification

This repository applies a runbook contract to every PowerShell script that is eligible for Azure Automation.

## Current contract

- Generated templates reuse an existing Automation account by default.
- Existing accounts keep their current region and managed identity configuration.
- Runbooks use a PowerShell 7.4 Runtime Environment with `Microsoft.Graph.Authentication`.
- Public boolean parameters accept `true`, `false`, `1`, `0`, `$true`, or `$false` as strings and normalize them before execution.
- Parameter sets are not allowed because Azure Automation rejects them during import.
- Microsoft Graph calls use the beta endpoint consistently.
- Required paging failures terminate the job instead of returning partial or empty data.
- Every script declares its Graph application permissions in `.PERMISSIONS`.
- Email recipients and sender mailboxes are always runtime inputs. No email address is stored anywhere in the repository.
- The website contact address is optional external configuration through `NEXT_PUBLIC_SUPPORT_EMAIL`.

## Template eligibility

The template generator excludes scripts that are not cloud runbooks:

- All Intune Remediations under `scripts/remediation`
- `backup-bitlocker-keys-to-keyvault.ps1`
- `backup-intune-configuration.ps1`
- `restore-intune-configuration.ps1`
- `get-policy-drift-report.ps1`
- `collect-device-diagnostics.ps1`

The last four depend on local folders or downloaded binary artifacts. Publishing them as cloud runbooks would create files only inside a temporary Automation sandbox.

CSV-driven device scripts support a runbook-native alternative:

- `add-devices-to-groups-from-csv.ps1` accepts `CsvContent`
- `rename-devices-from-csv.ps1` accepts `CsvContent`

Specify either the local `CsvPath` or `CsvContent`, never both.

## Permission corrections

- BitLocker inventory uses `BitlockerKey.ReadBasic.All` because it does not retrieve recovery secrets.
- FileVault inventory uses `DeviceManagementManagedDevices.PrivilegedOperations.All` and `DeviceManagementManagedDevices.Read.All`.
- Device sync, restart, and wipe use `DeviceManagementManagedDevices.PrivilegedOperations.All` plus read access.
- Group-targeted scripts use `GroupMember.Read.All` for group lookup and membership.
- Apple token checks use `DeviceManagementServiceConfig.Read.All`.
- Notification scripts that send mail declare `Mail.Send` and require `SenderUPN` plus recipient input at runtime.

## Automated checks

The CI pipeline blocks:

- PowerShell parse failures
- unsupported runbook parameter sets
- public switch parameters
- versioned `v1.0` Graph URLs
- undeclared local authentication scopes
- swallowed paging failures
- script-scope logging that is missing from Automation job history
- hardcoded email address literals anywhere in the repository
- templates that do not support existing accounts or PowerShell 7.4
- templates generated for remediation or local-only scripts

## Live certification result

On 2026-07-30, all 52 eligible scripts were imported and published in the
`aa-intuneautomation-demo` Automation account with the PowerShell 7.4 runtime.
Representative parameters were supplied through the Automation job API and every
latest certification job reached `Completed`.

- 52 of 52 latest jobs completed.
- 0 jobs contained an Error stream.
- 51 jobs contained no Error or Warning stream.
- `get-firewall-and-asr-status` produced one intentional tenant-health warning:
  four Windows devices had no assigned Firewall or ASR policy and were running
  on local defaults.
- Restart, sync, and wipe were exercised only in dry-run mode against an empty
  test group.
- Notification sender and recipient values were supplied only as runtime job
  parameters.
- The 22 permissions declared across all 69 scripts matched the 22 Microsoft
  Graph application roles granted to the Automation account managed identity.

Earlier failed and warning-producing certification attempts remain in Azure job
history for troubleshooting. Certification status is based on the latest job for
each `verify-*` runbook.

## Automation boundary

Static CI cannot safely execute tenant writes without a disposable tenant,
federated GitHub identity, test Automation account, and controlled fixtures. A
future automated live-certification workflow should import the current commit,
bind representative parameters, run read-only scripts, inspect every job stream,
and clean up only resources created by that workflow. Destructive scripts must
remain manual and use explicit test targets.

Durable file reports also require an agreed storage design and Azure RBAC model. Until that is implemented, cloud runbooks should rely on job output or notification delivery, and local-only scripts remain excluded from deployment templates.
