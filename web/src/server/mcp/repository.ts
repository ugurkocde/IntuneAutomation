import "server-only";
import { unstable_cache } from "next/cache";

import bundledIndexJson from "../../../../mcp/data/scripts-index.json";
import type {
  CatalogSource,
  ScriptIndex,
  ScriptMeta,
  ScriptRepository,
} from "./types.ts";

// Source repo/ref can be overridden for forks or testing. Read lazily so env
// changes apply per request rather than being frozen at module load.
const repo = () => process.env.INTUNE_MCP_REPO ?? "ugurkocde/intuneautomation";
const ref = () => process.env.INTUNE_MCP_REF ?? "main";
const rawBase = () => `https://raw.githubusercontent.com/${repo()}/${ref()}`;

const FETCH_TIMEOUT_MS = 10_000;

// The committed index doubles as the fallback of last resort; it is inlined
// into the server bundle at build time so no filesystem access is needed.
const bundledIndex = bundledIndexJson as unknown as ScriptIndex;

// Last successful fetch results survive between requests on a warm instance
// and let us serve slightly stale data through upstream outages.
const globalForMcp = globalThis as unknown as {
  intuneMcpLastGood?: { index?: ScriptIndex; instructions?: string };
};
const lastGood = (globalForMcp.intuneMcpLastGood ??= {});

async function fetchText(url: string, accept: string): Promise<string> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { Accept: accept, "User-Agent": "intuneautomation-mcp" },
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`);
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

const cachedIndexText = unstable_cache(
  async () =>
    fetchText(`${rawBase()}/mcp/data/scripts-index.json`, "application/json"),
  ["intune-mcp-index-v1"],
  { revalidate: 600 },
);

const cachedInstructions = unstable_cache(
  async () =>
    fetchText(
      `${rawBase()}/mcp/data/generator-instructions.md`,
      "text/markdown",
    ),
  ["intune-mcp-instructions-v1"],
  { revalidate: 600 },
);

const cachedScriptSource = unstable_cache(
  async (rawUrl: string, _version: string) => fetchText(rawUrl, "text/plain"),
  ["intune-mcp-script-source-v1"],
  { revalidate: 3_600 },
);

async function getIndex(): Promise<{
  index: ScriptIndex;
  source: CatalogSource;
}> {
  try {
    const index = JSON.parse(await cachedIndexText()) as ScriptIndex;
    lastGood.index = index;
    return { index, source: "github" };
  } catch {
    if (lastGood.index) {
      return { index: lastGood.index, source: "github (stale cache)" };
    }
    return { index: bundledIndex, source: "bundled" };
  }
}

async function getInstructions(): Promise<{
  text: string;
  source: CatalogSource;
}> {
  try {
    const text = await cachedInstructions();
    lastGood.instructions = text;
    return { text, source: "github" };
  } catch (error) {
    if (lastGood.instructions) {
      return { text: lastGood.instructions, source: "github (stale cache)" };
    }
    throw error instanceof Error
      ? error
      : new Error("Failed to load the authoring guide.");
  }
}

async function getScriptSource(script: ScriptMeta): Promise<string> {
  // The script version participates in the cache key so an updated script
  // busts its cached source before the time-based revalidation would.
  return cachedScriptSource(script.rawUrl, script.version);
}

export const intuneScriptRepository: ScriptRepository = {
  getIndex,
  getInstructions,
  getScriptSource,
};
