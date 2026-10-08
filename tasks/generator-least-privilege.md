# Generator: least-privilege Graph permissions

Goal: every generated script shows the minimum Graph permissions it needs, and the lint flags scopes that are broader than the script's calls require (for example `DeviceManagementConfiguration.ReadWrite.All` on a GET-only script).

## Findings
- The lint (`web/src/lib/generator-lint.ts`) only checked that `.PERMISSIONS` scopes exist. It never compared them to the calls the script makes.
- The system prompt asked for valid scopes but said nothing about least privilege.
- The upstream graph.pm index has the accepted scopes for each endpoint and method, but `sync-msgraph-data.mjs` dropped them.
  - The lists are alphabetical, not ordered by privilege, so ranking is our own (Read < ReadWrite).
- Directory endpoint data is unreliable: `GET /groups` lists only `Group-NestingSupport.ReadWrite.All`. Intune endpoints (`/deviceManagement`, `/deviceAppManagement`) are consistent.
- `GRAPH_ENDPOINTS` already ships to the client. The aligned scope-index array adds about 6 KB gzip, so lazy loading is not needed.

## Deliverables
- [x] The sync emits `GRAPH_SCOPE_LIST` plus `GRAPH_ENDPOINT_SCOPES`, an index array aligned with `GRAPH_ENDPOINTS`.
- [x] `generator-graph-permissions.ts` resolves calls from:
  - literal, `$base`-prefixed and interpolated URIs
  - `$uri` variables
  - methods given in the same statement, on backtick continuations, or in a splat
- [x] Lint findings, limited to Intune paths:
  - `permissions-excess-<scope>` (warn), with the replacement in `detail`
  - `permissions-missing-<method>-<template>` (warn)
  - `permissions-least-privilege` (pass)
- [x] The Inspector shows a "Minimum permissions" list: each scope next to the calls that need it.
- [x] The system prompt has a least-privilege rule.

## Acceptance criteria
1. A GET-only script on `/deviceManagement/deviceConfigurations` that declares `DeviceManagementConfiguration.ReadWrite.All` yields `permissions-excess`, suggesting `DeviceManagementConfiguration.Read.All`.
2. The same script with POST to that path yields no excess warning.
3. A script using `"$baseUri/deviceManagement/managedDevices"` with `$baseUri = "https://graph.microsoft.com/beta"` is resolved.
4. A call no declared scope covers yields `permissions-missing`.
5. Calls the analyzer cannot resolve produce no false excess warning; with zero resolved Intune calls the check is skipped.
6. The initial JS for `/generator` grows by less than 10 KB gzip.
7. At least 5 representative Intune endpoints work live with Lokka.
8. Unit tests cover 1 to 5 and pass. Typecheck passes. A separate reviewer agent signs off.

## Review
- 19 unit tests in `web/tests/generatorPermissions.test.mjs`; `npm test` passes 57 of 57; `tsc` is clean.
- 70 catalog scripts scanned: 56 make Intune calls, with 0 false excess and 0 false missing.
- Mutation check: Read changed to ReadWrite in 50 catalog scripts, 41 flagged. The rest have writes that can't be attributed, so they stay silent by design.
- Lokka app-only: GET deviceConfigurations, managedDevices, mobileApps and deviceCompliancePolicies, and POST reports/getDeviceNonComplianceReport, all returned 200.
  - The token holds both Read and ReadWrite, so this confirms the endpoints, not that Read alone is enough.
- Two reviewer-agent rounds plus CodeRabbit. All of these were found and fixed:
  - non-literal `-Method`
  - `#` inside strings
  - SDK write verbs
  - conditional `$uri` reassignment
  - splats with variable URIs
  - writes with no documented scopes
  - the `${}` splat boundary
  - unused declared scopes
- Not done: Playwright check of the Inspector. A live generation needs Turnstile and an Anthropic key.
