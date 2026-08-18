// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import { createGuardedMcpHandler } from "../src/server/mcp/requestGuards.ts";

const okHandler = async () =>
  new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

const post = (headers = {}, body = "{}") =>
  new Request("http://localhost:3000/mcp", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body,
  });

test("guard rejects unknown browser origins with a JSON-RPC error", async () => {
  const guarded = createGuardedMcpHandler(okHandler);
  const response = await guarded(post({ Origin: "https://evil.example.com" }));

  assert.equal(response.status, 403);
  const body = await response.json();
  assert.equal(body.jsonrpc, "2.0");
  assert.match(body.error.message, /origin/i);
});

test("guard allows the site's own origins and non-browser clients", async () => {
  const guarded = createGuardedMcpHandler(okHandler);

  const own = await guarded(post({ Origin: "https://intuneautomation.com" }));
  assert.equal(own.status, 200);
  assert.equal(
    own.headers.get("Access-Control-Allow-Origin"),
    "https://intuneautomation.com",
  );

  const cli = await guarded(post());
  assert.equal(cli.status, 200);
  assert.equal(cli.headers.get("Cache-Control"), "no-store");
  assert.equal(cli.headers.get("X-Content-Type-Options"), "nosniff");
});

test("guard answers CORS preflight without consuming rate limit", async () => {
  const guarded = createGuardedMcpHandler(okHandler, {
    requestsPerMinute: 1,
  });

  const preflight = await guarded(
    new Request("http://localhost:3000/mcp", {
      method: "OPTIONS",
      headers: { Origin: "https://intuneautomation.com" },
    }),
  );
  assert.equal(preflight.status, 204);
  assert.match(
    preflight.headers.get("Access-Control-Allow-Headers"),
    /MCP-Protocol-Version/,
  );

  // The rate-limit map is process-global, so pin a unique client IP.
  assert.equal(
    (await guarded(post({ "x-forwarded-for": "10.0.9.9" }))).status,
    200,
  );
});

test("guard rate limits per client IP and sets Retry-After", async () => {
  let clock = 1_000_000;
  const guarded = createGuardedMcpHandler(okHandler, {
    requestsPerMinute: 2,
    now: () => clock,
  });
  const from = (ip) => post({ "x-forwarded-for": ip });

  assert.equal((await guarded(from("10.0.0.1"))).status, 200);
  assert.equal((await guarded(from("10.0.0.1"))).status, 200);

  const limited = await guarded(from("10.0.0.1"));
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers.get("Retry-After")) >= 1);

  assert.equal((await guarded(from("10.0.0.2"))).status, 200);

  clock += 61_000;
  assert.equal((await guarded(from("10.0.0.1"))).status, 200);
});

test("guard rejects oversized bodies via header and via stream", async () => {
  const guarded = createGuardedMcpHandler(okHandler, { maxBodyBytes: 64 });

  const byHeader = await guarded(post({ "content-length": "100000" }));
  assert.equal(byHeader.status, 413);

  const byStream = await guarded(post({}, "x".repeat(100_000)));
  assert.equal(byStream.status, 413);
});

test("guard converts handler crashes into opaque JSON-RPC 500s", async () => {
  const guarded = createGuardedMcpHandler(async () => {
    throw new Error("secret internal detail");
  });

  const originalError = console.error;
  console.error = () => {};
  try {
    const response = await guarded(post());
    assert.equal(response.status, 500);
    const body = await response.text();
    assert.doesNotMatch(body, /secret internal detail/);
  } finally {
    console.error = originalError;
  }
});
