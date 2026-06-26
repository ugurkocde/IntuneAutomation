# @ugurkocde/intuneautomation-mcp

[![npm version](https://img.shields.io/npm/v/@ugurkocde/intuneautomation-mcp.svg)](https://www.npmjs.com/package/@ugurkocde/intuneautomation-mcp)
[![npm downloads](https://img.shields.io/npm/dm/@ugurkocde/intuneautomation-mcp.svg)](https://www.npmjs.com/package/@ugurkocde/intuneautomation-mcp)
[![license](https://img.shields.io/npm/l/@ugurkocde/intuneautomation-mcp.svg)](./LICENSE)
[![node](https://img.shields.io/node/v/@ugurkocde/intuneautomation-mcp.svg)](https://nodejs.org)

An [MCP](https://modelcontextprotocol.io) server that lets Claude Code, Claude
Desktop, Cursor, VS Code, Codex, and any MCP client **search, retrieve, and write**
Microsoft Intune PowerShell scripts from the
[IntuneAutomation](https://intuneautomation.com) library — in natural language.

Ask _"Which Intune scripts report on non-compliant devices?"_ or _"Write me a
script to export all compliance policies to CSV"_ and the assistant uses this
server to find the right script (with its required Microsoft Graph permissions,
minimum role, parameters, and source) or to author a new one that matches the
project's conventions.

> **No API key. No login. No hosted service. No telemetry.** The server runs
> locally as a subprocess of your MCP client and only reads the public script
> catalog from GitHub. It never connects to your Microsoft tenant and never runs
> any script — you do that yourself, with your own authentication.

## Install

### Claude Code

```bash
claude mcp add intuneautomation -- npx -y @ugurkocde/intuneautomation-mcp
```

### Claude Desktop / Cursor / Windsurf / generic

Add to the client's MCP config (`claude_desktop_config.json`, Cursor's
`mcp.json`, etc.):

```json
{
  "mcpServers": {
    "intuneautomation": {
      "command": "npx",
      "args": ["-y", "@ugurkocde/intuneautomation-mcp"]
    }
  }
}
```

### VS Code

```bash
code --add-mcp '{"name":"intuneautomation","command":"npx","args":["-y","@ugurkocde/intuneautomation-mcp"]}'
```

### Codex CLI

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.intuneautomation]
command = "npx"
args = ["-y", "@ugurkocde/intuneautomation-mcp"]
```

Restart your client afterwards.

## Try it

- "What Intune scripts do you have for application inventory?"
- "Find a script to rotate BitLocker keys — what permissions does it need?"
- "List all the remediation scripts."
- "Show me the full source of the device compliance report script."
- "Write an Intune script that reports devices not synced in the last 30 days."

## Tools

| Tool | Description |
| --- | --- |
| `search_scripts` | Full-text search the catalog by natural-language task. Ranked results. |
| `list_scripts` | List all scripts, optionally filtered by `category` or `tag`. |
| `get_script_metadata` | Full metadata for one script (permissions, min role, parameters, examples) — no source. |
| `get_script` | Full PowerShell source for one script, fetched from GitHub, plus metadata. |
| `get_script_authoring_guide` | The exact conventions [intuneautomation.com/generator](https://intuneautomation.com/generator) uses to write Intune/Graph scripts. Call before generating a NEW script. Pass `task` to also get the most similar existing scripts. |

### Authoring new scripts

With this server installed, asking _"write me an Intune script to report stale
devices"_ gives the assistant the generator's full ruleset — strict comment-help
block, module-init + managed-identity auth, Graph pagination/throttling helper,
safety rules (`-WhatIf`, no hardcoded secrets, `/beta` endpoints), and curated
verified Graph endpoint mappings — so the generated script matches the
IntuneAutomation library instead of being improvised.

## Resources

| Resource | Description |
| --- | --- |
| `intune-scripts://index` | The entire catalog with metadata (JSON). |
| `intune-scripts://authoring-guide` | The script authoring guide / generator conventions (Markdown). |
| `intune-script://{id}` | Full PowerShell source for a single script. |

## Prompts

| Prompt | Description |
| --- | --- |
| `find-intune-script` | Find existing scripts for a task. |
| `write-intune-script` | Author a new convention-compliant script. |

## How it works

```
Your MCP client  ──stdio──▶  intuneautomation-mcp  ──HTTPS──▶  raw.githubusercontent.com
   (Claude Code)              (local Node process)             (IntuneAutomation repo)
```

The server fetches a generated metadata index (`mcp/data/scripts-index.json`) and
the authoring guide (`mcp/data/generator-instructions.md`) from the repository's
`main` branch and caches them in memory (5 min). Full script source is fetched on
demand. If GitHub is unreachable, it falls back to copies bundled in this package.

New scripts added to the repository appear automatically — no reinstall or
republish needed. The authoring guide is exported verbatim from the website
generator's system prompt, so the MCP and the
[online generator](https://intuneautomation.com/generator) always teach the same
conventions.

## Configuration

| Env var | Default | Purpose |
| --- | --- | --- |
| `INTUNE_MCP_REPO` | `ugurkocde/intuneautomation` | Source repository (`owner/name`). For forks/testing. |
| `INTUNE_MCP_REF` | `main` | Branch or tag to read from. |

## Troubleshooting

- **Requires Node.js 18+.** Check with `node --version`. `npx` ships with Node.
- **Nothing happens after install:** fully restart the MCP client so it spawns
  the server.
- **Behind a proxy / offline:** the server falls back to the catalog bundled in
  the package, so search still works; only freshly-added scripts and live source
  fetches need network.
- **Stale results:** the index is cached for 5 minutes; restart the client to
  force a refresh.

## Security

This server is **read-only and unauthenticated**. It never connects to your
Microsoft tenant, never runs PowerShell, never asks for credentials, and sends no
telemetry. It only reads public files from the IntuneAutomation GitHub repository.
Scripts you retrieve are run by you, with your own Microsoft Graph authentication,
exactly as documented at [intuneautomation.com](https://intuneautomation.com).

## Credits

The authoring guide embeds curated Microsoft Graph endpoint mappings from the
[merill/msgraph](https://github.com/merill/msgraph) project (via
[graph.pm](https://graph.pm)). See [ATTRIBUTION.md](./ATTRIBUTION.md).

## License

MIT — see [LICENSE](./LICENSE). Part of the
[IntuneAutomation](https://github.com/ugurkocde/intuneautomation) project.
