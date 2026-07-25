import fs from "node:fs";
import path from "node:path";

// Server-only helper that derives the catalog size from the local checkout at
// build/render time so marketing copy and metadata never drift from the actual
// script count. Mirrors how the gallery counts entries (see github.ts
// fetchAllScripts): every .ps1/.sh file is one entry, except detection/
// remediation pairs, which are combined into a single entry per folder.

// Used only if the catalog directory cannot be found (should never happen in
// a normal checkout or CI build). A conservative floor keeps "N+" honest.
const FALLBACK_COUNT = 60;

const SCRIPT_EXTENSIONS = [".ps1", ".sh"];

function isScriptFile(name: string): boolean {
  return SCRIPT_EXTENSIONS.some((ext) => name.endsWith(ext));
}

// The web app lives in web/, the catalog one level up in the monorepo. Walk
// upward and identify the catalog by its remediation subfolder so a stray
// "scripts" directory elsewhere can't match.
function findCatalogDir(): string | null {
  let dir = process.cwd();
  for (let depth = 0; depth < 4; depth++) {
    const candidate = path.join(dir, "scripts");
    if (fs.existsSync(path.join(candidate, "remediation"))) {
      return candidate;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function countScriptFiles(dir: string): number {
  let count = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    if (entry.isDirectory()) {
      count += countScriptFiles(path.join(dir, entry.name));
    } else if (entry.isFile() && isScriptFile(entry.name)) {
      count++;
    }
  }
  return count;
}

let cachedCount: number | null = null;

export function getCatalogScriptCount(): number {
  if (cachedCount !== null) return cachedCount;

  const catalogDir = findCatalogDir();
  if (!catalogDir) return FALLBACK_COUNT;

  let count = 0;
  for (const entry of fs.readdirSync(catalogDir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    if (entry.isDirectory() && entry.name !== "remediation") {
      count += countScriptFiles(path.join(catalogDir, entry.name));
    } else if (entry.isFile() && isScriptFile(entry.name)) {
      count++;
    }
  }

  // Each remediation folder holding a detect/remediate pair renders as one
  // combined gallery entry; unpaired files fall back to standalone entries.
  const remediationDir = path.join(catalogDir, "remediation");
  for (const entry of fs.readdirSync(remediationDir, {
    withFileTypes: true,
  })) {
    if (entry.name.startsWith(".")) continue;
    if (!entry.isDirectory()) {
      if (entry.isFile() && isScriptFile(entry.name)) count++;
      continue;
    }
    const files = fs
      .readdirSync(path.join(remediationDir, entry.name))
      .filter(isScriptFile);
    const hasPair =
      files.some((f) => f.startsWith("detect")) &&
      files.some((f) => f.startsWith("remediate"));
    count += hasPair ? 1 : files.length;
  }

  cachedCount = count;
  return count;
}

// "69+" style label for marketing copy and metadata. The trailing "+" keeps
// the claim true if scripts land between deploys.
export function getScriptCountLabel(): string {
  return `${getCatalogScriptCount()}+`;
}

// Tags the gallery understands. Anything else that shows up in a header
// (Detection, Action, Device and so on) is dropped so these counts line up
// with what the live script list reports.
const KNOWN_TAGS = [
  "devices",
  "compliance",
  "apps",
  "reporting",
  "diagnostics",
  "security",
  "configuration",
  "operational",
  "monitoring",
  "notification",
  "remediation",
] as const;

// PowerShell headers carry a `.TAGS` field inside the <# #> comment block,
// shell scripts use the `# TAGS:` style. Loosely mirrors the parsing in
// github.ts parseScriptMetadata so both paths read the same values.
function parseScriptTags(filePath: string): string[] {
  let source: string;
  try {
    source = fs.readFileSync(filePath, "utf-8");
  } catch {
    return [];
  }

  let raw: string | undefined;
  if (filePath.endsWith(".ps1")) {
    const commentBlock = /<#([\s\S]*?)#>/.exec(source)?.[1];
    raw = commentBlock
      ? /\.TAGS\s*([\s\S]*?)(?=\n\s*\.|$)/i.exec(commentBlock)?.[1]
      : undefined;
  } else {
    raw = /^#\s*TAGS:\s*(.*)$/im.exec(source)?.[1];
  }
  if (!raw) return [];

  return raw
    .split(",")
    .map((tag) => tag.trim().toLowerCase())
    .filter((tag) => (KNOWN_TAGS as readonly string[]).includes(tag));
}

function addTags(tags: string[], counts: Record<string, number>): void {
  // One increment per tag per catalog entry, even if a tag repeats.
  for (const tag of new Set(tags)) {
    counts[tag] = (counts[tag] ?? 0) + 1;
  }
}

function collectTagCounts(dir: string, counts: Record<string, number>): void {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectTagCounts(full, counts);
    } else if (entry.isFile() && isScriptFile(entry.name)) {
      addTags(parseScriptTags(full), counts);
    }
  }
}

let cachedTagCounts: Record<string, number> | null = null;

// Per-tag catalog counts keyed by lowercase tag, derived from the checkout at
// build/render time. Lets the hero catalog render real numbers server-side
// instead of waiting for the client script list to arrive.
export function getCatalogTagCounts(): Record<string, number> {
  if (cachedTagCounts !== null) return cachedTagCounts;

  const counts: Record<string, number> = {};
  for (const tag of KNOWN_TAGS) counts[tag] = 0;

  const catalogDir = findCatalogDir();
  if (!catalogDir) return counts;

  for (const entry of fs.readdirSync(catalogDir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(catalogDir, entry.name);
    if (entry.isDirectory() && entry.name !== "remediation") {
      collectTagCounts(full, counts);
    } else if (entry.isFile() && isScriptFile(entry.name)) {
      addTags(parseScriptTags(full), counts);
    }
  }

  // Same pairing rule as getCatalogScriptCount: a folder holding a detect and
  // a remediate script is a single catalog entry, so its tags are counted once
  // as the union of both files.
  const remediationDir = path.join(catalogDir, "remediation");
  for (const entry of fs.readdirSync(remediationDir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(remediationDir, entry.name);
    if (!entry.isDirectory()) {
      if (entry.isFile() && isScriptFile(entry.name)) {
        addTags(parseScriptTags(full), counts);
      }
      continue;
    }

    const files = fs.readdirSync(full).filter(isScriptFile);
    const hasPair =
      files.some((f) => f.startsWith("detect")) &&
      files.some((f) => f.startsWith("remediate"));

    if (hasPair) {
      const union = new Set<string>();
      for (const file of files) {
        for (const tag of parseScriptTags(path.join(full, file))) {
          union.add(tag);
        }
      }
      addTags([...union], counts);
    } else {
      for (const file of files) {
        addTags(parseScriptTags(path.join(full, file)), counts);
      }
    }
  }

  cachedTagCounts = counts;
  return counts;
}
