"use client";

import "prismjs/themes/prism-tomorrow.css";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import Script from "next/script";
import {
  AlertTriangle,
  Check,
  Copy,
  Download,
  Loader2,
  Sparkles,
  ShieldCheck,
  SendHorizontal,
  Wand2,
} from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { Button } from "~/components/ui/button";
import { cn } from "~/lib/utils";
import { lintScript, type LintResult } from "~/lib/generator-lint";
import { LintPanel } from "./_components/lint-panel";

type Redaction = {
  kind: string;
  label: string;
  count: number;
};

type Props = {
  turnstileSiteKey: string | null;
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

export default function GeneratorClient({ turnstileSiteKey }: Props) {
  const [prompt, setPrompt] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [output, setOutput] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [redactions, setRedactions] = useState<Redaction[]>([]);
  const [copied, setCopied] = useState(false);
  const [lintResult, setLintResult] = useState<LintResult | null>(null);
  const [refinement, setRefinement] = useState("");
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [quota, setQuota] = useState<{
    remaining: number;
    limit: number;
    reset: number;
  } | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const turnstileContainerRef = useRef<HTMLDivElement | null>(null);
  const turnstileWidgetIdRef = useRef<string | null>(null);
  const codeRef = useRef<HTMLElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const outputRef = useRef<HTMLDivElement | null>(null);
  const didScrollForStreamRef = useRef(false);

  // Render Turnstile widget once the script loads.
  const renderTurnstile = useCallback(() => {
    if (!turnstileSiteKey) return;
    if (!turnstileContainerRef.current) return;
    if (!window.turnstile) return;
    if (turnstileWidgetIdRef.current) return;

    turnstileWidgetIdRef.current = window.turnstile.render(
      turnstileContainerRef.current,
      {
        sitekey: turnstileSiteKey,
        theme: "auto",
        callback: (token) => setTurnstileToken(token),
        "expired-callback": () => setTurnstileToken(null),
        "error-callback": () => setTurnstileToken(null),
      },
    );
  }, [turnstileSiteKey]);

  // If the script loaded before the container mounted, try again on mount.
  useEffect(() => {
    if (turnstileSiteKey && window.turnstile) {
      renderTurnstile();
    }
  }, [turnstileSiteKey, renderTurnstile]);

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

  // Highlight the final output once streaming finishes, and run the lint pass.
  useEffect(() => {
    if (isStreaming || !output || !codeRef.current) return;

    const extracted = extractPowerShellCode(output) ?? output;
    setLintResult(lintScript(extracted));

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
      limit: prev?.limit ?? 5,
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
        setError(
          err instanceof Error ? err.message : "Something went wrong.",
        );
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

  const onFixIssues = useCallback(async () => {
    if (!lintResult || lintResult.failCount + lintResult.warnCount === 0) return;
    const currentScript = extractPowerShellCode(output) ?? output;
    if (!currentScript) return;

    setError(null);
    setIsStreaming(true);
    setLintResult(null);
    setCopied(false);

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const res = await fetch("/api/generator/fix", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          originalPrompt: prompt,
          currentScript,
          findings: lintResult.findings,
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
  }, [lintResult, output, prompt, turnstileToken, absorbQuotaHeaders]);

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

      <div className="container mx-auto max-w-4xl px-4 py-10 sm:py-16">
        {/* Header */}
        <div className="mb-10">
          <div className="text-muted-foreground mb-3 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
            <Sparkles className="h-3 w-3" />
            Script Generator
            <span className="border-accent/40 text-accent rounded border px-1.5 py-0.5 text-[10px] tracking-normal normal-case">
              Beta
            </span>
          </div>
          <h1 className="mb-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            Describe what you need.
            <br />
            <span className="text-muted-foreground">
              We&apos;ll write the PowerShell.
            </span>
          </h1>
          <p className="text-muted-foreground max-w-2xl text-[15px] leading-relaxed">
            Production-quality Intune scripts generated from plain English.
            Free, no sign-in. Your prompt is sent to Anthropic for processing
            and is never stored on our servers.
          </p>
        </div>

        {/* Form */}
        <form onSubmit={onSubmit} className="space-y-5">
          {/* Security notice */}
          <div className="border-accent/30 bg-accent/5 flex gap-3 rounded-md border p-3 text-sm">
            <ShieldCheck className="text-accent mt-0.5 h-4 w-4 flex-shrink-0" />
            <div>
              <div className="font-medium">
                Don&apos;t paste secrets, credentials, or tenant IDs.
              </div>
              <div className="text-muted-foreground mt-0.5 text-[13px]">
                We scrub obvious patterns (GUIDs, tokens, keys, emails) before
                sending — but you&apos;re the first line of defense.
              </div>
            </div>
          </div>

          {/* Prompt */}
          <div>
            <label
              htmlFor="prompt"
              className="text-foreground mb-2 block text-sm font-medium"
            >
              What should the script do?
            </label>
            <textarea
              id="prompt"
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              placeholder="e.g. List all Intune-enrolled devices that haven't checked in for 60 days and export the results to CSV."
              rows={5}
              maxLength={MAX_PROMPT_LENGTH}
              className="border-border/70 bg-card text-foreground placeholder:text-muted-foreground/70 focus:border-accent/50 focus:ring-accent/30 w-full resize-y rounded-md border px-3 py-2.5 text-[14px] leading-relaxed focus:ring-1 focus:outline-none"
            />
            <div className="text-muted-foreground mt-1.5 flex items-center justify-between text-[11px]">
              <span>
                {prompt.length} / {MAX_PROMPT_LENGTH}
              </span>
              <button
                type="button"
                className="hover:text-foreground cursor-pointer transition-colors disabled:cursor-not-allowed disabled:opacity-50"
                onClick={() => setPrompt("")}
                disabled={!prompt}
              >
                Clear
              </button>
            </div>
          </div>

          {/* Examples */}
          <div>
            <div className="text-muted-foreground mb-2 font-mono text-[11px] tracking-[0.14em] uppercase">
              Try
            </div>
            <div className="flex flex-wrap gap-2">
              {EXAMPLE_PROMPTS.map((example) => (
                <button
                  key={example}
                  type="button"
                  onClick={() => setPrompt(example)}
                  className="border-border/70 hover:border-accent/40 hover:bg-card text-muted-foreground hover:text-foreground cursor-pointer rounded-md border px-2.5 py-1 text-[12px] transition-colors"
                >
                  {example.length > 60
                    ? example.slice(0, 60) + "…"
                    : example}
                </button>
              ))}
            </div>
          </div>

          {/* Turnstile widget */}
          {turnstileSiteKey && (
            <div ref={turnstileContainerRef} className="min-h-[65px]" />
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
              I am solely responsible for reviewing, testing, and running it in
              my environment. I accept the{" "}
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
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
            <Button
              type="submit"
              disabled={!canGenerate || quota?.remaining === 0}
              className="bg-accent text-accent-foreground hover:bg-accent/90 inline-flex cursor-pointer items-center gap-2"
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
                onClick={onCancel}
                className="border-border/70 cursor-pointer"
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
            {quota && (
              <p
                className={cn(
                  "text-[12px]",
                  quota.remaining === 0
                    ? "text-destructive"
                    : quota.remaining <= 1
                      ? "text-amber-500"
                      : "text-muted-foreground",
                )}
              >
                {quota.remaining === 0
                  ? `Daily limit reached. Resets in ${formatResetIn(quota.reset, now)}.`
                  : `${quota.remaining} of ${quota.limit} generation${
                      quota.limit === 1 ? "" : "s"
                    } left today · resets in ${formatResetIn(quota.reset, now)}`}
              </p>
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
          <div ref={outputRef} className="mt-8 scroll-mt-24">
            <div className="mb-3 flex gap-2 rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-[13px]">
              <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0 text-amber-500" />
              <span className="text-muted-foreground">
                <span className="text-foreground font-medium">
                  AI-generated.
                </span>{" "}
                Review and test before running in production. Verify all
                Microsoft Graph permissions and commands are correct.
              </span>
            </div>

            <div className="border-border/70 bg-card overflow-hidden rounded-md border">
              <div className="border-border/70 flex items-center justify-between border-b px-3 py-2">
                <div className="text-muted-foreground font-mono text-[10px] tracking-[0.16em] uppercase">
                  Output {isStreaming && "· streaming"}
                </div>
                <div className="flex gap-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={onCopy}
                    disabled={isStreaming || !output}
                    className="h-7 cursor-pointer gap-1.5 text-xs"
                  >
                    {copied ? (
                      <Check className="h-3 w-3" />
                    ) : (
                      <Copy className="h-3 w-3" />
                    )}
                    {copied ? "Copied" : "Copy"}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={onDownload}
                    disabled={isStreaming || !output}
                    className="h-7 cursor-pointer gap-1.5 text-xs"
                  >
                    <Download className="h-3 w-3" />
                    Download .ps1
                  </Button>
                </div>
              </div>
              <pre
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
              </pre>
            </div>

            {lintResult && !isStreaming && (
              <LintPanel
                result={lintResult}
                onFix={onFixIssues}
                fixDisabled={isStreaming}
              />
            )}

            {/* Refine — iterative follow-up. Each refinement counts toward
                the daily quota. */}
            {!isStreaming && !lintResult?.hardReject && (
              <div className="border-border/70 mt-3 rounded-md border p-3">
                <div className="text-muted-foreground mb-2 font-mono text-[10px] tracking-[0.16em] uppercase">
                  Refine
                </div>
                <div className="flex gap-2">
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
                    placeholder="e.g. Also export to CSV. Or: switch authentication to Managed Identity only."
                    maxLength={1500}
                    className="border-border/70 bg-background text-foreground placeholder:text-muted-foreground/70 focus:border-accent/50 focus:ring-accent/30 flex-1 rounded-md border px-3 py-2 text-[13px] focus:ring-1 focus:outline-none"
                  />
                  <Button
                    onClick={() => void onRefine()}
                    disabled={!refinement.trim() || isStreaming}
                    className="bg-accent text-accent-foreground hover:bg-accent/90 cursor-pointer gap-1.5"
                  >
                    <SendHorizontal className="h-3.5 w-3.5" />
                    Refine
                  </Button>
                </div>
                <div className="text-muted-foreground mt-1.5 text-[11px]">
                  Describe a change; we&apos;ll update the script. Each
                  refinement counts as one generation.
                </div>
              </div>
            )}
          </div>
        )}

        {/* Inline credit */}
        <div className="border-border/70 text-muted-foreground mt-12 border-t pt-6 text-[12px]">
          <p>
            Powered by Claude Haiku 4.5. Free for everyone — please use
            responsibly so it stays free.
          </p>
        </div>
      </div>

      <Footer />
    </div>
    </ScriptsProvider>
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
  const match = text.match(/```(?:powershell|ps1)?\n?([\s\S]*?)```/);
  if (match?.[1]) return match[1].trimEnd();
  const open = text.match(/```(?:powershell|ps1)?\n?([\s\S]*)$/);
  if (open?.[1]) return open[1].trimEnd();
  return null;
}

function extractTitle(code: string): string | null {
  const match = code.match(/\.TITLE\s*\n\s*(.+)/);
  return match?.[1]?.trim() ?? null;
}
