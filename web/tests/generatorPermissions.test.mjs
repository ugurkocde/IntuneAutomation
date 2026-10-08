// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import { analyzeGraphPermissions } from "../src/lib/generator-graph-permissions.ts";
import { lintScript } from "../src/lib/generator-lint.ts";

const BETA = "https://graph.microsoft.com/beta";

function script({ permissions, body, scopes = permissions }) {
  return `<#
.TITLE
    Test
.SYNOPSIS
    Test
.DESCRIPTION
    Example: Invoke-MgGraphRequest -Method DELETE -Uri "${BETA}/deviceManagement/deviceConfigurations/x"
.TAGS
    Operational
.PLATFORM
    Windows
.PERMISSIONS
    ${permissions}
.AUTHOR
    AI Generated (IntuneAutomation.com)
.VERSION
    1.0
.CHANGELOG
    1.0 - Initial release
.LASTUPDATE
    ${new Date().toISOString().slice(0, 10)}
.EXAMPLE
    .\\test.ps1
.NOTES
    None
#>

[CmdletBinding()]
param()

$Scopes = @(${scopes
    .split(",")
    .map((s) => `"${s.trim()}"`)
    .join(", ")})
Connect-MgGraph -Scopes $Scopes -NoWelcome
${body}
`;
}

const ids = (result) => result.findings.map((f) => f.id);

test("GET-only script with ReadWrite is flagged as excess with the Read replacement", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$configs = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(analysis.excess, [
    {
      scope: "DeviceManagementConfiguration.ReadWrite.All",
      replacement: "DeviceManagementConfiguration.Read.All",
    },
  ]);
  assert.deepEqual(analysis.required, [
    {
      scope: "DeviceManagementConfiguration.Read.All",
      calls: ["GET /deviceManagement/deviceConfigurations"],
    },
  ]);
  const lint = lintScript(code);
  const finding = lint.findings.find(
    (f) =>
      f.id === "permissions-excess-DeviceManagementConfiguration.ReadWrite.All",
  );
  assert.equal(finding?.severity, "warn");
  assert.match(finding.detail, /DeviceManagementConfiguration\.Read\.All/);
});

test("the same script with a POST to that path is not flagged", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$configs = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"
Invoke-MgGraphRequest -Method POST -Uri "${BETA}/deviceManagement/deviceConfigurations" -Body $json`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(analysis.excess, []);
  assert.deepEqual(analysis.missing, []);
  assert.deepEqual(
    analysis.required.map((r) => r.scope),
    ["DeviceManagementConfiguration.ReadWrite.All"],
  );
  assert.ok(ids(lintScript(code)).includes("permissions-least-privilege"));
});

test("a $baseUri prefix and interpolated ids are resolved", () => {
  const code = script({
    permissions: "DeviceManagementManagedDevices.ReadWrite.All",
    body: `$baseUri = "${BETA}"
$devices = Get-MgGraphAllPage -Uri "$baseUri/deviceManagement/managedDevices?\`$filter=operatingSystem eq 'Windows'"
foreach ($d in $devices) {
    $detail = Invoke-MgGraphRequest -Method GET -Uri "$baseUri/deviceManagement/managedDevices/$($d.id)"
}`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(analysis.required.flatMap((r) => r.calls).sort(), [
    "GET /deviceManagement/managedDevices",
    "GET /deviceManagement/managedDevices/{managedDeviceId}",
  ]);
  assert.equal(
    analysis.excess[0]?.replacement,
    "DeviceManagementManagedDevices.Read.All",
  );
});

test("methods are read from splats, continuations and $uri call sites", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$params = @{
    Uri    = "${BETA}/deviceManagement/deviceConfigurations/$id"
    Method = 'PATCH'
}
Invoke-MgGraphRequest @params
$uri = "${BETA}/deviceManagement/deviceCompliancePolicies/$id"
Invoke-MgGraphRequest -Uri $uri \`
    -Method DELETE`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, true);
  assert.deepEqual(analysis.excess, []);
  assert.deepEqual(analysis.required.flatMap((r) => r.calls).sort(), [
    "DELETE /deviceManagement/deviceCompliancePolicies/{deviceCompliancePolicyId}",
    "PATCH /deviceManagement/deviceConfigurations/{deviceConfigurationId}",
  ]);
});

test("a call no declared scope covers is reported as missing", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.Read.All",
    body: `$devices = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/managedDevices"`,
  });
  const lint = lintScript(code);
  const finding = lint.findings.find((f) =>
    f.id.startsWith("permissions-missing-"),
  );
  assert.equal(finding?.severity, "warn");
  assert.match(finding.detail, /DeviceManagementManagedDevices\.Read\.All/);
});

test("a remote action that needs PrivilegedOperations is reported as missing", () => {
  const code = script({
    permissions: "DeviceManagementManagedDevices.ReadWrite.All",
    body: `Invoke-MgGraphRequest -Method POST -Uri "${BETA}/deviceManagement/managedDevices/$($d.id)/syncDevice"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(
    analysis.missing.map((c) => c.template),
    ["/deviceManagement/managedDevices/{managedDeviceId}/syncDevice"],
  );
  assert.deepEqual(analysis.excess, []);
});

test("unresolved writes suppress excess warnings", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$configs = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"
Invoke-MgGraphRequest -Method PATCH -Uri $targetUri -Body $json`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, false);
  assert.deepEqual(analysis.excess, []);
});

test("Mg SDK write cmdlets suppress excess warnings", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$configs = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"
Update-MgBetaDeviceManagementDeviceConfiguration -DeviceConfigurationId $id -BodyParameter $body`,
  });
  assert.deepEqual(analyzeGraphPermissions(code).excess, []);
});

test("no resolved Intune calls means no analysis and no permission warnings", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All, Group.Read.All",
    body: `$groups = Get-MgGraphAllPage -Uri "${BETA}/groups"
$x = Invoke-MgGraphRequest -Uri $someUri`,
  });
  assert.equal(analyzeGraphPermissions(code), null);
  const lint = lintScript(code);
  assert.equal(lint.permissions, null);
  assert.ok(
    !lint.findings.some(
      (f) =>
        f.id.startsWith("permissions-excess") ||
        f.id.startsWith("permissions-missing"),
    ),
  );
});

test("URIs in help text and comments are ignored", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `# Invoke-MgGraphRequest -Method POST -Uri "${BETA}/deviceManagement/deviceConfigurations"
$configs = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, true);
  assert.equal(analysis.excess.length, 1);
});

test("report actions posted with Read scopes count as reads", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$r = Invoke-MgGraphRequest -Method POST -Uri "${BETA}/deviceManagement/reports/getDeviceNonComplianceReport" -Body $body`,
  });
  assert.equal(
    analyzeGraphPermissions(code).excess[0]?.replacement,
    "DeviceManagementConfiguration.Read.All",
  );
});

test("Read next to ReadWrite of the same family keeps only what is needed", () => {
  const code = script({
    permissions:
      "DeviceManagementConfiguration.Read.All, DeviceManagementConfiguration.ReadWrite.All",
    body: `$c = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"
Invoke-MgGraphRequest -Method PATCH -Uri "${BETA}/deviceManagement/deviceConfigurations/$id" -Body $b`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(
    analysis.required.map((r) => r.scope),
    ["DeviceManagementConfiguration.ReadWrite.All"],
  );
  assert.deepEqual(analysis.excess, []);
});
