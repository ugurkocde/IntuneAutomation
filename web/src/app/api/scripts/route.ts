import { NextResponse } from "next/server";
import { githubService } from "~/lib/github";
import { AnalyticsService } from "~/lib/supabase-analytics";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const forceRecalculate = searchParams.get("recalculate") === "true";

    // Reset weekly analytics on Monday or if explicitly requested
    const now = new Date();
    const isMonday = now.getDay() === 1;

    if (isMonday) {
      // Reset weekly stats in the background on Mondays
      AnalyticsService.resetWeeklyAnalytics().catch(console.error);
    } else if (forceRecalculate) {
      // Only do full recalculation if explicitly requested (use with caution!)
      AnalyticsService.recalculateAllAnalytics().catch(console.error);
    }

    // Fetch scripts (which includes cached file data)
    const scripts = await githubService.fetchAllScripts();

    // Always fetch fresh analytics data to ensure accurate view counts
    const freshAnalytics = await AnalyticsService.getAllScriptAnalytics();

    // Update scripts with fresh analytics data
    const scriptsWithFreshAnalytics = scripts.map((script) => {
      const analytics = freshAnalytics[script.id];
      if (analytics) {
        return {
          ...script,
          usageStats: {
            totalViews: analytics.total_views,
            totalDownloads: analytics.total_downloads,
            weeklyViews: analytics.weekly_views,
            weeklyDownloads: analytics.weekly_downloads,
            lastViewedAt: analytics.last_viewed_at,
          },
        };
      }
      return script;
    });

    return NextResponse.json(
      {
        success: true,
        data: scriptsWithFreshAnalytics,
        count: scriptsWithFreshAnalytics.length,
        lastFetched: new Date().toISOString(),
      },
      {
        headers: {
          // Allow caching for 1 minute to balance performance and freshness
          "Cache-Control": "public, s-maxage=60, stale-while-revalidate=59",
        },
      },
    );
  } catch (error) {
    console.error("Failed to fetch scripts:", error);

    return NextResponse.json(
      {
        success: false,
        error: "Failed to fetch scripts from GitHub",
        message: error instanceof Error ? error.message : "Unknown error",
      },
      { status: 500 },
    );
  }
}

export async function POST() {
  return NextResponse.json({ error: "Method not allowed" }, { status: 405 });
}
