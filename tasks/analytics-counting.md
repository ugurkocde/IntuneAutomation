# Analytics counting fixes + stats page

## Plan

- [x] 1. DB: dedup infrastructure - `counted` column on script_views/script_downloads, bot UA filter, new BEFORE INSERT triggers (bot filter, require session_id, dedup window 60s downloads / 30min views, live weekly increments)
- [x] 2. DB: backfill `counted` on historical rows (bot UAs, null-session rows after 2025-07-01 when session tracking became universal, dedup windows)
- [x] 3. DB: rewrite refresh_weekly_analytics (counted only), add recalculate_all_analytics, revoke EXECUTE on all SECURITY DEFINER RPCs from anon/authenticated, drop replaced functions
- [x] 4. DB: pg_cron - hourly weekly refresh (:15), nightly full recalculation (03:30 UTC)
- [x] 5. DB: run one-time recalculation, verify aggregates match counted events
- [x] 6. DB: get_monthly_analytics(months) RPC for trends page (anon-executable, SECURITY INVOKER)
- [x] 7. Web: remove Monday-only resetWeeklyAnalytics call and now-dead recalculation code from /api/scripts and AnalyticsService
- [x] 8. Web: /stats page - monthly trends chart (12 months views + downloads) + all-time leaderboard from script_analytics, navbar link, metadata/sitemap
- [x] 9. Evaluate with code-reviewer subagent, typecheck, verify page renders

## Review

- Acceptance criteria all verified:
  - Reconciliation query returned 0 mismatched rows between script_analytics and counted events (totals and weekly)
  - Trigger test (rolled back): bot UA insert not counted, real insert counted once, 60s duplicate not counted, null-session insert not counted; raw rows stored in all cases
  - has_function_privilege confirms anon/authenticated cannot execute any SECURITY DEFINER function
  - cron.job shows refresh-weekly-analytics (hourly :15) and recalculate-analytics-nightly (03:30 UTC), both active
  - /stats verified in browser (light and dark): tiles, 12-month line chart, leaderboard with real data; typecheck and prettier clean
- Code reviewer found one real issue (fractional y-axis labels for small maxValue), fixed with Math.round on the displayed tick value
- Cleaned totals after backfill: downloads 7,162 (was 7,731 displayed, 7,401 raw), views 19,266 (was 39,019 displayed, 37,966 raw). Views dropped ~49 percent because null-session bot traffic dominated
- Supabase migrations applied: analytics_counted_dedup_triggers, analytics_backfill_counted, analytics_refresh_recalc_lockdown, analytics_cron_schedules, get_monthly_analytics_rpc

## Per-script trends (2026-07-19, second pass)

- [x] Supabase RPC get_script_monthly_analytics(p_script_id, months_back) - anon-executable, counted events only (migration get_script_monthly_analytics_rpc)
- [x] AnalyticsService.getScriptMonthlyAnalytics wrapper
- [x] MonthlyTrendsChart gained a compact prop (340x190 viewBox, no end labels, thinned x-labels) for narrow containers
- [x] ScriptUsageTrends client component (render-prop, hides itself when no counted activity or fetch fails)
- [x] Mounted on /script/[slug] pages (12-month section between Notes and Related scripts) and in the ScriptDetail dialog sidebar (compact, 6 months)
- [x] Verified both surfaces in browser with real data (PAT added to gitignored web/.env.local via gh auth token for local dev); typecheck and prettier clean
- [x] Code-reviewer pass: one real finding (stale chart flash when switching scripts inside a mounted dialog) fixed by resetting state on scriptId change in script-usage-trends.tsx

## Follow-ups (not done)

- Postgres patch upgrade (advisor warning) must be done in Supabase dashboard, causes brief downtime
- Schema SQL still lives only in Supabase migration history, not in the repo (supabase-schema.sql referenced by ANALYTICS_SETUP.md never existed in git)
- web/.env.local created locally (gitignored) with public anon key for live-data previews; launch config web-dev-live added
