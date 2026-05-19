import type { Metadata } from "next";
import Link from "next/link";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Lock,
  ShieldCheck,
  Sparkles,
  Wand2,
  Zap,
} from "lucide-react";
import GeneratorClient from "./page-client";
import { env } from "~/env";
import {
  BreadcrumbSchema,
  FAQSchema,
  GeneratorHowToSchema,
  WebApplicationSchema,
} from "~/components/structured-data";

const BASE_URL = "https://intuneautomation.com";
const PAGE_URL = `${BASE_URL}/generator/`;

const PAGE_TITLE = "AI Intune PowerShell Script Generator";
const PAGE_DESCRIPTION =
  "Free AI-powered PowerShell script generator for Microsoft Intune and Microsoft Graph. Describe what you need in plain English and get a production-ready script in seconds. No sign-in. Prompts are not stored.";

export const metadata: Metadata = {
  title: PAGE_TITLE,
  description: PAGE_DESCRIPTION,
  keywords: [
    "Intune PowerShell script generator",
    "AI Intune script generator",
    "Microsoft Graph script generator",
    "free Intune automation scripts",
    "generate Intune detection script",
    "AI PowerShell generator",
    "Intune Graph API generator",
    "PowerShell AI tool",
  ],
  alternates: { canonical: "/generator/" },
  openGraph: {
    title: PAGE_TITLE,
    description: PAGE_DESCRIPTION,
    url: PAGE_URL,
    siteName: "IntuneAutomation",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og/generator-og.png",
        width: 1200,
        height: 630,
        alt: "AI Intune PowerShell Script Generator — IntuneAutomation",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: PAGE_TITLE,
    description: PAGE_DESCRIPTION,
    creator: "@intuneautomation",
    images: ["/og/generator-og.png"],
  },
};

// FAQ content — visible on page AND mirrored 1:1 in FAQPage JSON-LD so AI
// engines (Perplexity, ChatGPT, Gemini) can cite the answers and Google can
// surface them as rich results. Keep answers self-contained and authoritative.
const GENERATOR_FAQS = [
  {
    question: "What is the IntuneAutomation Script Generator?",
    answer:
      "The IntuneAutomation Script Generator is a free, browser-based AI tool that turns plain-English requests into production-ready PowerShell scripts for Microsoft Intune and Microsoft Graph. It runs entirely in your browser, requires no sign-in or installation, and is designed specifically for endpoint administrators who want to automate Intune tasks without writing the boilerplate by hand.",
  },
  {
    question: "Is the Intune script generator free?",
    answer:
      "Yes. The generator is free for everyone, with no sign-in required. To keep the service sustainable for the community, generation is rate-limited to 20 generations per IP per day. Refinements and lint-fix passes count toward the same daily quota.",
  },
  {
    question: "Which AI model powers the script generator?",
    answer:
      "The generator is powered by Anthropic's Claude Haiku 4.5. Haiku 4.5 is fast, code-aware, and tuned for structured output, which makes it well-suited for generating PowerShell that follows IntuneAutomation conventions including comment-based help, parameter validation, and explicit Microsoft Graph permission scopes.",
  },
  {
    question: "Are my prompts stored or used to train AI models?",
    answer:
      "No. Prompts are sent to Anthropic for processing and are not stored on our servers. Anthropic does not use API inputs or outputs to train its models by default. Before your prompt leaves the browser the generator scrubs obvious sensitive patterns including GUIDs, tokens, API keys, and email addresses, but you should still avoid pasting real credentials, tenant IDs, or production data.",
  },
  {
    question: "What kinds of Intune tasks can it generate scripts for?",
    answer:
      "The generator targets Microsoft Intune, Microsoft Graph, and Windows or macOS device management. Common use cases include device inventory and stale-device reports, compliance and configuration policy reporting, app deployment and failure summaries, Conditional Access auditing, BitLocker and security baseline detection scripts, Autopilot diagnostics, and remediation scripts for Intune Endpoint Analytics. Requests outside this scope are rejected.",
  },
  {
    question:
      "How does this compare to writing Intune scripts with general-purpose ChatGPT?",
    answer:
      "Unlike a general-purpose chat tool, the IntuneAutomation Script Generator is purpose-built for Microsoft Intune. It enforces a system prompt focused on Intune and Microsoft Graph, runs a PSScriptAnalyzer-style lint pass on every result with one-click fix-ups, redacts secrets before sending the prompt, and outputs scripts that follow the same comment-based help conventions used by the 120+ open-source scripts in the IntuneAutomation library.",
  },
  {
    question: "Can I refine the generated script?",
    answer:
      "Yes. After generation, use the inline Refine box to ask for changes — for example, switch to Managed Identity authentication, add CSV export, or adjust the Graph permissions. Each refinement counts as one generation against your daily quota. You can also click Fix issues to auto-resolve any lint warnings the generator detects.",
  },
];

const QUICK_FACTS: Array<[string, string]> = [
  ["Price", "Free"],
  ["Sign-in required", "No"],
  ["Daily limit", "20 generations per IP"],
  ["AI model", "Claude Haiku 4.5 (Anthropic)"],
  ["Output format", "PowerShell (.ps1)"],
  ["Prompt storage", "None — not stored on our servers"],
  ["Secret redaction", "Automatic for GUIDs, tokens, API keys, and emails"],
  ["Targets", "Microsoft Intune, Microsoft Graph, Windows, macOS"],
  ["Lint pass", "Built-in, with one-click Fix issues"],
];

// Example use cases — server-rendered as a semantic <ul> for crawlers and
// AI engines. The interactive click-to-fill chips inside the client form use
// the same strings (kept in sync via EXAMPLE_PROMPTS in page-client.tsx).
const EXAMPLE_USE_CASES = [
  "List all stale Intune devices that haven't checked in for 90 days and export to CSV",
  "Detection script: check if BitLocker is enabled on the system drive",
  "Report all Conditional Access policies with their assignments and conditions",
  "Find apps with deployment failures in the last 7 days and email a summary",
  "Audit Intune compliance policy assignments and flag devices out of compliance",
  "Export all Autopilot device registrations with their group tag and assigned user",
  "Generate a remediation script that re-enrolls a Windows device when MDM sync fails",
  "List all macOS devices missing a required configuration profile",
];

const FEATURE_LIST = [
  "Plain-English prompt to PowerShell script",
  "Streaming output",
  "Built-in PSScriptAnalyzer-style lint pass",
  "One-click Fix issues",
  "Inline refinement loop",
  "Automatic secret redaction (GUIDs, tokens, keys, emails)",
  "No sign-in required",
  "Free with daily quota",
  "Powered by Claude Haiku 4.5",
];

// Quality checks displayed in the inspector panel. Kept in sync with the
// lint rules in src/lib/generator-lint.ts. Server-rendered as crawlable
// reference content so anyone (or any bot) can read what's actually being
// verified, including the Security vs Safety distinction.
const QUALITY_CHECKS: Array<{
  name: string;
  summary: string;
  examples: string[];
  icon: typeof CheckCircle2;
}> = [
  {
    name: "Metadata",
    icon: CheckCircle2,
    summary:
      "The comment-based help block at the top of every script must be complete and tagged correctly.",
    examples: [
      "All 12 required fields present: .TITLE, .SYNOPSIS, .DESCRIPTION, .TAGS, .PLATFORM, .PERMISSIONS, .AUTHOR, .VERSION, .CHANGELOG, .LASTUPDATE, .EXAMPLE, .NOTES",
      ".AUTHOR is tagged AI Generated (IntuneAutomation.com) — never an impersonated person",
      ".LASTUPDATE is set to today's date in YYYY-MM-DD format",
    ],
  },
  {
    name: "Permissions",
    icon: Lock,
    summary:
      "Every Microsoft Graph permission scope declared in .PERMISSIONS must be a real scope, not invented.",
    examples: [
      "Each scope is matched against the official Microsoft Graph permission list (~700 scopes refreshed weekly from merill/msgraph)",
      "Unknown or misspelled scopes are flagged — common cause of Connect-MgGraph failures at runtime",
    ],
  },
  {
    name: "Security",
    icon: ShieldCheck,
    summary:
      "Detects code-injection and credential-leak risks in the script body.",
    examples: [
      "No Invoke-Expression or iex on user-controlled input",
      "No hardcoded passwords, API keys, tokens, or connection strings",
      "No -ExecutionPolicy Bypass without a reason",
      "No hardcoded non-Microsoft external URLs (webhook URLs must be parameters)",
    ],
  },
  {
    name: "Correctness",
    icon: Wand2,
    summary:
      "Catches logic bugs that pass syntax check but fail at runtime against a real Graph tenant.",
    examples: [
      "Null-unsafe [DateTime]::Parse on Graph date fields like lastSyncDateTime — Parse throws on null, a post-assignment null check is dead code",
      "Cmdlet confusions: Get-SecureBootUEFI used as a boolean, Get-Tpm used for BitLocker status",
      "Connect-MgGraph -Identity used without an Azure Automation detection branch (interactive runs fail)",
      "Every https://graph.microsoft.com/... URI is matched against the published Graph endpoint catalog (6,300+ endpoints)",
      "All Graph URIs must use the /beta path, never /v1.0 — the beta surface exposes the full Intune device-management API",
    ],
  },
  {
    name: "Safety",
    icon: AlertTriangle,
    summary:
      "Guards on destructive bulk operations. Different from Security — Safety is about protecting the tenant from accidental mass changes, not about code-level vulnerabilities.",
    examples: [
      "Any call to /retire, /wipe, /delete, /reset must run inside a script declared with [CmdletBinding(SupportsShouldProcess=$true)]",
      "SupportsShouldProcess gives the admin -WhatIf for safe-preview and -Confirm for explicit approval",
      "Without it, a single fat-finger run can wipe hundreds of devices with no undo",
    ],
  },
  {
    name: "Graph endpoints",
    icon: ShieldCheck,
    summary:
      "Each Microsoft Graph URI literal in the script is checked against the full published endpoint catalog in real time as the script streams in.",
    examples: [
      "Unknown endpoints are flagged with up to 3 closest known matches as candidate replacements",
      "Catches model hallucinations — invented paths that look plausible but don't exist",
      "Skipped when the URI contains PowerShell variable interpolation in the path (final URI not knowable statically)",
    ],
  },
];

export default function GeneratorPage() {
  return (
    <>
      <WebApplicationSchema
        baseUrl={BASE_URL}
        url={PAGE_URL}
        name="IntuneAutomation Script Generator"
        description={PAGE_DESCRIPTION}
        featureList={FEATURE_LIST}
      />
      <BreadcrumbSchema
        baseUrl={BASE_URL}
        items={[
          { name: "Home", url: "/" },
          { name: "Script Generator", url: "/generator/" },
        ]}
      />
      <FAQSchema faqs={GENERATOR_FAQS} />
      <GeneratorHowToSchema baseUrl={BASE_URL} />

      <GeneratorClient
        turnstileSiteKey={env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? null}
        seoContent={<GeneratorSeoContent />}
        seoFooter={<GeneratorSeoFooter />}
      />
    </>
  );
}

// Server-rendered SEO content. Renders inside the client wrapper so the static
// surface is delivered in the initial HTML — visible to GPTBot, ClaudeBot,
// PerplexityBot, Bingbot, and any crawler that doesn't execute JavaScript.
function GeneratorSeoContent() {
  return (
    <header className="mb-10 sm:mb-12">
      <div className="text-muted-foreground mb-5 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
        <Sparkles className="text-accent h-3 w-3" aria-hidden="true" />
        Script Generator
        <span className="bg-accent-soft text-accent rounded-sm px-1.5 py-0.5 text-[10px] font-medium tracking-normal normal-case">
          Beta
        </span>
      </div>
      <h1 className="font-display mb-5 text-[28px] leading-[1.1] tracking-tight sm:text-[44px]">
        AI Intune PowerShell Script Generator
      </h1>
      <p className="text-foreground mb-4 max-w-2xl text-[16px] leading-relaxed sm:text-[17px]">
        Describe what you need.{" "}
        <span className="text-muted-foreground">
          We&apos;ll write the PowerShell.
        </span>
      </p>
      <p className="text-muted-foreground max-w-2xl text-[14.5px] leading-relaxed sm:text-[15px]">
        The IntuneAutomation Script Generator is a free, browser-based AI tool
        that turns plain-English requests into production-ready PowerShell
        scripts for Microsoft Intune and Microsoft Graph. No sign-in and no
        installation required. Your prompt is sent to Anthropic for processing
        and is never stored on our servers.
      </p>
    </header>
  );
}

// Server-rendered SEO footer: features grid, quick-facts table, FAQ, internal
// links. Mirrors the FAQ JSON-LD schema 1:1 so Google rich results align with
// visible content. Lives below the generator UI.
function GeneratorSeoFooter() {
  return (
    <section
      className="mt-20 space-y-16"
      aria-label="About the script generator"
    >
      {/* Features */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <Zap className="text-accent h-3 w-3" aria-hidden="true" />
          What it does
        </div>
        <h2 className="font-display mb-3 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          Built specifically for Microsoft Intune
        </h2>
        <p className="text-muted-foreground mb-6 max-w-2xl text-[14.5px] leading-relaxed sm:text-[15px]">
          Unlike general-purpose AI chat tools, the IntuneAutomation Script
          Generator is purpose-built for Microsoft Intune and Microsoft Graph.
          It enforces an Intune-focused system prompt, runs a
          PSScriptAnalyzer-style lint pass on every result with one-click
          fix-ups, redacts secrets before sending the prompt, and produces
          scripts that follow the same comment-based help conventions used by
          the 120+ open-source scripts in the IntuneAutomation library.
        </p>
        <ul className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          {FEATURE_LIST.map((feature) => (
            <li
              key={feature}
              className="text-foreground/90 flex items-start gap-2.5 text-[14px] leading-relaxed"
            >
              <CheckCircle2
                className="text-accent mt-[3px] h-3.5 w-3.5 flex-shrink-0"
                aria-hidden="true"
              />
              <span>{feature}</span>
            </li>
          ))}
        </ul>
      </div>

      {/* Quick facts */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <Lock className="text-accent h-3 w-3" aria-hidden="true" />
          Quick facts
        </div>
        <h2 className="font-display mb-5 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          Generator at a glance
        </h2>
        <div className="border-border/70 bg-card/60 overflow-hidden rounded-xl border backdrop-blur-sm">
          <table className="w-full text-left text-[14px]">
            <caption className="sr-only">
              Key facts about the IntuneAutomation Script Generator
            </caption>
            <tbody>
              {QUICK_FACTS.map(([key, value], idx) => (
                <tr
                  key={key}
                  className={
                    idx !== QUICK_FACTS.length - 1
                      ? "border-border/40 border-b"
                      : undefined
                  }
                >
                  <th
                    scope="row"
                    className="text-muted-foreground w-[44%] px-4 py-3 align-top font-mono text-[12px] font-normal tracking-[0.06em] uppercase sm:w-[36%]"
                  >
                    {key}
                  </th>
                  <td className="text-foreground px-4 py-3 leading-relaxed">
                    {value}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* How it works */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <Wand2 className="text-accent h-3 w-3" aria-hidden="true" />
          How it works
        </div>
        <h2 className="font-display mb-5 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          Three steps from prompt to .ps1
        </h2>
        <ol className="space-y-5">
          {[
            {
              title: "Describe the task in plain English",
              body: "Type what you want the script to do — for example, list all stale Intune devices that haven't checked in for 90 days and export to CSV.",
            },
            {
              title: "Generate the script",
              body: "The generator streams a production-ready PowerShell script that uses the Microsoft Graph PowerShell SDK and includes comment-based help and the required Graph permission scopes.",
            },
            {
              title: "Review, refine, and run",
              body: "Read the script, optionally use the inline Refine box to ask for changes (for example, switch to Managed Identity authentication), then copy or download the .ps1 file and run it locally with Connect-MgGraph or deploy it to Azure Automation.",
            },
          ].map((step, idx) => (
            <li
              key={step.title}
              className="border-border/60 bg-card/40 flex gap-4 rounded-lg border p-4 backdrop-blur-sm"
            >
              <span
                className="bg-accent-soft text-accent border-accent/30 flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full border font-mono text-[12px] font-medium"
                aria-hidden="true"
              >
                {idx + 1}
              </span>
              <div>
                <h3 className="text-foreground mb-1 text-[15px] leading-tight font-medium">
                  {step.title}
                </h3>
                <p className="text-muted-foreground text-[14px] leading-relaxed">
                  {step.body}
                </p>
              </div>
            </li>
          ))}
        </ol>
      </div>

      {/* Quality checks — explains what every category in the inspector
          panel actually verifies. Server-rendered so the explanation is
          crawlable and a stable on-page reference for Security vs Safety.
          The id is the scroll target for the Inspector "?" button. */}
      <div id="quality-checks" className="scroll-mt-24">
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <ShieldCheck className="text-accent h-3 w-3" aria-hidden="true" />
          Quality checks
        </div>
        <h2 className="font-display mb-3 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          What we verify in every script
        </h2>
        <p className="text-muted-foreground mb-5 max-w-2xl text-[14.5px] leading-relaxed sm:text-[15px]">
          Every generated script runs through six independent checks. The
          inspector panel on the right of the output streams these in real
          time during generation. Any warning or failure triggers an automatic
          fix pass at no quota cost.
        </p>
        <ul className="border-border/70 bg-card/40 divide-border/50 divide-y rounded-xl border backdrop-blur-sm">
          {QUALITY_CHECKS.map((check) => (
            <li key={check.name} className="flex gap-4 p-5">
              <div className="bg-accent-soft text-accent border-accent/30 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-md border">
                <check.icon className="h-4 w-4" aria-hidden="true" />
              </div>
              <div className="min-w-0 flex-1">
                <h3 className="text-foreground mb-1 text-[15px] leading-tight font-medium">
                  {check.name}
                </h3>
                <p className="text-muted-foreground mb-2 text-[14px] leading-relaxed">
                  {check.summary}
                </p>
                <ul className="text-muted-foreground/90 list-disc space-y-1 pl-4 text-[13px] leading-relaxed">
                  {check.examples.map((example) => (
                    <li key={example}>{example}</li>
                  ))}
                </ul>
              </div>
            </li>
          ))}
        </ul>
      </div>

      {/* Example use cases — server-rendered semantic <ul> for crawlers. The
          interactive click-to-fill chips inside the form use the same
          strings. */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <Sparkles className="text-accent h-3 w-3" aria-hidden="true" />
          Examples
        </div>
        <h2 className="font-display mb-3 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          What people generate
        </h2>
        <p className="text-muted-foreground mb-5 max-w-2xl text-[14.5px] leading-relaxed sm:text-[15px]">
          Real-world Intune automation prompts the generator handles well. Use
          one as a starting point or paste your own.
        </p>
        <ul className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          {EXAMPLE_USE_CASES.map((example) => (
            <li
              key={example}
              className="border-border/60 bg-card/40 text-foreground/90 flex items-start gap-2.5 rounded-md border p-3 text-[14px] leading-relaxed backdrop-blur-sm"
            >
              <ArrowRight
                className="text-accent mt-[3px] h-3.5 w-3.5 flex-shrink-0"
                aria-hidden="true"
              />
              <span>{example}</span>
            </li>
          ))}
        </ul>
      </div>

      {/* FAQ — visible content matches FAQPage JSON-LD 1:1. */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <Sparkles className="text-accent h-3 w-3" aria-hidden="true" />
          FAQ
        </div>
        <h2 className="font-display mb-5 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          Frequently asked questions
        </h2>
        <div className="border-border/70 bg-card/40 divide-border/50 divide-y rounded-xl border backdrop-blur-sm">
          {GENERATOR_FAQS.map((faq) => (
            <details
              key={faq.question}
              className="group p-5 [&[open]>summary>svg]:rotate-45"
            >
              <summary className="text-foreground flex cursor-pointer list-none items-start justify-between gap-4 text-[15px] leading-snug font-medium">
                {faq.question}
                <svg
                  className="text-muted-foreground mt-1 h-4 w-4 flex-shrink-0 transition-transform"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </summary>
              <p className="text-muted-foreground mt-3 text-[14px] leading-relaxed">
                {faq.answer}
              </p>
            </details>
          ))}
        </div>
      </div>

      {/* Related — internal linking equity to /scripts and /blog */}
      <div>
        <div className="text-muted-foreground mb-4 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.18em] uppercase">
          <ArrowRight className="text-accent h-3 w-3" aria-hidden="true" />
          Related
        </div>
        <h2 className="font-display mb-5 text-[24px] leading-[1.15] tracking-tight sm:text-[30px]">
          Looking for pre-built scripts?
        </h2>
        <p className="text-muted-foreground mb-5 max-w-2xl text-[14.5px] leading-relaxed sm:text-[15px]">
          The IntuneAutomation library includes 120+ open-source PowerShell
          scripts maintained by the community, each with one-click deployment to
          Azure Automation as a scheduled runbook. Browse the catalog or read
          the blog for guides and best practices.
        </p>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/scripts/"
            className="border-border/70 hover:border-accent/50 hover:bg-accent-soft text-foreground inline-flex h-10 items-center gap-2 rounded-md border px-4 text-[14px] font-medium transition-colors"
          >
            Browse the script library
            <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
          </Link>
          <Link
            href="/blog/"
            className="border-border/70 hover:border-accent/50 hover:bg-accent-soft text-foreground inline-flex h-10 items-center gap-2 rounded-md border px-4 text-[14px] font-medium transition-colors"
          >
            Read the blog
            <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
          </Link>
        </div>
      </div>
    </section>
  );
}
