# Changelog

All notable changes to `@ugurkocde/intuneautomation-mcp` are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## 1.0.0

Initial public release.

### Tools

- `search_scripts` — full-text, ranked search over the script catalog.
- `list_scripts` — list scripts, filterable by category or tag.
- `get_script_metadata` — full metadata for a script (permissions, min role, parameters, examples).
- `get_script` — full PowerShell source for a script, fetched from GitHub.
- `get_script_authoring_guide` — the intuneautomation.com generator conventions for writing new Intune/Graph scripts, with similar-script suggestions.

### Resources

- `intune-scripts://index` — the full catalog as JSON.
- `intune-scripts://authoring-guide` — the authoring guide as Markdown.
- `intune-script://{id}` — full source for a single script.

### Prompts

- `find-intune-script` — find existing scripts for a task.
- `write-intune-script` — author a new convention-compliant script.

### Notes

- Read-only and unauthenticated; no tenant access, no telemetry.
- Data is fetched live from the IntuneAutomation GitHub repository, with an
  offline fallback bundled in the package.
- Source repo/ref can be overridden with `INTUNE_MCP_REPO` / `INTUNE_MCP_REF`.
