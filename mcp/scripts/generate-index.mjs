#!/usr/bin/env node
/**
 * Generates mcp/data/scripts-index.json by parsing the comment-based help
 * headers and param() blocks of every PowerShell script under scripts/.
 *
 * The MCP server fetches this index from GitHub raw at runtime, so it must be
 * regenerated and committed whenever scripts change (wired into CI). A copy is
 * also shipped inside the npm package as an offline fallback.
 *
 * Usage: node mcp/scripts/generate-index.mjs
 */
import { readdir, readFile, writeFile, mkdir } from "node:fs/promises";
import { join, relative, basename, dirname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = "ugurkocde/intuneautomation";
const BRANCH = "main";
const RAW_BASE = `https://raw.githubusercontent.com/${REPO}/${BRANCH}`;

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const scriptsDir = join(repoRoot, "scripts");
const outFile = join(repoRoot, "mcp", "data", "scripts-index.json");

// Single-value metadata fields (first non-empty line after the tag).
const SINGLE_FIELDS = [
  "TITLE", "SYNOPSIS", "AUTHOR", "VERSION", "MINROLE",
  "LASTUPDATE", "PLATFORM", "CATEGORY", "SCHEDULE", "EXECUTION",
  "OUTPUT", "REMEDIATIONTYPE", "PAIRSCRIPT",
];
// Multi-line block fields (everything up to the next tag).
const BLOCK_FIELDS = ["DESCRIPTION", "NOTES", "CHANGELOG"];

/** Recursively collect *.ps1 files, skipping virtualenv / hidden dirs. */
async function collectScripts(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await collectScripts(full)));
    } else if (entry.isFile() && entry.name.endsWith(".ps1")) {
      out.push(full);
    }
  }
  return out;
}

/** Extract the first <# ... #> comment-help block. */
function extractHelpBlock(content) {
  const m = content.match(/<#([\s\S]*?)#>/);
  return m ? m[1] : "";
}

/**
 * Split a help block into tag -> [raw lines] segments. Tags look like a line
 * whose only content is ".TAGNAME".
 */
function segmentByTag(block) {
  const lines = block.split(/\r?\n/);
  const segments = [];
  let current = null;
  for (const line of lines) {
    const tag = line.match(/^\s*\.([A-Z][A-Z0-9]+)\s*$/);
    if (tag) {
      current = { tag: tag[1], lines: [] };
      segments.push(current);
    } else if (current) {
      current.lines.push(line);
    }
  }
  return segments;
}

function dedent(lines) {
  // Trim trailing/leading blank lines, then strip common leading indent.
  const trimmed = [...lines];
  while (trimmed.length && trimmed[0].trim() === "") trimmed.shift();
  while (trimmed.length && trimmed[trimmed.length - 1].trim() === "") trimmed.pop();
  const indents = trimmed
    .filter((l) => l.trim() !== "")
    .map((l) => (l.match(/^\s*/)?.[0].length ?? 0));
  const min = indents.length ? Math.min(...indents) : 0;
  return trimmed.map((l) => l.slice(min)).join("\n").trim();
}

function firstLine(lines) {
  for (const l of lines) {
    if (l.trim() !== "") return l.trim();
  }
  return "";
}

function splitList(value) {
  return value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Best-effort parse of the param() block: returns parameter name, type,
 * mandatory flag and default value. Uses depth-aware scanning so nested
 * brackets/parens don't break splitting.
 */
function parseParams(content) {
  const start = content.search(/\bparam\s*\(/i);
  if (start === -1) return [];
  const open = content.indexOf("(", start);
  let depth = 0;
  let end = -1;
  for (let i = open; i < content.length; i++) {
    const c = content[i];
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end === -1) return [];
  const body = content.slice(open + 1, end);

  // Depth-aware split on top-level commas, ignoring brackets/commas that live
  // inside single- or double-quoted string defaults.
  const parts = [];
  let buf = "";
  depth = 0;
  let inSingle = false;
  let inDouble = false;
  for (const c of body) {
    if (c === "'" && !inDouble) inSingle = !inSingle;
    else if (c === '"' && !inSingle) inDouble = !inDouble;
    if (!inSingle && !inDouble) {
      if (c === "(" || c === "[" || c === "{") depth++;
      else if (c === ")" || c === "]" || c === "}") depth--;
    }
    if (c === "," && depth === 0 && !inSingle && !inDouble) {
      parts.push(buf);
      buf = "";
    } else {
      buf += c;
    }
  }
  if (buf.trim()) parts.push(buf);

  const params = [];
  for (const raw of parts) {
    const nameMatch = raw.match(/\$([A-Za-z_][A-Za-z0-9_]*)\s*(=\s*([\s\S]+?))?\s*$/);
    if (!nameMatch) continue;
    const name = nameMatch[1];
    // Type is the last [type] attribute immediately before the $var.
    const beforeVar = raw.slice(0, raw.indexOf("$" + name));
    const typeMatches = [...beforeVar.matchAll(/\[([^\]]+)\]/g)].map((m) => m[1].trim());
    // Filter out attribute decorations (Parameter, ValidateSet, etc.).
    const typeCandidates = typeMatches.filter(
      (t) => !/^(Parameter|CmdletBinding|Validate|Alias|AllowNull|AllowEmpty|SupportsWildcards)/i.test(t)
    );
    const type = typeCandidates.length ? typeCandidates[typeCandidates.length - 1] : "";
    const mandatory = /Mandatory\s*=\s*\$true/i.test(raw);
    let defaultValue = nameMatch[3] ? nameMatch[3].trim() : undefined;
    if (defaultValue) defaultValue = defaultValue.replace(/\s+/g, " ");
    params.push({
      name,
      type,
      mandatory,
      ...(defaultValue !== undefined ? { default: defaultValue } : {}),
      switch: /^switch$/i.test(type),
    });
  }
  return params;
}

async function buildEntry(filePath) {
  const content = await readFile(filePath, "utf8");
  const relPath = relative(repoRoot, filePath).split(sep).join("/");
  const id = basename(filePath, ".ps1");
  const category = relPath.split("/")[1] ?? ""; // scripts/<category>/file.ps1

  const block = extractHelpBlock(content);
  const segments = segmentByTag(block);

  const meta = { examples: [] };
  for (const seg of segments) {
    if (seg.tag === "EXAMPLE") {
      const text = dedent(seg.lines);
      if (text) meta.examples.push(text);
    } else if (SINGLE_FIELDS.includes(seg.tag)) {
      meta[seg.tag.toLowerCase()] = firstLine(seg.lines);
    } else if (BLOCK_FIELDS.includes(seg.tag)) {
      meta[seg.tag.toLowerCase()] = dedent(seg.lines);
    } else if (seg.tag === "TAGS") {
      meta.tags = splitList(firstLine(seg.lines));
    } else if (seg.tag === "PERMISSIONS") {
      meta.permissions = splitList(firstLine(seg.lines));
    }
  }

  return {
    id,
    title: meta.title ?? id,
    synopsis: meta.synopsis ?? "",
    description: meta.description ?? "",
    category, // folder-derived, canonical for grouping/filtering
    categoryLabel: meta.category || category,
    tags: meta.tags ?? [],
    permissions: meta.permissions ?? [],
    minRole: meta.minrole ?? "",
    platform: meta.platform ?? "",
    author: meta.author ?? "",
    version: meta.version ?? "",
    lastUpdate: meta.lastupdate ?? "",
    schedule: meta.schedule ?? "",
    execution: meta.execution ?? "",
    output: meta.output ?? "",
    remediationType: meta.remediationtype ?? "",
    pairScript: meta.pairscript ?? "",
    parameters: parseParams(content),
    examples: meta.examples,
    notes: meta.notes ?? "",
    path: relPath,
    rawUrl: `${RAW_BASE}/${relPath}`,
    githubUrl: `https://github.com/${REPO}/blob/${BRANCH}/${relPath}`,
  };
}

async function main() {
  const files = (await collectScripts(scriptsDir)).sort();
  const scripts = [];
  for (const f of files) {
    scripts.push(await buildEntry(f));
  }
  scripts.sort((a, b) => a.id.localeCompare(b.id));

  const categories = [...new Set(scripts.map((s) => s.category))].sort();
  const index = {
    repository: REPO,
    branch: BRANCH,
    generated: process.env.SOURCE_DATE || new Date().toISOString(),
    count: scripts.length,
    categories,
    scripts,
  };

  await mkdir(dirname(outFile), { recursive: true });
  await writeFile(outFile, JSON.stringify(index, null, 2) + "\n", "utf8");

  console.log(`Wrote ${relative(repoRoot, outFile)}`);
  console.log(`  ${scripts.length} scripts across ${categories.length} categories: ${categories.join(", ")}`);
  const missing = scripts.filter((s) => !s.title || !s.synopsis);
  if (missing.length) {
    console.warn(`  WARNING: ${missing.length} script(s) missing title/synopsis: ${missing.map((s) => s.id).join(", ")}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
