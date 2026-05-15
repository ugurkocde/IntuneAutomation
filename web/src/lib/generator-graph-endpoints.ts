// Path-template matcher for Microsoft Graph endpoints.
//
// Compiles the flat `METHOD /path/template` catalog from generator-graph-data
// into a per-method array of regexes. Each `{paramName}` segment becomes a
// `[^/?#]+` capture so concrete URIs like `/users/abc-123` match the template
// `/users/{id}`.
//
// The compiled matchers are cached at module scope — first call pays the
// (small) regex-compile cost, subsequent calls are O(templates) per lookup.

import { GRAPH_ENDPOINTS } from "./generator-graph-data";

type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

type CompiledEndpoint = {
  template: string;
  regex: RegExp;
  segmentCount: number;
};

let compiled: Map<Method, CompiledEndpoint[]> | null = null;
let templatesByMethod: Map<Method, string[]> | null = null;

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function templateToRegex(path: string): RegExp {
  // Replace `{name}` segments with a non-slash, non-query, non-fragment match.
  // OData function-call notation like `/users('id')` is rare in our scripts —
  // we treat the literal segment as-is and accept the small false-negative.
  const pattern = path
    .split("/")
    .map((seg) =>
      seg.includes("{") && seg.includes("}")
        ? // Template segment may have surrounding literal text (e.g. `me({id})`)
          // but the catalog uses bare `{id}` segments overwhelmingly. Treat the
          // whole segment as a placeholder.
          "[^/?#]+"
        : escapeRegex(seg),
    )
    .join("/");
  return new RegExp("^" + pattern + "$");
}

function ensureCompiled(): {
  compiled: Map<Method, CompiledEndpoint[]>;
  templatesByMethod: Map<Method, string[]>;
} {
  if (compiled && templatesByMethod) return { compiled, templatesByMethod };
  const out: Map<Method, CompiledEndpoint[]> = new Map();
  const tpl: Map<Method, string[]> = new Map();
  for (const entry of GRAPH_ENDPOINTS) {
    const spaceIdx = entry.indexOf(" ");
    if (spaceIdx < 0) continue;
    const method = entry.slice(0, spaceIdx).toUpperCase() as Method;
    const path = entry.slice(spaceIdx + 1);
    if (!path.startsWith("/")) continue;
    let list = out.get(method);
    if (!list) {
      list = [];
      out.set(method, list);
    }
    list.push({
      template: path,
      regex: templateToRegex(path),
      segmentCount: path.split("/").filter(Boolean).length,
    });
    let tlist = tpl.get(method);
    if (!tlist) {
      tlist = [];
      tpl.set(method, tlist);
    }
    tlist.push(path);
  }
  compiled = out;
  templatesByMethod = tpl;
  return { compiled, templatesByMethod };
}

// Catalog paths are stored without a `/v1.0` or `/beta` version prefix —
// scripts use the prefix in their literal URIs. Strip it so the matcher
// sees a uniform `/users/{id}` regardless of API version.
function stripVersion(path: string): string {
  return path.replace(/^\/(v1\.0|beta)(?=\/)/, "");
}

export function isKnownGraphEndpoint(method: string, path: string): boolean {
  const { compiled } = ensureCompiled();
  const list = compiled.get(method.toUpperCase() as Method);
  if (!list) return false;
  const normalized = stripVersion(path);
  return list.some((e) => e.regex.test(normalized));
}

// Cheap segment-overlap similarity. Higher = closer. Used to surface a few
// concrete candidate replacements when the model hallucinated an endpoint.
function similarity(a: string, b: string): number {
  const aSegs = a.toLowerCase().split("/").filter(Boolean);
  const bSegs = b.toLowerCase().split("/").filter(Boolean);
  let common = 0;
  const bSet = new Set(bSegs.map((s) => s.replace(/^\{.*\}$/, "")));
  for (const s of aSegs) {
    if (bSet.has(s.replace(/^\{.*\}$/, ""))) common++;
  }
  // Penalize big length differences so /users doesn't dominate matches for
  // /deviceManagement/managedDevices/{id}/wipe.
  const lengthPenalty =
    Math.abs(aSegs.length - bSegs.length) / Math.max(aSegs.length, 1);
  return common - lengthPenalty;
}

export function suggestGraphEndpoints(
  method: string,
  path: string,
  limit = 3,
): string[] {
  const { templatesByMethod } = ensureCompiled();
  const list = templatesByMethod.get(method.toUpperCase() as Method);
  if (!list || list.length === 0) return [];
  const normalized = stripVersion(path);
  return list
    .map((tpl) => ({ tpl, score: similarity(normalized, tpl) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .filter((x) => x.score > 0)
    .map((x) => `${method.toUpperCase()} ${x.tpl}`);
}

// Result for the lint rule. `matched` is false when the URI doesn't correspond
// to a known endpoint; `wrongVersion` is true when the script uses /v1.0 — the
// generator's policy is to always use /beta for the full Intune surface.
export type EndpointCheck = {
  method: string;
  uri: string;
  path: string;
  matched: boolean;
  wrongVersion: boolean;
  suggestions: string[];
};

function pathVersion(path: string): "v1.0" | "beta" | "unknown" {
  if (path.startsWith("/v1.0/")) return "v1.0";
  if (path.startsWith("/beta/")) return "beta";
  return "unknown";
}

// Extract every `https://graph.microsoft.com/{v1.0|beta}/...` URI literal from
// the script body, paired with its inferred HTTP method (default GET; overridden
// by a `-Method <VERB>` token on the SAME line, which catches the canonical
// single-line `Invoke-MgGraphRequest -Uri ... -Method POST` pattern without
// bleeding methods between unrelated calls).
//
// Heuristics:
//   - URIs with `$variable` interpolations are skipped — we can't know the
//     final path at lint time
//   - Method detection is scoped to the line containing the URI literal
export function extractGraphEndpointUsages(
  scriptBody: string,
): { method: string; uri: string; path: string }[] {
  const usages: { method: string; uri: string; path: string }[] = [];
  // Match either single or double quoted Graph URIs. Spaces are allowed inside
  // the URI body because PowerShell strings routinely contain unencoded OData
  // query params like `?$filter=operatingSystem eq 'macOS'`. We only break on
  // the MATCHING closing quote (via backreference, so the inner `'macOS'`
  // inside a double-quoted URI doesn't terminate the match early) and on an
  // embedded newline (`.` doesn't match `\n` in JS regex by default).
  const uriRe =
    /(["'])https:\/\/graph\.microsoft\.com\/(?:v1\.0|beta)\/.*?\1/g;
  for (const match of scriptBody.matchAll(uriRe)) {
    const raw = match[0].slice(1, -1); // strip quotes
    const url = stripQueryAndFragment(raw);
    const path = url.replace(/^https:\/\/graph\.microsoft\.com/, "");
    // PowerShell variable interpolation in the path means the final URI is
    // not known statically — skip. We only check `$` in the path (OData
    // query params like `?$select=` are legitimate and write as `` ?`$select= ``
    // in PowerShell double-quoted strings, which we don't want to bail on).
    if (path.includes("$")) continue;
    const idx = match.index ?? 0;
    const lineStart = scriptBody.lastIndexOf("\n", idx - 1) + 1;
    const nextNewline = scriptBody.indexOf("\n", idx);
    const lineEnd = nextNewline === -1 ? scriptBody.length : nextNewline;
    const line = scriptBody.slice(lineStart, lineEnd);
    const methodMatch = line.match(
      /-Method\s+["']?(GET|POST|PUT|PATCH|DELETE)["']?/i,
    );
    const method = (methodMatch?.[1] ?? "GET").toUpperCase();
    usages.push({ method, uri: raw, path });
  }
  return usages;
}

function stripQueryAndFragment(url: string): string {
  const q = url.indexOf("?");
  const f = url.indexOf("#");
  let end = url.length;
  if (q >= 0) end = Math.min(end, q);
  if (f >= 0) end = Math.min(end, f);
  return url.slice(0, end);
}

export function checkGraphEndpoints(scriptBody: string): EndpointCheck[] {
  return extractGraphEndpointUsages(scriptBody).map((u) => {
    const matched = isKnownGraphEndpoint(u.method, u.path);
    return {
      method: u.method,
      uri: u.uri,
      path: u.path,
      matched,
      wrongVersion: pathVersion(u.path) === "v1.0",
      suggestions: matched ? [] : suggestGraphEndpoints(u.method, u.path, 3),
    };
  });
}
