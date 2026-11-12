// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import test from "node:test";

import {
  GENERAL_MESSAGES,
  TENUVAULT_COMPANION_URL,
  TOPIC_MESSAGES,
  generalMessageFor,
  scriptTopicMessage,
  tenuvaultMessageUrl,
  writesConfiguration,
} from "../src/lib/tenuvault.ts";
import { analyzeGraphPermissions } from "../src/lib/generator-graph-permissions.ts";

test("message links carry source, medium, placement and message", () => {
  assert.equal(
    tenuvaultMessageUrl(GENERAL_MESSAGES.restore, "script_page"),
    "https://www.tenuvault.com/intune-restore?utm_source=intuneautomation.com&utm_medium=house_ad&utm_campaign=script_page&utm_content=restore_v1",
  );
  assert.equal(
    tenuvaultMessageUrl(TOPIC_MESSAGES.config_write, "generator"),
    "https://www.tenuvault.com/intune-backup?utm_source=intuneautomation.com&utm_medium=house_ad&utm_campaign=generator&utm_content=config_write_v1",
  );
});

test("the companion card is tagged as a listing", () => {
  assert.equal(
    TENUVAULT_COMPANION_URL,
    "https://www.tenuvault.com/?utm_source=intuneautomation.com&utm_medium=listing&utm_campaign=companion",
  );
});

test("only the backup, restore and drift scripts get a topic message", () => {
  const dir = "scripts/configuration";
  assert.equal(
    scriptTopicMessage(`${dir}/backup-intune-configuration.ps1`)?.id,
    "backup_script",
  );
  assert.equal(
    scriptTopicMessage(`${dir}/restore-intune-configuration.ps1`)?.id,
    "restore_script",
  );
  assert.equal(
    scriptTopicMessage(`${dir}/get-policy-drift-report.ps1`)?.id,
    "drift_script",
  );
  assert.equal(
    scriptTopicMessage("scripts/compliance/get-device-compliance-report.ps1"),
    undefined,
  );
  // A script elsewhere with the same file name, a missing path and a name
  // from the object prototype do not match.
  assert.equal(
    scriptTopicMessage("scripts/apps/backup-intune-configuration.ps1"),
    undefined,
  );
  assert.equal(scriptTopicMessage(undefined), undefined);
  assert.equal(scriptTopicMessage("constructor"), undefined);
});

test("the mapped script files exist", () => {
  for (const file of [
    "backup-intune-configuration.ps1",
    "restore-intune-configuration.ps1",
    "get-policy-drift-report.ps1",
  ]) {
    assert.ok(
      existsSync(
        new URL(`../../scripts/configuration/${file}`, import.meta.url),
      ),
      file,
    );
  }
});

const permissions = (required, extra = {}) => ({
  required: required.map((scope) => ({ scope, calls: [] })),
  declared: required,
  writesResolved: true,
  ...extra,
});

test("write scopes for policies, scripts and roles count as a configuration change", () => {
  for (const scope of [
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementScripts.ReadWrite.All",
    "DeviceManagementRBAC.ReadWrite.All",
  ]) {
    assert.equal(writesConfiguration(permissions([scope])), true, scope);
  }
});

test("read scopes and writes a backup cannot undo do not count", () => {
  assert.equal(
    writesConfiguration(
      permissions([
        "DeviceManagementConfiguration.Read.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementApps.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
      ]),
    ),
    false,
  );
  assert.equal(writesConfiguration(permissions([])), false);
  assert.equal(writesConfiguration(null), false);
  assert.equal(writesConfiguration(undefined), false);
});

test("an unresolved write falls back to the scopes the script declares", () => {
  const unresolved = {
    required: [{ scope: "DeviceManagementConfiguration.Read.All", calls: [] }],
    declared: ["DeviceManagementConfiguration.ReadWrite.All"],
    writesResolved: false,
  };
  assert.equal(writesConfiguration(unresolved), true);
  // With every write resolved, an over-declared scope alone does not count.
  assert.equal(
    writesConfiguration({ ...unresolved, writesResolved: true }),
    false,
  );
});

test("the generator's own analysis feeds the check", () => {
  const BETA = "https://graph.microsoft.com/beta";
  const header = (scope) => `<#
.TITLE
    Test
.SYNOPSIS
    Test
.DESCRIPTION
    Test
.TAGS
    Operational
.PLATFORM
    Windows
.PERMISSIONS
    ${scope}
.AUTHOR
    AI Generated (IntuneAutomation.com)
.VERSION
    1.0
.CHANGELOG
    1.0 - Initial release
.LASTUPDATE
    2026-01-01
.EXAMPLE
    .\\test.ps1
.NOTES
    None
#>

[CmdletBinding()]
param()

$Scopes = @("${scope}")
Connect-MgGraph -Scopes $Scopes -NoWelcome
`;
  const patch =
    header("DeviceManagementConfiguration.ReadWrite.All") +
    `Invoke-MgGraphRequest -Method PATCH -Uri "${BETA}/deviceManagement/deviceCompliancePolicies/x" -Body $body\n`;
  assert.equal(writesConfiguration(analyzeGraphPermissions(patch)), true);

  const read =
    header("DeviceManagementManagedDevices.Read.All") +
    `$d = Invoke-MgGraphRequest -Method GET -Uri "${BETA}/deviceManagement/managedDevices"\n`;
  assert.equal(writesConfiguration(analyzeGraphPermissions(read)), false);
});

test("the general messages take turns by calendar day in Berlin", () => {
  const at = (iso) => generalMessageFor(new Date(iso)).id;
  const first = at("2026-11-12T12:00:00Z");
  const second = at("2026-11-13T12:00:00Z");
  assert.notEqual(first, second);
  assert.deepEqual([first, second].sort(), ["free", "restore"]);
  assert.equal(at("2026-11-14T12:00:00Z"), first);
  // The whole Berlin day shows one message.
  assert.equal(at("2026-11-11T23:30:00Z"), first);
  assert.equal(at("2026-11-12T22:59:00Z"), first);
  // Berlin is one hour ahead of UTC in winter, so the day turns at 23:00 UTC.
  assert.equal(at("2026-11-12T23:00:00Z"), second);
});

test("the turns continue across a month with 31 days", () => {
  const at = (iso) => generalMessageFor(new Date(iso)).id;
  assert.notEqual(at("2026-10-31T12:00:00Z"), at("2026-11-01T12:00:00Z"));
  assert.notEqual(at("2026-12-31T12:00:00Z"), at("2027-01-01T12:00:00Z"));
});

test("over two weeks each message is shown on every weekday", () => {
  const seen = { restore: new Set(), free: new Set() };
  for (let day = 0; day < 14; day++) {
    const date = new Date(Date.UTC(2026, 10, 9 + day, 12));
    seen[generalMessageFor(date).id].add(date.getUTCDay());
  }
  assert.equal(seen.restore.size, 7);
  assert.equal(seen.free.size, 7);
});

test("the turns continue across daylight saving changes", () => {
  const at = (iso) => generalMessageFor(new Date(iso)).id;
  // Clocks change in Berlin on 29 March and 25 October 2026.
  for (const [before, after] of [
    ["2026-03-28T12:00:00Z", "2026-03-29T12:00:00Z"],
    ["2026-03-29T12:00:00Z", "2026-03-30T12:00:00Z"],
    ["2026-10-24T12:00:00Z", "2026-10-25T12:00:00Z"],
    ["2026-10-25T12:00:00Z", "2026-10-26T12:00:00Z"],
  ]) {
    assert.notEqual(at(before), at(after), `${before} and ${after}`);
  }
  assert.ok(["restore", "free"].includes(at("2026-10-25T00:30:00Z")));
});

test("dates before 1970 and unusable dates still yield a message", () => {
  const ids = ["restore", "free"];
  assert.ok(
    ids.includes(generalMessageFor(new Date("1969-12-31T12:00:00Z")).id),
  );
  assert.ok(
    ids.includes(generalMessageFor(new Date("1950-06-15T12:00:00Z")).id),
  );
  assert.ok(ids.includes(generalMessageFor(new Date("not a date")).id));
});

test("every message has a versioned tag", () => {
  for (const message of [
    ...Object.values(GENERAL_MESSAGES),
    ...Object.values(TOPIC_MESSAGES),
  ]) {
    assert.equal(message.tag, `${message.id}_v1`);
  }
});
