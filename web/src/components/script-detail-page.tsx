"use client";

// ScriptDetailPage v4 — page-version of the script detail view.
// Editorial layout: mono kicker breadcrumb, display headline, hairline-bordered
// surfaces, single cyan accent. Azure-blue reserved exclusively for Deploy-to-Azure.
// Sections open with `// LABEL` kickers; the code block uses a dark mono surface with
// a v4 toolbar. Plain background (no atmosphere — that's landing-only). Every analytics
// call, download payload, deploy URL, and Prism highlight path is preserved verbatim
// from v1; only the visual chrome has changed.

import React, { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { type Script } from "~/lib/scripts";
import { useToast } from "~/hooks/use-toast";
import "prismjs/themes/prism-tomorrow.css";
import {
  AlertTriangle,
  Calendar,
  Check,
  CheckCircle,
  Cloud,
  Copy,
  Download,
  Eye,
  ExternalLink,
  Github,
  Key,
  Maximize2,
  Minimize2,
  Monitor,
  User,
  XCircle,
} from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { RelatedScripts } from "~/components/related-scripts";
import { QualityChecks } from "~/components/quality-checks";

interface ScriptDetailPageProps {
  script: Script;
  allScripts?: Script[];
  permissionsData?: Record<
    string,
    { displayName: string; description: string }
  >;
}

/* -------------------------- formatting helpers --------------------------- */

function formatCompactNumber(num: number): string {
  if (num >= 1_000_000) return (num / 1_000_000).toFixed(1) + "M";
  if (num >= 10_000) return (num / 1000).toFixed(1) + "k";
  if (num >= 1000) return (num / 1000).toFixed(1) + "k";
  return num.toString();
}

/* ------------------------- small v4 sub-primitives ----------------------- */

function SectionKicker({ label }: { label: string }) {
  return <p className="font-mono-label text-accent-hi">// {label}</p>;
}

function MonoTag({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="text-muted-foreground inline-flex items-center rounded-sm border px-2 py-0.5 font-mono text-[10.5px] tracking-[0.14em] uppercase"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      {children}
    </span>
  );
}

function HairlinePanel({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`bg-card/40 rounded-md border backdrop-blur-md ${className}`}
      style={{ borderColor: "var(--brand-rule)" }}
    >
      {children}
    </div>
  );
}

const testResultMeta: Record<
  "pass" | "fail" | "warning",
  { icon: typeof CheckCircle; label: string; color: string }
> = {
  pass: {
    icon: CheckCircle,
    label: "All tests passed",
    color: "var(--brand-accent-hi)",
  },
  fail: {
    icon: XCircle,
    label: "Tests failed",
    color: "oklch(0.65 0.20 25)",
  },
  warning: {
    icon: AlertTriangle,
    label: "Warnings found",
    color: "var(--brand-warn)",
  },
};

export function ScriptDetailPage({
  script,
  allScripts,
  permissionsData,
}: ScriptDetailPageProps) {
  const [isDeployingToAzure, setIsDeployingToAzure] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [isHighlighted, setIsHighlighted] = useState(false);
  const [activeRemediationTab, setActiveRemediationTab] = useState<
    "detection" | "remediation"
  >("detection");
  const { toast } = useToast();
  const codeRef = useRef<HTMLPreElement>(null);
  const detectionCodeRef = useRef<HTMLPreElement>(null);
  const remediationCodeRef = useRef<HTMLPreElement>(null);
  const hasTrackedView = useRef(false);
  const primaryTag = script.tags[0];
  const fileExtension = script.githubPath?.endsWith(".sh") ? "sh" : "ps1";
  const githubUrl =
    script.githubUrl ||
    `https://github.com/ugurkocde/IntuneAutomation/blob/main/${script.githubPath || `scripts/${script.id}.${fileExtension}`}`;

  const isRemediation =
    script.scriptType === "remediation" && !!script.remediationPair;
  const isNotification =
    script.execution === "RunbookOnly" ||
    script.category === "notification" ||
    script.tags.includes("Notification");

  const kicker = isRemediation
    ? "// REMEDIATION · DETECTION"
    : isNotification
      ? "// NOTIFICATION · RUNBOOK"
      : primaryTag
        ? `// ${primaryTag.toUpperCase()}`
        : "// SCRIPT";

  const kickerColor = isNotification
    ? "var(--brand-azure)"
    : "var(--brand-accent-hi)";

  const breadcrumbDir = primaryTag ? primaryTag.toLowerCase() : "scripts";
  const breadcrumbFile = `${script.id || "script"}.${fileExtension}`;

  const handleDownload = async () => {
    // Track download analytics
    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? sessionStorage.getItem("session_id") || undefined
        : undefined;

    AnalyticsService.trackScriptDownload(script.id, script.title, "raw", {
      userAgent,
      sessionId,
    }).catch((error) => {
      console.error("Failed to track download:", error);
    });

    try {
      // If it's a remediation script, download both scripts
      if (script.scriptType === "remediation" && script.remediationPair) {
        // Download detection script
        const detectionBlob = new Blob(
          [script.remediationPair.detection.code],
          { type: "text/plain" },
        );
        const detectionUrl = URL.createObjectURL(detectionBlob);
        const detectionLink = document.createElement("a");
        detectionLink.href = detectionUrl;
        const detectionExt =
          script.remediationPair.detection.githubPath?.endsWith(".sh")
            ? "sh"
            : "ps1";
        detectionLink.download = `${script.remediationPair.detection.id}.${detectionExt}`;

        // Download remediation script
        const remediationBlob = new Blob(
          [script.remediationPair.remediation.code],
          { type: "text/plain" },
        );
        const remediationUrl = URL.createObjectURL(remediationBlob);
        const remediationLink = document.createElement("a");
        remediationLink.href = remediationUrl;
        const remediationExt =
          script.remediationPair.remediation.githubPath?.endsWith(".sh")
            ? "sh"
            : "ps1";
        remediationLink.download = `${script.remediationPair.remediation.id}.${remediationExt}`;

        // Trigger downloads with a small delay between them
        document.body.appendChild(detectionLink);
        detectionLink.click();
        document.body.removeChild(detectionLink);
        URL.revokeObjectURL(detectionUrl);

        // Small delay to ensure both downloads work
        setTimeout(() => {
          document.body.appendChild(remediationLink);
          remediationLink.click();
          document.body.removeChild(remediationLink);
          URL.revokeObjectURL(remediationUrl);
        }, 100);

        toast({
          title: "Downloads started!",
          description: "Downloading both detection and remediation scripts.",
        });
      } else {
        // Regular single script download
        const blob = new Blob([script.code], { type: "text/plain" });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        const fileExtension = script.githubPath?.endsWith(".sh") ? "sh" : "ps1";
        a.download = `${script.id || script.title.replace(/\s+/g, "_")}.${fileExtension}`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);

        toast({
          title: "Download started!",
          description: "The script is being downloaded.",
        });
      }
    } catch (error) {
      console.error("Download failed:", error);
      // Fallback: open the GitHub URL in a new tab
      window.open(githubUrl, "_blank");
    }
  };

  const handleDeployToAzure = async () => {
    setIsDeployingToAzure(true);

    try {
      // Fetch the pre-generated Azure deployment templates registry
      const templatesResponse = await fetch(
        "https://raw.githubusercontent.com/ugurkocde/IntuneAutomation/main/azure-deployment-templates.json",
      );

      if (!templatesResponse.ok) {
        throw new Error("Failed to fetch Azure deployment templates");
      }

      const templatesRegistry = await templatesResponse.json();
      const templateInfo = templatesRegistry.templates[script.id];

      if (!templateInfo) {
        throw new Error("Azure deployment template not found for this script");
      }

      // Open Azure portal with the pre-generated deployment URL
      window.open(templateInfo.deployUrl, "_blank");

      toast({
        title: "Deploying to Azure!",
        description:
          "Opening Azure portal to deploy the runbook. If the runbook appears empty after deployment, manually import the script from GitHub or use 'Browse gallery' > 'Browse' to import from the source URL.",
      });
    } catch (error) {
      toast({
        title: "Deployment failed",
        description:
          "Failed to load Azure deployment template. Please try again or download the script manually.",
        variant: "destructive",
      });
    } finally {
      setIsDeployingToAzure(false);
    }
  };

  const handleCopyScript = async () => {
    // Track copy as download
    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? sessionStorage.getItem("session_id") || undefined
        : undefined;

    AnalyticsService.trackScriptDownload(script.id, script.title, "copy", {
      userAgent,
      sessionId,
    }).catch((error) => {
      console.error("Failed to track copy:", error);
    });

    try {
      let codeToCopy = script.code;

      // If it's a remediation script, copy the active tab's code
      if (script.scriptType === "remediation" && script.remediationPair) {
        codeToCopy =
          activeRemediationTab === "detection"
            ? script.remediationPair.detection.code
            : script.remediationPair.remediation.code;
      }

      await navigator.clipboard.writeText(codeToCopy);
      setCopied(true);
      toast({
        title: "Script copied!",
        description: `The ${activeRemediationTab === "detection" ? "detection" : "remediation"} script has been copied to your clipboard.`,
      });
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
      toast({
        title: "Copy failed",
        description: "Failed to copy script to clipboard.",
        variant: "destructive",
      });
    }
  };

  const handleGithubView = () => {
    const userAgent =
      typeof window !== "undefined" ? navigator.userAgent : undefined;
    const sessionId =
      typeof window !== "undefined"
        ? sessionStorage.getItem("session_id") || undefined
        : undefined;
    AnalyticsService.trackScriptDownload(script.id, script.title, "github", {
      userAgent,
      sessionId,
    }).catch((error) => {
      console.error("Failed to track GitHub view:", error);
    });
  };

  const handleFullscreen = () => {
    setIsFullscreen(!isFullscreen);
  };

  // Track view when component mounts
  useEffect(() => {
    if (!hasTrackedView.current) {
      hasTrackedView.current = true;

      // Track analytics in the background
      const userAgent =
        typeof window !== "undefined" ? navigator.userAgent : undefined;
      const sessionId =
        typeof window !== "undefined"
          ? sessionStorage.getItem("session_id") || undefined
          : undefined;

      AnalyticsService.trackScriptView(script.id, script.title, {
        userAgent,
        sessionId,
      }).catch((error) => {
        // Silently fail - analytics shouldn't block user experience
        console.error("Failed to track view:", error);
      });
    }
  }, [script.id, script.title]);

  // Highlight code with Prism.js
  useEffect(() => {
    const highlightCode = async () => {
      if (isHighlighted) return;

      try {
        const Prism = await import("prismjs");

        // Import language components based on script type
        if (script.scriptType === "remediation" && script.remediationPair) {
          // Import languages for both scripts
          if (script.remediationPair.detection.githubPath?.endsWith(".sh")) {
            // @ts-ignore
            await import("prismjs/components/prism-bash");
          } else {
            // @ts-ignore
            await import("prismjs/components/prism-powershell");
          }

          // Highlight the active tab's code
          const activeRef =
            activeRemediationTab === "detection"
              ? detectionCodeRef
              : remediationCodeRef;
          if (activeRef.current) {
            Prism.highlightElement(activeRef.current);
          }
        } else {
          // Regular script
          if (script.githubPath?.endsWith(".sh")) {
            // @ts-ignore
            await import("prismjs/components/prism-bash");
          } else {
            // @ts-ignore
            await import("prismjs/components/prism-powershell");
          }

          if (codeRef.current) {
            Prism.highlightElement(codeRef.current);
          }
        }

        setIsHighlighted(true);
      } catch (error) {
        console.error("Failed to highlight code:", error);
      }
    };

    highlightCode();
  }, [isHighlighted, activeRemediationTab, script]);

  // Handle escape key for fullscreen
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isFullscreen) {
        setIsFullscreen(false);
      }
    };

    if (isFullscreen) {
      document.addEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "hidden";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "auto";
    };
  }, [isFullscreen]);

  /* ----------------------------- meta strip ---------------------------- */

  const metaParts: Array<{ key: string; node: React.ReactNode }> = [];
  if (script.usageStats && script.usageStats.totalViews > 0) {
    metaParts.push({
      key: "views",
      node: (
        <>
          <Eye className="h-3 w-3" aria-hidden="true" />
          <span>{formatCompactNumber(script.usageStats.totalViews)} views</span>
        </>
      ),
    });
  }
  if (script.usageStats && script.usageStats.totalDownloads > 0) {
    metaParts.push({
      key: "dl",
      node: (
        <>
          <Download className="h-3 w-3" aria-hidden="true" />
          <span>
            {formatCompactNumber(script.usageStats.totalDownloads)} downloads
          </span>
        </>
      ),
    });
  }
  if (script.version) {
    metaParts.push({
      key: "version",
      node: <span>Version {script.version}</span>,
    });
  }
  if (script.author) {
    metaParts.push({
      key: "author",
      node: (
        <>
          <User className="h-3 w-3" aria-hidden="true" />
          <span>By {script.author}</span>
        </>
      ),
    });
  }

  return (
    <ScriptsProvider>
      <div className="bg-background flex min-h-screen flex-col">
        <Navbar />
        <main className="flex-1 pt-20">
          <article className="container mx-auto max-w-5xl px-4 py-12 sm:py-16">
            {/* ───────────── Mono filesystem breadcrumb ───────────── */}
            <nav
              aria-label="Breadcrumb"
              className="text-muted-foreground font-mono text-[12px] leading-relaxed sm:text-[13px]"
            >
              <Link
                href="/"
                className="hover:text-foreground transition-colors"
              >
                ~
              </Link>
              <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
              <Link
                href="/scripts/"
                className="hover:text-foreground transition-colors"
              >
                intune-library
              </Link>
              <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
              {primaryTag ? (
                <>
                  <Link
                    href={`/scripts/${breadcrumbDir}/`}
                    className="hover:text-foreground transition-colors"
                  >
                    {breadcrumbDir}
                  </Link>
                  <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
                </>
              ) : null}
              <span className="text-foreground">{breadcrumbFile}</span>
            </nav>

            {/* ───────────── Header ───────────── */}
            <header className="mt-8">
              <p
                className="font-mono text-[11px] font-medium tracking-[0.18em] uppercase"
                style={{ color: kickerColor }}
                aria-hidden="true"
              >
                {kicker}
              </p>
              <h1 className="font-display text-foreground mt-4 text-[clamp(2rem,5vw,3.5rem)] leading-[1.05] tracking-[-0.025em]">
                {script.title}
              </h1>
              <p className="text-muted-foreground mt-5 max-w-3xl text-base leading-relaxed sm:text-lg">
                {script.description}
              </p>

              {script.tags.length > 0 && (
                <div className="mt-6 flex flex-wrap gap-1.5">
                  {script.tags.map((tag) => (
                    <MonoTag key={tag}>{tag}</MonoTag>
                  ))}
                </div>
              )}

              {metaParts.length > 0 && (
                <div
                  className="text-muted-foreground mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 border-t pt-5 font-mono text-[11px] tracking-[0.14em] uppercase"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  {metaParts.map((part, i) => (
                    <span
                      key={part.key}
                      className="inline-flex items-center gap-1.5"
                    >
                      {i > 0 && (
                        <span
                          aria-hidden="true"
                          className="text-muted-foreground/40 mr-2 -ml-3"
                        >
                          ·
                        </span>
                      )}
                      {part.node}
                    </span>
                  ))}
                </div>
              )}
            </header>

            {/* ───────────── Action row ───────────── */}
            <div
              className="bg-card/40 mt-8 flex flex-col gap-1 rounded-md border p-1 backdrop-blur-md sm:flex-row sm:items-stretch"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              {!script.githubPath?.endsWith(".sh") &&
                script.scriptType !== "remediation" && (
                  <>
                    <button
                      type="button"
                      onClick={handleDeployToAzure}
                      disabled={isDeployingToAzure}
                      className="focus-visible:ring-accent group focus-visible:ring-offset-background flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-sm px-4 py-3 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-azure)_8%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-60"
                      style={{ color: "var(--brand-azure)" }}
                    >
                      <Cloud
                        className={`h-4 w-4 ${isDeployingToAzure ? "animate-pulse" : ""}`}
                        aria-hidden="true"
                      />
                      <span>
                        {isDeployingToAzure
                          ? "Deploying to Azure…"
                          : "Deploy to Azure"}
                      </span>
                    </button>
                    <span
                      aria-hidden="true"
                      className="hidden w-px self-stretch sm:block"
                      style={{ backgroundColor: "var(--brand-rule)" }}
                    />
                  </>
                )}

              <button
                type="button"
                onClick={handleCopyScript}
                className="focus-visible:ring-accent group text-muted-foreground hover:text-foreground focus-visible:ring-offset-background flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-sm px-4 py-3 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_6%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                {copied ? (
                  <>
                    <Check
                      className="h-4 w-4"
                      strokeWidth={2.25}
                      style={{ color: "var(--brand-accent-hi)" }}
                      aria-hidden="true"
                    />
                    <span style={{ color: "var(--brand-accent-hi)" }}>
                      Copied
                    </span>
                  </>
                ) : (
                  <>
                    <Copy className="h-4 w-4" aria-hidden="true" />
                    <span>
                      {isRemediation
                        ? `Copy ${activeRemediationTab}`
                        : "Copy script"}
                    </span>
                  </>
                )}
              </button>

              <span
                aria-hidden="true"
                className="hidden w-px self-stretch sm:block"
                style={{ backgroundColor: "var(--brand-rule)" }}
              />

              <button
                type="button"
                onClick={handleDownload}
                className="focus-visible:ring-accent group text-muted-foreground hover:text-foreground focus-visible:ring-offset-background flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-sm px-4 py-3 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_6%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                <Download className="h-4 w-4" aria-hidden="true" />
                <span>
                  {script.scriptType === "remediation"
                    ? "Download both"
                    : "Download"}
                </span>
              </button>

              <span
                aria-hidden="true"
                className="hidden w-px self-stretch sm:block"
                style={{ backgroundColor: "var(--brand-rule)" }}
              />

              <a
                href={githubUrl}
                target="_blank"
                rel="noopener noreferrer"
                onClick={handleGithubView}
                className="focus-visible:ring-accent group text-muted-foreground hover:text-foreground focus-visible:ring-offset-background flex flex-1 items-center justify-center gap-2 rounded-sm px-4 py-3 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_6%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                <Github className="h-4 w-4" aria-hidden="true" />
                <span>View on GitHub</span>
                <ExternalLink
                  className="h-3 w-3 opacity-60"
                  aria-hidden="true"
                />
              </a>
            </div>

            {/* ───────────── Quality checks ───────────── */}
            {(script.tests || script.testResult) && (
              <section
                className="mt-12"
                aria-labelledby="quality-checks-heading"
              >
                <SectionKicker label="QUALITY CHECKS" />
                <h2
                  id="quality-checks-heading"
                  className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  Validation status
                </h2>
                <div className="mt-5">
                  {script.tests ? (
                    <QualityChecks tests={script.tests} />
                  ) : script.testResult ? (
                    (() => {
                      const meta =
                        testResultMeta[script.testResult.result] ||
                        testResultMeta.fail;
                      const Icon = meta.icon;
                      return (
                        <HairlinePanel className="p-4 sm:p-5">
                          <div className="flex flex-wrap items-center gap-3">
                            <span
                              className="inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.14em] uppercase"
                              style={{ color: meta.color }}
                            >
                              <Icon className="h-4 w-4" aria-hidden="true" />
                              {meta.label}
                            </span>
                            <span className="text-muted-foreground font-mono text-[11px] tracking-wide">
                              · tested {script.testResult.timestamp}
                            </span>
                          </div>
                        </HairlinePanel>
                      );
                    })()
                  ) : null}
                </div>
              </section>
            )}

            {/* ───────────── Required permissions ───────────── */}
            {script.permissions && script.permissions.length > 0 && (
              <section className="mt-12" aria-labelledby="permissions-heading">
                <SectionKicker label="REQUIRED PERMISSIONS" />
                <h2
                  id="permissions-heading"
                  className="font-display text-foreground mt-3 flex items-center gap-2 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  <Key
                    className="h-5 w-5 shrink-0"
                    style={{ color: "var(--brand-accent-hi)" }}
                    aria-hidden="true"
                  />
                  Microsoft Graph scopes
                </h2>
                <HairlinePanel className="mt-5 divide-y">
                  {script.permissions.map((permission) => {
                    const permissionInfo = permissionsData?.[permission];
                    return (
                      <div
                        key={permission}
                        className="px-5 py-4"
                        style={{ borderColor: "var(--brand-rule)" }}
                      >
                        <code
                          className="font-mono text-[12.5px] font-medium"
                          style={{ color: "var(--brand-accent-hi)" }}
                        >
                          {permission}
                        </code>
                        {permissionInfo?.description && (
                          <p className="text-muted-foreground mt-1.5 text-sm leading-relaxed">
                            {permissionInfo.description}
                          </p>
                        )}
                      </div>
                    );
                  })}
                </HairlinePanel>
              </section>
            )}

            {/* ───────────── Schedule (runbook) ───────────── */}
            {script.schedule && script.schedule !== "OnDemand" && (
              <section className="mt-12" aria-labelledby="schedule-heading">
                <SectionKicker label="SCHEDULE" />
                <h2
                  id="schedule-heading"
                  className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  Runs on a cadence
                </h2>
                <HairlinePanel className="mt-5 flex items-center gap-3 px-5 py-4">
                  <Calendar
                    className="h-4 w-4 shrink-0"
                    style={{ color: "var(--brand-azure)" }}
                    aria-hidden="true"
                  />
                  <span
                    className="font-mono text-[11px] tracking-[0.16em] uppercase"
                    style={{ color: "var(--brand-azure)" }}
                  >
                    {script.schedule}
                  </span>
                  <span className="text-muted-foreground text-sm">
                    · expected execution cadence as a runbook
                  </span>
                </HairlinePanel>
              </section>
            )}

            {/* ───────────── Tested platforms ───────────── */}
            {script.testedPlatforms && script.testedPlatforms.length > 0 && (
              <section className="mt-12" aria-labelledby="platforms-heading">
                <SectionKicker label="TESTED PLATFORMS" />
                <h2
                  id="platforms-heading"
                  className="font-display text-foreground mt-3 flex items-center gap-2 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  <Monitor
                    className="h-5 w-5 shrink-0"
                    style={{ color: "var(--brand-accent-hi)" }}
                    aria-hidden="true"
                  />
                  Verified runtimes
                </h2>
                <div className="mt-5 flex flex-wrap gap-1.5">
                  {script.testedPlatforms.map((platform) => (
                    <MonoTag key={platform}>{platform}</MonoTag>
                  ))}
                </div>
              </section>
            )}

            {/* ───────────── Changelog ───────────── */}
            {script.changelog && script.changelog.length > 0 && (
              <section className="mt-12" aria-labelledby="changelog-heading">
                <SectionKicker label="CHANGELOG" />
                <h2
                  id="changelog-heading"
                  className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  Version history
                </h2>
                <ol className="mt-5 space-y-3">
                  {script.changelog.map((entry, i) => (
                    <li
                      key={i}
                      className="border-l-2 pl-5"
                      style={{
                        borderColor:
                          "color-mix(in oklab, var(--brand-accent) 55%, transparent)",
                      }}
                    >
                      <p className="text-muted-foreground font-mono text-[10.5px] tracking-[0.18em] uppercase">
                        Entry · {String(i + 1).padStart(2, "0")}
                      </p>
                      <p className="text-foreground mt-1.5 text-sm leading-relaxed">
                        {entry}
                      </p>
                    </li>
                  ))}
                </ol>
              </section>
            )}

            {/* ───────────── Code block ───────────── */}
            <section className="mt-12" aria-labelledby="code-heading">
              <SectionKicker label="CODE" />
              <h2
                id="code-heading"
                className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
              >
                Source
              </h2>

              <div
                className={
                  isFullscreen
                    ? "bg-background fixed inset-0 z-50 flex flex-col"
                    : "mt-5 overflow-hidden rounded-md border"
                }
                style={
                  isFullscreen
                    ? undefined
                    : { borderColor: "var(--brand-rule)" }
                }
              >
                {/* Toolbar */}
                <div
                  className="flex items-center justify-between border-b px-4 py-2.5"
                  style={{
                    borderColor: "var(--brand-rule)",
                    background:
                      "color-mix(in oklab, var(--foreground) 4%, var(--background))",
                  }}
                >
                  <div className="flex items-center gap-2">
                    <span
                      aria-hidden="true"
                      className="inline-block h-2 w-2 rounded-full"
                      style={{ backgroundColor: "var(--brand-accent)" }}
                    />
                    <span className="text-muted-foreground font-mono text-[11px] tracking-[0.14em] uppercase">
                      {script.id}.
                      {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                    </span>
                  </div>
                  <div className="flex items-center gap-1">
                    <button
                      type="button"
                      onClick={handleCopyScript}
                      className="focus-visible:ring-accent text-muted-foreground hover:text-foreground focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm px-2 py-1 font-mono text-[10.5px] tracking-[0.14em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                      aria-label={copied ? "Copied" : "Copy code"}
                    >
                      {copied ? (
                        <>
                          <Check
                            className="h-3 w-3"
                            strokeWidth={2.25}
                            style={{ color: "var(--brand-accent-hi)" }}
                            aria-hidden="true"
                          />
                          <span style={{ color: "var(--brand-accent-hi)" }}>
                            Copied
                          </span>
                        </>
                      ) : (
                        <>
                          <Copy className="h-3 w-3" aria-hidden="true" />
                          <span>Copy</span>
                        </>
                      )}
                    </button>
                    <button
                      type="button"
                      onClick={handleFullscreen}
                      className="focus-visible:ring-accent text-muted-foreground hover:text-foreground focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm px-2 py-1 font-mono text-[10.5px] tracking-[0.14em] uppercase transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_8%,transparent)] focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                      aria-label={
                        isFullscreen ? "Exit fullscreen" : "Enter fullscreen"
                      }
                    >
                      {isFullscreen ? (
                        <>
                          <Minimize2 className="h-3 w-3" aria-hidden="true" />
                          <span>Exit</span>
                        </>
                      ) : (
                        <>
                          <Maximize2 className="h-3 w-3" aria-hidden="true" />
                          <span>Fullscreen</span>
                        </>
                      )}
                    </button>
                  </div>
                </div>

                {/* Remediation tabs */}
                {isRemediation && script.remediationPair ? (
                  <>
                    <div
                      role="tablist"
                      aria-label="Remediation script tabs"
                      className="grid grid-cols-2 border-b"
                      style={{ borderColor: "var(--brand-rule)" }}
                    >
                      <button
                        role="tab"
                        type="button"
                        aria-selected={activeRemediationTab === "detection"}
                        onClick={() => setActiveRemediationTab("detection")}
                        className="focus-visible:ring-accent group relative cursor-pointer px-4 py-2.5 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors focus-visible:ring-2 focus-visible:outline-none focus-visible:ring-inset"
                        style={{
                          color:
                            activeRemediationTab === "detection"
                              ? "var(--brand-accent-hi)"
                              : undefined,
                        }}
                      >
                        Detection
                        {activeRemediationTab === "detection" && (
                          <span
                            aria-hidden="true"
                            className="pointer-events-none absolute inset-x-0 bottom-0 h-px"
                            style={{ backgroundColor: "var(--brand-accent)" }}
                          />
                        )}
                      </button>
                      <button
                        role="tab"
                        type="button"
                        aria-selected={activeRemediationTab === "remediation"}
                        onClick={() => setActiveRemediationTab("remediation")}
                        className="focus-visible:ring-accent group text-muted-foreground hover:text-foreground relative cursor-pointer px-4 py-2.5 font-mono text-[11px] tracking-[0.16em] uppercase transition-colors focus-visible:ring-2 focus-visible:outline-none focus-visible:ring-inset"
                        style={{
                          color:
                            activeRemediationTab === "remediation"
                              ? "var(--brand-accent-hi)"
                              : undefined,
                        }}
                      >
                        Remediation
                        {activeRemediationTab === "remediation" && (
                          <span
                            aria-hidden="true"
                            className="pointer-events-none absolute inset-x-0 bottom-0 h-px"
                            style={{ backgroundColor: "var(--brand-accent)" }}
                          />
                        )}
                      </button>
                    </div>

                    <div
                      className={`overflow-auto ${isFullscreen ? "flex-1" : "max-h-[600px]"}`}
                      style={{
                        background:
                          "color-mix(in oklab, var(--foreground) 5%, var(--background))",
                      }}
                    >
                      {activeRemediationTab === "detection" ? (
                        <pre
                          ref={detectionCodeRef}
                          className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-[13px] leading-relaxed`}
                          style={{ margin: 0, background: "transparent" }}
                        >
                          <code
                            className={
                              script.remediationPair.detection.githubPath?.endsWith(
                                ".sh",
                              )
                                ? "language-bash"
                                : "language-powershell"
                            }
                          >
                            {script.remediationPair.detection.code}
                          </code>
                        </pre>
                      ) : (
                        <pre
                          ref={remediationCodeRef}
                          className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-[13px] leading-relaxed`}
                          style={{ margin: 0, background: "transparent" }}
                        >
                          <code
                            className={
                              script.remediationPair.remediation.githubPath?.endsWith(
                                ".sh",
                              )
                                ? "language-bash"
                                : "language-powershell"
                            }
                          >
                            {script.remediationPair.remediation.code}
                          </code>
                        </pre>
                      )}
                    </div>
                  </>
                ) : (
                  <div
                    className={`overflow-auto ${isFullscreen ? "flex-1" : "max-h-[640px]"}`}
                    style={{
                      background:
                        "color-mix(in oklab, var(--foreground) 5%, var(--background))",
                    }}
                  >
                    <pre
                      ref={codeRef}
                      className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-[13px] leading-relaxed`}
                      style={{ margin: 0, background: "transparent" }}
                    >
                      <code
                        className={
                          script.githubPath?.endsWith(".sh")
                            ? "language-bash"
                            : "language-powershell"
                        }
                      >
                        {script.code}
                      </code>
                    </pre>
                  </div>
                )}
              </div>
            </section>

            {/* ───────────── Notes ───────────── */}
            {script.notes && (
              <section className="mt-12" aria-labelledby="notes-heading">
                <SectionKicker label="NOTES" />
                <h2
                  id="notes-heading"
                  className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
                >
                  Author notes
                </h2>
                <HairlinePanel className="mt-5 px-5 py-5">
                  <p className="text-foreground/90 text-sm leading-relaxed whitespace-pre-wrap">
                    {script.notes}
                  </p>
                </HairlinePanel>
              </section>
            )}

            {/* ───────────── Related scripts ───────────── */}
            {allScripts && allScripts.length > 1 && (
              <RelatedScripts
                currentScript={script}
                allScripts={allScripts}
                limit={3}
              />
            )}
          </article>

          {/* Structured data for search engines */}
          <script
            type="application/ld+json"
            dangerouslySetInnerHTML={{
              __html: JSON.stringify({
                "@context": "https://schema.org",
                "@type": "SoftwareSourceCode",
                name: script.title,
                description: script.description,
                codeRepository: script.githubUrl,
                programmingLanguage: script.githubPath?.endsWith(".sh")
                  ? "Bash"
                  : "PowerShell",
                author: {
                  "@type": "Person",
                  name: script.author || "IntuneAutomation.com",
                },
                applicationCategory: "System Administration",
                operatingSystem:
                  script.testedPlatforms?.join(", ") || "Windows",
                dateModified: script.lastUpdated,
                version: script.version || "1.0",
              }),
            }}
          />
        </main>
        <Footer />
        <SearchDialog />
      </div>
    </ScriptsProvider>
  );
}
