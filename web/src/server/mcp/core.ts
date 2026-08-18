// Pure catalog logic: search, filtering, aggregation, pagination. No I/O and no
// framework imports so the whole module is unit-testable with a fixture index.
import type { ScriptIndex, ScriptMeta } from "./types.ts";

export const MAX_SEARCH_OFFSET = 500;
export const MAX_CATALOG_OFFSET = 1_000;

export function findScript(
  index: ScriptIndex,
  id: string,
): ScriptMeta | undefined {
  const needle = id
    .trim()
    .toLowerCase()
    .replace(/\.ps1$/, "");
  return index.scripts.find((s) => s.id.toLowerCase() === needle);
}

const FIELD_WEIGHTS: Array<[string, number]> = [
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
      return String(
        (s as unknown as Record<string, unknown>)[field] ?? "",
      ).toLowerCase();
  }
}

export interface ScriptFilters {
  category?: string;
  tag?: string;
  platform?: string;
  permission?: string;
}

/** Exact category match; case-insensitive substring for tag/platform/permission. */
export function filterScripts(
  scripts: ScriptMeta[],
  filters: ScriptFilters,
): ScriptMeta[] {
  let result = scripts;
  if (filters.category) {
    const c = filters.category.trim().toLowerCase();
    result = result.filter((s) => s.category.toLowerCase() === c);
  }
  if (filters.tag) {
    const t = filters.tag.trim().toLowerCase();
    result = result.filter((s) =>
      s.tags.some((x) => x.toLowerCase().includes(t)),
    );
  }
  if (filters.platform) {
    const p = filters.platform.trim().toLowerCase();
    result = result.filter((s) => s.platform.toLowerCase().includes(p));
  }
  if (filters.permission) {
    const perm = filters.permission.trim().toLowerCase();
    result = result.filter((s) =>
      s.permissions.some((x) => x.toLowerCase().includes(perm)),
    );
  }
  return result;
}

/**
 * Scored full-text search. Every query term must match at least one field
 * (AND semantics); score is the sum of weighted field hits across all terms.
 * Without a query, returns the input ordered by id so browsing is deterministic.
 */
export function rankScripts(
  scripts: ScriptMeta[],
  query?: string,
): ScriptMeta[] {
  const terms = query?.toLowerCase().trim().split(/\s+/).filter(Boolean) ?? [];
  if (terms.length === 0) {
    return [...scripts].sort((a, b) => a.id.localeCompare(b.id));
  }

  const scored: Array<{ s: ScriptMeta; score: number }> = [];
  for (const s of scripts) {
    let score = 0;
    let allTermsMatch = true;
    for (const term of terms) {
      let termMatched = false;
      for (const [field, weight] of FIELD_WEIGHTS) {
        if (haystack(s, field).includes(term)) {
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
  return scored.map((x) => x.s);
}

/** Compact summary used in search results (omits source-heavy fields). */
export function summarize(s: ScriptMeta) {
  return {
    id: s.id,
    title: s.title,
    synopsis: s.synopsis,
    category: s.category,
    tags: s.tags,
    permissions: s.permissions,
    minRole: s.minRole,
    platform: s.platform || null,
    runbookEligible: s.runbook?.eligible ?? false,
    githubUrl: s.githubUrl,
  };
}

export type ScriptSummary = ReturnType<typeof summarize>;

/** Full metadata for one script (everything except the source code). */
export function fullMetadata(s: ScriptMeta) {
  return {
    id: s.id,
    title: s.title,
    synopsis: s.synopsis,
    description: s.description,
    category: s.category,
    tags: s.tags,
    permissions: s.permissions,
    minRole: s.minRole,
    platform: s.platform || null,
    author: s.author,
    version: s.version,
    lastUpdate: s.lastUpdate,
    schedule: s.schedule || null,
    execution: s.execution || null,
    output: s.output || null,
    remediationType: s.remediationType || null,
    pairScript: s.pairScript || null,
    parameters: s.parameters.map((p) => ({
      name: p.name,
      type: p.type,
      mandatory: p.mandatory,
      default: p.default ?? null,
      switch: p.switch,
    })),
    examples: s.examples,
    notes: s.notes,
    path: s.path,
    rawUrl: s.rawUrl,
    githubUrl: s.githubUrl,
    runbook: s.runbook ?? null,
    azureDeploy: s.azureDeploy ?? null,
  };
}

export type ScriptMetadata = ReturnType<typeof fullMetadata>;

export type CatalogKind =
  | "categories"
  | "tags"
  | "platforms"
  | "permissions"
  | "minRoles";

/**
 * Aggregates distinct values with usage counts for one metadata dimension.
 * Case-insensitive dedup keeps the first-seen casing. Sorted by count then value.
 */
export function buildCatalog(
  index: ScriptIndex,
  kind: CatalogKind,
): Array<{ value: string; count: number }> {
  const counts = new Map<string, { value: string; count: number }>();
  const add = (raw: string) => {
    const value = raw.trim();
    if (!value) return;
    const key = value.toLowerCase();
    const entry = counts.get(key);
    if (entry) entry.count += 1;
    else counts.set(key, { value, count: 1 });
  };

  for (const s of index.scripts) {
    switch (kind) {
      case "categories":
        add(s.category);
        break;
      case "tags":
        s.tags.forEach(add);
        break;
      case "platforms":
        add(s.platform);
        break;
      case "permissions":
        s.permissions.forEach(add);
        break;
      case "minRoles":
        add(s.minRole);
        break;
    }
  }

  return [...counts.values()].sort(
    (a, b) => b.count - a.count || a.value.localeCompare(b.value),
  );
}

export function nextBoundedOffset(
  offset: number,
  returnedItems: number,
  hasMore: boolean,
  maxOffset: number,
): number | null {
  if (!hasMore || returnedItems === 0) return null;

  const nextOffset = offset + returnedItems;
  return nextOffset <= maxOffset ? nextOffset : null;
}

export function paginateText(
  value: string,
  requestedStart: number,
  maxLength: number,
) {
  const start = Math.min(requestedStart, value.length);
  const end = Math.min(start + maxLength, value.length);

  return {
    value: value.slice(start, end),
    totalCharacters: value.length,
    start,
    nextStart: end < value.length ? end : null,
    truncated: end < value.length || start > 0,
  };
}
