import { NextResponse, type NextRequest } from "next/server";
import { hashIp, peekPerIp } from "~/server/generator/rate-limit";
import { getClientIp } from "~/server/generator/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

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
