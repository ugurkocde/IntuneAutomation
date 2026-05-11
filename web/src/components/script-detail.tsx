"use client";

import React, {
  useEffect,
  useRef,
  useState,
  useCallback,
  useMemo,
} from "react";
import { motion, AnimatePresence } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { Badge } from "~/components/ui/badge";
import { Button } from "~/components/ui/button";
import {
  Calendar,
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
  Info,
  Activity,
  Cloud,
  Bell,
  Monitor,
  Apple,
} from "lucide-react";
import { useToast } from "~/hooks/use-toast";
import { AnalyticsService } from "~/lib/supabase-analytics";
import "prismjs/themes/prism-tomorrow.css";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "~/components/ui/tabs";

// GitHub repository constants
const REPO_OWNER = "ugurkocde";
const REPO_NAME = "IntuneAutomation";

interface ScriptDetailProps {
  script: Script;
  onClose: () => void;
  updateScriptStats?: (scriptId: string, type: "view" | "download") => void;
}

// Icon mapping for each tag
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

// Color mapping for each tag
const tagColors: Record<ScriptTag, string> = {
  Security:
    "text-red-600 bg-red-50 border-red-200 dark:text-red-400 dark:bg-red-950/50 dark:border-red-800/50",
  Devices:
    "text-blue-600 bg-blue-50 border-blue-200 dark:text-blue-400 dark:bg-blue-950/50 dark:border-blue-800/50",
  Compliance:
    "text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-950/50 dark:border-green-800/50",
  Apps: "text-purple-600 bg-purple-50 border-purple-200 dark:text-purple-400 dark:bg-purple-950/50 dark:border-purple-800/50",
  Reporting:
    "text-orange-600 bg-orange-50 border-orange-200 dark:text-orange-400 dark:bg-orange-950/50 dark:border-orange-800/50",
  Diagnostics:
    "text-cyan-600 bg-cyan-50 border-cyan-200 dark:text-cyan-400 dark:bg-cyan-950/50 dark:border-cyan-800/50",
  Configuration:
    "text-slate-600 bg-slate-50 border-slate-200 dark:text-slate-400 dark:bg-slate-950/50 dark:border-slate-800/50",
  Operational:
    "text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-950/50 dark:border-yellow-800/50",
  Monitoring:
    "text-indigo-600 bg-indigo-50 border-indigo-200 dark:text-indigo-400 dark:bg-indigo-950/50 dark:border-indigo-800/50",
  Notification:
    "text-violet-600 bg-violet-50 border-violet-200 dark:text-violet-400 dark:bg-violet-950/50 dark:border-violet-800/50",
  Remediation:
    "text-emerald-600 bg-emerald-50 border-emerald-200 dark:text-emerald-400 dark:bg-emerald-950/50 dark:border-emerald-800/50",
};

// Color mapping for test results
const testResultColors = {
  pass: "text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-950/50 dark:border-green-800/50",
  fail: "text-red-600 bg-red-50 border-red-200 dark:text-red-400 dark:bg-red-950/50 dark:border-red-800/50",
  warning:
    "text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-950/50 dark:border-yellow-800/50",
};

const testResultIcons = {
  pass: CheckCircle,
  fail: XCircle,
  warning: AlertTriangle,
};

export function ScriptDetail({
  script,
  onClose,
  updateScriptStats,
}: ScriptDetailProps) {
  const { toast } = useToast();
  const codeRef = useRef<HTMLPreElement>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [downloaded, setDownloaded] = useState(false);
  const [isHighlighted, setIsHighlighted] = useState(false);
  const [isContentLoading, setIsContentLoading] = useState(true);
  const [currentCodeContent, setCurrentCodeContent] = useState("");
  const [isGitHubMode, setIsGitHubMode] = useState(false);
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
  const PrimaryIcon = useMemo(
    () => (primaryTag ? tagIcons[primaryTag] : Code),
    [primaryTag],
  );

  const githubUrl = useMemo(
    () =>
      script.githubUrl ||
      `https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/${script.githubPath || `scripts/${script.id}.ps1`}`,
    [script.githubUrl, script.githubPath, script.id],
  );

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
  }, [isHighlighted]);

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

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.2 }}
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 pt-8 pb-4 sm:items-center sm:p-4"
      onClick={onClose}
    >
      <motion.div
        initial={{ y: "100%", opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        exit={{ y: "100%", opacity: 0 }}
        transition={{ duration: 0.3, ease: "easeOut" }}
        className="bg-card relative flex h-full max-h-[calc(100vh-3rem)] w-full flex-col overflow-hidden rounded-2xl border shadow-xl sm:max-h-[95vh] sm:max-w-7xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Compact Header - spans full width */}
        <div className="border-border/50 bg-card relative z-10 shrink-0 border-b p-4 sm:p-6">
          <div className="flex w-full items-center justify-between gap-4">
            {/* Title section */}
            <div className="flex min-w-0 flex-1 items-center gap-3">
              <div
                className={`shrink-0 rounded-lg p-2 ${primaryTag ? tagColors[primaryTag] : "bg-primary/10 text-primary"}`}
              >
                <PrimaryIcon className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <h2 className="text-foreground text-xl leading-tight font-bold sm:text-2xl">
                  {script.title}
                </h2>
                {/* Show description on mobile only */}
                <div className="mt-1 sm:hidden">
                  <div className="overflow-hidden">
                    <p
                      className={`text-muted-foreground text-sm leading-relaxed ${!isDescriptionExpanded && script.description.length > 120 ? "line-clamp-2" : ""}`}
                    >
                      {script.description}
                    </p>
                  </div>
                  {script.description.length > 120 && (
                    <button
                      onClick={() =>
                        setIsDescriptionExpanded(!isDescriptionExpanded)
                      }
                      className="text-primary hover:text-primary/80 mt-1 flex items-center gap-1 text-xs font-medium transition-colors"
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
            </div>

            {/* Action buttons */}
            <div className="flex items-center gap-2">
              {/* Open in new tab button */}
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  const url = `/script/${script.slug || script.id}`;
                  window.open(url, "_blank");
                }}
                className="h-8 w-8 shrink-0 rounded-full hover:bg-muted cursor-pointer"
                aria-label="Open in new tab"
                title="Open in new tab"
              >
                <ExternalLink className="h-4 w-4" />
              </Button>

              {/* Close button */}
              <Button
                variant="ghost"
                size="icon"
                onClick={onClose}
                className="h-8 w-8 shrink-0 rounded-full"
                aria-label="Close"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>

          {/* Tags row - mobile only */}
          <div className="mt-3 flex gap-2 overflow-x-auto pb-1 sm:hidden">
            {script.tags.map((tag) => {
              const TagIcon = tagIcons[tag];
              return (
                <Badge
                  key={tag}
                  variant="outline"
                  className={`gap-1.5 border px-2 py-1 text-xs font-medium whitespace-nowrap ${tagColors[tag]}`}
                >
                  <TagIcon className="h-3 w-3" />
                  {tag}
                </Badge>
              );
            })}
          </div>
        </div>

        {/* Main Content Area - Two Column Layout on Desktop */}
        <div className="flex flex-1 overflow-hidden">
          {/* Left Column - Metadata & Details (Desktop) / Full width (Mobile) */}
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
                  duration: 0.25,
                  ease: "easeInOut",
                }}
                className="flex flex-col overflow-hidden lg:w-1/3"
              >
                {/* Scrollable container for both mobile and desktop */}
                <div className="flex flex-1 flex-col overflow-hidden">
                  <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.1, duration: 0.3, ease: "easeOut" }}
                    className="flex flex-1 flex-col overflow-y-auto"
                  >
                    {/* Metadata Section */}
                    <div className="border-border/50 bg-card/95 shrink-0 border-b p-4 sm:p-6">
                      <div className="space-y-4">
                        {/* Description - desktop only */}
                        <div className="hidden sm:block">
                          <p className="text-muted-foreground text-sm leading-relaxed">
                            {script.description}
                          </p>
                        </div>

                        {/* Tags - desktop only */}
                        <div className="hidden gap-2 sm:flex sm:flex-wrap">
                          {script.tags.map((tag) => {
                            const TagIcon = tagIcons[tag];
                            return (
                              <Badge
                                key={tag}
                                variant="outline"
                                className={`gap-1.5 border px-2 py-1 text-xs font-medium ${tagColors[tag]}`}
                              >
                                <TagIcon className="h-3 w-3" />
                                {tag}
                              </Badge>
                            );
                          })}
                        </div>

                        {/* Essential info */}
                        <div className="text-muted-foreground space-y-2 text-sm">
                          <div className="flex items-center gap-2">
                            <Code className="h-4 w-4" />
                            <span>
                              {script.githubPath?.endsWith(".sh")
                                ? "Shell Script"
                                : "PowerShell Script"}
                            </span>
                          </div>
                          {script.testedPlatforms &&
                            script.testedPlatforms.length > 0 && (
                              <div className="flex items-center gap-2">
                                {script.testedPlatforms.includes("macOS") ? (
                                  <Apple className="h-4 w-4" />
                                ) : (
                                  <Monitor className="h-4 w-4" />
                                )}
                                <span>
                                  Platform: {script.testedPlatforms.join(", ")}
                                </span>
                              </div>
                            )}
                          {script.author && (
                            <div className="flex items-center gap-2">
                              <User className="h-4 w-4" />
                              <span>{script.author}</span>
                            </div>
                          )}
                          {script.version && (
                            <div className="flex items-center gap-2">
                              <Code className="h-4 w-4" />
                              <span>Version {script.version}</span>
                            </div>
                          )}
                          {script.minRole && (
                            <div className="flex items-center gap-2">
                              <User className="h-4 w-4" />
                              <span>Min Role: {script.minRole}</span>
                            </div>
                          )}
                        </div>

                        {/* Permissions */}
                        <div className="bg-muted/50 rounded-lg p-3">
                          <div className="mb-2 flex items-center gap-2">
                            <Key className="text-muted-foreground h-4 w-4" />
                            <h3 className="text-sm font-medium">
                              Required Permissions
                            </h3>
                          </div>
                          <p className="text-muted-foreground text-xs leading-relaxed">
                            {script.permissions?.join(", ") ||
                              "DeviceManagement.Read.All"}
                          </p>
                        </div>

                        {/* Action Buttons */}
                        <div className="flex flex-col gap-2 sm:flex-row">
                          <Button
                            variant="default"
                            size="sm"
                            className="h-10 w-full gap-2 text-sm sm:h-9 sm:flex-1"
                            asChild
                          >
                            <a
                              href={githubUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              onClick={handleGitHubClick}
                            >
                              <Github className="h-4 w-4" />
                              <span className="sm:hidden">View on GitHub</span>
                              <span className="hidden sm:inline">GitHub</span>
                              <ExternalLink className="h-3 w-3" />
                            </a>
                          </Button>

                          {!script.githubPath?.endsWith(".sh") &&
                            script.scriptType !== "remediation" && (
                              <Button
                                variant="secondary"
                                size="sm"
                                className="h-10 w-full cursor-pointer gap-2 border-[#0078d4] bg-[#0078d4] text-sm text-white hover:border-[#106ebe] hover:bg-[#106ebe] sm:h-9 sm:flex-1"
                                onClick={handleDeployToAzure}
                                disabled={isDeployingToAzure}
                              >
                                {isDeployingToAzure ? (
                                  <>
                                    <Cloud className="h-4 w-4 animate-pulse" />
                                    <span className="sm:hidden">
                                      Deploying to Azure...
                                    </span>
                                    <span className="hidden sm:inline">
                                      Deploying...
                                    </span>
                                  </>
                                ) : (
                                  <>
                                    <Cloud className="h-4 w-4" />
                                    <span>Deploy to Azure</span>
                                  </>
                                )}
                              </Button>
                            )}

                          <Button
                            variant="outline"
                            size="sm"
                            className="h-10 w-full cursor-pointer gap-2 text-sm sm:h-9 sm:flex-1"
                            onClick={handleDownloadScript}
                            disabled={downloaded}
                          >
                            {downloaded ? (
                              <>
                                <Check className="h-4 w-4 text-green-600" />
                                <span>
                                  {script.scriptType === "remediation"
                                    ? "Scripts Downloaded!"
                                    : "Downloaded!"}
                                </span>
                              </>
                            ) : (
                              <>
                                <Download className="h-4 w-4" />
                                <span>
                                  {script.scriptType === "remediation"
                                    ? "Download Both"
                                    : "Download"}
                                </span>
                              </>
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>

                    {/* Details Section - now part of the same scrollable container */}
                    <div className="p-4 sm:p-6">
                      <div className="space-y-4">
                        {/* Script Test Results */}
                        {script.testResult && (
                          <div className="bg-muted/50 rounded-lg p-4">
                            <div className="mb-3 flex items-center gap-2">
                              <TestTube className="text-muted-foreground h-4 w-4" />
                              <h3 className="text-sm font-medium">
                                Test Results
                              </h3>
                            </div>
                            <Badge
                              variant="outline"
                              className={`mb-3 gap-1.5 border px-2.5 py-1 text-xs font-medium ${testResultColors[script.testResult.result] || testResultColors.fail}`}
                            >
                              {React.createElement(
                                testResultIcons[script.testResult.result] ||
                                  testResultIcons.fail,
                                { className: "h-3 w-3" },
                              )}
                              {script.testResult.result === "pass"
                                ? "All Tests Passed"
                                : script.testResult.result === "fail"
                                  ? "Tests Failed"
                                  : "Warnings Found"}
                            </Badge>
                            <p className="text-muted-foreground text-xs leading-relaxed">
                              {script.testResult.result === "pass"
                                ? script.githubPath?.endsWith(".sh")
                                  ? "This script has passed all ShellCheck quality checks and follows shell scripting best practices."
                                  : "This script has passed all PSScriptAnalyzer quality checks and follows PowerShell best practices."
                                : script.testResult.result === "fail"
                                  ? "This script has some issues that need to be addressed. Please review the code carefully."
                                  : "This script has minor warnings but is generally safe to use."}
                            </p>
                            <div className="text-muted-foreground mt-2 flex items-center gap-1 text-xs">
                              <Clock className="h-3 w-3" />
                              <span>Tested {script.testResult.timestamp}</span>
                            </div>
                          </div>
                        )}

                        {/* Changelog */}
                        {script.changelog && script.changelog.length > 0 && (
                          <div className="bg-muted/50 rounded-lg p-4">
                            <div className="mb-3 flex items-center gap-2">
                              <History className="text-muted-foreground h-4 w-4" />
                              <h3 className="text-sm font-medium">Changelog</h3>
                            </div>
                            <div className="space-y-2">
                              {script.changelog.map((entry, index) => (
                                <div
                                  key={index}
                                  className="text-muted-foreground bg-background/50 rounded-md p-2 text-xs leading-relaxed"
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

          {/* Right Column - Code Section (Desktop) / Hidden (Mobile on small screens) */}
          <motion.div
            initial={false}
            animate={{
              width: isDesktop ? (isSidebarCollapsed ? "100%" : "60%") : "100%",
            }}
            transition={{ duration: 0.3, ease: "easeInOut" }}
            className={`border-border/50 hidden flex-col overflow-hidden sm:flex ${
              !isSidebarCollapsed ? "border-l" : ""
            } lg:w-2/3`}
          >
            {/* Code header */}
            <div className="border-border bg-muted/30 flex shrink-0 items-center justify-between border-b px-4 py-3">
              <div className="flex items-center gap-2">
                <Code className="text-muted-foreground h-4 w-4" />
                <span className="text-muted-foreground text-sm font-medium">
                  {script.id}.
                  {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                </span>
                {/* Sidebar toggle buttons - desktop only */}
                {isDesktop && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setIsSidebarCollapsed(!isSidebarCollapsed)}
                    className="ml-4 h-8 gap-2 px-3 text-xs font-medium"
                    aria-label={
                      isSidebarCollapsed ? "Show sidebar" : "Hide sidebar"
                    }
                  >
                    {isSidebarCollapsed ? (
                      <>
                        <Info className="h-3 w-3" />
                        <span>Show Details</span>
                      </>
                    ) : (
                      <>
                        <ChevronDown className="h-3 w-3" />
                        <span>Hide Details</span>
                      </>
                    )}
                  </Button>
                )}
              </div>
              <Button
                variant={copied === "script" ? "default" : "outline"}
                size="sm"
                className={`gap-2 text-sm font-medium transition-all ${
                  copied === "script"
                    ? "bg-green-600 text-white hover:bg-green-700"
                    : "hover:bg-muted"
                }`}
                onClick={handleCopyScript}
                disabled={copied === "script"}
              >
                {copied === "script" ? (
                  <>
                    <Check className="h-4 w-4" />
                    <span>Copied!</span>
                  </>
                ) : (
                  <>
                    <Copy className="h-4 w-4" />
                    <span>Copy Script</span>
                  </>
                )}
              </Button>
            </div>

            {/* Code content */}
            {script.scriptType === "remediation" && script.remediationPair ? (
              <Tabs
                value={activeRemediationTab}
                onValueChange={(value) =>
                  setActiveRemediationTab(value as "detection" | "remediation")
                }
                className="flex flex-1 flex-col overflow-hidden"
              >
                <TabsList className="grid w-full grid-cols-2 rounded-none border-b">
                  <TabsTrigger value="detection" className="rounded-none">
                    Detection Script
                  </TabsTrigger>
                  <TabsTrigger value="remediation" className="rounded-none">
                    Remediation Script
                  </TabsTrigger>
                </TabsList>
                <TabsContent
                  value="detection"
                  className="m-0 flex-1 overflow-auto"
                >
                  <div className="bg-muted/20 h-full">
                    <pre
                      className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 text-sm leading-relaxed`}
                      ref={
                        activeRemediationTab === "detection"
                          ? codeRef
                          : undefined
                      }
                    >
                      <code>{script.remediationPair.detection.code}</code>
                    </pre>
                  </div>
                </TabsContent>
                <TabsContent
                  value="remediation"
                  className="m-0 flex-1 overflow-auto"
                >
                  <div className="bg-muted/20 h-full">
                    <pre
                      className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 text-sm leading-relaxed`}
                      ref={
                        activeRemediationTab === "remediation"
                          ? codeRef
                          : undefined
                      }
                    >
                      <code>{script.remediationPair.remediation.code}</code>
                    </pre>
                  </div>
                </TabsContent>
              </Tabs>
            ) : (
              <div className="bg-muted/20 flex-1 overflow-auto">
                <pre
                  className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} h-full p-6 text-sm leading-relaxed`}
                  ref={codeRef}
                >
                  <code>{script.code}</code>
                </pre>
              </div>
            )}
          </motion.div>
        </div>

        {/* Mobile Code Section - Full width at bottom */}
        <div className="flex flex-col overflow-hidden sm:hidden">
          <div className="border-border/50 bg-card/95 shrink-0 border-t p-3">
            <Button
              variant="outline"
              size="sm"
              className="h-10 w-full gap-2"
              onClick={() => setShowDetails(!showDetails)}
            >
              <Code className="h-4 w-4" />
              <span>{showDetails ? "Hide" : "View"} Script</span>
              {showDetails ? (
                <ChevronUp className="h-4 w-4" />
              ) : (
                <ChevronDown className="h-4 w-4" />
              )}
            </Button>
          </div>

          <AnimatePresence>
            {showDetails && (
              <motion.div
                initial={{ height: 0 }}
                animate={{ height: "50vh" }}
                exit={{ height: 0 }}
                transition={{ duration: 0.3 }}
                className="border-border/50 overflow-hidden border-t"
              >
                <div className="bg-muted/30 flex items-center justify-between border-b px-3 py-2">
                  <div className="flex items-center gap-2">
                    <Code className="text-muted-foreground h-3 w-3" />
                    <span className="text-muted-foreground text-xs font-medium">
                      {script.id}.
                      {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                    </span>
                  </div>
                  <Button
                    variant={copied === "script" ? "default" : "secondary"}
                    size="sm"
                    className={`h-7 gap-1.5 px-2.5 text-xs ${
                      copied === "script" ? "bg-green-600 text-white" : ""
                    }`}
                    onClick={handleCopyScript}
                    disabled={copied === "script"}
                  >
                    {copied === "script" ? (
                      <>
                        <Check className="h-3 w-3" />
                        <span>Copied!</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-3 w-3" />
                        <span>Copy</span>
                      </>
                    )}
                  </Button>
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
                    <TabsList className="grid w-full grid-cols-2 rounded-none border-b">
                      <TabsTrigger
                        value="detection"
                        className="rounded-none text-xs"
                      >
                        Detection
                      </TabsTrigger>
                      <TabsTrigger
                        value="remediation"
                        className="rounded-none text-xs"
                      >
                        Remediation
                      </TabsTrigger>
                    </TabsList>
                    <TabsContent
                      value="detection"
                      className="m-0 flex-1 overflow-auto"
                    >
                      <div className="bg-muted/20 h-full">
                        <pre
                          className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 text-xs leading-relaxed`}
                          ref={
                            activeRemediationTab === "detection"
                              ? codeRef
                              : undefined
                          }
                        >
                          <code>{script.remediationPair.detection.code}</code>
                        </pre>
                      </div>
                    </TabsContent>
                    <TabsContent
                      value="remediation"
                      className="m-0 flex-1 overflow-auto"
                    >
                      <div className="bg-muted/20 h-full">
                        <pre
                          className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 text-xs leading-relaxed`}
                          ref={
                            activeRemediationTab === "remediation"
                              ? codeRef
                              : undefined
                          }
                        >
                          <code>{script.remediationPair.remediation.code}</code>
                        </pre>
                      </div>
                    </TabsContent>
                  </Tabs>
                ) : (
                  <div className="bg-muted/20 h-full overflow-auto">
                    <pre
                      className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-3 text-xs leading-relaxed`}
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
