import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import type { ScriptIndex, ScriptMeta } from "./types.js";

// Source repo/ref can be overridden for forks or testing.
export const REPO = process.env.INTUNE_MCP_REPO ?? "ugurkocde/intuneautomation";
export const BRANCH = process.env.INTUNE_MCP_REF ?? "main";
const INDEX_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/mcp/data/scripts-index.json`;
const INSTRUCTIONS_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/mcp/data/generator-instructions.md`;

const FETCH_TIMEOUT_MS = 10_000;
const CACHE_TTL_MS = 5 * 60 * 1000;

export type IndexSource = "github" | "github (stale cache)" | "bundled";

interface CacheEntry {
  index: ScriptIndex;
  at: number;
  source: IndexSource;
}

let cache: CacheEntry | null = null;

async function fetchJson(url: string): Promise<ScriptIndex> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { Accept: "application/json", "User-Agent": "intuneautomation-mcp" },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} fetching index`);
    return (await res.json()) as ScriptIndex;
  } finally {
    clearTimeout(timer);
  }
}

async function loadBundled(): Promise<ScriptIndex> {
  // dist/catalog.js -> ../data/scripts-index.json (shipped in the package)
  const here = dirname(fileURLToPath(import.meta.url));
  const path = join(here, "..", "data", "scripts-index.json");
  return JSON.parse(await readFile(path, "utf8")) as ScriptIndex;
}

/**
 * Returns the script index. Source of truth is GitHub raw; on network failure
 * we fall back to a stale in-memory cache, then to the index bundled in the
 * package. Cached for CACHE_TTL_MS to avoid refetching on every tool call.
 */
export async function getIndex(force = false): Promise<{ index: ScriptIndex; source: IndexSource }> {
  const now = Date.now();
  if (!force && cache && now - cache.at < CACHE_TTL_MS) {
    return { index: cache.index, source: cache.source };
  }
  try {
    const index = await fetchJson(INDEX_URL);
    cache = { index, at: now, source: "github" };
  } catch {
    if (cache) {
      // Refresh `at` so we serve the stale copy for another TTL cycle instead
      // of re-hitting (and waiting out) the failing fetch on every tool call.
      cache = { ...cache, at: now, source: "github (stale cache)" };
    } else {
      const index = await loadBundled();
      cache = { index, at: now, source: "bundled" };
    }
  }
  return { index: cache.index, source: cache.source };
}

/** Fetch raw PowerShell source for a single script. */
export async function fetchScriptSource(rawUrl: string): Promise<string> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(rawUrl, {
      signal: ctrl.signal,
      headers: { "User-Agent": "intuneautomation-mcp" },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${rawUrl}`);
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

let instructionsCache: { text: string; at: number; source: IndexSource } | null = null;

/**
 * Returns the script-authoring guide (the generator's SYSTEM_PROMPT). Same
 * source-of-truth/fallback strategy as the index: GitHub raw, then stale cache,
 * then the copy bundled in the package.
 */
export async function getInstructions(): Promise<{ text: string; source: IndexSource }> {
  const now = Date.now();
  if (instructionsCache && now - instructionsCache.at < CACHE_TTL_MS) {
    return { text: instructionsCache.text, source: instructionsCache.source };
  }
  try {
    // Same raw-text fetch contract as script source.
    const text = await fetchScriptSource(INSTRUCTIONS_URL);
    instructionsCache = { text, at: now, source: "github" };
  } catch {
    if (instructionsCache) {
      instructionsCache = { ...instructionsCache, at: now, source: "github (stale cache)" };
    } else {
      const here = dirname(fileURLToPath(import.meta.url));
      const text = await readFile(join(here, "..", "data", "generator-instructions.md"), "utf8");
      instructionsCache = { text, at: now, source: "bundled" };
    }
  }
  return { text: instructionsCache.text, source: instructionsCache.source };
}

export function findScript(index: ScriptIndex, id: string): ScriptMeta | undefined {
  const needle = id.trim().toLowerCase().replace(/\.ps1$/, "");
  return index.scripts.find((s) => s.id.toLowerCase() === needle);
}

const FIELD_WEIGHTS: Array<[keyof ScriptMeta | "tagsJoined" | "permsJoined", number]> = [
  ["title", 6],
  ["id", 5],
  ["tagsJoined", 4],
  ["synopsis", 3],
  ["category", 3],
  ["permsJoined", 2],
  ["description", 2],
  ["notes", 1],
];

function haystack(s: ScriptMeta, field: string): string {
  switch (field) {
    case "tagsJoined":
      return s.tags.join(" ").toLowerCase();
    case "permsJoined":
      return s.permissions.join(" ").toLowerCase();
    default:
      return String((s as unknown as Record<string, unknown>)[field] ?? "").toLowerCase();
  }
}

/**
 * Scored full-text search. Every query term must match at least one field
 * (AND semantics); score is the sum of weighted field hits across all terms.
 */
export function searchScripts(index: ScriptIndex, query: string, limit = 10): ScriptMeta[] {
  const terms = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
  if (terms.length === 0) return [];

  const scored: Array<{ s: ScriptMeta; score: number }> = [];
  for (const s of index.scripts) {
    let score = 0;
    let allTermsMatch = true;
    for (const term of terms) {
      let termMatched = false;
      for (const [field, weight] of FIELD_WEIGHTS) {
        if (haystack(s, field as string).includes(term)) {
          score += weight;
          termMatched = true;
        }
      }
      if (!termMatched) {
        allTermsMatch = false;
        break;
      }
    }
    if (allTermsMatch) scored.push({ s, score });
  }

  scored.sort((a, b) => b.score - a.score || a.s.id.localeCompare(b.s.id));
  return scored.slice(0, Math.max(1, limit)).map((x) => x.s);
}

/** Compact summary used in list/search results (omits source-heavy fields). */
export function summarize(s: ScriptMeta) {
  return {
    id: s.id,
    title: s.title,
    synopsis: s.synopsis,
    category: s.category,
    tags: s.tags,
    permissions: s.permissions,
    minRole: s.minRole,
    platform: s.platform || undefined,
    githubUrl: s.githubUrl,
  };
}
