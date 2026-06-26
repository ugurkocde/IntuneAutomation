#!/usr/bin/env node
import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { z } from "zod";
import {
  getIndex,
  getInstructions,
  searchScripts,
  findScript,
  fetchScriptSource,
  summarize,
} from "./catalog.js";
import type { ScriptMeta } from "./types.js";

// Single source of truth for the version: dist/index.js -> ../package.json.
const pkg = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "package.json"), "utf8")
) as { version: string };
const VERSION = pkg.version;

const server = new McpServer(
  {
    name: "intuneautomation-mcp",
    version: VERSION,
  },
  {
    instructions:
      "This server exposes the IntuneAutomation PowerShell script library (Microsoft Intune / Microsoft Graph automation). " +
      "When the user asks what scripts exist or describes an Intune task, call search_scripts or list_scripts before answering — do not guess. " +
      "Use get_script_metadata for permissions/parameters and get_script for full source. " +
      "Before writing ANY new Intune/Graph/Windows/macOS-management PowerShell script, ALWAYS call get_script_authoring_guide first (pass the task) so the output matches the library's conventions and a similar existing script can be reused. " +
      "This server is read-only: it never accesses the user's tenant and runs no scripts.",
  }
);

function jsonText(value: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }] };
}

function errorText(message: string) {
  return { content: [{ type: "text" as const, text: message }], isError: true };
}

function fullMetadata(s: ScriptMeta) {
  return {
    id: s.id,
    title: s.title,
    synopsis: s.synopsis,
    description: s.description,
    category: s.category,
    tags: s.tags,
    permissions: s.permissions,
    minRole: s.minRole,
    platform: s.platform || undefined,
    author: s.author,
    version: s.version,
    lastUpdate: s.lastUpdate,
    schedule: s.schedule || undefined,
    execution: s.execution || undefined,
    output: s.output || undefined,
    remediationType: s.remediationType || undefined,
    pairScript: s.pairScript || undefined,
    parameters: s.parameters,
    examples: s.examples,
    notes: s.notes,
    path: s.path,
    rawUrl: s.rawUrl,
    githubUrl: s.githubUrl,
  };
}

// --- Tools -----------------------------------------------------------------

server.registerTool(
  "list_scripts",
  {
    title: "List Intune automation scripts",
    description:
      "List the IntuneAutomation PowerShell scripts, optionally filtered by category or tag. " +
      "Returns a summary (id, title, synopsis, category, tags, required Graph permissions, minimum role) for each script. " +
      "Use this to browse the catalog; use get_script to retrieve full source.",
    inputSchema: {
      category: z
        .string()
        .optional()
        .describe("Filter by category, e.g. apps, compliance, devices, monitoring, notification, operational, remediation, security."),
      tag: z.string().optional().describe("Filter by a tag (case-insensitive substring match), e.g. Reporting, Security."),
    },
  },
  async ({ category, tag }) => {
    const { index, source } = await getIndex();
    let scripts = index.scripts;
    if (category) {
      const c = category.trim().toLowerCase();
      scripts = scripts.filter((s) => s.category.toLowerCase() === c);
    }
    if (tag) {
      const t = tag.trim().toLowerCase();
      scripts = scripts.filter((s) => s.tags.some((x) => x.toLowerCase().includes(t)));
    }
    return jsonText({
      source,
      total: index.count,
      categories: index.categories,
      matched: scripts.length,
      scripts: scripts.map(summarize),
    });
  }
);

server.registerTool(
  "search_scripts",
  {
    title: "Search Intune automation scripts",
    description:
      "Full-text search across the IntuneAutomation script catalog (title, id, tags, synopsis, category, permissions, description). " +
      "Returns the best-matching scripts as summaries, ranked by relevance. Use this when the user describes a task in natural language.",
    inputSchema: {
      query: z.string().describe("Natural-language search, e.g. 'report non-compliant devices' or 'rotate bitlocker keys'."),
      limit: z.number().int().min(1).max(33).optional().describe("Max results to return (default 10)."),
    },
  },
  async ({ query, limit }) => {
    const { index, source } = await getIndex();
    const results = searchScripts(index, query, limit ?? 10);
    return jsonText({
      source,
      query,
      matched: results.length,
      scripts: results.map(summarize),
    });
  }
);

server.registerTool(
  "get_script_metadata",
  {
    title: "Get script metadata",
    description:
      "Return full metadata for one script by id (title, description, required Graph permissions, minimum role, parameters, usage examples, notes) WITHOUT the source code. Use before get_script when you only need to know how to run it.",
    inputSchema: {
      id: z.string().describe("Script id (filename without .ps1), e.g. get-application-inventory-report."),
    },
  },
  async ({ id }) => {
    const { index } = await getIndex();
    const script = findScript(index, id);
    if (!script) {
      return errorText(`No script with id '${id}'. Use list_scripts or search_scripts to find valid ids.`);
    }
    return jsonText(fullMetadata(script));
  }
);

server.registerTool(
  "get_script",
  {
    title: "Get full script source",
    description:
      "Return the full PowerShell source of a script by id, fetched from GitHub, along with its metadata. Use this to show or copy the script the user wants to run.",
    inputSchema: {
      id: z.string().describe("Script id (filename without .ps1), e.g. get-application-inventory-report."),
    },
  },
  async ({ id }) => {
    const { index } = await getIndex();
    const script = findScript(index, id);
    if (!script) {
      return errorText(`No script with id '${id}'. Use list_scripts or search_scripts to find valid ids.`);
    }
    let source: string;
    try {
      source = await fetchScriptSource(script.rawUrl);
    } catch (err) {
      return errorText(`Failed to fetch source for '${id}' from ${script.rawUrl}: ${(err as Error).message}`);
    }
    return {
      content: [
        { type: "text" as const, text: JSON.stringify(fullMetadata(script), null, 2) },
        { type: "text" as const, text: "```powershell\n" + source + "\n```" },
      ],
    };
  }
);

server.registerTool(
  "get_script_authoring_guide",
  {
    title: "Get the Intune script authoring guide",
    description:
      "Return the authoring conventions used by intuneautomation.com to write production PowerShell scripts for Microsoft Intune / Microsoft Graph (strict help-block format, required-module + auth patterns, Graph pagination/throttling helper, safety rules, and verified Graph endpoint mappings). " +
      "ALWAYS call this before writing a NEW Intune/Graph/Windows/macOS-management PowerShell script so your output matches the IntuneAutomation library. Optionally pass the user's task to also get the most similar existing scripts to reuse as references.",
    inputSchema: {
      task: z
        .string()
        .optional()
        .describe("What the user wants the script to do, e.g. 'report stale devices not synced in 30 days'. Used to surface similar existing scripts."),
    },
  },
  async ({ task }) => {
    const { text, source } = await getInstructions();
    const today = new Date().toISOString().slice(0, 10);
    const content: Array<{ type: "text"; text: string }> = [];

    content.push({
      type: "text",
      text:
        `Use today's date for the .LASTUPDATE field: ${today}\n` +
        `(authoring guide source: ${source})`,
    });

    if (task && task.trim()) {
      const { index } = await getIndex();
      const similar = searchScripts(index, task, 3);
      if (similar.length) {
        content.push({
          type: "text",
          text:
            "Before writing from scratch, check these existing IntuneAutomation scripts that may already cover this (use get_script to read one):\n" +
            JSON.stringify(similar.map(summarize), null, 2),
        });
      }
    }

    content.push({ type: "text", text });
    return { content };
  }
);

// --- Prompts ---------------------------------------------------------------

server.registerPrompt(
  "find-intune-script",
  {
    title: "Find an Intune script",
    description: "Find existing IntuneAutomation scripts for a task.",
    argsSchema: {
      task: z.string().describe("What you want to do in Intune, e.g. 'report devices not synced in 30 days'."),
    },
  },
  ({ task }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text:
            `Find IntuneAutomation scripts for this task: ${task}\n\n` +
            "Use the search_scripts tool, then summarize the best matches with their required Microsoft Graph permissions and minimum role. " +
            "If one fits, offer to retrieve its full source with get_script.",
        },
      },
    ],
  })
);

server.registerPrompt(
  "write-intune-script",
  {
    title: "Write a new Intune script",
    description: "Author a new Intune/Graph PowerShell script that matches the IntuneAutomation library conventions.",
    argsSchema: {
      task: z.string().describe("What the new script should do, e.g. 'export all compliance policies to CSV'."),
    },
  },
  ({ task }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text:
            `Write a Microsoft Intune PowerShell script that does the following: ${task}\n\n` +
            "First call get_script_authoring_guide (pass the task) to load the required conventions and any similar existing scripts. " +
            "If an existing script already covers this, retrieve it with get_script instead of writing a new one. " +
            "Otherwise produce the script following the guide exactly.",
        },
      },
    ],
  })
);

// --- Resources -------------------------------------------------------------

server.registerResource(
  "scripts-index",
  "intune-scripts://index",
  {
    title: "IntuneAutomation script index",
    description: "The full catalog of IntuneAutomation scripts with metadata (JSON).",
    mimeType: "application/json",
  },
  async (uri) => {
    const { index } = await getIndex();
    return { contents: [{ uri: uri.href, mimeType: "application/json", text: JSON.stringify(index, null, 2) }] };
  }
);

server.registerResource(
  "authoring-guide",
  "intune-scripts://authoring-guide",
  {
    title: "IntuneAutomation script authoring guide",
    description: "Conventions for writing production Intune/Graph PowerShell scripts (the generator system prompt).",
    mimeType: "text/markdown",
  },
  async (uri) => {
    const { text } = await getInstructions();
    return { contents: [{ uri: uri.href, mimeType: "text/markdown", text }] };
  }
);

server.registerResource(
  "script",
  new ResourceTemplate("intune-script://{id}", {
    list: async () => {
      const { index } = await getIndex();
      return {
        resources: index.scripts.map((s) => ({
          uri: `intune-script://${s.id}`,
          name: s.title,
          description: s.synopsis,
          mimeType: "text/x-powershell",
        })),
      };
    },
  }),
  {
    title: "Intune automation script source",
    description: "Full PowerShell source for a single script, addressed by id.",
    mimeType: "text/x-powershell",
  },
  async (uri, { id }) => {
    const { index } = await getIndex();
    const script = findScript(index, Array.isArray(id) ? id[0] : id);
    if (!script) {
      throw new Error(`No script with id '${id}'.`);
    }
    const source = await fetchScriptSource(script.rawUrl);
    return { contents: [{ uri: uri.href, mimeType: "text/x-powershell", text: source }] };
  }
);

// --- Start -----------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // stderr is safe for logging; stdout is reserved for the MCP protocol.
  console.error(`intuneautomation-mcp v${VERSION} ready (stdio)`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
