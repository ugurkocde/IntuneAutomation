// Secret scrubber for user prompts before they hit Anthropic.
// Conservative on false positives (we surface what was redacted, so users notice).
// Aggressive on patterns we're sure indicate secrets (keys, tokens, GUIDs).

export type RedactionKind =
  | "tenant-or-app-id"
  | "jwt"
  | "bearer-token"
  | "api-key"
  | "long-base64"
  | "email"
  | "ip-address";

export type Redaction = {
  kind: RedactionKind;
  label: string;
  count: number;
};

export type ScrubResult = {
  cleaned: string;
  redactions: Redaction[];
};

// Each rule applies in order. Earlier rules win when patterns overlap.
const RULES: Array<{
  kind: RedactionKind;
  label: string;
  pattern: RegExp;
  replacement: string;
}> = [
  // JWT-shaped tokens (three base64url segments)
  {
    kind: "jwt",
    label: "JWT token",
    pattern:
      /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g,
    replacement: "[REDACTED_JWT]",
  },
  // Bearer authorization header
  {
    kind: "bearer-token",
    label: "Bearer token",
    pattern: /\bBearer\s+[A-Za-z0-9._\-+/=]{20,}\b/gi,
    replacement: "Bearer [REDACTED_TOKEN]",
  },
  // Common API key prefixes — match prefix + any non-whitespace continuation
  {
    kind: "api-key",
    label: "API key",
    pattern:
      /\b(sk-(?:proj-|ant-|svcacct-)?[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|ghr_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abps]-[A-Za-z0-9-]{10,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|AAAA[A-Za-z0-9_-]{30,})\b/g,
    replacement: "[REDACTED_API_KEY]",
  },
  // GUIDs (tenant IDs, app IDs, object IDs)
  {
    kind: "tenant-or-app-id",
    label: "GUID (tenant/app/object ID)",
    pattern:
      /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g,
    replacement: "[REDACTED_GUID]",
  },
  // Long base64 / hex blobs (likely secrets, certificates, hashes).
  // \b doesn't anchor against +/= (non-word chars) — use explicit lookarounds
  // so a secret like "AAAB+very/long/secret==" is still matched.
  {
    kind: "long-base64",
    label: "Long encoded value",
    pattern: /(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{60,}={0,2}(?![A-Za-z0-9+/=])/g,
    replacement: "[REDACTED_BLOB]",
  },
  // Email addresses
  {
    kind: "email",
    label: "Email address",
    pattern:
      /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g,
    replacement: "[REDACTED_EMAIL]",
  },
  // Public IPv4 addresses (skip rfc1918/loopback)
  {
    kind: "ip-address",
    label: "IP address",
    pattern: /\b(?!10\.|192\.168\.|127\.|0\.)(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/g,
    replacement: "[REDACTED_IP]",
  },
];

export function scrubPrompt(input: string): ScrubResult {
  let cleaned = input;
  const tally = new Map<RedactionKind, { label: string; count: number }>();

  for (const rule of RULES) {
    let hits = 0;
    cleaned = cleaned.replace(rule.pattern, () => {
      hits++;
      return rule.replacement;
    });
    if (hits > 0) {
      tally.set(rule.kind, { label: rule.label, count: hits });
    }
  }

  const redactions: Redaction[] = Array.from(tally.entries()).map(
    ([kind, { label, count }]) => ({ kind, label, count }),
  );

  return { cleaned, redactions };
}
