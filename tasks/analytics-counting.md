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

## Runbooks deployed metric (2026-07-25, third pass)

Counts "Deploy to Azure" button clicks as a third series named "Runbooks deployed". This is a
click count, not a deployment-success count: the site opens portal.azure.com in a new tab and
never learns whether the ARM deployment finished, so the metric can only ever mean "opened the
deploy flow".

- [x] Dedicated `script_deployments` table rather than a fourth `download_type`, so azure clicks
      never inflate `total_downloads`. Same shape as script_downloads (`deploy_target` check
      constraint currently allows only 'azure'), same `counted` semantics, indexes mirrored,
      RLS = anon insert (validated) + anon select
- [x] `script_deployments_before_insert` trigger: bot UA filter, session_id required, 60s dedup
      window keyed by script + session + target, live increment of the new aggregate columns
- [x] `script_analytics` gained `total_deployments` / `weekly_deployments`; `refresh_weekly_analytics`
      and `recalculate_all_analytics` extended (third full join, third zero-out condition)
- [x] `get_monthly_analytics` / `get_script_monthly_analytics` dropped and recreated returning a
      third `deployments` column (return type change requires drop), anon EXECUTE re-granted
- [x] Removed the dead `download_type = 'azure'` path: the column CHECK constraint never allowed
      'azure' even though the RLS policy advertised it, so every azure insert from the dialog had
      been failing silently since it was added (0 rows ever written). Policy tightened to match
- [x] Tracking wired into all three Deploy buttons: /script/[slug] page (previously tracked
      nothing), ScriptDetail dialog (previously the broken azure download call), ScriptCard
      quick-action (previously tracked nothing)
- [x] Chart: third series driven off the SERIES constant (line, legend total, tooltip row, table
      column all derive from it). `--stat-deployments` reddish purple added per theme. End-of-line
      labels now nudge apart when series share a value, which they did with all three at 1
- [x] `usageStats.totalDeployments` surfaced in the /script/[slug] meta strip as "N runbook(s)
      deployed"; /stats gained a fifth tile and matching copy
- [x] Verified live: clicked all three real Deploy buttons, confirmed counted rows, aggregate
      increments, both RPCs, both API routes, meta strip and chart in the browser. Trigger checks
      (dedup / bot UA / null session / distinct session) verified against the real table
- [x] Locked down `script_deployments_before_insert` to match its siblings. Revoking from
      anon/authenticated alone was not enough: the function still carried the default `PUBLIC`
      grant (`=X/postgres` in proacl), which anon inherits, so it also needed
      `revoke execute ... from public`. ACL now identical to script_views/downloads
      (`{postgres=X,service_role=X}`), has_function_privilege false for anon and authenticated
      across all 7 SECURITY DEFINER functions, and both advisor warnings cleared. Verified the
      trigger still fires afterwards by inserting through the anon REST endpoint (counted=true,
      aggregate incremented) - Postgres does not check EXECUTE on trigger functions at fire time
- [x] Cleared the 3 verification clicks from `script_deployments` and re-ran
      `recalculate_all_analytics()`. Deployment counters back to 0 everywhere; views (19,652) and
      downloads (7,302) unchanged across all 73 rows, so the metric starts from real traffic only

## Follow-ups (not done)

- Postgres patch upgrade (advisor warning) must be done in Supabase dashboard, causes brief downtime
- Schema SQL still lives only in Supabase migration history, not in the repo (supabase-schema.sql referenced by ANALYTICS_SETUP.md never existed in git)
- web/.env.local created locally (gitignored) with public anon key for live-data previews; launch config web-dev-live added
