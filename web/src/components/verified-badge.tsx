"use client";

import { CheckCircle, XCircle, AlertTriangle, MinusCircle } from "lucide-react";
import { Badge } from "~/components/ui/badge";
import type { Script } from "~/lib/scripts";

interface VerifiedBadgeProps {
  script: Script;
  /** Variant controls sizing; "compact" suits list/grid cards. */
  variant?: "compact";
}

const colors = {
  pass: "text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-950/50 dark:border-green-800/50",
  fail: "text-red-600 bg-red-50 border-red-200 dark:text-red-400 dark:bg-red-950/50 dark:border-red-800/50",
  warning:
    "text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-950/50 dark:border-yellow-800/50",
  skip: "text-muted-foreground bg-muted/50 border-border",
} as const;

type ColorKey = keyof typeof colors;

/**
 * Returns a per-tier failure count summary string, e.g. "2 of 5 checks failing".
 * Returns null when no tier failed.
 */
function summarizeTiers(script: Script): {
  total: number;
  failed: number;
  status: ColorKey;
} | null {
  const tests = script.tests;
  if (!tests?.tests) return null;
  const tierStatuses = Object.values(tests.tests).map((t) => t.status);
  if (tierStatuses.length === 0) return null;
  const failed = tierStatuses.filter((s) => s === "fail").length;
  const status: ColorKey =
    tests.overall === "pass"
      ? "pass"
      : tests.overall === "fail"
        ? "fail"
        : "skip";
  return { total: tierStatuses.length, failed, status };
}

export function VerifiedBadge({ script }: VerifiedBadgeProps) {
  const structured = summarizeTiers(script);

  if (structured) {
    const { total, failed, status } = structured;
    const Icon =
      status === "pass"
        ? CheckCircle
        : status === "fail"
          ? XCircle
          : MinusCircle;
    const label =
      status === "pass"
        ? "Verified"
        : status === "fail"
          ? `${failed}/${total} failing`
          : "Not tested";
    const title =
      status === "pass"
        ? `All ${total} quality checks pass`
        : status === "fail"
          ? `${failed} of ${total} quality checks failing - open the script for details`
          : "Quality checks have not run on this script yet";
    return (
      <Badge
        variant="outline"
        className={`gap-1 border text-xs font-medium ${colors[status]}`}
        title={title}
      >
        <Icon className="h-3 w-3" />
        {label}
      </Badge>
    );
  }

  // Legacy fallback - single pass/fail/warning from testresults.json
  if (script.testResult) {
    const result = script.testResult.result;
    const Icon =
      result === "pass"
        ? CheckCircle
        : result === "fail"
          ? XCircle
          : AlertTriangle;
    const colorKey: ColorKey =
      result === "pass" ? "pass" : result === "fail" ? "fail" : "warning";
    return (
      <Badge
        variant="outline"
        className={`gap-1 border text-xs font-medium ${colors[colorKey]}`}
      >
        <Icon className="h-3 w-3" />
        {result === "pass" ? "Tested" : result}
      </Badge>
    );
  }

  return null;
}
