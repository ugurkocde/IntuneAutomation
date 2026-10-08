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

test("write calls the parser cannot pin down never produce excess warnings", () => {
  const rw = "DeviceManagementConfiguration.ReadWrite.All";
  const get = `$all = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"`;
  const cases = {
    "variable method": `$verb = if ($create) { "POST" } else { "PATCH" }
Invoke-MgGraphRequest -Method $verb -Uri "${BETA}/deviceManagement/deviceConfigurations/$id" -Body $b`,
    "colon method": `Invoke-MgGraphRequest -Method:PATCH -Uri "${BETA}/deviceManagement/deviceConfigurations/$id"`,
    "quoted splat keys": `$p = @{
    'Uri'    = "${BETA}/deviceManagement/deviceConfigurations/$id"
    'Method' = 'PATCH'
}
Invoke-MgGraphRequest @p`,
    "hash inside a string": `Invoke-MgGraphRequest -Uri "${BETA}/deviceManagement/deviceConfigurations/$id" -Body @{ displayName = "Baseline #2" } -Method PATCH`,
    "SDK verb outside the old list": `Disable-MgBetaDeviceManagementDeviceConfiguration -DeviceConfigurationId $id`,
    "conditional reassignment": `$uri = "${BETA}/deviceManagement/deviceConfigurations/$cid"
$c = Invoke-MgGraphRequest -Uri $uri
if ($x) { $uri = "${BETA}/deviceManagement/managedDevices/$id" }
Invoke-MgGraphRequest -Uri $uri -Method PATCH -Body $b`,
  };
  for (const [name, body] of Object.entries(cases)) {
    const analysis = analyzeGraphPermissions(
      script({ permissions: rw, body: `${get}\n${body}` }),
    );
    assert.deepEqual(analysis?.excess ?? [], [], name);
  }
});

test("a reused variable name in another function does not leak its method", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.Read.All, Mail.Send",
    body: `$Uri = "${BETA}/deviceManagement/deviceConfigurations"
$all = Get-MgGraphAllPage -Uri $Uri
function Send-Report {
    $Uri = "${BETA}/users/$SenderUPN/sendMail"
    Invoke-MgGraphRequest -Uri $Uri -Method POST -Body $mail
}`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(analysis.missing, []);
  assert.deepEqual(
    analysis.required.flatMap((r) => r.calls),
    ["GET /deviceManagement/deviceConfigurations"],
  );
});

test("a splat pointing at a $uri variable takes the splat's method", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$uri = "${BETA}/deviceManagement/deviceConfigurations/$id"
$p = @{
    Method = 'PATCH'
    Uri    = $uri
}
Invoke-MgGraphRequest @p`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, true);
  assert.deepEqual(
    analysis.required.flatMap((r) => r.calls),
    ["PATCH /deviceManagement/deviceConfigurations/{deviceConfigurationId}"],
  );
  assert.deepEqual(analysis.excess, []);
});

test("a write with no documented scopes suppresses excess and the pass", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$c = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"
Invoke-MgGraphRequest -Method POST -Uri "${BETA}/deviceManagement/virtualEndpoint/externalPartners/$pid/deployAgent"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, false);
  assert.deepEqual(analysis.excess, []);
  assert.ok(!ids(lintScript(code)).includes("permissions-least-privilege"));
});

test("a splat whose URI contains ${...} still finds the method", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$p = @{
    Uri    = "${BETA}/deviceManagement/deviceConfigurations/\${id}"
    Method = 'PATCH'
}
Invoke-MgGraphRequest @p`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, true);
  assert.deepEqual(
    analysis.required.flatMap((r) => r.calls),
    ["PATCH /deviceManagement/deviceConfigurations/{deviceConfigurationId}"],
  );
});

test("an unused declared Intune scope rules out the least-privilege pass", () => {
  const code = script({
    permissions:
      "DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.ReadWrite.All",
    body: `$c = Get-MgGraphAllPage -Uri "${BETA}/deviceManagement/deviceConfigurations"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.deepEqual(analysis.unused, [
    "DeviceManagementManagedDevices.ReadWrite.All",
  ]);
  assert.ok(!ids(lintScript(code)).includes("permissions-least-privilege"));
});

test("a splat closed on the same line as its last key finds the method", () => {
  const code = script({
    permissions: "DeviceManagementConfiguration.ReadWrite.All",
    body: `$p = @{
    Uri    = "${BETA}/deviceManagement/deviceConfigurations/\${id}"
    Method = 'PATCH' }
Invoke-MgGraphRequest @p
$c = Invoke-MgGraphRequest -Uri "${BETA}/deviceManagement/deviceConfigurations"`,
  });
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, true);
  assert.deepEqual(analysis.excess, []);
  assert.deepEqual(analysis.required.flatMap((r) => r.calls).sort(), [
    "GET /deviceManagement/deviceConfigurations",
    "PATCH /deviceManagement/deviceConfigurations/{deviceConfigurationId}",
  ]);
});

test("a helper that forwards its -Method parameter does not count as a write", () => {
  const helper = (extra) => `function Invoke-GraphRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST', 'PATCH')][string]$Method = 'GET'
    )
    Invoke-MgGraphRequest -Uri $Uri -Method $Method -ErrorAction Stop
}
$apps = Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps"
${extra}`;
  const readOnly = analyzeGraphPermissions(
    script({
      permissions: "DeviceManagementApps.ReadWrite.All",
      body: helper(""),
    }),
  );
  assert.equal(readOnly.writesResolved, true);
  assert.equal(
    readOnly.excess[0]?.replacement,
    "DeviceManagementApps.Read.All",
  );

  const named = analyzeGraphPermissions(
    script({
      permissions: "DeviceManagementApps.ReadWrite.All",
      body: helper(
        `Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Method PATCH`,
      ),
    }),
  );
  assert.deepEqual(named.excess, []);

  const positional = analyzeGraphPermissions(
    script({
      permissions: "DeviceManagementApps.ReadWrite.All",
      body: helper(
        `Invoke-GraphRequest "${BETA}/deviceAppManagement/mobileApps/$id" 'PATCH'`,
      ),
    }),
  );
  assert.equal(positional.writesResolved, false);
  assert.deepEqual(positional.excess, []);

  for (const call of [
    `Invoke-GraphRequest "${BETA}/deviceAppManagement/mobileApps/$id" PATCH`,
    `Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Meth PATCH`,
  ]) {
    const bare = analyzeGraphPermissions(
      script({
        permissions: "DeviceManagementApps.ReadWrite.All",
        body: helper(call),
      }),
    );
    assert.equal(bare.writesResolved, false, call);
  }
});

test("a script-level -Method parameter forwarded to Graph stays a possible write", () => {
  const code = script({
    permissions: "DeviceManagementApps.ReadWrite.All",
    body: `$apps = Get-MgGraphAllPage -Uri "${BETA}/deviceAppManagement/mobileApps"
Invoke-MgGraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Method $Method`,
  }).replace(
    "[CmdletBinding()]\nparam()",
    "[CmdletBinding()]\nparam([string]$Method = 'GET')",
  );
  const analysis = analyzeGraphPermissions(code);
  assert.equal(analysis.writesResolved, false);
  assert.deepEqual(analysis.excess, []);
});

test("a forwarded parameter with another name stays a possible write", () => {
  const code = script({
    permissions: "DeviceManagementApps.ReadWrite.All",
    body: `function Send-Graph {
    param([string]$Uri, [string]$Verb = 'GET')
    Invoke-MgGraphRequest -Uri $Uri -Method $Verb
}
$apps = Send-Graph -Uri "${BETA}/deviceAppManagement/mobileApps"`,
  });
  assert.equal(analyzeGraphPermissions(code).writesResolved, false);
});

test("the forwarder exemption is bound to the function that declares $Method", () => {
  const unrelated = script({
    permissions: "DeviceManagementApps.ReadWrite.All",
    body: `function Format-Row {
    param([string]$Method)
    "$Method"
}
$apps = Get-MgGraphAllPage -Uri "${BETA}/deviceAppManagement/mobileApps"
Invoke-MgGraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Method $Method`,
  });
  assert.equal(analyzeGraphPermissions(unrelated).writesResolved, false);

  const helper = (extra, dflt = "'GET'") => `function Invoke-GraphRequest {
    param([string]$Uri, [string]$Method = ${dflt})
    Invoke-MgGraphRequest -Uri $Uri -Method $Method
}
$apps = Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps"
${extra}`;
  const positionalVariable = script({
    permissions: "DeviceManagementApps.ReadWrite.All",
    body: helper(
      `$r = Invoke-GraphRequest "${BETA}/deviceAppManagement/mobileApps/$id" $env:GRAPH_METHOD`,
    ),
  });
  assert.equal(
    analyzeGraphPermissions(positionalVariable).writesResolved,
    false,
  );

  const envDefault = script({
    permissions: "DeviceManagementApps.ReadWrite.All",
    body: helper("", "$env:GRAPH_METHOD"),
  });
  assert.equal(analyzeGraphPermissions(envDefault).writesResolved, false);
});

test("an alias on $Method or a write verb under another name keeps the token", () => {
  const helper = (paramBlock, call) =>
    script({
      permissions: "DeviceManagementApps.ReadWrite.All",
      body: `function Invoke-GraphRequest {
    param(${paramBlock})
    Invoke-MgGraphRequest -Uri $Uri -Method $Method
}
$apps = Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps"
${call}`,
    });
  const aliased = helper(
    "[string]$Uri, [Alias('Verb')][string]$Method = 'GET'",
    `Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Verb PATCH`,
  );
  assert.equal(analyzeGraphPermissions(aliased).writesResolved, false);
  const otherName = helper(
    "[string]$Uri, [string]$Method = 'GET', [string]$Mode",
    `Invoke-GraphRequest -Uri "${BETA}/deviceAppManagement/mobileApps/$id" -Mode PATCH`,
  );
  assert.equal(analyzeGraphPermissions(otherName).writesResolved, false);
});
