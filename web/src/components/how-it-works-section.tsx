"use client";

// How It Works v2 — editorial-technical pipeline diagram.
// A single SVG flow argues the wedge: one script, two operational paths (local + cloud),
// re-converging on the tenant. Desktop draws a horizontal branching pipeline; mobile
// renders a purpose-built vertical stack. Motion budget: one stroke-dashoffset draw, once.

import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";

export default function HowItWorksSection() {
  const prefersReducedMotion = useReducedMotion();

  return (
    <section
      id="how-it-works"
      aria-labelledby="how-it-works-heading"
      className="bg-blueprint-soft relative overflow-hidden border-y border-border/60 py-20 sm:py-24 md:py-32"
    >
      {/* Atmospheric edge fade so the grid feels printed, not tiled */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-gradient-to-b from-background via-transparent to-background"
      />

      {/* Subtle accent glow anchored behind the convergence node (right side)
       * — ties the section visually to the hero atmosphere. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute top-1/2 right-[8%] -z-0 h-[460px] w-[460px] -translate-y-1/2 rounded-full opacity-20 blur-3xl dark:opacity-50"
        style={{
          background:
            "radial-gradient(circle at center, color-mix(in oklab, var(--brand-accent) 18%, transparent) 0%, transparent 65%)",
        }}
      />

      {/* Tactile grain overlay at 3% opacity — matches the hero. */}
      <div
        aria-hidden="true"
        className="bg-grain pointer-events-none absolute inset-0 opacity-[0.02] mix-blend-multiply dark:opacity-[0.03] dark:mix-blend-overlay"
      />

      <div className="relative mx-auto max-w-6xl px-4 sm:px-6">
        {/* ─────────────── Opener ─────────────── */}
        {/* Chapter divider — giant numeric "02" flush-left, smaller subhead
         * beside it. Breaks the same-volume H2 monotony across the page. */}
        <div className="grid grid-cols-1 items-end gap-6 sm:grid-cols-[auto_1fr] sm:gap-10">
          <p
            aria-hidden="true"
            className="font-display text-foreground/15 leading-[0.8] tracking-[-0.05em] text-[clamp(7rem,18vw,16rem)] dark:text-foreground/10"
          >
            02
          </p>
          <div className="pb-2 sm:pb-6">
            <p className="font-mono-label text-accent-hi">
              // How it works
            </p>
            <h2
              id="how-it-works-heading"
              className="font-display text-foreground mt-4 text-3xl leading-[1.05] tracking-[-0.02em] sm:text-4xl md:text-[2.75rem]"
            >
              Two paths. One outcome.
            </h2>
            <p className="text-muted-foreground mt-4 max-w-xl text-base leading-relaxed sm:text-lg">
              The same PowerShell script runs ad-hoc from your terminal or on
              a schedule as an Azure Automation runbook. Same script. Same
              tenant. Different operational cadence.
            </p>
          </div>
        </div>

        {/* Screen-reader-only plain-language description of the diagram */}
        <ol className="sr-only">
          <li>
            Step 1: You author or pick a PowerShell script from the library.
          </li>
          <li>
            Path A — Local: run it interactively from your shell against the
            Microsoft Graph using your own credentials.
          </li>
          <li>
            Path B — Cloud: deploy it once as an Azure Automation runbook;
            it then runs on a schedule using a managed identity.
          </li>
          <li>
            Both paths converge on the same outcome: changes applied to your
            Intune tenant.
          </li>
        </ol>

        {/* ─────────────── Desktop diagram ─────────────── */}
        <DesktopPipeline reducedMotion={!!prefersReducedMotion} />

        {/* ─────────────── Mobile diagram ─────────────── */}
        <MobilePipeline />

        {/* ─────────────── CTA ─────────────── */}
        <div className="mt-16 flex flex-col items-center gap-2 text-center sm:mt-20">
          <Link
            href="/scripts/"
            className="group inline-flex items-center gap-2 text-base font-medium text-foreground underline decoration-[color:var(--brand-accent)] decoration-2 underline-offset-[6px] transition hover:decoration-[color:var(--brand-accent-hi)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-4 focus-visible:ring-offset-background"
          >
            Browse scripts
            <span
              aria-hidden="true"
              className="text-accent transition-transform group-hover:translate-x-0.5"
            >
              →
            </span>
          </Link>
          <p className="font-mono text-[11px] tracking-wider text-muted-foreground uppercase">
            All scripts ship both paths. No selection required.
          </p>
        </div>
      </div>
    </section>
  );
}

/* -------------------------------------------------------------------------- */
/*  Desktop pipeline — SVG paths + absolutely-positioned HTML node cards.     */
/* -------------------------------------------------------------------------- */

function DesktopPipeline({ reducedMotion }: { reducedMotion: boolean }) {
  // The diagram is laid out in a normalized 1000x320 viewBox. ALL geometry
  // (paths, junction dots, labels) is expressed in those units. The HTML
  // node cards above are positioned with the SAME percentage anchors so
  // the lines connect to card edges instead of running through them.
  //
  //  Column layout (% of width = viewBox x):
  //   ┌──────────────────────────────────────────────────────────────┐
  //   │  origin       gap     local/cloud      gap     tenant         │
  //   │  0%-23%      23-35%   35%-65%         65-77%   77%-100%       │
  //   └──────────────────────────────────────────────────────────────┘
  //  Vertical (% of height = viewBox y):
  //   y=160 — horizontal centerline (origin & tenant cards)
  //   y=60  — top branch centerline (local card)
  //   y=260 — bottom branch centerline (azure card)
  //
  // Lines start exactly at the right edge of the origin card (x=230) and
  // end exactly at the left edge of the tenant card (x=770), bending up
  // and down to pass through the middle-card row.
  const DASH = 1200;
  const initial = reducedMotion ? { strokeDashoffset: 0 } : { strokeDashoffset: DASH };
  const animate = { strokeDashoffset: 0 };

  return (
    <div className="relative mx-auto mt-16 hidden md:block" aria-hidden="true">
      <div className="relative w-full" style={{ aspectRatio: "1000 / 320" }}>
        <svg
          viewBox="0 0 1000 320"
          width="100%"
          height="100%"
          preserveAspectRatio="none"
          role="img"
          aria-label="Diagram: your PowerShell script runs either locally or as an Azure Automation runbook; both paths target your Intune tenant."
          className="absolute inset-0"
        >
          {/* Top branch: origin-right (230,160) → up under local card → tenant-left (770,160).
           * The path passes UNDER the local card; card sits on top, hiding the middle. */}
          <motion.path
            d="M 230 160 C 290 160, 320 60, 410 60 L 590 60 C 680 60, 710 160, 770 160"
            fill="none"
            stroke="var(--brand-accent)"
            strokeOpacity="0.9"
            strokeWidth="1"
            strokeLinecap="round"
            strokeDasharray={DASH}
            initial={initial}
            whileInView={animate}
            viewport={{ once: true, amount: 0.4 }}
            transition={{ duration: 1.1, ease: [0.22, 1, 0.36, 1] }}
          />

          {/* Bottom branch: mirror of top, y=260. */}
          <motion.path
            d="M 230 160 C 290 160, 320 260, 410 260 L 590 260 C 680 260, 710 160, 770 160"
            fill="none"
            stroke="var(--brand-accent)"
            strokeOpacity="0.9"
            strokeWidth="1"
            strokeLinecap="round"
            strokeDasharray={DASH}
            initial={initial}
            whileInView={animate}
            viewport={{ once: true, amount: 0.4 }}
            transition={{
              duration: 1.1,
              delay: reducedMotion ? 0 : 0.15,
              ease: [0.22, 1, 0.36, 1],
            }}
          />

          {/* Junction dots at exact card-edge anchor points */}
          <circle cx="230" cy="160" r="3.5" fill="var(--brand-accent)" />
          <circle cx="770" cy="160" r="3.5" fill="var(--brand-accent)" />

          {/* Branch labels positioned on the BEND segment (before the card),
           * not inside the card area. x=300 sits in the diagonal portion. */}
          <text
            x="300"
            y="112"
            fill="var(--brand-accent-hi)"
            fontFamily="var(--font-geist-mono), monospace"
            fontSize="9"
            letterSpacing="2"
          >
            LOCAL
          </text>
          <text
            x="300"
            y="220"
            fill="var(--brand-accent-hi)"
            fontFamily="var(--font-geist-mono), monospace"
            fontSize="9"
            letterSpacing="2"
          >
            CLOUD
          </text>
        </svg>

        {/* ── Node cards — anchored to the SVG coordinate system ──────────
         *  Cards use the same percentage anchors the SVG uses.
         *  Origin card: width 22%, left:0%   → spans 0-22%  (right edge x=220, line starts x=230 → 10px gap)
         *  Middle cards: width 30%, centered at 50% → spans 35-65%
         *  Tenant card: width 22%, right:0% → spans 78-100% (left edge x=780, line ends x=770 → 10px gap)
         *  Top of middle cards: top:60-px-equivalent centered → so card vertical center matches y=60
         *  → top: (60/320)*100% = 18.75%, transform: translateY(-50%) puts vertical center at y=60.
         */}

        {/* Origin — YOUR SCRIPT (vertically centered) */}
        <NodeCard
          style={{
            left: "0%",
            top: "50%",
            width: "22%",
            transform: "translateY(-50%)",
          }}
          delay={0}
          reducedMotion={reducedMotion}
        >
          <CardLabel>Your script</CardLabel>
          <CardSub>A PowerShell file from the library.</CardSub>
          <CardMeta>
            <span>file: .ps1</span>
            <span>auth: any</span>
          </CardMeta>
          <CardIcon>
            <ScriptGlyph />
          </CardIcon>
        </NodeCard>

        {/* Top branch — LOCAL POWERSHELL (centered on top branch line y=60) */}
        <NodeCard
          style={{
            left: "50%",
            top: "18.75%",
            width: "30%",
            transform: "translate(-50%, -50%)",
          }}
          delay={0.15}
          reducedMotion={reducedMotion}
        >
          <CardLabel>Local PowerShell</CardLabel>
          <CardSub>Run it from your shell.</CardSub>
          <CardMeta>
            <span>auth: interactive</span>
            <span>cadence: on demand</span>
          </CardMeta>
          <CardIcon>
            <TerminalGlyph />
          </CardIcon>
        </NodeCard>

        {/* Bottom branch — AZURE AUTOMATION (centered on bottom branch line y=260) */}
        <NodeCard
          style={{
            left: "50%",
            top: "81.25%",
            width: "30%",
            transform: "translate(-50%, -50%)",
          }}
          delay={0.3}
          reducedMotion={reducedMotion}
          accent="azure"
        >
          <CardLabel>Azure Automation</CardLabel>
          <CardSub>Deploy once, run on schedule.</CardSub>
          <CardMeta>
            <span>auth: managed identity</span>
            <span>cadence: daily 02:00 UTC</span>
          </CardMeta>
          <CardIcon>
            <AzureGlyph />
          </CardIcon>
        </NodeCard>

        {/* Convergence — TENANT (vertically centered) */}
        <NodeCard
          style={{
            right: "0%",
            top: "50%",
            width: "22%",
            transform: "translateY(-50%)",
          }}
          delay={0.45}
          reducedMotion={reducedMotion}
          emphasized
        >
          <CardLabel>Your Intune tenant</CardLabel>
          <CardSub>Changes applied.</CardSub>
          <CardMeta>
            <span>graph: v1.0</span>
            <span>scope: tenant</span>
          </CardMeta>
          <CardIcon>
            <TenantGlyph />
          </CardIcon>
        </NodeCard>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Mobile pipeline — purpose-built vertical layout, NOT a squished desktop.  */
/* -------------------------------------------------------------------------- */

function MobilePipeline() {
  return (
    <div className="mt-16 grid gap-4 md:hidden" aria-hidden="true">
      {/* Origin */}
      <NodeCardStatic>
        <CardLabel>Your script</CardLabel>
        <CardSub>A PowerShell file from the library.</CardSub>
        <CardMeta>
          <span>file: .ps1</span>
          <span>auth: any</span>
        </CardMeta>
      </NodeCardStatic>

      <ArrowDown />

      {/* Two branches side-by-side on mobile */}
      <div className="grid grid-cols-2 gap-3">
        <NodeCardStatic compact>
          <CardLabel>Local</CardLabel>
          <CardSub>Run from your shell.</CardSub>
          <CardMeta>
            <span>on demand</span>
          </CardMeta>
        </NodeCardStatic>
        <NodeCardStatic compact accent="azure">
          <CardLabel>Azure runbook</CardLabel>
          <CardSub>Run on schedule.</CardSub>
          <CardMeta>
            <span>managed identity</span>
          </CardMeta>
        </NodeCardStatic>
      </div>

      {/* Two arrows converging */}
      <div className="grid grid-cols-2 gap-3">
        <ArrowDown />
        <ArrowDown />
      </div>

      <NodeCardStatic emphasized>
        <CardLabel>Your Intune tenant</CardLabel>
        <CardSub>Changes applied.</CardSub>
        <CardMeta>
          <span>graph: v1.0</span>
          <span>scope: tenant</span>
        </CardMeta>
      </NodeCardStatic>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Node card primitives                                                      */
/* -------------------------------------------------------------------------- */

type CardAccent = "default" | "azure";

interface NodeCardProps {
  children: React.ReactNode;
  style?: React.CSSProperties;
  delay?: number;
  reducedMotion?: boolean;
  accent?: CardAccent;
  emphasized?: boolean;
}

function NodeCard({
  children,
  style,
  delay = 0,
  reducedMotion = false,
  accent = "default",
  emphasized = false,
}: NodeCardProps) {
  const borderClass =
    accent === "azure"
      ? "border-[color:var(--brand-azure)]/40"
      : emphasized
        ? "border-[color:var(--brand-accent)]/60"
        : "border-border";

  // Two-layer structure: the outer div owns positioning (top/left/transform
  // for centering on the SVG anchor). The inner motion.div handles the
  // fade-in animation. Framer-motion's `y` transform would otherwise
  // overwrite the centering `translateY(-50%)` and unalign the cards from
  // the SVG branch lines.
  return (
    <div
      style={{
        position: "absolute",
        // Each NodeCard supplies its own width via `style.width` — varies
        // between branch cards (wider) and origin/tenant cards (narrower)
        // so the SVG path endpoints align exactly with card edges.
        ...style,
      }}
    >
      <motion.div
        initial={reducedMotion ? false : { opacity: 0, y: 6 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, amount: 0.4 }}
        transition={{
          duration: 0.4,
          delay: reducedMotion ? 0 : 0.6 + delay,
          ease: [0.22, 1, 0.36, 1],
        }}
        className={`rounded-md border ${borderClass} bg-card/50 p-4 backdrop-blur-md`}
      >
        {children}
      </motion.div>
    </div>
  );
}

function NodeCardStatic({
  children,
  accent = "default",
  emphasized = false,
  compact = false,
}: {
  children: React.ReactNode;
  accent?: CardAccent;
  emphasized?: boolean;
  compact?: boolean;
}) {
  const borderClass =
    accent === "azure"
      ? "border-[color:var(--brand-azure)]/40"
      : emphasized
        ? "border-[color:var(--brand-accent)]/60"
        : "border-border";

  return (
    <div
      className={`rounded-md border ${borderClass} bg-card/50 backdrop-blur-md ${compact ? "p-3" : "p-4"}`}
    >
      {children}
    </div>
  );
}

function CardLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="font-mono text-[11px] font-medium tracking-[0.14em] text-foreground uppercase">
      {children}
    </p>
  );
}

function CardSub({ children }: { children: React.ReactNode }) {
  return (
    <p className="mt-1.5 text-[13px] leading-snug text-muted-foreground">
      {children}
    </p>
  );
}

function CardMeta({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-3 flex flex-col gap-0.5 border-t border-border/60 pt-2 font-mono text-[10.5px] leading-relaxed text-muted-foreground/90">
      {children}
    </div>
  );
}

function CardIcon({ children }: { children: React.ReactNode }) {
  return (
    <div className="absolute top-3 right-3 inline-flex h-5 w-5 items-center justify-center text-muted-foreground/80">
      {children}
    </div>
  );
}

function ArrowDown() {
  return (
    <div className="flex justify-center" aria-hidden="true">
      <span className="font-mono text-base leading-none text-accent">▼</span>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Glyphs                                                                    */
/* -------------------------------------------------------------------------- */

function ScriptGlyph() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" />
      <path d="M14 3v6h6" />
      <path d="M8 13h6" />
      <path d="M8 17h4" />
    </svg>
  );
}

function TerminalGlyph() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <polyline points="4 17 10 11 4 5" />
      <line x1="12" y1="19" x2="20" y2="19" />
    </svg>
  );
}

function AzureGlyph() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M13.3 3 5 21h5.1l1.1-3 5.6.1-2.2-5.1L17 7.6 22 21H10.6L13.3 3Z"
        fill="var(--brand-azure)"
      />
    </svg>
  );
}

function TenantGlyph() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="11" width="18" height="10" rx="1.5" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
      <circle cx="12" cy="16" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  );
}
