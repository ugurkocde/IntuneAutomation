import { NextResponse, type NextRequest } from "next/server";
import { createAnthropic } from "@ai-sdk/anthropic";
import { streamText } from "ai";
import { env } from "~/env";
import { SYSTEM_PROMPT } from "~/server/generator/system-prompt";
import { scrubPrompt, type Redaction } from "~/server/generator/scrub";
import {
  checkPerIp,
  commitReservation,
  hashIp,
  releaseReservation,
  reserveTokens,
} from "~/server/generator/rate-limit";
import { verifyTurnstile } from "~/server/generator/turnstile";
import { checkOnTopic } from "~/server/generator/topic-filter";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_PROMPT_LENGTH = 4000;
const MAX_OUTPUT_TOKENS = 6000;
// Pessimistic reservation: assume worst-case input + output tokens for the
// daily-cap accounting. Reconciled with actuals when the stream finishes.
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

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "bad-request", "Invalid JSON body.");
  }

  const { prompt, turnstileToken, acceptedTerms } = (body ?? {}) as {
    prompt?: unknown;
    turnstileToken?: unknown;
    acceptedTerms?: unknown;
  };

  if (acceptedTerms !== true) {
    return errorResponse(
      400,
      "terms-not-accepted",
      "You must accept the Terms of Use to use the generator.",
    );
  }

  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    return errorResponse(400, "empty-prompt", "Prompt cannot be empty.");
  }
  if (prompt.length > MAX_PROMPT_LENGTH) {
    return errorResponse(
      400,
      "prompt-too-long",
      `Prompt must be ${MAX_PROMPT_LENGTH} characters or fewer.`,
    );
  }

  const ip = getClientIp(req);
  if (ip === "unknown" && process.env.NODE_ENV === "production") {
    // Without a real IP we cannot rate-limit safely (would collapse all
    // unidentified callers into one bucket). Reject in production.
    return errorResponse(
      400,
      "no-client-ip",
      "Could not determine your client IP. Refresh and try again.",
    );
  }

  // 1. Turnstile
  const turnstile = await verifyTurnstile(
    typeof turnstileToken === "string" ? turnstileToken : null,
    ip,
  );
  if (!turnstile.ok) {
    return errorResponse(
      403,
      "turnstile-failed",
      "Bot verification failed. Refresh the page and try again.",
      { detail: turnstile.reason },
    );
  }

  // 2. Cheap pre-flight topic filter. Done BEFORE rate-limit + reservation so
  // an off-topic prompt doesn't consume the user's daily quota. The Turnstile
  // gate above prevents bots from hammering this cheap path indefinitely.
  const { cleaned, redactions } = scrubPrompt(prompt.trim());
  const topic = checkOnTopic(cleaned);
  if (!topic.onTopic) {
    return errorResponse(
      400,
      "off-topic",
      "This generator only writes PowerShell scripts for Microsoft Intune, Microsoft Graph, and Windows/macOS device management. Please rephrase your request to describe a script for those domains.",
    );
  }

  // 3. Per-IP rate limit
  const ipHash = hashIp(ip);
  const ipCheck = await checkPerIp(ipHash);
  if (!ipCheck.allowed) {
    const resetIn = Math.max(0, Math.ceil((ipCheck.reset - Date.now()) / 1000));
    return errorResponse(
      429,
      "rate-limited",
      "You've reached the daily generation limit. Try again later.",
      { resetInSeconds: resetIn },
    );
  }

  // 4. Reserve daily-cap budget pessimistically (closes the TOCTOU window).
  const reservation = await reserveTokens(RESERVED_TOKENS_PER_REQUEST);
  if (!reservation.allowed) {
    return errorResponse(
      503,
      "daily-cap-reached",
      "The free generator has reached its daily capacity. Please try again tomorrow.",
    );
  }

  // 5. If no Anthropic key configured, return a mock so dev/preview works without billing.
  if (!env.ANTHROPIC_API_KEY) {
    // Refund the reservation since we're not actually calling Anthropic.
    await releaseReservation(RESERVED_TOKENS_PER_REQUEST);
    return mockStreamResponse(cleaned, redactions);
  }

  // 6. Stream from Anthropic with prompt caching on the system prompt.
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

  const result = streamText({
    model: anthropic(MODEL_ID),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: 0.2,
    // Propagate client disconnects to Anthropic so cancels stop billing.
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
        content: `Today's date (use in .LASTUPDATE): ${today}\n\nUser request:\n${cleaned}`,
      },
    ],
    onFinish: async ({ usage }) => {
      const total =
        (usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0);
      await reconcile(total);
    },
    onAbort: async () => {
      // Client disconnected. Refund what we haven't used. Anthropic billing
      // for aborted streams is best-effort partial — we treat actual=0 here,
      // which slightly over-refunds in the worst case but never under-refunds.
      await reconcile(0);
    },
    onError: async () => {
      await reconcile(0);
    },
  });

  const response = result.toTextStreamResponse();
  response.headers.set(
    "x-generator-redactions",
    encodeRedactions(redactions),
  );
  return response;
}

function encodeRedactions(redactions: Redaction[]): string {
  return Buffer.from(JSON.stringify(redactions), "utf-8").toString("base64");
}

function mockStreamResponse(prompt: string, redactions: Redaction[]) {
  const today = new Date().toISOString().slice(0, 10);
  const mock = `\`\`\`powershell
<#
.TITLE
    Mock Generator Output (Anthropic key not configured)

.SYNOPSIS
    Returned when ANTHROPIC_API_KEY is not set so the UI can be tested locally.

.DESCRIPTION
    This is a placeholder response. Configure ANTHROPIC_API_KEY to get real
    AI-generated scripts. Your prompt was: "${prompt.slice(0, 120)}..."

.TAGS
    Operational

.PLATFORM
    Windows

.MINROLE
    Global Reader

.PERMISSIONS
    User.Read

.AUTHOR
    AI Generated (IntuneAutomation.com)

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    ${today}

.EXAMPLE
    .\\mock.ps1
    Prints a notice.

.NOTES
    - This is a mock. Set ANTHROPIC_API_KEY to enable real generation.
#>

[CmdletBinding()]
param()

Write-Warning "Mock response — set ANTHROPIC_API_KEY to enable the script generator."
\`\`\`
`;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const enc = new TextEncoder();
      for (const chunk of mock.match(/.{1,40}/gs) ?? [mock]) {
        controller.enqueue(enc.encode(chunk));
        await new Promise((r) => setTimeout(r, 30));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "x-generator-redactions": encodeRedactions(redactions),
      "x-generator-mock": "1",
    },
  });
}
