"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Check,
  ChevronDown,
  Loader2,
  ShieldCheck,
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

const categoryLabel: Record<LintFinding["category"], string> = {
  metadata: "Metadata",
  permissions: "Permissions",
  security: "Security",
  correctness: "Correctness",
  safety: "Safety",
};

export function Inspector({
  isStreaming,
  isAutoFixing,
  endpointChecks,
  lintResult,
  onFix,
}: Props) {
  const verified = endpointChecks.filter((c) => c.known).length;
  const unknown = endpointChecks.length - verified;

  const showEmptyState =
    !isAutoFixing && endpointChecks.length === 0 && !lintResult;

  return (
    <div className="flex flex-col gap-3">
      <div className="border-border/70 bg-card overflow-hidden rounded-xl border shadow-md ring-1 ring-black/[0.02] dark:ring-white/[0.02]">
        <div className="border-border/70 bg-background/60 flex items-center gap-2 border-b px-3.5 py-2.5 backdrop-blur-sm">
          <span className="text-foreground text-[12.5px] font-medium">
            Inspector
          </span>
          {isStreaming && (
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

        {/* Graph endpoint checks — list of detected URIs with verification state */}
        {endpointChecks.length > 0 && (
          <div>
            <div className="border-border/40 flex items-center gap-2 border-b px-3.5 py-2 text-[11.5px]">
              <ShieldCheck
                className="text-muted-foreground h-3.5 w-3.5"
                aria-hidden="true"
              />
              <span className="text-foreground font-medium">
                Graph endpoints
              </span>
              <span
                className={cn(
                  "ml-auto inline-flex items-center gap-1 font-mono",
                  verified === endpointChecks.length
                    ? "text-emerald-600 dark:text-emerald-400"
                    : "text-muted-foreground",
                )}
              >
                <Check className="h-3 w-3" aria-hidden="true" />
                {verified}
              </span>
              {unknown > 0 && (
                <span className="inline-flex items-center gap-1 font-mono text-amber-600 dark:text-amber-400">
                  <AlertTriangle className="h-3 w-3" aria-hidden="true" />
                  {unknown}
                </span>
              )}
            </div>
            <ul className="divide-border/40 max-h-[200px] divide-y overflow-y-auto">
              {endpointChecks.map((c) => (
                <li
                  key={`${c.method} ${c.path}`}
                  className="flex items-start gap-2 px-3.5 py-2 text-[11.5px]"
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
          </div>
        )}

        {/* Quality check (post-stream lint) */}
        {lintResult && !isStreaming && !isAutoFixing && (
          <CompactLintSection result={lintResult} onFix={onFix} />
        )}

        {/* Empty state — pre-stream / nothing detected yet */}
        {showEmptyState && (
          <div className="px-3.5 py-6 text-center">
            <p className="text-muted-foreground/70 text-[11.5px] leading-relaxed">
              Checks will appear here as the script generates.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function CompactLintSection({
  result,
  onFix,
}: {
  result: LintResult;
  onFix?: () => void;
}) {
  const [expanded, setExpanded] = useState(result.failCount > 0);
  const fixable = result.failCount + result.warnCount;

  const tone: "ok" | "warn" | "fail" =
    result.failCount > 0 ? "fail" : result.warnCount > 0 ? "warn" : "ok";

  const headerIcon =
    tone === "ok" ? (
      <ShieldCheck className="h-3.5 w-3.5 text-emerald-500" />
    ) : tone === "warn" ? (
      <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />
    ) : (
      <X className="text-destructive h-3.5 w-3.5" />
    );

  const headerText =
    tone === "ok"
      ? "Quality check passed"
      : tone === "warn"
        ? `${result.warnCount} warning${result.warnCount === 1 ? "" : "s"}`
        : `${result.failCount} issue${result.failCount === 1 ? "" : "s"} found`;

  return (
    <div>
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="hover:bg-foreground/[0.02] flex w-full items-center gap-2 px-3.5 py-2.5 text-left transition-colors"
        aria-expanded={expanded}
      >
        {headerIcon}
        <span className="text-foreground flex-1 text-[12.5px] font-medium">
          {headerText}
        </span>
        <ChevronDown
          className={cn(
            "text-muted-foreground h-3.5 w-3.5 transition-transform",
            expanded && "rotate-180",
          )}
          aria-hidden="true"
        />
      </button>

      {/* Severity chips row */}
      <div className="flex flex-wrap items-center gap-1 px-3.5 pb-2 text-[11px] tabular-nums">
        {result.passCount > 0 && (
          <span className="inline-flex items-center gap-1 rounded-sm border border-emerald-500/30 bg-emerald-500/10 px-1.5 py-0.5 text-emerald-600 dark:text-emerald-400">
            <span className="h-1 w-1 rounded-full bg-emerald-500" />
            {result.passCount} pass
          </span>
        )}
        {result.warnCount > 0 && (
          <span className="inline-flex items-center gap-1 rounded-sm border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-amber-600 dark:text-amber-400">
            <span className="h-1 w-1 rounded-full bg-amber-500" />
            {result.warnCount} warn
          </span>
        )}
        {result.failCount > 0 && (
          <span className="border-destructive/40 bg-destructive/10 text-destructive inline-flex items-center gap-1 rounded-sm border px-1.5 py-0.5">
            <span className="bg-destructive h-1 w-1 rounded-full" />
            {result.failCount} fail
          </span>
        )}
      </div>

      {expanded && (
        <ul className="border-border/40 divide-border/40 max-h-[280px] divide-y overflow-y-auto border-t">
          {result.findings.map((f) => (
            <li
              key={f.id}
              className="flex gap-2 px-3.5 py-2 text-[11.5px] leading-relaxed"
            >
              <div className="mt-0.5 flex-shrink-0">
                {f.severity === "pass" ? (
                  <Check className="h-3 w-3 text-emerald-500" />
                ) : f.severity === "warn" ? (
                  <AlertTriangle className="h-3 w-3 text-amber-500" />
                ) : (
                  <X className="text-destructive h-3 w-3" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-foreground">
                  <span className="text-muted-foreground/70 mr-1.5 text-[10.5px]">
                    {categoryLabel[f.category]}
                  </span>
                  {f.message}
                </div>
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

      {fixable > 0 && !!onFix && (
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
