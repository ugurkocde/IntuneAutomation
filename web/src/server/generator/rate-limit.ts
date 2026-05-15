import "server-only";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";
import { createHash } from "node:crypto";
import { env } from "~/env";

const redis =
  env.UPSTASH_REDIS_REST_URL && env.UPSTASH_REDIS_REST_TOKEN
    ? new Redis({
        url: env.UPSTASH_REDIS_REST_URL,
        token: env.UPSTASH_REDIS_REST_TOKEN,
      })
    : null;

// 20 generations / IP / 24h. Sliding window so traffic spreads out.
const perIpLimiter = redis
  ? new Ratelimit({
      redis,
      limiter: Ratelimit.slidingWindow(20, "24 h"),
      analytics: false,
      prefix: "gen:ip",
    })
  : null;

const DAILY_CAP_TOKENS = env.GENERATOR_DAILY_TOKEN_CAP ?? 2_000_000;

function utcDateKey() {
  // YYYY-MM-DD in UTC — single bucket per day
  return new Date().toISOString().slice(0, 10);
}

export function hashIp(ip: string): string {
  return createHash("sha256").update(ip).digest("hex").slice(0, 32);
}

export type PerIpResult =
  | { allowed: true; remaining: number; reset: number }
  | { allowed: false; remaining: 0; reset: number; reason: "per-ip" };

export async function checkPerIp(ipHash: string): Promise<PerIpResult> {
  if (!perIpLimiter) {
    // Dev mode with no Redis configured — allow everything.
    return { allowed: true, remaining: 999, reset: Date.now() + 86_400_000 };
  }
  const { success, remaining, reset } = await perIpLimiter.limit(ipHash);
  if (!success) {
    return { allowed: false, remaining: 0, reset, reason: "per-ip" };
  }
  return { allowed: true, remaining, reset };
}

export const PER_IP_LIMIT = 20;

// Non-consuming peek at the per-IP quota. Used by the UI to show remaining
// quota without burning a generation.
export async function peekPerIp(
  ipHash: string,
): Promise<{ remaining: number; limit: number; reset: number }> {
  if (!perIpLimiter) {
    return {
      remaining: PER_IP_LIMIT,
      limit: PER_IP_LIMIT,
      reset: Date.now() + 86_400_000,
    };
  }
  const { remaining, reset, limit } = await perIpLimiter.getRemaining(ipHash);
  return { remaining, limit, reset };
}

export type ReservationResult =
  | { allowed: true; reservationId: string; usedTokens: number }
  | { allowed: false; usedTokens: number; capTokens: number };

// Atomic pessimistic reservation: increments the daily counter by the
// estimated max tokens up front, then checks if the new total exceeds the cap.
// This closes the TOCTOU window between check and stream completion.
//
// Returns a reservation token that callers must pass to commitReservation()
// after the stream finishes, to reconcile the estimate with actual usage.
export async function reserveTokens(
  estimatedTokens: number,
): Promise<ReservationResult> {
  if (!redis) {
    return {
      allowed: true,
      reservationId: "dev",
      usedTokens: 0,
    };
  }
  const key = `gen:tokens:${utcDateKey()}`;
  const newTotal = await redis.incrby(key, estimatedTokens);
  // Set TTL unconditionally — idempotent, avoids a TOCTOU where two concurrent
  // writers both miss the "first write" condition and leave the key without
  // expiry. Cheap.
  await redis.expire(key, 60 * 60 * 48);
  if (newTotal > DAILY_CAP_TOKENS) {
    // Over the cap — refund the reservation and reject.
    await redis.incrby(key, -estimatedTokens);
    return {
      allowed: false,
      usedTokens: newTotal - estimatedTokens,
      capTokens: DAILY_CAP_TOKENS,
    };
  }
  return {
    allowed: true,
    reservationId: String(estimatedTokens),
    usedTokens: newTotal,
  };
}

// Reconcile the reservation against actual usage. Adjusts the counter by
// (actualTokens - reservedTokens). Negative values are fine.
export async function commitReservation(
  reservedTokens: number,
  actualTokens: number,
): Promise<void> {
  if (!redis) return;
  const delta = actualTokens - reservedTokens;
  if (delta === 0) return;
  const key = `gen:tokens:${utcDateKey()}`;
  await redis.incrby(key, delta);
}

// Release a reservation without recording any usage (e.g. early failure).
export async function releaseReservation(
  reservedTokens: number,
): Promise<void> {
  if (!redis || reservedTokens <= 0) return;
  const key = `gen:tokens:${utcDateKey()}`;
  await redis.incrby(key, -reservedTokens);
}
