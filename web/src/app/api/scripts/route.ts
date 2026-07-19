import { NextResponse } from "next/server";
import { githubService } from "~/lib/github";
import { AnalyticsService } from "~/lib/supabase-analytics";

export async function GET() {
  try {
    // Weekly and total aggregates are maintained by database triggers and
    // pg_cron jobs (refresh_weekly_analytics hourly, recalculate_all_analytics
    // nightly) - no app-side maintenance needed here.

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
