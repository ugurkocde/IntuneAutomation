import { NextResponse } from "next/server";
import { supabase } from "~/lib/supabase-analytics";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  try {
    // Fetch aggregated stats from the script_analytics table
    const { data: analytics, error } = await supabase
      .from("script_analytics")
      .select("total_views, total_downloads");

    if (error) {
      console.error("Failed to fetch analytics:", error);
      return NextResponse.json(
        {
          totalViews: 0,
          totalDownloads: 0,
          totalScripts: 0,
        },
        { status: 200 },
      );
    }

    // Calculate totals
    const totalViews = (analytics || []).reduce(
      (sum, stat) => sum + (stat.total_views || 0),
      0,
    );
    const totalDownloads = (analytics || []).reduce(
      (sum, stat) => sum + (stat.total_downloads || 0),
      0,
    );
    const totalScripts = (analytics || []).length;

    // Return with cache headers (5 minutes cache)
    return NextResponse.json(
      {
        totalViews,
        totalDownloads,
        totalScripts,
      },
      {
        headers: {
          "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600",
        },
      },
    );
  } catch (error) {
    console.error("Failed to fetch total stats:", error);
    return NextResponse.json(
      {
        totalViews: 0,
        totalDownloads: 0,
        totalScripts: 0,
      },
      { status: 200 },
    );
  }
}