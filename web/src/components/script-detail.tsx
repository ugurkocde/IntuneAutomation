"use client";

// ScriptDetail v4 — editorial-technical reskin of the landing modal.
// Surface: bg-card/40 + hairline border + backdrop-blur. Mono kickers, font-display title.
// One accent (phosphor cyan). Azure-blue reserved strictly for Deploy-to-Azure.
// Data flow, handlers, props, and rendered fields are preserved verbatim.

import React, {
  useEffect,
  useRef,
  useState,
  useCallback,
  useMemo,
} from "react";
import { motion, AnimatePresence, useReducedMotion } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { Button } from "~/components/ui/button";
import {
  Copy,
  Download,
  Github,
  X,
  User,
  Shield,
  Smartphone,
  CheckCircle,
  Package,
  BarChart3,
  Stethoscope,
  Settings,
  ExternalLink,
  Code,
  Check,
  Clock,
  Key,
  History,
  Cog,
  AlertTriangle,
  XCircle,
  TestTube,
  ChevronDown,
  ChevronUp,
  Activity,
  Cloud,
  Bell,
  Monitor,
  Apple,
  PanelLeftClose,
  PanelLeftOpen,
} from "lucide-react";
import { useToast } from "~/hooks/use-toast";
import { AnalyticsService } from "~/lib/supabase-analytics";
import "prismjs/themes/prism-tomorrow.css";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "~/components/ui/tabs";
import { QualityChecks } from "~/components/quality-checks";
import { ScriptUsageTrends } from "~/components/script-usage-trends";

// GitHub repository constants
const REPO_OWNER = "ugurkocde";
const REPO_NAME = "IntuneAutomation";

interface ScriptDetailProps {
  script: Script;
  onClose: () => void;
  updateScriptStats?: (scriptId: string, type: "view" | "download") => void;
}

// Icon mapping for each tag — Lucide only, no emoji.
const tagIcons: Record<ScriptTag, typeof Shield> = {
  Security: Shield,
  Devices: Smartphone,
  Compliance: CheckCircle,
  Apps: Package,
  Reporting: BarChart3,
  Diagnostics: Stethoscope,
  Configuration: Settings,
  Operational: Cog,
  Monitoring: Activity,
  Notification: Bell,
  Remediation: Settings,
};

// Lucide icons for test result statuses.
const testResultIcons = {
  pass: CheckCircle,
  fail: XCircle,
  warning: AlertTriangle,
};

// Semantic foreground color per status — drops the rainbow background chips
// for hairline tokens in line with the v4 vocabulary.
const testResultTone: Record<"pass" | "fail" | "warning", string> = {
  pass: "var(--brand-accent-hi)",
  fail: "var(--destructive)",
  warning: "var(--brand-warn)",
};

const testResultLabel: Record<"pass" | "fail" | "warning", string> = {
  pass: "All tests passed",
  fail: "Tests failed",
  warning: "Warnings found",
};

/* ------------------------------------------------------------------ */
/*  Sub-primitives                                                     */
/* ------------------------------------------------------------------ */

// Mono uppercase pill — replaces the rainbow tagColors palette.
function TagPill({ tag }: { tag: ScriptTag }) {
  const TagIcon = tagIcons[tag];
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-sm border px-2 py-1 font-mono text-[10.5px] tracking-[0.14em] whitespace-nowrap uppercase"
      style={{
        borderColor:
          "color-mix(in oklab, var(--brand-accent-hi) 45%, transparent)",
        color: "var(--brand-accent-hi)",
        backgroundColor:
          "color-mix(in oklab, var(--brand-accent) 6%, transparent)",
      }}
    >
      <TagIcon className="h-3 w-3" strokeWidth={2} aria-hidden="true" />
      {tag}
    </span>
  );
}

// Mono section kicker — `// SECTION` in cyan-hi.
function SectionKicker({ children }: { children: React.ReactNode }) {
  return (
    <p
      className="font-mono text-[10.5px] font-medium tracking-[0.18em] uppercase"
      style={{ color: "var(--brand-accent-hi)" }}
      aria-hidden="true"
    >
      {children}
    </p>
  );
}

export function ScriptDetail({
  script,
  onClose,
  updateScriptStats,
}: ScriptDetailProps) {
  const { toast } = useToast();
  const prefersReducedMotion = useReducedMotion();
  const codeRef = useRef<HTMLPreElement>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [downloaded, setDownloaded] = useState(false);
  const [isHighlighted, setIsHighlighted] = useState(false);
  const [currentCodeContent, setCurrentCodeContent] = useState("");
  const [showDetails, setShowDetails] = useState(false);
  const [isDesktop, setIsDesktop] = useState(false);
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const hasTrackedView = useRef(false);
  const [isDeployingToAzure, setIsDeployingToAzure] = useState(false);
  const [isDescriptionExpanded, setIsDescriptionExpanded] = useState(false);
  const [activeRemediationTab, setActiveRemediationTab] = useState<
    "detection" | "remediation"
  >("detection");

  // Memoize expensive computations
  const primaryTag = useMemo(() => script.tags[0], [script.tags]);

  const githubUrl = useMemo(
    () =>
      script.githubUrl ||
      `https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/${script.githubPath || `scripts/${script.id}.ps1`}`,
    [script.githubUrl, script.githubPath, script.id],
  );

  // Filesystem-style breadcrumb path — `~/intune-library/{tag}/{slug}.ps1`.
  const breadcrumbExt = script.githubPath?.endsWith(".sh") ? "sh" : "ps1";
  const breadcrumbSlug = script.slug || script.id;
  const breadcrumbTagSlug = primaryTag ? primaryTag.toLowerCase() : "scripts";

  // Track script view when component mounts
  useEffect(() => {
    if (!hasTrackedView.current && script) {
      hasTrackedView.current = true;
      setCurrentCodeContent(script.code);
    }
  }, [script]);

  // Lazy load Prism.js and highlight code
  const highlightCode = useCallback(async () => {
    if (!codeRef.current || isHighlighted) return;

    try {
      // Dynamic import to avoid blocking the main thread
      const Prism = await import("prismjs");

      if (script.githubPath?.endsWith(".sh")) {
        // @ts-ignore - Prism.js component imports don't have proper types
        await import("prismjs/components/prism-bash");
      } else {
        // @ts-ignore - Prism.js component imports don't have proper types
        await import("prismjs/components/prism-powershell");
      }

      // Use requestIdleCallback for non-blocking highlighting
      if ("requestIdleCallback" in window) {
        requestIdleCallback(() => {
          if (codeRef.current) {
            Prism.highlightElement(codeRef.current);
            setIsHighlighted(true);
          }
        });
      } else {
        // Fallback for browsers without requestIdleCallback
        setTimeout(() => {
          if (codeRef.current) {
            Prism.highlightElement(codeRef.current);
            setIsHighlighted(true);
          }
        }, 0);
      }
    } catch (error) {
      // Silently fail - syntax highlighting is not critical
    }
  }, [isHighlighted, script.githubPath]);

  // Memoized event handlers
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      }
    },
    [onClose],
  );

  const handleCopyScript = useCallback(async () => {
    try {
      let codeToCopy = currentCodeContent;

      // If it's a remediation script, copy the active tab's code
      if (script.scriptType === "remediation" && script.remediationPair) {
        codeToCopy =
          activeRemediationTab === "detection"
            ? script.remediationPair.detection.code
            : script.remediationPair.remediation.code;
      }

      await navigator.clipboard.writeText(codeToCopy);
      setCopied("script");

      // Update stats immediately in the UI for real-time feedback
      updateScriptStats?.(script.id, "download");

      // Track the download/copy
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
        // Silently fail - analytics shouldn't block user experience
      });

      toast({
        title: "Script copied!",
        description: "The script has been copied to your clipboard.",
      });

      setTimeout(() => setCopied(null), 2000);
    } catch (error) {
      toast({
        title: "Copy failed",
        description: "Failed to copy script to clipboard.",
        variant: "destructive",
      });
    }
  }, [
    currentCodeContent,
    script,
    activeRemediationTab,
    toast,
    updateScriptStats,
  ]);

  const handleDownloadScript = useCallback(async () => {
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
        const blob = new Blob([currentCodeContent], { type: "text/plain" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        const fileExtension = script.githubPath?.endsWith(".sh") ? "sh" : "ps1";
        a.download = `${script.id}.${fileExtension}`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        toast({
          title: "Download started!",
          description: "The script is being downloaded.",
        });
      }

      setDownloaded(true);

      // Update stats immediately in the UI for real-time feedback
      updateScriptStats?.(script.id, "download");

      // Track the download
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
        // Silently fail - analytics shouldn't block user experience
      });
    } catch (error) {
      toast({
        title: "Download failed",
        description: "Failed to download the script.",
        variant: "destructive",
      });
    }
  }, [currentCodeContent, script, toast, updateScriptStats]);

  const handleGitHubClick = useCallback(() => {
    // Update stats immediately in the UI for real-time feedback
    updateScriptStats?.(script.id, "download");

    // Track GitHub link click
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
      // Silently fail - analytics shouldn't block user experience
    });
  }, [script.id, script.title, updateScriptStats]);

  const handleDeployToAzure = useCallback(async () => {
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

      // Track the deployment attempt
      const userAgent =
        typeof window !== "undefined" ? navigator.userAgent : undefined;
      const sessionId =
        typeof window !== "undefined"
          ? sessionStorage.getItem("session_id") || undefined
          : undefined;

      AnalyticsService.trackScriptDownload(script.id, script.title, "azure", {
        userAgent,
        sessionId,
      }).catch((error) => {
        // Silently fail - analytics shouldn't block user experience
      });

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
  }, [script, toast]);

  useEffect(() => {
    // Check if we're on desktop
    const checkIsDesktop = () => {
      setIsDesktop(window.innerWidth >= 640);
    };

    checkIsDesktop();
    window.addEventListener("resize", checkIsDesktop);

    // Highlight code after a short delay to avoid blocking initial render
    const timer = setTimeout(highlightCode, 100);

    window.addEventListener("keydown", handleKeyDown);
    document.body.style.overflow = "hidden";

    return () => {
      clearTimeout(timer);
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("resize", checkIsDesktop);
      document.body.style.overflow = "auto";
    };
  }, [highlightCode, handleKeyDown]);

  // Code surface — dark, soft-mixed background per v4 contract.
  const codeSurfaceStyle: React.CSSProperties = {
    backgroundColor:
      "color-mix(in oklab, var(--foreground) 5%, var(--background))",
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{
        duration: prefersReducedMotion ? 0 : 0.2,
        ease: [0.22, 1, 0.36, 1],
      }}
      className="bg-background/60 fixed inset-0 z-50 flex items-end justify-center p-4 pt-8 pb-4 backdrop-blur-sm sm:items-center sm:p-4"
      onClick={onClose}
    >
      <motion.div
        initial={
          prefersReducedMotion ? { opacity: 0 } : { y: "4%", opacity: 0 }
        }
        animate={{ y: 0, opacity: 1 }}
        exit={prefersReducedMotion ? { opacity: 0 } : { y: "4%", opacity: 0 }}
        transition={{
          duration: prefersReducedMotion ? 0 : 0.32,
          ease: [0.22, 1, 0.36, 1],
        }}
        className="bg-card/40 relative flex h-full max-h-[calc(100vh-3rem)] w-full flex-col overflow-hidden rounded-lg border backdrop-blur-md sm:max-h-[95vh] sm:max-w-7xl"
        style={{ borderColor: "var(--brand-rule)" }}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={script.title}
      >
        {/* -------------------------------------------------------------- */}
        {/* Header — breadcrumb path on the left, controls on the right.   */}
        {/* -------------------------------------------------------------- */}
        <div
          className="relative z-10 shrink-0 border-b p-4 sm:p-6"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          {/* Filesystem-tree breadcrumb — matches the hero CategoryMap vocabulary. */}
          <div className="flex items-start justify-between gap-4">
            <p className="text-muted-foreground min-w-0 truncate font-mono text-[11px] tracking-wide">
              <span className="select-none">~/intune-library</span>
              <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
              <span style={{ color: "var(--brand-accent-hi)" }}>
                {breadcrumbTagSlug}
              </span>
              <span style={{ color: "var(--brand-accent-hi)" }}>/</span>
              <span className="text-foreground">
                {breadcrumbSlug}.{breadcrumbExt}
              </span>
            </p>

            {/* Action buttons */}
            <div className="flex shrink-0 items-center gap-1">
              <button
                type="button"
                onClick={() => {
                  const url = `/script/${script.slug || script.id}/`;
                  window.open(url, "_blank");
                }}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-8 w-8 items-center justify-center rounded-sm transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                aria-label="Open in new tab"
                title="Open in new tab"
              >
                <ExternalLink className="h-4 w-4" strokeWidth={2} />
              </button>
              <button
                type="button"
                onClick={onClose}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-8 w-8 items-center justify-center rounded-sm transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                aria-label="Close"
              >
                <X className="h-4 w-4" strokeWidth={2} />
              </button>
            </div>
          </div>

          {/* Mono kicker — primary tag */}
          <div className="mt-4">
            <SectionKicker>
              {primaryTag ? `// ${primaryTag.toUpperCase()}` : "// SCRIPT"}
            </SectionKicker>
            <h2 className="font-display text-foreground mt-2 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl">
              {script.title}
            </h2>

            {/* Mobile-only description (desktop renders it in the sidebar). */}
            <div className="mt-3 sm:hidden">
              <p
                className={`text-muted-foreground text-sm leading-relaxed ${
                  !isDescriptionExpanded && script.description.length > 120
                    ? "line-clamp-2"
                    : ""
                }`}
              >
                {script.description}
              </p>
              {script.description.length > 120 && (
                <button
                  type="button"
                  onClick={() =>
                    setIsDescriptionExpanded(!isDescriptionExpanded)
                  }
                  className="text-muted-foreground hover:text-foreground mt-1 inline-flex items-center gap-1 font-mono text-[10.5px] tracking-[0.18em] uppercase transition-colors"
                >
                  {isDescriptionExpanded ? (
                    <>
                      <span>Show less</span>
                      <ChevronUp className="h-3 w-3" />
                    </>
                  ) : (
                    <>
                      <span>Read more</span>
                      <ChevronDown className="h-3 w-3" />
                    </>
                  )}
                </button>
              )}
            </div>
          </div>

          {/* Tag pills — mobile only here; desktop shows them in the sidebar */}
          <div className="mt-3 flex gap-2 overflow-x-auto pb-1 sm:hidden">
            {script.tags.map((tag) => (
              <TagPill key={tag} tag={tag} />
            ))}
          </div>
        </div>

        {/* -------------------------------------------------------------- */}
        {/* Main content — two-column layout on desktop                    */}
        {/* -------------------------------------------------------------- */}
        <div className="flex flex-1 overflow-hidden">
          {/* Left column — metadata, actions, details */}
          <AnimatePresence mode="wait">
            {(!isDesktop || !isSidebarCollapsed) && (
              <motion.div
                key="sidebar"
                initial={isDesktop ? { width: 0 } : false}
                animate={{
                  width: isDesktop ? "40%" : "100%",
                }}
                exit={{
                  width: 0,
                }}
                transition={{
                  duration: prefersReducedMotion ? 0 : 0.25,
                  ease: [0.22, 1, 0.36, 1],
                }}
                className="flex flex-col overflow-hidden lg:w-1/3"
              >
                <div className="flex flex-1 flex-col overflow-hidden">
                  <motion.div
                    initial={
                      prefersReducedMotion ? false : { opacity: 0, y: 12 }
                    }
                    animate={{ opacity: 1, y: 0 }}
                    transition={{
                      delay: 0.08,
                      duration: prefersReducedMotion ? 0 : 0.3,
                      ease: [0.22, 1, 0.36, 1],
                    }}
                    className="flex flex-1 flex-col overflow-y-auto"
                  >
                    {/* Description + tag pills + metadata + actions */}
                    <div
                      className="shrink-0 border-b p-4 sm:p-6"
                      style={{ borderColor: "var(--brand-rule)" }}
                    >
                      <div className="space-y-5">
                        {/* Description — desktop only (mobile renders in header). */}
                        <div className="hidden sm:block">
                          <p className="text-muted-foreground text-sm leading-relaxed">
                            {script.description}
                          </p>
                        </div>

                        {/* Tag pills — desktop only here. */}
                        <div className="hidden gap-2 sm:flex sm:flex-wrap">
                          {script.tags.map((tag) => (
                            <TagPill key={tag} tag={tag} />
                          ))}
                        </div>

                        {/* Meta strip — mono uppercase tracked-wide. */}
                        <div>
                          <SectionKicker>// META</SectionKicker>
                          <ul className="mt-2 space-y-1.5 font-mono text-[11px] tracking-wide">
                            <li className="text-muted-foreground flex items-center gap-2">
                              <Code
                                className="h-3 w-3"
                                strokeWidth={2}
                                aria-hidden="true"
                              />
                              <span>
                                {script.githubPath?.endsWith(".sh")
                                  ? "Shell script"
                                  : "PowerShell script"}
                              </span>
                            </li>
                            {script.testedPlatforms &&
                              script.testedPlatforms.length > 0 && (
                                <li className="text-muted-foreground flex items-center gap-2">
                                  {script.testedPlatforms.includes("macOS") ? (
                                    <Apple
                                      className="h-3 w-3"
                                      strokeWidth={2}
                                      aria-hidden="true"
                                    />
                                  ) : (
                                    <Monitor
                                      className="h-3 w-3"
                                      strokeWidth={2}
                                      aria-hidden="true"
                                    />
                                  )}
                                  <span>
                                    Platform ·{" "}
                                    {script.testedPlatforms.join(", ")}
                                  </span>
                                </li>
                              )}
                            {script.author && (
                              <li className="text-muted-foreground flex items-center gap-2">
                                <User
                                  className="h-3 w-3"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <span>{script.author}</span>
                              </li>
                            )}
                            {script.version && (
                              <li className="text-muted-foreground flex items-center gap-2">
                                <Code
                                  className="h-3 w-3"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <span>Version {script.version}</span>
                              </li>
                            )}
                            {script.minRole && (
                              <li className="text-muted-foreground flex items-center gap-2">
                                <User
                                  className="h-3 w-3"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <span>Min role · {script.minRole}</span>
                              </li>
                            )}
                          </ul>
                        </div>

                        {/* Permissions — hairline-bordered card, mono kicker.
                            Render each scope on its own row so long lists stop
                            collapsing into a hard-to-scan comma blob. */}
                        <div
                          className="rounded-md border p-3"
                          style={{ borderColor: "var(--brand-rule)" }}
                        >
                          <div className="mb-2 flex items-center gap-2">
                            <Key
                              className="text-muted-foreground h-3.5 w-3.5"
                              strokeWidth={2}
                              aria-hidden="true"
                            />
                            <SectionKicker>
                              // REQUIRED PERMISSIONS
                            </SectionKicker>
                          </div>
                          <ul className="space-y-1">
                            {(script.permissions &&
                            script.permissions.length > 0
                              ? script.permissions
                              : ["DeviceManagement.Read.All"]
                            ).map((perm) => (
                              <li key={perm}>
                                <code
                                  className="font-mono text-[11px] leading-relaxed break-all"
                                  style={{ color: "var(--brand-accent-hi)" }}
                                >
                                  {perm}
                                </code>
                              </li>
                            ))}
                          </ul>
                        </div>

                        {/* Action row — mirrors v4 ScriptCard vocabulary.
                            Deploy gets Azure-blue. Copy + Download + GitHub stay neutral.
                            Stacked vertically — three buttons side-by-side in a ~33% sidebar
                            forced text to wrap awkwardly at common widths. */}
                        <div className="flex flex-col gap-2">
                          {/* GitHub */}
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-10 w-full cursor-pointer gap-2 rounded-md text-xs font-medium tracking-wide uppercase sm:h-9"
                            asChild
                          >
                            <a
                              href={githubUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              onClick={handleGitHubClick}
                            >
                              <Github
                                className="h-3.5 w-3.5"
                                strokeWidth={2}
                                aria-hidden="true"
                              />
                              <span>GitHub</span>
                              <ExternalLink
                                className="h-3 w-3"
                                strokeWidth={2}
                                aria-hidden="true"
                              />
                            </a>
                          </Button>

                          {/* Deploy to Azure — the ONLY surface allowed Azure-blue. */}
                          {!script.githubPath?.endsWith(".sh") &&
                            script.scriptType !== "remediation" && (
                              <button
                                type="button"
                                onClick={handleDeployToAzure}
                                disabled={isDeployingToAzure}
                                className="focus-visible:ring-accent focus-visible:ring-offset-background inline-flex h-10 w-full cursor-pointer items-center justify-center gap-2 rounded-md border text-xs font-medium tracking-wide uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-60 sm:h-9"
                                style={{
                                  borderColor:
                                    "color-mix(in oklab, var(--brand-azure) 55%, transparent)",
                                  color: "var(--brand-azure)",
                                  backgroundColor:
                                    "color-mix(in oklab, var(--brand-azure) 7%, transparent)",
                                }}
                                aria-label="Deploy to Azure Automation"
                              >
                                {isDeployingToAzure ? (
                                  <>
                                    <Cloud
                                      className="h-3.5 w-3.5 animate-pulse"
                                      strokeWidth={2}
                                      aria-hidden="true"
                                    />
                                    <span>Deploying…</span>
                                  </>
                                ) : (
                                  <>
                                    <Cloud
                                      className="h-3.5 w-3.5"
                                      strokeWidth={2}
                                      aria-hidden="true"
                                    />
                                    <span>Deploy to Azure</span>
                                  </>
                                )}
                              </button>
                            )}

                          {/* Download */}
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-10 w-full cursor-pointer gap-2 rounded-md text-xs font-medium tracking-wide uppercase sm:h-9"
                            onClick={handleDownloadScript}
                            disabled={downloaded}
                          >
                            {downloaded ? (
                              <>
                                <Check
                                  className="h-3.5 w-3.5"
                                  strokeWidth={2.25}
                                  aria-hidden="true"
                                  style={{
                                    color: "var(--brand-accent-hi)",
                                  }}
                                />
                                <span
                                  style={{ color: "var(--brand-accent-hi)" }}
                                >
                                  {script.scriptType === "remediation"
                                    ? "Downloaded both"
                                    : "Downloaded"}
                                </span>
                              </>
                            ) : (
                              <>
                                <Download
                                  className="h-3.5 w-3.5"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <span>
                                  {script.scriptType === "remediation"
                                    ? "Download both"
                                    : "Download"}
                                </span>
                              </>
                            )}
                          </Button>
                        </div>

                        {/* Usage trends — compact 6-month chart, hidden when
                            there is no counted activity for this script. */}
                        <ScriptUsageTrends
                          scriptId={script.id}
                          months={6}
                          compact
                        >
                          {(chart) => (
                            <div
                              className="rounded-md border p-3"
                              style={{ borderColor: "var(--brand-rule)" }}
                            >
                              <div className="mb-2 flex items-center gap-2">
                                <BarChart3
                                  className="text-muted-foreground h-3.5 w-3.5"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <SectionKicker>// USAGE TRENDS</SectionKicker>
                              </div>
                              {chart}
                            </div>
                          )}
                        </ScriptUsageTrends>
                      </div>
                    </div>

                    {/* Quality / tests / changelog — same scroll container */}
                    <div className="p-4 sm:p-6">
                      <div className="space-y-5">
                        {/* Quality checks — component already uses semantic tokens. */}
                        {script.tests ? (
                          <QualityChecks tests={script.tests} />
                        ) : (
                          script.testResult && (
                            <div
                              className="rounded-md border p-4"
                              style={{ borderColor: "var(--brand-rule)" }}
                            >
                              <div className="mb-2 flex items-center gap-2">
                                <TestTube
                                  className="text-muted-foreground h-3.5 w-3.5"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <SectionKicker>// TEST RESULTS</SectionKicker>
                              </div>
                              <div className="mb-3 flex items-center gap-1.5 font-mono text-[11px] tracking-[0.14em] uppercase">
                                {React.createElement(
                                  testResultIcons[script.testResult.result] ||
                                    testResultIcons.fail,
                                  {
                                    className: "h-3.5 w-3.5",
                                    strokeWidth: 2,
                                    style: {
                                      color:
                                        testResultTone[
                                          script.testResult.result
                                        ] || testResultTone.fail,
                                    },
                                    "aria-hidden": true,
                                  },
                                )}
                                <span
                                  style={{
                                    color:
                                      testResultTone[
                                        script.testResult.result
                                      ] || testResultTone.fail,
                                  }}
                                >
                                  {testResultLabel[script.testResult.result] ||
                                    testResultLabel.fail}
                                </span>
                              </div>
                              <p className="text-muted-foreground text-xs leading-relaxed">
                                {script.testResult.result === "pass"
                                  ? script.githubPath?.endsWith(".sh")
                                    ? "This script has passed all ShellCheck quality checks and follows shell scripting best practices."
                                    : "This script has passed all PSScriptAnalyzer quality checks and follows PowerShell best practices."
                                  : script.testResult.result === "fail"
                                    ? "This script has some issues that need to be addressed. Please review the code carefully."
                                    : "This script has minor warnings but is generally safe to use."}
                              </p>
                              <div className="text-muted-foreground/80 mt-2 flex items-center gap-1 font-mono text-[10.5px] tracking-wide">
                                <Clock
                                  className="h-3 w-3"
                                  strokeWidth={2}
                                  aria-hidden="true"
                                />
                                <span>
                                  Tested {script.testResult.timestamp}
                                </span>
                              </div>
                            </div>
                          )
                        )}

                        {/* Changelog */}
                        {script.changelog && script.changelog.length > 0 && (
                          <div
                            className="rounded-md border p-4"
                            style={{ borderColor: "var(--brand-rule)" }}
                          >
                            <div className="mb-3 flex items-center gap-2">
                              <History
                                className="text-muted-foreground h-3.5 w-3.5"
                                strokeWidth={2}
                                aria-hidden="true"
                              />
                              <SectionKicker>// CHANGELOG</SectionKicker>
                            </div>
                            <div className="space-y-1.5">
                              {script.changelog.map((entry, index) => (
                                <div
                                  key={index}
                                  className="text-muted-foreground rounded-sm border-l-2 px-3 py-1.5 font-mono text-[11px] leading-relaxed"
                                  style={{
                                    borderColor:
                                      "color-mix(in oklab, var(--brand-accent) 30%, transparent)",
                                    backgroundColor:
                                      "color-mix(in oklab, var(--brand-accent) 4%, transparent)",
                                  }}
                                >
                                  {entry}
                                </div>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    </div>
                  </motion.div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Right column — code surface (desktop only) */}
          <motion.div
            initial={false}
            animate={{
              width: isDesktop ? (isSidebarCollapsed ? "100%" : "60%") : "100%",
            }}
            transition={{
              duration: prefersReducedMotion ? 0 : 0.3,
              ease: [0.22, 1, 0.36, 1],
            }}
            className={`hidden flex-col overflow-hidden sm:flex ${
              !isSidebarCollapsed ? "border-l" : ""
            } lg:w-2/3`}
            style={{
              borderColor: "var(--brand-rule)",
            }}
          >
            {/* Code header — mono filename + Copy button */}
            <div
              className="flex shrink-0 items-center justify-between border-b px-4 py-3"
              style={{
                borderColor: "var(--brand-rule)",
                backgroundColor:
                  "color-mix(in oklab, var(--foreground) 3%, var(--background))",
              }}
            >
              <div className="flex items-center gap-3">
                {isDesktop && (
                  <>
                    <button
                      type="button"
                      onClick={() => setIsSidebarCollapsed(!isSidebarCollapsed)}
                      className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm font-mono text-[11px] tracking-[0.14em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none"
                      aria-label={
                        isSidebarCollapsed
                          ? "Show details panel"
                          : "Hide details panel"
                      }
                    >
                      {isSidebarCollapsed ? (
                        <>
                          <PanelLeftOpen
                            className="h-3 w-3"
                            strokeWidth={2}
                            aria-hidden="true"
                          />
                          <span>Show details</span>
                        </>
                      ) : (
                        <>
                          <PanelLeftClose
                            className="h-3 w-3"
                            strokeWidth={2}
                            aria-hidden="true"
                          />
                          <span>Hide details</span>
                        </>
                      )}
                    </button>
                    <span
                      aria-hidden="true"
                      className="h-3 w-px"
                      style={{ backgroundColor: "var(--brand-rule)" }}
                    />
                  </>
                )}
                <Code
                  className="text-muted-foreground h-3.5 w-3.5"
                  strokeWidth={2}
                  aria-hidden="true"
                />
                <span className="text-muted-foreground font-mono text-[11px] tracking-wide">
                  {script.id}.
                  {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                </span>
              </div>

              {/* Copy button — neutral by default, cyan-accent on success */}
              <button
                type="button"
                onClick={handleCopyScript}
                disabled={copied === "script"}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm font-mono text-[11px] tracking-[0.14em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none disabled:cursor-default"
                aria-label={
                  copied === "script"
                    ? "Script copied"
                    : "Copy script to clipboard"
                }
              >
                {copied === "script" ? (
                  <>
                    <Check
                      className="h-3 w-3"
                      strokeWidth={2.25}
                      aria-hidden="true"
                      style={{ color: "var(--brand-accent-hi)" }}
                    />
                    <span style={{ color: "var(--brand-accent-hi)" }}>
                      Copied
                    </span>
                  </>
                ) : (
                  <>
                    <Copy
                      className="h-3 w-3"
                      strokeWidth={2}
                      aria-hidden="true"
                    />
                    <span>Copy script</span>
                  </>
                )}
              </button>
            </div>

            {/* Code body */}
            {script.scriptType === "remediation" && script.remediationPair ? (
              <Tabs
                value={activeRemediationTab}
                onValueChange={(value) =>
                  setActiveRemediationTab(value as "detection" | "remediation")
                }
                className="flex flex-1 flex-col overflow-hidden"
              >
                <TabsList
                  className="grid w-full grid-cols-2 rounded-none border-b bg-transparent p-0"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <TabsTrigger
                    value="detection"
                    className="rounded-none font-mono text-[11px] tracking-[0.14em] uppercase"
                  >
                    Detection script
                  </TabsTrigger>
                  <TabsTrigger
                    value="remediation"
                    className="rounded-none font-mono text-[11px] tracking-[0.14em] uppercase"
                  >
                    Remediation script
                  </TabsTrigger>
                </TabsList>
                <TabsContent
                  value="detection"
                  className="m-0 flex-1 overflow-auto"
                  style={codeSurfaceStyle}
                >
                  <pre
                    className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 font-mono text-[12.5px] leading-relaxed`}
                    ref={
                      activeRemediationTab === "detection" ? codeRef : undefined
                    }
                  >
                    <code>{script.remediationPair.detection.code}</code>
                  </pre>
                </TabsContent>
                <TabsContent
                  value="remediation"
                  className="m-0 flex-1 overflow-auto"
                  style={codeSurfaceStyle}
                >
                  <pre
                    className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 font-mono text-[12.5px] leading-relaxed`}
                    ref={
                      activeRemediationTab === "remediation"
                        ? codeRef
                        : undefined
                    }
                  >
                    <code>{script.remediationPair.remediation.code}</code>
                  </pre>
                </TabsContent>
              </Tabs>
            ) : (
              <div className="flex-1 overflow-auto" style={codeSurfaceStyle}>
                <pre
                  className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 font-mono text-[12.5px] leading-relaxed`}
                  ref={codeRef}
                >
                  <code>{script.code}</code>
                </pre>
              </div>
            )}
          </motion.div>
        </div>

        {/* -------------------------------------------------------------- */}
        {/* Mobile-only code disclosure                                    */}
        {/* -------------------------------------------------------------- */}
        <div className="flex flex-col overflow-hidden sm:hidden">
          <div
            className="shrink-0 border-t p-3"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <Button
              variant="outline"
              size="sm"
              className="h-10 w-full gap-2 rounded-md text-xs font-medium tracking-wide uppercase"
              onClick={() => setShowDetails(!showDetails)}
            >
              <Code
                className="h-3.5 w-3.5"
                strokeWidth={2}
                aria-hidden="true"
              />
              <span>{showDetails ? "Hide script" : "View script"}</span>
              {showDetails ? (
                <ChevronUp className="h-3.5 w-3.5" strokeWidth={2} />
              ) : (
                <ChevronDown className="h-3.5 w-3.5" strokeWidth={2} />
              )}
            </Button>
          </div>

          <AnimatePresence>
            {showDetails && (
              <motion.div
                initial={{ height: 0 }}
                animate={{ height: "50vh" }}
                exit={{ height: 0 }}
                transition={{
                  duration: prefersReducedMotion ? 0 : 0.3,
                  ease: [0.22, 1, 0.36, 1],
                }}
                className="overflow-hidden border-t"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                <div
                  className="flex items-center justify-between border-b px-3 py-2"
                  style={{
                    borderColor: "var(--brand-rule)",
                    backgroundColor:
                      "color-mix(in oklab, var(--foreground) 3%, var(--background))",
                  }}
                >
                  <div className="flex items-center gap-2">
                    <Code
                      className="text-muted-foreground h-3 w-3"
                      strokeWidth={2}
                      aria-hidden="true"
                    />
                    <span className="text-muted-foreground font-mono text-[10.5px] tracking-wide">
                      {script.id}.
                      {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={handleCopyScript}
                    disabled={copied === "script"}
                    className="text-muted-foreground hover:text-foreground focus-visible:ring-accent focus-visible:ring-offset-background inline-flex cursor-pointer items-center gap-1.5 rounded-sm font-mono text-[10.5px] tracking-[0.14em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:outline-none disabled:cursor-default"
                    aria-label={
                      copied === "script"
                        ? "Script copied"
                        : "Copy script to clipboard"
                    }
                  >
                    {copied === "script" ? (
                      <>
                        <Check
                          className="h-3 w-3"
                          strokeWidth={2.25}
                          aria-hidden="true"
                          style={{ color: "var(--brand-accent-hi)" }}
                        />
                        <span style={{ color: "var(--brand-accent-hi)" }}>
                          Copied
                        </span>
                      </>
                    ) : (
                      <>
                        <Copy
                          className="h-3 w-3"
                          strokeWidth={2}
                          aria-hidden="true"
                        />
                        <span>Copy</span>
                      </>
                    )}
                  </button>
                </div>

                {script.scriptType === "remediation" &&
                script.remediationPair ? (
                  <Tabs
                    value={activeRemediationTab}
                    onValueChange={(value) =>
                      setActiveRemediationTab(
                        value as "detection" | "remediation",
                      )
                    }
                    className="flex h-full flex-1 flex-col"
                  >
                    <TabsList
                      className="grid w-full grid-cols-2 rounded-none border-b bg-transparent p-0"
                      style={{ borderColor: "var(--brand-rule)" }}
                    >
                      <TabsTrigger
                        value="detection"
                        className="rounded-none font-mono text-[10.5px] tracking-[0.14em] uppercase"
                      >
                        Detection
                      </TabsTrigger>
                      <TabsTrigger
                        value="remediation"
                        className="rounded-none font-mono text-[10.5px] tracking-[0.14em] uppercase"
                      >
                        Remediation
                      </TabsTrigger>
                    </TabsList>
                    <TabsContent
                      value="detection"
                      className="m-0 flex-1 overflow-auto"
                      style={codeSurfaceStyle}
                    >
                      <pre
                        className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 font-mono text-[11px] leading-relaxed`}
                        ref={
                          activeRemediationTab === "detection"
                            ? codeRef
                            : undefined
                        }
                      >
                        <code>{script.remediationPair.detection.code}</code>
                      </pre>
                    </TabsContent>
                    <TabsContent
                      value="remediation"
                      className="m-0 flex-1 overflow-auto"
                      style={codeSurfaceStyle}
                    >
                      <pre
                        className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 font-mono text-[11px] leading-relaxed`}
                        ref={
                          activeRemediationTab === "remediation"
                            ? codeRef
                            : undefined
                        }
                      >
                        <code>{script.remediationPair.remediation.code}</code>
                      </pre>
                    </TabsContent>
                  </Tabs>
                ) : (
                  <div
                    className="h-full overflow-auto"
                    style={codeSurfaceStyle}
                  >
                    <pre
                      className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 font-mono text-[11px] leading-relaxed`}
                      ref={codeRef}
                    >
                      <code>{script.code}</code>
                    </pre>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </motion.div>
    </motion.div>
  );
}
