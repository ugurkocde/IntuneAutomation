# IntuneAutomation MCP server

The hosted IntuneAutomation MCP server lets any Streamable HTTP compatible AI
client search the public script library, read full script sources with their
required Microsoft Graph permissions, and author new scripts that follow the
library's conventions. The AI model in your own client does the reasoning; the
server only serves catalog data.

## Endpoint

```text
https://intuneautomation.com/mcp
```

The endpoint is public and read-only. It does not require an API key. Opening
the same URL in a browser displays the installation guide; MCP requests
continue to use the Streamable HTTP protocol.

## Connect from Claude Desktop

1. Open **Customize or Settings, then Connectors**.
2. Choose **+ and Add custom connector**.
3. Name it `IntuneAutomation` and paste the endpoint above.
4. Leave OAuth Client ID and OAuth Client Secret empty.
5. In a new chat, open **+ and Connectors** and enable IntuneAutomation.

## Connect from Claude Code

```bash
claude mcp add --transport http --scope user intuneautomation https://intuneautomation.com/mcp
claude mcp list
```

Change `--scope user` to `--scope project` if the configuration should be
shared through the repository's `.mcp.json` file.

## Connect from Codex

```bash
codex mcp add intuneautomation --url https://intuneautomation.com/mcp
codex mcp list
```

## Connect from ChatGPT

OpenAI currently documents custom MCP apps as available on ChatGPT web. On an
eligible plan or workspace:

1. On ChatGPT web, enable Developer mode under **Settings, Apps, Advanced Settings**.
2. Open **Apps and Create**, name the app `IntuneAutomation`, and paste the endpoint.
3. Select no authentication, then choose **Scan Tools and Create**.
4. Start a new chat and select IntuneAutomation from the tools menu.

## Connect from VS Code (GitHub Copilot)

1. Open the Command Palette and run `MCP: Add Server`.
2. Choose HTTP, paste the endpoint, and name it `intuneautomation`.
3. Save it globally or to the workspace, then trust the server.
4. Open Copilot Chat and enable the IntuneAutomation tools.

## Connect a custom harness

Use your MCP client's HTTP or Streamable HTTP transport. A common
configuration shape is:

```json
{
  "mcpServers": {
    "intuneautomation": {
      "type": "http",
      "url": "https://intuneautomation.com/mcp"
    }
  }
}
```

Clients should honor HTTP `429` responses and the `Retry-After` header.

## Tools

### `search_scripts`

Searches and browses the catalog. With a `query`, results are ranked full-text
matches over title, id, tags, synopsis, category, permissions, and
description. Without a query, the whole catalog is returned in stable id
order. Optional filters: `category` (exact), `tag`, `platform`, and
`permission` (case-insensitive substrings). Paginate with `limit` (max 25) and
`offset`; follow `nextOffset` until it is `null`.

### `get_script_metadata`

Full metadata for one script by `id`: description, required Graph permissions,
minimum role, parameters, examples, notes, Azure Automation runbook
eligibility, and a one-click Azure deployment link where available. No source
code.

### `get_script`

The full PowerShell source of a script plus its metadata. Large scripts are
chunked: pass `start` and `maxCharacters` (max 30000) and follow `nextStart`
until it is `null`.

### `get_script_authoring_guide`

The exact authoring conventions used by
[intuneautomation.com/generator](https://intuneautomation.com/generator):
strict help-block format, module and auth patterns, Graph pagination and
throttling helpers, safety rules, and verified Graph endpoint mappings. Pass
`task` to also receive the most similar existing scripts. Clients should call
this before writing any new Intune or Graph PowerShell script.

### `list_script_catalog`

Discovers the exact `categories`, `tags`, `platforms`, `permissions`, or
`minRoles` values used across the library, with usage counts. Use it to find
valid filter values for `search_scripts`.

## Prompts and resources

The server also exposes two prompts (`find-intune-script`,
`write-intune-script`) and three resources (`intune-scripts://index`,
`intune-scripts://authoring-guide`, `intune-script://{id}`).

## Trust model

The server is read-only and unauthenticated. It never connects to your
Microsoft tenant, never runs PowerShell, never asks for credentials, and sends
no telemetry. It only serves files from the public IntuneAutomation GitHub
repository. Scripts you retrieve are run by you, with your own Microsoft Graph
authentication, exactly as documented at
[intuneautomation.com](https://intuneautomation.com).

## Implementation

The server runs as part of the website: route handler at
`web/src/app/mcp/route.ts`, server logic under `web/src/server/mcp/`, catalog
data pipeline under `mcp/`. The former npm package
(`@ugurkocde/intuneautomation-mcp`, stdio) is deprecated; existing installs
keep working but new users should connect to the hosted endpoint.
