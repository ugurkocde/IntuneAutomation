import { NextResponse } from "next/server";
import { getTotalCount } from "~/server/generator/rate-limit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Public stats — lifetime count of initial /generate calls that passed
// Turnstile. Used as a small social-proof line under the form's daily quota.
// Cached on the edge for 60s so the public endpoint doesn't get hammered on
// every page load.
export async function GET() {
  const total = await getTotalCount();
  return NextResponse.json(
    { total },
    {
      status: 200,
      headers: {
        "cache-control":
          "public, s-maxage=60, stale-while-revalidate=300",
      },
    },
  );
}
