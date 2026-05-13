"use client";

// FullScriptGallery v4 — page chrome for /scripts/.
// Surface vocabulary inherited from hero + script-card v4:
//   - mono `// SECTION` kickers in accent-hi
//   - Geist font-display headlines, no gradient text
//   - hairline-bordered panels via var(--brand-rule), rounded-md / rounded-lg
//   - mono uppercase tag pills (cyan-hi border + text-accent-hi when active)
//   - search input mirrors the v4 search-dialog field treatment
//   - sort + pagination use semantic tokens, mono labels
// Card rendering itself is unchanged — ScriptCard is already v4 and owns its
// own surface. We only style the OUTER wrapper + filter chrome.
//
// Strict useScripts contracts preserved:
//   - searchQuery/setSearchQuery bidirectional binding (shared with search-dialog)
//   - selectedTags/toggleTag (shared filter state)
//   - setSelectedScript + setIsDetailOpen open the modal
//   - handleScriptClick dispatches `scriptViewed` window event
//   - handleScriptClick pushes `/script/{slug}/` to history
//   - AnalyticsService.trackScriptView fire-and-forget per card click

import type React from "react";

import { useState, useEffect, useRef, useMemo } from "react";
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
  X,
} from "lucide-react";
import Link from "next/link";

type SortOption = "views" | "recent" | "alphabetical" | "downloads";

const SORT_OPTIONS: { value: SortOption; label: string }[] = [
  { value: "views", label: "Most viewed" },
  { value: "downloads", label: "Most downloaded" },
  { value: "recent", label: "Recently updated" },
  { value: "alphabetical", label: "Alphabetical" },
];

const SCRIPTS_PER_PAGE = 12;

export default function FullScriptGallery() {
  const {
    allScripts,
    filteredScripts,
    selectedScript,
    setSelectedScript,
    searchQuery,
    setSearchQuery,
    selectedTags,
    toggleTag,
    setSelectedTags,
    isDetailOpen,
    setIsDetailOpen,
    isLoading,
    error,
    refetchScripts,
    updateScriptStats,
  } = useScripts();

  const [localSearch, setLocalSearch] = useState(searchQuery);
  const [sortBy, setSortBy] = useState<SortOption>("views");
  const [sortOpen, setSortOpen] = useState(false);
  const [currentPage, setCurrentPage] = useState(0);
  const hasHandledInitialUrl = useRef(false);
  const prefersReducedMotion = useReducedMotion();

  // Keep local input mirrored to provider state (provider is the source of
  // truth — `filteredScripts` is derived from `searchQuery`).
  useEffect(() => {
    setLocalSearch(searchQuery);
  }, [searchQuery]);

  // Per-tag counts (mono pills surface real counts next to the tag name).
  const tagCounts = useMemo(() => {
    const map = new Map<ScriptTag, number>();
    for (const script of allScripts) {
      for (const tag of script.tags) {
        map.set(tag, (map.get(tag) ?? 0) + 1);
      }
    }
    return map;
  }, [allScripts]);

  // Sort the already-filtered scripts.
  const sortedScripts = useMemo(() => {
    const copy = [...filteredScripts];
    copy.sort((a, b) => {
      switch (sortBy) {
        case "views":
          return (
            (b.usageStats?.totalViews ?? 0) - (a.usageStats?.totalViews ?? 0)
          );
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

  const totalPages = Math.max(
    1,
    Math.ceil(sortedScripts.length / SCRIPTS_PER_PAGE),
  );
  const currentScripts = sortedScripts.slice(
    currentPage * SCRIPTS_PER_PAGE,
    (currentPage + 1) * SCRIPTS_PER_PAGE,
  );

  // Reset to first page when filters / sort change.
  useEffect(() => {
    setCurrentPage(0);
  }, [filteredScripts.length, sortBy]);

  // Close sort dropdown on outside click.
  useEffect(() => {
    if (!sortOpen) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as Element | null;
      if (target && !target.closest("[data-sort-menu]")) setSortOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [sortOpen]);

  // Initial deep-link handling + popstate sync.
  useEffect(() => {
    if (!hasHandledInitialUrl.current && typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      const scriptParam = params.get("script");
      if (scriptParam) {
        const script = filteredScripts.find(
          (s) =>
            s.id === scriptParam ||
            s.slug === scriptParam ||
            s.title.toLowerCase().replace(/\s+/g, "-") === scriptParam,
        );
        if (script) {
          setSelectedScript(script);
          setIsDetailOpen(true);
        }
      }
      hasHandledInitialUrl.current = true;
    }

    const handlePopState = () => {
      const params = new URLSearchParams(window.location.search);
      const scriptParam = params.get("script");
      if (scriptParam) {
        const script = filteredScripts.find(
          (s) =>
            s.id === scriptParam ||
            s.slug === scriptParam ||
            s.title.toLowerCase().replace(/\s+/g, "-") === scriptParam,
        );
        if (script && script !== selectedScript) {
          setSelectedScript(script);
          setIsDetailOpen(true);
        }
      } else if (selectedScript) {
        setSelectedScript(null);
        setIsDetailOpen(false);
      }
    };

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, [filteredScripts, selectedScript, setSelectedScript, setIsDetailOpen]);

  // Mirror selected script to URL for shareable state.
  useEffect(() => {
    if (selectedScript && isDetailOpen) {
      const scriptSlug = selectedScript.slug || selectedScript.id;
      window.history.pushState(null, "", `?script=${scriptSlug}`);
    } else if (!isDetailOpen && selectedScript === null) {
      window.history.pushState(null, "", "/scripts/");
    }
  }, [selectedScript, isDetailOpen]);

  // Card click — preserves all analytics + URL contracts.
  const handleScriptClick = (script: Script) => {
    updateScriptStats(script.id, "view");
    window.dispatchEvent(new Event("scriptViewed"));

    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? (sessionStorage.getItem("session_id") ?? undefined)
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

  // Debounced-ish search: we push every keystroke directly to provider since
  // it is already O(filtered) and the dataset is small.
  const handleSearchChange = (value: string) => {
    setLocalSearch(value);
    setSearchQuery(value);
  };

  const totalCount = allScripts.length;
  const filtersActive = selectedTags.length > 0 || searchQuery.length > 0;

  const scrollToResults = () => {
    const el = document.getElementById("scripts-results");
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  return (
    <section
      id="scripts-section"
      className="container mx-auto max-w-7xl px-4 pt-16 pb-20 sm:px-6 sm:pt-20"
    >
      {/* ─────────────── Page header ─────────────── */}
      <header className="mb-12">
        <p className="font-mono-label text-accent-hi">
          // Library · {totalCount > 0 ? totalCount : "—"} scripts
        </p>
        <h1 className="font-display text-foreground mt-4 text-[clamp(2.25rem,5vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
          Every script in the{" "}
          <span className="text-accent-hi font-semibold">library.</span>
        </h1>
        <p className="text-muted-foreground mt-5 max-w-2xl text-base leading-relaxed sm:text-lg">
          The complete catalog of open-source PowerShell scripts for Microsoft
          Intune — run locally or deploy as Azure Automation runbooks. Filter by
          tag, search, sort.
        </p>

        {/* Status row — surfaced inline rather than centered to keep the
            header rhythm intact. */}
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
                  Failed to fetch scripts from GitHub.
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
            onChange={(e) => handleSearchChange(e.target.value)}
            placeholder="search filename, tag, description..."
            aria-label="Search scripts"
            className="placeholder:text-muted-foreground/70 text-foreground flex h-14 w-full bg-transparent text-[15px] outline-none"
          />
          {localSearch && (
            <button
              type="button"
              onClick={() => handleSearchChange("")}
              className="text-muted-foreground hover:text-foreground focus-visible:ring-accent inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-sm transition-colors focus-visible:ring-1 focus-visible:outline-none"
              aria-label="Clear search"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          )}
          <kbd className="border-border/70 text-muted-foreground hidden h-5 shrink-0 items-center rounded border px-1.5 font-mono text-[10px] opacity-80 select-none sm:inline-flex">
            /
          </kbd>
        </div>

        {/* Tag pill row (horizontally scrollable) */}
        <div
          className="border-b px-5 py-3"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <div
            className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
            role="group"
            aria-label="Filter by tag"
          >
            {allTags.map((tag) => {
              const active = selectedTags.includes(tag);
              const count = tagCounts.get(tag) ?? 0;
              return (
                <TagPill
                  key={tag}
                  tag={tag}
                  count={count}
                  active={active}
                  onClick={() => toggleTag(tag)}
                />
              );
            })}
          </div>
        </div>

        {/* Sort + filter-summary row */}
        <div className="flex flex-col gap-3 px-5 py-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
              {filtersActive ? (
                <>
                  {selectedTags.length > 0 && (
                    <>
                      {selectedTags.length} tag
                      {selectedTags.length === 1 ? "" : "s"}
                    </>
                  )}
                  {selectedTags.length > 0 && searchQuery.length > 0 && " · "}
                  {searchQuery.length > 0 && "search"}
                  {" · "}
                  {sortedScripts.length} result
                  {sortedScripts.length === 1 ? "" : "s"}
                </>
              ) : (
                <>{sortedScripts.length} results</>
              )}
            </p>
            {filtersActive && (
              <button
                type="button"
                onClick={() => {
                  setSelectedTags([]);
                  handleSearchChange("");
                }}
                className="focus-visible:ring-accent text-muted-foreground hover:text-accent-hi inline-flex items-center gap-1 rounded-sm font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none"
              >
                Clear
                <X className="h-3 w-3" aria-hidden="true" />
              </button>
            )}
          </div>

          {/* Sort dropdown */}
          <div className="relative" data-sort-menu>
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
      <div id="scripts-results">
        {isLoading ? (
          <LoadingState />
        ) : sortedScripts.length === 0 ? (
          <EmptyState
            onClear={() => {
              setSelectedTags([]);
              handleSearchChange("");
            }}
          />
        ) : (
          <>
            <motion.div
              key={`${sortBy}-${currentPage}-${selectedTags.join("-")}-${searchQuery}`}
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
                onChange={(page) => {
                  setCurrentPage(page);
                  scrollToResults();
                }}
              />
            )}
          </>
        )}
      </div>

      <AnimatePresence>
        {selectedScript && isDetailOpen && (
          <ScriptDetail
            script={selectedScript}
            updateScriptStats={updateScriptStats}
            onClose={() => {
              setIsDetailOpen(false);
              setSelectedScript(null);
              window.history.pushState(null, "", "/scripts/");
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

function TagPill({
  tag,
  count,
  active,
  onClick,
}: {
  tag: ScriptTag;
  count: number;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      data-tag={tag}
      className={
        "focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-7 shrink-0 items-center gap-2 rounded-sm border px-2.5 font-mono text-[10.5px] font-medium tracking-[0.14em] uppercase transition-colors focus-visible:ring-1 focus-visible:ring-offset-2 focus-visible:outline-none " +
        (active
          ? "border-accent bg-accent-soft text-foreground"
          : "text-accent-hi hover:bg-accent-soft hover:text-foreground")
      }
      style={
        active
          ? undefined
          : {
              borderColor:
                "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
            }
      }
    >
      <span>{tag}</span>
      <span className="text-muted-foreground/70 tabular-nums">{count}</span>
    </button>
  );
}

function LoadingState() {
  return (
    <div
      className="bg-card/40 flex flex-col items-center gap-4 rounded-md border py-16 backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <RefreshCw
        className="text-muted-foreground h-6 w-6 animate-spin"
        aria-hidden="true"
      />
      <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
        Loading scripts from GitHub...
      </p>
    </div>
  );
}

function EmptyState({ onClear }: { onClear: () => void }) {
  return (
    <div
      className="bg-card/40 flex flex-col items-center gap-4 rounded-md border py-16 text-center backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
        No scripts match your filters
      </p>
      <button
        type="button"
        onClick={onClear}
        className="focus-visible:ring-accent text-muted-foreground hover:text-accent-hi inline-flex items-center gap-1.5 rounded-sm font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:outline-none"
      >
        Clear filters
        <span aria-hidden="true">→</span>
      </button>
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

      <div className="flex items-center gap-1">
        {Array.from({ length: totalPages }, (_, i) => {
          const active = i === currentPage;
          return (
            <button
              key={i}
              type="button"
              onClick={() => onChange(i)}
              aria-current={active ? "page" : undefined}
              aria-label={`Page ${i + 1}`}
              className={`focus-visible:ring-accent inline-flex h-9 w-9 items-center justify-center rounded-md border font-mono text-[11px] tracking-wide tabular-nums transition-colors focus-visible:ring-1 focus-visible:outline-none ${
                active
                  ? "text-foreground border-accent bg-accent-soft"
                  : "text-muted-foreground hover:text-foreground hover:border-accent/40 border-border/70"
              }`}
              style={active ? undefined : { borderColor: "var(--brand-rule)" }}
            >
              {i + 1}
            </button>
          );
        })}
      </div>

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
