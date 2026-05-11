# IntuneAutomation Landing v2 — "Mission Control" Aesthetic

## What's wrong with v1 (my honest critique)

1. **No identity.** Looks like every other dev-tools site. Forgettable.
2. **Color is dead.** Black/white/one-blue is lazy minimalism, not refined minimalism.
3. **No signature moment.** Static terminal + static Azure card. Nothing demonstrates the product.
4. **Typography is one-note.** Geist at 6 sizes. No display contrast, no character.
5. **"Two ways" cards are flat boxes.** No depth, no light, no interaction.
6. **Animations are dead fade-ins.** No scroll choreography, no magnetic buttons, no surprises.
7. **Ecosystem section clashes** — leftover gradient cards from old design.

## Aesthetic direction: "Mission Control / Engineering Blueprint"

A precision instrument for IT operations. Think Apollo mission control × architectural blueprint × modern editorial. Technical confidence, not marketing softness. The audience is admins who run scripts in production tenants — they should feel like the site is built by someone who respects the gravity of that work.

### Palette (oklch, dark-first)

```
--bg          oklch(0.16 0.025 250)   /* midnight navy, not pure black */
--bg-elevated oklch(0.20 0.030 250)
--bg-glass    oklch(0.22 0.035 250 / 0.6)
--fg          oklch(0.96 0.005 90)    /* warm white, not pure */
--fg-muted    oklch(0.68 0.022 250)
--rule        oklch(0.32 0.035 250 / 0.5)  /* blueprint grid lines */
--accent      oklch(0.82 0.18 195)    /* phosphor cyan — THE signature */
--accent-glow oklch(0.82 0.18 195 / 0.35)
--warn        oklch(0.80 0.18 75)     /* sodium amber — used once, for "live" */
--azure       oklch(0.62 0.18 244)    /* reserved for Deploy-to-Azure only */
```

Light mode mirrors these with cream backgrounds, ink foregrounds, and the same accents — but it's secondary; design dark-first.

### Typography (3 voices)

- **Display**: `Instrument Serif` (Google Fonts, free) — italic, used ONCE for the H1 and ONCE for a section opener. Massive (clamp 4rem → 7rem).
- **Body & UI**: keep `Geist` — but tighten tracking to -0.02em on headlines and use 450 weight (not bold) for most text.
- **Mono / labels**: `JetBrains Mono` (Google Fonts, free) — for code, stats, technical labels, every UPPERCASE tracked-wide tag.

This three-voice system gives the site instant character without paid fonts.

### Signature visual moments

1. **The H1 itself.** Instrument Serif italic, ultra-large, with one word colored phosphor-cyan: *"Open-source PowerShell scripts, **ready** for Microsoft Intune."* On scroll, the cyan word swaps to "**production-ready**" then "**Azure-ready**" via a 600ms crossfade — but only TWICE, then it settles. Not a ticker.

2. **The blueprint background.** SVG grid (40px modules) with faded cyan rules, slightly imperfect (1px misalignment for tactile feel). A single faint annotation line points from the H1 to the terminal, like an engineering callout.

3. **The "live terminal" hero card.** Real typing animation that runs once on load (~6 seconds), types `Connect-MgGraph -Scopes ...` then `.\get-stale-devices.ps1` then a streaming output `→ 142 stale devices found`. After typing completes, a cyan wire animates from the terminal's bottom edge to the Deploy-to-Azure card below it, drawn over 1.2s, with two small particles flowing along the wire. Then everything rests.

4. **Stats as a "specs sheet."** Not 4 boxes. A vertical instrument-panel list:
   ```
   SCRIPTS IN LIBRARY  ················ 127
   TOTAL DOWNLOADS     ················ 24.6K
   GITHUB STARS        ················ 98  ⬆ +12 this month
   CONTRIBUTORS        ················ 18
   ```
   Each number rolls in from 000 → real value via a 1.5s flip-counter (only on first scroll into view).

5. **"How It Works" as a horizontal pipeline diagram.** Instead of two cards, render one continuous SVG flow:
   ```
   YOUR SCRIPT ──┬── (local) PowerShell + Connect-MgGraph ──→ TENANT
                 └── (cloud) Deploy to Azure ──→ Runbook ──→ TENANT
   ```
   The two paths visibly branch from a single source and converge on the same outcome. Lines are cyan, animated to draw left-to-right on scroll. Each node is a small instrument-panel card with mono labels.

6. **Magnetic buttons.** Primary CTA has cursor-following slight translation (max 4px) on hover, with a subtle phosphor glow that intensifies as you approach. Subtle, not gimmicky.

7. **The "Companion tools" section becomes a manifest.** Treat it like the back-page of a technical manual. Three rows in a single table-like layout (not cards), with monospace project IDs, platform tags, and a single thin underline link. Removes the gradient cards entirely.

### Layout breaks the grid

- **Hero**: 7+5 asymmetric split (not 6+6). H1 dominates the left, terminal floats right slightly cropped at the page edge to feel "in motion."
- **Pipeline section**: full-bleed background with the SVG diagram extending into the page margins.
- **Stats / specs sheet**: narrow centered column (max-w-prose), feels like a product datasheet.
- **Popular Scripts**: keep grid but reskin cards — sharp corners (radius 4px not 12px), thin cyan top border, mono labels.

### Motion principles

- One choreographed page-load (staggered reveals 80ms apart).
- Scroll-triggered draws (the pipeline lines, the stats counters).
- Hover micro-interactions are subtle, not bouncy. No `scale: 1.05`. Use `translate-y: -2px` + glow.
- All animations respect `prefers-reduced-motion`.
- One ambient effect: a single faint cyan pulse on the H1's accent word, every 6 seconds. Calm but alive.

### Section-by-section deliverable

| Section | Treatment |
|---|---|
| Navbar | Slim, glass blur, mono logo wordmark "INTUNEAUTOMATION ▮" with blinking cursor. Minimal links. |
| Hero | Asymmetric. Display H1 + word-swap. Animated terminal. Wire-draw to Azure card. Stats as specs sheet under it. |
| Popular Scripts | Re-skinned cards (sharp, thin cyan rule, mono labels). Keep the grid. Section heading: small mono label "// POPULAR THIS WEEK" then display serif "Most used in the field." |
| How It Works | Replace with the horizontal pipeline diagram. One sentence opener. |
| FAQ | Reskin: numbered (01, 02...) in mono, instrument serif question text, refined accordion. |
| Companion tools | Becomes a 3-row manifest table, not cards. |
| Footer | Tighter. Mono labels, ink-thin rules between columns. Maintainer credit as a small mono line: `MAINTAINED BY UGUR KOC ▮ MICROSOFT MVP`. |
| Floating CTA | Stays gated. Reskin as a slim cyan-outlined pill, not a balloon. |

### Files affected

- `web/src/components/hero-section.tsx` — heavy rewrite
- `web/src/components/how-it-works-section.tsx` — full rewrite (pipeline SVG)
- `web/src/components/popular-scripts.tsx` — card reskin
- `web/src/components/script-card.tsx` — minor reskin (sharp corners, mono labels)
- `web/src/components/ecosystem-section.tsx` — replace cards with manifest table
- `web/src/components/footer.tsx` — typography pass
- `web/src/components/navbar.tsx` — wordmark + mono treatment
- `web/src/components/faq-section.tsx` — accordion reskin + numbering
- `web/src/components/floating-subscription-cta.tsx` — pill reskin
- `web/src/styles/globals.css` — full palette swap (oklch), add 3-voice font system
- `web/src/app/layout.tsx` — load Instrument Serif + JetBrains Mono via `next/font/google`
- `web/tailwind.config.js` — extend theme tokens to match new variables

### Acceptance criteria

1. New palette is the dominant color story; no leftover blue/purple gradient remnants on the landing route.
2. Three font voices are loaded and visible: display serif (H1), body sans (Geist), mono (labels/code).
3. Hero has a working animated terminal that types out a real PowerShell snippet on load.
4. "How It Works" is the SVG pipeline diagram, not two boxes.
5. Stats render as a specs-sheet list with rolling counter animation.
6. Companion tools render as a manifest table, not gradient cards.
7. `npm run typecheck` and `npm run build` pass.
8. No console errors in preview.
9. Mobile (375px) usable — pipeline collapses to vertical, hero stacks, terminal scrolls horizontally if needed.
10. `prefers-reduced-motion` honored — all animations have a static fallback.
11. Dark and light modes both polished. Dark is primary; light is secondary but coherent.
12. No new heavy dependencies. Two Google fonts via `next/font`, no other additions.

### What I'm NOT doing in this pass

- No new icon library (stick with lucide-react).
- No 3D / WebGL / Three.js.
- No video assets.
- No paid fonts.
- Not changing data contracts (`useScripts`, AnalyticsProvider, modal lifecycle) — same as v1 constraints.
- Not touching the script detail modal, search dialog, blog, or any other route.
