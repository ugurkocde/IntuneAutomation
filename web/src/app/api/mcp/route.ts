import { NextResponse } from "next/server";

import { createIntuneMcpHandler } from "~/server/mcp/intuneServer";
import { intuneScriptRepository } from "~/server/mcp/repository";
import { createGuardedMcpHandler } from "~/server/mcp/requestGuards";
import { isMcpProtocolRequest } from "~/server/mcp/requestRouting";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

const handler = createGuardedMcpHandler(
  createIntuneMcpHandler(intuneScriptRepository),
);

// Browsers land here only when they bypass the middleware rewrite by hitting
// /api/mcp directly; send them to the guide page at the public URL.
const GET = async (request: Request) =>
  isMcpProtocolRequest(request.method, request.headers.get("accept"))
    ? handler(request)
    : NextResponse.redirect(new URL("/mcp/", request.url), 308);

export { GET, handler as DELETE, handler as OPTIONS, handler as POST };
