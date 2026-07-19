import type { Metadata } from "next";
import Link from "next/link";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";
import { MonthlyTrendsChart } from "~/components/monthly-trends-chart";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { githubService } from "~/lib/github";

const BASE_URL = "https://intuneautomation.com";

export const metadata: Metadata = {
  title: "Script Usage Stats - Downloads and Views",
  description:
    "Live usage statistics for the IntuneAutomation script library: monthly download and view trends plus the all-time most downloaded Microsoft Intune PowerShell scripts. Counts are deduplicated and bot-filtered.",
  alternates: { canonical: "/stats/" },
  openGraph: {
    title: "Script Usage Stats - Downloads and Views",
    description:
      "Monthly trends and the all-time leaderboard of the most downloaded Intune PowerShell scripts.",
    url: `${BASE_URL}/stats/`,
    type: "website",
    siteName: "IntuneAutomation",
  },
};

// Aggregates change slowly (hourly/nightly jobs); rebuild at most every 5 minutes
export const revalidate = 300;

function formatCompactNumber(num: number): string {
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
  if (num >= 1000) return `${(num / 1000).toFixed(1)}k`;
  return num.toString();
}

export default async function StatsPage() {
  const [monthly, analyticsMap, scripts] = await Promise.all([
    AnalyticsService.getMonthlyAnalytics(12),
    AnalyticsService.getAllScriptAnalytics(),
    githubService.fetchAllScripts(),
  ]);

  const scriptById = new Map(scripts.map((s) => [s.id, s]));

  // Leaderboard: prefer scripts that still exist in the library; if the GitHub
  // fetch failed (empty list), fall back to analytics-only entries so the page
  // still renders.
  const leaderboard = Object.values(analyticsMap)
    .filter((a) => scripts.length === 0 || scriptById.has(a.script_id))
    .sort((a, b) => b.total_downloads - a.total_downloads)
    .slice(0, 15);

  const trackedScripts =
    scripts.length > 0
      ? scripts.length
      : Object.values(analyticsMap).filter((a) => a.total_downloads > 0).length;

  const totals = Object.values(analyticsMap).reduce(
    (acc, a) => ({
      downloads: acc.downloads + a.total_downloads,
      views: acc.views + a.total_views,
      weeklyDownloads: acc.weeklyDownloads + a.weekly_downloads,
    }),
    { downloads: 0, views: 0, weeklyDownloads: 0 },
  );

  const tiles = [
    { label: "Total downloads", value: totals.downloads },
    { label: "Total views", value: totals.views },
    { label: "Downloads this week", value: totals.weeklyDownloads },
    { label: "Scripts in library", value: trackedScripts },
  ];

  return (
    <AnalyticsProvider>
      <ScriptsProvider>
        <div className="bg-background min-h-screen">
          <Navbar />

          <main className="container mx-auto max-w-5xl px-4 py-12">
            <header className="mb-10">
              <h1 className="text-foreground text-3xl font-bold tracking-tight">
                Script usage stats
              </h1>
              <p className="text-muted-foreground mt-2 max-w-2xl text-sm">
                Live statistics for the script library. Counts are deduplicated
                per session and filtered for bot traffic, so numbers reflect
                real usage.
              </p>
            </header>

            {/* Stat tiles */}
            <section
              aria-label="Overall totals"
              className="mb-10 grid grid-cols-2 gap-4 md:grid-cols-4"
            >
              {tiles.map((tile) => (
                <div
                  key={tile.label}
                  className="bg-card border-border rounded-lg border p-4"
                >
                  <p className="text-foreground text-2xl font-semibold tabular-nums">
                    {formatCompactNumber(tile.value)}
                  </p>
                  <p className="text-muted-foreground mt-1 text-xs">
                    {tile.label}
                  </p>
                </div>
              ))}
            </section>

            {/* Monthly trends */}
            <section aria-labelledby="trends-heading" className="mb-12">
              <h2
                id="trends-heading"
                className="text-foreground mb-1 text-xl font-semibold"
              >
                Monthly trends
              </h2>
              <p className="text-muted-foreground mb-4 text-sm">
                Views and downloads per month over the last 12 months.
              </p>
              <div className="bg-card border-border rounded-lg border p-4 sm:p-6">
                <MonthlyTrendsChart data={monthly} />
              </div>
            </section>

            {/* All-time leaderboard */}
            <section aria-labelledby="leaderboard-heading">
              <h2
                id="leaderboard-heading"
                className="text-foreground mb-1 text-xl font-semibold"
              >
                All-time leaderboard
              </h2>
              <p className="text-muted-foreground mb-4 text-sm">
                The most downloaded scripts since tracking began.
              </p>
              <div className="bg-card border-border overflow-x-auto rounded-lg border">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="text-muted-foreground border-border border-b text-xs">
                      <th className="px-4 py-3 font-medium">#</th>
                      <th className="px-4 py-3 font-medium">Script</th>
                      <th className="px-4 py-3 text-right font-medium">
                        Downloads
                      </th>
                      <th className="px-4 py-3 text-right font-medium">
                        Views
                      </th>
                      <th className="hidden px-4 py-3 text-right font-medium sm:table-cell">
                        This week
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {leaderboard.map((entry, index) => {
                      const script = scriptById.get(entry.script_id);
                      const fallbackTitle = entry.script_id
                        .split("-")
                        .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
                        .join(" ");
                      return (
                        <tr
                          key={entry.script_id}
                          className="border-border/60 hover:bg-accent/40 border-b transition-colors last:border-b-0"
                        >
                          <td className="text-muted-foreground px-4 py-3 tabular-nums">
                            {index + 1}
                          </td>
                          <td className="px-4 py-3">
                            {script ? (
                              <Link
                                href={`/script/${script.slug}/`}
                                className="text-foreground hover:text-brand-accent font-medium transition-colors"
                              >
                                {script.title}
                              </Link>
                            ) : (
                              <span className="text-foreground font-medium">
                                {fallbackTitle}
                              </span>
                            )}
                          </td>
                          <td className="text-foreground px-4 py-3 text-right tabular-nums">
                            {entry.total_downloads.toLocaleString("en-US")}
                          </td>
                          <td className="text-muted-foreground px-4 py-3 text-right tabular-nums">
                            {entry.total_views.toLocaleString("en-US")}
                          </td>
                          <td className="text-muted-foreground hidden px-4 py-3 text-right tabular-nums sm:table-cell">
                            {entry.weekly_downloads.toLocaleString("en-US")}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <p className="text-muted-foreground mt-3 text-xs">
                Downloads include copies to clipboard, raw file downloads, and
                GitHub opens. Stats refresh hourly.
              </p>
            </section>
          </main>

          <Footer />
        </div>
      </ScriptsProvider>
    </AnalyticsProvider>
  );
}
