# Landing v2 — Refined Plan (post-review)

## What the reviews agreed on

**All four reviewers (YC, SaaS CEO, UI design expert, UX researcher) said:**

1. Aesthetic direction is correct — keep navy + phosphor cyan + 3-voice type system.
2. **Kill the H1 word-swap.** Same idea three times, rotating-ticker pattern in disguise, every AI startup uses crossfade text changes. Hold the H1 still.
3. **Kill the ambient pulse on the H1.** A still, confident H1 is stronger than an "alive" one.
4. **Kill the flip-counter on stats.** Datasheets don't count up; performing the truth instead of stating it is a consumer-SaaS tell.
5. **Too many motion systems.** UX counted 8 simultaneous on first paint. Cap: two intentional motions, no ambient loops.
6. **Surface the Microsoft MVP credential near the H1.** Currently buried in the footer. This is the most distinctive trust asset on the page — UI reviewer called it worth more than the entire blueprint grid.

**Sharp disagreement (3 of 4 vs UI expert):**

- Wire-draw from terminal to Azure card: YC + CEO + UX want it cut or de-emphasized. UI wanted to keep it as the only moment that "explains the wedge."
- **Resolution:** CEO's idea wins. Replace the wire animation with a **static annotated diagram of what gets deployed** — a small mock of the Azure portal showing the resource group, automation account, runbook, schedule, and managed identity that the ARM template provisions. Proof beats motion. The diagram explains the wedge AND survives scroll-skim AND doesn't depend on a 6-second animation most admins won't see.

**CEO's strategic add (huge):** redirect 60% of design effort to compounding levers. Within this PR's scope I can:
- Add a small "What's new" strip on the landing showing the 3 most recently added/updated scripts (drives return visits).
- Tighten the email CTA to a concrete promise: "Monthly: new scripts + Intune Graph API breakage alerts."

## What's NEW in this refined plan vs the draft

| Aspect | Draft v2 | Refined v2.1 |
|---|---|---|
| H1 word-swap | Three-state rotation | **Cut. Single still phrase.** |
| Ambient pulse on H1 | Every 6 seconds | **Cut.** |
| Stats animation | Flip-counter | **Cut. Render final-state.** |
| Wire-draw from terminal to Azure card | 1.2s drawing animation with particles | **Replaced** with a static "what gets deployed" diagram (resource group / runbook / schedule / identity). |
| Microsoft MVP credential | Tiny mono line in footer | **Promoted** to a small chip directly beneath the H1, alongside "Open source · MIT". |
| Terminal interaction | 6s typing animation, code not selectable until done | **Static by default with `Replay` affordance.** Code selectable from frame 1. |
| Body font | Geist 450 | **Manrope 500** (less recognized than Geist, warmer, still neutral). |
| Mono font | JetBrains Mono | **Geist Mono** (less ubiquitous than JetBrains, pairs natively with our existing Geist if Manrope swap reverts). |
| Display font | Instrument Serif italic | **Fraunces** (variable opsz axis, SOFT axis lets us dial warmth without changing fonts; more character than Instrument Serif). |
| Blueprint grid misalignment "tactile" | 1px intentional misalignment | **Cut.** Looks like a bug at 1x DPR. Clean grid only. |
| New: "What's new" strip | — | **Added.** 3 most recently updated scripts with relative timestamps, between hero and How It Works. |
| Email CTA copy | "Get script updates" | **"Monthly: new scripts + Intune Graph API breakage alerts. No marketing."** |
| Color contrast | Cyan at L=0.82 used for body labels too | Cyan body labels bumped to **L=0.86** for AA; sodium amber dropped to **L=0.75** to avoid vibrating with cyan when adjacent. |

## The two motions we keep

1. **A single choreographed page-load fade-in** — staggered 80ms across hero elements only. Settles in ~600ms total. Nothing else fires automatically.
2. **One scroll-triggered diagram draw** — the "How It Works" SVG flow lines animate left-to-right when the section enters the viewport, once. Respects `prefers-reduced-motion` with a fully drawn static fallback that is the *designed* state, not degraded.

That's it. No ambient loops. No typing terminal. No wire-draw. No flip counters. No magnetic buttons. The terminal in the hero is **static** with a `Replay` button users can opt into.

## The aesthetic, restated

**Editorial-technical, not Mission Control theater.** Cut 40% of the cinematic ambition per the CEO. The terminal carries all the "control panel" weight; the rest of the page is generous whitespace, considered typography, and a single phosphor accent reserved for high-information surfaces (the H1's key word, the trust-chip outline, the diagram lines, the primary CTA's focus ring).

Picture: a datasheet that respects you. Not Mission Control. Not Apollo. The work of someone who reads `Get-Help` for fun.

## Section-by-section deliverable (final)

| Section | Treatment |
|---|---|
| **Navbar** | Slim, glass blur. Wordmark in Geist Mono, no blinking cursor. |
| **Hero** | Asymmetric 7+5 (desktop), stacked (mobile). H1 in Fraunces, single still phrase. Beneath the H1: three small chips in mono — `OPEN SOURCE` · `MIT` · `MICROSOFT MVP`. CTAs: Browse scripts (primary, cyan focus ring) + Star on GitHub (with live count) + Search `/`. Right column: static terminal card with `Replay` button, plus the "what gets deployed" diagram beneath it. |
| **Stats** | Specs-sheet format. Numbers render final-state. No animation. |
| **"What's new" strip** | New section between hero and How It Works. 3 most recently updated scripts with `2d ago` / `1w ago` relative timestamps. Drives return visits. |
| **Popular Scripts** | Re-skin: sharp corners (4px), thin cyan top rule on hover only (not always-on), mono labels. Section heading: small mono kicker `// POPULAR THIS WEEK`, then Fraunces "Most used in the field." |
| **How It Works** | Horizontal SVG pipeline diagram. ONE scroll-triggered line draw. At mobile widths, **different layout** — vertical stacked steps with mono labels (NOT a transformed pipeline). |
| **FAQ** | Numbered 01, 02… in mono. Fraunces questions. Refined accordion. |
| **Companion tools** | 3-row manifest table, not cards. Mono project IDs, platform tags, thin underline links. |
| **Footer** | Tighter. Mono labels. Ink-thin rules between columns. Maintainer credit as a small mono line. |
| **Floating CTA** | Slim cyan-outlined pill (not balloon). Copy: "Monthly: new scripts + Intune Graph API breakage alerts." |

## Acceptance criteria (final)

1. New oklch palette is the dominant color story. Only Azure-blue retained, scoped exclusively to Deploy-to-Azure surfaces.
2. Three font voices loaded via `next/font/google`: **Fraunces** (display), **Manrope** (body), **Geist Mono** (mono/labels).
3. Microsoft MVP chip is visible above the fold, beneath the H1.
4. "What's new" strip renders 3 most recently updated scripts with relative timestamps.
5. Floating subscription CTA copy specifies the promise: "Monthly: new scripts + Intune Graph API breakage alerts."
6. Hero terminal is static by default with a `Replay` control; code is selectable from frame 1.
7. "How It Works" is an SVG pipeline diagram with one scroll-triggered draw. Mobile layout is purpose-built (not a transformed desktop).
8. No ambient animation loops. No typing terminal animation. No H1 word-swap. No flip-counters.
9. `prefers-reduced-motion`: fully drawn diagram is the static fallback, not a degraded state.
10. Cyan body labels meet AA contrast on the new navy background (L ≥ 0.86 for small text).
11. `npm run typecheck` and `npm run build` pass.
12. Mobile (375px) usable; pipeline collapses to a purpose-built vertical layout.
13. No new heavy dependencies. Two new Google fonts via `next/font`, no other additions.

## What I'm NOT doing in this pass

- No video, no WebGL, no paid fonts.
- No animated terminal typing (replaced with static + Replay button).
- No wire-draw animation (replaced with static "what gets deployed" diagram).
- No flip-counter on stats.
- No ambient loops.
- No magnetic buttons.
- No changes to the script detail modal, search dialog, or any other route.
- No data-contract changes (`useScripts`, AnalyticsProvider, modal lifecycle preserved).
- No `aggregateRating` reintroduced. No emojis introduced.

## Open question for the user before implementing

The biggest single trade I made vs the draft: **I cut the wire-draw animation** and **replaced it with a static labeled diagram of what the Azure deployment actually produces** (resource group, automation account, runbook, schedule, managed identity). Three of four reviewers wanted the animation gone; the CEO's "proof beats motion" framing won me over.

If you wanted the wire animation specifically because it would look slick — say so and I'll keep a constrained version (smaller, no particles, no timing-dependent reveal, just a fade-in of the static line). Otherwise I'll ship the static diagram.
