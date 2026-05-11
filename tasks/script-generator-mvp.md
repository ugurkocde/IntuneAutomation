# Script Generator MVP — IntuneAutomation.com

## Goal

Ship a free, no-login PowerShell script generator at `scriptgenerator.intuneautomation.com` (or `/generator` route) that turns natural-language requests into production-quality Intune scripts following the existing template conventions. Streaming output, copy/download only, no execution.

## Acceptance criteria (the contract)

A reviewer should be able to verify every one of these:

1. New page accessible at `/generator` and via subdomain `scriptgenerator.intuneautomation.com` (Vercel domain + middleware rewrite). Renders without auth.
2. Single prompt textarea, "Generate" button, streaming output area with PowerShell syntax highlighting (reuse existing Prism setup).
3. Required pre-generation checkbox — "Generate" button disabled until checked. Checkbox text references `/terms` and `/privacy`.
4. Persistent banner above output: "AI-generated. Review and test before production use."
5. Output follows template structure: contains `.TITLE`, `.SYNOPSIS`, `.DESCRIPTION`, `.TAGS`, `.PERMISSIONS`, `.AUTHOR`, `.VERSION`, `.EXAMPLE`, parameter block, module check, Graph auth pattern.
6. Server-side regex scrub strips secrets BEFORE sending to Anthropic. Scrub categories:
   - GUIDs (tenant/app/object IDs)
   - JWT-shaped tokens
   - Bearer tokens
   - Common API key prefixes (`sk-`, `ghp_`, `gho_`, `xox`, `AKIA`, `AIza`, etc.)
   - Long base64 blobs (>40 chars)
   - Email addresses (optional — surface in UI)
7. UI shows the user what was redacted (so they trust the scrub and learn).
8. Rate limit enforced per IP via Upstash Redis: 5 generations / 24h. 429 response with friendly message after limit.
9. Cloudflare Turnstile token verified server-side before generation.
10. Hard daily spend cap: if env-configured token count exceeded for the day, return 503 with maintenance message.
11. No prompt content logged anywhere on our side. Vercel function logs verified clean.
12. `/terms` and `/privacy` pages exist with clickwrap-grade language (Anthropic as processor, no storage on our side, user responsible for review, AS IS, liability cap).
13. Streaming via Vercel AI SDK (`ai` + `@ai-sdk/anthropic`).
14. Prompt caching enabled on the system prompt (verify via Anthropic API response showing cache hits after first call).
15. Copy button works (clipboard API). Download button produces `<title-slug>.ps1` file.
16. Mobile-responsive (test 375px width).
17. Type-check passes (`pnpm check`). Format passes. Build succeeds.

## Non-goals (explicit)

- No user accounts, no GitHub login (defer)
- No tenant connection / no script execution
- No RAG / pgvector lookup (system prompt + few-shot only for v1)
- No multi-turn editing (defer — v1.1: "refine this script" follow-up turn)
- No A/B model selection in UI (Haiku by default, code path supports swap)
- No telemetry beyond rate-limit counters

## Stack additions

- `@ai-sdk/anthropic` + `ai` (Vercel AI SDK) — streaming
- `@upstash/ratelimit` + `@upstash/redis` — rate limit
- Cloudflare Turnstile (client widget + server verify, free tier)
- New env vars: `ANTHROPIC_API_KEY`, `TURNSTILE_SECRET_KEY`, `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`, `DAILY_TOKEN_CAP` (optional)

## Architecture

```
[client]
  /generator page
  - Turnstile widget
  - prompt textarea
  - ToU checkbox (required)
  - "Generate" button
  - streamed output area + copy/download
       |
       v
POST /api/generator/generate (Vercel Function, edge or node)
  1. Verify Turnstile token (siteverify)
  2. Rate limit check (Upstash, key = sha256(ip))
  3. Daily cap check (Upstash counter)
  4. Regex scrub on user prompt; collect redaction summary
  5. Build messages: [system (cached) + user (scrubbed)]
  6. Stream from Claude Haiku 4.5 via AI SDK
  7. Pipe to client as SSE/streamText response
  8. After stream completes: increment token usage counter
  9. Never log prompt or output content
```

## File plan

New files:
- `web/src/app/generator/page.tsx` — server component shell + metadata
- `web/src/app/generator/page-client.tsx` — client UI (textarea, Turnstile, streaming)
- `web/src/app/generator/_components/redaction-summary.tsx`
- `web/src/app/generator/_components/output-panel.tsx`
- `web/src/app/api/generator/generate/route.ts` — streaming endpoint
- `web/src/app/terms/page.tsx`
- `web/src/app/privacy/page.tsx`
- `web/src/server/generator/system-prompt.ts` — large system prompt + few-shot examples
- `web/src/server/generator/scrub.ts` — regex scrubber + redaction reporting
- `web/src/server/generator/rate-limit.ts` — Upstash setup
- `web/src/server/generator/turnstile.ts` — Turnstile verification
- `web/src/middleware.ts` — subdomain rewrite (if file doesn't exist; check first)

Modified files:
- `web/src/env.js` — add new env vars
- `web/package.json` — add `ai`, `@ai-sdk/anthropic`, `@upstash/ratelimit`, `@upstash/redis`
- `web/next.config.mjs` (or `.ts`) — allow subdomain host in `images`/headers if needed
- `web/src/app/sitemap.ts` — add `/generator`, `/terms`, `/privacy`
- `web/src/app/robots.ts` — confirm AI crawlers allowed on `/generator` (it's marketing-positive)
- `web/src/components/navbar.tsx` — add "Generator" link with "New" badge

## System prompt strategy

Single large system prompt assembled from:
1. Role + persona: senior Intune/Graph PowerShell engineer
2. Hard rules (don't invent Graph permissions, always check modules, always parameter validation, output ONLY the script in a code fence, etc.)
3. Inlined `script-template.ps1` as the canonical structure
4. 3 hand-picked example scripts (one each: security, monitoring, remediation) — full source, ~400 lines each
5. Output contract: must start with `<#`, must end with closing block + script body, must include all required metadata fields
6. Failure mode: if user prompt is ambiguous, ask one clarifying question instead of guessing (BUT for MVP: just generate with best assumption and note assumptions in `.NOTES`)

Cache the entire system prompt with Anthropic ephemeral cache breakpoint → only user message is uncached.

## Implementation steps (in order)

1. Install deps + add env vars (validate via `env.js` schema)
2. Write `system-prompt.ts` (this is the highest-leverage file — get it right)
3. Write `scrub.ts` + unit-test mentally with sample inputs
4. Build `/api/generator/generate` streaming route
5. Build `/generator` page + client UI
6. Add Turnstile + rate limit
7. Write `/terms` and `/privacy` pages
8. Subdomain rewrite in middleware (or defer — `/generator` works for v1)
9. Navbar link
10. Sitemap + robots update
11. End-to-end manual test in browser via dev server
12. Type-check + format + build
13. Code review pass with `feature-dev:code-reviewer` subagent against acceptance criteria

## Risks & mitigations

- **Anthropic API key leak**: server-only env, never sent to client. `env.js` enforces.
- **Spend runaway**: daily token cap + per-IP rate limit + Turnstile.
- **Bad outputs damaging reputation**: disclaimer banner + ToU + scrub. Telemetry-free thumbs up/down can come in v1.1.
- **Subdomain DNS not yet configured**: ship `/generator` first; subdomain rewrite is additive.
- **Turnstile blocks legitimate users**: keep "managed" challenge level, not "invisible+strict".

## Open questions before implementation

1. **Anthropic API key — do you already have one ready, or want me to assume `ANTHROPIC_API_KEY` env and document setup?**
2. **Upstash + Turnstile accounts — same question. Free tiers, takes ~5 min each.**
3. **Subdomain `scriptgenerator.intuneautomation.com` — ship now via middleware rewrite, or ship `/generator` first and add subdomain after DNS is set?**
4. **Model default — Claude Haiku 4.5 (recommended for cost) or Sonnet 4.6 (better quality, ~10x cost)?**
5. **Terms/Privacy text — want me to draft, or do you have a lawyer-reviewed template to use?**

## Review section (filled in after implementation)

_To be completed once MVP is built and evaluated._
