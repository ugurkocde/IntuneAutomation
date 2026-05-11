import { NextResponse, type NextRequest } from "next/server";
import { createAnthropic } from "@ai-sdk/anthropic";
import { streamText } from "ai";
import { env } from "~/env";
import { SYSTEM_PROMPT } from "~/server/generator/system-prompt";
import { scrubPrompt } from "~/server/generator/scrub";
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

const MAX_REFINEMENT_LENGTH = 1500;
const MAX_SCRIPT_LENGTH = 30_000;
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

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "bad-request", "Invalid JSON body.");
  }

  const { originalPrompt, currentScript, refinement, turnstileToken } =
    (body ?? {}) as {
      originalPrompt?: unknown;
      currentScript?: unknown;
      refinement?: unknown;
      turnstileToken?: unknown;
    };

  if (typeof originalPrompt !== "string" || originalPrompt.length === 0) {
    return errorResponse(400, "bad-request", "Original prompt missing.");
  }
  if (typeof currentScript !== "string" || currentScript.length === 0) {
    return errorResponse(400, "bad-request", "Current script missing.");
  }
  if (currentScript.length > MAX_SCRIPT_LENGTH) {
    return errorResponse(400, "script-too-long", "Script exceeds size limit.");
  }
  if (typeof refinement !== "string" || refinement.trim().length === 0) {
    return errorResponse(
      400,
      "empty-refinement",
      "Refinement instruction cannot be empty.",
    );
  }
  if (refinement.length > MAX_REFINEMENT_LENGTH) {
    return errorResponse(
      400,
      "refinement-too-long",
      `Refinement must be ${MAX_REFINEMENT_LENGTH} characters or fewer.`,
    );
  }

  const ip = getClientIp(req);
  if (ip === "unknown" && process.env.NODE_ENV === "production") {
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
    );
  }

  // 2. Scrub the refinement instruction (same defense as the primary prompt).
  // The current script is not scrubbed — it's already-generated PS code,
  // not user input that might contain secrets.
  const { cleaned: cleanedRefinement } = scrubPrompt(refinement.trim());

  // 3. Topic filter on the refinement instruction. The instruction must still
  // be domain-relevant; "now write a poem instead" would be rejected here.
  const topic = checkOnTopic(cleanedRefinement);
  if (!topic.onTopic) {
    return errorResponse(
      400,
      "off-topic",
      "Refinements must describe Intune / Microsoft Graph / Windows scripting changes. Please rephrase.",
    );
  }

  // 4. Per-IP rate limit (refinements count as generations).
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

  // 5. Reserve daily-cap tokens.
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

  const refineInstruction = `The original user request was:

${originalPrompt}

The current script is:

\`\`\`powershell
${currentScript}
\`\`\`

The user wants this modification applied to the script:

${cleanedRefinement}

Produce an updated version of the script that incorporates this modification. Keep all unaffected parts identical, including the metadata block structure. Apply all the same hard rules from your system prompt. Update .CHANGELOG with a brief note about the change, increment .VERSION minor (e.g. 1.0 -> 1.1), and use ${today} for .LASTUPDATE. Output ONLY the updated script in a single \`\`\`powershell fenced code block.`;

  const result = streamText({
    model: anthropic(MODEL_ID),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: 0.2,
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
        content: refineInstruction,
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

  return result.toTextStreamResponse();
}
