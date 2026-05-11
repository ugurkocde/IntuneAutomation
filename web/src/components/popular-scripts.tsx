"use client";

import type React from "react";

import { motion } from "framer-motion";
import { ScriptCard } from "~/components/script-card";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import {
  RefreshCw,
  AlertCircle,
  Github,
  ArrowRight,
  TrendingUp,
  Sparkles,
} from "lucide-react";
import { Button } from "~/components/ui/button";
import { Alert, AlertDescription } from "~/components/ui/alert";
import Link from "next/link";

export default function PopularScripts() {
  const {
    allScripts,
    selectedScript,
    setSelectedScript,
    setIsDetailOpen,
    isLoading,
    error,
    lastFetched,
    refetchScripts,
    updateScriptStats,
  } = useScripts();

  // Get the most popular scripts (top 6 by views and recent activity)
  const popularScripts = [...allScripts]
    .sort((a, b) => {
      // Prioritize scripts with high views and recent weekly activity
      const aScore =
        (a.usageStats?.totalViews || 0) + (a.usageStats?.weeklyViews || 0) * 10;
      const bScore =
        (b.usageStats?.totalViews || 0) + (b.usageStats?.weeklyViews || 0) * 10;
      return bScore - aScore;
    })
    .slice(0, 6);

  const handleScriptClick = (script: any) => {
    // Update stats immediately in the UI for real-time feedback
    updateScriptStats(script.id, "view");

    // Emit custom event for script view
    window.dispatchEvent(new Event("scriptViewed"));

    // Track analytics in the background (don't block UI)
    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? sessionStorage.getItem("session_id") || undefined
        : undefined;

    AnalyticsService.trackScriptView(script.id, script.title, {
      userAgent,
      sessionId,
    }).catch((error) => {
      // Silently fail - analytics shouldn't block user experience
    });

    // Update URL to match the script page for better navigation
    window.history.pushState(null, "", `/script/${script.slug}`);

    setSelectedScript(script);
    setIsDetailOpen(true);
  };

  return (
    <section
      id="popular-scripts-section"
      className="container mx-auto max-w-7xl px-4 py-16"
    >
      <div className="mb-12 text-center">
        <div className="mb-6 inline-flex items-center gap-2 rounded-full border bg-gradient-to-r from-blue-50 to-purple-50 px-4 py-2 text-sm font-medium text-blue-700 dark:from-blue-950/50 dark:to-purple-950/50 dark:text-blue-400">
          <TrendingUp className="h-4 w-4" />
          <span>Popular This Week</span>
        </div>

        <h2 className="mb-4 text-3xl font-bold">Most Popular Scripts</h2>
        <p className="text-muted-foreground mx-auto max-w-2xl">
          Discover the most viewed and downloaded PowerShell scripts — the
          community’s top picks for automating Intune tasks.
        </p>

        {/* Status Information */}
        <div className="mt-6 flex flex-col items-center gap-4">
          {isLoading && (
            <div className="text-muted-foreground flex items-center gap-2 text-sm">
              <RefreshCw className="h-4 w-4 animate-spin" />
              <span>Loading latest scripts...</span>
            </div>
          )}

          {error && (
            <Alert variant="destructive" className="max-w-2xl">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription className="flex items-center justify-between">
                <span>Failed to fetch scripts: {error}</span>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={refetchScripts}
                  className="ml-4"
                >
                  <RefreshCw className="mr-2 h-4 w-4" />
                  Retry
                </Button>
              </AlertDescription>
            </Alert>
          )}

          {lastFetched && !isLoading && !error && (
            <div className="text-muted-foreground flex items-center gap-2 text-xs">
              <Github className="h-3 w-3" />
              <span>
                Last updated: {new Date(lastFetched).toLocaleString()}
              </span>
            </div>
          )}
        </div>
      </div>

      {isLoading ? (
        <div className="py-12 text-center">
          <div className="inline-flex flex-col items-center gap-4">
            <RefreshCw className="text-muted-foreground h-8 w-8 animate-spin" />
            <p className="text-muted-foreground">Loading popular scripts...</p>
          </div>
        </div>
      ) : popularScripts.length === 0 ? (
        <div className="py-12 text-center">
          <p className="text-muted-foreground">
            No scripts available at the moment.
          </p>
        </div>
      ) : (
        <>
          {/* Popular Scripts Grid */}
          <motion.div
            className="grid min-h-[400px] grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ staggerChildren: 0.1 }}
          >
            {popularScripts.map((script, index) => (
              <motion.div
                key={script.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.1 }}
              >
                <ScriptCard
                  script={script}
                  onClick={() => handleScriptClick(script)}
                />
              </motion.div>
            ))}
          </motion.div>

          {/* Call to Action */}
          <div className="mt-16 text-center">
            <Button
              asChild
              size="lg"
              className="gap-2 bg-gradient-to-r from-blue-600 to-purple-600 shadow-lg hover:from-blue-700 hover:to-purple-700 hover:shadow-xl"
            >
              <Link href="/scripts">
                <span>Explore All Scripts</span>
                <ArrowRight className="h-4 w-4" />
              </Link>
            </Button>
          </div>
        </>
      )}
    </section>
  );
}
