"use client";

// Hero v4, library-shape forward.
// Signature visual: a CategoryMap on the right rendered as a filesystem-tree
// catalog (~/intune-library/ + tag directories with per-tag counts rendered
// server-side and swapped for live numbers once the script list loads). Each
// row is a real link to /scripts/{tag}/. Honest about scale, on-brand with the
// engineering aesthetic, no single script pretends to be "the" canonical one.
// Atmosphere: layered cyan radial glow + grain + masked blueprint grid.
// Typography: three weight-contrasted H1 lines with clip-path reveal on load.
// Trust strip: catalog size, CI validation, GitHub stars, license.
// Custom scroll cue.

import { useCallback, useMemo } from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight, ArrowUpRight, Search, Sparkles } from "lucide-react";
import { useScripts } from "~/components/scripts-provider";
import type { ScriptTag } from "~/lib/scripts";

const REPO_URL = "https://github.com/ugurkocde/IntuneAutomation";

// Plain star formatting: exact below 1k, one decimal with a k suffix above.
function formatStars(count: number): string {
  return count > 1000 ? `${(count / 1000).toFixed(1)}k` : count.toString();
}

export default function HeroSection({
  fallbackCount,
  fallbackTagCounts,
  githubStars,
}: {
  // Build-time catalog count from the server page. Used for SSR and until
  // the live script list loads so the copy never shows a stale number.
  fallbackCount: number;
  // Build-time per-tag counts, keyed by lowercase tag. Same purpose as
  // fallbackCount but for the catalog rows on the right.
  fallbackTagCounts: Record<string, number>;
  // Live repository stars from the server page, null when the fetch failed.
  githubStars: number | null;
}) {
  const { setSearchOpen, allScripts } = useScripts();
  const prefersReducedMotion = useReducedMotion();

  // Real count when scripts have loaded; otherwise the build-time count
  // so the trust strip never renders an empty "scripts" attestation. Both
  // are exact numbers, so neither carries a "+" suffix.
  const scriptsCountLabel = (
    allScripts.length > 0 ? allScripts.length : fallbackCount
  ).toString();

  const handleSearchClick = useCallback(() => {
    setSearchOpen(true);
  }, [setSearchOpen]);

  // Motion choreography. Each block declares its own delay so the timeline is
  // visible at a glance. Front-loaded so the headline paints early; the
  // longest chain (trust strip) settles at about 1.1s.
  const init = prefersReducedMotion ? false : { opacity: 0, y: 12 };
  const animate = { opacity: 1, y: 0 };
  const ease = [0.22, 1, 0.36, 1] as const;
  const t = (delay: number, duration = 0.55) => ({ delay, duration, ease });

  return (
    // The min-height budget subtracts the announcement banner plus the sticky
    // navbar so the whole left column and the scroll cue stay inside the first
    // viewport on a 900px-tall (and 800px-tall) laptop screen.
    <section
      className="relative isolate overflow-hidden lg:flex lg:min-h-[calc(100svh-8rem)] lg:items-center"
      aria-label="IntuneAutomation introduction"
    >
      {/* -------- Atmosphere layers (back to front) -------- */}
      <HeroAtmosphere />

      <div className="relative mx-auto w-full max-w-7xl px-4 pt-16 pb-20 sm:px-6 sm:pt-20 sm:pb-24 lg:py-14">
        <div className="grid grid-cols-1 items-start gap-14 lg:grid-cols-[1.15fr_1fr] lg:items-center lg:gap-20">
          {/* ============================================== */}
          {/* LEFT — typography + CTAs                       */}
          {/* ============================================== */}
          <div className="min-w-0">
            {/* Launch pill — announces the AI Script Generator above the
             * headline. Fades in just before the H1 reveal cascades. Uses
             * the existing v2 mono-uppercase kicker pattern with a cyan
             * accent dot and a small arrow that translates on hover. */}
            <motion.div
              initial={init}
              animate={animate}
              transition={t(0)}
              className="mb-6"
            >
              <Link
                href="/generator/"
                className="border-border/70 hover:border-accent/50 hover:bg-card/60 focus-visible:ring-accent group bg-card/40 text-muted-foreground focus-visible:ring-offset-background inline-flex items-center gap-2.5 rounded-full border py-1.5 pr-2.5 pl-3 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                <span
                  className="inline-block h-1.5 w-1.5 rounded-full"
                  style={{ backgroundColor: "var(--brand-accent)" }}
                  aria-hidden="true"
                />
                <span className="text-foreground">New</span>
                <span className="bg-border/80 h-3 w-px" aria-hidden="true" />
                <Sparkles
                  className="text-accent h-3 w-3"
                  strokeWidth={2}
                  aria-hidden="true"
                />
                <span>Script Generator</span>
                <ArrowRight
                  className="text-muted-foreground group-hover:text-foreground h-3 w-3 transition-transform group-hover:translate-x-0.5"
                  strokeWidth={2}
                  aria-hidden="true"
                />
              </Link>
            </motion.div>

            {/* H1 — three-line weight-contrasted lockup with clip-reveal.
             * Last line uses the muted weight + cyan accent on "production"
             * so the promise lands as the eye finishes the headline. The clamp
             * max is the largest size where "that actually work" still holds a
             * single line in the left column on a laptop, so the lockup stays
             * three lines instead of spilling to four. */}
            <h1 className="font-display text-foreground text-[clamp(2.4rem,7vw,4.75rem)] leading-[0.95]">
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.08}
                weight="normal"
              >
                Intune scripts
              </RevealLine>
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.16}
                weight="display"
              >
                that actually work
              </RevealLine>
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.24}
                weight="muted"
              >
                in{" "}
                <span className="text-accent-hi font-semibold">
                  production.
                </span>
              </RevealLine>
            </h1>

            {/* Lead — citation-ready, AI-engines quotable */}
            <motion.p
              initial={init}
              animate={animate}
              transition={t(0.35)}
              className="text-muted-foreground mt-6 max-w-xl text-base leading-relaxed sm:text-lg"
            >
              {scriptsCountLabel} open-source Intune scripts you can run locally
              or deploy as Azure Automation runbooks without writing any
              infrastructure code.
            </motion.p>

            {/* CTAs: primary has real depth + custom focus; secondary jumps to
             * the how-it-works section; tertiary is the search affordance with
             * the `/` shortcut surfaced. */}
            <motion.div
              initial={init}
              animate={animate}
              transition={t(0.45)}
              className="mt-8 flex flex-row flex-wrap items-center gap-3 sm:gap-4"
            >
              <Link
                href="/scripts/"
                className="group ring-accent bg-foreground text-background focus-visible:ring-offset-background inline-flex h-12 items-center gap-2 rounded-md px-5 text-sm font-medium shadow-[inset_0_1px_0_color-mix(in_oklab,white_18%,transparent),0_8px_22px_-12px_color-mix(in_oklab,var(--brand-accent)_60%,transparent)] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none active:translate-y-0"
              >
                Browse scripts
                <span
                  aria-hidden="true"
                  className="relative inline-block h-4 w-4 overflow-hidden"
                >
                  <ArrowRight className="absolute inset-0 h-4 w-4 transition-transform duration-300 group-hover:translate-x-4 group-hover:-translate-y-4" />
                  <ArrowUpRight className="absolute inset-0 h-4 w-4 -translate-x-4 translate-y-4 transition-transform duration-300 group-hover:translate-x-0 group-hover:translate-y-0" />
                </span>
              </Link>

              <a
                href="#how-it-works"
                className="border-border/70 hover:border-accent/40 group focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-12 items-center gap-2 rounded-md border bg-transparent px-4 text-sm font-medium transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                <span>See how it works</span>
                <span
                  aria-hidden="true"
                  className="text-muted-foreground group-hover:text-foreground transition-[color,transform] group-hover:translate-y-0.5"
                >
                  ↓
                </span>
              </a>

              {/* Tertiary Search affordance — hidden on mobile because the
               * navbar already exposes a search icon at the same width. From
               * sm+ we surface the `/` shortcut hint inline. */}
              <button
                type="button"
                onClick={handleSearchClick}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background hidden h-12 items-center gap-2 rounded-md px-2 text-sm transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none sm:inline-flex"
              >
                <Search className="h-3.5 w-3.5" strokeWidth={2} />
                <span>Search</span>
                <kbd className="border-border/70 text-muted-foreground ml-0.5 inline-flex h-5 items-center rounded border px-1.5 font-mono text-[10px] opacity-80 select-none">
                  /
                </kbd>
              </button>
            </motion.div>

            {/* Trust micro-strip: every attestation links to the artifact that
             * proves it (catalog, CI workflow, repository, license). */}
            <motion.div
              initial={init}
              animate={animate}
              transition={t(0.55)}
              className="text-muted-foreground mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 font-mono text-[11px] tracking-widest uppercase"
            >
              <Link
                href="/scripts/"
                className="hover:text-foreground inline-flex items-center gap-1.5 transition-colors"
              >
                <Dot /> {scriptsCountLabel} scripts
              </Link>
              <a
                href={`${REPO_URL}/actions/workflows/script-analysis.yml`}
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-foreground inline-flex items-center gap-1.5 transition-colors"
              >
                <Dot /> PSScriptAnalyzer validated in CI
              </a>
              <a
                href={REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-foreground inline-flex items-center gap-1.5 transition-colors"
              >
                <Dot />{" "}
                {githubStars === null
                  ? "Open source on GitHub"
                  : `${formatStars(githubStars)} GitHub stars`}
              </a>
              <a
                href={`${REPO_URL}/blob/main/LICENSE`}
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-foreground inline-flex items-center gap-1.5 transition-colors"
              >
                <Dot /> MIT licensed
              </a>
            </motion.div>
          </div>

          {/* ============================================== */}
          {/* RIGHT — Category map                           */}
          {/* The library's shape at a glance. Each tile     */}
          {/* clicks through to a filtered view. Honest about*/}
          {/* scale, no single script pretends to be "the"   */}
          {/* canonical example.                              */}
          {/* ============================================== */}
          <motion.div
            initial={prefersReducedMotion ? false : { opacity: 0, x: 16 }}
            animate={{ opacity: 1, x: 0 }}
            transition={t(0.2, 0.7)}
            className="min-w-0"
          >
            <CategoryMap
              fallbackCount={fallbackCount}
              fallbackTagCounts={fallbackTagCounts}
            />
          </motion.div>
        </div>
      </div>

      {/* Custom scroll cue — hardware-style ready indicator */}
      <ScrollCue />
    </section>
  );
}

/* -------------------------------------------------------------------------- */
/*  Atmosphere layers                                                          */
/* -------------------------------------------------------------------------- */

function HeroAtmosphere() {
  return (
    <>
      {/* Phosphor glow anchored upper-right, drifts subtly.
       * Lower opacity in light mode so cyan reads as warmth, not a teal smudge
       * on cream paper. The dark: variant restores the full intensity. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-32 -right-32 -z-20 h-[680px] w-[680px] rounded-full opacity-30 blur-3xl dark:opacity-70"
      >
        {/* The gradient lives on the drifting child so the keyframes actually
         * move and breathe the glow; the parent only positions and blurs it. */}
        <div
          className="animate-drift h-full w-full rounded-full"
          style={{
            background:
              "radial-gradient(circle at center, color-mix(in oklab, var(--brand-accent) 28%, transparent) 0%, color-mix(in oklab, var(--brand-accent) 12%, transparent) 35%, transparent 70%)",
          }}
        />
      </div>

      {/* Secondary cool glow anchored lower-left, much fainter */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-40 -left-20 -z-20 h-[520px] w-[520px] rounded-full opacity-15 blur-3xl dark:opacity-40"
        style={{
          background:
            "radial-gradient(circle at center, color-mix(in oklab, var(--brand-azure) 18%, transparent) 0%, transparent 65%)",
        }}
      />

      {/* Blueprint grid with radial mask so corners feel infinite */}
      <div
        aria-hidden="true"
        className="bg-blueprint-soft pointer-events-none absolute inset-0 -z-10 opacity-60"
        style={{
          maskImage:
            "radial-gradient(ellipse 90% 70% at 50% 35%, black 35%, transparent 88%)",
          WebkitMaskImage:
            "radial-gradient(ellipse 90% 70% at 50% 35%, black 35%, transparent 88%)",
        }}
      />

      {/* Grain noise — tactile texture. Multiply on light, overlay on dark
       * so the texture reads as ink rather than haze on either canvas. */}
      <div
        aria-hidden="true"
        className="bg-grain pointer-events-none absolute inset-0 -z-10 opacity-[0.03] mix-blend-multiply dark:opacity-[0.04] dark:mix-blend-overlay"
      />

      {/* Bottom hairline rule to mark end of hero section */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute right-0 bottom-0 left-0 h-px"
        style={{ background: "var(--brand-rule)", opacity: 0.5 }}
      />
    </>
  );
}

/* -------------------------------------------------------------------------- */
/*  RevealLine — clip-path mask wipe-reveal for headline lines                 */
/* -------------------------------------------------------------------------- */

function RevealLine({
  children,
  delay,
  weight,
}: {
  children: React.ReactNode;
  delay: number;
  weight: "normal" | "display" | "muted";
}) {
  const reduced = useReducedMotion();
  const weightClass =
    weight === "display"
      ? "font-semibold"
      : weight === "muted"
        ? "text-muted-foreground font-normal"
        : "font-normal";

  return (
    <motion.span
      initial={reduced ? false : { clipPath: "inset(0 100% 0 0)", opacity: 0 }}
      animate={{ clipPath: "inset(0 0% 0 0)", opacity: 1 }}
      transition={{
        delay,
        duration: 0.65,
        ease: [0.22, 1, 0.36, 1],
      }}
      className={`block tracking-[-0.04em] ${weightClass}`}
    >
      {children}
    </motion.span>
  );
}

/* -------------------------------------------------------------------------- */
/*  Dot — tiny cyan indicator used in trust strip                              */
/* -------------------------------------------------------------------------- */

function Dot() {
  return (
    <span
      aria-hidden="true"
      className="inline-block h-1 w-1 rounded-full"
      style={{ backgroundColor: "var(--brand-accent)" }}
    />
  );
}

/* -------------------------------------------------------------------------- */
/*  DottedLeader: CSS-drawn leader between a catalog label and its count       */
/* -------------------------------------------------------------------------- */

function DottedLeader() {
  return (
    <span
      aria-hidden="true"
      className="text-muted-foreground/40 mx-1 flex-1 self-stretch select-none"
      style={{
        // One 1px dot per 8px tile, centered vertically in the row so it
        // tracks the text without relying on a repeated glyph run.
        backgroundImage:
          "radial-gradient(circle, currentColor 1px, transparent 1px)",
        backgroundSize: "8px 100%",
        backgroundRepeat: "repeat-x",
      }}
    />
  );
}

/* -------------------------------------------------------------------------- */
/*  ScrollCue — custom hardware-ready indicator                                */
/* -------------------------------------------------------------------------- */

function ScrollCue() {
  return (
    <div
      aria-hidden="true"
      className="absolute bottom-6 left-1/2 hidden -translate-x-1/2 flex-col items-center gap-2 sm:flex"
    >
      <div className="flex flex-col items-center gap-[3px]">
        <span
          className="pulse-cue h-px w-6"
          style={{
            backgroundColor: "var(--brand-accent)",
            animationDelay: "0s",
          }}
        />
        <span
          className="pulse-cue h-px w-6"
          style={{
            backgroundColor: "var(--brand-accent)",
            animationDelay: "0.4s",
          }}
        />
        <span
          className="pulse-cue h-px w-6"
          style={{
            backgroundColor: "var(--brand-accent)",
            animationDelay: "0.8s",
          }}
        />
      </div>
      <span className="text-muted-foreground font-mono text-[10px] tracking-[0.22em] uppercase">
        Scroll
      </span>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  CategoryMap — the library's shape at a glance.                             */
/*  Each row is a topic directory with a script count, rendered from the       */
/*  server-side catalog counts and swapped for live numbers once the script    */
/*  list arrives, so crawlers and the first paint both see real figures.       */
/*  Clicking a row filters /scripts/ to that tag.                              */
/* -------------------------------------------------------------------------- */

interface CategoryEntry {
  tag: ScriptTag;
  slug: string; // dir-name representation in the catalog tree
}

// Order: the six most-trafficked categories first, then five more. On lg+
// screens we show all 11. Below lg we render only the first 6 + a closing
// "more topics" branch so the catalog stays compact on tablets and phones.
const CATEGORY_TREE: CategoryEntry[] = [
  { tag: "Devices", slug: "devices" },
  { tag: "Compliance", slug: "compliance" },
  { tag: "Apps", slug: "apps" },
  { tag: "Security", slug: "security" },
  { tag: "Reporting", slug: "reporting" },
  { tag: "Operational", slug: "operational" },
  { tag: "Configuration", slug: "configuration" },
  { tag: "Monitoring", slug: "monitoring" },
  { tag: "Diagnostics", slug: "diagnostics" },
  { tag: "Notification", slug: "notification" },
  { tag: "Remediation", slug: "remediation" },
];

const COMPACT_VISIBLE = 6;

function CategoryMap({
  fallbackCount,
  fallbackTagCounts,
}: {
  fallbackCount: number;
  fallbackTagCounts: Record<string, number>;
}) {
  const { allScripts } = useScripts();

  // Live per-tag counts from allScripts. Empty until the list loads, at which
  // point every row swaps from the server-side count to the live one.
  const counts = useMemo(() => {
    const map = new Map<ScriptTag, number>();
    for (const script of allScripts) {
      for (const tag of script.tags) {
        map.set(tag, (map.get(tag) ?? 0) + 1);
      }
    }
    return map;
  }, [allScripts]);

  const totalCount = allScripts.length;
  const countFor = (entry: CategoryEntry) =>
    totalCount > 0
      ? (counts.get(entry.tag) ?? 0)
      : (fallbackTagCounts[entry.slug] ?? 0);
  const compactList = CATEGORY_TREE.slice(0, COMPACT_VISIBLE);
  const moreCategoriesCount = Math.max(
    0,
    CATEGORY_TREE.length - COMPACT_VISIBLE,
  );
  const totalLabel =
    totalCount > 0 ? totalCount.toString() : fallbackCount.toString();

  return (
    <div
      className="bg-card/40 relative overflow-hidden rounded-lg border backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      {/* Header — mono kicker with real total */}
      <div
        className="flex items-center justify-between border-b px-5 py-3"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
          // Library · {totalLabel} scripts
        </p>
        <Link
          href="/scripts/"
          className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 font-mono text-[10px] tracking-[0.18em] uppercase transition-colors"
        >
          All
          <ArrowUpRight className="h-3 w-3" aria-hidden="true" />
        </Link>
      </div>

      {/* Filesystem-tree body — each row is a real `<a>` to the filtered view.
       * Below `lg`: first 6 entries + a "more topics" closing branch (keeps
       * the catalog compact on tablets/phones). On `lg+`: all 11 entries are
       * rendered, the last using a `└──` corner connector. */}
      <div className="px-5 py-5 font-mono text-[13px] leading-[1.9]">
        {/* Root label */}
        <p className="text-muted-foreground select-none">
          ~/intune-library
          <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
        </p>

        {/* Compact tree — visible below lg */}
        <ul className="mt-1.5 lg:hidden">
          {compactList.map((entry) => (
            <CatalogRow
              key={entry.tag}
              entry={entry}
              connector="├──"
              count={countFor(entry)}
            />
          ))}
          <BrowseAllBranch connector="└──" moreCount={moreCategoriesCount} />
        </ul>

        {/* Full tree — visible at lg+ */}
        <ul className="mt-1.5 hidden lg:block">
          {CATEGORY_TREE.map((entry, i) => {
            const isLast = i === CATEGORY_TREE.length - 1;
            return (
              <CatalogRow
                key={entry.tag}
                entry={entry}
                connector={isLast ? "└──" : "├──"}
                count={countFor(entry)}
              />
            );
          })}
        </ul>
      </div>
    </div>
  );
}

function CatalogRow({
  entry,
  connector,
  count,
}: {
  entry: CategoryEntry;
  connector: string;
  count: number;
}) {
  return (
    <li>
      <Link
        href={`/scripts/${entry.slug}/`}
        className="group focus-visible:ring-accent flex items-baseline gap-2 rounded-sm py-0.5 transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-1 focus-visible:outline-none focus-visible:ring-inset"
        aria-label={`Browse ${entry.tag} scripts`}
      >
        <span
          aria-hidden="true"
          className="text-muted-foreground/60 select-none"
        >
          {connector}
        </span>
        <span className="text-foreground group-hover:text-accent-hi transition-colors">
          {entry.slug}
        </span>
        <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
        <DottedLeader />
        <span className="text-foreground tabular-nums">{count}</span>
        <ArrowUpRight
          className="text-muted-foreground group-hover:text-accent-hi h-3 w-3 shrink-0 translate-y-[1px] transition-all group-hover:-translate-y-px"
          aria-hidden="true"
        />
      </Link>
    </li>
  );
}

function BrowseAllBranch({
  connector,
  moreCount,
}: {
  connector: string;
  moreCount: number;
}) {
  return (
    <li>
      <Link
        href="/scripts/"
        className="group focus-visible:ring-accent flex items-baseline gap-2 rounded-sm py-0.5 transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-1 focus-visible:outline-none focus-visible:ring-inset"
      >
        <span
          aria-hidden="true"
          className="text-muted-foreground/60 select-none"
        >
          {connector}
        </span>
        <span className="text-muted-foreground group-hover:text-foreground transition-colors">
          + {moreCount} more topics
        </span>
        <DottedLeader />
        <span className="text-muted-foreground group-hover:text-foreground transition-colors">
          browse all
        </span>
        <ArrowRight
          className="text-muted-foreground group-hover:text-accent-hi h-3 w-3 shrink-0 translate-y-[1px] transition-transform group-hover:translate-x-0.5"
          aria-hidden="true"
        />
      </Link>
    </li>
  );
}
