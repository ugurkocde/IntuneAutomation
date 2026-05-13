"use client";

// SearchDialog v4 — Cmd-K / `/` overlay in the library vocabulary.
// Surface: bg-card/40 + backdrop-blur, hairline rule via --brand-rule, rounded-lg.
// Result rows read like catalog entries: mono filename · display title · mono tag pill.
// Keyboard parity preserved (arrow keys via cmdk + Esc to close); analytics fire-and-forget.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { Command } from "cmdk";
import { ArrowUpRight, Search, X } from "lucide-react";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import type { Script, ScriptTag } from "~/lib/scripts";

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

// All script identifiers in the repo end up as `.ps1` filenames; the
// in-app `id` is the slug. We render `${slug}.ps1` as the catalog row's
// monospaced filename — same vocabulary as `~/intune-library/` in the hero.
function filenameFor(script: Script): string {
  return `${script.id}.ps1`;
}

// Tags get rendered as small mono pills. We surface up to 2 per row to keep
// scanability tight; remaining tags collapse to a `+N` indicator.
const VISIBLE_TAGS = 2;

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

export default function SearchDialog() {
  const {
    allScripts,
    isSearchOpen,
    setSearchOpen,
    setSelectedScript,
    setIsDetailOpen,
    searchQuery,
    setSearchQuery,
    selectedTags,
    toggleTag,
    filteredScripts,
    updateScriptStats,
  } = useScripts();

  const prefersReducedMotion = useReducedMotion();
  const inputRef = useRef<HTMLInputElement>(null);
  const [inputValue, setInputValue] = useState(searchQuery);

  // Keep local input mirrored to provider state — provider is the source of truth
  // since `filteredScripts` is derived from `searchQuery`. We push every keystroke.
  useEffect(() => {
    setInputValue(searchQuery);
  }, [searchQuery]);

  const handleInputChange = useCallback(
    (next: string) => {
      setInputValue(next);
      setSearchQuery(next);
    },
    [setSearchQuery],
  );

  // Focus the input shortly after the dialog mounts. The timeout dodges
  // a race with framer-motion's initial render where the node exists but
  // isn't yet focusable in Safari.
  useEffect(() => {
    if (!isSearchOpen) return;
    const id = window.setTimeout(() => inputRef.current?.focus(), 80);
    return () => window.clearTimeout(id);
  }, [isSearchOpen]);

  // Esc to close — kept at document level so it fires even if focus has
  // drifted (e.g., onto a tag pill).
  useEffect(() => {
    if (!isSearchOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setSearchOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [isSearchOpen, setSearchOpen]);

  // Available tags = union of tags from currently-filtered scripts. We sort
  // selected tags first so users see their active filter without scrolling.
  const availableTags = useMemo<ScriptTag[]>(() => {
    const set = new Set<ScriptTag>();
    for (const script of allScripts) {
      for (const tag of script.tags) set.add(tag);
    }
    const all = Array.from(set);
    all.sort((a, b) => {
      const aSel = selectedTags.includes(a) ? 0 : 1;
      const bSel = selectedTags.includes(b) ? 0 : 1;
      if (aSel !== bSel) return aSel - bSel;
      return a.localeCompare(b);
    });
    return all;
  }, [allScripts, selectedTags]);

  // Selection handler — preserves every contract from the original component:
  // 1. update local stats, 2. fire analytics fire-and-forget, 3. open detail
  // modal, 4. push URL state, 5. dispatch scriptViewed window event, 6. close
  // this dialog.
  const handleSelect = useCallback(
    (scriptId: string) => {
      const script = allScripts.find((s) => s.id === scriptId);
      if (!script) return;

      updateScriptStats(script.id, "view");

      const userAgent =
        typeof window !== "undefined" ? navigator.userAgent : undefined;
      const sessionId =
        typeof window !== "undefined"
          ? (sessionStorage.getItem("session_id") ?? undefined)
          : undefined;

      // Fire-and-forget — analytics must never block UX.
      void AnalyticsService.trackScriptView(script.id, script.title, {
        userAgent,
        sessionId,
      }).catch(() => {
        /* swallow — analytics failures are non-blocking */
      });

      setSelectedScript(script);
      setIsDetailOpen(true);
      setSearchOpen(false);

      if (typeof window !== "undefined") {
        window.history.pushState({}, "", `/script/${script.id}/`);
        window.dispatchEvent(new Event("scriptViewed"));
      }
    },
    [
      allScripts,
      setIsDetailOpen,
      setSearchOpen,
      setSelectedScript,
      updateScriptStats,
    ],
  );

  if (!isSearchOpen) return null;

  const totalCount = allScripts.length;
  const resultCount = filteredScripts.length;

  return (
    <AnimatePresence>
      {isSearchOpen && (
        <motion.div
          initial={prefersReducedMotion ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.18 }}
          className="bg-background/60 fixed inset-0 z-50 backdrop-blur-sm"
          onClick={() => setSearchOpen(false)}
          aria-hidden="true"
        >
          {/* Two-layer pattern: outer absolute centers, inner motion handles
              scale/opacity without fighting the translate transform. */}
          <div className="fixed inset-0 z-50 flex items-start justify-center px-4 pt-[12vh] sm:pt-[16vh]">
            <motion.div
              initial={
                prefersReducedMotion
                  ? false
                  : { opacity: 0, y: -8, scale: 0.98 }
              }
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -4, scale: 0.98 }}
              transition={{ duration: 0.18, ease: [0.22, 1, 0.36, 1] }}
              role="dialog"
              aria-modal="true"
              aria-label="Search scripts"
              onClick={(e) => e.stopPropagation()}
              className="bg-card/40 relative w-full max-w-2xl overflow-hidden rounded-lg border shadow-[0_24px_60px_-24px_color-mix(in_oklab,black_60%,transparent)] backdrop-blur-md"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <Command
                loop
                shouldFilter={false}
                className="flex flex-col"
                label="Script search"
              >
                {/* -------------------------------------------------- */}
                {/*  Header strip — mono kicker + esc hint              */}
                {/* -------------------------------------------------- */}
                <div
                  className="flex items-center justify-between border-b px-5 py-3"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <p className="text-accent-hi font-mono text-[11px] font-medium tracking-[0.18em] uppercase">
                    // Search · {totalCount > 0 ? totalCount : "—"} scripts
                  </p>
                  <button
                    type="button"
                    onClick={() => setSearchOpen(false)}
                    className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex items-center gap-1.5 rounded-sm font-mono text-[10px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-1 focus-visible:ring-offset-2 focus-visible:outline-none"
                    aria-label="Close search"
                  >
                    <kbd className="border-border/70 text-muted-foreground inline-flex h-5 items-center rounded border px-1.5 font-mono text-[10px] tracking-normal select-none">
                      ESC
                    </kbd>
                    <ArrowUpRight className="h-3 w-3" aria-hidden="true" />
                  </button>
                </div>

                {/* -------------------------------------------------- */}
                {/*  Input row — no inner border, hairline-separated    */}
                {/* -------------------------------------------------- */}
                <div
                  className="flex items-center gap-3 border-b px-5"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <Search
                    className="text-muted-foreground h-4 w-4 shrink-0"
                    aria-hidden="true"
                    strokeWidth={2}
                  />
                  <Command.Input
                    ref={inputRef}
                    value={inputValue}
                    onValueChange={handleInputChange}
                    placeholder="search filename, tag, description..."
                    className="placeholder:text-muted-foreground/70 text-foreground flex h-14 w-full bg-transparent text-[15px] outline-none disabled:cursor-not-allowed disabled:opacity-50"
                  />
                  {inputValue && (
                    <button
                      type="button"
                      onClick={() => handleInputChange("")}
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

                {/* -------------------------------------------------- */}
                {/*  Tag filter strip — horizontal scrollable mono pills */}
                {/* -------------------------------------------------- */}
                {availableTags.length > 0 && (
                  <div
                    className="border-b px-5 py-3"
                    style={{ borderColor: "var(--brand-rule)" }}
                  >
                    <div
                      className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
                      role="group"
                      aria-label="Filter by tag"
                    >
                      {availableTags.map((tag) => {
                        const active = selectedTags.includes(tag);
                        return (
                          <TagPill
                            key={tag}
                            tag={tag}
                            active={active}
                            onClick={() => toggleTag(tag)}
                          />
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* -------------------------------------------------- */}
                {/*  Result list                                        */}
                {/* -------------------------------------------------- */}
                <Command.List className="max-h-[min(60vh,28rem)] overflow-y-auto py-2">
                  <Command.Empty className="px-5 py-10 text-center">
                    <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
                      No scripts match · Esc to close
                    </p>
                  </Command.Empty>

                  {filteredScripts.map((script) => (
                    <Command.Item
                      key={script.id}
                      value={script.id}
                      onSelect={handleSelect}
                      className="group aria-selected:bg-accent-soft mx-2 flex cursor-pointer items-center gap-4 rounded-sm px-3 py-2.5 text-sm transition-colors"
                    >
                      {/* Left — mono filename. The catalog identity of the row. */}
                      <span
                        className="text-muted-foreground group-aria-selected:text-accent-hi shrink-0 font-mono text-[11px] tracking-wide tabular-nums transition-colors"
                        aria-hidden="true"
                      >
                        {filenameFor(script)}
                      </span>

                      {/* Middle — display title. Truncates before pushing tags off-row. */}
                      <span className="font-display text-foreground min-w-0 flex-1 truncate text-[15px] leading-snug tracking-[-0.01em]">
                        {script.title}
                      </span>

                      {/* Right — up to N mono tag pills + overflow indicator. */}
                      <span className="hidden shrink-0 items-center gap-1.5 sm:inline-flex">
                        {script.tags.slice(0, VISIBLE_TAGS).map((tag) => (
                          <TagBadge key={tag} tag={tag} />
                        ))}
                        {script.tags.length > VISIBLE_TAGS && (
                          <span className="text-muted-foreground/70 font-mono text-[10px] tracking-wide">
                            +{script.tags.length - VISIBLE_TAGS}
                          </span>
                        )}
                      </span>

                      {/* Affordance arrow — appears on hover/keyboard selection. */}
                      <ArrowUpRight
                        className="text-muted-foreground group-aria-selected:text-accent-hi h-3.5 w-3.5 shrink-0 opacity-0 transition-all group-aria-selected:-translate-y-px group-aria-selected:opacity-100"
                        aria-hidden="true"
                      />
                    </Command.Item>
                  ))}
                </Command.List>

                {/* -------------------------------------------------- */}
                {/*  Footer — mono navigation hints + live result count */}
                {/* -------------------------------------------------- */}
                <div
                  className="flex items-center justify-between border-t px-5 py-2.5"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <p className="text-muted-foreground font-mono text-[10px] tracking-[0.18em] uppercase">
                    {resultCount} {resultCount === 1 ? "result" : "results"}
                  </p>
                  <div className="text-muted-foreground hidden items-center gap-3 font-mono text-[10px] tracking-[0.18em] uppercase sm:flex">
                    <span className="inline-flex items-center gap-1">
                      <KbdHint>↑</KbdHint>
                      <KbdHint>↓</KbdHint>
                      navigate
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <KbdHint>↵</KbdHint>
                      open
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <KbdHint>esc</KbdHint>
                      close
                    </span>
                  </div>
                </div>
              </Command>
            </motion.div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-primitives                                                     */
/* ------------------------------------------------------------------ */

function TagPill({
  tag,
  active,
  onClick,
}: {
  tag: ScriptTag;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={
        "focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-6 shrink-0 items-center rounded-sm border px-2 font-mono text-[10px] font-medium tracking-[0.14em] uppercase transition-colors focus-visible:ring-1 focus-visible:ring-offset-2 focus-visible:outline-none " +
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
      {tag}
    </button>
  );
}

function TagBadge({ tag }: { tag: ScriptTag }) {
  return (
    <span
      className="text-accent-hi inline-flex h-5 items-center rounded-sm border px-1.5 font-mono text-[9.5px] font-medium tracking-[0.14em] uppercase"
      style={{
        borderColor: "color-mix(in oklab, var(--brand-rule) 80%, transparent)",
      }}
    >
      {tag}
    </span>
  );
}

function KbdHint({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="border-border/70 text-muted-foreground inline-flex h-4 min-w-4 items-center justify-center rounded border px-1 font-mono text-[9.5px] tracking-normal select-none">
      {children}
    </kbd>
  );
}
