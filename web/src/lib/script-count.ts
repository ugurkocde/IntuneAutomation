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
