// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import { createIntuneMcpHandler } from "../src/server/mcp/intuneServer.ts";
import { makeRepository } from "./fixtures/scriptIndex.mjs";

async function sendJsonRpc(handler, message) {
  const response = await handler(
    new Request("http://localhost:3000/mcp", {
      method: "POST",
      headers: {
        Accept: "application/json, text/event-stream",
        "Content-Type": "application/json",
        "MCP-Protocol-Version": "2025-06-18",
      },
      body: JSON.stringify(message),
    }),
  );
  const body = await response.text();

  assert.equal(response.status, 200, body);
  if (response.headers.get("content-type")?.includes("text/event-stream")) {
    const data = body
      .split("\n")
      .find((line) => line.startsWith("data:"))
      ?.slice(5)
      .trim();
    assert.ok(data, body);
    return JSON.parse(data);
  }
  return JSON.parse(body);
}

const callTool = (handler, name, args, id = 10) =>
  sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id,
    method: "tools/call",
    params: { name, arguments: args },
  });

test("MCP server initializes as a stateless IntuneAutomation server", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);
  const response = await sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0.0" },
    },
  });

  assert.equal(response.result.serverInfo.name, "intuneautomation");
  assert.match(response.result.instructions, /read-only/i);
  assert.match(
    response.result.instructions,
    /never accesses the user's tenant/i,
  );
});

test("MCP server advertises the five bounded read-only tools", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);
  const response = await sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id: 2,
    method: "tools/list",
    params: {},
  });
  const tools = response.result.tools;

  assert.deepEqual(tools.map((tool) => tool.name).sort(), [
    "get_script",
    "get_script_authoring_guide",
    "get_script_metadata",
    "list_script_catalog",
    "search_scripts",
  ]);
  for (const tool of tools) {
    assert.equal(tool.annotations.readOnlyHint, true, tool.name);
    assert.equal(tool.annotations.destructiveHint, false, tool.name);
    assert.ok(tool.outputSchema, tool.name);
  }
  assert.equal(
    tools.find((tool) => tool.name === "search_scripts").inputSchema.properties
      .limit.maximum,
    25,
  );
  assert.equal(
    tools.find((tool) => tool.name === "get_script").inputSchema.properties
      .maxCharacters.maximum,
    30_000,
  );
});

test("search_scripts ranks, filters, paginates, and browses without a query", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);

  const ranked = await callTool(handler, "search_scripts", {
    query: "bitlocker",
  });
  assert.equal(ranked.result.structuredContent.matched, 1);
  assert.equal(
    ranked.result.structuredContent.scripts[0].id,
    "rotate-bitlocker-keys",
  );
  assert.equal(ranked.result.structuredContent.nextOffset, null);

  const browsed = await callTool(handler, "search_scripts", {});
  assert.equal(browsed.result.structuredContent.query, null);
  assert.equal(browsed.result.structuredContent.matched, 3);
  assert.equal(browsed.result.structuredContent.scripts.length, 3);

  const paged = await callTool(handler, "search_scripts", {
    limit: 1,
    offset: 1,
  });
  assert.equal(paged.result.structuredContent.scripts.length, 1);
  assert.equal(paged.result.structuredContent.nextOffset, 2);

  const filtered = await callTool(handler, "search_scripts", {
    category: "security",
  });
  assert.equal(filtered.result.structuredContent.matched, 1);
});

test("get_script_metadata returns runbook and azureDeploy details", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);
  const response = await callTool(handler, "get_script_metadata", {
    id: "get-device-report",
  });

  const script = response.result.structuredContent.script;
  assert.equal(script.runbook.eligible, true);
  assert.match(script.azureDeploy.deployUrl, /portal\.azure\.com/);
  assert.equal(script.parameters[0].name, "OutputPath");
});

test("get_script chunks source and follows nextStart to completion", async () => {
  const { calls, repository } = makeRepository({
    scriptSource: "x".repeat(2_500),
  });
  const handler = createIntuneMcpHandler(repository);

  const first = await callTool(handler, "get_script", {
    id: "get-device-report",
    maxCharacters: 1_000,
  });
  const firstResult = first.result.structuredContent;
  assert.equal(firstResult.content.length, 1_000);
  assert.equal(firstResult.totalCharacters, 2_500);
  assert.equal(firstResult.nextStart, 1_000);
  assert.equal(firstResult.truncated, true);

  const last = await callTool(handler, "get_script", {
    id: "get-device-report",
    start: 2_000,
    maxCharacters: 1_000,
  });
  assert.equal(last.result.structuredContent.content.length, 500);
  assert.equal(last.result.structuredContent.nextStart, null);
  assert.deepEqual(calls.getScriptSource, [
    "get-device-report",
    "get-device-report",
  ]);
});

test("get_script and get_script_metadata reject unknown ids as tool errors", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);

  for (const name of ["get_script", "get_script_metadata"]) {
    const response = await callTool(handler, name, { id: "missing-script" });
    assert.equal(response.result.isError, true, name);
    assert.match(response.result.content[0].text, /no script with id/i);
  }
});

test("get_script_authoring_guide returns the guide, date, and similar scripts", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);
  const response = await callTool(handler, "get_script_authoring_guide", {
    task: "rotate bitlocker keys",
  });

  const result = response.result.structuredContent;
  assert.match(result.today, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(result.guide, /Hard rules/);
  assert.equal(result.truncated, false);
  assert.equal(result.similarScripts[0].id, "rotate-bitlocker-keys");
});

test("list_script_catalog aggregates values and honors search", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);

  const permissions = await callTool(handler, "list_script_catalog", {
    kind: "permissions",
  });
  assert.equal(permissions.result.structuredContent.total, 2);

  const filtered = await callTool(handler, "list_script_catalog", {
    kind: "categories",
    search: "sec",
  });
  assert.deepEqual(filtered.result.structuredContent.items, [
    { value: "security", count: 1 },
  ]);
});

test("MCP server exposes prompts and resources for the catalog", async () => {
  const { repository } = makeRepository();
  const handler = createIntuneMcpHandler(repository);

  const prompts = await sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id: 20,
    method: "prompts/list",
    params: {},
  });
  assert.deepEqual(prompts.result.prompts.map((p) => p.name).sort(), [
    "find-intune-script",
    "write-intune-script",
  ]);

  const resources = await sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id: 21,
    method: "resources/list",
    params: {},
  });
  const uris = resources.result.resources.map((r) => r.uri);
  assert.ok(uris.includes("intune-scripts://index"));
  assert.ok(uris.includes("intune-scripts://authoring-guide"));

  const read = await sendJsonRpc(handler, {
    jsonrpc: "2.0",
    id: 22,
    method: "resources/read",
    params: { uri: "intune-script://get-device-report" },
  });
  assert.match(read.result.contents[0].text, /Write-Output 'ok'/);
});

test("tool failures do not leak upstream error details", async () => {
  const { repository } = makeRepository();
  repository.getIndex = async () => {
    throw new Error("secret upstream detail");
  };
  const handler = createIntuneMcpHandler(repository);

  const originalError = console.error;
  console.error = () => {};
  try {
    const response = await callTool(handler, "search_scripts", {
      query: "devices",
    });
    assert.equal(response.result.isError, true);
    assert.doesNotMatch(response.result.content[0].text, /secret upstream/);
    assert.match(response.result.content[0].text, /could not search/i);
  } finally {
    console.error = originalError;
  }
});
