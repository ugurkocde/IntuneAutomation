import "server-only";
import { env } from "~/env";

const TURNSTILE_VERIFY_URL =
  "https://challenges.cloudflare.com/turnstile/v0/siteverify";

let warnedAboutMissingSecret = false;

export type TurnstileResult =
  | { ok: true; bypassed: boolean }
  | { ok: false; reason: string };

export async function verifyTurnstile(
  token: string | null | undefined,
  ip: string | null,
): Promise<TurnstileResult> {
  // Bypass in development so localhost works without the site key being
  // whitelisted for 127.0.0.1 in the Cloudflare dashboard.
  if (process.env.NODE_ENV === "development") {
    return { ok: true, bypassed: true };
  }

  // No secret in non-dev environments is a deployment misconfiguration.
  // Fail closed rather than silently disable bot verification.
  if (!env.TURNSTILE_SECRET_KEY) {
    if (!warnedAboutMissingSecret) {
      console.error(
        "[generator] TURNSTILE_SECRET_KEY is not set — rejecting all " +
          "generator requests until the env var is configured.",
      );
      warnedAboutMissingSecret = true;
    }
    return { ok: false, reason: "turnstile-not-configured" };
  }

  if (!token) {
    return { ok: false, reason: "missing-token" };
  }

  const body = new URLSearchParams();
  body.set("secret", env.TURNSTILE_SECRET_KEY);
  body.set("response", token);
  if (ip && ip !== "unknown") body.set("remoteip", ip);

  try {
    const res = await fetch(TURNSTILE_VERIFY_URL, {
      method: "POST",
      body,
      headers: { "content-type": "application/x-www-form-urlencoded" },
    });
    const data = (await res.json()) as {
      success?: boolean;
      "error-codes"?: string[];
    };
    if (!data.success) {
      return {
        ok: false,
        reason: data["error-codes"]?.join(",") ?? "verification-failed",
      };
    }
    return { ok: true, bypassed: false };
  } catch (err) {
    return {
      ok: false,
      reason:
        err instanceof Error ? `network: ${err.message}` : "network-error",
    };
  }
}
