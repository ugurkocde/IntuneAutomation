import type { McpServer } from "@modelcontextprotocol/server";
import { ResourceTemplate } from "@modelcontextprotocol/server";
import { createMcpHandler } from "mcp-handler";
import { z } from "zod4";

import {
  MAX_CATALOG_OFFSET,
  MAX_SEARCH_OFFSET,
  buildCatalog,
  filterScripts,
  findScript,
  fullMetadata,
  nextBoundedOffset,
  paginateText,
  rankScripts,
  summarize,
  type CatalogKind,
} from "./core.ts";
import type { ScriptRepository } from "./types.ts";

export const SERVER_NAME = "intuneautomation";
export const SERVER_VERSION = "2.0.0";

const TOOL_TIMEOUT_MS = 12_000;

export const SERVER_INSTRUCTIONS =
  "This server exposes the IntuneAutomation PowerShell script library (Microsoft Intune / Microsoft Graph automation). " +
  "When the user asks what scripts exist or describes an Intune task, call search_scripts before answering; do not guess. " +
  "Call search_scripts without a query to browse the whole catalog, and list_script_catalog to discover valid filter values. " +
  "Use get_script_metadata for permissions/parameters and get_script for full source; follow nextStart until it is null when a script is chunked. " +
  "Before writing ANY new Intune/Graph/Windows/macOS-management PowerShell script, ALWAYS call get_script_authoring_guide first (pass the task) so the output matches the library's conventions and a similar existing script can be reused. " +
  "This server is read-only: it never accesses the user's tenant and runs no scripts.";

const readOnlyAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
} as const;

const filterInput = z.string().trim().min(1).max(100);

const searchInputSchema = z.object({
  query: z
    .string()
    .trim()
    .min(2)
    .max(200)
    .optional()
    .describe(
      "Natural-language search, e.g. 'report non-compliant devices' or 'rotate bitlocker keys'. Omit to browse the catalog.",
    ),
  category: filterInput
    .optional()
    .describe(
      "Exact category, e.g. apps, compliance, devices, monitoring, remediation, security. Discover values with list_script_catalog.",
    ),
  tag: filterInput
    .optional()
    .describe("Tag filter (case-insensitive substring), e.g. Reporting."),
  platform: filterInput
    .optional()
    .describe("Platform filter (case-insensitive substring), e.g. Windows."),
  permission: filterInput
    .optional()
    .describe(
      "Microsoft Graph permission filter (case-insensitive substring), e.g. DeviceManagementManagedDevices.Read.All.",
    ),
  limit: z.number().int().min(1).max(25).default(10),
  offset: z.number().int().min(0).max(MAX_SEARCH_OFFSET).default(0),
});

const summarySchema = z.object({
  id: z.string(),
  title: z.string(),
  synopsis: z.string(),
  category: z.string(),
  tags: z.array(z.string()),
  permissions: z.array(z.string()),
  minRole: z.string(),
  platform: z.string().nullable(),
  runbookEligible: z.boolean(),
  githubUrl: z.string(),
});

const searchOutputSchema = z.object({
  query: z.string().nullable(),
  category: z.string().nullable(),
  tag: z.string().nullable(),
  platform: z.string().nullable(),
  permission: z.string().nullable(),
  total: z.number().int(),
  matched: z.number().int(),
  offset: z.number().int(),
  nextOffset: z.number().int().nullable(),
  catalogSource: z.string(),
  scripts: z.array(summarySchema),
});

const metadataSchema = z.object({
  id: z.string(),
  title: z.string(),
  synopsis: z.string(),
  description: z.string(),
  category: z.string(),
  tags: z.array(z.string()),
  permissions: z.array(z.string()),
  minRole: z.string(),
  platform: z.string().nullable(),
  author: z.string(),
  version: z.string(),
  lastUpdate: z.string(),
  schedule: z.string().nullable(),
  execution: z.string().nullable(),
  output: z.string().nullable(),
  remediationType: z.string().nullable(),
  pairScript: z.string().nullable(),
  parameters: z.array(
    z.object({
      name: z.string(),
      type: z.string(),
      mandatory: z.boolean(),
      default: z.string().nullable(),
      switch: z.boolean(),
    }),
  ),
  examples: z.array(z.string()),
  notes: z.string(),
  path: z.string(),
  rawUrl: z.string(),
  githubUrl: z.string(),
  runbook: z
    .object({
      eligible: z.boolean(),
      runtime: z.string(),
      exclusionReason: z.string(),
    })
    .nullable(),
  azureDeploy: z
    .object({
      deployUrl: z.string(),
      templateUrl: z.string(),
      supportsExistingAutomationAccount: z.boolean(),
    })
    .nullable(),
});

const idInputSchema = z
  .string()
  .trim()
  .min(1)
  .max(200)
  .describe(
    "Script id (filename without .ps1), e.g. get-application-inventory-report.",
  );

const metadataOutputSchema = z.object({
  catalogSource: z.string(),
  script: metadataSchema,
});

const getScriptInputSchema = z.object({
  id: idInputSchema,
  start: z
    .number()
    .int()
    .min(0)
    .default(0)
    .describe("Character offset used to continue a large script."),
  maxCharacters: z
    .number()
    .int()
    .min(1_000)
    .max(30_000)
    .default(12_000)
    .describe("Maximum source characters returned in this response."),
});

const getScriptOutputSchema = z.object({
  catalogSource: z.string(),
  script: metadataSchema,
  language: z.literal("powershell"),
  content: z.string(),
  totalCharacters: z.number().int(),
  start: z.number().int(),
  nextStart: z.number().int().nullable(),
  truncated: z.boolean(),
});

const guideInputSchema = z.object({
  task: z
    .string()
    .trim()
    .min(1)
    .max(500)
    .optional()
    .describe(
      "What the user wants the script to do, e.g. 'report stale devices not synced in 30 days'. Used to surface similar existing scripts.",
    ),
  start: z
    .number()
    .int()
    .min(0)
    .default(0)
    .describe("Character offset used to continue the guide if it was chunked."),
  maxCharacters: z.number().int().min(1_000).max(60_000).default(60_000),
});

const guideOutputSchema = z.object({
  today: z
    .string()
    .describe("Use this date for the .LASTUPDATE field of a new script."),
  guideSource: z.string(),
  similarScripts: z.array(summarySchema),
  guide: z.string(),
  totalCharacters: z.number().int(),
  start: z.number().int(),
  nextStart: z.number().int().nullable(),
  truncated: z.boolean(),
});

const catalogKinds = [
  "categories",
  "tags",
  "platforms",
  "permissions",
  "minRoles",
] as const;

const catalogInputSchema = z.object({
  kind: z.enum(catalogKinds),
  search: z
    .string()
    .trim()
    .max(100)
    .optional()
    .describe("Case-insensitive substring filter over the values."),
  limit: z.number().int().min(1).max(100).default(50),
  offset: z.number().int().min(0).max(MAX_CATALOG_OFFSET).default(0),
});

const catalogOutputSchema = z.object({
  kind: z.enum(catalogKinds),
  items: z.array(z.object({ value: z.string(), count: z.number().int() })),
  total: z.number().int(),
  offset: z.number().int(),
  nextOffset: z.number().int().nullable(),
  catalogSource: z.string(),
});

const toToolResult = <T extends object>(result: T) => ({
  content: [{ type: "text" as const, text: JSON.stringify(result) }],
  structuredContent: result as Record<string, unknown>,
});

const toolError = (message: string) => ({
  isError: true,
  content: [{ type: "text" as const, text: message }],
});

const unknownIdError = (id: string) =>
  toolError(`No script with id '${id}'. Use search_scripts to find valid ids.`);

async function withTimeout<T>(operation: Promise<T>): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error("IntuneAutomation MCP timed out.")),
          TOOL_TIMEOUT_MS,
        );
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function logToolFailure(tool: string, error: unknown) {
  console.error(
    `IntuneAutomation MCP ${tool} failed:`,
    error instanceof Error ? error.name : "UnknownError",
  );
}

export function registerIntuneTools(
  server: McpServer,
  repository: ScriptRepository,
) {
  server.registerTool(
    "search_scripts",
    {
      title: "Search Intune automation scripts",
      description:
        "Search and browse the IntuneAutomation PowerShell script catalog. With a query, results are ranked full-text matches over title, id, tags, synopsis, category, permissions, and description. " +
        "Without a query, the whole catalog is returned in stable id order. All filters combine with the query. " +
        "Follow nextOffset for more results. Use get_script to retrieve full source.",
      inputSchema: searchInputSchema,
      outputSchema: searchOutputSchema,
      annotations: readOnlyAnnotations,
    },
    async (input) => {
      try {
        const { index, source } = await withTimeout(repository.getIndex());
        const filtered = filterScripts(index.scripts, input);
        const ranked = rankScripts(filtered, input.query);
        const page = ranked.slice(input.offset, input.offset + input.limit);
        return toToolResult({
          query: input.query ?? null,
          category: input.category ?? null,
          tag: input.tag ?? null,
          platform: input.platform ?? null,
          permission: input.permission ?? null,
          total: index.count,
          matched: ranked.length,
          offset: input.offset,
          nextOffset: nextBoundedOffset(
            input.offset,
            page.length,
            input.offset + page.length < ranked.length,
            MAX_SEARCH_OFFSET,
          ),
          catalogSource: source,
          scripts: page.map(summarize),
        });
      } catch (error) {
        logToolFailure("search", error);
        return toolError("IntuneAutomation MCP could not search the catalog.");
      }
    },
  );

  server.registerTool(
    "get_script_metadata",
    {
      title: "Get script metadata",
      description:
        "Return full metadata for one script by id (title, description, required Graph permissions, minimum role, parameters, usage examples, notes, Azure Automation runbook eligibility, and an Azure deploy link when available) WITHOUT the source code. " +
        "Use before get_script when you only need to know how to run it.",
      inputSchema: z.object({ id: idInputSchema }),
      outputSchema: metadataOutputSchema,
      annotations: readOnlyAnnotations,
    },
    async ({ id }) => {
      try {
        const { index, source } = await withTimeout(repository.getIndex());
        const script = findScript(index, id);
        if (!script) return unknownIdError(id);
        return toToolResult({
          catalogSource: source,
          script: fullMetadata(script),
        });
      } catch (error) {
        logToolFailure("metadata", error);
        return toolError(
          "IntuneAutomation MCP could not retrieve that script's metadata.",
        );
      }
    },
  );

  server.registerTool(
    "get_script",
    {
      title: "Get full script source",
      description:
        "Return the full PowerShell source of a script by id, along with its metadata. Large scripts are chunked; call again with nextStart until it is null. " +
        "Use this to show or copy the script the user wants to run.",
      inputSchema: getScriptInputSchema,
      outputSchema: getScriptOutputSchema,
      annotations: readOnlyAnnotations,
    },
    async ({ id, start, maxCharacters }) => {
      try {
        const { index, source } = await withTimeout(repository.getIndex());
        const script = findScript(index, id);
        if (!script) return unknownIdError(id);
        const content = await withTimeout(repository.getScriptSource(script));
        const page = paginateText(content, start, maxCharacters);
        return toToolResult({
          catalogSource: source,
          script: fullMetadata(script),
          language: "powershell" as const,
          content: page.value,
          totalCharacters: page.totalCharacters,
          start: page.start,
          nextStart: page.nextStart,
          truncated: page.truncated,
        });
      } catch (error) {
        logToolFailure("get_script", error);
        return toolError(
          "IntuneAutomation MCP could not fetch that script's source.",
        );
      }
    },
  );

  server.registerTool(
    "get_script_authoring_guide",
    {
      title: "Get the Intune script authoring guide",
      description:
        "Return the authoring conventions used by intuneautomation.com to write production PowerShell scripts for Microsoft Intune / Microsoft Graph (strict help-block format, required-module + auth patterns, Graph pagination/throttling helper, safety rules, and verified Graph endpoint mappings). " +
        "ALWAYS call this before writing a NEW Intune/Graph/Windows/macOS-management PowerShell script so your output matches the IntuneAutomation library. " +
        "Pass the user's task to also get the most similar existing scripts to reuse instead.",
      inputSchema: guideInputSchema,
      outputSchema: guideOutputSchema,
      annotations: readOnlyAnnotations,
    },
    async ({ task, start, maxCharacters }) => {
      try {
        const { text, source } = await withTimeout(
          repository.getInstructions(),
        );
        const page = paginateText(text, start, maxCharacters);
        let similar: ReturnType<typeof summarize>[] = [];
        if (task) {
          const { index } = await withTimeout(repository.getIndex());
          similar = rankScripts(index.scripts, task).slice(0, 3).map(summarize);
        }
        return toToolResult({
          today: new Date().toISOString().slice(0, 10),
          guideSource: source,
          similarScripts: similar,
          guide: page.value,
          totalCharacters: page.totalCharacters,
          start: page.start,
          nextStart: page.nextStart,
          truncated: page.truncated,
        });
      } catch (error) {
        logToolFailure("authoring_guide", error);
        return toolError(
          "IntuneAutomation MCP could not load the authoring guide.",
        );
      }
    },
  );

  server.registerTool(
    "list_script_catalog",
    {
      title: "List catalog metadata values",
      description:
        "Discover the exact categories, tags, platforms, Microsoft Graph permissions, or minimum roles used across the script library, with usage counts. " +
        "Use this to find valid filter values before calling search_scripts.",
      inputSchema: catalogInputSchema,
      outputSchema: catalogOutputSchema,
      annotations: readOnlyAnnotations,
    },
    async ({ kind, search, limit, offset }) => {
      try {
        const { index, source } = await withTimeout(repository.getIndex());
        let items = buildCatalog(index, kind as CatalogKind);
        if (search) {
          const needle = search.toLowerCase();
          items = items.filter((i) => i.value.toLowerCase().includes(needle));
        }
        const page = items.slice(offset, offset + limit);
        return toToolResult({
          kind,
          items: page,
          total: items.length,
          offset,
          nextOffset: nextBoundedOffset(
            offset,
            page.length,
            offset + page.length < items.length,
            MAX_CATALOG_OFFSET,
          ),
          catalogSource: source,
        });
      } catch (error) {
        logToolFailure("catalog", error);
        return toolError(
          "IntuneAutomation MCP could not list catalog metadata.",
        );
      }
    },
  );
}

export function registerIntunePrompts(server: McpServer) {
  server.registerPrompt(
    "find-intune-script",
    {
      title: "Find an Intune script",
      description: "Find existing IntuneAutomation scripts for a task.",
      argsSchema: z.object({
        task: z
          .string()
          .describe(
            "What you want to do in Intune, e.g. 'report devices not synced in 30 days'.",
          ),
      }),
    },
    ({ task }) => ({
      messages: [
        {
          role: "user" as const,
          content: {
            type: "text" as const,
            text:
              `Find IntuneAutomation scripts for this task: ${task}\n\n` +
              "Use the search_scripts tool, then summarize the best matches with their required Microsoft Graph permissions and minimum role. " +
              "If one fits, offer to retrieve its full source with get_script.",
          },
        },
      ],
    }),
  );

  server.registerPrompt(
    "write-intune-script",
    {
      title: "Write a new Intune script",
      description:
        "Author a new Intune/Graph PowerShell script that matches the IntuneAutomation library conventions.",
      argsSchema: z.object({
        task: z
          .string()
          .describe(
            "What the new script should do, e.g. 'export all compliance policies to CSV'.",
          ),
      }),
    },
    ({ task }) => ({
      messages: [
        {
          role: "user" as const,
          content: {
            type: "text" as const,
            text:
              `Write a Microsoft Intune PowerShell script that does the following: ${task}\n\n` +
              "First call get_script_authoring_guide (pass the task) to load the required conventions and any similar existing scripts. " +
              "If an existing script already covers this, retrieve it with get_script instead of writing a new one. " +
              "Otherwise produce the script following the guide exactly.",
          },
        },
      ],
    }),
  );
}

export function registerIntuneResources(
  server: McpServer,
  repository: ScriptRepository,
) {
  server.registerResource(
    "scripts-index",
    "intune-scripts://index",
    {
      title: "IntuneAutomation script index",
      description:
        "The full catalog of IntuneAutomation scripts with metadata (JSON).",
      mimeType: "application/json",
    },
    async (uri) => {
      const { index } = await repository.getIndex();
      return {
        contents: [
          {
            uri: uri.href,
            mimeType: "application/json",
            text: JSON.stringify(index, null, 2),
          },
        ],
      };
    },
  );

  server.registerResource(
    "authoring-guide",
    "intune-scripts://authoring-guide",
    {
      title: "IntuneAutomation script authoring guide",
      description:
        "Conventions for writing production Intune/Graph PowerShell scripts (the generator system prompt).",
      mimeType: "text/markdown",
    },
    async (uri) => {
      const { text } = await repository.getInstructions();
      return {
        contents: [{ uri: uri.href, mimeType: "text/markdown", text }],
      };
    },
  );

  server.registerResource(
    "script",
    new ResourceTemplate("intune-script://{id}", {
      list: async () => {
        const { index } = await repository.getIndex();
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
      description:
        "Full PowerShell source for a single script, addressed by id.",
      mimeType: "text/x-powershell",
    },
    async (uri, { id }) => {
      const { index } = await repository.getIndex();
      const rawId = Array.isArray(id) ? id[0] : id;
      const script = findScript(index, rawId ?? "");
      if (!script) {
        throw new Error(`No script with id '${String(id)}'.`);
      }
      const source = await repository.getScriptSource(script);
      return {
        contents: [
          { uri: uri.href, mimeType: "text/x-powershell", text: source },
        ],
      };
    },
  );
}

export function createIntuneMcpHandler(repository: ScriptRepository) {
  return createMcpHandler(
    (server) => {
      registerIntuneTools(server, repository);
      registerIntunePrompts(server);
      registerIntuneResources(server, repository);
    },
    {
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      instructions: SERVER_INSTRUCTIONS,
      maxSubscriptions: 0,
      onEvent(event) {
        if (event.type === "ERROR") {
          console.error("IntuneAutomation MCP protocol error", {
            source: event.source,
            severity: event.severity,
          });
        }
      },
    },
  );
}
