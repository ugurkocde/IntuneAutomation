// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import { isMcpProtocolRequest } from "../src/server/mcp/requestRouting.ts";

test("browser page views are not protocol traffic", () => {
  assert.equal(
    isMcpProtocolRequest("GET", "text/html,application/xhtml+xml"),
    false,
  );
  assert.equal(isMcpProtocolRequest("HEAD", "text/html"), false);
});

test("MCP client requests are protocol traffic", () => {
  assert.equal(isMcpProtocolRequest("POST", "application/json"), true);
  assert.equal(isMcpProtocolRequest("DELETE", null), true);
  assert.equal(isMcpProtocolRequest("OPTIONS", "*/*"), true);
  assert.equal(isMcpProtocolRequest("GET", "text/event-stream"), true);
  assert.equal(
    isMcpProtocolRequest("GET", "application/json, text/event-stream"),
    true,
  );
  assert.equal(isMcpProtocolRequest("GET", null), true);
  assert.equal(isMcpProtocolRequest("GET", "*/*"), true);
});

test("mixed accepts that include an MCP media type stay protocol traffic", () => {
  assert.equal(
    isMcpProtocolRequest("GET", "text/html, text/event-stream"),
    true,
  );
  assert.equal(
    isMcpProtocolRequest("GET", "text/html, application/json"),
    true,
  );
});
