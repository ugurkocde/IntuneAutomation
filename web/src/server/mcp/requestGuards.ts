// HTTP-level protections for the public MCP endpoint: per-IP rate limiting,
// request body caps, and a browser origin allowlist. In-memory and
// per-instance by design; the endpoint is read-only over cached public data,
// so the guard's job is abuse damping, not accounting.
const DEFAULT_MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_REQUESTS_PER_MINUTE = 60;
const RATE_LIMIT_WINDOW_MS = 60_000;
const MAX_RATE_LIMIT_KEYS = 10_000;
const DEFAULT_ALLOWED_ORIGINS = [
  "https://intuneautomation.com",
  "https://www.intuneautomation.com",
];

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

interface GuardOptions {
  maxBodyBytes?: number;
  requestsPerMinute?: number;
  now?: () => number;
  allowedOrigins?: readonly string[];
}

type McpHandler = (request: Request) => Promise<Response>;

const globalForMcpRateLimit = globalThis as unknown as {
  intuneMcpRateLimits?: Map<string, RateLimitEntry>;
};

const rateLimits =
  globalForMcpRateLimit.intuneMcpRateLimits ??
  new Map<string, RateLimitEntry>();

globalForMcpRateLimit.intuneMcpRateLimits = rateLimits;

const clientKey = (request: Request) => {
  const forwardedFor =
    request.headers.get("x-vercel-forwarded-for") ??
    request.headers.get("x-forwarded-for") ??
    request.headers.get("x-real-ip");
  return forwardedFor?.split(",")[0]?.trim() ?? "unknown";
};

const jsonRpcHttpError = (
  status: number,
  message: string,
  extraHeaders?: HeadersInit,
) =>
  new Response(
    JSON.stringify({
      jsonrpc: "2.0",
      id: null,
      error: { code: -32000, message },
    }),
    {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        ...extraHeaders,
      },
    },
  );

const withPublicMcpHeaders = (response: Response, origin: string | null) => {
  const headers = new Headers(response.headers);
  if (origin) headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Access-Control-Expose-Headers", "Mcp-Session-Id, Retry-After");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  const vary = headers.get("Vary");
  if (
    !vary
      ?.toLowerCase()
      .split(/\s*,\s*/)
      .includes("origin")
  ) {
    headers.set("Vary", vary ? `${vary}, Origin` : "Origin");
  }
  if (response.status === 405 && !headers.has("Allow")) {
    headers.set("Allow", "POST, OPTIONS");
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
};

const pruneRateLimits = (now: number) => {
  for (const [key, entry] of rateLimits) {
    if (entry.resetAt <= now) rateLimits.delete(key);
  }

  while (rateLimits.size >= MAX_RATE_LIMIT_KEYS) {
    const oldestKey = rateLimits.keys().next().value as string | undefined;
    if (!oldestKey) break;
    rateLimits.delete(oldestKey);
  }
};

const readBoundedBody = async (request: Request, maxBytes: number) => {
  if (!request.body) return new ArrayBuffer(0);

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    totalBytes += value.byteLength;
    if (totalBytes > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }

  const body = new ArrayBuffer(totalBytes);
  const bytes = new Uint8Array(body);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
};

export function createGuardedMcpHandler(
  handler: McpHandler,
  options: GuardOptions = {},
) {
  const maxBodyBytes = options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
  const requestsPerMinute =
    options.requestsPerMinute ?? DEFAULT_REQUESTS_PER_MINUTE;
  const now = options.now ?? Date.now;
  const configuredOrigins = (process.env.MCP_ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  const allowedOrigins = new Set(
    options.allowedOrigins ?? [
      ...DEFAULT_ALLOWED_ORIGINS,
      ...configuredOrigins,
      ...(process.env.NODE_ENV === "production"
        ? []
        : ["http://localhost:3000", "http://127.0.0.1:3000"]),
    ],
  );

  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get("origin");
    if (origin && !allowedOrigins.has(origin)) {
      return withPublicMcpHeaders(
        jsonRpcHttpError(
          403,
          "This browser origin cannot access the MCP server.",
        ),
        null,
      );
    }

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          ...(origin ? { "Access-Control-Allow-Origin": origin } : {}),
          "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Headers":
            "Content-Type, Accept, MCP-Protocol-Version, Mcp-Session-Id, Last-Event-ID",
          "Access-Control-Max-Age": "86400",
          Vary: "Origin",
        },
      });
    }

    const currentTime = now();
    const key = clientKey(request);
    let entry = rateLimits.get(key);

    if (entry && entry.resetAt <= currentTime) {
      rateLimits.delete(key);
      entry = undefined;
    }

    if (!entry) {
      if (rateLimits.size >= MAX_RATE_LIMIT_KEYS) pruneRateLimits(currentTime);
      entry = { count: 0, resetAt: currentTime + RATE_LIMIT_WINDOW_MS };
      rateLimits.set(key, entry);
    } else {
      rateLimits.delete(key);
      rateLimits.set(key, entry);
    }

    entry.count += 1;
    if (entry.count > requestsPerMinute) {
      const retryAfter = Math.max(
        1,
        Math.ceil((entry.resetAt - currentTime) / 1_000),
      );
      return withPublicMcpHeaders(
        jsonRpcHttpError(429, "Too many MCP requests. Please retry later.", {
          "Retry-After": String(retryAfter),
        }),
        origin,
      );
    }

    let forwardedRequest = request;
    if (request.method === "POST") {
      const contentLength = Number(request.headers.get("content-length"));
      if (Number.isFinite(contentLength) && contentLength > maxBodyBytes) {
        return withPublicMcpHeaders(
          jsonRpcHttpError(413, "The MCP request body is too large."),
          origin,
        );
      }

      const body = await readBoundedBody(request, maxBodyBytes);
      if (!body) {
        return withPublicMcpHeaders(
          jsonRpcHttpError(413, "The MCP request body is too large."),
          origin,
        );
      }

      forwardedRequest = new Request(request, { body });
    }

    try {
      return withPublicMcpHeaders(await handler(forwardedRequest), origin);
    } catch (error) {
      console.error(
        "IntuneAutomation MCP request failed:",
        error instanceof Error ? error.name : "UnknownError",
      );
      return withPublicMcpHeaders(
        jsonRpcHttpError(500, "The MCP server could not process the request."),
        origin,
      );
    }
  };
}
