# v4 Route Coverage Plan

Take the v4 design system that currently only lives on the landing page (`/`) and extend it across every reachable surface so the polish doesn't break the moment a user clicks anything.

## What "v4 contract" means in practice

Across every reskinned file:
- **Surface:** `rounded-md` (not `2xl`/`3xl`), hairline border via `var(--brand-rule)`, `bg-card/40` + `backdrop-blur-md`. No drop shadows.
- **Color:** semantic tokens (`bg-background`, `text-foreground`, `text-muted-foreground`, `border-border`). One accent (`var(--brand-accent-hi)` for cyan). Azure blue (`var(--brand-azure)`) reserved for Deploy-to-Azure surfaces. NO rainbow tag palettes, NO gradient backgrounds, NO `from-X` `to-Y` Tailwind utilities.
- **Type:** Geist for everything; `.font-display` class for headlines (tight tracking, semibold); `.font-mono-label` for tracked-uppercase mono labels; `font-mono` for code and stats.
- **Mono kickers:** every section opens with `// SECTION NAME` in cyan-hi mono before its display headline.
- **No emojis** in source files. Replace with Lucide icons or plain text.
- **Motion:** framer-motion `whileInView` with `viewport={{ once: true }}` for entry. Two-layer pattern when combining centering transforms with motion. `useReducedMotion()` respected.
- **A11y:** real `<a>`/`<button>` semantics, `aria-label` on icon-only controls, focus rings via `.ring-accent`, `prefers-reduced-motion` fallbacks.

## Tracks and files

### Track 1 — Overlays (HIGHEST traffic from landing)
Every visitor who clicks a card or hits Cmd-K lands here. Must be v4 before anything else ships.

| File | Lines | What it is |
|---|---|---|
| `web/src/components/search-dialog.tsx` | 184 | Cmd-K / `/` search dialog. Radix-based. Result rows should look like compact v4 cards. |
| `web/src/components/script-detail.tsx` | 1108 | Modal opened from PopularScripts grid on landing. Heavy v1 styling: gradients, big rounded corners. The single biggest reskin in this plan. |

### Track 2 — Scripts gallery routes
Destinations from `Browse scripts` CTA and from every CategoryMap tile.

| File | Lines | What it is |
|---|---|---|
| `web/src/app/scripts/page.tsx` | route entry | `/scripts/` page. Server component shell. |
| `web/src/app/scripts/[tag]/page.tsx` | route entry | `/scripts/[tag]/` filtered route. |
| `web/src/components/full-script-gallery.tsx` | 706 | Main gallery + filter chrome (tag pills, search, sort). |
| `web/src/components/tag-script-gallery.tsx` | 457 | Tag-filtered gallery variant. |
| `web/src/components/script-gallery.tsx` | (used) | Shared gallery shell? Worth auditing. |
| `web/src/components/notification-script-card.tsx` | — | Specialized card variant rendered inside galleries. |
| `web/src/components/notification-scripts-section.tsx` | — | Section wrapper, also contains emojis to strip. |

ScriptCard itself is already v4 (rewritten earlier), so the GRID looks right — but the page chrome around it (filter pills, search bar, header, "Reporting / Operational / Notification" tabs) is v1.

### Track 3 — Script detail (route version)
The `/script/[slug]/` destination when someone navigates directly (deep-link, share, RSS, AI citation). Modal handles most landing-side clicks; this route handles everything else.

| File | Lines | What it is |
|---|---|---|
| `web/src/app/script/[slug]/...` | route entry | Server component shell. |
| `web/src/components/script-detail-page.tsx` | 745 | Page-version of the detail view. Has its own v1 chrome (header, sidebar, deploy panel). |
| `web/src/components/script-comparison-table.tsx` | — | Used here. Has emojis + v1 styling. |
| `web/src/components/script-list-item.tsx` | — | Used in sidebar related-scripts list. |
| `web/src/components/script-detail-page-wrapper.tsx` | — | Wrapper, audit only. |
| `web/src/components/related-scripts.tsx` | — | Sidebar component. |

### Track 4 — Blog
Lower priority but the navbar links there. Must not look broken.

| File | Lines | What it is |
|---|---|---|
| `web/src/app/blog/page.tsx` + `page-client.tsx` | — | Blog index. |
| `web/src/app/blog/[slug]/page.tsx` + `page-client.tsx` | — | Individual blog post. |
| MDX components | — | `mdx-components.tsx` if it exists, or default rendering. |

### Track 5 — Utility + emoji cleanup
Cleanup pass for non-landing files.

| File | Notes |
|---|---|
| `web/src/app/unsubscribe/page.tsx` | Emoji status icons + v1 chrome. |
| `web/src/components/static-navbar.tsx` | If used by any layout — audit and align with v4 navbar. |
| `web/src/components/SubscriptionForm.tsx` | Has 📧 emoji. |
| `web/src/components/notification-scripts-section.tsx` | Platform-icon emojis (🍎 📱 🛡️ 📦). |
| `web/src/components/script-comparison-table.tsx` | ⚙️ 🔔 emojis. |
| `web/src/app/api/trpc/[trpc]/route.ts` | ❌ in server log prefix. |
| `web/src/app/unsubscribe/page.tsx` | ✅ ❌ ⚠️ as 6xl status icons. |

All emojis replaced with Lucide icons (Mail, Apple, Smartphone, Shield, Package, Settings, Bell, CheckCircle, XCircle, AlertTriangle) or plain text prefixes.

## Execution strategy

1. **Audit pass (me, in parallel with Track 1):** read each file once, note specific v1 patterns and their v4 replacements per file. Produce a concrete checklist per file.

2. **Track 1 first, then verify in preview.** Two parallel `ui-design-expert` agents — one for `search-dialog.tsx`, one for `script-detail.tsx`. These are the most-clicked surfaces; verifying first protects the highest-value journey.

3. **Tracks 2 + 3 + 4 in parallel.** Three more `ui-design-expert` agents:
   - Agent for Track 2 (scripts gallery + tag gallery + notification-* helpers).
   - Agent for Track 3 (script detail page + comparison table + list item).
   - Agent for Track 4 (blog index + blog post).
   No file overlap between these tracks, so parallel-safe.

4. **Track 5 (me).** Quick mechanical cleanup — emojis to Lucide icons, unsubscribe page reskin to match v4. All small edits.

5. **Typecheck + build after each phase.** Catch regressions before they compound.

6. **Final pass:** `feature-dev:code-reviewer` over the whole diff. Verify no regressions on contracts (useScripts shape, modal close handlers, search shortcut, analytics events, trailing slashes, dark/light, mobile responsive).

7. **Preview verification:** screenshot at desktop + mobile for each reskinned surface. Confirm dark + light coherent.

## Acceptance criteria

1. Every reskinned file passes `npm run typecheck`.
2. `npm run build` succeeds at the end.
3. No file in the landing-page journey has `rounded-2xl`, `rounded-3xl`, `bg-gradient-to-*`, `from-{color}-{shade}` Tailwind utilities, or rainbow tag palettes.
4. Search dialog opens with v4 surface: `bg-card/40 backdrop-blur-md`, hairline border, mono labels on result rows, no Radix default chrome.
5. Script detail modal: same surface, action row matches v4 ScriptCard, badges replaced with mono kickers, no gradient overlays.
6. `/scripts/` and `/scripts/[tag]/` page chrome (filter UI, search bar, tag pills, headers) matches v4 vocabulary. ScriptCard grid inside is already v4 — don't touch.
7. `/script/[slug]/` page chrome matches v4. The "Deploy to Azure" panel uses Azure-blue accent properly.
8. Blog index + post pages match v4 typography (Geist + display class for headings, mono kickers for section markers, no gradient hero blocks).
9. `/unsubscribe/` page uses v4 surface treatment for the result states. Emojis replaced with Lucide icons sized appropriately (h-12 w-12 in `text-accent-hi` or `text-destructive`).
10. **No emojis remain anywhere in `web/src/`.**
11. All v4 motion respects `useReducedMotion()`.
12. Dark and light mode both render coherently on every reskinned surface.
13. Mobile (375px) renders without horizontal overflow on every reskinned surface.

## Out of scope (separate PRs)

- Atmospheric primitives (radial glows, grain overlays) extended to non-landing surfaces — those are intentionally landing-only signature moments.
- The "What's new" strip + Popular Scripts ordering — landing-page concern.
- SEO assets (OG image PNG, app icons 192/512, apple-touch-icon) — separate `public/` asset PR.
- Analytics events naming.

## Estimated time

- Track 1 audit + reskin: 15–20 min agent + 10 min verify = 30 min
- Tracks 2 + 3 + 4 parallel: 25–35 min agent + 15 min verify = 50 min
- Track 5 cleanup: 15 min self
- Final review + build: 15 min
- **Total: ~2 hours of agent + tool time.**

## Risks

1. **`script-detail.tsx` is 1108 lines.** Largest single reskin. Could overrun. Mitigation: clear contract to agent — surface treatment + token swap, don't redesign UX.
2. **Modal contracts.** Modal opens via `useScripts()` `selectedScript` + `isDetailOpen`. Must preserve: `onClose` push to `/`, analytics on click, the `scriptViewed` event dispatch. Document explicitly in agent brief.
3. **Page chrome vs ScriptCard.** Easy to accidentally restyle ScriptCard if the agent doesn't read the boundary. Spec the agent to leave `script-card.tsx` untouched.
4. **Blog uses MDX.** Custom typography in MDX is harder to control than vanilla JSX. May need a small `mdx-components.tsx` to enforce v4 prose styles.
5. **Dev preview is cache-fragile.** Each iteration I'll need to clear `.next` and restart preview at least once. Built into estimate.

## Sign-off question

This plan covers ~3,500 lines across ~15 files, with 5 parallel agent runs and ~2 hours of work. Confirm the scope before I launch, or trim if anything here is out of scope for the PR you want to ship today.
