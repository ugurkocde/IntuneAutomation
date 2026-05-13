// Companion tools section — v3 bento.
// Asymmetric 3-card grid: IntuneBrew flagship (2/3) + IntuneGet + TenuVault.
// Each card carries a custom inline monogram and a platform-specific chrome
// (macOS terminal / Windows titlebar / snapshot timeline). Plausible analytics preserved.

"use client";

import { motion, useReducedMotion } from "framer-motion";
import { ArrowUpRight } from "lucide-react";

/* -------------------------------------------------------------------------- */
/*  Data                                                                       */
/* -------------------------------------------------------------------------- */

interface CompanionProject {
  id: string;
  name: string;
  platform: string;
  description: string;
  link: string;
  ariaSummary: string;
}

const PROJECTS: Record<"brew" | "get" | "vault", CompanionProject> = {
  brew: {
    id: "01",
    name: "IntuneBrew",
    platform: "MACOS",
    description:
      "macOS Intune deployment via Homebrew. Package and ship Mac apps without leaving the terminal.",
    link: "https://IntuneBrew.com",
    ariaSummary: "macOS Intune deployment via Homebrew",
  },
  get: {
    id: "02",
    name: "IntuneGet",
    platform: "WINDOWS",
    description:
      "Windows app management and deployment automation for streamlined fleet packaging.",
    link: "https://IntuneGet.com",
    ariaSummary: "Windows app management and deployment automation",
  },
  vault: {
    id: "03",
    name: "TenuVault",
    platform: "BACKUP · RESTORE",
    description:
      "Tenant-level backup and restore for Microsoft Intune. Snapshot policies, profiles, and apps — roll back when something breaks.",
    link: "https://TenuVault.com",
    ariaSummary: "Backup and restore for Microsoft Intune tenants",
  },
};

/* -------------------------------------------------------------------------- */
/*  Plausible analytics                                                        */
/* -------------------------------------------------------------------------- */

type PlausibleWindow = Window & {
  plausible?: (
    event: string,
    options?: { props?: Record<string, string> },
  ) => void;
};

function trackProjectClick(project: CompanionProject) {
  if (typeof window === "undefined") return;
  const w = window as PlausibleWindow;
  w.plausible?.("Project Click", {
    props: {
      project: project.name,
      location: "ecosystem-section",
    },
  });
}

/* -------------------------------------------------------------------------- */
/*  Section                                                                    */
/* -------------------------------------------------------------------------- */

export default function EcosystemSection() {
  const prefersReducedMotion = useReducedMotion();

  const reveal = (index: number) => ({
    initial: prefersReducedMotion
      ? { opacity: 1, y: 0 }
      : { opacity: 0, y: 12 },
    whileInView: { opacity: 1, y: 0 },
    viewport: { once: true, margin: "-80px" } as const,
    transition: {
      duration: prefersReducedMotion ? 0 : 0.6,
      delay: prefersReducedMotion ? 0 : index * 0.1,
      ease: [0.22, 1, 0.36, 1] as const,
    },
  });

  return (
    <section
      aria-labelledby="ecosystem-heading"
      className="bg-background relative px-4 py-16 sm:py-20"
    >
      {/* Subtle ambient glow anchored center-right to echo the hero atmosphere */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute top-1/2 right-[6%] -z-0 h-[320px] w-[320px] -translate-y-1/2 rounded-full opacity-12 blur-3xl dark:opacity-25"
        style={{
          background:
            "radial-gradient(circle at center, color-mix(in oklab, var(--brand-accent) 14%, transparent) 0%, transparent 65%)",
        }}
      />

      <div className="relative mx-auto max-w-6xl">
        {/* Opener — compact mono kicker + headline + one-line lead */}
        <div className="mb-8 flex flex-col gap-3 sm:mb-10 sm:flex-row sm:items-end sm:justify-between sm:gap-8">
          <div className="max-w-2xl">
            <p className="font-mono-label text-accent-hi mb-3">
              // Companion tools
            </p>
            <h2
              id="ecosystem-heading"
              className="font-display text-foreground text-2xl leading-[1.1] tracking-[-0.02em] sm:text-3xl md:text-[2rem]"
            >
              Companion tools from{" "}
              <a
                href="https://ugurlabs.com"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-accent-hi underline decoration-[color:var(--brand-rule)] decoration-2 underline-offset-[6px] transition-colors hover:decoration-[color:var(--brand-accent)]"
              >
                UgurLabs
              </a>
              .
            </h2>
          </div>
          <p className="text-muted-foreground max-w-sm text-sm leading-relaxed sm:text-right">
            Three open-source tools that pair with IntuneAutomation — packaging,
            deployment, and tenant backup.
          </p>
        </div>

        {/* Bento grid — compact: smaller min-heights, no forced aspect ratio */}
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3 md:grid-rows-2">
          {/* Flagship — IntuneBrew, spans 2 cols × 2 rows */}
          <motion.div {...reveal(0)} className="md:col-span-2 md:row-span-2">
            <BentoCard project={PROJECTS.brew} flagship>
              <BrewMonogram />
              <TerminalChrome />
            </BentoCard>
          </motion.div>

          {/* Top-right — IntuneGet */}
          <motion.div {...reveal(1)} className="md:col-span-1 md:row-span-1">
            <BentoCard project={PROJECTS.get}>
              <GetMonogram />
              <WindowsChrome />
            </BentoCard>
          </motion.div>

          {/* Bottom-right — TenuVault */}
          <motion.div {...reveal(2)} className="md:col-span-1 md:row-span-1">
            <BentoCard project={PROJECTS.vault}>
              <VaultMonogram />
              <VaultChrome />
            </BentoCard>
          </motion.div>
        </div>
      </div>

      {/* Card-level keyframes — monogram pulse on hover */}
      <style jsx>{`
        :global(.bento-card:hover .bento-monogram) {
          animation: bento-pulse 600ms ease-out;
        }
        @keyframes bento-pulse {
          0% {
            transform: scale(1);
          }
          50% {
            transform: scale(1.04);
          }
          100% {
            transform: scale(1);
          }
        }
        @media (prefers-reduced-motion: reduce) {
          :global(.bento-card:hover .bento-monogram) {
            animation: none;
          }
        }
      `}</style>
    </section>
  );
}

/* -------------------------------------------------------------------------- */
/*  BentoCard — link-wrapped surface with monogram + chrome slots              */
/* -------------------------------------------------------------------------- */

function BentoCard({
  project,
  flagship = false,
  children,
}: {
  project: CompanionProject;
  flagship?: boolean;
  children: React.ReactNode;
}) {
  // Children are: [monogram, chrome]. Render via React.Children for clarity.
  const childArray = Array.isArray(children) ? children : [children];
  const monogram = childArray[0];
  const chrome = childArray[1];

  return (
    <a
      href={project.link}
      target="_blank"
      rel="noopener noreferrer"
      onClick={() => trackProjectClick(project)}
      aria-label={`${project.name} — ${project.ariaSummary} (opens in new tab)`}
      className={[
        "bento-card group bg-card/40 relative flex h-full w-full flex-col overflow-hidden rounded-lg border backdrop-blur-md",
        "transition-[transform,border-color,background-color] duration-150 ease-out",
        "hover:bg-card/60 hover:-translate-y-0.5",
        "focus-visible:ring-offset-background focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-2 focus-visible:outline-none",
        flagship
          ? "min-h-[280px] md:min-h-[320px]"
          : "min-h-[150px] md:min-h-[156px]",
      ].join(" ")}
      style={{
        borderColor: "var(--brand-rule)",
      }}
    >
      {/* Hover border tint — implemented as a pseudo overlay so it doesn't
       * fight the base border color on transition. */}
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 rounded-lg border opacity-0 transition-opacity duration-200 group-hover:opacity-100"
        style={{
          borderColor:
            "color-mix(in oklab, var(--brand-accent) 40%, transparent)",
        }}
      />

      {/* ── Top half — monogram + meta ───────────────────────────────────── */}
      <div
        className={[
          "relative flex flex-1 flex-col",
          flagship ? "p-5 sm:p-6" : "p-4 sm:p-5",
        ].join(" ")}
      >
        {/* Top row: monogram (left) + arrow (right) */}
        <div className="flex items-start justify-between">
          <div
            className="bento-monogram inline-flex origin-center items-center justify-center"
            style={{ color: "var(--brand-accent-hi)" }}
            aria-hidden="true"
          >
            {monogram}
          </div>

          <ArrowUpRight
            className="text-foreground/70 h-5 w-5 opacity-50 transition-all duration-200 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 group-hover:opacity-100"
            aria-hidden="true"
            strokeWidth={1.5}
          />
        </div>

        {/* Spacer pushes title block toward bottom of the top region */}
        <div className="flex-1" />

        {/* Title block */}
        <div className="mt-6 flex flex-col gap-2">
          <span
            className="text-accent font-mono text-[11px] tracking-[0.18em]"
            aria-hidden="true"
          >
            {project.id}
          </span>
          <h3
            className={[
              "font-display text-foreground leading-[1.05] tracking-[-0.02em]",
              flagship ? "text-3xl sm:text-[2.25rem]" : "text-2xl",
            ].join(" ")}
          >
            {project.name}
          </h3>
          <p className="font-mono-label text-accent-hi">{project.platform}</p>
          <p
            className={[
              "text-muted-foreground leading-relaxed",
              flagship ? "mt-2 max-w-md text-[15px]" : "mt-1 text-[13.5px]",
            ].join(" ")}
          >
            {project.description}
          </p>
        </div>
      </div>

      {/* ── Bottom half — platform chrome ────────────────────────────────── */}
      <div
        className={[
          "relative w-full shrink-0 border-t",
          flagship ? "h-[40%]" : "h-[50%]",
        ].join(" ")}
        style={{ borderColor: "var(--brand-rule)" }}
        aria-hidden="true"
      >
        {chrome}
      </div>
    </a>
  );
}

/* -------------------------------------------------------------------------- */
/*  Monograms — inline SVG, 64×64, currentColor-driven                         */
/* -------------------------------------------------------------------------- */

function BrewMonogram() {
  // Geometric "B" with a small tap-handle silhouette below.
  return (
    <svg
      width="44"
      height="44"
      viewBox="0 0 64 64"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.25"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {/* B body — two stacked half-rounds on a vertical spine */}
      <path d="M16 10 L16 46" />
      <path d="M16 10 L32 10 A 9 9 0 0 1 32 28 L 16 28" />
      <path d="M16 28 L34 28 A 9 9 0 0 1 34 46 L 16 46" />
      {/* Tap handle silhouette — short vertical stem + cap */}
      <path d="M40 50 L40 58" />
      <path d="M36 58 L44 58" />
      <circle cx="40" cy="48" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

function GetMonogram() {
  // Bracketed [G] — terminal-style, angular brackets around a sans capital G.
  return (
    <svg
      width="44"
      height="44"
      viewBox="0 0 64 64"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.25"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {/* Left bracket */}
      <path d="M14 12 L8 12 L8 52 L14 52" />
      {/* Right bracket */}
      <path d="M50 12 L56 12 L56 52 L50 52" />
      {/* Capital G — arc with horizontal crossbar */}
      <path d="M40 22 A 12 12 0 1 0 40 42" />
      <path d="M40 32 L40 42 L32 42" />
    </svg>
  );
}

function VaultMonogram() {
  // A stylized "V" sitting inside a vault outline — the door frame implies
  // security/backup without being a literal padlock.
  return (
    <svg
      width="44"
      height="44"
      viewBox="0 0 64 64"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.25"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {/* Vault frame */}
      <rect x="8" y="10" width="48" height="44" rx="3" />
      {/* Inner door rule */}
      <line x1="14" y1="14" x2="14" y2="50" />
      {/* V glyph */}
      <path d="M22 18 L32 46 L42 18" />
      {/* Vault dial */}
      <circle cx="48" cy="32" r="3.25" fill="currentColor" stroke="none" />
      <line x1="48" y1="32" x2="51" y2="29" stroke="currentColor" />
    </svg>
  );
}

/* -------------------------------------------------------------------------- */
/*  Platform chrome — minimal HTML+CSS evocations                              */
/* -------------------------------------------------------------------------- */

function TerminalChrome() {
  // Faux macOS terminal — monochrome traffic lights via brand-rule.
  return (
    <div className="flex h-full flex-col">
      {/* Title bar */}
      <div
        className="flex items-center gap-3 border-b px-4 py-2"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <div className="flex items-center gap-1.5">
          <span
            className="block h-2.5 w-2.5 rounded-full"
            style={{
              background:
                "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
            }}
          />
          <span
            className="block h-2.5 w-2.5 rounded-full"
            style={{
              background:
                "color-mix(in oklab, var(--brand-rule) 55%, transparent)",
            }}
          />
          <span
            className="block h-2.5 w-2.5 rounded-full"
            style={{
              background:
                "color-mix(in oklab, var(--brand-rule) 30%, transparent)",
            }}
          />
        </div>
        <span className="text-muted-foreground/80 truncate font-mono text-[11px] tracking-tight">
          ~/intunebrew · brew install
        </span>
      </div>

      {/* Terminal body */}
      <div className="flex flex-1 flex-col gap-1.5 overflow-hidden px-4 py-3 font-mono text-[12px] leading-relaxed">
        <span className="text-muted-foreground/70">
          # Push Microsoft 365 to your Mac fleet
        </span>
        <span className="text-foreground/85">
          <span className="text-accent-hi">$</span> brew install --cask
          office-365
        </span>
        <span className="text-muted-foreground/70">
          ==&gt; Downloading https://officecdn.microsoft.com…
        </span>
        <span className="text-muted-foreground/70">
          ==&gt; Uploading to Intune as macOS LOB app
        </span>
        <span className="text-accent">
          ✓ Assigned to group: All-Macs · 1,284 devices
        </span>
      </div>
    </div>
  );
}

function WindowsChrome() {
  // Faux Windows titlebar — neutral, no literal blue.
  return (
    <div className="flex h-full flex-col">
      {/* Title bar */}
      <div
        className="flex items-center justify-between border-b px-3 py-1.5"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <span className="text-muted-foreground/85 truncate font-mono text-[10.5px] tracking-tight">
          intuneget.exe
        </span>
        <div className="text-muted-foreground/70 flex items-center gap-2 font-mono text-[11px] leading-none">
          <span aria-hidden="true">—</span>
          <span aria-hidden="true">▢</span>
          <span aria-hidden="true">×</span>
        </div>
      </div>

      {/* Body */}
      <div className="flex flex-1 flex-col gap-1 overflow-hidden px-3 py-2.5 font-mono text-[11px] leading-relaxed">
        <span className="text-muted-foreground/70">
          PS C:\fleet&gt; intuneget pack vlc
        </span>
        <span className="text-foreground/85">packaging vlc-3.0.20.msi …</span>
        <span className="text-accent">✓ uploaded · ready to assign</span>
      </div>
    </div>
  );
}

function VaultChrome() {
  // Snapshot timeline — vertical list of tenant backup entries with timestamps
  // and sizes, reading as a real backup history. The latest snapshot is
  // accented; older ones decay in opacity.
  const snapshots: Array<{
    when: string;
    label: string;
    size: string;
    live?: boolean;
  }> = [
    {
      when: "TODAY 02:00",
      label: "policies + apps",
      size: "184 MB",
      live: true,
    },
    { when: "YESTERDAY", label: "config profiles", size: "127 MB" },
    { when: "5 DAYS AGO", label: "full tenant", size: "412 MB" },
  ];

  return (
    <div className="flex h-full flex-col justify-center gap-2 px-4 pt-3 pb-4">
      <div className="flex items-center justify-between">
        <span className="text-muted-foreground font-mono text-[9.5px] tracking-[0.16em] uppercase">
          ↻ Snapshots
        </span>
        <span className="text-muted-foreground font-mono text-[9.5px] tracking-[0.16em] uppercase">
          tenant · contoso
        </span>
      </div>

      <ul className="flex flex-col gap-1.5">
        {snapshots.map((snap, i) => (
          <li
            key={snap.when}
            className="flex items-baseline justify-between gap-2 font-mono text-[10px] leading-snug"
            style={{ opacity: 1 - i * 0.18 }}
          >
            <span className="flex items-baseline gap-1.5">
              <span
                aria-hidden="true"
                className="inline-block h-1 w-1 shrink-0 translate-y-[-1px] rounded-full"
                style={{
                  backgroundColor: snap.live
                    ? "var(--brand-accent)"
                    : "var(--brand-rule)",
                }}
              />
              <span className="text-foreground/85">{snap.when}</span>
              <span className="text-muted-foreground hidden sm:inline">
                · {snap.label}
              </span>
            </span>
            <span className="text-muted-foreground shrink-0">{snap.size}</span>
          </li>
        ))}
      </ul>

      <p className="text-accent mt-1 font-mono text-[9.5px] tracking-[0.16em] uppercase">
        ✓ restore point available
      </p>
    </div>
  );
}
