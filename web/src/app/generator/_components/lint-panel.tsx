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
    ok: "border-emerald-500/30 bg-emerald-500/5",
    warn: "border-amber-500/30 bg-amber-500/5",
    fail: "border-destructive/40 bg-destructive/5",
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
        "mt-3 overflow-hidden rounded-md border",
        variantStyles[headerVariant],
      )}
    >
      <div className="flex items-center justify-between gap-2 px-3 py-2">
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="flex flex-1 items-center gap-2 text-left text-[13px]"
          aria-expanded={expanded}
        >
          {headerIcon}
          <span className="text-foreground font-medium">{headerText}</span>
          <span className="text-muted-foreground text-[12px]">
            {result.passCount} pass · {result.warnCount} warn ·{" "}
            {result.failCount} fail
          </span>
        </button>
        <div className="flex items-center gap-1.5">
          {showFixButton && (
            <Button
              size="sm"
              variant="outline"
              onClick={onFix}
              disabled={fixDisabled}
              className="border-border/70 h-7 gap-1.5 text-xs"
              title="Send the issues back to the AI for correction"
            >
              <Wand2 className="h-3 w-3" />
              Fix with AI
            </Button>
          )}
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            aria-label={expanded ? "Collapse" : "Expand"}
            className="text-muted-foreground rounded-md p-1.5"
          >
            <ChevronDown
              className={cn(
                "h-3.5 w-3.5 transition-transform",
                expanded && "rotate-180",
              )}
            />
          </button>
        </div>
      </div>

      {expanded && (
        <ul className="border-border/40 divide-y divide-current/10 border-t">
          {result.findings.map((f) => (
            <li
              key={f.id}
              className="flex gap-2.5 px-3 py-2 text-[12.5px] leading-relaxed"
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
                  <span className="text-muted-foreground mr-1.5 font-mono text-[10px] tracking-wider uppercase">
                    {categoryLabel[f.category]}
                  </span>
                  {f.message}
                </div>
                {f.detail && (
                  <div className="text-muted-foreground mt-0.5 text-[12px]">
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
