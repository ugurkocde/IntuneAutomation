// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import {
  fetchWithRetry,
  isRetryableResponse,
  mapWithConcurrency,
} from "../src/lib/fetch-resilience.ts";

const noSleep = async () => {};
const response = (status, headers = {}) =>
  new Response(null, { status, headers });

test("isRetryableResponse treats 429 and 5xx as transient", () => {
  assert.equal(isRetryableResponse(response(429)), true);
  assert.equal(isRetryableResponse(response(502)), true);
  assert.equal(isRetryableResponse(response(404)), false);
  assert.equal(isRetryableResponse(response(401)), false);
});

test("isRetryableResponse retries GitHub rate-limit 403s but not permission 403s", () => {
  assert.equal(isRetryableResponse(response(403)), false);
  assert.equal(
    isRetryableResponse(response(403, { "x-ratelimit-remaining": "0" })),
    true,
  );
  assert.equal(
    isRetryableResponse(response(403, { "retry-after": "30" })),
    true,
  );
  assert.equal(
    isRetryableResponse(response(403, { "x-ratelimit-remaining": "42" })),
    false,
  );
});

test("fetchWithRetry returns the first ok response without retrying", async () => {
  let calls = 0;
  const res = await fetchWithRetry(
    async () => {
      calls++;
      return response(200);
    },
    { sleep: noSleep },
  );
  assert.equal(res.status, 200);
  assert.equal(calls, 1);
});

test("fetchWithRetry retries transient statuses and network errors", async () => {
  const outcomes = [
    () => Promise.reject(new Error("ECONNRESET")),
    () => Promise.resolve(response(503)),
    () => Promise.resolve(response(200)),
  ];
  let calls = 0;
  const res = await fetchWithRetry(() => outcomes[calls++](), {
    attempts: 3,
    sleep: noSleep,
  });
  assert.equal(res.status, 200);
  assert.equal(calls, 3);
});

test("fetchWithRetry does not retry non-transient statuses", async () => {
  let calls = 0;
  const res = await fetchWithRetry(
    async () => {
      calls++;
      return response(404);
    },
    { attempts: 3, sleep: noSleep },
  );
  assert.equal(res.status, 404);
  assert.equal(calls, 1);
});

test("fetchWithRetry surfaces the last failure once attempts are exhausted", async () => {
  let calls = 0;
  const res = await fetchWithRetry(
    async () => {
      calls++;
      return response(500);
    },
    { attempts: 2, sleep: noSleep },
  );
  assert.equal(res.status, 500);
  assert.equal(calls, 2);

  await assert.rejects(
    fetchWithRetry(
      async () => {
        throw new Error("down");
      },
      { attempts: 2, sleep: noSleep },
    ),
    /down/,
  );
});

test("fetchWithRetry backs off exponentially between attempts", async () => {
  const waits = [];
  let calls = 0;
  await fetchWithRetry(
    async () => {
      calls++;
      return response(calls < 3 ? 500 : 200);
    },
    { attempts: 3, baseDelayMs: 100, sleep: async (ms) => void waits.push(ms) },
  );
  assert.deepEqual(waits, [100, 200]);
});

test("mapWithConcurrency preserves order and caps in-flight work", async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const items = [5, 1, 4, 2, 3, 0];
  const result = await mapWithConcurrency(items, 2, async (n) => {
    inFlight++;
    maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((r) => setTimeout(r, n));
    inFlight--;
    return n * 10;
  });
  assert.deepEqual(result, [50, 10, 40, 20, 30, 0]);
  assert.equal(maxInFlight, 2);
});

test("mapWithConcurrency rejects when any task fails", async () => {
  await assert.rejects(
    mapWithConcurrency([1, 2, 3], 3, async (n) => {
      if (n === 2) throw new Error("boom");
      return n;
    }),
    /boom/,
  );
});

test("mapWithConcurrency handles empty input", async () => {
  assert.deepEqual(await mapWithConcurrency([], 4, async (x) => x), []);
});
