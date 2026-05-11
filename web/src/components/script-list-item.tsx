"use client";

// ScriptListItem v4 — compact hairline row for galleries and sidebars.
// Mono kicker tag · display-weight title · muted description · mono meta strip.
// Hairline border, no shadows, no rainbow tag palette, single cyan accent. Hover
// state lifts text + slides arrow — never a giant card-y elevation change.

import React from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import type { Script } from "~/lib/scripts";
import { useAnalyticsContext } from "~/components/analytics-provider";
import { VerifiedBadge } from "~/components/verified-badge";
import { ArrowUpRight } from "lucide-react";

interface ScriptListItemProps {
  script: Script;
  onClick: () => void;
}

/* -------------------------- formatting helpers --------------------------- */

function formatCompactNumber(num: number): string {
  if (num >= 1_000_000) return (num / 1_000_000).toFixed(1) + "M";
  if (num >= 10_000) return (num / 1000).toFixed(1) + "k";
  if (num >= 1000) return (num / 1000).toFixed(1) + "k";
  return num.toString();
}

function formatRelative(iso?: string): string | null {
  if (!iso) return null;
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return null;
  const diff = Date.now() - then;
  const day = 86_400_000;
  const days = Math.floor(diff / day);
  if (days < 1) return "today";
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  if (days < 365) return `${Math.floor(days / 30)}mo ago`;
  return `${Math.floor(days / 365)}y ago`;
}

/* --------------------------------- view ---------------------------------- */

export function ScriptListItem({ script, onClick }: ScriptListItemProps) {
  const prefersReducedMotion = useReducedMotion();
  const primaryTag = script.tags[0];
  const scriptUrl = `/script/${script.id}/`;

  const { getAnalytics } = useAnalyticsContext();
  const analytics = getAnalytics(script.id);
  const usageStats = analytics || script.usageStats;

  // Notification / runbook classification — same logic as ScriptCard.
  const isNotification =
    script.execution === "RunbookOnly" ||
    script.category === "notification" ||
    script.tags.includes("Notification");

  const kicker = isNotification
    ? "// NOTIFICATION · RUNBOOK"
    : primaryTag
      ? `// ${primaryTag.toUpperCase()}`
      : "// SCRIPT";

  const updatedRel = formatRelative(script.lastUpdated);

  // Build mono meta strip.
  const metaParts: string[] = [];
  if (usageStats && usageStats.totalViews > 0) {
    metaParts.push(`${formatCompactNumber(usageStats.totalViews)} views`);
  }
  if (usageStats && usageStats.totalDownloads > 0) {
    metaParts.push(`${formatCompactNumber(usageStats.totalDownloads)} dl`);
  }
  if (updatedRel) metaParts.push(`updated ${updatedRel}`);

  const handleClick = (e: React.MouseEvent) => {
    if (e.metaKey || e.ctrlKey) return; // honor open-in-new-tab
    e.preventDefault();
    onClick();
  };

  return (
    <motion.div
      initial={prefersReducedMotion ? false : { opacity: 0, y: 6 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-10%" }}
      transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
      className="group"
    >
      <Link
        href={scriptUrl}
        onClick={handleClick}
        className="focus-visible:ring-accent block focus-visible:outline-none"
        aria-label={script.title}
      >
        <article
          className="bg-card/40 relative grid grid-cols-[1fr_auto] items-start gap-x-4 gap-y-2 rounded-md border p-5 backdrop-blur-sm transition-[transform,border-color] duration-200 ease-out group-hover:-translate-y-0.5 group-focus-visible:-translate-y-0.5 sm:grid-cols-[1fr_auto_auto] sm:p-6"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          {/* Hover border accent layer */}
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 rounded-md border opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-visible:opacity-100"
            style={{
              borderColor:
                "color-mix(in oklab, var(--brand-accent) 40%, transparent)",
            }}
          />

          {/* Left column — kicker, title, description, tags */}
          <div className="min-w-0">
            <p
              className="font-mono text-[10.5px] font-medium tracking-[0.14em] uppercase"
              style={{
                color: isNotification
                  ? "var(--brand-azure)"
                  : "var(--brand-accent-hi)",
              }}
              aria-hidden="true"
            >
              {kicker}
            </p>

            <h3 className="font-display text-foreground group-hover:text-accent-hi mt-2 line-clamp-1 text-base leading-tight tracking-[-0.015em] transition-colors sm:text-lg">
              {script.title}
            </h3>

            <p className="text-muted-foreground mt-1.5 line-clamp-2 text-sm leading-relaxed">
              {script.description}
            </p>

            {/* Mono tag chips + meta — combined into a single mono line */}
            <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1.5">
              <div className="flex flex-wrap gap-1.5">
                {script.tags.slice(0, 3).map((tag) => (
                  <span
                    key={tag}
                    className="text-muted-foreground inline-flex items-center rounded-sm border px-1.5 py-0.5 font-mono text-[10px] tracking-[0.14em] uppercase"
                    style={{ borderColor: "var(--brand-rule)" }}
                  >
                    {tag}
                  </span>
                ))}
                {script.tags.length > 3 && (
                  <span className="text-muted-foreground/70 inline-flex items-center font-mono text-[10px] tracking-[0.14em] uppercase">
                    +{script.tags.length - 3}
                  </span>
                )}
              </div>
              {metaParts.length > 0 && (
                <p className="text-muted-foreground/80 font-mono text-[11px] tracking-wide">
                  · {metaParts.join(" · ")}
                </p>
              )}
            </div>
          </div>

          {/* Mid column — verified badge (md+ only) */}
          <div className="hidden shrink-0 sm:block">
            <VerifiedBadge script={script} />
          </div>

          {/* Right column — affordance arrow */}
          <div className="flex items-start justify-end pt-1">
            <ArrowUpRight
              aria-hidden="true"
              className="text-muted-foreground/60 group-hover:text-accent-hi h-4 w-4 shrink-0 transition-all duration-200 group-hover:-translate-y-px group-hover:translate-x-0.5"
            />
          </div>
        </article>
      </Link>
    </motion.div>
  );
}
