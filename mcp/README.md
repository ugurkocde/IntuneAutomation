# IntuneAutomation MCP

An [MCP](https://modelcontextprotocol.io) server that lets Claude, Codex,
GitHub Copilot, ChatGPT, and any MCP client **search, retrieve, and write**
Microsoft Intune PowerShell scripts from the
[IntuneAutomation](https://intuneautomation.com) library, in natural language.

## Connect

The server is hosted. There is nothing to install: point your MCP client at

```text
https://intuneautomation.com/mcp
```

Open that URL in a browser for client-by-client setup instructions
(Claude Desktop, Claude Code, Codex, ChatGPT, VS Code), or see
[docs/mcp.md](../docs/mcp.md). Quick start for Claude Code:

```bash
claude mcp add --transport http --scope user intuneautomation https://intuneautomation.com/mcp
```

> **No API key. No login. No telemetry.** The endpoint is read-only and only
> serves the public script catalog from this repository. It never connects to
> your Microsoft tenant and never runs any script; you do that yourself, with
> your own authentication.

## What lives in this directory

The MCP server implementation runs as part of the website
([`web/src/server/mcp/`](../web/src/server/mcp/) and
[`web/src/app/mcp/route.ts`](../web/src/app/mcp/route.ts)). This directory
holds the data pipeline it serves:

| Path | Purpose |
| --- | --- |
| `data/scripts-index.json` | Generated catalog of every script with metadata (permissions, roles, parameters, runbook eligibility, Azure deploy links). |
| `data/generator-instructions.md` | The script authoring guide, exported from the website generator's system prompt. |
| `scripts/generate-index.mjs` | Regenerates the catalog from the comment-based help of every script under `scripts/`. Wired into CI. |
| `server.json` | MCP registry manifest pointing at the hosted endpoint. |

Both data files are kept fresh by CI (`script-analysis.yml`,
`refresh-generator-instructions.yml`) and guarded against drift
(`mcp-ci.yml`), so newly added scripts appear on the hosted server within
minutes of merging.

## The former npm package

Versions up to 1.x shipped as a local stdio server on npm
(`@ugurkocde/intuneautomation-mcp`). That package is deprecated in favor of the
hosted endpoint: existing installs keep working (the package reads this
repository's data at runtime), but it no longer receives updates. See
[CHANGELOG.md](./CHANGELOG.md).

## Credits

The authoring guide embeds curated Microsoft Graph endpoint mappings from the
[merill/msgraph](https://github.com/merill/msgraph) project (via
[graph.pm](https://graph.pm)). See [ATTRIBUTION.md](./ATTRIBUTION.md).

## License

MIT, see [LICENSE](./LICENSE). Part of the
[IntuneAutomation](https://github.com/ugurkocde/IntuneAutomation) project.
