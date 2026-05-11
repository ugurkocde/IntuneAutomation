"use client";

import { CheckCircle, XCircle, MinusCircle, ShieldCheck } from "lucide-react";
import { Badge } from "~/components/ui/badge";
import type { ScriptTestTier, ScriptTests, TierStatus } from "~/lib/scripts";

interface QualityChecksProps {
  tests: ScriptTests;
}

const POWERSHELL_TIERS: Array<{
  key: string;
  label: string;
  description: string;
}> = [
  {
    key: "parse",
    label: "Parse",
    description: "The script parses as valid PowerShell.",
  },
  {
    key: "lint",
    label: "Lint",
    description: "PSScriptAnalyzer found no Error or Warning issues.",
  },
  {
    key: "metadata",
    label: "Metadata",
    description:
      "All required documentation fields are present in the script header.",
  },
  {
    key: "runbookReady",
    label: "Runbook-ready",
    description:
      "No interactive cmdlets that would block in an Azure Automation runbook.",
  },
  {
    key: "moduleDeps",
    label: "Module deps",
    description:
      "All imported modules resolve to known Microsoft Graph / Azure module families.",
  },
];

const SHELL_TIERS: Array<{
  key: string;
  label: string;
  description: string;
}> = [
  {
    key: "shellcheck",
    label: "ShellCheck",
    description: "ShellCheck reported zero issues.",
  },
];

const statusStyles: Record<TierStatus, string> = {
  pass: "text-green-700 bg-green-50 border-green-200 dark:text-green-300 dark:bg-green-950/40 dark:border-green-800/50",
  fail: "text-red-700 bg-red-50 border-red-200 dark:text-red-300 dark:bg-red-950/40 dark:border-red-800/50",
  skip: "text-muted-foreground bg-muted/50 border-border",
};

const statusIcons: Record<
  TierStatus,
  React.ComponentType<{ className?: string }>
> = {
  pass: CheckCircle,
  fail: XCircle,
  skip: MinusCircle,
};

const statusLabels: Record<TierStatus, string> = {
  pass: "Pass",
  fail: "Fail",
  skip: "Skip",
};

function describeFailure(key: string, tier: ScriptTestTier): string | null {
  if (tier.status !== "fail") return null;
  switch (key) {
    case "parse": {
      const first = tier.errors?.[0];
      if (first?.line && first.message) {
        return `L${first.line}: ${first.message}`;
      }
      return "Parse errors";
    }
    case "lint":
      return `${tier.issues ?? 0} lint issue${tier.issues === 1 ? "" : "s"}`;
    case "metadata":
      return `Missing: ${(tier.missing ?? []).join(", ")}`;
    case "runbookReady": {
      const first = tier.findings?.[0];
      if (first?.match) {
        return `L${first.line}: ${first.match}`;
      }
      return "Interactive patterns present";
    }
    case "moduleDeps":
      return `Unknown: ${(tier.unknown ?? []).join(", ")}`;
    case "shellcheck":
      return `${tier.issues ?? 0} issue${tier.issues === 1 ? "" : "s"}`;
    default:
      return null;
  }
}

export function QualityChecks({ tests }: QualityChecksProps) {
  const tierConfig = tests.type === "Shell" ? SHELL_TIERS : POWERSHELL_TIERS;
  const lastTested = new Date(tests.lastTested);
  const formattedDate = isNaN(lastTested.getTime())
    ? tests.lastTested
    : lastTested.toLocaleDateString(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
      });

  const overall = tests.overall;
  const overallIcon = statusIcons[overall] ?? statusIcons.skip;
  const OverallIcon = overallIcon;

  return (
    <section
      aria-label="Script quality checks"
      className="bg-muted/30 mb-6 rounded-lg border p-4"
    >
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <ShieldCheck className="text-muted-foreground h-4 w-4" />
          <h3 className="text-sm font-semibold">Quality checks</h3>
          <Badge
            variant="outline"
            className={`gap-1 border text-xs ${statusStyles[overall] ?? statusStyles.skip}`}
          >
            <OverallIcon className="h-3 w-3" />
            {overall === "pass"
              ? "All checks pass"
              : overall === "fail"
                ? "Has failures"
                : "Not tested"}
          </Badge>
        </div>
        <span className="text-muted-foreground text-xs">
          Last run {formattedDate}
        </span>
      </div>

      <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {tierConfig.map(({ key, label, description }) => {
          const tier = tests.tests[key];
          const status: TierStatus = tier?.status ?? "skip";
          const Icon = statusIcons[status];
          const detail = tier ? describeFailure(key, tier) : null;

          return (
            <li
              key={key}
              className="bg-background flex items-start gap-3 rounded-md border p-3"
              title={description}
            >
              <Icon
                className={`mt-0.5 h-4 w-4 flex-shrink-0 ${
                  status === "pass"
                    ? "text-green-600 dark:text-green-400"
                    : status === "fail"
                      ? "text-red-600 dark:text-red-400"
                      : "text-muted-foreground"
                }`}
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="truncate text-sm font-medium">{label}</span>
                  <span
                    className={`text-xs font-medium ${
                      status === "pass"
                        ? "text-green-700 dark:text-green-300"
                        : status === "fail"
                          ? "text-red-700 dark:text-red-300"
                          : "text-muted-foreground"
                    }`}
                  >
                    {statusLabels[status]}
                  </span>
                </div>
                {detail && (
                  <p className="text-muted-foreground mt-0.5 truncate text-xs">
                    {detail}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ul>

      <p className="text-muted-foreground mt-3 text-xs">
        Tests run automatically on every change.{" "}
        <a
          href="https://github.com/ugurkocde/IntuneAutomation/blob/main/TESTING.md"
          target="_blank"
          rel="noopener noreferrer"
          className="underline-offset-2 hover:underline"
        >
          What does each check mean?
        </a>
      </p>
    </section>
  );
}
