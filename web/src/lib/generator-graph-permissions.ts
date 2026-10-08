// Least-privilege analysis for generated scripts.
//
// Resolves the Graph calls a script makes, looks up the scopes Microsoft
// documents as accepted for each endpoint (GRAPH_ENDPOINT_SCOPES), and
// compares that with what the script declares in .PERMISSIONS and
// Connect-MgGraph -Scopes.
//
// Only Intune paths (/deviceManagement, /deviceAppManagement) are analysed.
// The upstream permission data for directory endpoints is incomplete (GET
// /groups lists only Group-NestingSupport.ReadWrite.All, for example), so
// advice there would be wrong more often than right.
//
// Every heuristic leans towards silence: a false "too broad" warning makes
// the auto-fix pass downgrade a scope the script needs, which breaks it.

import {
  GRAPH_ENDPOINT_SCOPES,
  GRAPH_SCOPE_LIST,
  GRAPH_SCOPES,
} from "./generator-graph-data.ts";
import { matchGraphEndpoint } from "./generator-graph-endpoints.ts";

export type GraphCall = {
  method: string;
  // Catalog template, e.g. /deviceManagement/managedDevices/{managedDeviceId}
  template: string;
  accepted: readonly string[];
};

export type RequiredScope = { scope: string; calls: string[] };

export type ExcessScope = { scope: string; replacement: string };

export type PermissionAnalysis = {
  declared: string[];
  // Minimum scopes covering every resolved Intune call, with the calls each
  // one is needed for.
  required: RequiredScope[];
  // Declared ReadWrite scopes where the Read sibling covers every call. When
  // the Read sibling is already declared, the ReadWrite scope can just go.
  excess: ExcessScope[];
  // Resolved Intune calls no declared scope covers.
  missing: GraphCall[];
  // False when the script has write calls we could not attribute to an
  // endpoint (or uses Mg SDK write cmdlets); excess is not reported then.
  writesResolved: boolean;
};

const WRITE_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);
const INTUNE_PATH = /^\/device(?:Management|AppManagement)(?:\/|$)/;
const PLACEHOLDER = "__var__";

// Any method spec: `-Method PATCH`, `-Method:PATCH`, `-Method $verb`,
// `Method = 'PATCH'`, `'Method' = $m`. The value is classified by methodOf.
const METHOD_TOKEN_RE =
  /(?:-Method(?:\s*:\s*|\s+)|['"]?\bMethod['"]?\s*=\s*)([^\s;,)}]+)/gi;

// A value that is not a literal verb (a variable, an if expression) could be
// a write, so it counts as one that cannot be attributed.
function methodOf(value: string): string {
  const verb = value.replace(/^["']|["']$/g, "").toUpperCase();
  return verb === "GET" || WRITE_METHODS.has(verb) ? verb : "UNKNOWN";
}

// Mg SDK cmdlets other than these read-only verbs may change data.
// Invoke-MgGraphRequest is handled through its -Method token instead.
const SDK_SAFE_VERBS = new Set([
  "get",
  "find",
  "connect",
  "disconnect",
  "select",
  "test",
]);
function hasSdkWrite(code: string): boolean {
  for (const m of code.matchAll(/\b([A-Za-z]+)-Mg(\w*)/g)) {
    const verb = (m[1] ?? "").toLowerCase();
    if (SDK_SAFE_VERBS.has(verb)) continue;
    if (verb === "invoke" && /^GraphRequest$/i.test(m[2] ?? "")) continue;
    return true;
  }
  return false;
}

// Removes `#` comments that are outside quotes, so `"Baseline #2"` survives.
function stripLineComments(code: string): string {
  return code
    .split("\n")
    .map((line) => {
      let quote: string | null = null;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (quote) {
          if (ch === quote) quote = null;
        } else if (ch === '"' || ch === "'") {
          quote = ch;
        } else if (ch === "#" && (i === 0 || /\s/.test(line[i - 1]!))) {
          return line.slice(0, i);
        }
      }
      return line;
    })
    .join("\n");
}

function readSibling(scope: string): string | null {
  if (!scope.includes(".ReadWrite.")) return null;
  const read = scope.replace(".ReadWrite.", ".Read.");
  return GRAPH_SCOPES.has(read) ? read : null;
}

function isReadOnlyScope(scope: string): boolean {
  return /\.Read(?:Basic)?(?:\.|$)/.test(scope) && !scope.includes("ReadWrite");
}

// A declared ReadWrite scope also grants what its Read sibling grants, even
// where the docs only list the Read scope.
function covers(scope: string, call: GraphCall): boolean {
  if (call.accepted.includes(scope)) return true;
  const read = readSibling(scope);
  return read !== null && call.accepted.includes(read);
}

// GET, or a POST report action such as /deviceManagement/reports/getXxx that
// documents a Read scope. Everything else is treated as a write, even when
// the docs (sometimes wrongly) list a Read scope for it.
function isReadLike(call: GraphCall): boolean {
  if (call.method === "GET") return true;
  if (call.method !== "POST") return false;
  const last = call.template.split("/").pop() ?? "";
  return /^get[A-Z]/.test(last) && call.accepted.some(isReadOnlyScope);
}

export function parseDeclaredScopes(code: string): string[] {
  const out = new Set<string>();
  const perms = code.match(/\.PERMISSIONS\s*\n\s*([^\n]+)/)?.[1]?.trim();
  if (perms && !/^none\b/i.test(perms)) {
    for (const s of perms.split(",")) if (s.trim()) out.add(s.trim());
  }
  // $Scopes = @("a", "b") and Connect-MgGraph -Scopes "a","b" / @(...)
  const lists = [
    ...code.matchAll(/\$\w*Scopes?\w*\s*=\s*@?\(([^)]*)\)/gi),
    ...code.matchAll(/-Scopes\s+(@\([^)]*\)|(?:["'][^"'\n]+["']\s*,?\s*)+)/gi),
  ];
  for (const m of lists) {
    for (const q of (m[1] ?? "").matchAll(
      /["']([A-Za-z][\w-]*(?:\.[\w-]+)+)["']/g,
    )) {
      if (q[1]) out.add(q[1]);
    }
  }
  return [...out];
}

// Replace PowerShell interpolations with a placeholder segment value, so
// `/managedDevices/$($device.id)` still matches `/managedDevices/{id}`.
function replaceInterpolations(s: string): string {
  return s.replace(
    /\$\([^)]*\)|\$\{[^}]*\}|\$[A-Za-z_][\w]*(?:\.\w+)*/g,
    PLACEHOLDER,
  );
}

function stripQuery(path: string): string {
  const q = path.search(/[?#]/);
  return q >= 0 ? path.slice(0, q) : path;
}

// `possible` usages come from call sites after the variable was reassigned.
// The reassignment may be conditional, so the call might still hit this
// path; such usages only make the excess check more cautious.
type Usage = {
  method: string;
  path: string;
  tokenIndex: number | null;
  possible?: boolean;
};

// Finds the HTTP method for a Graph URI at `idx`. Looks at the statement the
// URI is in (following backtick continuations), then at an enclosing splat
// hashtable. Returns the token position so unattributed writes can be found.
function methodAt(
  code: string,
  idx: number,
): { method: string; tokenIndex: number | null } {
  const lineStart = code.lastIndexOf("\n", idx - 1) + 1;
  let end = code.indexOf("\n", idx);
  while (end !== -1 && /`\s*$/.test(code.slice(lineStart, end))) {
    end = code.indexOf("\n", end + 1);
  }
  const stmtEnd = end === -1 ? code.length : end;
  const scan = (from: number, to: number) => {
    const re = new RegExp(METHOD_TOKEN_RE.source, "gi");
    re.lastIndex = from;
    const m = re.exec(code);
    if (m && m.index < to) {
      return { method: methodOf(m[1] ?? ""), tokenIndex: m.index };
    }
    return null;
  };
  const inStatement = scan(lineStart, stmtEnd);
  if (inStatement) return inStatement;

  // Splatted call: @{ Uri = "..."; Method = "PATCH" }
  const before = code.slice(lineStart, idx);
  if (/\bUri['"]?\s*=\s*$/i.test(before)) {
    const open = code.lastIndexOf("@{", idx);
    const close = code.indexOf("}", idx);
    if (open !== -1 && close !== -1) {
      const inSplat = scan(open, close);
      if (inSplat) return inSplat;
    }
  }
  return { method: "GET", tokenIndex: null };
}

function extractUsages(code: string): Usage[] {
  // Variables holding a bare Graph base, e.g. $GraphBase = ".../beta"
  const bases = new Map<string, string>();
  for (const m of code.matchAll(
    /\$(\w+)\s*=\s*["']https:\/\/graph\.microsoft\.com\/(v1\.0|beta)\/?["']/gi,
  )) {
    if (m[1] && m[2]) bases.set(m[1].toLowerCase(), `/${m[2]}`);
  }

  const usages: Usage[] = [];
  for (const m of code.matchAll(/"([^"\n]*)"|'([^'\n]*)'/g)) {
    let raw = m[1] ?? m[2] ?? "";
    const literalIdx = m.index ?? 0;

    const base = raw.match(/^\$(?:\{(\w+)\}|\((\w+)\)|(\w+))(?=\/)/);
    const baseName = (base?.[1] ?? base?.[2] ?? base?.[3])?.toLowerCase();
    if (base && baseName && bases.has(baseName)) {
      raw = bases.get(baseName) + raw.slice(base[0].length);
    }

    let path: string;
    const abs = raw.match(
      /^https:\/\/graph\.microsoft\.com(\/(?:v1\.0|beta)\/.*)$/i,
    );
    if (abs?.[1]) path = abs[1];
    else if (/^\/?(?:v1\.0|beta)\//.test(raw))
      path = "/" + raw.replace(/^\//, "");
    else continue;

    path = stripQuery(replaceInterpolations(path)).replace(
      /^\/(?:v1\.0|beta)/,
      "",
    );
    if (!path || path === "/") continue;

    // `$uri = "..."` followed later by `-Uri $uri`: use the methods at the
    // call sites. Otherwise the literal is the call site.
    const lineStart = code.lastIndexOf("\n", literalIdx - 1) + 1;
    const assigned = code.slice(lineStart, literalIdx).match(/\$(\w+)\s*=\s*$/);
    const sites: { index: number; possible: boolean }[] = [];
    if (assigned?.[1]) {
      // Call sites before the next reassignment certainly use this literal.
      // Later ones possibly do (the reassignment may sit in an if block, or
      // the name may be reused in another function).
      const reassign = new RegExp(`\\$${assigned[1]}\\s*=(?!=)`, "gi");
      reassign.lastIndex = literalIdx + m[0].length;
      const scopeEnd = reassign.exec(code)?.index ?? code.length;
      const useRe = new RegExp(
        `(?:-Uri\\s+|\\bUri['"]?\\s*=\\s*)\\$${assigned[1]}\\b`,
        "gi",
      );
      useRe.lastIndex = literalIdx;
      for (let u = useRe.exec(code); u; u = useRe.exec(code)) {
        sites.push({ index: u.index, possible: u.index >= scopeEnd });
      }
    }
    if (!sites.some((s) => !s.possible)) {
      sites.push({ index: literalIdx, possible: false });
    }
    for (const site of sites) {
      usages.push({
        path,
        ...methodAt(code, site.index),
        possible: site.possible,
      });
    }
  }
  return usages;
}

function resolve(usages: Usage[]): {
  calls: GraphCall[];
  possibleCalls: GraphCall[];
  attributedTokens: Set<number>;
} {
  const calls = new Map<string, GraphCall>();
  const possibleCalls = new Map<string, GraphCall>();
  const attributedTokens = new Set<number>();
  for (const u of usages) {
    const hit = matchGraphEndpoint(u.method, u.path);
    const target = u.possible ? possibleCalls : calls;
    // A write to a path we can read and that is clearly outside Intune (such
    // as /users/{upn}/sendMail, missing from the catalog) cannot need an
    // Intune scope, so it does not block the excess check either.
    const knownNonIntune =
      !u.path.startsWith(`/${PLACEHOLDER}`) && !INTUNE_PATH.test(u.path);
    if ((hit || knownNonIntune) && u.tokenIndex !== null && !u.possible) {
      attributedTokens.add(u.tokenIndex);
    }
    if (!hit) continue;
    const key = `${u.method} ${hit.template}`;
    if (target.has(key)) continue;
    target.set(key, {
      method: u.method,
      template: hit.template,
      accepted: (GRAPH_ENDPOINT_SCOPES[hit.index] ?? []).map(
        (i) => GRAPH_SCOPE_LIST[i] ?? "",
      ),
    });
  }
  return {
    calls: [...calls.values()],
    possibleCalls: [...possibleCalls.values()],
    attributedTokens,
  };
}

function rank(scope: string): number {
  if (isReadOnlyScope(scope)) return 0;
  if (scope.includes("ReadWrite")) return 1;
  return 2; // PrivilegedOperations and other action scopes
}

function chooseScope(call: GraphCall, declared: Set<string>): string {
  return [...call.accepted].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      Number(!declared.has(a)) - Number(!declared.has(b)) ||
      a.length - b.length ||
      a.localeCompare(b),
  )[0]!;
}

function minimumScopes(
  calls: GraphCall[],
  declared: Set<string>,
): RequiredScope[] {
  const chosen = new Map<string, GraphCall[]>();
  for (const call of calls) {
    if (call.accepted.length === 0) continue;
    const scope = chooseScope(call, declared);
    chosen.set(scope, [...(chosen.get(scope) ?? []), call]);
  }
  // Drop a scope when other chosen scopes already cover all its calls, e.g.
  // Read.All next to ReadWrite.All of the same family. Least privileged
  // scopes are tried first so the broader one that is needed anyway stays.
  for (const scope of [...chosen.keys()].sort((a, b) => rank(a) - rank(b))) {
    const others = [...chosen.keys()].filter((s) => s !== scope);
    const redundant = chosen
      .get(scope)!
      .every((call) => others.some((o) => covers(o, call)));
    if (redundant) chosen.delete(scope);
  }
  return [...chosen.entries()]
    .map(([scope, cs]) => ({
      scope,
      calls: [...new Set(cs.map((c) => `${c.method} ${c.template}`))],
    }))
    .sort((a, b) => a.scope.localeCompare(b.scope));
}

export function analyzeGraphPermissions(
  code: string,
): PermissionAnalysis | null {
  const declaredList = parseDeclaredScopes(code);
  // Help text and comments often quote URIs and verbs; only scan real code.
  const body = stripLineComments(code.replace(/<#[\s\S]*?#>/g, ""));
  const usages = extractUsages(body);
  const { calls: allCalls, possibleCalls, attributedTokens } = resolve(usages);
  const calls = allCalls.filter((c) => INTUNE_PATH.test(c.template));
  if (calls.length === 0) return null;

  // Every method spec that is not a literal GET must belong to a resolved
  // call; otherwise some write is unaccounted for and excess stays silent.
  const writeTokens = [...body.matchAll(METHOD_TOKEN_RE)].filter(
    (m) => methodOf(m[1] ?? "") !== "GET",
  );
  const writesResolved =
    writeTokens.every((m) => attributedTokens.has(m.index ?? -1)) &&
    !hasSdkWrite(body);

  const declared = new Set(declaredList);
  const excess: ExcessScope[] = [];
  if (writesResolved) {
    for (const scope of declaredList) {
      const read = readSibling(scope);
      if (!read) continue;
      const covered = calls.filter((c) => covers(scope, c));
      if (covered.length === 0) continue;
      const mightNeed = possibleCalls.filter((c) => covers(scope, c));
      if (
        [...covered, ...mightNeed].every(
          (c) => isReadLike(c) && c.accepted.includes(read),
        )
      ) {
        excess.push({ scope, replacement: read });
      }
    }
  }

  const missing = calls.filter(
    (c) => c.accepted.length > 0 && !declaredList.some((d) => covers(d, c)),
  );

  return {
    declared: declaredList,
    required: minimumScopes(calls, declared),
    excess,
    missing,
    writesResolved,
  };
}
