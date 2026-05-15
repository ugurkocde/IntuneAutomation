import "server-only";
import { NextResponse, type NextRequest } from "next/server";

export function getClientIp(req: NextRequest): string {
  // On Vercel, `x-real-ip` is set by the platform to the verified client IP
  // and is not influenceable by the client. Prefer it over `x-forwarded-for`,
  // which is a comma-separated chain whose leftmost entry can be spoofed
  // upstream of the platform proxy in some configurations.
  const real = req.headers.get("x-real-ip");
  if (real && real.trim().length > 0) return real.trim();
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]?.trim() ?? "unknown";
  return "unknown";
}

export function errorResponse(
  status: number,
  code: string,
  message: string,
  extra?: Record<string, unknown>,
  headers?: Record<string, string>,
) {
  const res = NextResponse.json(
    { error: code, message, ...extra },
    { status },
  );
  if (headers) {
    for (const [k, v] of Object.entries(headers)) res.headers.set(k, v);
  }
  return res;
}

// Caps how long a single stream may run. The Vercel function timeout is the
// outer bound — this just makes sure we proactively release the daily-cap
// reservation if Anthropic stalls mid-stream.
export const STREAM_TIMEOUT_MS = 55_000;

export function streamAbortSignal(req: NextRequest): AbortSignal {
  // Merge the client-disconnect signal with a hard timeout. Either trips the
  // stream abort.
  return AbortSignal.any([req.signal, AbortSignal.timeout(STREAM_TIMEOUT_MS)]);
}

// Sanitize free-text fields that will be interpolated into LLM prompts inside
// fenced code blocks. Strips bare backtick fences so a malicious payload can't
// close the fence early and inject instructions. Caps the length too.
export function sanitizeForFencedInterpolation(
  input: string,
  maxLen: number,
): string {
  return input
    .slice(0, maxLen)
    .replace(/```/g, "ʼʼʼ")
    .replace(/\r/g, "");
}
