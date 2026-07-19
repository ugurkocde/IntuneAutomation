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

## MgGraphCommunity auth migration (2026-07-19)

Swap local interactive auth in all Graph scripts to MgGraphCommunity (WAM-free); runbook path untouched.

- [x] Add MgGraphCommunity to $RequiredModules for local runs only (auto-install via existing Initialize-RequiredModule)
- [x] Replace Connect-MgGraph -Scopes with Connect-MgGraphCommunity -Scopes in the local branch (30 scripts)
- [x] Remove vestigial Microsoft.Graph.Mail requirement from notification scripts (mail sent via REST /sendMail)
- [x] Bump .VERSION, add .CHANGELOG entry, set .LASTUPDATE, add .NOTES line per modified script
- [x] Verify: every modified file parses clean (PowerShell parser), runbook branch unchanged, no typed cmdlets introduced
- [x] Evaluate with code-reviewer subagent

Acceptance criteria:
1. All 30 interactive scripts call Connect-MgGraphCommunity in the local branch and still call Connect-MgGraph -Identity in the Azure Automation branch.
2. MgGraphCommunity is never required/installed in the Azure Automation path.
3. Invoke-MgGraphRequest / Disconnect-MgGraph usage unchanged (token handoff covers them).
4. Zero parse errors across modified scripts.
5. Headers updated (VERSION, CHANGELOG, LASTUPDATE, NOTES) in every modified script.

Review (2026-07-19): 29 of 30 interactive scripts migrated; all six acceptance criteria confirmed by code-reviewer subagent; zero parse errors. Excluded: backup-bitlocker-keys-to-keyvault.ps1 (cross-resource Key Vault token, flagged as separate task). Notification README Mail-module references cleaned. Not committed yet.

Website banner (2026-07-19): site-wide announcement bar added in web/src/components/announcement-banner.tsx, rendered from the root layout above the navbar. Client-side date gate expires it automatically on 2026-07-26 (no redeploy needed); dismiss button persists via localStorage. Verified in browser: renders in dark and light mode, expiry hides it, dismiss persists across reload. Typecheck clean.

Key Vault script rework (2026-07-19): backup-bitlocker-keys-to-keyvault.ps1 reworked and review-approved. Auth: two MgGraphCommunity sessions (device code for vault audience, interactive for Graph), per-call session toggle in Set-KeyVaultSecret with finally-restore. Live Graph verification via Lokka proved the old retrieval path could never return keys (windowsProtectionState has no bitLockerStatus; hardwareInformation select lacks azureADDeviceId); retrieval now uses informationProtection/bitlocker/recoveryKeys by azureADDeviceId with isEncrypted pre-filter. Secret version parsed from id URI. Remaining live-test item: first real run needs interactive sign-ins plus one-time Key Vault consent. Not committed.

Live end-to-end validation (2026-07-19): backup-bitlocker-keys-to-keyvault.ps1 executed for real with user sign-ins. All green: vault-audience token via device code (aud cfa8b339), Graph token with BitlockerKey.Read.All, SDK handoff, session toggle, post-toggle Graph probe, recovery key read, secret written to bitlockerfilevaultkeys and confirmed via ARM. Key Vault Secrets Officer granted to admin account on the vault (user, portal). Fixed during validation: MgGraphCommunity 1.4.0 minimum version requirement (1.3.0 lacks session commands), single-key array unrolling in retrieval function.

Endpoint audit of 29 scripts (2026-07-19, live via Lokka + msgraph docs): auth migration itself clean; audit found pre-existing breakage. BROKEN: mobileApps/{id}/deviceStatuses retired from service (kills get-app-installation-status-report, app-deployment-failure-alert, create-app-based-groups detection path; replacement is deviceManagement/reports actions); wipe-devices, rotate-macos-laps-passwords, check-filevault-keys all missing DeviceManagementManagedDevices.PrivilegedOperations.All scope (actions always 403); get-maa-compliance-report uses v1.0 deviceManagementScripts (beta-only) and treats group IDs as user IDs; get-endpoint-analytics-report WFA collection GET 400s (needs ('allDevices')/metricDevices pattern). SUSPECT: maa-pending-requests-monitor reads 6+ nonexistent operationApprovalRequest properties; device-compliance-drift-alert reads deviceCompliancePolicyStates without $expand; app-deployment-failure-alert dead isBuiltIn filter. Full agent report in session transcript. Fixes not yet applied.

Audit fixes applied (2026-07-19): all 9 audit findings fixed. Scope additions (PrivilegedOperations.All) in wipe-devices, rotate-macos-laps-passwords, check-filevault-keys. Schema fixes live-verified via Lokka in get-maa-compliance-report (beta scripts endpoint + group member resolution), get-endpoint-analytics-report (WFA metricDevices route), maa-pending-requests-monitor (real operationApprovalRequest schema), device-compliance-drift-alert (per-device policy states). deviceStatuses retirement: three scripts rewritten onto POST deviceManagement/reports/retrieveDeviceAppInstallationStatusReport (columnar schema mapped by name, InstallState enum from resultantAppState docs, confirmed live incl. localized state column). 30 files parse clean. Reviewer pass pending. Not committed.

Reviewer round on audit fixes (2026-07-19): groups 1 and 2 (7 scripts) passed outright. Two findings in the deviceStatuses rewrite fixed per reviewer prescription and simulation-verified: paging sentinel ([int]::MaxValue) so a first-page 429 retries instead of silently returning empty, and FilterByInstallState wildcard match so "pending" matches "pendingInstall". All 30 modified scripts parse clean. Batch complete, awaiting commit.
