"use client";

// TagScriptGallery v4 — page chrome for /scripts/[tag]/.
// Same vocabulary as FullScriptGallery, tag-specific:
//   - mono kicker: `// LIBRARY · {TAG} · {N} SCRIPTS`
//   - filesystem-style breadcrumb `~/intune-library/{tag}/` echoes the hero
//     CategoryMap aesthetic
//   - Geist display headline of the tag name with cyan accent on the noun
//   - tag SWITCHER strip lets the user jump to another tag without going back
//   - search input matches v4 search-dialog field treatment
//   - results grid wraps the existing v4 <ScriptCard>; we never restyle the card
//
// Strict useScripts contracts preserved:
//   - allScripts + filteredScripts (we filter further by `tag`, locally)
//   - selectedScript / setSelectedScript / isDetailOpen / setIsDetailOpen modal contract
//   - updateScriptStats + AnalyticsService.trackScriptView fire-and-forget
//   - dispatches `scriptViewed` and pushes `/script/{slug}/` to history on click
//
// NOTE: this gallery uses a LOCAL search state (not the shared provider
// searchQuery) so navigating between /scripts/ and /scripts/{tag}/ does not
// carry a stale query across views — matches prior behaviour.

import type React from "react";
import { useState, useEffect, useMemo, useRef } from "react";
import Link from "next/link";
import { motion, AnimatePresence, useReducedMotion } from "framer-motion";
import { ScriptCard } from "~/components/script-card";
import { ScriptDetail } from "~/components/script-detail";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { allTags, type Script, type ScriptTag } from "~/lib/scripts";
import {
  Search,
  RefreshCw,
  AlertCircle,
  ChevronLeft,
  ChevronRight,
  ArrowLeft,
  X,
} from "lucide-react";

type SortOption = "views" | "recent" | "alphabetical" | "downloads";

const SORT_OPTIONS: { value: SortOption; label: string }[] = [
  { value: "views", label: "Most viewed" },
  { value: "downloads", label: "Most downloaded" },
  { value: "recent", label: "Recently updated" },
  { value: "alphabetical", label: "Alphabetical" },
];

const SCRIPTS_PER_PAGE = 12;

interface TagScriptGalleryProps {
  tag: ScriptTag;
  description: string;
}

export default function TagScriptGallery({
  tag,
  description,
}: TagScriptGalleryProps) {
  const {
    allScripts,
    selectedScript,
    setSelectedScript,
    isDetailOpen,
    setIsDetailOpen,
    isLoading,
    error,
    refetchScripts,
    updateScriptStats,
  } = useScripts();

  const [localSearch, setLocalSearch] = useState("");
  const [sortBy, setSortBy] = useState<SortOption>("views");
  const [sortOpen, setSortOpen] = useState(false);
  const [currentPage, setCurrentPage] = useState(0);
  const prefersReducedMotion = useReducedMotion();
  const sortRef = useRef<HTMLDivElement>(null);

  // Tag-scoped corpus.
  const tagScripts = useMemo(
    () => allScripts.filter((script) => script.tags.includes(tag)),
    [allScripts, tag],
  );

  // Per-tag global counts for the switcher strip.
  const tagCounts = useMemo(() => {
    const map = new Map<ScriptTag, number>();
    for (const script of allScripts) {
      for (const t of script.tags) {
        map.set(t, (map.get(t) ?? 0) + 1);
      }
    }
    return map;
  }, [allScripts]);

  // Local search across the tag-scoped corpus.
  const filteredScripts = useMemo(() => {
    if (!localSearch) return tagScripts;
    const query = localSearch.toLowerCase();
    return tagScripts.filter(
      (script) =>
        script.title.toLowerCase().includes(query) ||
        script.description.toLowerCase().includes(query) ||
        script.tags.some((t) => t.toLowerCase().includes(query)),
    );
  }, [tagScripts, localSearch]);

  const sortedScripts = useMemo(() => {
    const copy = [...filteredScripts];
    copy.sort((a, b) => {
      switch (sortBy) {
        case "views":
          return (b.usageStats?.totalViews ?? 0) - (a.usageStats?.totalViews ?? 0);
        case "downloads":
          return (
            (b.usageStats?.totalDownloads ?? 0) -
            (a.usageStats?.totalDownloads ?? 0)
          );
        case "recent": {
          const aDate = new Date(a.lastUpdated ?? 0).getTime();
          const bDate = new Date(b.lastUpdated ?? 0).getTime();
          if (aDate === bDate) return a.title.localeCompare(b.title);
          return bDate - aDate;
        }
        case "alphabetical":
          return a.title.localeCompare(b.title);
        default:
          return 0;
      }
    });
    return copy;
  }, [filteredScripts, sortBy]);

  const totalPages = Math.max(1, Math.ceil(sortedScripts.length / SCRIPTS_PER_PAGE));
  const currentScripts = sortedScripts.slice(
    currentPage * SCRIPTS_PER_PAGE,
    (currentPage + 1) * SCRIPTS_PER_PAGE,
  );

  useEffect(() => {
    setCurrentPage(0);
  }, [localSearch, sortBy, tag]);

  useEffect(() => {
    if (!sortOpen) return;
    const handler = (e: MouseEvent) => {
      if (sortRef.current && !sortRef.current.contains(e.target as Node)) {
        setSortOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [sortOpen]);

  const handleScriptClick = (script: Script) => {
    updateScriptStats(script.id, "view");
    window.dispatchEvent(new Event("scriptViewed"));

    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? sessionStorage.getItem("session_id") ?? undefined
        : undefined;

    void AnalyticsService.trackScriptView(script.id, script.title, {
      userAgent,
      sessionId,
    }).catch(() => {
      /* swallow — analytics never block UX */
    });

    window.history.pushState(null, "", `/script/${script.slug || script.id}/`);
    setSelectedScript(script);
    setIsDetailOpen(true);
  };

  const tagSlug = tag.toLowerCase();
  const tagCount = tagScripts.length;

  return (
    <section className="container mx-auto max-w-7xl px-4 pt-16 pb-20 sm:px-6 sm:pt-20">
      {/* ─────────────── Page header ─────────────── */}
      <header className="mb-12">
        {/* Filesystem-style breadcrumb echoes the hero CategoryMap */}
        <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
          <Link
            href="/scripts/"
            className="hover:text-accent-hi transition-colors"
          >
            ~/intune-library
          </Link>
          <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
          <span className="text-foreground">{tagSlug}</span>
          <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
        </p>

        <p className="font-mono-label text-accent-hi mt-4">
          // Library · {tag} · {tagCount} script{tagCount === 1 ? "" : "s"}
        </p>

        <h1 className="font-display text-foreground mt-4 text-[clamp(2.25rem,5vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
          <span className="text-accent-hi font-semibold">{tag}</span>{" "}
          <span className="text-muted-foreground font-normal">scripts.</span>
        </h1>

        <p className="text-muted-foreground mt-5 max-w-2xl text-base leading-relaxed sm:text-lg">
          {description}
        </p>

        {/* Back link — mono micro-link, no chunky button */}
        <div className="mt-6">
          <Link
            href="/scripts/"
            className="focus-visible:ring-accent text-muted-foreground hover:text-accent-hi inline-flex items-center gap-1.5 font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none rounded-sm"
          >
            <ArrowLeft className="h-3 w-3" aria-hidden="true" />
            All scripts
          </Link>
        </div>

        {error && (
          <div
            className="bg-card/40 mt-6 flex items-start gap-3 rounded-md border p-4 backdrop-blur-md"
            style={{ borderColor: "var(--brand-rule)" }}
            role="alert"
          >
            <AlertCircle
              className="text-destructive h-4 w-4 shrink-0 translate-y-0.5"
              aria-hidden="true"
            />
            <div className="flex flex-1 items-center justify-between gap-3">
              <p className="text-sm">
                <span className="text-foreground font-medium">
                  Failed to fetch scripts.
                </span>{" "}
                <span className="text-muted-foreground">{error}</span>
              </p>
              <button
                type="button"
                onClick={refetchScripts}
                className="focus-visible:ring-accent text-muted-foreground hover:text-foreground inline-flex shrink-0 items-center gap-1.5 font-mono text-[10px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none"
              >
                <RefreshCw className="h-3 w-3" aria-hidden="true" />
                Retry
              </button>
            </div>
          </div>
        )}
      </header>

      {/* ─────────────── Filter chrome ─────────────── */}
      <div
        className="bg-card/40 mb-10 rounded-lg border backdrop-blur-md"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        {/* Search row */}
        <div
          className="flex items-center gap-3 border-b px-5"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <Search
            className="text-muted-foreground h-4 w-4 shrink-0"
            aria-hidden="true"
            strokeWidth={2}
          />
          <input
            type="text"
            value={localSearch}
            onChange={(e) => setLocalSearch(e.target.value)}
            placeholder={`search ${tag} scripts...`}
            aria-label={`Search ${tag} scripts`}
            className="placeholder:text-muted-foreground/70 text-foreground flex h-14 w-full bg-transparent text-[15px] outline-none"
          />
          {localSearch && (
            <button
              type="button"
              onClick={() => setLocalSearch("")}
              className="text-muted-foreground hover:text-foreground focus-visible:ring-accent inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-sm transition-colors focus-visible:ring-1 focus-visible:outline-none"
              aria-label="Clear search"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          )}
        </div>

        {/* Tag switcher — selecting another tag navigates to its page */}
        <div
          className="border-b px-5 py-3"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <div
            className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
            role="group"
            aria-label="Switch to another tag"
          >
            {allTags.map((t) => {
              const active = t === tag;
              const count = tagCounts.get(t) ?? 0;
              return (
                <TagSwitch
                  key={t}
                  tag={t}
                  count={count}
                  active={active}
                />
              );
            })}
          </div>
        </div>

        {/* Result count + sort */}
        <div className="flex flex-col gap-3 px-5 py-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
            {sortedScripts.length} result{sortedScripts.length === 1 ? "" : "s"}
            {localSearch && (
              <>
                {" · "}
                search:{" "}
                <span className="text-foreground">"{localSearch}"</span>
              </>
            )}
          </p>

          <div className="relative" ref={sortRef}>
            <button
              type="button"
              onClick={() => setSortOpen((v) => !v)}
              aria-haspopup="listbox"
              aria-expanded={sortOpen}
              className="focus-visible:ring-accent border-border/70 hover:border-accent/40 hover:text-foreground text-muted-foreground inline-flex items-center gap-2 rounded-md border px-3 py-1.5 font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <span className="text-muted-foreground/80">Sort</span>
              <span className="text-foreground">
                {SORT_OPTIONS.find((o) => o.value === sortBy)?.label}
              </span>
              <ChevronRight
                className={`h-3 w-3 transition-transform ${sortOpen ? "rotate-90" : ""}`}
                aria-hidden="true"
              />
            </button>

            <AnimatePresence>
              {sortOpen && (
                <motion.ul
                  initial={prefersReducedMotion ? false : { opacity: 0, y: -4 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -4 }}
                  transition={{ duration: 0.12, ease: [0.22, 1, 0.36, 1] }}
                  role="listbox"
                  className="bg-card/95 absolute top-full right-0 z-30 mt-2 w-56 overflow-hidden rounded-md border backdrop-blur-md"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  {SORT_OPTIONS.map((opt) => {
                    const active = sortBy === opt.value;
                    return (
                      <li key={opt.value}>
                        <button
                          type="button"
                          role="option"
                          aria-selected={active}
                          onClick={() => {
                            setSortBy(opt.value);
                            setSortOpen(false);
                          }}
                          className={`hover:bg-accent-soft flex w-full items-center justify-between gap-2 px-3 py-2 text-left font-mono text-[11px] tracking-[0.14em] uppercase transition-colors ${
                            active
                              ? "text-accent-hi"
                              : "text-muted-foreground hover:text-foreground"
                          }`}
                        >
                          <span>{opt.label}</span>
                          {active && (
                            <span
                              aria-hidden="true"
                              className="inline-block h-1 w-1 rounded-full"
                              style={{
                                backgroundColor: "var(--brand-accent-hi)",
                              }}
                            />
                          )}
                        </button>
                      </li>
                    );
                  })}
                </motion.ul>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>

      {/* ─────────────── Results grid ─────────────── */}
      {isLoading ? (
        <LoadingState tag={tag} />
      ) : sortedScripts.length === 0 ? (
        <EmptyState
          message={
            localSearch
              ? `No ${tag} scripts match "${localSearch}".`
              : `No ${tag} scripts available yet.`
          }
          onClear={localSearch ? () => setLocalSearch("") : undefined}
        />
      ) : (
        <>
          <motion.div
            key={`${sortBy}-${currentPage}-${localSearch}-${tag}`}
            initial={prefersReducedMotion ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.25 }}
            className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
          >
            {currentScripts.map((script) => (
              <ScriptCard
                key={script.id}
                script={script}
                onClick={() => handleScriptClick(script)}
              />
            ))}
          </motion.div>

          {totalPages > 1 && (
            <Pagination
              currentPage={currentPage}
              totalPages={totalPages}
              onChange={setCurrentPage}
            />
          )}
        </>
      )}

      <AnimatePresence>
        {selectedScript && isDetailOpen && (
          <ScriptDetail
            script={selectedScript}
            updateScriptStats={updateScriptStats}
            onClose={() => {
              setIsDetailOpen(false);
              setSelectedScript(null);
              window.history.pushState(null, "", `/scripts/${tagSlug}/`);
            }}
          />
        )}
      </AnimatePresence>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-primitives                                                     */
/* ------------------------------------------------------------------ */

function TagSwitch({
  tag,
  count,
  active,
}: {
  tag: ScriptTag;
  count: number;
  active: boolean;
}) {
  const slug = tag.toLowerCase();
  // Active = render as a static span so we don't link to ourselves.
  if (active) {
    return (
      <span
        aria-current="page"
        className="inline-flex h-7 shrink-0 items-center gap-2 rounded-sm border bg-accent-soft border-accent text-foreground px-2.5 font-mono text-[10.5px] font-medium tracking-[0.14em] uppercase"
      >
        <span>{tag}</span>
        <span className="text-muted-foreground/70 tabular-nums">{count}</span>
      </span>
    );
  }
  return (
    <Link
      href={`/scripts/${slug}/`}
      className="focus-visible:ring-accent inline-flex h-7 shrink-0 items-center gap-2 rounded-sm border px-2.5 font-mono text-[10.5px] font-medium tracking-[0.14em] uppercase transition-colors text-accent-hi hover:bg-accent-soft hover:text-foreground focus-visible:ring-1 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none"
      style={{
        borderColor:
          "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
      }}
    >
      <span>{tag}</span>
      <span className="text-muted-foreground/70 tabular-nums">{count}</span>
    </Link>
  );
}

function LoadingState({ tag }: { tag: ScriptTag }) {
  return (
    <div
      className="bg-card/40 flex flex-col items-center gap-4 rounded-md border py-16 backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <RefreshCw
        className="text-muted-foreground h-6 w-6 animate-spin"
        aria-hidden="true"
      />
      <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
        Loading {tag} scripts...
      </p>
    </div>
  );
}

function EmptyState({
  message,
  onClear,
}: {
  message: string;
  onClear?: () => void;
}) {
  return (
    <div
      className="bg-card/40 flex flex-col items-center gap-4 rounded-md border py-16 text-center backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <p className="text-muted-foreground text-sm">{message}</p>
      {onClear && (
        <button
          type="button"
          onClick={onClear}
          className="focus-visible:ring-accent text-muted-foreground hover:text-accent-hi inline-flex items-center gap-1.5 font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none rounded-sm"
        >
          Clear search
          <span aria-hidden="true">→</span>
        </button>
      )}
    </div>
  );
}

function Pagination({
  currentPage,
  totalPages,
  onChange,
}: {
  currentPage: number;
  totalPages: number;
  onChange: (page: number) => void;
}) {
  return (
    <nav
      aria-label="Pagination"
      className="mt-10 flex items-center justify-center gap-2"
    >
      <button
        type="button"
        onClick={() => onChange(currentPage - 1)}
        disabled={currentPage === 0}
        className="focus-visible:ring-accent border-border/70 text-muted-foreground hover:text-foreground hover:border-accent/40 inline-flex h-9 items-center gap-1.5 rounded-md border px-3 font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-40"
        style={{ borderColor: "var(--brand-rule)" }}
        aria-label="Previous page"
      >
        <ChevronLeft className="h-3.5 w-3.5" aria-hidden="true" />
        Prev
      </button>

      <span className="font-mono text-muted-foreground inline-flex h-9 items-center px-2 text-[11px] tabular-nums tracking-[0.18em] uppercase">
        {currentPage + 1} / {totalPages}
      </span>

      <button
        type="button"
        onClick={() => onChange(currentPage + 1)}
        disabled={currentPage === totalPages - 1}
        className="focus-visible:ring-accent border-border/70 text-muted-foreground hover:text-foreground hover:border-accent/40 inline-flex h-9 items-center gap-1.5 rounded-md border px-3 font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-40"
        style={{ borderColor: "var(--brand-rule)" }}
        aria-label="Next page"
      >
        Next
        <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
      </button>
    </nav>
  );
}
