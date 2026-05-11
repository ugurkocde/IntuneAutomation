import { NextResponse } from "next/server";
import { AnalyticsService } from "~/lib/supabase-analytics";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const action = searchParams.get("action");
    const limit = parseInt(searchParams.get("limit") || "10");
    const by = (searchParams.get("by") as "views" | "downloads") || "views";

    switch (action) {
      case "top-scripts":
        const topScripts = await AnalyticsService.getTopScripts(by, limit);
        return NextResponse.json({
          success: true,
          data: topScripts,
          count: topScripts.length,
        });

      case "all-analytics":
        const analytics = await AnalyticsService.getAllScriptAnalytics();
        return NextResponse.json({
          success: true,
          data: analytics,
          count: Object.keys(analytics).length,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action parameter",
            message: "Available actions: top-scripts, all-analytics",
          },
          { status: 400 },
        );
    }
  } catch (error) {
    console.error("Analytics API error:", error);

    return NextResponse.json(
      {
        success: false,
        error: "Failed to fetch analytics data",
        message: error instanceof Error ? error.message : "Unknown error",
      },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const action = searchParams.get("action");

    switch (action) {
      case "track-view":
        const viewData = await request.json();
        const viewResult = await AnalyticsService.trackScriptView(
          viewData.scriptId,
          viewData.scriptTitle,
          {
            userAgent: viewData.userAgent,
            sessionId: viewData.sessionId,
          },
        );

        return NextResponse.json({
          success: viewResult,
          message: viewResult
            ? "View tracked successfully"
            : "Failed to track view",
        });

      case "track-download":
        const downloadData = await request.json();
        const downloadResult = await AnalyticsService.trackScriptDownload(
          downloadData.scriptId,
          downloadData.scriptTitle,
          downloadData.downloadType,
          {
            userAgent: downloadData.userAgent,
            sessionId: downloadData.sessionId,
          },
        );

        return NextResponse.json({
          success: downloadResult,
          message: downloadResult
            ? "Download tracked successfully"
            : "Failed to track download",
        });

      case "cleanup":
        const { daysToKeep = 90 } = await request.json();
        await AnalyticsService.cleanupOldData(daysToKeep);

        return NextResponse.json({
          success: true,
          message: `Cleaned up data older than ${daysToKeep} days`,
        });

      default:
        return NextResponse.json(
          {
            success: false,
            error: "Invalid action parameter",
            message: "Available actions: track-view, track-download, cleanup",
          },
          { status: 400 },
        );
    }
  } catch (error) {
    console.error("Analytics API error:", error);

    return NextResponse.json(
      {
        success: false,
        error: "Failed to process analytics request",
        message: error instanceof Error ? error.message : "Unknown error",
      },
      { status: 500 },
    );
  }
}
