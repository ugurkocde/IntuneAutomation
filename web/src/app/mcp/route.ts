import {
  createGuideAwareMcpGetHandler,
  createMcpGuideResponse,
} from "~/server/mcp/guidePage";
import { createIntuneMcpHandler } from "~/server/mcp/intuneServer";
import { intuneScriptRepository } from "~/server/mcp/repository";
import { createGuardedMcpHandler } from "~/server/mcp/requestGuards";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

const handler = createGuardedMcpHandler(
  createIntuneMcpHandler(intuneScriptRepository),
);

export const GET = createGuideAwareMcpGetHandler(handler);
export const HEAD = () => Promise.resolve(createMcpGuideResponse(true));

export { handler as DELETE, handler as OPTIONS, handler as POST };
