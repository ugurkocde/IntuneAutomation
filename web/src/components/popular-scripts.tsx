"use client";

import type React from "react";

import { motion } from "framer-motion";
import { ScriptCard } from "~/components/script-card";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { RefreshCw, ArrowRight } from "lucide-react";
import { Button } from "~/components/ui/button";
import Link from "next/link";

export default function PopularScripts() {
  const {
    allScripts,
    selectedScript,
    setSelectedScript,
    setIsDetailOpen,
    isLoading,
    error,
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
      aria-labelledby="popular-heading"
      className="border-border/60 border-t px-4 py-24 sm:py-32"
    >
      <div className="mx-auto max-w-7xl">
        <div className="mb-14">
          <p className="font-mono-label text-accent-hi mb-4">
            // POPULAR THIS WEEK
          </p>
          <h2
            id="popular-heading"
            className="font-display text-foreground mb-3 text-4xl leading-[1.05] sm:text-5xl md:text-6xl"
          >
            What admins ran this week.
          </h2>
          <p className="text-muted-foreground max-w-2xl text-base sm:text-lg">
            The six most viewed and downloaded scripts in the library over the
            last seven days.
          </p>
        </div>

        {/* Inline status — small, mono, no heavy alert UI */}
        {error && (
          <div className="border-destructive/30 bg-destructive/5 text-destructive mb-8 flex items-center justify-between gap-4 rounded-md border px-4 py-3 text-sm">
            <span className="font-mono text-xs">
              <span className="opacity-60">ERR · </span>
              Failed to fetch scripts: {error}
            </span>
            <Button
              variant="outline"
              size="sm"
              onClick={refetchScripts}
              className="h-7 gap-1.5 text-xs"
            >
              <RefreshCw className="h-3 w-3" />
              Retry
            </Button>
          </div>
        )}

        {isLoading ? (
          <div className="grid min-h-[420px] grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
            {[...Array(6)].map((_, i) => (
              <div
                key={i}
                className="bg-card/40 border-border/40 h-56 animate-pulse rounded-md border"
              />
            ))}
          </div>
        ) : popularScripts.length === 0 ? (
          <div className="py-16 text-center">
            <p className="text-muted-foreground font-mono text-xs tracking-widest uppercase">
              No scripts available
            </p>
          </div>
        ) : (
          <>
            <motion.div
              className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ staggerChildren: 0.06 }}
            >
              {popularScripts.map((script, index) => (
                <motion.div
                  key={script.id}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.06, duration: 0.4 }}
                >
                  <ScriptCard
                    script={script}
                    onClick={() => handleScriptClick(script)}
                  />
                </motion.div>
              ))}
            </motion.div>

            <div className="border-border/60 mt-14 flex items-center justify-end gap-4 border-t pt-8">
              <Link
                href="/scripts/"
                className="text-foreground hover:text-accent-hi group inline-flex items-center gap-1.5 border-b border-current pb-0.5 font-mono text-sm transition-colors"
              >
                Browse all scripts
                <ArrowRight
                  className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5"
                  aria-hidden="true"
                />
              </Link>
            </div>
          </>
        )}
      </div>
    </section>
  );
}
