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
import { checkOnTopic } from "~/server/generator/topic-filter";
import { classifyOnTopicWithLLM } from "~/server/generator/topic-classifier";
import {
  errorResponse,
  getClientIp,
  sanitizeForFencedInterpolation,
  streamAbortSignal,
} from "~/server/generator/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_REFINEMENT_LENGTH = 1500;
const MAX_ORIGINAL_PROMPT_LENGTH = 4000;
const MAX_SCRIPT_LENGTH = 30_000;
const MAX_OUTPUT_TOKENS = 6000;
const RESERVED_TOKENS_PER_REQUEST = 8000;
const MODEL_ID = "claude-haiku-4-5";

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "bad-request", "Invalid JSON body.");
  }

  const { originalPrompt, currentScript, refinement, turnstileToken } = (body ??
    {}) as {
    originalPrompt?: unknown;
    currentScript?: unknown;
    refinement?: unknown;
    turnstileToken?: unknown;
  };

  if (typeof originalPrompt !== "string" || originalPrompt.length === 0) {
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

  // 1. Bot/abuse gate — accept EITHER fresh Turnstile token OR active
  // continuation session opened by a recent /generate (same model as /fix).
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

  // 2. Scrub both the refinement instruction AND the original prompt — both
  // are user-controlled text that ends up in the LLM message verbatim.
  const { cleaned: cleanedRefinement } = scrubPrompt(refinement.trim());
  const { cleaned: cleanedOriginalPrompt } = scrubPrompt(originalPrompt.trim());

  // 3. Topic filter on BOTH the refinement and the original prompt. The
  // original prompt appears first in the conversation; an attacker could try
  // to slip a jailbreak in there and use a clean refinement to pass this gate.
  const refinementTopic = checkOnTopic(cleanedRefinement);
  if (!refinementTopic.onTopic) {
    const llmSaysOnTopic = await classifyOnTopicWithLLM(cleanedRefinement);
    if (!llmSaysOnTopic) {
      return errorResponse(
        400,
        "off-topic",
        "Refinements must describe Intune / Microsoft Graph / Windows scripting changes. Please rephrase.",
      );
    }
  }
  const originalTopic = checkOnTopic(cleanedOriginalPrompt);
  if (!originalTopic.onTopic) {
    const llmSaysOnTopic = await classifyOnTopicWithLLM(cleanedOriginalPrompt);
    if (!llmSaysOnTopic) {
      return errorResponse(
        400,
        "off-topic",
        "The original prompt does not look like an Intune / Microsoft Graph / Windows scripting request.",
      );
    }
  }

  // 4. Sanitize the current script — client-controlled, must not break out
  // of the fenced block we wrap it in.
  const safeCurrentScript = sanitizeForFencedInterpolation(
    currentScript,
    MAX_SCRIPT_LENGTH,
  );

  // 5. Per-IP rate limit (refinements count as generations).
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

  // 6. Reserve daily-cap tokens.
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

  const refineInstruction = `The original user request was:

${cleanedOriginalPrompt}

The current script is:

\`\`\`powershell
${safeCurrentScript}
\`\`\`

The user wants this modification applied to the script:

${cleanedRefinement}

Produce an updated version of the script that incorporates this modification. Keep all unaffected parts identical, including the metadata block structure. Apply all the same hard rules from your system prompt. Update .CHANGELOG with a brief note about the change, increment .VERSION minor (e.g. 1.0 -> 1.1), and use ${today} for .LASTUPDATE. Output ONLY the updated script in a single \`\`\`powershell fenced code block.`;

  const result = streamText({
    model: anthropic(MODEL_ID),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: 0.2,
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
        content: refineInstruction,
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
