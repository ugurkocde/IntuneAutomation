import { NextResponse, type NextRequest } from "next/server";
import { hashIp, peekPerIp } from "~/server/generator/rate-limit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function getClientIp(req: NextRequest): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]?.trim() ?? "unknown";
  return req.headers.get("x-real-ip") ?? "unknown";
}

export async function GET(req: NextRequest) {
  const ip = getClientIp(req);
  if (ip === "unknown") {
    return NextResponse.json(
      { remaining: null, limit: null, reset: null },
      { status: 200 },
    );
  }
  const { remaining, limit, reset } = await peekPerIp(hashIp(ip));
  return NextResponse.json(
    { remaining, limit, reset },
    {
      status: 200,
      headers: {
        "cache-control": "private, max-age=30",
      },
    },
  );
}
