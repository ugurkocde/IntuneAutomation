"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Check,
  ChevronDown,
  Loader2,
  Wand2,
  X,
} from "lucide-react";
import { cn } from "~/lib/utils";
import { Button } from "~/components/ui/button";
import type { LintFinding, LintResult } from "~/lib/generator-lint";

export type EndpointCheckRow = {
  method: string;
  path: string;
  known: boolean;
};

type Props = {
  isStreaming: boolean;
  isAutoFixing: boolean;
  endpointChecks: EndpointCheckRow[];
  lintResult: LintResult | null;
  onFix?: () => void;
};

// Categories visible in the inspector, in the order they appear. These are the
// same buckets the lint pass tags findings with. "Graph endpoints" is split out
// because it has its own live-streaming list separate from category-level state.
const CHECK_CATEGORIES: LintFinding["category"][] = [
  "metadata",
  "permissions",
  "security",
  "correctness",
  "safety",
];

const categoryLabel: Record<LintFinding["category"], string> = {
  metadata: "Metadata",
  permissions: "Permissions",
  security: "Security",
  correctness: "Correctness",
  safety: "Safety",
};

const categoryTooltip: Record<LintFinding["category"], string> = {
  metadata:
    "The comment-based help block: all 12 required fields present, AI-generated author tag, .LASTUPDATE is today.",
  permissions:
    "Every scope in .PERMISSIONS exists in the official Microsoft Graph permission list (~700 scopes).",
  security:
    "Code-injection and credential-leak risks: no Invoke-Expression, no hardcoded passwords/keys, no ExecutionPolicy Bypass, no non-Microsoft external URLs.",
  correctness:
    "Logic bugs: cmdlet misuse, null-unsafe [DateTime]::Parse on Graph fields, Connect-MgGraph -Identity without an Azure Automation branch, /v1.0 Graph URIs.",
  safety:
    "Destructive operations (retire / wipe / delete) are gated by [CmdletBinding(SupportsShouldProcess=$true)] so -WhatIf and -Confirm work.",
};

type CategoryState =
  | { status: "pending" }
  | { status: "pass" }
  | { status: "warn"; count: number; findings: LintFinding[] }
  | { status: "fail"; count: number; findings: LintFinding[] };

// Pass findings whose meaning is "we saw what we needed" — committable as soon
// as they appear, even mid-stream. Other pass findings ("no dangerous pattern
// detected") are absence-based and only become trustworthy once the stream
// completes, so the corresponding categories stay pending until then.
const EARLY_COMMIT_PASS_IDS = new Set([
  "metadata-complete",
  "author-correct",
  "date-current",
  "permissions-valid",
  "permissions-none",
  "destructive-with-shouldprocess",
]);

function categoryState(
  category: LintFinding["category"],
  isStreaming: boolean,
  isAutoFixing: boolean,
  lintResult: LintResult | null,
): CategoryState {
  if (isAutoFixing) return { status: "pending" };
  if (!lintResult) return { status: "pending" };

  const inCategory = lintResult.findings.filter(
    (f) =>
      f.category === category &&
      // The Graph endpoint findings are surfaced in their own section, not in
      // Correctness — exclude them here so the row doesn't double-report.
      !f.id.startsWith("graph-endpoint"),
  );
  const fails = inCategory.filter((f) => f.severity === "fail");
  const warns = inCategory.filter((f) => f.severity === "warn");
  if (fails.length > 0)
    return { status: "fail", count: fails.length, findings: inCategory };
  if (warns.length > 0)
    return { status: "warn", count: warns.length, findings: inCategory };

  // No findings yet. If the stream is done, that's a real pass.
  if (!isStreaming) return { status: "pass" };

  // During streaming, only commit pass when we have a presence-based pass
  // signal for this category. Absence-based "all clear" findings (e.g.
  // no-dangerous-patterns) could flip later as more body streams in — hold
  // those categories at pending.
  const earlyPass = inCategory.some(
    (f) => f.severity === "pass" && EARLY_COMMIT_PASS_IDS.has(f.id),
  );
  return earlyPass ? { status: "pass" } : { status: "pending" };
}

export function Inspector({
  isStreaming,
  isAutoFixing,
  endpointChecks,
  lintResult,
  onFix,
}: Props) {
  const fixable =
    (lintResult?.failCount ?? 0) + (lintResult?.warnCount ?? 0) > 0;
  const showFix = fixable && !!onFix && !isStreaming && !isAutoFixing;

  return (
    <div className="border-border/70 bg-card overflow-hidden rounded-xl border shadow-md ring-1 ring-black/[0.02] dark:ring-white/[0.02]">
      <div className="border-border/70 bg-background/60 flex items-center gap-2 border-b px-3.5 py-2.5 backdrop-blur-sm">
        <span className="text-foreground text-[12.5px] font-medium">
          Inspector
        </span>
        {(isStreaming || isAutoFixing) && (
          <span className="text-muted-foreground ml-auto inline-flex items-center gap-1 text-[11px]">
            <span
              className="h-1.5 w-1.5 animate-pulse rounded-full bg-current"
              aria-hidden="true"
            />
            live
          </span>
        )}
      </div>

      {/* Auto-fix status */}
      {isAutoFixing && (
        <div className="border-border/40 border-b px-3.5 py-2.5">
          <div className="text-foreground inline-flex items-center gap-2 text-[12.5px]">
            <Loader2 className="text-accent h-3.5 w-3.5 animate-spin" />
            <span className="font-medium">Polishing automatically</span>
          </div>
          <p className="text-muted-foreground mt-1 text-[11.5px] leading-relaxed">
            The first pass had issues. We&apos;re re-generating a cleaned-up
            version automatically.
          </p>
        </div>
      )}

      {/* Category check list — known set of checks, each transitions from
        spinner -> pass/warn/fail when the stream completes and lint runs. */}
      <ul className="divide-border/40 divide-y">
        {CHECK_CATEGORIES.map((cat) => (
          <CategoryRow
            key={cat}
            category={cat}
            state={categoryState(cat, isStreaming, isAutoFixing, lintResult)}
          />
        ))}
      </ul>

      {/* Graph endpoint section — live during streaming, summary after */}
      <GraphEndpointSection
        isStreaming={isStreaming}
        isAutoFixing={isAutoFixing}
        endpointChecks={endpointChecks}
      />

      {showFix && (
        <div className="border-border/40 border-t px-3.5 py-2.5">
          <Button
            size="sm"
            variant="outline"
            onClick={onFix}
            className="border-border/70 h-8 w-full cursor-pointer gap-1.5 text-xs"
          >
            <Wand2 className="h-3 w-3" />
            Fix with AI
          </Button>
        </div>
      )}
    </div>
  );
}

function CategoryRow({
  category,
  state,
}: {
  category: LintFinding["category"];
  state: CategoryState;
}) {
  const [expanded, setExpanded] = useState(false);
  const label = categoryLabel[category];

  const icon =
    state.status === "pending" ? (
      <Loader2
        className="text-muted-foreground/60 h-3.5 w-3.5 animate-spin"
        aria-hidden="true"
      />
    ) : state.status === "pass" ? (
      <Check className="h-3.5 w-3.5 text-emerald-500" aria-hidden="true" />
    ) : state.status === "warn" ? (
      <AlertTriangle
        className="h-3.5 w-3.5 text-amber-500"
        aria-hidden="true"
      />
    ) : (
      <X className="text-destructive h-3.5 w-3.5" aria-hidden="true" />
    );

  const canExpand = state.status === "warn" || state.status === "fail";
  const findings = canExpand ? state.findings : [];

  return (
    <li>
      <button
        type="button"
        onClick={() => canExpand && setExpanded((v) => !v)}
        disabled={!canExpand}
        title={categoryTooltip[category]}
        className={cn(
          "flex w-full items-center gap-2 px-3.5 py-2 text-left text-[12.5px]",
          canExpand && "hover:bg-foreground/[0.02] cursor-pointer",
        )}
        aria-expanded={canExpand ? expanded : undefined}
      >
        {icon}
        <span
          className={cn(
            "flex-1",
            state.status === "pending"
              ? "text-muted-foreground"
              : "text-foreground",
          )}
        >
          {label}
        </span>
        {(state.status === "warn" || state.status === "fail") && (
          <span
            className={cn(
              "rounded-sm border px-1.5 py-0.5 text-[10.5px] font-medium tabular-nums",
              state.status === "warn"
                ? "border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                : "border-destructive/40 bg-destructive/10 text-destructive",
            )}
          >
            {state.count}
          </span>
        )}
        {canExpand && (
          <ChevronDown
            className={cn(
              "text-muted-foreground h-3 w-3 transition-transform",
              expanded && "rotate-180",
            )}
            aria-hidden="true"
          />
        )}
      </button>
      {expanded && findings.length > 0 && (
        <ul className="border-border/40 bg-muted/20 border-t px-3.5 py-2">
          {findings.map((f) => (
            <li
              key={f.id}
              className="flex gap-2 py-1 text-[11.5px] leading-relaxed first:pt-0 last:pb-0"
            >
              <span className="mt-0.5 flex-shrink-0">
                {f.severity === "pass" ? (
                  <Check className="h-3 w-3 text-emerald-500" />
                ) : f.severity === "warn" ? (
                  <AlertTriangle className="h-3 w-3 text-amber-500" />
                ) : (
                  <X className="text-destructive h-3 w-3" />
                )}
              </span>
              <div className="min-w-0 flex-1">
                <div className="text-foreground">{f.message}</div>
                {f.detail && (
                  <div className="text-muted-foreground mt-0.5 text-[11px] leading-relaxed">
                    {f.detail}
                  </div>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </li>
  );
}

function GraphEndpointSection({
  isStreaming,
  isAutoFixing,
  endpointChecks,
}: {
  isStreaming: boolean;
  isAutoFixing: boolean;
  endpointChecks: EndpointCheckRow[];
}) {
  const verified = endpointChecks.filter((c) => c.known).length;
  const unknown = endpointChecks.length - verified;
  const inFlight = isStreaming || isAutoFixing;

  // While there are no endpoints detected yet AND streaming hasn't started a
  // useful pass, show a pending row so the section's purpose is visible.
  const showPending = inFlight && endpointChecks.length === 0;

  return (
    <div className="border-border/40 border-t">
      <div
        className="flex items-center gap-2 px-3.5 py-2 text-[12.5px]"
        title="Every literal https://graph.microsoft.com/... URI in the script is matched against the published Microsoft Graph endpoint catalog (6,300+ endpoints). Unknown URIs are flagged with up to 3 closest known matches as suggestions."
      >
        {showPending ? (
          <Loader2
            className="text-muted-foreground/60 h-3.5 w-3.5 animate-spin"
            aria-hidden="true"
          />
        ) : endpointChecks.length === 0 ? (
          <Check
            className="text-muted-foreground/40 h-3.5 w-3.5"
            aria-hidden="true"
          />
        ) : verified === endpointChecks.length ? (
          <Check className="h-3.5 w-3.5 text-emerald-500" aria-hidden="true" />
        ) : (
          <AlertTriangle
            className="h-3.5 w-3.5 text-amber-500"
            aria-hidden="true"
          />
        )}
        <span
          className={cn(
            "flex-1",
            showPending ? "text-muted-foreground" : "text-foreground",
          )}
        >
          Graph endpoints
        </span>
        {endpointChecks.length > 0 && (
          <span className="text-muted-foreground inline-flex items-center gap-1.5 text-[11px] tabular-nums">
            <span
              className={cn(
                "inline-flex items-center gap-1",
                verified === endpointChecks.length &&
                  "text-emerald-600 dark:text-emerald-400",
              )}
            >
              <Check className="h-3 w-3" aria-hidden="true" />
              {verified}
            </span>
            {unknown > 0 && (
              <span className="inline-flex items-center gap-1 text-amber-600 dark:text-amber-400">
                <AlertTriangle className="h-3 w-3" aria-hidden="true" />
                {unknown}
              </span>
            )}
          </span>
        )}
      </div>

      {endpointChecks.length > 0 && (
        <ul className="border-border/40 max-h-[200px] divide-y divide-border/40 overflow-y-auto border-t">
          {endpointChecks.map((c) => (
            <li
              key={`${c.method} ${c.path}`}
              className="animate-in fade-in slide-in-from-right-1 flex items-start gap-2 px-3.5 py-2 text-[11.5px] duration-300"
            >
              <span className="mt-0.5 flex-shrink-0">
                {c.known ? (
                  <Check className="h-3 w-3 text-emerald-500" />
                ) : (
                  <AlertTriangle className="h-3 w-3 text-amber-500" />
                )}
              </span>
              <span className="min-w-0 flex-1 font-mono leading-snug break-words">
                <span className="text-muted-foreground/80 mr-1">
                  {c.method}
                </span>
                <span className="text-foreground">{c.path}</span>
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
