# Generator: least-privilege Graph permissions

Goal: every generated script shows the minimum Graph permissions it needs, and the lint flags scopes that are broader than the script's calls require (for example `DeviceManagementConfiguration.ReadWrite.All` on a GET-only script).

## Findings
- The lint (`web/src/lib/generator-lint.ts`) only checks that `.PERMISSIONS` scopes exist. It never compares them to the calls the script makes.
- The system prompt asks for valid scopes but says nothing about least privilege.
- The upstream graph.pm index has the accepted scopes for each endpoint and method, but `sync-msgraph-data.mjs` drops them.
  - Lists are alphabetical. They are not ordered least to most privileged, so ranking has to be our own (Read < ReadWrite, same resource family).
- The full map is about 760 KB. Restricted to Intune, directory, users and groups it is about 544 KB, which is too big for the client lint bundle as-is.
- `extractGraphEndpointUsages` skips URIs containing `$`. Most generated scripts build URIs as `"$baseUri/deviceManagement/..."`, so that extractor needs extending.

## Deliverables
- [ ] The sync emits a compact `METHOD /path -> accepted scopes` map (scope-id dictionary, Graph areas the generator targets), loaded lazily so the initial generator bundle does not grow.
- [ ] The endpoint extractor resolves a `$base`/`$uri` prefix, reads `-Method` from splatted or multi-line calls, and returns the matched template.
- [ ] Lint computes the required scopes from the matched calls and compares them with `.PERMISSIONS` and `Connect-MgGraph -Scopes`/`$Scopes`:
  - `permissions-excess` (warn): a declared ReadWrite scope where the Read sibling satisfies every call. The `detail` names the replacement, so the existing Fix flow corrects it.
  - `permissions-missing` (warn): a call that no declared scope covers.
  - `permissions-least` (pass): the declared scopes are the minimum.
- [ ] The Inspector shows a "Minimum permissions" list: each scope next to the calls that need it.
- [ ] The system prompt adds a least-privilege rule: Read.All for GET-only work, ReadWrite only for resources the script writes, and `.PERMISSIONS` must equal `$Scopes`.

## Acceptance criteria
1. A GET-only script on `/deviceManagement/deviceConfigurations` that declares `DeviceManagementConfiguration.ReadWrite.All` yields `permissions-excess`, suggesting `DeviceManagementConfiguration.Read.All`.
2. The same script with POST to that path yields no excess warning.
3. A script using `"$baseUri/deviceManagement/managedDevices"` with `$baseUri = "https://graph.microsoft.com/beta"` is resolved and analysed.
4. A call with no declared scope covering it yields `permissions-missing`.
5. Scripts whose calls cannot be resolved produce no false excess warning; with zero resolved calls the check is skipped.
6. The initial JS for `/generator` grows by less than 10 KB gzip. The map loads lazily.
7. Required scopes for at least 5 representative Intune endpoints match Microsoft Learn and are confirmed live with Lokka (GET with Read.All succeeds).
8. Unit tests cover 1 to 5 and pass. Typecheck and build pass. A separate reviewer agent signs off.
