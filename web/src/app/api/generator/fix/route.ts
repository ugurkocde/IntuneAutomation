import { NextResponse, type NextRequest } from "next/server";
import { createAnthropic } from "@ai-sdk/anthropic";
import { streamText } from "ai";
import { env } from "~/env";
import { SYSTEM_PROMPT } from "~/server/generator/system-prompt";
import {
  checkPerIp,
  commitReservation,
  hashIp,
  releaseReservation,
  reserveTokens,
} from "~/server/generator/rate-limit";
import { verifyTurnstile } from "~/server/generator/turnstile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_SCRIPT_LENGTH = 30_000;
const MAX_FINDINGS = 20;
const MAX_OUTPUT_TOKENS = 6000;
const RESERVED_TOKENS_PER_REQUEST = 8000;
const MODEL_ID = "claude-haiku-4-5";

function getClientIp(req: NextRequest): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]?.trim() ?? "unknown";
  return req.headers.get("x-real-ip") ?? "unknown";
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  extra?: Record<string, unknown>,
) {
  return NextResponse.json({ error: code, message, ...extra }, { status });
}

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

  // Turnstile + rate limit + cap — same gates as primary generation. A fix
  // costs the same as a new generation, so it counts against the daily quota.
  const turnstile = await verifyTurnstile(
    typeof turnstileToken === "string" ? turnstileToken : null,
    ip,
  );
  if (!turnstile.ok) {
    return errorResponse(
      403,
      "turnstile-failed",
      "Bot verification failed. Refresh the page and try again.",
    );
  }

  const ipHash = hashIp(ip);
  const ipCheck = await checkPerIp(ipHash);
  if (!ipCheck.allowed) {
    const resetIn = Math.max(0, Math.ceil((ipCheck.reset - Date.now()) / 1000));
    const res = errorResponse(
      429,
      "rate-limited",
      "You've reached the daily generation limit. Try again later.",
      { resetInSeconds: resetIn },
    );
    res.headers.set("X-RateLimit-Remaining", "0");
    res.headers.set("X-RateLimit-Reset", String(ipCheck.reset));
    return res;
  }
  const rateLimitHeaders = {
    "X-RateLimit-Remaining": String(ipCheck.remaining),
    "X-RateLimit-Reset": String(ipCheck.reset),
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

  const issuesList = failOrWarnFindings
    .map((f, i) => {
      const detail =
        typeof f.detail === "string" && f.detail.length > 0
          ? ` Suggestion: ${f.detail}`
          : "";
      return `${i + 1}. [${f.severity}] ${f.message}${detail}`;
    })
    .join("\n");

  const today = new Date().toISOString().slice(0, 10);
  const anthropic = createAnthropic({ apiKey: env.ANTHROPIC_API_KEY });

  let reconciled = false;
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

${originalPrompt}

You previously produced this script:

\`\`\`powershell
${currentScript}
\`\`\`

An automated quality check found these issues:

${issuesList}

Produce a corrected version of the script that addresses ONLY these specific issues. Keep all other content and structure identical. Apply all the same hard rules from your system prompt. Output ONLY the corrected script in a single \`\`\`powershell fenced code block. Today's date for .LASTUPDATE is ${today}.`;

  const result = streamText({
    model: anthropic(MODEL_ID),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: 0.1,
    abortSignal: req.signal,
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
    onFinish: async ({ usage }) => {
      const total = (usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0);
      await reconcile(total);
    },
    onAbort: async () => {
      await reconcile(0);
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
