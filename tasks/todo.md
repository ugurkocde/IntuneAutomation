# Landing Page Redesign — IntuneAutomation.com

## Strategic synthesis (from UX, SEO, code, YC reviews)

**Core problems with current landing:**
- H1 is the brand name in a gradient, not the value prop. Cold visitors can't tell what this is.
- "Save 20+ hours per week" and "Trusted by IT Professionals Worldwide" are fabricated. No proof. Erodes trust with admin audience.
- Deploy-to-Azure (the genuine wedge versus copying from GitHub gists) is buried in Step 2 of "How It Works" and FAQ #3.
- All landing sections are client-rendered — AI crawlers (Perplexity, ChatGPT, Claude) see empty HTML.
- OG image and app icons are referenced in metadata but don't exist as files.
- FAQ schema emits 5 questions; the visible FAQ component renders 11. Citation leak.
- Fabricated `aggregateRating: 4.5/4.8` violates Google rich-results policy.
- Hero CTA uses `window.location.href = "/scripts"` instead of `<Link>` — no crawl signal.
- 6 popular-script tiles use click handlers, not anchors — 6 lost internal links per render.
- "Save 20+ hours" not substantiated. Need to lean on real numbers (scripts count, downloads, contributors, GitHub stars).

**Positioning (new):**
> Open-source PowerShell scripts for Microsoft Intune — copy them, or one-click deploy to Azure Automation as scheduled runbooks.

## Deliverable scope

### 1. SEO infrastructure
- [ ] Trim `<title>` to under 60 chars; convert to `{ default, template }` pattern in `layout.tsx`
- [ ] Remove redundant hand-rolled font preload in `layout.tsx` (lines 110-116) — `next/font` self-preloads
- [ ] Expand `icons` in metadata to include apple-touch + 192/512 png
- [ ] Add explicit allow rules for GPTBot, ClaudeBot, PerplexityBot, Google-Extended, etc. in `robots.ts`
- [ ] Fix `sitemap.ts` — replace `new Date()` with fixed dates so crawl budget isn't wasted
- [ ] Sync `FAQSchema` in `page.tsx` with the full 11 FAQs from `faq-section.tsx`
- [ ] Strip fabricated `aggregateRating` from `structured-data.tsx` (SoftwareSourceCodeSchema lines 146-157) and `script-structured-data.tsx`
- [ ] Add `Person` schema for Ugur Koc with credentials, sameAs
- [ ] Add `HowTo` schema for the 3-step flow
- [ ] Add `BreadcrumbList` for home
- [ ] Add `ItemList` for popular scripts
- [ ] Add SVG OG image fallback at `/public/og/intuneautomation-og.svg` (real PNG to be commissioned later)
- [ ] Add `apple-touch-icon.png` reference / placeholder

### 2. Server-render critical content
- [ ] `page.tsx` becomes a Server Component that fetches real stats and passes them to the client hero
- [ ] Stats numbers render server-side so AI crawlers see real values, not "..."
- [ ] Add SR-only "Quick Facts" block at top of body with definitional sentence (citation bait for GEO)

### 3. Hero redesign
- [ ] H1: keyword-rich product-class sentence; brand demoted to small kicker/wordmark
- [ ] Definitional opening sentence as the description (citation bait)
- [ ] One primary CTA: "Browse Scripts" → `<Link href="/scripts/">`
- [ ] One secondary CTA: "Star on GitHub" with live star count, real `<a href>` to repo
- [ ] Tertiary text-link: "See it deploy to Azure" anchoring to How It Works
- [ ] Strip rotating subtitle ticker; replace with category matrix or static value-prop bullets
- [ ] Strip "Save 20+ hours per week" — replace with real-number strip (scripts / downloads / contributors / stars)
- [ ] Reduce motion: pick one ambient effect (orbs OR particles), not both
- [ ] Remove `window.location.href` navigation in favor of `<Link>`
- [ ] Trust badges: link each to proof (license file, PSScriptAnalyzer report, contributors)
- [ ] Replace warning emoji in error fallback with icon

### 4. Stats integration
- [ ] Inline real numbers as a strip under the hero CTAs (eliminate separate `<StatsSection>` for redundancy OR keep as expanded breakdown later)
- [ ] Drop hyperbolic "Trusted by IT Professionals Worldwide" line
- [ ] Rename "Active Scripts" → "Scripts in library"

### 5. How It Works rework
- [ ] Split into 2 pathways: "Run locally" vs "Deploy to Azure (1-click)"
- [ ] Mock visual of Deploy-to-Azure button (the wedge feature)
- [ ] Code preview of the connect/run command (developers trust code samples)

### 6. Popular Scripts surface earlier
- [ ] Re-order page: Hero → PopularScripts → HowItWorks → FAQ → ...
- [ ] Wrap each script card in a real `<Link href="/script/{slug}/">` (modal can stay as enhancement via JS interception)

### 7. FAQ rework
- [ ] Re-order to match user funnel: Prerequisites → Safety/Security → How to run → Deploy to Azure → Maintenance → Technical opinions
- [ ] Optionally group with subheads ("Getting started", "Security & safety", "Technical details")
- [ ] Keep all 11 questions; ensure JSON-LD in `page.tsx` mirrors all 11

### 8. Ecosystem section
- [ ] Strip personal-pronoun framing ("tools I've built"); reframe as "Companion tools"
- [ ] Drop LinkedIn-follow CTA from the ecosystem block (already in footer)
- [ ] Remove placeholder comment in source

### 9. Floating subscription CTA
- [ ] Gate behind ≥1 script-view event; remove pure 60s timer trigger
- [ ] Replace "Join 500+" hardcoded fallback with rendering nothing if real count fetch fails
- [ ] Tighten copy: "One new Intune script in your inbox each Tuesday"

### 10. Footer
- [ ] Remove "Coffee + Heart" personal framing → product-mode copy
- [ ] Add legal links column (license, GitHub, blog, contributing)

## Acceptance criteria

1. `npm run typecheck` passes
2. `npm run build` succeeds
3. New `<h1>` describes the offering, not the brand name
4. No fabricated metrics ("Save 20+ hours", "Trusted by IT Professionals Worldwide")
5. No fake `aggregateRating` in any schema
6. FAQ JSON-LD includes all 11 questions (matches visible FAQ)
7. All landing internal navigation uses `<Link>` with trailing slash, not `window.location.href`
8. Hero CTAs include a GitHub link + star count + Deploy-to-Azure path
9. ScriptsProvider/AnalyticsProvider/useScripts contract preserved (no data flow regressions)
10. Theme toggle still functional; dark and light modes both visually coherent
11. Mobile responsive at ≤375px viewport
12. No emoji in source files (per global rules)
13. No new heavy dependencies
14. Subscription form still POSTs to Supabase `script_subscribers` correctly

## Out of scope (this PR)

- Designing a final raster OG image (placeholder SVG generated; commission png separately)
- `/about` and `/contact` pages
- Tree test / 5-second usability test (recommended next steps from UX)
- Restructuring `/scripts` route or script detail pages
