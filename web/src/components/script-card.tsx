"use client";

// ScriptCard v3 — editorial-technical aesthetic.
// One accent (phosphor cyan). Azure-blue reserved for the Deploy affordance and
// the Notification/Runbook tag. Amber reserved for the single Trending pulse-dot.
// Surface: rounded-md, hairline border, no shadow. Composition: mono kicker,
// display title, body description, mono stats, mono action row (Copy/Deploy/GitHub).

import React from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { Check, Cloud, Copy, Github } from "lucide-react";
import type { Script, ScriptTag } from "~/lib/scripts";
import { useAnalyticsContext } from "~/components/analytics-provider";
import { VerifiedBadge } from "~/components/verified-badge";

interface ScriptCardProps {
  script: Script;
  onClick: () => void;
}

/* ------------------------------------------------------------------ */
/*  Formatting helpers                                                 */
/* ------------------------------------------------------------------ */

function formatCompactNumber(num: number): string {
  if (num >= 1_000_000) return (num / 1_000_000).toFixed(1) + "M";
  if (num >= 10_000) return (num / 1000).toFixed(1) + "k";
  if (num >= 1000) return (num / 1000).toFixed(1) + "k";
  return num.toString();
}

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

export function ScriptCard({ script, onClick }: ScriptCardProps) {
  const prefersReducedMotion = useReducedMotion();
  const [copied, setCopied] = React.useState(false);

  const scriptUrl = `/script/${script.id}`;
  const primaryTag: ScriptTag | undefined = script.tags[0];

  // Analytics — real-time if available, else cached.
  const { getAnalytics } = useAnalyticsContext();
  const analytics = getAnalytics(script.id);
  const usageStats = analytics || script.usageStats;

  // Notification / runbook classification (preserved logic).
  const isNotification =
    script.execution === "RunbookOnly" ||
    script.category === "notification" ||
    script.tags.includes("Notification" as ScriptTag);

  // Trending classification (preserved logic).
  const isTrending =
    !!usageStats &&
    (usageStats.weeklyViews > 10 || usageStats.weeklyDownloads > 5);

  /* ------------------ Handlers ------------------ */

  const handleCardClick = (e: React.MouseEvent) => {
    // Honor cmd/ctrl+click (open in new tab via Link).
    if (e.metaKey || e.ctrlKey) return;
    e.preventDefault();
    onClick();
  };

  const handleCopyScript = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(script.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch (err) {
      console.error("Failed to copy:", err);
    }
  };

  const handleDeployToAzure = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    try {
      const res = await fetch(
        "https://raw.githubusercontent.com/ugurkocde/IntuneAutomation/main/azure-deployment-templates.json",
      );
      if (!res.ok) throw new Error("Failed to fetch Azure templates");
      const registry = (await res.json()) as {
        templates: Record<string, { deployUrl: string }>;
      };
      const template = registry.templates[script.id];
      if (!template) throw new Error("Template not found");
      window.open(template.deployUrl, "_blank");
    } catch (err) {
      console.error("Azure deployment failed:", err);
      window.open(scriptUrl, "_blank");
    }
  };

  const handleGithub = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (script.githubUrl) {
      window.open(script.githubUrl, "_blank");
    }
  };

  /* ------------------ Derived display ------------------ */

  const kicker = isNotification
    ? "// NOTIFICATION · RUNBOOK"
    : primaryTag
      ? `// ${primaryTag.toUpperCase()}`
      : "// SCRIPT";

  // Build the stats line — only include what we actually have.
  const statsParts: string[] = [];
  if (usageStats && usageStats.totalViews > 0) {
    statsParts.push(`${formatCompactNumber(usageStats.totalViews)} views`);
  }
  if (usageStats && usageStats.totalDownloads > 0) {
    statsParts.push(`${formatCompactNumber(usageStats.totalDownloads)} dl`);
  }

  /* ------------------ Render ------------------ */

  return (
    <motion.div
      initial={prefersReducedMotion ? false : { opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
      className="group"
    >
      <Link
        href={scriptUrl}
        onClick={handleCardClick}
        className="block focus-visible:outline-none"
        aria-label={script.title}
      >
        <article
          className="bg-card/40 relative flex h-full flex-col rounded-md border p-5 backdrop-blur-sm transition-[transform,border-color] duration-200 ease-out group-hover:-translate-y-0.5 group-focus-visible:-translate-y-0.5 sm:p-6"
          style={{
            borderColor: "var(--brand-rule)",
            // Hover border color shift via CSS var so we don't need a JS toggle.
            // The hover state below overrides this with color-mix.
          }}
        >
          {/* Hover/focus border accent — applied via a sibling absolute layer
              so we can use color-mix without losing the base hairline. */}
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 rounded-md border opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-visible:opacity-100"
            style={{
              borderColor:
                "color-mix(in oklab, var(--brand-accent) 40%, transparent)",
            }}
          />

          {/* Trending pulse — single small amber dot in top-right.
              The ONLY non-cyan colour signal on the card (besides the inline
              Deploy/Notification azure accent). */}
          {isTrending && (
            <span
              className="pointer-events-none absolute top-3 right-3 inline-flex h-2 w-2"
              role="status"
              aria-label="Trending this week"
              title="Trending this week"
            >
              <span
                aria-hidden="true"
                className="absolute inline-flex h-full w-full rounded-full opacity-75"
                style={{
                  backgroundColor: "var(--brand-warn)",
                  animation: prefersReducedMotion
                    ? "none"
                    : "ping 2.4s cubic-bezier(0,0,0.2,1) infinite",
                }}
              />
              <span
                aria-hidden="true"
                className="relative inline-flex h-2 w-2 rounded-full"
                style={{ backgroundColor: "var(--brand-warn)" }}
              />
            </span>
          )}

          {/* Kicker — mono uppercase tag label */}
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

          {/* Title */}
          <h3 className="font-display text-foreground group-hover:text-foreground mt-3 line-clamp-2 text-[1.375rem] leading-tight tracking-[-0.02em] transition-colors duration-200">
            {script.title}
          </h3>

          {/* Description */}
          <p className="text-muted-foreground mt-3 line-clamp-3 text-sm leading-relaxed">
            {script.description}
          </p>

          {/* Spacer that pushes the footer to the bottom of an equal-height card */}
          <div className="flex-1" />

          {/* Stats line — mono, muted, dot-separated */}
          {statsParts.length > 0 && (
            <p className="text-muted-foreground/90 mt-5 font-mono text-[11px] tracking-wide">
              {statsParts.join(" · ")}
            </p>
          )}

          {/* Verified badge + action row — separated by hairline rule */}
          <div
            className="mt-4 flex items-center justify-between gap-3 border-t pt-4"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            {/* Action row — three compact mono micro-links */}
            <div className="flex items-center gap-3">
              <ActionButton
                onClick={handleCopyScript}
                ariaLabel={
                  copied ? "Script copied" : "Copy script to clipboard"
                }
              >
                {copied ? (
                  <>
                    <Check
                      className="h-3 w-3"
                      strokeWidth={2.25}
                      aria-hidden="true"
                      style={{ color: "var(--brand-accent-hi)" }}
                    />
                    <span style={{ color: "var(--brand-accent-hi)" }}>
                      Copied
                    </span>
                  </>
                ) : (
                  <>
                    <Copy
                      className="h-3 w-3"
                      strokeWidth={2}
                      aria-hidden="true"
                    />
                    <span>Copy</span>
                  </>
                )}
              </ActionButton>

              <Separator />

              <ActionButton
                onClick={handleDeployToAzure}
                ariaLabel="Deploy to Azure Automation"
                accent="azure"
              >
                <Cloud className="h-3 w-3" strokeWidth={2} aria-hidden="true" />
                <span>Deploy</span>
              </ActionButton>

              {script.githubUrl && (
                <>
                  <Separator />
                  <ActionButton
                    onClick={handleGithub}
                    ariaLabel="View source on GitHub (opens in new tab)"
                  >
                    <Github
                      className="h-3 w-3"
                      strokeWidth={2}
                      aria-hidden="true"
                    />
                    <span>GitHub</span>
                  </ActionButton>
                </>
              )}
            </div>

            {/* Quality check badge — kept; uses semantic tokens internally */}
            <div className="shrink-0">
              <VerifiedBadge script={script} />
            </div>
          </div>
        </article>
      </Link>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-primitives                                                     */
/* ------------------------------------------------------------------ */

function ActionButton({
  children,
  onClick,
  ariaLabel,
  accent = "default",
}: {
  children: React.ReactNode;
  onClick: (e: React.MouseEvent) => void;
  ariaLabel: string;
  accent?: "default" | "azure";
}) {
  const hoverColor =
    accent === "azure" ? "var(--brand-azure)" : "var(--brand-accent-hi)";

  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      className="text-muted-foreground hover:text-foreground focus-visible:ring-accent group/btn focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm font-mono text-[11px] tracking-wide uppercase transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
      style={
        {
          // CSS var consumed by hover style below. We rely on the Tailwind
          // hover:text-foreground for the default state, then override on
          // hover with an inline style for the accent variant.
          ["--hover-color" as string]: hoverColor,
        } as React.CSSProperties
      }
      onMouseEnter={(e) => {
        if (accent === "azure") {
          (e.currentTarget as HTMLElement).style.color = hoverColor;
        }
      }}
      onMouseLeave={(e) => {
        if (accent === "azure") {
          (e.currentTarget as HTMLElement).style.color = "";
        }
      }}
    >
      {children}
    </button>
  );
}

function Separator() {
  return (
    <span
      aria-hidden="true"
      className="inline-block h-1 w-1 shrink-0 rounded-full"
      style={{
        backgroundColor:
          "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
      }}
    />
  );
}
