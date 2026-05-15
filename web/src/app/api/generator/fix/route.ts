import { type NextRequest } from "next/server";
import { createAnthropic } from "@ai-sdk/anthropic";
import { streamText } from "ai";
import { env } from "~/env";
import { SYSTEM_PROMPT } from "~/server/generator/system-prompt";
import { scrubPrompt } from "~/server/generator/scrub";
import {
  checkPerIp,
  commitReservation,
  hasActiveSession,
  hashIp,
  releaseReservation,
  reserveTokens,
} from "~/server/generator/rate-limit";
import { verifyTurnstile } from "~/server/generator/turnstile";
import {
  errorResponse,
  getClientIp,
  sanitizeForFencedInterpolation,
  streamAbortSignal,
} from "~/server/generator/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_SCRIPT_LENGTH = 30_000;
const MAX_ORIGINAL_PROMPT_LENGTH = 4000;
const MAX_FINDING_DETAIL_LENGTH = 500;
const MAX_FINDINGS = 20;
const MAX_OUTPUT_TOKENS = 6000;
const RESERVED_TOKENS_PER_REQUEST = 8000;
const MODEL_ID = "claude-haiku-4-5";

type FixBody = {
  originalPrompt?: unknown;
  currentScript?: unknown;
  findings?: unknown;
  turnstileToken?: unknown;
};

type ClientFinding = {
  message?: unknown;
  detail?: unknown;
  severity?: unknown;
};

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "bad-request", "Invalid JSON body.");
  }
  const { originalPrompt, currentScript, findings, turnstileToken } = (body ??
    {}) as FixBody;

  if (
    typeof originalPrompt !== "string" ||
    originalPrompt.trim().length === 0
  ) {
    return errorResponse(400, "bad-request", "Original prompt missing.");
  }
  if (originalPrompt.length > MAX_ORIGINAL_PROMPT_LENGTH) {
    return errorResponse(
      400,
      "prompt-too-long",
      "Original prompt exceeds size limit.",
    );
  }
  if (typeof currentScript !== "string" || currentScript.length === 0) {
    return errorResponse(400, "bad-request", "Current script missing.");
  }
  if (currentScript.length > MAX_SCRIPT_LENGTH) {
    return errorResponse(400, "script-too-long", "Script exceeds size limit.");
  }
  if (!Array.isArray(findings) || findings.length === 0) {
    return errorResponse(400, "bad-request", "No findings to fix.");
  }

  const failOrWarnFindings = (findings as ClientFinding[])
    .filter(
      (f): f is ClientFinding & { message: string } =>
        (f.severity === "fail" || f.severity === "warn") &&
        typeof f.message === "string",
    )
    .slice(0, MAX_FINDINGS);

  if (failOrWarnFindings.length === 0) {
    return errorResponse(400, "nothing-to-fix", "No fixable findings.");
  }

  const ip = getClientIp(req);
  if (ip === "unknown" && process.env.NODE_ENV === "production") {
    return errorResponse(
      400,
      "no-client-ip",
      "Could not determine your client IP. Refresh and try again.",
    );
  }

  // Verify bot/abuse gate. Accept EITHER a fresh Turnstile token OR an active
  // continuation session opened by a recent /generate that already passed
  // Turnstile — since Turnstile tokens are single-use server-side, the
  // auto-fix and refine flows ride on the session marker instead of
  // forcing the user to re-solve a challenge.
  const ipHash = hashIp(ip);
  let verified = false;
  if (typeof turnstileToken === "string" && turnstileToken.length > 0) {
    const t = await verifyTurnstile(turnstileToken, ip);
    verified = t.ok;
  }
  if (!verified && (await hasActiveSession(ipHash))) {
    verified = true;
  }
  if (!verified) {
    return errorResponse(
      403,
      "turnstile-failed",
      "Bot verification failed. Refresh the page and try again.",
    );
  }

  const ipCheck = await checkPerIp(ipHash);
  if (!ipCheck.allowed) {
    const resetIn = Math.max(0, Math.ceil((ipCheck.reset - Date.now()) / 1000));
    return errorResponse(
      429,
      "rate-limited",
      "You've reached the daily generation limit. Try again later.",
      { resetInSeconds: resetIn },
      {
        "x-ratelimit-remaining": "0",
        "x-ratelimit-reset": String(ipCheck.reset),
        "retry-after": String(resetIn),
      },
    );
  }
  const rateLimitHeaders = {
    "x-ratelimit-remaining": String(ipCheck.remaining),
    "x-ratelimit-reset": String(ipCheck.reset),
  };

  const reservation = await reserveTokens(RESERVED_TOKENS_PER_REQUEST);
  if (!reservation.allowed) {
    return errorResponse(
      503,
      "daily-cap-reached",
      "The free generator has reached its daily capacity. Please try again tomorrow.",
    );
  }

  if (!env.ANTHROPIC_API_KEY) {
    await releaseReservation(RESERVED_TOKENS_PER_REQUEST);
    return errorResponse(
      503,
      "service-unavailable",
      "Generator is not configured (no API key).",
    );
  }

  // Scrub the original prompt — the user might have typed a secret in the
  // initial generate call. We don't want it leaking to Anthropic on the fix.
  const { cleaned: cleanedOriginalPrompt } = scrubPrompt(originalPrompt.trim());

  // Sanitize the current script: it's client-controlled (whatever the browser
  // POSTs), so it must not be able to break out of the fenced block we wrap
  // it in. Replace bare ``` triples with a lookalike to neutralize injections.
  const safeCurrentScript = sanitizeForFencedInterpolation(
    currentScript,
    MAX_SCRIPT_LENGTH,
  );

  const issuesList = failOrWarnFindings
    .map((f, i) => {
      const rawDetail =
        typeof f.detail === "string" && f.detail.length > 0 ? f.detail : "";
      const safeDetail = sanitizeForFencedInterpolation(
        rawDetail,
        MAX_FINDING_DETAIL_LENGTH,
      )
        .replace(/\n/g, " ")
        .trim();
      const detail = safeDetail.length > 0 ? ` Suggestion: ${safeDetail}` : "";
      const safeMessage = sanitizeForFencedInterpolation(f.message, 300)
        .replace(/\n/g, " ")
        .trim();
      const safeSeverity = f.severity === "fail" ? "fail" : "warn";
      return `${i + 1}. [${safeSeverity}] ${safeMessage}${detail}`;
    })
    .join("\n");

  const today = new Date().toISOString().slice(0, 10);
  const anthropic = createAnthropic({ apiKey: env.ANTHROPIC_API_KEY });

  let reconciled = false;
  const lastUsage = { input: 0, output: 0 };
  const reconcile = async (actual: number) => {
    if (reconciled) return;
    reconciled = true;
    try {
      await commitReservation(RESERVED_TOKENS_PER_REQUEST, actual);
    } catch {
      // Telemetry shouldn't break streaming.
    }
  };

  const fixInstruction = `The original user request was:

${cleanedOriginalPrompt}

You previously produced this script:

\`\`\`powershell
${safeCurrentScript}
\`\`\`

An automated quality check found these issues:

${issuesList}

Produce a corrected version of the script that addresses ONLY these specific issues. Keep all other content and structure identical. Apply all the same hard rules from your system prompt. Output ONLY the corrected script in a single \`\`\`powershell fenced code block. Today's date for .LASTUPDATE is ${today}.`;

  const result = streamText({
    model: anthropic(MODEL_ID),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: 0.1,
    abortSignal: streamAbortSignal(req),
    messages: [
      {
        role: "system",
        content: SYSTEM_PROMPT,
        providerOptions: {
          anthropic: { cacheControl: { type: "ephemeral" } },
        },
      },
      {
        role: "user",
        content: fixInstruction,
      },
    ],
    onChunk: ({ chunk }) => {
      const maybeUsage = (chunk as unknown as { usage?: typeof lastUsage })
        .usage;
      if (maybeUsage) {
        if (typeof maybeUsage.input === "number")
          lastUsage.input = maybeUsage.input;
        if (typeof maybeUsage.output === "number")
          lastUsage.output = maybeUsage.output;
      }
    },
    onFinish: async ({ usage }) => {
      const total = (usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0);
      await reconcile(total);
    },
    onAbort: async () => {
      await reconcile(lastUsage.input + lastUsage.output);
    },
    onError: async () => {
      await reconcile(0);
    },
  });

  const response = result.toTextStreamResponse();
  for (const [k, v] of Object.entries(rateLimitHeaders)) {
    response.headers.set(k, v);
  }
  return response;
}
