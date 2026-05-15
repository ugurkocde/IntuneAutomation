// Lightweight quality + safety linter for AI-generated PowerShell scripts.
// Pure function — runs client-side after streaming completes. No server roundtrip.

import { GRAPH_SCOPES } from "./generator-graph-data";
import { checkGraphEndpoints } from "./generator-graph-endpoints";
//
// Categories of checks:
//   - Metadata completeness (the .TITLE/.SYNOPSIS/... block)
//   - Microsoft Graph permission validity (whitelist of real scopes)
//   - Security patterns (Invoke-Expression, hardcoded credentials, etc.)
//   - Cmdlet pitfalls observed in real Claude outputs (Secure Boot, etc.)
//   - Safety on destructive Graph operations (SupportsShouldProcess)
//   - Null-safe Graph date parsing

export type LintSeverity = "pass" | "warn" | "fail";

export type LintFinding = {
  id: string;
  severity: LintSeverity;
  category: "metadata" | "permissions" | "security" | "correctness" | "safety";
  message: string;
  detail?: string;
};

export type LintResult = {
  findings: LintFinding[];
  passCount: number;
  warnCount: number;
  failCount: number;
  // If true, the output didn't look like a valid PowerShell script at all.
  // The UI should suppress the code panel and show a rejection message.
  hardReject: { reason: string } | null;
};

// Structural pre-check. Returns a hard-reject reason if the text doesn't look
// like a PS script at all — e.g. Claude bailed and produced prose, a novel,
// or refused mid-response. The lint panel can't fix these, only reject.
function detectHardReject(code: string): { reason: string } | null {
  const trimmed = code.trim();
  if (trimmed.length < 80) {
    return { reason: "Output is too short to be a valid script." };
  }
  if (!trimmed.startsWith("<#")) {
    return {
      reason:
        "Output does not start with the required PowerShell comment-based help block (<# ... #>).",
    };
  }
  // Must contain a comment-block close + the .TITLE field. If neither, almost
  // certainly not a real script.
  if (!trimmed.includes("#>") || !trimmed.includes(".TITLE")) {
    return {
      reason:
        "Output is missing the required metadata block (.TITLE and #> close).",
    };
  }
  return null;
}

// Microsoft Graph permission scopes — sourced from the merill/msgraph
// reference (https://graph.pm). The full set of ~700 scopes across every
// published Graph endpoint, refreshed weekly via the sync-msgraph-data
// script. See web/src/lib/generator-graph-data.ts.
const KNOWN_GRAPH_SCOPES = GRAPH_SCOPES;

// Common cmdlet confusions Claude has produced. Each entry: regex pattern
// matched in the script body, message, and suggested replacement.
const CMDLET_PITFALLS: Array<{
  id: string;
  pattern: RegExp;
  message: string;
  suggestion: string;
}> = [
  {
    id: "secure-boot-cmdlet",
    pattern: /\bGet-SecureBootUEFI\b/,
    message:
      "`Get-SecureBootUEFI` returns UEFI firmware variables, not a boolean.",
    suggestion: "Use `Confirm-SecureBootUEFI` for a true/false enabled check.",
  },
  {
    id: "mp-status-realtime",
    pattern: /\bGet-MpComputerStatus\b[\s\S]{0,80}RealTimeProtectionEnabled/,
    message:
      "`Get-MpComputerStatus.RealTimeProtectionEnabled` is slower and may lag policy.",
    suggestion:
      "For policy state, use `(Get-MpPreference).DisableRealtimeMonitoring`.",
  },
  {
    id: "tpm-encryption",
    pattern: /\bGet-Tpm\b[\s\S]{0,100}(?:ProtectionStatus|Encrypted)/i,
    message: "`Get-Tpm` reports TPM state, not BitLocker encryption status.",
    suggestion:
      "Use `Get-BitLockerVolume -MountPoint 'C:'` and inspect `.ProtectionStatus`.",
  },
];

const TODAY = () => new Date().toISOString().slice(0, 10);

export function lintScript(code: string): LintResult {
  const findings: LintFinding[] = [];

  // Structural hard-reject: if output is clearly not a PS script, bail early
  // so the UI can show a rejection notice instead of the bogus content.
  const hardReject = detectHardReject(code);
  if (hardReject) {
    return {
      findings: [
        {
          id: "hard-reject",
          severity: "fail",
          category: "metadata",
          message: hardReject.reason,
        },
      ],
      passCount: 0,
      warnCount: 0,
      failCount: 1,
      hardReject,
    };
  }

  // ------------------------------------------------------------------
  // 1. Metadata completeness
  // ------------------------------------------------------------------
  const requiredFields = [
    ".TITLE",
    ".SYNOPSIS",
    ".DESCRIPTION",
    ".TAGS",
    ".PLATFORM",
    ".PERMISSIONS",
    ".AUTHOR",
    ".VERSION",
    ".CHANGELOG",
    ".LASTUPDATE",
    ".EXAMPLE",
    ".NOTES",
  ];
  const missingFields = requiredFields.filter((f) => !code.includes(f));
  if (missingFields.length === 0) {
    findings.push({
      id: "metadata-complete",
      severity: "pass",
      category: "metadata",
      message: `All ${requiredFields.length} required metadata fields present.`,
    });
  } else {
    findings.push({
      id: "metadata-missing",
      severity: "fail",
      category: "metadata",
      message: `Missing metadata fields: ${missingFields.join(", ")}.`,
    });
  }

  // ------------------------------------------------------------------
  // 2. Author marker (don't impersonate)
  // ------------------------------------------------------------------
  if (/\.AUTHOR\s*\n\s*AI Generated \(IntuneAutomation\.com\)/.test(code)) {
    findings.push({
      id: "author-correct",
      severity: "pass",
      category: "metadata",
      message: "Author tagged as AI-generated.",
    });
  } else {
    findings.push({
      id: "author-wrong",
      severity: "warn",
      category: "metadata",
      message:
        "`.AUTHOR` is not the expected `AI Generated (IntuneAutomation.com)` marker.",
    });
  }

  // ------------------------------------------------------------------
  // 3. LASTUPDATE date is today
  // ------------------------------------------------------------------
  const dateMatch = code.match(/\.LASTUPDATE\s*\n\s*(\d{4}-\d{2}-\d{2})/);
  if (dateMatch && dateMatch[1] === TODAY()) {
    findings.push({
      id: "date-current",
      severity: "pass",
      category: "metadata",
      message: "`.LASTUPDATE` is today.",
    });
  } else if (dateMatch) {
    findings.push({
      id: "date-stale",
      severity: "warn",
      category: "metadata",
      message: `\`.LASTUPDATE\` is ${dateMatch[1]} (expected ${TODAY()}).`,
    });
  }

  // ------------------------------------------------------------------
  // 4. Graph permissions validity
  // ------------------------------------------------------------------
  const permsMatch = code.match(/\.PERMISSIONS\s*\n\s*([^\n]+)/);
  if (permsMatch?.[1]) {
    const permLine = permsMatch[1].trim();
    const isNone = /^none\b/i.test(permLine);

    if (isNone) {
      findings.push({
        id: "permissions-none",
        severity: "pass",
        category: "permissions",
        message: "No Graph permissions required (SYSTEM-context script).",
      });
    } else {
      const scopes = permLine
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      const invalid = scopes.filter((s) => !KNOWN_GRAPH_SCOPES.has(s));
      if (invalid.length === 0) {
        findings.push({
          id: "permissions-valid",
          severity: "pass",
          category: "permissions",
          message: `All ${scopes.length} Microsoft Graph permission scope${scopes.length === 1 ? "" : "s"} verified against the official list.`,
        });
      } else {
        findings.push({
          id: "permissions-unknown",
          severity: "warn",
          category: "permissions",
          message: `Unrecognized Graph scope${invalid.length === 1 ? "" : "s"}: ${invalid.join(", ")}.`,
          detail:
            "Verify the spelling on the Microsoft Graph permissions reference. May be valid but uncommon, or hallucinated.",
        });
      }
    }
  }

  // ------------------------------------------------------------------
  // 5. Dangerous code patterns
  // ------------------------------------------------------------------
  const dangerousPatterns: Array<{ id: string; re: RegExp; msg: string }> = [
    {
      id: "invoke-expression",
      re: /\bInvoke-Expression\b|\biex\b/i,
      msg: "Uses `Invoke-Expression` (`iex`) — risky if any input is user-controlled. Review carefully.",
    },
    {
      id: "hardcoded-password",
      re: /(?:password|secret|pwd|apikey|api_key)\s*=\s*["'][^"'$][^"']{4,}["']/i,
      msg: "Possible hardcoded credential found.",
    },
    {
      id: "execution-policy-bypass",
      re: /-ExecutionPolicy\s+Bypass/i,
      msg: "Sets `-ExecutionPolicy Bypass`. Acceptable for Intune deployment scripts but flag for review.",
    },
  ];
  let dangerousFound = false;
  for (const p of dangerousPatterns) {
    if (p.re.test(code)) {
      dangerousFound = true;
      findings.push({
        id: p.id,
        severity: p.id === "execution-policy-bypass" ? "warn" : "fail",
        category: "security",
        message: p.msg,
      });
    }
  }
  if (!dangerousFound) {
    findings.push({
      id: "no-dangerous-patterns",
      severity: "pass",
      category: "security",
      message:
        "No high-risk patterns detected (no Invoke-Expression, no hardcoded credentials).",
    });
  }

  // ------------------------------------------------------------------
  // 6. Hardcoded webhook / non-Graph external URLs
  // ------------------------------------------------------------------
  // Strip comment-based help block and inline comments before scanning URLs,
  // so we don't flag URLs inside .EXAMPLE or .NOTES.
  const codeWithoutHelpBlock = code.replace(/<#[\s\S]*?#>/g, "");
  const codeWithoutComments = codeWithoutHelpBlock.replace(
    /(^|\s)#[^\n]*/g,
    "",
  );
  const urlMatches = Array.from(
    codeWithoutComments.matchAll(/https?:\/\/[^\s"'`)]+/g),
  );
  const externalUrls = urlMatches
    .map((m) => m[0])
    .filter((u) => {
      const host = u.replace(/^https?:\/\//, "").split(/[\/?#]/)[0] ?? "";
      // Allow Microsoft Graph and well-known Microsoft endpoints
      if (
        host.endsWith("graph.microsoft.com") ||
        host.endsWith("microsoftonline.com") ||
        host.endsWith("microsoft.com")
      ) {
        return false;
      }
      return true;
    })
    .filter((u) => !u.includes("$")); // Variable-substituted URLs are parametric

  if (externalUrls.length > 0) {
    findings.push({
      id: "hardcoded-external-url",
      severity: "fail",
      category: "security",
      message: `Hardcoded external URL${externalUrls.length === 1 ? "" : "s"} in script body: ${externalUrls.slice(0, 2).join(", ")}${externalUrls.length > 2 ? "…" : ""}`,
      detail:
        "Webhook URLs and external endpoints should be parameters, not hardcoded.",
    });
  }

  // ------------------------------------------------------------------
  // 7. Cmdlet pitfalls (known Claude confusions)
  // ------------------------------------------------------------------
  for (const pitfall of CMDLET_PITFALLS) {
    if (pitfall.pattern.test(code)) {
      findings.push({
        id: pitfall.id,
        severity: "fail",
        category: "correctness",
        message: pitfall.message,
        detail: pitfall.suggestion,
      });
    }
  }

  // ------------------------------------------------------------------
  // 8. Destructive Graph operations require SupportsShouldProcess
  // ------------------------------------------------------------------
  const destructiveEndpoints =
    /\/(retire|wipe|delete|reset|setDeviceName|disable)\b/i;
  const hasDestructiveCall =
    destructiveEndpoints.test(codeWithoutHelpBlock) ||
    /\bMethod\s+(?:DELETE|POST)\b[\s\S]{0,200}\/(retire|wipe|delete)\b/i.test(
      codeWithoutHelpBlock,
    );
  const hasShouldProcess =
    /\[CmdletBinding\([^)]*SupportsShouldProcess\s*=\s*\$true/i.test(code);
  if (hasDestructiveCall && !hasShouldProcess) {
    findings.push({
      id: "destructive-no-shouldprocess",
      severity: "fail",
      category: "safety",
      message:
        "Script performs destructive operations (retire/wipe/delete) but lacks `SupportsShouldProcess`.",
      detail:
        "Add `[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]` and gate destructive calls behind `$PSCmdlet.ShouldProcess(...)`.",
    });
  } else if (hasDestructiveCall && hasShouldProcess) {
    findings.push({
      id: "destructive-with-shouldprocess",
      severity: "pass",
      category: "safety",
      message:
        "Destructive operations are gated by `SupportsShouldProcess` and `-WhatIf`.",
    });
  }

  // ------------------------------------------------------------------
  // 9. Null-safe date parsing
  // ------------------------------------------------------------------
  // Flag direct [DateTime]::Parse($x.someDateField) without a preceding guard.
  // Recognized guards (any of these means the call is safe):
  //   - same line includes `if (`, `?` ternary, `-and`, or `$null -ne`
  //   - the ~300 chars before the call contain an `if (...)` or `while (...)`
  //     condition that references the SAME property name (multi-line block)
  //   - the ~300 chars before contain a `try {` (try/catch wrap)
  // We don't have a real PS parser; the heuristic favors not flagging false
  // positives over catching every edge case, because the warning triggers
  // auto-fix and an over-eager rule causes auto-fix to loop without progress.
  const dateParseMatches = Array.from(
    codeWithoutHelpBlock.matchAll(
      /\[DateTime\]::Parse\(\s*\$(?:_|\w+)\.(\w*[Dd]ate[Tt]ime\w*|\w*[Tt]ime)\s*\)/g,
    ),
  );
  const escapeForRegex = (s: string) =>
    s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const unsafeDateParses = dateParseMatches.filter((m) => {
    const idx = m.index ?? 0;
    const fieldName = m[1] ?? "";
    const lineStart = codeWithoutHelpBlock.lastIndexOf("\n", idx) + 1;
    const lineEnd = codeWithoutHelpBlock.indexOf("\n", idx);
    const line = codeWithoutHelpBlock.slice(
      lineStart,
      lineEnd === -1 ? undefined : lineEnd,
    );
    if (/\bif\s*\(|\?\s*\{|-and|\$null\s+-ne/.test(line)) return false;

    // Walk back ~300 chars (typically 5-8 lines of PS).
    const before = codeWithoutHelpBlock.slice(Math.max(0, idx - 300), idx);
    // Multi-line if/while guard that references the SAME property.
    const fieldGuard = new RegExp(
      `\\b(if|while)\\s*\\([^)]*\\b${escapeForRegex(fieldName)}\\b`,
      "i",
    );
    if (fieldGuard.test(before)) return false;
    // Try-wrap (any enclosing try block in nearby scope).
    if (/\btry\s*\{/.test(before)) return false;

    return true;
  });
  if (unsafeDateParses.length > 0) {
    findings.push({
      id: "unsafe-date-parse",
      severity: "warn",
      category: "correctness",
      message: `${unsafeDateParses.length} unguarded \`[DateTime]::Parse(...)\` call${unsafeDateParses.length === 1 ? "" : "s"} on a date field.`,
      detail:
        "Rewrite as `$var = if ($x.field) { [DateTime]::Parse($x.field) } else { $null }`, or wrap in try/catch. Parse THROWS on null/empty input — a later `if ($null -eq $var)` check is dead code and does not prevent the throw. Microsoft Graph returns null for date fields on newly enrolled or errored devices.",
    });
  }

  // ------------------------------------------------------------------
  // 10. Connect-MgGraph called with both -Scopes and -Identity (mutually
  //     exclusive in Azure Automation environments) — quick sanity check
  // ------------------------------------------------------------------
  const hasIdentityAuth = /Connect-MgGraph\s+-Identity/.test(code);
  const hasIfAzureAutomation = /\$IsAzureAutomation/.test(code);
  if (hasIdentityAuth && !hasIfAzureAutomation) {
    findings.push({
      id: "managed-identity-no-fallback",
      severity: "warn",
      category: "correctness",
      message:
        "`Connect-MgGraph -Identity` is used but there is no Azure Automation detection branch.",
      detail:
        "Interactive runs will fail. Detect with `$null -ne $PSPrivateMetadata.JobId.Guid` and branch.",
    });
  }

  // ------------------------------------------------------------------
  // 11. Graph endpoint verification — every literal Graph URI in the
  //     script body is checked against the published Graph API catalog
  //     (compiled from merill/msgraph). Unknown endpoints are flagged
  //     with up to 3 fuzzy-match candidate replacements so the auto-fix
  //     pass has concrete suggestions instead of just "this is wrong".
  // ------------------------------------------------------------------
  const endpointChecks = checkGraphEndpoints(codeWithoutHelpBlock);
  const unknownEndpoints = endpointChecks.filter((c) => !c.matched);
  const v1Endpoints = endpointChecks.filter(
    (c) => c.matched && c.wrongVersion,
  );
  if (
    endpointChecks.length > 0 &&
    unknownEndpoints.length === 0 &&
    v1Endpoints.length === 0
  ) {
    findings.push({
      id: "graph-endpoints-valid",
      severity: "pass",
      category: "correctness",
      message: `All ${endpointChecks.length} Microsoft Graph endpoint URI${endpointChecks.length === 1 ? "" : "s"} verified against the official catalog.`,
    });
  }
  for (const u of unknownEndpoints) {
    const suggestionText =
      u.suggestions.length > 0
        ? ` Closest known endpoints: ${u.suggestions.join("; ")}.`
        : "";
    findings.push({
      id: `graph-endpoint-unknown-${u.method.toLowerCase()}`,
      severity: "fail",
      category: "correctness",
      message: `Graph endpoint not found in the official catalog: ${u.method} ${u.path}.`,
      detail: `Replace with a real endpoint or remove this call.${suggestionText}`,
    });
  }
  if (v1Endpoints.length > 0) {
    findings.push({
      id: "graph-endpoint-v1",
      severity: "warn",
      category: "correctness",
      message: `${v1Endpoints.length} Graph endpoint${v1Endpoints.length === 1 ? " uses" : "s use"} /v1.0 — switch to /beta.`,
      detail:
        "IntuneAutomation generator always uses /beta for the full Intune device-management API surface. Rewrite each /v1.0 URI to /beta with the same path.",
    });
  }

  const passCount = findings.filter((f) => f.severity === "pass").length;
  const warnCount = findings.filter((f) => f.severity === "warn").length;
  const failCount = findings.filter((f) => f.severity === "fail").length;

  return { findings, passCount, warnCount, failCount, hardReject: null };
}
