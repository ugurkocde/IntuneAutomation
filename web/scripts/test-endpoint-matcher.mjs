#!/usr/bin/env node
// Smoke test for the Graph endpoint matcher and lint integration.
// Run with: node scripts/test-endpoint-matcher.mjs

import { register } from "node:module";
import { pathToFileURL } from "node:url";

// Use tsx if available, else require the file post-build. Easiest: import the
// JSON-shaped GRAPH_ENDPOINTS directly via a dynamic eval of the .ts file
// content stripped of types. The data module is auto-generated, type-free at
// runtime, so we can read it as JS with a regex strip.
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_FILE = resolve(HERE, "..", "src", "lib", "generator-graph-data.ts");

const src = readFileSync(DATA_FILE, "utf8");
const m = src.match(/export const GRAPH_ENDPOINTS: readonly string\[\] = (\[[\s\S]*?\]);/);
if (!m) {
  console.error("GRAPH_ENDPOINTS not found in data file");
  process.exit(1);
}
const GRAPH_ENDPOINTS = JSON.parse(m[1]);
console.log(`Loaded ${GRAPH_ENDPOINTS.length} endpoints`);

// Inline a minimal copy of the matcher logic from generator-graph-endpoints.ts.
function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
function templateToRegex(path) {
  const pattern = path
    .split("/")
    .map((seg) =>
      seg.includes("{") && seg.includes("}") ? "[^/?#]+" : escapeRegex(seg),
    )
    .join("/");
  return new RegExp("^" + pattern + "$");
}
const byMethod = new Map();
for (const entry of GRAPH_ENDPOINTS) {
  const sp = entry.indexOf(" ");
  const method = entry.slice(0, sp);
  const path = entry.slice(sp + 1);
  let list = byMethod.get(method);
  if (!list) {
    list = [];
    byMethod.set(method, list);
  }
  list.push({ template: path, regex: templateToRegex(path) });
}
function stripVersion(path) {
  return path.replace(/^\/(v1\.0|beta)(?=\/)/, "");
}
function isKnown(method, path) {
  const list = byMethod.get(method.toUpperCase());
  if (!list) return false;
  const normalized = stripVersion(path);
  return list.some((e) => e.regex.test(normalized));
}

// Test cases — pairs of [method, path, expectedMatch].
const cases = [
  // Known canonical Intune/Graph endpoints (should ALL match)
  ["GET", "/v1.0/deviceManagement/managedDevices", true],
  ["GET", "/beta/deviceManagement/managedDevices/abc-123", true],
  ["GET", "/v1.0/users", true],
  ["GET", "/v1.0/users/jane@contoso.com", true],
  ["GET", "/v1.0/groups", true],
  ["GET", "/beta/identity/conditionalAccess/policies", true],
  ["GET", "/v1.0/deviceManagement/roleDefinitions", true],
  ["GET", "/v1.0/deviceManagement/roleAssignments", true],
  ["POST", "/v1.0/users/abc/microsoft.graph.retire", false], // wrong action shape
  // Known-bad / hallucinated
  ["GET", "/v1.0/deviceManagement/totallyFakeEndpoint", false],
  ["GET", "/v1.0/intune/managedDevices", false], // wrong product prefix
  ["POST", "/v1.0/users/abc/sendInvite", false], // misnamed
];

let pass = 0;
let fail = 0;
for (const [method, path, expected] of cases) {
  const actual = isKnown(method, path);
  const ok = actual === expected;
  if (ok) pass++;
  else fail++;
  console.log(
    `${ok ? "PASS" : "FAIL"} ${method} ${path} -> ${actual} (expected ${expected})`,
  );
}
console.log(`\n${pass} passed, ${fail} failed`);

// Integration test: feed a script body containing both real and fake Graph
// URIs to the extraction + check pipeline.
function stripQueryAndFragment(url) {
  const q = url.indexOf("?");
  const f = url.indexOf("#");
  let end = url.length;
  if (q >= 0) end = Math.min(end, q);
  if (f >= 0) end = Math.min(end, f);
  return url.slice(0, end);
}
function extractUsages(body) {
  const usages = [];
  const re =
    /["']https:\/\/graph\.microsoft\.com\/(?:v1\.0|beta)\/[^"'\s]*["']/g;
  for (const m of body.matchAll(re)) {
    const raw = m[0].slice(1, -1);
    const url = stripQueryAndFragment(raw);
    const path = url.replace(/^https:\/\/graph\.microsoft\.com/, "");
    if (path.includes("$")) continue;
    const idx = m.index ?? 0;
    const lineStart = body.lastIndexOf("\n", idx - 1) + 1;
    const nextNL = body.indexOf("\n", idx);
    const lineEnd = nextNL === -1 ? body.length : nextNL;
    const line = body.slice(lineStart, lineEnd);
    const mm = line.match(/-Method\s+["']?(GET|POST|PUT|PATCH|DELETE)["']?/i);
    const method = (mm?.[1] ?? "GET").toUpperCase();
    usages.push({ method, path });
  }
  return usages;
}

const scriptSample = `
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?\`$select=id,deviceName"
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceManagement/notARealThing" -Method POST
Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/users?\`$select=id,displayName"
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/abc-123/members"
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users/\$id"
`;
const usages = extractUsages(scriptSample);
console.log(`\nIntegration: extracted ${usages.length} URIs from sample script`);
let unknownCount = 0;
for (const u of usages) {
  const ok = isKnown(u.method, u.path);
  if (!ok) unknownCount++;
  console.log(`  ${u.method} ${u.path} -> ${ok ? "known" : "UNKNOWN"}`);
}
console.log(`Expected 1 unknown ("/deviceManagement/notARealThing"), got ${unknownCount}`);
const integrationOk = unknownCount === 1;
process.exit(fail === 0 && integrationOk ? 0 : 1);
