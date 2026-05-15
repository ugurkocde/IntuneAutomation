#!/usr/bin/env node
// Smoke test for the unsafe-date-parse lint heuristic. Inlines the same logic
// the lint uses so we can exercise it against representative PS snippets
// without booting Next/TS.

function escapeForRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function findUnsafeDateParses(scriptBody) {
  const code = scriptBody;
  const matches = Array.from(
    code.matchAll(
      /\[DateTime\]::Parse\(\s*\$(?:_|\w+)\.(\w*[Dd]ate[Tt]ime\w*|\w*[Tt]ime)\s*\)/g,
    ),
  );
  return matches.filter((m) => {
    const idx = m.index ?? 0;
    const fieldName = m[1] ?? "";
    const lineStart = code.lastIndexOf("\n", idx) + 1;
    const lineEnd = code.indexOf("\n", idx);
    const line = code.slice(lineStart, lineEnd === -1 ? undefined : lineEnd);
    if (/\bif\s*\(|\?\s*\{|-and|\$null\s+-ne/.test(line)) return false;
    const before = code.slice(Math.max(0, idx - 300), idx);
    const fieldGuard = new RegExp(
      `\\b(if|while)\\s*\\([^)]*\\b${escapeForRegex(fieldName)}\\b`,
      "i",
    );
    if (fieldGuard.test(before)) return false;
    if (/\btry\s*\{/.test(before)) return false;
    return true;
  });
}

const cases = [
  {
    name: "bare unguarded (should flag)",
    body: `$lastSync = [DateTime]::Parse($device.lastSyncDateTime)`,
    expectUnsafe: 1,
  },
  {
    name: "bare with downstream null check (should still flag — dead code)",
    body: `$lastSync = [DateTime]::Parse($device.lastSyncDateTime)
if ($null -eq $lastSync) { return }`,
    expectUnsafe: 1,
  },
  {
    name: "inline ternary same line (should NOT flag)",
    body: `$lastSync = if ($device.lastSyncDateTime) { [DateTime]::Parse($device.lastSyncDateTime) } else { $null }`,
    expectUnsafe: 0,
  },
  {
    name: "multi-line if-block guard on same field (should NOT flag)",
    body: `if ($device.lastSyncDateTime) {
    $lastSync = [DateTime]::Parse($device.lastSyncDateTime)
} else {
    $lastSync = $null
}`,
    expectUnsafe: 0,
  },
  {
    name: "try/catch wrap (should NOT flag)",
    body: `try {
    $lastSync = [DateTime]::Parse($device.lastSyncDateTime)
} catch {
    $lastSync = $null
}`,
    expectUnsafe: 0,
  },
  {
    name: "if on different field (should still flag — wrong field guarded)",
    body: `if ($device.deviceName) {
    $lastSync = [DateTime]::Parse($device.lastSyncDateTime)
}`,
    expectUnsafe: 1,
  },
  {
    name: "$null -ne same-line guard (should NOT flag)",
    body: `if ($null -ne $device.lastSyncDateTime) { $lastSync = [DateTime]::Parse($device.lastSyncDateTime) }`,
    expectUnsafe: 0,
  },
  {
    name: "multiple unguarded parses (should flag both)",
    body: `$a = [DateTime]::Parse($device.enrolledDateTime)
$b = [DateTime]::Parse($device.lastSyncDateTime)`,
    expectUnsafe: 2,
  },
  {
    name: "multiple parses, second guarded by enclosing try (should flag only first)",
    body: `$a = [DateTime]::Parse($device.enrolledDateTime)
try {
    $b = [DateTime]::Parse($device.lastSyncDateTime)
} catch { $b = $null }`,
    expectUnsafe: 1,
  },
];

let pass = 0;
let fail = 0;
for (const c of cases) {
  const got = findUnsafeDateParses(c.body).length;
  const ok = got === c.expectUnsafe;
  if (ok) pass++;
  else fail++;
  console.log(`${ok ? "PASS" : "FAIL"} ${c.name} → got=${got} expected=${c.expectUnsafe}`);
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
