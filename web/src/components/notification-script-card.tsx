"use client";

// NotificationScriptCard v4 — kept as a specialised variant of the script
// card surface for any caller that wants notification/runbook framing.
// Currently not imported anywhere in the gallery routes (the standard
// `<ScriptCard>` v4 already surfaces `// NOTIFICATION · RUNBOOK` as its
// kicker for runbook-only scripts), but kept here in case a future caller
// wants the bigger surface. Reskinned from v1 (rainbow palette, gradient
// overlays, rounded-2xl) to v4 (hairline border, rounded-md, mono kicker,
// semantic tokens + cyan/azure accents only).

import React from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { useAnalyticsContext } from "~/components/analytics-provider";
import { VerifiedBadge } from "~/components/verified-badge";
import { ArrowUpRight, Apple, Mail, CloudLightning } from "lucide-react";

interface EnhancedScriptCardProps {
  script: Script;
  onClick: () => void;
}

function formatCompactNumber(num: number): string {
  if (num >= 1_000_000) return (num / 1_000_000).toFixed(1) + "M";
  if (num >= 10_000) return (num / 1000).toFixed(1) + "k";
  if (num >= 1000) return (num / 1000).toFixed(1) + "k";
  return num.toString();
}

export function NotificationScriptCard({
  script,
  onClick,
}: EnhancedScriptCardProps) {
  const primaryTag = script.tags[0];
  const scriptUrl = `/script/${script.id}/`;
  const prefersReducedMotion = useReducedMotion();

  const { getAnalytics } = useAnalyticsContext();
  const analytics = getAnalytics(script.id);
  const usageStats = analytics || script.usageStats;

  const isNotification =
    script.execution === "RunbookOnly" ||
    script.category === "notification" ||
    script.tags.includes("Notification" as ScriptTag);

  const isEmail = script.output === "Email";

  const isMacOS = script.testedPlatforms?.some(
    (platform) =>
      platform.toLowerCase().includes("macos") ||
      platform.toLowerCase().includes("mac os"),
  );

  const handleClick = (e: React.MouseEvent) => {
    if (e.metaKey || e.ctrlKey) return;
    e.preventDefault();
    onClick();
  };

  const kicker = isNotification
    ? "// NOTIFICATION · RUNBOOK"
    : primaryTag
      ? `// ${primaryTag.toUpperCase()}`
      : "// SCRIPT";

  return (
    <motion.div
      initial={prefersReducedMotion ? false : { opacity: 0, y: 8 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-10%" }}
      transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
      className="group"
    >
      <Link
        href={scriptUrl}
        onClick={handleClick}
        className="block focus-visible:outline-none"
        aria-label={script.title}
      >
        <article
          className="bg-card/40 relative flex h-full min-h-[260px] flex-col rounded-md border p-5 backdrop-blur-sm transition-[transform,border-color] duration-200 ease-out group-hover:-translate-y-0.5 sm:p-6"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 rounded-md border opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-visible:opacity-100"
            style={{
              borderColor:
                "color-mix(in oklab, var(--brand-accent) 40%, transparent)",
            }}
          />

          {/* Kicker */}
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
          <h3 className="font-display text-foreground mt-3 line-clamp-2 text-[1.25rem] leading-tight tracking-[-0.02em]">
            {script.title}
          </h3>

          {/* Description */}
          <p className="text-muted-foreground mt-3 line-clamp-3 text-sm leading-relaxed">
            {script.description}
          </p>

          {/* Mono attribute strip */}
          <div className="mt-4 flex flex-wrap items-center gap-1.5">
            {isMacOS && (
              <MetaPill icon={Apple} label="macOS" />
            )}
            {isNotification && (
              <MetaPill
                icon={CloudLightning}
                label="Runbook only"
                accent="azure"
              />
            )}
            {isNotification && isEmail && (
              <MetaPill icon={Mail} label="Email" accent="azure" />
            )}
          </div>

          <div className="flex-1" />

          {/* Stats + verified badge */}
          <div
            className="mt-5 flex items-center justify-between gap-3 border-t pt-4"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <div className="text-muted-foreground font-mono text-[11px] tracking-wide">
              {usageStats ? (
                <>
                  {formatCompactNumber(usageStats.totalViews)} views ·{" "}
                  {formatCompactNumber(usageStats.totalDownloads)} dl
                </>
              ) : (
                <span className="text-muted-foreground/60">— · —</span>
              )}
            </div>

            <div className="flex items-center gap-3">
              <VerifiedBadge script={script} />
              <ArrowUpRight
                className="text-muted-foreground group-hover:text-accent-hi h-3.5 w-3.5 transition-all group-hover:-translate-y-px"
                aria-hidden="true"
              />
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

function MetaPill({
  icon: Icon,
  label,
  accent = "default",
}: {
  icon: React.ElementType;
  label: string;
  accent?: "default" | "azure";
}) {
  const color =
    accent === "azure" ? "var(--brand-azure)" : "var(--brand-accent-hi)";
  return (
    <span
      className="inline-flex h-5 items-center gap-1 rounded-sm border px-1.5 font-mono text-[9.5px] font-medium tracking-[0.14em] uppercase"
      style={{
        borderColor: "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
        color,
      }}
    >
      <Icon className="h-3 w-3" aria-hidden="true" strokeWidth={2} />
      {label}
    </span>
  );
}
