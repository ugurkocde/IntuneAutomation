"use client";

import { useState } from "react";
import {
  Check,
  AlertTriangle,
  X,
  ShieldCheck,
  ChevronDown,
  Wand2,
} from "lucide-react";
import { cn } from "~/lib/utils";
import { Button } from "~/components/ui/button";
import type { LintFinding, LintResult } from "~/lib/generator-lint";

type Props = {
  result: LintResult;
  onFix?: () => void;
  fixDisabled?: boolean;
};

const categoryLabel: Record<LintFinding["category"], string> = {
  metadata: "Metadata",
  permissions: "Permissions",
  security: "Security",
  correctness: "Correctness",
  safety: "Safety",
};

export function LintPanel({ result, onFix, fixDisabled }: Props) {
  const [expanded, setExpanded] = useState(result.failCount > 0);

  const headerVariant: "ok" | "warn" | "fail" =
    result.failCount > 0
      ? "fail"
      : result.warnCount > 0
        ? "warn"
        : "ok";

  const variantStyles = {
    ok: "border-emerald-500/25 bg-emerald-500/[0.04]",
    warn: "border-amber-500/25 bg-amber-500/[0.04]",
    fail: "border-destructive/35 bg-destructive/[0.04]",
  };

  const variantAccent = {
    ok: "bg-emerald-500",
    warn: "bg-amber-500",
    fail: "bg-destructive",
  };

  const headerIcon =
    headerVariant === "ok" ? (
      <ShieldCheck className="text-emerald-500 h-4 w-4" />
    ) : headerVariant === "warn" ? (
      <AlertTriangle className="h-4 w-4 text-amber-500" />
    ) : (
      <X className="text-destructive h-4 w-4" />
    );

  const headerText =
    headerVariant === "ok"
      ? "Quality check passed"
      : headerVariant === "warn"
        ? `Quality check: ${result.warnCount} warning${result.warnCount === 1 ? "" : "s"}`
        : `Quality check: ${result.failCount} issue${result.failCount === 1 ? "" : "s"} found`;

  const fixableCount = result.failCount + result.warnCount;
  const showFixButton = fixableCount > 0 && !!onFix;

  return (
    <div
      className={cn(
        "relative mt-3 overflow-hidden rounded-xl border backdrop-blur-sm",
        variantStyles[headerVariant],
      )}
    >
      {/* Left accent rail — color-codes severity at a glance from a distance. */}
      <span
        className={cn(
          "absolute inset-y-0 left-0 w-[3px]",
          variantAccent[headerVariant],
          headerVariant === "ok" ? "opacity-50" : "opacity-70",
        )}
        aria-hidden="true"
      />
      <div
        role="button"
        tabIndex={0}
        aria-expanded={expanded}
        onClick={() => setExpanded((v) => !v)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            setExpanded((v) => !v);
          }
        }}
        className="focus-visible:ring-ring/50 hover:bg-foreground/[0.02] flex cursor-pointer items-center justify-between gap-2 px-3.5 py-2.5 pl-4 transition-colors select-none focus:outline-none focus-visible:ring-2"
      >
        <div className="flex flex-1 flex-wrap items-center gap-x-2.5 gap-y-1 text-left text-[13px]">
          {headerIcon}
          <span className="text-foreground font-medium">{headerText}</span>
          <span className="flex items-center gap-1.5 font-mono text-[10.5px] tracking-wider uppercase tabular-nums">
            {result.passCount > 0 && (
              <span className="inline-flex items-center gap-1 rounded-sm border border-emerald-500/30 bg-emerald-500/10 px-1.5 py-0.5 text-emerald-500">
                <span className="h-1 w-1 rounded-full bg-emerald-500" />
                {result.passCount} pass
              </span>
            )}
            {result.warnCount > 0 && (
              <span className="inline-flex items-center gap-1 rounded-sm border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-amber-500">
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
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          {showFixButton && (
            <Button
              size="sm"
              variant="outline"
              onClick={(e) => {
                e.stopPropagation();
                onFix?.();
              }}
              disabled={fixDisabled}
              className="border-border/70 h-7 cursor-pointer gap-1.5 text-xs"
              title="Send the issues back to the AI for correction"
            >
              <Wand2 className="h-3 w-3" />
              Fix with AI
            </Button>
          )}
          <ChevronDown
            className={cn(
              "text-muted-foreground h-3.5 w-3.5 transition-transform",
              expanded && "rotate-180",
            )}
            aria-hidden="true"
          />
        </div>
      </div>

      {expanded && (
        <ul className="border-border/40 divide-border/40 divide-y border-t">
          {result.findings.map((f) => (
            <li
              key={f.id}
              className="hover:bg-foreground/[0.015] flex gap-2.5 px-3.5 py-2.5 pl-4 text-[12.5px] leading-relaxed transition-colors"
            >
              <div className="mt-0.5 flex-shrink-0">
                {f.severity === "pass" ? (
                  <Check className="h-3.5 w-3.5 text-emerald-500" />
                ) : f.severity === "warn" ? (
                  <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />
                ) : (
                  <X className="text-destructive h-3.5 w-3.5" />
                )}
              </div>
              <div className="flex-1">
                <div className="text-foreground">
                  <span className="text-muted-foreground/80 mr-1.5 font-mono text-[10px] tracking-[0.14em] uppercase">
                    {categoryLabel[f.category]}
                  </span>
                  {f.message}
                </div>
                {f.detail && (
                  <div className="text-muted-foreground mt-0.5 text-[12px] leading-relaxed">
                    {f.detail}
                  </div>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
