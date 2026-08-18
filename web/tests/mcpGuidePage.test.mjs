// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import {
  createGuideAwareMcpGetHandler,
  createMcpGuideResponse,
  wantsMcpGuide,
} from "../src/server/mcp/guidePage.ts";

const get = (accept) =>
  new Request("http://localhost:3000/mcp", {
    method: "GET",
    headers: accept ? { Accept: accept } : {},
  });

test("wantsMcpGuide detects browsers but not MCP clients", () => {
  assert.equal(wantsMcpGuide(get("text/html,application/xhtml+xml")), true);
  assert.equal(wantsMcpGuide(get("text/event-stream")), false);
  assert.equal(
    wantsMcpGuide(get("application/json, text/event-stream")),
    false,
  );
  assert.equal(wantsMcpGuide(get()), false);
  assert.equal(
    wantsMcpGuide(new Request("http://localhost:3000/mcp", { method: "POST" })),
    false,
  );
});

test("guide-aware GET serves the guide to browsers and defers otherwise", async () => {
  let passedThrough = 0;
  const handler = createGuideAwareMcpGetHandler(async () => {
    passedThrough += 1;
    return new Response("mcp", { status: 200 });
  });

  const guide = await handler(get("text/html"));
  assert.match(await guide.text(), /IntuneAutomation MCP/);
  assert.equal(passedThrough, 0);

  await handler(get("text/event-stream"));
  assert.equal(passedThrough, 1);
});

test("guide response carries strict security and caching headers", async () => {
  const response = createMcpGuideResponse();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("Content-Type"), /text\/html/);
  assert.match(
    response.headers.get("Content-Security-Policy"),
    /default-src 'none'/,
  );
  assert.equal(response.headers.get("X-Content-Type-Options"), "nosniff");
  assert.equal(response.headers.get("Vary"), "Accept");

  const headOnly = createMcpGuideResponse(true);
  assert.equal(await headOnly.text(), "");
});

test("guide copy documents the endpoint, the five tools, and the trust model", async () => {
  const html = await createMcpGuideResponse().text();

  assert.match(html, /https:\/\/intuneautomation\.com\/mcp/);
  for (const tool of [
    "search_scripts",
    "get_script_metadata",
    "get_script",
    "get_script_authoring_guide",
    "list_script_catalog",
  ]) {
    assert.ok(html.includes(tool), tool);
  }
  assert.match(html, /never connects to your Microsoft tenant/i);
  assert.match(html, /claude mcp add --transport http/);
  assert.ok(!html.includes("—"), "guide page must not contain em dashes");
});
