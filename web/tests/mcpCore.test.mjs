// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCatalog,
  filterScripts,
  findScript,
  fullMetadata,
  nextBoundedOffset,
  paginateText,
  rankScripts,
  summarize,
} from "../src/server/mcp/core.ts";
import {
  fixtureIndex,
  fixtureScripts,
  makeScript,
} from "./fixtures/scriptIndex.mjs";

test("findScript matches case-insensitively and ignores a .ps1 suffix", () => {
  assert.equal(
    findScript(fixtureIndex, "Get-Device-Report.PS1")?.id,
    "get-device-report",
  );
  assert.equal(findScript(fixtureIndex, "does-not-exist"), undefined);
});

test("rankScripts requires every term to match and ranks title hits first", () => {
  const ranked = rankScripts(fixtureScripts, "bitlocker rotate");
  assert.equal(ranked[0].id, "rotate-bitlocker-keys");
  assert.equal(ranked.length, 1);

  assert.equal(rankScripts(fixtureScripts, "zzz-not-there").length, 0);
});

test("rankScripts without a query returns the catalog in stable id order", () => {
  const ranked = rankScripts(fixtureScripts);
  assert.deepEqual(
    ranked.map((s) => s.id),
    ["detect-stale-devices", "get-device-report", "rotate-bitlocker-keys"],
  );
});

test("filterScripts combines category, tag, platform, and permission filters", () => {
  assert.equal(
    filterScripts(fixtureScripts, { category: "Security" }).length,
    1,
  );
  assert.equal(filterScripts(fixtureScripts, { tag: "reporting" }).length, 1);
  assert.equal(filterScripts(fixtureScripts, { tag: "devices" }).length, 2);
  assert.equal(
    filterScripts(fixtureScripts, { platform: "windows" }).length,
    2,
  );
  assert.equal(
    filterScripts(fixtureScripts, { permission: "readwrite" }).length,
    1,
  );
  assert.equal(
    filterScripts(fixtureScripts, { category: "devices", tag: "Reporting" })[0]
      .id,
    "get-device-report",
  );
});

test("summarize surfaces runbook eligibility and normalizes empty platform", () => {
  const summary = summarize(fixtureScripts[2]);
  assert.equal(summary.platform, null);
  assert.equal(summary.runbookEligible, true);
  assert.equal(summarize(fixtureScripts[1]).runbookEligible, false);
});

test("fullMetadata carries runbook and azureDeploy and tolerates old indexes", () => {
  const meta = fullMetadata(fixtureScripts[0]);
  assert.equal(meta.runbook.eligible, true);
  assert.equal(meta.azureDeploy.supportsExistingAutomationAccount, true);

  const legacy = makeScript();
  delete legacy.runbook;
  delete legacy.azureDeploy;
  const legacyMeta = fullMetadata(legacy);
  assert.equal(legacyMeta.runbook, null);
  assert.equal(legacyMeta.azureDeploy, null);
});

test("buildCatalog aggregates values with counts and skips empties", () => {
  const categories = buildCatalog(fixtureIndex, "categories");
  assert.deepEqual(categories, [
    { value: "devices", count: 1 },
    { value: "remediation", count: 1 },
    { value: "security", count: 1 },
  ]);

  const platforms = buildCatalog(fixtureIndex, "platforms");
  assert.deepEqual(platforms, [{ value: "Windows", count: 2 }]);

  const tags = buildCatalog(fixtureIndex, "tags");
  assert.equal(tags.find((t) => t.value === "Devices")?.count, 2);
});

test("paginateText chunks and reports continuation offsets", () => {
  const first = paginateText("abcdefghij", 0, 4);
  assert.deepEqual(first, {
    value: "abcd",
    totalCharacters: 10,
    start: 0,
    nextStart: 4,
    truncated: true,
  });

  const last = paginateText("abcdefghij", 8, 4);
  assert.equal(last.value, "ij");
  assert.equal(last.nextStart, null);
  assert.equal(last.truncated, true);

  const whole = paginateText("abc", 0, 10);
  assert.equal(whole.truncated, false);
  assert.equal(whole.nextStart, null);
});

test("nextBoundedOffset stops at the cap and on exhausted results", () => {
  assert.equal(nextBoundedOffset(0, 10, true, 500), 10);
  assert.equal(nextBoundedOffset(0, 10, false, 500), null);
  assert.equal(nextBoundedOffset(0, 0, true, 500), null);
  assert.equal(nextBoundedOffset(495, 10, true, 500), null);
});
