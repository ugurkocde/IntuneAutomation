"use client";

import "prismjs/themes/prism-tomorrow.css";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import Script from "next/script";
import {
  AlertTriangle,
  Check,
  Copy,
  Download,
  Loader2,
  ShieldCheck,
  SendHorizontal,
  Wand2,
} from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider, useScripts } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";

const ScriptDetail = dynamic(
  () =>
    import("~/components/script-detail").then((mod) => ({
      default: mod.ScriptDetail,
    })),
  { ssr: false },
);
import { Button } from "~/components/ui/button";
import { cn } from "~/lib/utils";
import { lintScript, type LintResult } from "~/lib/generator-lint";
import {
  extractGraphEndpointUsages,
  isKnownGraphEndpoint,
} from "~/lib/generator-graph-endpoints";
import { Inspector } from "./_components/inspector";

type Redaction = {
  kind: string;
  label: string;
  count: number;
};

type Props = {
  turnstileSiteKey: string | null;
  // Server-rendered SEO content. Lives inside the client wrapper so the
  // crawl-visible static surface ships in the initial HTML — see
  // generator/page.tsx for the rendered markup.
  seoContent?: ReactNode;
  seoFooter?: ReactNode;
};

const MAX_PROMPT_LENGTH = 4000;

const EXAMPLE_PROMPTS = [
  "List all stale Intune devices that haven't checked in for 90 days and export to CSV",
  "Detection script: check if BitLocker is enabled on the system drive",
  "Report all Conditional Access policies with their assignments and conditions",
  "Find apps with deployment failures in the last 7 days and email a summary",
];

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: HTMLElement,
        opts: {
          sitekey: string;
          callback: (token: string) => void;
          "error-callback"?: () => void;
          "expired-callback"?: () => void;
          theme?: "light" | "dark" | "auto";
        },
      ) => string;
      reset: (widgetId?: string) => void;
      remove: (widgetId: string) => void;
    };
  }
}

export default function GeneratorClient({
  turnstileSiteKey,
  seoContent,
  seoFooter,
}: Props) {
  const [prompt, setPrompt] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [output, setOutput] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [redactions, setRedactions] = useState<Redaction[]>([]);
  const [copied, setCopied] = useState(false);
  const [lintResult, setLintResult] = useState<LintResult | null>(null);
  // True while the post-stream auto-fix pass is running. UI suppresses the
  // lint panel during this window so users see "Polishing..." instead of an
  // intermediate panel + fix-button click sequence.
  const [isAutoFixing, setIsAutoFixing] = useState(false);
  // Live Graph endpoint verification visible during streaming. Each entry is
  // a unique (method, path) pair extracted from the streamed output so far.
  const [endpointChecks, setEndpointChecks] = useState<
    { method: string; path: string; known: boolean }[]
  >([]);
  const [refinement, setRefinement] = useState("");
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [turnstileStatus, setTurnstileStatus] = useState<
    "idle" | "loading" | "ready" | "expired" | "failed"
  >("idle");
  const [quota, setQuota] = useState<{
    remaining: number;
    limit: number;
    reset: number;
  } | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const turnstileContainerRef = useRef<HTMLDivElement | null>(null);
  const turnstileWidgetIdRef = useRef<string | null>(null);
  const turnstileRetriesRef = useRef(0);
  const codeRef = useRef<HTMLElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const outputRef = useRef<HTMLDivElement | null>(null);
  const didScrollForStreamRef = useRef(false);
  const codeScrollRef = useRef<HTMLPreElement | null>(null);
  // Sticky-to-bottom flag for the streaming code panel. Stays true while the
  // user is at the bottom; flips to false the moment they scroll up, so we
  // don't fight their manual review.
  const followStreamRef = useRef(true);
  // Per-generation flag — only one auto-fix pass is allowed per initial
  // stream, so we don't loop on issues the model can't actually resolve.
  const didAutoFixRef = useRef(false);
  // Ref-bridge so the post-stream effect (declared above runFix) can invoke
  // the latest fix routine without depending on it directly.
  const runFixRef = useRef<
    | ((script: string, findings: LintResult["findings"]) => Promise<void>)
    | null
  >(null);

  // Render Turnstile widget once the script loads.
  const renderTurnstile = useCallback(() => {
    if (!turnstileSiteKey) return;
    if (!turnstileContainerRef.current) return;
    if (!window.turnstile) return;
    if (turnstileWidgetIdRef.current) return;

    setTurnstileStatus("loading");
    try {
      turnstileWidgetIdRef.current = window.turnstile.render(
        turnstileContainerRef.current,
        {
          sitekey: turnstileSiteKey,
          theme: "auto",
          callback: (token) => {
            setTurnstileToken(token);
            setTurnstileStatus("ready");
            turnstileRetriesRef.current = 0;
          },
          "expired-callback": () => {
            setTurnstileToken(null);
            setTurnstileStatus("expired");
          },
          "error-callback": () => {
            setTurnstileToken(null);
            // Auto-retry a few times before giving up — Turnstile doesn't
            // self-recover after a transient challenge failure.
            const id = turnstileWidgetIdRef.current;
            if (turnstileRetriesRef.current < 3 && id && window.turnstile) {
              turnstileRetriesRef.current++;
              window.turnstile.reset(id);
              setTurnstileStatus("loading");
            } else {
              setTurnstileStatus("failed");
            }
          },
        },
      );
    } catch {
      setTurnstileStatus("failed");
    }
  }, [turnstileSiteKey]);

  // If the script loaded before the container mounted, try again on mount.
  useEffect(() => {
    if (turnstileSiteKey && window.turnstile) {
      renderTurnstile();
    }
  }, [turnstileSiteKey, renderTurnstile]);

  // Polling fallback: covers two failure modes — (a) api.js loads before the
  // container mounts so renderTurnstile bails early, and (b) api.js is
  // blocked by an ad/privacy blocker and never fires onLoad. Retry every
  // 500ms for up to 12s, then surface a clear error so users can recover.
  useEffect(() => {
    if (!turnstileSiteKey) return;
    if (turnstileWidgetIdRef.current) return;
    let elapsed = 0;
    const interval = window.setInterval(() => {
      elapsed += 500;
      if (turnstileWidgetIdRef.current) {
        window.clearInterval(interval);
        return;
      }
      if (window.turnstile) {
        renderTurnstile();
      }
      if (elapsed >= 12_000) {
        window.clearInterval(interval);
        if (!turnstileWidgetIdRef.current) {
          setTurnstileStatus("failed");
        }
      }
    }, 500);
    return () => window.clearInterval(interval);
  }, [turnstileSiteKey, renderTurnstile]);

  // Unmount cleanup: remove the widget so a re-mount doesn't orphan it and
  // leave the form stuck because of the cached widget-id guard.
  useEffect(() => {
    return () => {
      const id = turnstileWidgetIdRef.current;
      if (id && window.turnstile) {
        try {
          window.turnstile.remove(id);
        } catch {
          // Ignore — widget may already be gone.
        }
      }
      turnstileWidgetIdRef.current = null;
    };
  }, []);

  // Fetch the current per-IP quota on mount so the counter is accurate before
  // the user generates anything. Best-effort: failures fall back to no display.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/generator/quota", {
          cache: "no-store",
        });
        if (!res.ok) return;
        const data = (await res.json()) as {
          remaining: number | null;
          limit: number | null;
          reset: number | null;
        };
        if (
          cancelled ||
          data.remaining == null ||
          data.limit == null ||
          data.reset == null
        )
          return;
        setQuota({
          remaining: data.remaining,
          limit: data.limit,
          reset: data.reset,
        });
      } catch {
        // Non-critical
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Tick once a minute so the "resets in" countdown stays current without
  // burning CPU on per-second updates.
  useEffect(() => {
    if (!quota) return;
    const id = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(id);
  }, [quota]);

  // When a new stream begins and the output container has rendered with its
  // first tokens, scroll it into view once — so users see where the result
  // will appear. Only fires once per stream to avoid fighting manual scroll.
  useEffect(() => {
    if (!isStreaming || !output || didScrollForStreamRef.current) return;
    const el = outputRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const isOffScreen = rect.top > window.innerHeight * 0.6 || rect.bottom < 0;
    if (isOffScreen) {
      el.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    didScrollForStreamRef.current = true;
  }, [isStreaming, output]);

  // While streaming, keep the code panel pinned to the bottom so the user can
  // follow new tokens. If the user scrolls up to review earlier output, we
  // back off — followStreamRef tracks that intent.
  useEffect(() => {
    if (!isStreaming) return;
    const el = codeScrollRef.current;
    if (!el || !followStreamRef.current) return;
    el.scrollTop = el.scrollHeight;
  }, [isStreaming, output]);

  // Live Graph endpoint verification — re-runs on every output chunk so the
  // admin can see in real time that detected URIs are being checked against
  // the published Microsoft Graph catalog. Cheap: regex + Map lookup against
  // ~6,400 templates, microseconds per call. Deduped by `METHOD path`.
  useEffect(() => {
    if (!output) {
      if (endpointChecks.length > 0) setEndpointChecks([]);
      return;
    }
    const usages = extractGraphEndpointUsages(output);
    const seen = new Set<string>();
    const next: { method: string; path: string; known: boolean }[] = [];
    for (const u of usages) {
      const key = `${u.method} ${u.path}`;
      if (seen.has(key)) continue;
      seen.add(key);
      next.push({
        method: u.method,
        path: u.path,
        known: isKnownGraphEndpoint(u.method, u.path),
      });
    }
    const sameAsPrev =
      next.length === endpointChecks.length &&
      next.every(
        (n, i) =>
          n.method === endpointChecks[i]?.method &&
          n.path === endpointChecks[i]?.path &&
          n.known === endpointChecks[i]?.known,
      );
    if (!sameAsPrev) setEndpointChecks(next);
  }, [output, endpointChecks]);

  // Detect user-initiated scroll inside the code panel. Within ~24px of the
  // bottom counts as "still following"; anything higher pauses auto-scroll.
  const onCodeScroll = useCallback(() => {
    const el = codeScrollRef.current;
    if (!el) return;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    followStreamRef.current = distanceFromBottom < 24;
  }, []);

  // Highlight the final output once streaming finishes, and run the lint pass.
  useEffect(() => {
    if (isStreaming || !output || !codeRef.current) return;

    const extracted = extractPowerShellCode(output) ?? output;
    const result = lintScript(extracted);
    setLintResult(result);

    // Auto-fix once: if the very first lint pass after a fresh generation
    // surfaces fail/warn findings, silently re-run the fix endpoint so the
    // user gets a clean script without needing to click "Fix with AI".
    // Skipped on hard-rejects (model produced non-script output) and after
    // one pass already happened (so we don't loop on issues the model can't
    // resolve).
    const hasActionableIssues = result.failCount > 0 || result.warnCount > 0;
    if (
      hasActionableIssues &&
      !result.hardReject &&
      !didAutoFixRef.current &&
      runFixRef.current
    ) {
      didAutoFixRef.current = true;
      setIsAutoFixing(true);
      void runFixRef
        .current(extracted, result.findings)
        .finally(() => setIsAutoFixing(false));
      // Don't run Prism on output we're about to replace.
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const Prism = await import("prismjs");
        // @ts-expect-error - Prism component imports lack types
        await import("prismjs/components/prism-powershell");
        if (!cancelled && codeRef.current) {
          Prism.highlightElement(codeRef.current);
        }
      } catch {
        // Highlighting is non-critical.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isStreaming, output]);

  const absorbQuotaHeaders = useCallback((res: Response) => {
    const remaining = res.headers.get("x-ratelimit-remaining");
    const reset = res.headers.get("x-ratelimit-reset");
    if (remaining == null || reset == null) return;
    const remainingNum = Number(remaining);
    const resetNum = Number(reset);
    if (!Number.isFinite(remainingNum) || !Number.isFinite(resetNum)) return;
    setQuota((prev) => ({
      remaining: remainingNum,
      reset: resetNum,
      limit: prev?.limit ?? 20,
    }));
  }, []);

  const isDev = process.env.NODE_ENV === "development";

  const canGenerate =
    prompt.trim().length > 0 &&
    prompt.length <= MAX_PROMPT_LENGTH &&
    accepted &&
    (isDev || !turnstileSiteKey || turnstileToken) &&
    !isStreaming;

  const onSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!canGenerate) return;

      setError(null);
      setOutput("");
      setRedactions([]);
      setLintResult(null);
      setCopied(false);
      setIsStreaming(true);
      didScrollForStreamRef.current = false;
      followStreamRef.current = true;
      // Allow one auto-fix pass per fresh generation. Refine/fix don't reset
      // this — only a brand-new prompt does.
      didAutoFixRef.current = false;

      const controller = new AbortController();
      abortRef.current = controller;

      try {
        const res = await fetch("/api/generator/generate", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            prompt,
            turnstileToken,
            acceptedTerms: true,
          }),
          signal: controller.signal,
        });

        absorbQuotaHeaders(res);

        if (!res.ok) {
          const data = (await res.json().catch(() => null)) as {
            message?: string;
          } | null;
          throw new Error(data?.message ?? `Request failed (${res.status})`);
        }

        const redactionHeader = res.headers.get("x-generator-redactions");
        if (redactionHeader) {
          try {
            const parsed = JSON.parse(atob(redactionHeader)) as Redaction[];
            setRedactions(parsed);
          } catch {
            // Ignore malformed header
          }
        }

        const reader = res.body?.getReader();
        if (!reader) throw new Error("No response stream.");
        const decoder = new TextDecoder();
        let accumulated = "";
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          accumulated += decoder.decode(value, { stream: true });
          setOutput(accumulated);
        }
      } catch (err) {
        if ((err as { name?: string } | null)?.name === "AbortError") return;
        setError(err instanceof Error ? err.message : "Something went wrong.");
      } finally {
        setIsStreaming(false);
        abortRef.current = null;
        if (turnstileWidgetIdRef.current && window.turnstile) {
          window.turnstile.reset(turnstileWidgetIdRef.current);
          setTurnstileToken(null);
        }
      }
    },
    [canGenerate, prompt, turnstileToken, absorbQuotaHeaders],
  );

  const onCancel = useCallback(() => {
    abortRef.current?.abort();
    setIsStreaming(false);
  }, []);

  const onRefine = useCallback(async () => {
    const trimmed = refinement.trim();
    if (!trimmed) return;
    const currentScript = extractPowerShellCode(output) ?? output;
    if (!currentScript) return;

    setError(null);
    setIsStreaming(true);
    setLintResult(null);
    setCopied(false);
    followStreamRef.current = true;

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const res = await fetch("/api/generator/refine", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          originalPrompt: prompt,
          currentScript,
          refinement: trimmed,
          turnstileToken,
        }),
        signal: controller.signal,
      });

      absorbQuotaHeaders(res);

      if (!res.ok) {
        const data = (await res.json().catch(() => null)) as {
          message?: string;
        } | null;
        throw new Error(data?.message ?? `Refine failed (${res.status})`);
      }

      const reader = res.body?.getReader();
      if (!reader) throw new Error("No response stream.");
      const decoder = new TextDecoder();
      let accumulated = "";
      setOutput("");
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        accumulated += decoder.decode(value, { stream: true });
        setOutput(accumulated);
      }
      setRefinement("");
    } catch (err) {
      if ((err as { name?: string } | null)?.name === "AbortError") return;
      setError(err instanceof Error ? err.message : "Something went wrong.");
    } finally {
      setIsStreaming(false);
      abortRef.current = null;
      if (turnstileWidgetIdRef.current && window.turnstile) {
        window.turnstile.reset(turnstileWidgetIdRef.current);
        setTurnstileToken(null);
      }
    }
  }, [refinement, output, prompt, turnstileToken, absorbQuotaHeaders]);

  // Shared fix-streaming routine. Used by both the manual "Fix with AI"
  // button and the post-generation auto-fix pass. Takes the script + findings
  // explicitly so callers don't have to round-trip through state.
  const runFix = useCallback(
    async (currentScript: string, findings: LintResult["findings"]) => {
      setError(null);
      setIsStreaming(true);
      setLintResult(null);
      setCopied(false);
      followStreamRef.current = true;

      const controller = new AbortController();
      abortRef.current = controller;

      try {
        const res = await fetch("/api/generator/fix", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            originalPrompt: prompt,
            currentScript,
            findings,
            turnstileToken,
          }),
          signal: controller.signal,
        });

        absorbQuotaHeaders(res);

        if (!res.ok) {
          const data = (await res.json().catch(() => null)) as {
            message?: string;
          } | null;
          throw new Error(data?.message ?? `Fix failed (${res.status})`);
        }

        const reader = res.body?.getReader();
        if (!reader) throw new Error("No response stream.");
        const decoder = new TextDecoder();
        let accumulated = "";
        setOutput("");
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          accumulated += decoder.decode(value, { stream: true });
          setOutput(accumulated);
        }
      } catch (err) {
        if ((err as { name?: string } | null)?.name === "AbortError") return;
        setError(err instanceof Error ? err.message : "Something went wrong.");
      } finally {
        setIsStreaming(false);
        abortRef.current = null;
        if (turnstileWidgetIdRef.current && window.turnstile) {
          window.turnstile.reset(turnstileWidgetIdRef.current);
          setTurnstileToken(null);
        }
      }
    },
    [prompt, turnstileToken, absorbQuotaHeaders],
  );

  // Keep the ref pointed at the latest runFix so the post-stream effect can
  // invoke it without taking a dep on the callback identity.
  runFixRef.current = runFix;

  const onFixIssues = useCallback(async () => {
    if (!lintResult || lintResult.failCount + lintResult.warnCount === 0)
      return;
    const currentScript = extractPowerShellCode(output) ?? output;
    if (!currentScript) return;
    await runFix(currentScript, lintResult.findings);
  }, [lintResult, output, runFix]);

  const onCopy = useCallback(async () => {
    const code = extractPowerShellCode(output) ?? output;
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setError("Could not copy to clipboard.");
    }
  }, [output]);

  const onDownload = useCallback(() => {
    const code = extractPowerShellCode(output) ?? output;
    const title = extractTitle(code) ?? "intune-script";
    const slug = title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "")
      .slice(0, 60);
    const blob = new Blob([code], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${slug || "intune-script"}.ps1`;
    a.click();
    URL.revokeObjectURL(url);
  }, [output]);

  const code = extractPowerShellCode(output) ?? output;

  return (
    <ScriptsProvider>
      <div className="bg-background text-foreground min-h-screen">
        {turnstileSiteKey && (
          <Script
            src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
            strategy="afterInteractive"
            onLoad={renderTurnstile}
          />
        )}

        <Navbar />
        <SearchDialog />

        {/* Atmospheric backdrop — soft phosphor halo + faint blueprint grid,
          consistent with hero/how-it-works sections. Sits behind content. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-x-0 top-0 -z-0 h-[520px] overflow-hidden"
        >
          <div className="bg-blueprint-soft absolute inset-0 [mask-image:linear-gradient(to_bottom,black,transparent_85%)] opacity-40" />
          <div className="bg-glow-accent animate-drift absolute -top-32 left-1/2 h-[520px] w-[820px] -translate-x-1/2 opacity-70" />
        </div>

        <div className="relative container mx-auto max-w-4xl px-4 py-12 sm:py-20">
          {/* SEO content — server-rendered via parent. Includes the H1,
            definition paragraph, and kicker chip. Crawl-visible in initial HTML. */}
          {seoContent}

          {/* Form */}
          <form onSubmit={onSubmit} className="space-y-6">
            {/* Security notice */}
            <div className="border-accent/25 bg-accent-soft/70 flex gap-3 rounded-lg border p-4 text-sm backdrop-blur-sm">
              <ShieldCheck className="text-accent mt-0.5 h-4 w-4 flex-shrink-0" />
              <div>
                <div className="font-medium">
                  Don&apos;t paste secrets, credentials, or tenant IDs.
                </div>
                <div className="text-muted-foreground mt-0.5 text-[13px] leading-relaxed">
                  We scrub obvious patterns (GUIDs, tokens, keys, emails) before
                  sending — but you&apos;re the first line of defense.
                </div>
              </div>
            </div>

            {/* Prompt — the hero input. Surfaces as a distinct card with
              elevated treatment so it reads as the primary action zone. */}
            <div className="border-border/70 bg-card/80 rounded-xl border p-4 shadow-sm backdrop-blur-sm sm:p-5">
              <label
                htmlFor="prompt"
                className="text-muted-foreground mb-3 flex items-center gap-2 font-mono text-[11px] tracking-[0.16em] uppercase"
              >
                <span
                  className="bg-accent h-1.5 w-1.5 rounded-full"
                  aria-hidden="true"
                />
                What should the script do?
              </label>
              <textarea
                id="prompt"
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                placeholder="e.g. List all Intune-enrolled devices that haven't checked in for 60 days and export the results to CSV."
                rows={5}
                maxLength={MAX_PROMPT_LENGTH}
                className="border-border/60 bg-background/60 text-foreground placeholder:text-muted-foreground/55 focus-visible:border-accent/60 focus-visible:ring-accent/25 w-full resize-y rounded-md border px-4 py-3 text-[14.5px] leading-relaxed shadow-xs transition-colors focus-visible:ring-[3px] focus-visible:outline-none"
              />
              <div className="text-muted-foreground mt-2.5 flex items-center justify-between text-[11px]">
                <span
                  className={cn(
                    "font-mono tabular-nums transition-colors",
                    prompt.length > MAX_PROMPT_LENGTH * 0.9 && "text-amber-500",
                    prompt.length >= MAX_PROMPT_LENGTH && "text-destructive",
                  )}
                >
                  {prompt.length} / {MAX_PROMPT_LENGTH}
                </span>
                <button
                  type="button"
                  className="hover:text-foreground focus-visible:ring-ring/50 cursor-pointer rounded-sm transition-colors focus-visible:ring-2 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50"
                  onClick={() => setPrompt("")}
                  disabled={!prompt}
                >
                  Clear
                </button>
              </div>

              {/* Examples — placed inside the prompt card so suggestions feel
                like extensions of the input, not a separate concept. */}
              <div className="border-border/40 mt-4 border-t pt-4">
                <div className="text-muted-foreground mb-2.5 font-mono text-[10.5px] tracking-[0.18em] uppercase">
                  Try one of these
                </div>
                <div className="flex flex-wrap gap-2">
                  {EXAMPLE_PROMPTS.map((example) => (
                    <button
                      key={example}
                      type="button"
                      onClick={() => setPrompt(example)}
                      className="border-border/60 hover:border-accent/50 hover:bg-accent-soft text-muted-foreground hover:text-foreground focus-visible:ring-accent/40 group bg-background/40 cursor-pointer rounded-md border px-2.5 py-1.5 text-[12px] leading-snug transition-all duration-150 hover:-translate-y-px focus-visible:ring-2 focus-visible:outline-none"
                    >
                      {example.length > 60
                        ? example.slice(0, 60) + "…"
                        : example}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* Turnstile widget */}
            {turnstileSiteKey && (
              <div>
                <div ref={turnstileContainerRef} className="min-h-[65px]" />
                {turnstileStatus === "failed" && (
                  <p className="text-destructive text-[13px] leading-relaxed">
                    Bot verification couldn&apos;t load. This is usually caused
                    by an ad blocker or privacy extension blocking{" "}
                    <code className="font-mono text-[12px]">
                      challenges.cloudflare.com
                    </code>
                    . Allow it for this site or try a different browser, then
                    reload the page.
                  </p>
                )}
                {(turnstileStatus === "idle" ||
                  turnstileStatus === "loading") &&
                  !turnstileToken && (
                    <p className="text-muted-foreground text-[12px]">
                      Loading bot verification…
                    </p>
                  )}
              </div>
            )}

            {/* Terms checkbox */}
            <label className="flex cursor-pointer items-start gap-2.5 text-[13px] leading-relaxed">
              <input
                type="checkbox"
                checked={accepted}
                onChange={(e) => setAccepted(e.target.checked)}
                className="border-border/70 accent-accent mt-0.5 h-4 w-4 flex-shrink-0 rounded"
              />
              <span className="text-muted-foreground">
                I understand this script is AI-generated and may contain errors.
                I am solely responsible for reviewing, testing, and running it
                in my environment. I accept the{" "}
                <Link
                  href="/terms"
                  className="text-foreground hover:text-accent underline underline-offset-2"
                  target="_blank"
                >
                  Terms of Use
                </Link>{" "}
                and{" "}
                <Link
                  href="/privacy"
                  className="text-foreground hover:text-accent underline underline-offset-2"
                  target="_blank"
                >
                  Privacy Policy
                </Link>
                .
              </span>
            </label>

            {/* Submit */}
            <div className="space-y-3 pt-1">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                <Button
                  type="submit"
                  size="lg"
                  disabled={!canGenerate || quota?.remaining === 0}
                  className="bg-foreground text-background hover:bg-foreground/90 inline-flex h-11 cursor-pointer items-center gap-2 px-6 text-[14px] font-medium shadow-[0_10px_28px_-12px_color-mix(in_oklab,var(--brand-accent)_70%,transparent)] transition-all duration-200 hover:-translate-y-0.5 hover:shadow-[0_14px_36px_-12px_color-mix(in_oklab,var(--brand-accent)_80%,transparent)] active:translate-y-0 disabled:translate-y-0 disabled:shadow-none"
                >
                  {isStreaming ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Generating…
                    </>
                  ) : (
                    <>
                      <Wand2 className="h-3.5 w-3.5" />
                      Generate script
                    </>
                  )}
                </Button>
                {isStreaming && (
                  <Button
                    type="button"
                    variant="outline"
                    size="lg"
                    onClick={onCancel}
                    className="border-border/70 h-11 cursor-pointer"
                  >
                    Cancel
                  </Button>
                )}
                {!isStreaming && !canGenerate && (
                  <p className="text-muted-foreground text-[12px]">
                    {prompt.trim().length === 0
                      ? "Describe what the script should do to enable."
                      : prompt.length > MAX_PROMPT_LENGTH
                        ? `Prompt is too long (max ${MAX_PROMPT_LENGTH} characters).`
                        : !accepted
                          ? "Accept the Terms above to enable."
                          : turnstileSiteKey && !turnstileToken && !isDev
                            ? "Complete the verification above to enable."
                            : null}
                  </p>
                )}
              </div>
              {quota && (
                <div className="flex items-center gap-2.5">
                  <div
                    className="bg-border/60 h-1 w-24 overflow-hidden rounded-full"
                    role="progressbar"
                    aria-valuemin={0}
                    aria-valuemax={quota.limit}
                    aria-valuenow={quota.remaining}
                    aria-label="Daily generations remaining"
                  >
                    <div
                      className={cn(
                        "h-full rounded-full transition-all",
                        quota.remaining === 0
                          ? "bg-destructive"
                          : quota.remaining <= 1
                            ? "bg-amber-500"
                            : "bg-accent",
                      )}
                      style={{
                        width: `${Math.max(0, Math.min(100, (quota.remaining / quota.limit) * 100))}%`,
                        backgroundColor:
                          quota.remaining > 1
                            ? "var(--brand-accent)"
                            : undefined,
                      }}
                    />
                  </div>
                  <p
                    className={cn(
                      "text-[12px] tabular-nums",
                      quota.remaining === 0
                        ? "text-destructive"
                        : quota.remaining <= 1
                          ? "text-amber-500"
                          : "text-muted-foreground",
                    )}
                  >
                    {quota.remaining === 0
                      ? `Daily limit reached · resets in ${formatResetIn(quota.reset, now)}`
                      : `${quota.remaining} of ${quota.limit} left today · resets in ${formatResetIn(quota.reset, now)}`}
                  </p>
                </div>
              )}
            </div>
          </form>

          {/* Error */}
          {error && (
            <div className="border-destructive/40 bg-destructive/5 text-destructive mt-6 flex gap-2 rounded-md border p-3 text-sm">
              <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Redaction summary */}
          {redactions.length > 0 && (
            <div className="border-border/70 bg-card mt-6 rounded-md border p-3 text-[13px]">
              <div className="text-muted-foreground mb-1.5 font-mono text-[10px] tracking-[0.16em] uppercase">
                Redacted from your prompt
              </div>
              <ul className="text-muted-foreground space-y-0.5">
                {redactions.map((r) => (
                  <li key={r.kind}>
                    <span className="text-foreground">{r.label}</span> ·{" "}
                    {r.count} occurrence{r.count !== 1 ? "s" : ""} replaced
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Hard-reject: output didn't look like a valid script. */}
          {output && !isStreaming && lintResult?.hardReject && (
            <div className="border-destructive/40 bg-destructive/5 mt-8 rounded-md border p-4">
              <div className="text-foreground mb-1 flex items-center gap-2 font-medium">
                <AlertTriangle className="text-destructive h-4 w-4" />
                Output was rejected
              </div>
              <p className="text-muted-foreground text-[13px] leading-relaxed">
                {lintResult.hardReject.reason} The generator only produces
                PowerShell scripts for Intune, Microsoft Graph, and Windows /
                macOS device management. Please rephrase your request.
              </p>
            </div>
          )}

          {/* Output */}
          {output && !lintResult?.hardReject && (
            <div
              ref={outputRef}
              // Break out of the prose-width parent (max-w-4xl) on large
              // screens so the code area + inspector both have room. Capped at
              // viewport width minus padding so we never overflow.
              className="animate-in fade-in slide-in-from-bottom-2 mx-auto mt-10 scroll-mt-24 duration-300 lg:-mx-24 xl:-mx-40"
            >
              <div className="mb-3 flex gap-2.5 rounded-lg border border-amber-500/25 bg-amber-500/5 p-3.5 text-[13px]">
                <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0 text-amber-500" />
                <span className="text-muted-foreground leading-relaxed">
                  <span className="text-foreground font-medium">
                    AI-generated.
                  </span>{" "}
                  Review and test before running in production. Verify all
                  Microsoft Graph permissions and commands are correct.
                </span>
              </div>

              {/* Split layout: code panel on the left, Inspector slides in from the right. */}
              <div className="flex flex-col gap-3 lg:flex-row lg:items-start">
                <div className="min-w-0 flex-1">
                  <div className="border-border/70 bg-card overflow-hidden rounded-xl border shadow-md ring-1 ring-black/[0.02] dark:ring-white/[0.02]">
                <div className="border-border/70 bg-background/60 flex items-center justify-between gap-3 border-b px-3.5 py-2.5 backdrop-blur-sm">
                  <div className="text-muted-foreground flex items-center gap-2.5 font-mono text-[10.5px] tracking-[0.18em] uppercase">
                    {/* Faux window dots — gives the code block a familiar
                      "editor window" feel without being toy-like. */}
                    <span
                      className="hidden items-center gap-1 sm:inline-flex"
                      aria-hidden="true"
                    >
                      <span className="bg-border/70 h-2 w-2 rounded-full" />
                      <span className="bg-border/70 h-2 w-2 rounded-full" />
                      <span className="bg-border/70 h-2 w-2 rounded-full" />
                    </span>
                    <span className="border-accent/30 bg-accent-soft text-accent rounded border px-1.5 py-0.5 font-mono text-[10px] tracking-[0.14em]">
                      .ps1
                    </span>
                    <span className="hidden sm:inline">Output</span>
                    {isStreaming && (
                      <span className="text-accent inline-flex items-center gap-1.5 tracking-normal normal-case">
                        <span
                          className="h-1.5 w-1.5 animate-pulse rounded-full"
                          style={{ backgroundColor: "var(--brand-accent)" }}
                          aria-hidden="true"
                        />
                        {isAutoFixing
                          ? "Polishing automatically"
                          : "Streaming"}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={onCopy}
                      disabled={isStreaming || !output}
                      className="h-8 cursor-pointer gap-1.5 text-xs"
                    >
                      {copied ? (
                        <Check className="h-3.5 w-3.5 text-emerald-500" />
                      ) : (
                        <Copy className="h-3.5 w-3.5" />
                      )}
                      {copied ? "Copied" : "Copy"}
                    </Button>
                    <span
                      className="bg-border/60 mx-0.5 h-4 w-px"
                      aria-hidden="true"
                    />
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={onDownload}
                      disabled={isStreaming || !output}
                      className="h-8 cursor-pointer gap-1.5 text-xs"
                    >
                      <Download className="h-3.5 w-3.5" />
                      Download
                    </Button>
                  </div>
                </div>
                    <pre
                      ref={codeScrollRef}
                      onScroll={onCodeScroll}
                      className={cn(
                        "max-h-[640px] overflow-auto p-4 text-[12.5px] leading-relaxed",
                      )}
                    >
                      <code
                        ref={codeRef}
                        className="language-powershell font-mono"
                      >
                        {code}
                      </code>
                      {isStreaming && (
                        <span
                          className="bg-accent ml-0.5 inline-block h-[1.05em] w-[2px] translate-y-[2px] animate-pulse align-baseline"
                          aria-hidden="true"
                        />
                      )}
                    </pre>
                  </div>
                </div>

                {/* Inspector — slides in from the right on desktop, sits below on
                  mobile. The slide-in animation runs once on mount, after the
                  parent fade-in plays, so it feels like the panel "opens up". */}
                <aside
                  className="animate-in fade-in slide-in-from-right-4 duration-500 lg:w-[296px] lg:flex-shrink-0"
                  style={{ animationDelay: "120ms", animationFillMode: "both" }}
                >
                  <Inspector
                    isStreaming={isStreaming}
                    isAutoFixing={isAutoFixing}
                    endpointChecks={endpointChecks}
                    lintResult={lintResult}
                    onFix={onFixIssues}
                  />
                </aside>
              </div>

              {/* Refine — iterative follow-up. Each refinement counts toward
                the daily quota. */}
              {!isStreaming && !lintResult?.hardReject && (
                <div className="border-border/70 bg-card/60 mt-3 rounded-xl border p-4 backdrop-blur-sm">
                  <div className="text-muted-foreground mb-2.5 flex items-center gap-2 font-mono text-[10.5px] tracking-[0.18em] uppercase">
                    <span
                      className="bg-accent h-1.5 w-1.5 rounded-full"
                      aria-hidden="true"
                    />
                    Refine
                  </div>
                  <div className="flex flex-col gap-2 sm:flex-row">
                    <div className="focus-within:border-accent/60 focus-within:ring-accent/25 border-border/60 bg-background/70 flex flex-1 items-center gap-2 rounded-md border px-3 transition-colors focus-within:ring-[3px]">
                      <SendHorizontal
                        className="text-muted-foreground/60 h-3.5 w-3.5 flex-shrink-0"
                        aria-hidden="true"
                      />
                      <input
                        type="text"
                        value={refinement}
                        onChange={(e) => setRefinement(e.target.value)}
                        onKeyDown={(e) => {
                          if (
                            e.key === "Enter" &&
                            !e.shiftKey &&
                            refinement.trim()
                          ) {
                            e.preventDefault();
                            void onRefine();
                          }
                        }}
                        placeholder="e.g. Also export to CSV. Or: switch to Managed Identity auth."
                        maxLength={1500}
                        className="text-foreground placeholder:text-muted-foreground/60 h-10 flex-1 bg-transparent text-[13.5px] focus:outline-none"
                      />
                    </div>
                    <Button
                      variant="outline"
                      onClick={() => void onRefine()}
                      disabled={!refinement.trim() || isStreaming}
                      className="border-border/70 hover:border-accent/50 hover:bg-accent-soft h-10 cursor-pointer gap-1.5"
                    >
                      <SendHorizontal
                        className="h-3.5 w-3.5"
                        aria-hidden="true"
                      />
                      Refine
                    </Button>
                  </div>
                  <div className="text-muted-foreground mt-2.5 text-[11.5px] leading-relaxed">
                    Describe a change and we&apos;ll update the script. Each
                    refinement counts as one generation. Press{" "}
                    <kbd className="border-border/60 bg-background/70 text-muted-foreground rounded border px-1 py-px font-mono text-[10px]">
                      Enter
                    </kbd>{" "}
                    to send.
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Inline credit */}
          <div className="border-border/40 mt-16 flex flex-wrap items-center justify-between gap-3 border-t pt-6 text-[12px] leading-relaxed">
            <p className="text-muted-foreground">
              Powered by{" "}
              <span className="text-foreground font-medium">
                Claude Haiku 4.5
              </span>
              . Free for everyone — please use responsibly so it stays free.
            </p>
            <span className="border-border/60 text-muted-foreground inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 font-mono text-[10px] tracking-[0.14em] uppercase">
              <span
                className="bg-accent h-1.5 w-1.5 rounded-full"
                aria-hidden="true"
              />
              No prompt storage
            </span>
          </div>

          {/* SEO footer — server-rendered features grid, quick-facts table, FAQ,
            and internal links. Lives in the initial HTML for crawlers. */}
          {seoFooter}
        </div>

        <Footer />
      </div>
      <GeneratorScriptDetail />
    </ScriptsProvider>
  );
}

// Mounts the script detail modal when a user selects a script from the search
// dialog while on the generator page. Without this consumer, the provider
// flips `isDetailOpen` but nothing renders.
function GeneratorScriptDetail() {
  const {
    selectedScript,
    setSelectedScript,
    isDetailOpen,
    setIsDetailOpen,
    updateScriptStats,
  } = useScripts();

  if (!selectedScript || !isDetailOpen) return null;

  return (
    <ScriptDetail
      script={selectedScript}
      updateScriptStats={updateScriptStats}
      onClose={() => {
        setIsDetailOpen(false);
        setSelectedScript(null);
        window.history.pushState(null, "", "/generator/");
      }}
    />
  );
}

function formatResetIn(resetMs: number, nowMs: number): string {
  const diff = Math.max(0, resetMs - nowMs);
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return "less than a minute";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remMin = minutes % 60;
  if (hours < 24) return remMin ? `${hours}h ${remMin}m` : `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d`;
}

function extractPowerShellCode(text: string): string | null {
  // Match the opening fence followed by everything up to the LAST closing
  // fence in the string. Greedy match prevents premature termination if the
  // script body happens to contain an embedded ``` triple (e.g. inside a
  // here-string or comment).
  const closed = text.match(/```(?:powershell|ps1)?\n?([\s\S]*)```/);
  if (closed?.[1]) return closed[1].trimEnd();
  // Still streaming — no closing fence yet. Return everything after the
  // opening fence.
  const open = text.match(/```(?:powershell|ps1)?\n?([\s\S]*)$/);
  if (open?.[1]) return open[1].trimEnd();
  return null;
}

function extractTitle(code: string): string | null {
  const match = code.match(/\.TITLE\s*\n\s*(.+)/);
  return match?.[1]?.trim() ?? null;
}
