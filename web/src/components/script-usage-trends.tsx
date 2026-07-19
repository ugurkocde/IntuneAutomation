"use client";

import { useEffect, useState } from "react";
import { MonthlyTrendsChart } from "~/components/monthly-trends-chart";
import {
  AnalyticsService,
  type MonthlyAnalytics,
} from "~/lib/supabase-analytics";

// Fetches the per-script monthly rollup client-side (same anon path as the
// rest of the analytics) and renders nothing until data with actual activity
// arrives - analytics failures must never block or clutter the page.
export function ScriptUsageTrends({
  scriptId,
  months = 12,
  compact = false,
  children,
}: {
  scriptId: string;
  months?: number;
  compact?: boolean;
  // Wrapper rendered only when there is data; the chart is passed as an
  // argument so each surface (page section, dialog card) keeps its own frame.
  children: (chart: React.ReactNode) => React.ReactNode;
}) {
  const [data, setData] = useState<MonthlyAnalytics[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    // Clear previous script's data so a script switch inside a mounted dialog
    // never shows the old chart under the new title while the fetch resolves
    setData(null);
    AnalyticsService.getScriptMonthlyAnalytics(scriptId, months)
      .then((rows) => {
        if (!cancelled) setData(rows);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });
    return () => {
      cancelled = true;
    };
  }, [scriptId, months]);

  if (!data || !data.some((d) => d.views > 0 || d.downloads > 0)) {
    return null;
  }

  return <>{children(<MonthlyTrendsChart data={data} compact={compact} />)}</>;
}
