"use client";

// NotificationScriptsSection v4 — section wrapper for the notification/alerts
// landing strip. Reskinned from v1 (gradient hero text, rainbow palette,
// violet+indigo CTA panel, rounded-xl shadowed cards) to v4 (mono kicker,
// Geist display headline, hairline-bordered cards, semantic tokens, azure
// accent reserved for the Deploy/Runbook affordance, no emoji).
//
// Lucide icons (Apple, Smartphone, Shield, Package, etc.) replace any prior
// emoji platform-icon usage.

import React from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import {
  Apple,
  Bell,
  Mail,
  Calendar,
  Shield,
  AlertTriangle,
  Package,
  Smartphone,
  ArrowUpRight,
  CloudLightning,
  CheckCircle2,
} from "lucide-react";

const features = [
  {
    icon: Apple,
    title: "Apple Token Monitoring",
    description: "Get alerts before DEP tokens and APNS certificates expire.",
    script: "apple-token-expiration-alert",
    benefits: [
      "Prevent enrollment failures",
      "Plan renewals in advance",
      "Multiple threshold options",
    ],
  },
  {
    icon: Smartphone,
    title: "Stale Device Detection",
    description: "Identify devices that haven't checked in for cleanup.",
    script: "stale-device-cleanup-alert",
    benefits: [
      "Optimise licensing costs",
      "Maintain clean inventory",
      "Platform-specific analysis",
    ],
  },
  {
    icon: Shield,
    title: "Compliance Drift Alerts",
    description: "Monitor when devices fall out of compliance.",
    script: "device-compliance-drift-alert",
    benefits: [
      "Maintain security posture",
      "Track compliance trends",
      "Policy-specific insights",
    ],
  },
  {
    icon: Package,
    title: "App Deployment Monitoring",
    description: "Track application deployment failures and issues.",
    script: "app-deployment-failure-alert",
    benefits: [
      "Ensure app availability",
      "Identify problem apps",
      "Platform-specific metrics",
    ],
  },
];

const setupSteps = [
  {
    number: "01",
    title: "Deploy to Azure",
    description: "Use our templates to deploy scripts to Azure Automation.",
    icon: CloudLightning,
  },
  {
    number: "02",
    title: "Configure thresholds",
    description: "Set monitoring thresholds that match your requirements.",
    icon: AlertTriangle,
  },
  {
    number: "03",
    title: "Add recipients",
    description: "Specify email addresses for notification delivery.",
    icon: Mail,
  },
  {
    number: "04",
    title: "Schedule & relax",
    description: "Scripts run automatically and alert when needed.",
    icon: Calendar,
  },
];

export function NotificationScriptsSection() {
  const prefersReducedMotion = useReducedMotion();
  const enter = prefersReducedMotion ? false : { opacity: 0, y: 12 };
  const animate = { opacity: 1, y: 0 };
  const ease = [0.22, 1, 0.36, 1] as const;
  const viewport = { once: true, margin: "-10% 0px" };

  return (
    <section
      aria-labelledby="notifications-heading"
      className="relative overflow-hidden border-y py-20 sm:py-24 md:py-28"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      {/* Soft blueprint underlay — keeps the section feeling like the same
          system without claiming the hero's signature radial glow. */}
      <div
        aria-hidden="true"
        className="bg-blueprint-soft pointer-events-none absolute inset-0 opacity-40"
      />

      <div className="relative mx-auto max-w-6xl px-4 sm:px-6">
        {/* ─────────────── Opener ─────────────── */}
        <motion.div
          initial={enter}
          whileInView={animate}
          viewport={viewport}
          transition={{ duration: 0.5, ease }}
          className="max-w-3xl"
        >
          <p className="font-mono-label text-accent-hi">
            // Notifications · Azure Automation
          </p>
          <h2
            id="notifications-heading"
            className="font-display text-foreground mt-4 text-3xl leading-[1.05] tracking-[-0.02em] sm:text-4xl md:text-[2.75rem]"
          >
            Proactive monitoring.{" "}
            <span className="text-accent-hi font-semibold">Email alerts.</span>
          </h2>
          <p className="text-muted-foreground mt-5 max-w-2xl text-base leading-relaxed sm:text-lg">
            Stay ahead of issues with monitoring scripts that send email
            notifications when your Intune environment needs attention.
          </p>

          <div className="mt-6 flex flex-wrap items-center gap-1.5">
            <MetaPill
              icon={CloudLightning}
              label="Azure Automation"
              accent="azure"
            />
            <MetaPill icon={Mail} label="Email notifications" />
            <MetaPill icon={Calendar} label="Scheduled" />
            <MetaPill icon={AlertTriangle} label="Threshold-based" />
          </div>
        </motion.div>

        {/* ─────────────── Features grid ─────────────── */}
        <div className="mt-16">
          <motion.p
            initial={enter}
            whileInView={animate}
            viewport={viewport}
            transition={{ duration: 0.5, ease, delay: 0.05 }}
            className="font-mono-label text-muted-foreground mb-6"
          >
            // Available scripts
          </motion.p>

          <div className="grid gap-4 md:grid-cols-2">
            {features.map((feature, index) => {
              const Icon = feature.icon;
              return (
                <motion.article
                  key={feature.script}
                  initial={enter}
                  whileInView={animate}
                  viewport={viewport}
                  transition={{
                    duration: 0.5,
                    ease,
                    delay: 0.05 * index,
                  }}
                  className="bg-card/40 group rounded-md border p-6 backdrop-blur-md transition-[transform,border-color] duration-200 hover:-translate-y-0.5"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <div className="flex items-start justify-between gap-3">
                    <Icon
                      className="text-accent-hi h-5 w-5 shrink-0"
                      aria-hidden="true"
                      strokeWidth={2}
                    />
                    <ArrowUpRight
                      className="text-muted-foreground group-hover:text-accent-hi h-4 w-4 shrink-0 transition-all group-hover:-translate-y-px"
                      aria-hidden="true"
                    />
                  </div>

                  <h3 className="font-display text-foreground mt-4 text-lg leading-tight tracking-[-0.01em]">
                    {feature.title}
                  </h3>
                  <p className="text-muted-foreground mt-2 text-sm leading-relaxed">
                    {feature.description}
                  </p>

                  <ul className="mt-4 space-y-1.5">
                    {feature.benefits.map((benefit) => (
                      <li
                        key={benefit}
                        className="text-muted-foreground flex items-start gap-2 text-sm"
                      >
                        <CheckCircle2
                          className="text-accent-hi mt-0.5 h-3.5 w-3.5 shrink-0"
                          aria-hidden="true"
                          strokeWidth={2}
                        />
                        <span>{benefit}</span>
                      </li>
                    ))}
                  </ul>

                  <div
                    className="mt-5 flex items-center justify-between border-t pt-4"
                    style={{ borderColor: "var(--brand-rule)" }}
                  >
                    <Link
                      href={`/script/${feature.script}/`}
                      className="focus-visible:ring-accent text-muted-foreground hover:text-accent-hi inline-flex items-center gap-1.5 rounded-sm font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none"
                    >
                      View script
                      <ArrowUpRight className="h-3 w-3" aria-hidden="true" />
                    </Link>
                  </div>
                </motion.article>
              );
            })}
          </div>
        </div>

        {/* ─────────────── How it works ─────────────── */}
        <motion.div
          initial={enter}
          whileInView={animate}
          viewport={viewport}
          transition={{ duration: 0.5, ease }}
          className="mt-20"
        >
          <p className="font-mono-label text-muted-foreground mb-6">// Setup</p>
          <h3 className="font-display text-foreground text-2xl leading-tight tracking-[-0.02em] sm:text-3xl">
            Four steps to live monitoring.
          </h3>

          <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {setupSteps.map((step, index) => {
              const Icon = step.icon;
              return (
                <motion.div
                  key={step.number}
                  initial={enter}
                  whileInView={animate}
                  viewport={viewport}
                  transition={{
                    duration: 0.5,
                    ease,
                    delay: 0.05 * index,
                  }}
                  className="bg-card/40 rounded-md border p-5 backdrop-blur-md"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <div className="flex items-center justify-between">
                    <p className="text-accent-hi font-mono text-[11px] tracking-[0.18em] uppercase">
                      {step.number}
                    </p>
                    <Icon
                      className="text-muted-foreground h-4 w-4"
                      aria-hidden="true"
                      strokeWidth={2}
                    />
                  </div>
                  <h4 className="font-display text-foreground mt-3 text-base leading-snug tracking-[-0.01em]">
                    {step.title}
                  </h4>
                  <p className="text-muted-foreground mt-2 text-sm leading-relaxed">
                    {step.description}
                  </p>
                </motion.div>
              );
            })}
          </div>
        </motion.div>

        {/* ─────────────── CTA ─────────────── */}
        <motion.div
          initial={enter}
          whileInView={animate}
          viewport={viewport}
          transition={{ duration: 0.5, ease, delay: 0.1 }}
          className="bg-card/40 mt-20 rounded-lg border p-8 backdrop-blur-md sm:p-10"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <div className="flex flex-col items-start gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div className="max-w-xl">
              <p className="font-mono-label text-accent-hi flex items-center gap-2">
                <Bell className="h-3 w-3" aria-hidden="true" />
                Ready to enable monitoring?
              </p>
              <h3 className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em]">
                Pick a script and ship it to Azure.
              </h3>
              <p className="text-muted-foreground mt-3 text-sm leading-relaxed">
                Every notification script ships with an Azure deployment
                template. One click, zero infrastructure code.
              </p>
            </div>

            <div className="flex flex-col gap-2 sm:flex-row">
              <Link
                href="/scripts/notification/"
                className="ring-accent bg-foreground text-background focus-visible:ring-offset-background inline-flex h-11 items-center justify-center gap-2 rounded-md px-5 text-sm font-medium transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                Browse notification scripts
                <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
              </Link>
              <a
                href="https://github.com/ugurkocde/intuneautomation/tree/main/scripts/notification"
                target="_blank"
                rel="noopener noreferrer"
                className="border-border/70 hover:border-accent/40 hover:text-foreground text-muted-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-11 items-center justify-center gap-2 rounded-md border px-4 text-sm font-medium transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                View documentation
              </a>
            </div>
          </div>
        </motion.div>

        {/* ─────────────── Info note ─────────────── */}
        <motion.aside
          initial={enter}
          whileInView={animate}
          viewport={viewport}
          transition={{ duration: 0.5, ease, delay: 0.15 }}
          className="bg-card/40 mt-8 rounded-md border p-5 backdrop-blur-md"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <div className="flex gap-3">
            <AlertTriangle
              className="text-accent-hi h-4 w-4 shrink-0 translate-y-0.5"
              aria-hidden="true"
              strokeWidth={2}
            />
            <div>
              <p className="font-mono-label text-muted-foreground">
                // Requirements
              </p>
              <ul className="text-muted-foreground mt-2 space-y-1 text-sm leading-relaxed">
                <li>
                  Azure Automation account with a system-assigned managed
                  identity.
                </li>
                <li>Email delivery via Microsoft Graph Mail API.</li>
                <li>Scripts include error handling and structured logging.</li>
                <li>Thresholds and schedules are fully configurable.</li>
              </ul>
            </div>
          </div>
        </motion.aside>
      </div>
    </section>
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
      className="inline-flex h-6 items-center gap-1.5 rounded-sm border px-2 font-mono text-[10px] font-medium tracking-[0.14em] uppercase"
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
