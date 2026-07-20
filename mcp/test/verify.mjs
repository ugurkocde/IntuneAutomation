#!/usr/bin/env node
/**
 * End-to-end verification: launches the built server over stdio with a real MCP
 * client, exercises every tool and resource, and asserts the responses.
 *
 * Run: npm run build && npm run verify
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { readFileSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const serverEntry = join(here, "..", "dist", "index.js");
// Count from the committed index in this checkout. The drift guard keeps this
// file in sync with scripts/, so it is the source of truth for the fallback
// test even when the primary fetch serves an older index from the main branch
// (which happens on any branch that adds or removes scripts).
const committedIndexCount = JSON.parse(
  readFileSync(join(here, "..", "data", "scripts-index.json"), "utf8"),
).scripts.length;

let passed = 0;
let failed = 0;
function check(name, cond, detail = "") {
  if (cond) {
    passed++;
    console.log(`  PASS  ${name}`);
  } else {
    failed++;
    console.log(`  FAIL  ${name}${detail ? "  -> " + detail : ""}`);
  }
}

function parse(result) {
  const text = result.content.find((c) => c.type === "text")?.text ?? "{}";
  return JSON.parse(text);
}

const transport = new StdioClientTransport({ command: process.execPath, args: [serverEntry] });
const client = new Client({ name: "verify-client", version: "1.0.0" });
await client.connect(transport);

let primaryTotal = 0; // catalog size from the primary server, reused by the fallback test

try {
  // Tools registered
  const tools = (await client.listTools()).tools.map((t) => t.name).sort();
  check("5 tools registered", tools.length === 5, tools.join(","));
  for (const t of ["get_script", "get_script_authoring_guide", "get_script_metadata", "list_scripts", "search_scripts"]) {
    check(`tool present: ${t}`, tools.includes(t));
  }

  // list_scripts (no filter)
  const all = parse(await client.callTool({ name: "list_scripts", arguments: {} }));
  primaryTotal = all.total;
  // Derive expected values from the index itself so adding scripts never breaks CI.
  check("list_scripts returns the whole catalog", all.matched === all.total && all.total > 0, `matched=${all.matched} total=${all.total}`);
  check("list_scripts reports categories", all.categories.length > 0, all.categories.join(","));
  // Pre-publish the index isn't on main yet, so the server correctly falls back
  // to the bundled copy. Post-push this becomes "github". Either is valid.
  check("list_scripts index source is valid", ["github", "github (stale cache)", "bundled"].includes(all.source), `source=${all.source}`);
  if (all.source === "bundled") {
    console.log("  NOTE  index served from bundled fallback (mcp/data/scripts-index.json not yet on GitHub main); becomes 'github' after push");
  }

  // list_scripts filtered by category — derive an existing category and expected count.
  const someCategory = all.categories[0];
  const expectedInCategory = all.scripts.filter((s) => s.category === someCategory).length;
  const inCategory = parse(await client.callTool({ name: "list_scripts", arguments: { category: someCategory } }));
  check(
    `list_scripts category=${someCategory} returns only that category`,
    inCategory.scripts.every((s) => s.category === someCategory) && inCategory.matched === expectedInCategory && expectedInCategory > 0,
    `matched=${inCategory.matched} expected=${expectedInCategory}`
  );

  // list_scripts filtered by tag
  const reporting = parse(await client.callTool({ name: "list_scripts", arguments: { tag: "reporting" } }));
  check("list_scripts tag=reporting returns results", reporting.matched > 0, `matched=${reporting.matched}`);

  // search_scripts
  const search = parse(await client.callTool({ name: "search_scripts", arguments: { query: "application inventory report", limit: 5 } }));
  check("search finds app inventory script first", search.scripts[0]?.id === "get-application-inventory-report", search.scripts[0]?.id);

  const compliance = parse(await client.callTool({ name: "search_scripts", arguments: { query: "compliance" } }));
  check("search 'compliance' returns matches", compliance.matched > 0, `matched=${compliance.matched}`);

  const nonsense = parse(await client.callTool({ name: "search_scripts", arguments: { query: "zzzzqqqq-nomatch" } }));
  check("search nonsense returns 0", nonsense.matched === 0, `matched=${nonsense.matched}`);

  // get_script_metadata
  const meta = parse(await client.callTool({ name: "get_script_metadata", arguments: { id: "get-application-inventory-report" } }));
  check("metadata has permissions", Array.isArray(meta.permissions) && meta.permissions.length > 0);
  check("metadata has parameters", Array.isArray(meta.parameters) && meta.parameters.length > 0);
  check("metadata has examples", Array.isArray(meta.examples) && meta.examples.length > 0);
  check("metadata has minRole", typeof meta.minRole === "string" && meta.minRole.length > 0, meta.minRole);

  // get_script_metadata accepts .ps1 suffix and is case-insensitive
  const meta2 = parse(await client.callTool({ name: "get_script_metadata", arguments: { id: "GET-APPLICATION-INVENTORY-REPORT.ps1" } }));
  check("metadata id is case/suffix tolerant", meta2.id === "get-application-inventory-report");

  // get_script_metadata unknown id -> error
  const bad = await client.callTool({ name: "get_script_metadata", arguments: { id: "does-not-exist" } });
  check("unknown id returns isError", bad.isError === true);

  // get_script (fetches real source from GitHub raw)
  const full = await client.callTool({ name: "get_script", arguments: { id: "get-application-inventory-report" } });
  const sourceBlock = full.content.find((c) => c.type === "text" && c.text.includes("```powershell"));
  check("get_script returns powershell source", !!sourceBlock && sourceBlock.text.includes("CmdletBinding"), "no source block");

  // Prompts
  const prompts = (await client.listPrompts()).prompts.map((p) => p.name).sort();
  check("2 prompts registered", prompts.length === 2, prompts.join(","));
  check("prompt present: find-intune-script", prompts.includes("find-intune-script"));
  check("prompt present: write-intune-script", prompts.includes("write-intune-script"));
  const writePrompt = await client.getPrompt({ name: "write-intune-script", arguments: { task: "export compliance policies" } });
  check("write prompt references authoring guide", writePrompt.messages[0].content.text.includes("get_script_authoring_guide"));

  // rawUrl reachability smoke (one sampled script)
  const sample = all.scripts[0];
  const rawRes = await fetch(sample.githubUrl.replace("github.com", "raw.githubusercontent.com").replace("/blob/", "/"));
  check(`sampled script rawUrl reachable (${sample.id})`, rawRes.ok, `HTTP ${rawRes.status}`);

  // get_script_authoring_guide
  const guide = await client.callTool({ name: "get_script_authoring_guide", arguments: {} });
  const guideText = guide.content.map((c) => c.text).join("\n");
  check("authoring guide includes hard rules", guideText.includes("Hard rules"));
  check("authoring guide includes canonical structure", guideText.includes("Canonical structure"));
  check("authoring guide injects today's date", /Use today's date for the \.LASTUPDATE field: \d{4}-\d{2}-\d{2}/.test(guideText));

  const guideWithTask = await client.callTool({ name: "get_script_authoring_guide", arguments: { task: "application inventory report for managed devices" } });
  const guideTaskText = guideWithTask.content.map((c) => c.text).join("\n");
  check("authoring guide with task surfaces similar scripts", guideTaskText.includes("get-application-inventory-report"));

  // Resources
  const resources = await client.listResources();
  check("static index resource present", resources.resources.some((r) => r.uri === "intune-scripts://index"));
  check("authoring-guide resource present", resources.resources.some((r) => r.uri === "intune-scripts://authoring-guide"));

  const guideRes = await client.readResource({ uri: "intune-scripts://authoring-guide" });
  check("authoring-guide resource readable", guideRes.contents[0].text.includes("Hard rules"));

  const tmpl = await client.listResourceTemplates();
  check("script resource template present", tmpl.resourceTemplates.some((r) => r.uriTemplate === "intune-script://{id}"));

  const idxRes = await client.readResource({ uri: "intune-scripts://index" });
  const idxJson = JSON.parse(idxRes.contents[0].text);
  check("index resource matches catalog count", idxJson.count === all.total, `count=${idxJson.count} total=${all.total}`);

  const srcRes = await client.readResource({ uri: "intune-script://get-application-inventory-report" });
  check("script resource returns source", srcRes.contents[0].text.includes("CmdletBinding"));
} finally {
  await client.close();
}

// Bundled-fallback path: point the server at a nonexistent repo so the remote
// index fetch fails and it must serve the copy bundled in the package.
{
  const fbTransport = new StdioClientTransport({
    command: process.execPath,
    args: [serverEntry],
    env: { ...process.env, INTUNE_MCP_REPO: "ugurkocde/__intune_mcp_does_not_exist__" },
  });
  const fbClient = new Client({ name: "verify-fallback-client", version: "1.0.0" });
  await fbClient.connect(fbTransport);
  try {
    const fb = parse(await fbClient.callTool({ name: "list_scripts", arguments: {} }));
    check(
      "bundled fallback serves the committed index",
      fb.matched === committedIndexCount && committedIndexCount > 0,
      `fb=${fb.matched} committed=${committedIndexCount} primary=${primaryTotal}`,
    );
    check("bundled fallback reports source=bundled", fb.source === "bundled", `source=${fb.source}`);
  } finally {
    await fbClient.close();
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
