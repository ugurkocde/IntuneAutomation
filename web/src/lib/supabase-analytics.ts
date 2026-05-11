import { createClient } from "@supabase/supabase-js";

// Supabase configuration
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Types for our analytics tables
export interface ScriptView {
  id?: number;
  script_id: string;
  script_title: string;
  user_ip?: string;
  user_agent?: string;
  session_id?: string;
  created_at?: string;
}

export interface ScriptDownload {
  id?: number;
  script_id: string;
  script_title: string;
  download_type: "copy" | "raw" | "github" | "azure";
  user_ip?: string;
  user_agent?: string;
  session_id?: string;
  created_at?: string;
}

export interface ScriptAnalytics {
  script_id: string;
  total_views: number;
  total_downloads: number;
  weekly_views: number;
  weekly_downloads: number;
  last_viewed_at?: string;
  updated_at: string;
}

// Analytics service class
export class AnalyticsService {
  // Track when a user views a script
  static async trackScriptView(
    scriptId: string,
    scriptTitle: string,
    userInfo?: {
      userAgent?: string;
      sessionId?: string;
    },
  ) {
    try {
      // Check if Supabase is properly configured
      if (!supabaseUrl || !supabaseAnonKey) {
        return false;
      }

      const { error } = await supabase.from("script_views").insert({
        script_id: scriptId,
        script_title: scriptTitle,
        user_agent: userInfo?.userAgent,
        session_id: userInfo?.sessionId,
      });

      if (error) {
        return false;
      }

      // Analytics are now updated automatically by database triggers
      // No need to manually update aggregated analytics
      return true;
    } catch (error) {
      return false;
    }
  }

  // Track when a user downloads/copies a script
  static async trackScriptDownload(
    scriptId: string,
    scriptTitle: string,
    downloadType: "copy" | "raw" | "github" | "azure",
    userInfo?: {
      userAgent?: string;
      sessionId?: string;
    },
  ) {
    try {
      // Check if Supabase is properly configured
      if (!supabaseUrl || !supabaseAnonKey) {
        return false;
      }

      const { error } = await supabase.from("script_downloads").insert({
        script_id: scriptId,
        script_title: scriptTitle,
        download_type: downloadType,
        user_agent: userInfo?.userAgent,
        session_id: userInfo?.sessionId,
      });

      if (error) {
        return false;
      }

      // Analytics are now updated automatically by database triggers
      // No need to manually update aggregated analytics
      return true;
    } catch (error) {
      return false;
    }
  }

  // Update aggregated analytics for a script
  private static async updateScriptAnalytics(scriptId: string) {
    try {
      // First, let's see if we can read ANY data from the tables
      const { data: allViewsTest, error: allViewsError } = await supabase
        .from("script_views")
        .select("*")
        .limit(5);

      if (allViewsError) {
        return;
      }

      const { data: allDownloadsTest, error: allDownloadsError } =
        await supabase.from("script_downloads").select("*").limit(5);

      if (allDownloadsError) {
        return;
      }

      // Use a more reliable method: get the actual data and count it
      const { data: allViews, error: viewError } = await supabase
        .from("script_views")
        .select("*")
        .eq("script_id", scriptId);

      if (viewError) {
        return;
      }

      const totalViews = allViews?.length || 0;

      // Get downloads
      const { data: allDownloads, error: downloadError } = await supabase
        .from("script_downloads")
        .select("*")
        .eq("script_id", scriptId);

      if (downloadError) {
        return;
      }

      const totalDownloads = allDownloads?.length || 0;

      // Get weekly data (current week starting Monday)
      const now = new Date();
      const currentDay = now.getDay();
      const daysFromMonday = currentDay === 0 ? 6 : currentDay - 1; // Sunday = 0, so we need 6 days back
      const weekStart = new Date(now);
      weekStart.setDate(now.getDate() - daysFromMonday);
      weekStart.setHours(0, 0, 0, 0); // Start of Monday

      const weeklyViews =
        allViews?.filter((view) => new Date(view.created_at) >= weekStart)
          .length || 0;

      const weeklyDownloads =
        allDownloads?.filter(
          (download) => new Date(download.created_at) >= weekStart,
        ).length || 0;

      // Get last viewed time
      const lastView = allViews?.sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
      )[0];

      // Prepare the analytics data
      const analyticsData = {
        script_id: scriptId,
        total_views: totalViews,
        total_downloads: totalDownloads,
        weekly_views: weeklyViews,
        weekly_downloads: weeklyDownloads,
        last_viewed_at: lastView?.created_at,
        updated_at: new Date().toISOString(),
      };

      // Upsert analytics record with proper conflict resolution
      const { error } = await supabase
        .from("script_analytics")
        .upsert(analyticsData, {
          onConflict: "script_id",
          ignoreDuplicates: false,
        });

      if (error) {
        return;
      }

      // Verify the update by reading it back
      await supabase
        .from("script_analytics")
        .select("*")
        .eq("script_id", scriptId)
        .single();
    } catch (error) {
      // Silently fail
    }
  }

  // Get analytics for all scripts
  static async getAllScriptAnalytics(): Promise<
    Record<string, ScriptAnalytics>
  > {
    try {
      // Check if Supabase is properly configured
      if (!supabaseUrl || !supabaseAnonKey) {
        return {};
      }

      const { data, error } = await supabase
        .from("script_analytics")
        .select("*");

      if (error) {
        return {};
      }

      // Convert to map for easy lookup
      const analyticsMap: Record<string, ScriptAnalytics> = {};
      data?.forEach((analytics) => {
        analyticsMap[analytics.script_id] = {
          script_id: analytics.script_id,
          total_views: analytics.total_views,
          total_downloads: analytics.total_downloads,
          weekly_views: analytics.weekly_views,
          weekly_downloads: analytics.weekly_downloads,
          last_viewed_at: analytics.last_viewed_at,
          updated_at: analytics.updated_at,
        };
      });

      return analyticsMap;
    } catch (error) {
      return {};
    }
  }

  // Get top scripts by views or downloads
  static async getTopScripts(
    by: "views" | "downloads" = "views",
    limit: number = 10,
  ) {
    try {
      const orderColumn = by === "views" ? "total_views" : "total_downloads";

      const { data, error } = await supabase
        .from("script_analytics")
        .select("*")
        .order(orderColumn, { ascending: false })
        .limit(limit);

      if (error) {
        return [];
      }

      return data || [];
    } catch (error) {
      return [];
    }
  }

  // Clean up old analytics data (for maintenance)
  static async cleanupOldData(daysToKeep: number = 90) {
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);

      await Promise.all([
        supabase
          .from("script_views")
          .delete()
          .lt("created_at", cutoffDate.toISOString()),
        supabase
          .from("script_downloads")
          .delete()
          .lt("created_at", cutoffDate.toISOString()),
      ]);
    } catch (error) {
      // Silently fail
    }
  }

  // Reset weekly analytics using the database function
  static async resetWeeklyAnalytics() {
    try {
      // Check if Supabase is properly configured
      if (!supabaseUrl || !supabaseAnonKey) {
        return false;
      }

      // Call the existing database function that recalculates weekly stats
      const { error } = await supabase.rpc("refresh_weekly_analytics");

      if (error) {
        console.error("Failed to refresh weekly analytics:", error);
        return false;
      }

      return true;
    } catch (error) {
      console.error("Failed to reset weekly analytics:", error);
      return false;
    }
  }

  // Recalculate analytics for all scripts (use with caution - can overwrite correct values!)
  static async recalculateAllAnalytics() {
    try {
      // Get all unique script IDs from analytics table
      const { data: analyticsData } = await supabase
        .from("script_analytics")
        .select("script_id");

      if (!analyticsData || analyticsData.length === 0) {
        return true; // No analytics to update
      }

      // Update analytics for each script
      const updates = analyticsData.map((item) =>
        this.updateScriptAnalytics(item.script_id),
      );

      await Promise.all(updates);
      return true;
    } catch (error) {
      console.error("Failed to recalculate analytics:", error);
      return false;
    }
  }

  // Test Supabase connection
  static async testConnection() {
    try {
      const { data, error } = await supabase
        .from("script_analytics")
        .select("*")
        .limit(1);

      if (error) {
        return false;
      }

      return true;
    } catch (error) {
      return false;
    }
  }
}
