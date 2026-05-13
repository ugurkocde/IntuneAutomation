"use client";

// ScriptComparisonTable v4 — editorial spec-sheet treatment.
// Hairline-bordered comparison grid, mono column headers with Lucide icons (no emojis),
// single cyan accent for the active column row separators. Summary cards reuse the
// rounded-md / hairline / no-shadow card vocabulary; the "Notification" card carries
// a faint azure-tinted top edge instead of the previous violet gradient.

import React from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight, Bell, Check, Settings, X } from "lucide-react";

interface ComparisonRow {
  feature: string;
  operational: string | boolean;
  notification: string | boolean;
}

const comparisonData: ComparisonRow[] = [
  {
    feature: "Execution Environment",
    operational: "Local + Azure Automation",
    notification: "Azure Automation Only",
  },
  {
    feature: "Output Method",
    operational: "Files (CSV, JSON, HTML)",
    notification: "Email Notifications Only",
  },
  {
    feature: "Authentication",
    operational: "Interactive + Managed Identity",
    notification: "Managed Identity Only",
  },
  {
    feature: "Scheduling",
    operational: "Optional",
    notification: "Required (Daily/Weekly)",
  },
  {
    feature: "Primary Use Case",
    operational: "On-demand tasks & reporting",
    notification: "Continuous monitoring & alerting",
  },
  {
    feature: "Parameters",
    operational: "Multiple configuration options",
    notification: "Minimal (threshold + recipients)",
  },
  {
    feature: "User Interaction",
    operational: "Direct execution & immediate results",
    notification: "Set-and-forget automation",
  },
  {
    feature: "Microsoft Graph Permissions",
    operational: "Read-only for specific resources",
    notification: "Read + Mail.Send",
  },
  {
    feature: "Local Execution Support",
    operational: true,
    notification: false,
  },
  { feature: "Email Alerts", operational: false, notification: true },
];

/* ------------------------------------------------------------------------ */
/*  Cell content primitive                                                   */
/* ------------------------------------------------------------------------ */

function CellValue({ value }: { value: string | boolean }) {
  if (typeof value === "boolean") {
    return value ? (
      <span
        className="inline-flex items-center gap-1.5 font-mono text-[11px] tracking-wide uppercase"
        style={{ color: "var(--brand-accent-hi)" }}
      >
        <Check className="h-4 w-4" strokeWidth={2.25} aria-hidden="true" />
        Yes
      </span>
    ) : (
      <span className="text-muted-foreground/70 inline-flex items-center gap-1.5 font-mono text-[11px] tracking-wide uppercase">
        <X className="h-4 w-4" strokeWidth={2.25} aria-hidden="true" />
        No
      </span>
    );
  }
  return (
    <span className="text-muted-foreground text-sm leading-relaxed">
      {value}
    </span>
  );
}

/* ------------------------------------------------------------------------ */
/*  Section                                                                  */
/* ------------------------------------------------------------------------ */

export function ScriptComparisonTable() {
  const prefersReducedMotion = useReducedMotion();
  const ease = [0.22, 1, 0.36, 1] as const;
  const fade = (delay: number) => ({
    initial: prefersReducedMotion ? false : { opacity: 0, y: 12 },
    whileInView: { opacity: 1, y: 0 },
    viewport: { once: true, margin: "-80px" },
    transition: { delay, duration: 0.55, ease },
  });

  return (
    <section className="py-20 sm:py-24" aria-labelledby="comparison-heading">
      <div className="mx-auto max-w-5xl px-4 sm:px-6">
        {/* Opener — mono kicker + display headline */}
        <motion.div className="text-center" {...fade(0)}>
          <p className="font-mono-label text-accent-hi">// COMPARISON</p>
          <h2
            id="comparison-heading"
            className="font-display text-foreground mt-3 text-3xl leading-tight tracking-[-0.02em] sm:text-4xl"
          >
            Script types, side by side.
          </h2>
          <p className="text-muted-foreground mx-auto mt-4 max-w-2xl text-base leading-relaxed sm:text-lg">
            Understanding the difference between operational and notification
            scripts helps you pick the right tool for the job.
          </p>
        </motion.div>

        {/* Desktop table */}
        <motion.div
          {...fade(0.1)}
          className="bg-card/40 mt-12 hidden overflow-hidden rounded-md border backdrop-blur-md md:block"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <table className="w-full text-left">
            <thead>
              <tr
                className="border-b"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                <th className="w-1/3 px-5 py-4 align-bottom">
                  <p className="text-muted-foreground font-mono text-[10.5px] tracking-[0.18em] uppercase">
                    // FEATURE
                  </p>
                </th>
                <th className="px-5 py-4 align-bottom">
                  <p
                    className="font-mono text-[10.5px] tracking-[0.18em] uppercase"
                    style={{ color: "var(--brand-accent-hi)" }}
                  >
                    // OPERATIONAL · REPORTING
                  </p>
                  <div className="mt-2 flex items-center gap-2">
                    <Settings
                      className="h-4 w-4"
                      style={{ color: "var(--brand-accent-hi)" }}
                      aria-hidden="true"
                    />
                    <span className="font-display text-foreground text-base leading-tight tracking-[-0.015em]">
                      Traditional scripts
                    </span>
                  </div>
                </th>
                <th className="px-5 py-4 align-bottom">
                  <p
                    className="font-mono text-[10.5px] tracking-[0.18em] uppercase"
                    style={{ color: "var(--brand-azure)" }}
                  >
                    // NOTIFICATION · RUNBOOK
                  </p>
                  <div className="mt-2 flex items-center gap-2">
                    <Bell
                      className="h-4 w-4"
                      style={{ color: "var(--brand-azure)" }}
                      aria-hidden="true"
                    />
                    <span className="font-display text-foreground text-base leading-tight tracking-[-0.015em]">
                      Monitoring &amp; alerts
                    </span>
                    <span
                      className="ml-1 inline-flex items-center rounded-sm border px-1.5 py-0.5 font-mono text-[9.5px] font-medium tracking-[0.16em] uppercase"
                      style={{
                        borderColor:
                          "color-mix(in oklab, var(--brand-warn) 50%, transparent)",
                        color: "var(--brand-warn)",
                      }}
                    >
                      New
                    </span>
                  </div>
                </th>
              </tr>
            </thead>
            <tbody>
              {comparisonData.map((row, index) => (
                <tr
                  key={row.feature}
                  className={
                    index === comparisonData.length - 1 ? "" : "border-b"
                  }
                  style={
                    index === comparisonData.length - 1
                      ? undefined
                      : { borderColor: "var(--brand-rule)" }
                  }
                >
                  <td className="text-foreground px-5 py-4 align-top text-sm font-medium">
                    {row.feature}
                  </td>
                  <td className="px-5 py-4 align-top">
                    <CellValue value={row.operational} />
                  </td>
                  <td className="px-5 py-4 align-top">
                    <CellValue value={row.notification} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </motion.div>

        {/* Mobile stacked cards */}
        <div className="mt-10 space-y-3 md:hidden">
          {comparisonData.map((row, index) => (
            <motion.div
              key={row.feature}
              initial={prefersReducedMotion ? false : { opacity: 0, y: 8 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={{
                delay: Math.min(index * 0.04, 0.32),
                duration: 0.45,
                ease,
              }}
              className="bg-card/40 rounded-md border p-4 backdrop-blur-sm"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <p className="text-muted-foreground font-mono text-[10.5px] tracking-[0.18em] uppercase">
                {row.feature}
              </p>
              <dl className="mt-3 space-y-2">
                <div className="flex items-start justify-between gap-3">
                  <dt
                    className="font-mono text-[10.5px] tracking-[0.16em] uppercase"
                    style={{ color: "var(--brand-accent-hi)" }}
                  >
                    Operational
                  </dt>
                  <dd className="text-right">
                    <CellValue value={row.operational} />
                  </dd>
                </div>
                <div
                  className="flex items-start justify-between gap-3 border-t pt-2"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <dt
                    className="font-mono text-[10.5px] tracking-[0.16em] uppercase"
                    style={{ color: "var(--brand-azure)" }}
                  >
                    Notification
                  </dt>
                  <dd className="text-right">
                    <CellValue value={row.notification} />
                  </dd>
                </div>
              </dl>
            </motion.div>
          ))}
        </div>

        {/* Summary cards — both share the same v4 vocabulary. The notification
         * card carries a faint azure top-edge instead of the old violet gradient. */}
        <div className="mt-14 grid gap-5 md:grid-cols-2">
          <motion.div
            {...fade(0.15)}
            className="bg-card/40 rounded-md border p-6 backdrop-blur-md"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <p
              className="font-mono text-[10.5px] tracking-[0.18em] uppercase"
              style={{ color: "var(--brand-accent-hi)" }}
            >
              // WHEN TO PICK · OPERATIONAL
            </p>
            <h3 className="font-display text-foreground mt-2 text-xl leading-tight tracking-[-0.015em]">
              Direct execution &amp; one-off tasks
            </h3>
            <ul className="mt-5 space-y-2.5">
              {[
                "Need immediate results or reports",
                "Running ad-hoc analysis or troubleshooting",
                "Exporting data for further processing",
                "Performing one-time administrative tasks",
              ].map((bullet) => (
                <li
                  key={bullet}
                  className="text-muted-foreground flex items-start gap-2.5 text-sm leading-relaxed"
                >
                  <span
                    aria-hidden="true"
                    className="mt-2 inline-block h-1 w-1 shrink-0 rounded-full"
                    style={{ backgroundColor: "var(--brand-accent)" }}
                  />
                  <span>{bullet}</span>
                </li>
              ))}
            </ul>
          </motion.div>

          <motion.div
            {...fade(0.22)}
            className="bg-card/40 relative rounded-md border p-6 backdrop-blur-md"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            {/* Azure hairline rule — signals the notification path */}
            <span
              aria-hidden="true"
              className="pointer-events-none absolute inset-x-0 top-0 h-px"
              style={{
                background:
                  "linear-gradient(to right, transparent, color-mix(in oklab, var(--brand-azure) 60%, transparent), transparent)",
              }}
            />
            <p
              className="font-mono text-[10.5px] tracking-[0.18em] uppercase"
              style={{ color: "var(--brand-azure)" }}
            >
              // WHEN TO PICK · NOTIFICATION
            </p>
            <h3 className="font-display text-foreground mt-2 text-xl leading-tight tracking-[-0.015em]">
              Continuous monitoring &amp; alerting
            </h3>
            <ul className="mt-5 space-y-2.5">
              {[
                "Want proactive monitoring of your environment",
                "Need alerts for critical events or thresholds",
                "Managing compliance and security posture",
                "Tracking expiration dates and renewals",
              ].map((bullet) => (
                <li
                  key={bullet}
                  className="text-muted-foreground flex items-start gap-2.5 text-sm leading-relaxed"
                >
                  <span
                    aria-hidden="true"
                    className="mt-2 inline-block h-1 w-1 shrink-0 rounded-full"
                    style={{ backgroundColor: "var(--brand-azure)" }}
                  />
                  <span>{bullet}</span>
                </li>
              ))}
            </ul>

            <Link
              href="/scripts/notification/"
              className="focus-visible:ring-accent group focus-visible:ring-offset-background mt-6 inline-flex w-full items-center justify-between rounded-sm border px-4 py-2.5 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              style={{ borderColor: "var(--brand-rule)" }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor =
                  "color-mix(in oklab, var(--brand-azure) 50%, transparent)";
                e.currentTarget.style.color = "var(--brand-azure)";
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = "var(--brand-rule)";
                e.currentTarget.style.color = "";
              }}
            >
              <span>Explore notification scripts</span>
              <ArrowRight
                className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5"
                aria-hidden="true"
              />
            </Link>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
