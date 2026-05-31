// Cheap pre-flight check: does this prompt LOOK like an Intune / Microsoft 365 /
// Windows admin scripting request? Reject obvious off-topic prompts before
// spending Anthropic tokens.
//
// Bias: lenient. False positives (real requests rejected) hurt much more than
// false negatives (off-topic gets through). Only ~30 well-chosen domain tokens
// are enough to catch 95% of casual misuse (recipes, essays, code in other
// languages, generic chatbot abuse).

const DOMAIN_KEYWORDS = [
  // Intune + Microsoft platform
  "intune",
  "autopilot",
  "defender",
  "bitlocker",
  "conditional access",
  "azure ad",
  "entra",
  "microsoft 365",
  "microsoft graph",
  "m365",
  "msgraph",
  "office 365",
  "o365",
  "msi",
  "winget",
  "endpoint manager",
  "mdm",
  "mam",
  // Language / artifact
  "powershell",
  "ps1",
  "cmdlet",
  "runbook",
  "script",
  "module",
  // Concepts
  "device",
  "endpoint",
  "managed",
  "compliance",
  "policy",
  "configuration",
  "profile",
  "tenant",
  "enrollment",
  "deployment",
  "remediation",
  "detection",
  "audit",
  "role",
  "permission",
  "scope",
  "license",
  "subscription",
  "notification",
  "alert",
  "webhook",
  // Platforms
  "windows",
  "macos",
  "ios",
  "android",
  // Common targets
  "user",
  "group",
  "app",
  "application",
  "update",
  "patch",
  "certificate",
  "registry",
  "service",
  "process",
  "wifi",
  "vpn",
  "smtp",
  "teams",
  "outlook",
  "exchange",
  "sharepoint",
  "onedrive",
  "intunewin",
  // Verbs we expect
  "report",
  "export",
  "list",
  "audit",
  "monitor",
  "rotate",
  "retire",
  "wipe",
  "deploy",
  "install",
  "uninstall",
  "schedule",
  "automate",
];

// Strong terms are specific enough to accept without the LLM classifier.
// Generic words like "script", "user", or "app" are weak hints only; they
// should not let unrelated or abusive prompts bypass classification.
const STRONG_DOMAIN_KEYWORDS = [
  "intune",
  "autopilot",
  "defender",
  "bitlocker",
  "conditional access",
  "azure ad",
  "entra",
  "microsoft 365",
  "microsoft graph",
  "m365",
  "msgraph",
  "office 365",
  "o365",
  "endpoint manager",
  "mdm",
  "mam",
  "powershell",
  "ps1",
  "cmdlet",
  "runbook",
  "compliance",
  "policy",
  "configuration",
  "profile",
  "tenant",
  "enrollment",
  "remediation",
  "detection",
  "audit",
  "permission",
  "scope",
  "intunewin",
];

const WEAK_DOMAIN_KEYWORDS = DOMAIN_KEYWORDS.filter(
  (k) => !STRONG_DOMAIN_KEYWORDS.includes(k),
);

const STRONG_KEYWORD_SET = new Set(
  STRONG_DOMAIN_KEYWORDS.map((k) => k.toLowerCase()),
);
const WEAK_KEYWORD_SET = new Set(
  WEAK_DOMAIN_KEYWORDS.map((k) => k.toLowerCase()),
);

// Multi-word keywords must be checked as substrings (e.g. "azure ad").
const STRONG_MULTI_WORD = STRONG_DOMAIN_KEYWORDS.filter((k) => k.includes(" "));
const WEAK_MULTI_WORD = WEAK_DOMAIN_KEYWORDS.filter((k) => k.includes(" "));

export type TopicCheckResult =
  | { onTopic: true; matches: number }
  | { onTopic: false; reason: "no-domain-keywords" };

export function checkOnTopic(prompt: string): TopicCheckResult {
  const lower = prompt.toLowerCase();
  let matches = 0;
  let strongMatches = 0;

  // Tokenize on word boundaries for single-word matches.
  const tokens = lower.match(/[a-z0-9-]{2,}/g) ?? [];
  for (const t of tokens) {
    if (STRONG_KEYWORD_SET.has(t)) {
      matches++;
      strongMatches++;
    } else if (WEAK_KEYWORD_SET.has(t)) {
      matches++;
    }
  }

  // Substring match for multi-word terms.
  for (const phrase of STRONG_MULTI_WORD) {
    if (lower.includes(phrase)) {
      matches++;
      strongMatches++;
    }
  }
  for (const phrase of WEAK_MULTI_WORD) {
    if (lower.includes(phrase)) matches++;
  }

  if (strongMatches === 0) {
    return { onTopic: false, reason: "no-domain-keywords" };
  }
  return { onTopic: true, matches };
}
