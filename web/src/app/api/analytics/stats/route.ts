import { NextResponse } from "next/server";
import { supabase } from "~/lib/supabase-analytics";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  try {
    // Fetch all analytics data from the script_analytics table
    const { data: analytics, error } = await supabase
      .from("script_analytics")
      .select("*");

    if (error) {
      console.error("Failed to fetch analytics:", error);
      return NextResponse.json({}, { status: 200 });
    }

    // Transform to a map for easy lookup
    const analyticsMap = (analytics || []).reduce(
      (acc, stat) => {
        acc[stat.script_id] = {
          totalViews: stat.total_views,
          weeklyViews: stat.weekly_views,
          totalDownloads: stat.total_downloads,
          weeklyDownloads: stat.weekly_downloads,
        };
        return acc;
      },
      {} as Record<string, any>,
    );

    // Return with no-cache headers
    return NextResponse.json(analyticsMap, {
      headers: {
        "Cache-Control": "no-store, no-cache, must-revalidate",
        Pragma: "no-cache",
        Expires: "0",
      },
    });
  } catch (error) {
    console.error("Failed to fetch analytics stats:", error);
    return NextResponse.json({}, { status: 200 });
  }
}
