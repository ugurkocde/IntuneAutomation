import { createClient } from "@supabase/supabase-js";

// Supabase configuration
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

// `persistSession: false` + an explicit `storage: undefined` keeps the auth
// helper from touching `localStorage`. Required for SSR safety in Node 22+
// where `globalThis.localStorage` exists as a partial polyfill that breaks
// Supabase v2's default auth storage. Anonymous reads/writes (which is what
// this app uses Supabase for) don't need session persistence anyway.
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});

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

export interface MonthlyAnalytics {
  month: string;
  views: number;
  downloads: number;
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

  // Monthly rollup of deduplicated, bot-filtered events (see get_monthly_analytics in Supabase)
  static async getMonthlyAnalytics(
    monthsBack: number = 12,
  ): Promise<MonthlyAnalytics[]> {
    try {
      if (!supabaseUrl || !supabaseAnonKey) {
        return [];
      }

      const { data, error } = await supabase.rpc("get_monthly_analytics", {
        months_back: monthsBack,
      });

      if (error) {
        return [];
      }

      return (data as MonthlyAnalytics[]) ?? [];
    } catch (error) {
      return [];
    }
  }

  // Monthly rollup for a single script (see get_script_monthly_analytics in Supabase)
  static async getScriptMonthlyAnalytics(
    scriptId: string,
    monthsBack: number = 12,
  ): Promise<MonthlyAnalytics[]> {
    try {
      if (!supabaseUrl || !supabaseAnonKey) {
        return [];
      }

      const { data, error } = await supabase.rpc(
        "get_script_monthly_analytics",
        {
          p_script_id: scriptId,
          months_back: monthsBack,
        },
      );

      if (error) {
        return [];
      }

      return (data as MonthlyAnalytics[]) ?? [];
    } catch (error) {
      return [];
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
