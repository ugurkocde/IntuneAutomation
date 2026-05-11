"use client";

// Hero v4 — library-shape forward.
// Signature visual: a CategoryMap on the right rendered as a filesystem-tree
// catalog (~/intune-library/ + tag directories with live script counts). Each
// row is a real link to /scripts/{tag}/. Honest about scale, on-brand with the
// engineering aesthetic, no single script pretends to be "the" canonical one.
// Atmosphere: layered cyan radial glow + grain + masked blueprint grid.
// Typography: three weight-contrasted H1 lines with clip-path reveal on load.
// Custom scroll cue.

import { useCallback, useMemo } from "react";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowRight, ArrowUpRight, Search } from "lucide-react";
import { useScripts } from "~/components/scripts-provider";
import type { ScriptTag } from "~/lib/scripts";


export default function HeroSection() {
  const { setSearchOpen, allScripts } = useScripts();
  const prefersReducedMotion = useReducedMotion();

  // Real count when scripts have loaded; otherwise an honest floor value
  // so the trust strip never renders an empty "scripts" attestation.
  const scriptsCountLabel =
    allScripts.length > 0 ? `${allScripts.length}+` : "120+";

  const handleSearchClick = useCallback(() => {
    setSearchOpen(true);
  }, [setSearchOpen]);

  // Motion choreography. Each block declares its own delay so the timeline is
  // visible at a glance. Total settle under 1.2s.
  const init = prefersReducedMotion ? false : { opacity: 0, y: 12 };
  const animate = { opacity: 1, y: 0 };
  const ease = [0.22, 1, 0.36, 1] as const;
  const t = (delay: number, duration = 0.55) => ({ delay, duration, ease });

  return (
    <section
      className="relative isolate overflow-hidden"
      aria-label="IntuneAutomation introduction"
    >
      {/* -------- Atmosphere layers (back to front) -------- */}
      <HeroAtmosphere />

      <div className="relative mx-auto max-w-7xl px-4 pt-24 pb-20 sm:px-6 sm:pt-28 sm:pb-28 lg:pt-32 lg:pb-32">
        <div className="grid grid-cols-1 items-start gap-14 lg:grid-cols-[1.15fr_1fr] lg:items-center lg:gap-20">
          {/* ============================================== */}
          {/* LEFT — typography + CTAs                       */}
          {/* ============================================== */}
          <div className="min-w-0">

            {/* H1 — three-line weight-contrasted lockup with clip-reveal.
             * Last line uses the muted weight + cyan accent on "production"
             * so the promise lands as the eye finishes the headline. */}
            <h1 className="font-display text-foreground text-[clamp(2.4rem,7vw,6.5rem)] leading-[0.95]">
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.15}
                weight="normal"
              >
                Intune scripts
              </RevealLine>
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.28}
                weight="display"
              >
                that actually work
              </RevealLine>
              <RevealLine
                delay={prefersReducedMotion ? 0 : 0.41}
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
              transition={t(0.58)}
              className="text-muted-foreground mt-8 max-w-xl text-base leading-relaxed sm:text-lg"
            >
              120+ open-source Intune scripts you can run locally or deploy as
              Azure Automation runbooks without writing any infrastructure code.
            </motion.p>

            {/* CTAs — primary has real depth + custom focus; secondary is the
             * GitHub anchor with live star count; tertiary is the search
             * affordance with the `/` shortcut surfaced. */}
            <motion.div
              initial={init}
              animate={animate}
              transition={t(0.7)}
              className="mt-10 flex flex-row flex-wrap items-center gap-3 sm:gap-4"
            >
              <Link
                href="/scripts/"
                className="group ring-accent inline-flex h-12 items-center gap-2 rounded-md bg-foreground px-5 text-sm font-medium text-background shadow-[inset_0_1px_0_color-mix(in_oklab,white_18%,transparent),0_8px_22px_-12px_color-mix(in_oklab,var(--brand-accent)_60%,transparent)] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none active:translate-y-0"
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
                className="border-border/70 hover:border-accent/40 group focus-visible:ring-accent inline-flex h-12 items-center gap-2 rounded-md border bg-transparent px-4 text-sm font-medium transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none"
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
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent hidden h-12 items-center gap-2 rounded-md px-2 text-sm transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none sm:inline-flex"
              >
                <Search className="h-3.5 w-3.5" strokeWidth={2} />
                <span>Search</span>
                <kbd className="border-border/70 text-muted-foreground ml-0.5 inline-flex h-5 items-center rounded border px-1.5 font-mono text-[10px] opacity-80 select-none">
                  /
                </kbd>
              </button>
            </motion.div>

            {/* Trust micro-strip — small linked attestations */}
            <motion.div
              initial={init}
              animate={animate}
              transition={t(0.82)}
              className="text-muted-foreground mt-10 flex flex-wrap items-center gap-x-5 gap-y-2 font-mono text-[11px] tracking-widest uppercase"
            >
              <Link
                href="/scripts/"
                className="hover:text-foreground inline-flex items-center gap-1.5 transition-colors"
              >
                <Dot /> {scriptsCountLabel} scripts
              </Link>
              <span className="inline-flex items-center gap-1.5">
                <Dot /> PSScriptAnalyzer validated in CI
              </span>
            </motion.div>
          </div>

          {/* ============================================== */}
          {/* RIGHT — Category map                           */}
          {/* The library's shape at a glance. Each tile     */}
          {/* clicks through to a filtered view. Honest about*/}
          {/* scale — no single script pretends to be "the"  */}
          {/* canonical example.                              */}
          {/* ============================================== */}
          <motion.div
            initial={prefersReducedMotion ? false : { opacity: 0, x: 16 }}
            animate={{ opacity: 1, x: 0 }}
            transition={t(0.32, 0.7)}
            className="min-w-0"
          >
            <CategoryMap />
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
        style={{
          background:
            "radial-gradient(circle at center, color-mix(in oklab, var(--brand-accent) 28%, transparent) 0%, color-mix(in oklab, var(--brand-accent) 12%, transparent) 35%, transparent 70%)",
        }}
      >
        <div className="animate-drift h-full w-full" />
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
          style={{ backgroundColor: "var(--brand-accent)", animationDelay: "0s" }}
        />
        <span
          className="pulse-cue h-px w-6"
          style={{ backgroundColor: "var(--brand-accent)", animationDelay: "0.4s" }}
        />
        <span
          className="pulse-cue h-px w-6"
          style={{ backgroundColor: "var(--brand-accent)", animationDelay: "0.8s" }}
        />
      </div>
      <span className="font-mono text-[10px] tracking-[0.22em] text-muted-foreground uppercase">
        Scroll
      </span>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  CategoryMap — the library's shape at a glance.                             */
/*  Six topic tiles, each with a live script count and a one-liner. Clicking   */
/*  a tile filters /scripts/ to that tag. Honest about the library being a    */
/*  catalog — no single script pretends to be canonical.                       */
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

function CategoryMap() {
  const { allScripts } = useScripts();

  // Real per-tag counts from allScripts. Falls back to em-dash until loaded.
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
  const compactList = CATEGORY_TREE.slice(0, COMPACT_VISIBLE);
  const moreCategoriesCount = Math.max(
    0,
    CATEGORY_TREE.length - COMPACT_VISIBLE,
  );
  const totalLabel = totalCount > 0 ? totalCount.toString() : "120+";

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
        <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
          // Library · {totalLabel} scripts
        </p>
        <Link
          href="/scripts/"
          className="text-muted-foreground hover:text-foreground font-mono inline-flex items-center gap-1 text-[10px] tracking-[0.18em] uppercase transition-colors"
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
              count={counts.get(entry.tag) ?? null}
            />
          ))}
          <BrowseAllBranch
            connector="└──"
            moreCount={moreCategoriesCount}
          />
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
                count={counts.get(entry.tag) ?? null}
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
  count: number | null;
}) {
  return (
    <li>
      <Link
        href={`/scripts/${entry.slug}/`}
        className="group focus-visible:ring-accent flex items-baseline gap-2 rounded-sm py-0.5 transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-1 focus-visible:ring-inset focus-visible:outline-none"
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
        <span
          aria-hidden="true"
          className="text-muted-foreground/40 mx-1 flex-1 overflow-hidden tracking-[0.18em] select-none"
        >
          ··················································································
        </span>
        <span className="text-foreground tabular-nums">{count ?? "—"}</span>
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
        className="group focus-visible:ring-accent flex items-baseline gap-2 rounded-sm py-0.5 transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-1 focus-visible:ring-inset focus-visible:outline-none"
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
        <span
          aria-hidden="true"
          className="text-muted-foreground/40 mx-1 flex-1 overflow-hidden tracking-[0.18em] select-none"
        >
          ··················································································
        </span>
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

