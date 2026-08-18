// Decides whether a request to /mcp is a browser page view (serve the Next.js
// guide page with the site chrome) or MCP protocol traffic (rewrite to the
// /api/mcp route handler). Pure and dependency-free so the middleware (edge
// runtime) and the node test runner can both import it.

/**
 * Browser page views are GET/HEAD requests that prefer text/html. Everything
 * else (POST/DELETE/OPTIONS, SSE streams, JSON accepts) is protocol traffic.
 */
export function isMcpProtocolRequest(
  method: string,
  acceptHeader: string | null,
): boolean {
  if (method !== "GET" && method !== "HEAD") return true;

  const accept = acceptHeader?.toLowerCase() ?? "";
  return (
    !accept.includes("text/html") ||
    accept.includes("text/event-stream") ||
    accept.includes("application/json")
  );
}
