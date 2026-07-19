"use client";

import { useRef, useState } from "react";
import type { MonthlyAnalytics } from "~/lib/supabase-analytics";

const SERIES = [
  { key: "views" as const, label: "Views", color: "var(--stat-views)" },
  {
    key: "downloads" as const,
    label: "Downloads",
    color: "var(--stat-downloads)",
  },
];

function formatCompact(num: number): string {
  if (num >= 1000) {
    return `${(num / 1000).toFixed(num >= 10000 ? 0 : 1)}k`;
  }
  return num.toString();
}

function monthLabel(iso: string, withYear = false): string {
  const d = new Date(`${iso}T00:00:00Z`);
  const month = d.toLocaleString("en-US", { month: "short", timeZone: "UTC" });
  return withYear ? `${month} '${String(d.getUTCFullYear()).slice(2)}` : month;
}

function niceCeil(value: number): number {
  if (value <= 0) return 10;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  for (const m of [1, 2, 2.5, 5, 10]) {
    if (m * magnitude >= value) return m * magnitude;
  }
  return 10 * magnitude;
}

// The SVG plot with its own hover state, so the full and compact variants can
// be rendered side by side (visibility toggled by CSS breakpoints) without
// sharing crosshair geometry.
function TrendChartSvg({
  data,
  compact,
}: {
  data: MonthlyAnalytics[];
  compact: boolean;
}) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);

  // SVG coordinate space (scales responsively via viewBox). Compact keeps the
  // viewBox close to narrow container widths so text stays legible.
  const W = compact ? 340 : 720;
  const H = compact ? 190 : 300;
  const PAD = compact
    ? { top: 10, right: 12, bottom: 24, left: 36 }
    : { top: 16, right: 96, bottom: 30, left: 48 };
  const PLOT_W = W - PAD.left - PAD.right;
  const PLOT_H = H - PAD.top - PAD.bottom;

  const maxValue = niceCeil(
    Math.max(...data.map((d) => Math.max(d.views, d.downloads))),
  );

  const x = (i: number) =>
    PAD.left +
    (data.length === 1 ? PLOT_W / 2 : (i / (data.length - 1)) * PLOT_W);
  const y = (v: number) => PAD.top + PLOT_H - (v / maxValue) * PLOT_H;

  const gridValues = [0.25, 0.5, 0.75, 1].map((f) => f * maxValue);

  const handleMove = (event: React.MouseEvent<SVGSVGElement>) => {
    const svg = svgRef.current;
    if (!svg) return;
    const rect = svg.getBoundingClientRect();
    const px = ((event.clientX - rect.left) / rect.width) * W;
    const step = data.length === 1 ? PLOT_W : PLOT_W / (data.length - 1);
    const index = Math.round((px - PAD.left) / step);
    setHoverIndex(Math.min(data.length - 1, Math.max(0, index)));
  };

  const hovered = hoverIndex === null ? null : data[hoverIndex];

  return (
    <div className="relative">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${W} ${H}`}
        className="w-full"
        role="img"
        aria-label="Monthly views and downloads over the charted period"
        onMouseMove={handleMove}
        onMouseLeave={() => setHoverIndex(null)}
      >
        {/* Gridlines + y labels (recessive) */}
        {gridValues.map((v) => (
          <g key={v}>
            <line
              x1={PAD.left}
              x2={PAD.left + PLOT_W}
              y1={y(v)}
              y2={y(v)}
              stroke="var(--border)"
              strokeWidth={1}
            />
            <text
              x={PAD.left - 8}
              y={y(v) + 3}
              textAnchor="end"
              fontSize={10}
              fill="var(--muted-foreground)"
            >
              {formatCompact(Math.round(v))}
            </text>
          </g>
        ))}
        {/* Baseline */}
        <line
          x1={PAD.left}
          x2={PAD.left + PLOT_W}
          y1={y(0)}
          y2={y(0)}
          stroke="var(--muted-foreground)"
          strokeWidth={1}
        />

        {/* X labels (thinned out when compact charts have many months) */}
        {data.map((d, i) => {
          if (compact && data.length > 8 && i % 2 === 1) return null;
          const showYear = i === 0 || d.month.slice(5, 7) === "01";
          return (
            <text
              key={d.month}
              x={x(i)}
              y={H - 8}
              textAnchor="middle"
              fontSize={10}
              fill="var(--muted-foreground)"
            >
              {monthLabel(d.month, showYear)}
            </text>
          );
        })}

        {/* Crosshair */}
        {hoverIndex !== null && (
          <line
            x1={x(hoverIndex)}
            x2={x(hoverIndex)}
            y1={PAD.top}
            y2={PAD.top + PLOT_H}
            stroke="var(--muted-foreground)"
            strokeWidth={1}
            strokeDasharray="3 3"
          />
        )}

        {/* Series lines */}
        {SERIES.map((s) => (
          <polyline
            key={s.key}
            points={data.map((d, i) => `${x(i)},${y(d[s.key])}`).join(" ")}
            fill="none"
            stroke={s.color}
            strokeWidth={2}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        ))}

        {/* End-of-line direct labels with surface-ringed markers */}
        {!compact &&
          SERIES.map((s) => {
            const last = data[data.length - 1]!;
            return (
              <g key={s.key}>
                <circle
                  cx={x(data.length - 1)}
                  cy={y(last[s.key])}
                  r={4}
                  fill={s.color}
                  stroke="var(--card)"
                  strokeWidth={2}
                />
                <text
                  x={x(data.length - 1) + 10}
                  y={y(last[s.key]) + 3}
                  fontSize={11}
                  fill="var(--foreground)"
                >
                  {s.label}
                </text>
              </g>
            );
          })}

        {/* Hover markers */}
        {hoverIndex !== null &&
          hovered &&
          SERIES.map((s) => (
            <circle
              key={s.key}
              cx={x(hoverIndex)}
              cy={y(hovered[s.key])}
              r={4.5}
              fill={s.color}
              stroke="var(--card)"
              strokeWidth={2}
            />
          ))}
      </svg>

      {/* Tooltip */}
      {hoverIndex !== null && hovered && (
        <div
          className="bg-popover border-border pointer-events-none absolute top-2 z-10 rounded-md border px-3 py-2 text-xs shadow-sm"
          style={{
            left: `${(x(hoverIndex) / W) * 100}%`,
            transform:
              hoverIndex > data.length / 2
                ? "translateX(calc(-100% - 12px))"
                : "translateX(12px)",
          }}
        >
          <p className="text-foreground mb-1 font-medium">
            {new Date(`${hovered.month}T00:00:00Z`).toLocaleString("en-US", {
              month: "long",
              year: "numeric",
              timeZone: "UTC",
            })}
          </p>
          {SERIES.map((s) => (
            <p
              key={s.key}
              className="text-muted-foreground flex items-center gap-1.5"
            >
              <span
                aria-hidden="true"
                className="inline-block h-2 w-2 rounded-full"
                style={{ backgroundColor: s.color }}
              />
              {s.label}:{" "}
              <span className="text-foreground font-medium">
                {hovered[s.key].toLocaleString("en-US")}
              </span>
            </p>
          ))}
        </div>
      )}
    </div>
  );
}

export function MonthlyTrendsChart({
  data,
  compact = false,
}: {
  data: MonthlyAnalytics[];
  // Compact mode targets containers that are narrow at every breakpoint
  // (dialog sidebar). Without it, the compact variant is still used below the
  // sm breakpoint so the chart stays legible on phones.
  compact?: boolean;
}) {
  if (data.length === 0) {
    return (
      <p className="text-muted-foreground py-12 text-center text-sm">
        No analytics data available yet.
      </p>
    );
  }

  // Period totals shown in the legend so the headline numbers live inside
  // the chart card itself
  const totals = data.reduce(
    (acc, d) => ({
      views: acc.views + d.views,
      downloads: acc.downloads + d.downloads,
    }),
    { views: 0, downloads: 0 },
  );

  return (
    <div>
      {/* Legend with period totals */}
      <div className="mb-2 flex flex-wrap items-center gap-x-4 gap-y-1">
        {SERIES.map((s) => (
          <span
            key={s.key}
            className="text-muted-foreground inline-flex items-center gap-1.5 text-xs"
          >
            <span
              aria-hidden="true"
              className="inline-block h-2 w-2 rounded-full"
              style={{ backgroundColor: s.color }}
            />
            {s.label}
            <span className="text-foreground font-medium tabular-nums">
              {totals[s.key].toLocaleString("en-US")}
            </span>
          </span>
        ))}
      </div>

      {compact ? (
        <TrendChartSvg data={data} compact />
      ) : (
        <>
          {/* Full chart from the sm breakpoint up, compact variant on phones */}
          <div className="hidden sm:block">
            <TrendChartSvg data={data} compact={false} />
          </div>
          <div className="sm:hidden">
            <TrendChartSvg data={data} compact />
          </div>
        </>
      )}

      {/* Table view of the same data */}
      <details className="mt-3">
        <summary className="text-muted-foreground hover:text-foreground cursor-pointer text-xs">
          View as table
        </summary>
        <div className="mt-2 overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead>
              <tr className="text-muted-foreground border-border border-b">
                <th className="py-1.5 pr-4 font-medium">Month</th>
                <th className="py-1.5 pr-4 text-right font-medium">Views</th>
                <th className="py-1.5 text-right font-medium">Downloads</th>
              </tr>
            </thead>
            <tbody>
              {data.map((d) => (
                <tr key={d.month} className="border-border/60 border-b">
                  <td className="py-1.5 pr-4">
                    {new Date(`${d.month}T00:00:00Z`).toLocaleString("en-US", {
                      month: "long",
                      year: "numeric",
                      timeZone: "UTC",
                    })}
                  </td>
                  <td className="py-1.5 pr-4 text-right tabular-nums">
                    {d.views.toLocaleString("en-US")}
                  </td>
                  <td className="py-1.5 text-right tabular-nums">
                    {d.downloads.toLocaleString("en-US")}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </div>
  );
}
