import { NextResponse, type NextRequest } from "next/server";

import { isMcpProtocolRequest } from "~/server/mcp/requestRouting";

// /mcp is one public URL with two faces: browsers get the Next.js guide page
// (with the site navbar and footer), MCP clients speak Streamable HTTP. The
// protocol handler lives at /api/mcp; this rewrite keeps the advertised
// https://intuneautomation.com/mcp working for both without a client-visible
// redirect.
export function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname.replace(/\/$/, "");
  if (
    pathname === "/mcp" &&
    isMcpProtocolRequest(request.method, request.headers.get("accept"))
  ) {
    return NextResponse.rewrite(new URL("/api/mcp", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/mcp", "/mcp/"],
};
