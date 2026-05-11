"use client";

import React, { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { type Script } from "~/lib/scripts";
import { Badge } from "~/components/ui/badge";
import { Button } from "~/components/ui/button";
import { useToast } from "~/hooks/use-toast";
import "prismjs/themes/prism-tomorrow.css";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "~/components/ui/tabs";
import {
  Code2,
  User,
  Shield,
  Smartphone,
  CheckCircle,
  Package,
  BarChart3,
  Stethoscope,
  Settings,
  Clock,
  Key,
  Github,
  Download,
  ExternalLink,
  ArrowLeft,
  Cog,
  AlertTriangle,
  XCircle,
  Cloud,
  Maximize2,
  Minimize2,
  Copy,
  Check,
} from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { Breadcrumb, type BreadcrumbItem } from "~/components/breadcrumb";
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

// Icon mapping for each tag
const tagIcons: Record<string, typeof Shield> = {
  Security: Shield,
  Devices: Smartphone,
  Compliance: CheckCircle,
  Apps: Package,
  Reporting: BarChart3,
  Diagnostics: Stethoscope,
  Configuration: Settings,
  Operational: Cog,
};

// Color mapping for each tag
const tagColors: Record<string, string> = {
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
    "text-amber-600 bg-amber-50 border-amber-200 dark:text-amber-400 dark:bg-amber-950/50 dark:border-amber-800/50",
};

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
  const PrimaryIcon = primaryTag ? tagIcons[primaryTag] || Code2 : Code2;
  const fileExtension = script.githubPath?.endsWith(".sh") ? "sh" : "ps1";
  const githubUrl =
    script.githubUrl ||
    `https://github.com/ugurkocde/IntuneAutomation/blob/main/${script.githubPath || `scripts/${script.id}.${fileExtension}`}`;

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

  return (
    <ScriptsProvider>
      <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
        <Navbar />
        <main className="flex-1 pt-20">
          <div className="container mx-auto max-w-4xl px-4 py-8">
            {/* Breadcrumb navigation */}
            <Breadcrumb
              items={[
                { name: "Home", href: "/" },
                { name: "Scripts", href: "/scripts/" },
                { name: script.title },
              ]}
              className="mb-6"
            />

            {/* Script header */}
            <div className="mb-8">
              <div className="mb-4 flex items-center gap-4">
                <div
                  className={`rounded-xl p-3 ${primaryTag ? tagColors[primaryTag] : "bg-primary/10 text-primary"}`}
                >
                  <PrimaryIcon className="h-6 w-6" />
                </div>
                <div>
                  <h1 className="mb-2 text-3xl font-bold">{script.title}</h1>
                  <p className="text-muted-foreground text-lg">
                    {script.description}
                  </p>
                </div>
              </div>

              {/* Tags */}
              <div className="mb-6 flex flex-wrap gap-2">
                {script.tags.map((tag) => {
                  const TagIcon = tagIcons[tag] || Code2;
                  return (
                    <Badge
                      key={tag}
                      variant="outline"
                      className={`gap-1.5 border px-3 py-1 text-sm font-medium ${tagColors[tag]}`}
                    >
                      <TagIcon className="h-4 w-4" />
                      {tag}
                    </Badge>
                  );
                })}
              </div>

              {/* Metadata */}
              <div className="text-muted-foreground mb-6 flex flex-wrap items-center gap-6 text-sm">
                {script.author && (
                  <div className="flex items-center gap-2">
                    <User className="h-4 w-4" />
                    <span>Author: {script.author}</span>
                  </div>
                )}
                {script.version && (
                  <div className="flex items-center gap-2">
                    <Code2 className="h-4 w-4" />
                    <span>Version: {script.version}</span>
                  </div>
                )}
              </div>

              {/* Test Results - per-tier panel when available, fallback to flat badge */}
              {script.tests ? (
                <QualityChecks tests={script.tests} />
              ) : (
                script.testResult && (
                  <div className="bg-muted/50 mb-6 rounded-lg p-4">
                    <div className="flex items-center gap-2">
                      <Badge
                        variant="outline"
                        className={`gap-2 border px-3 py-1 text-sm font-medium ${testResultColors[script.testResult.result] || testResultColors.fail}`}
                      >
                        {React.createElement(
                          testResultIcons[script.testResult.result] ||
                            testResultIcons.fail,
                          { className: "h-4 w-4" },
                        )}
                        {script.testResult.result === "pass"
                          ? "All Tests Passed"
                          : script.testResult.result === "fail"
                            ? "Tests Failed"
                            : "Warnings Found"}
                      </Badge>
                      <span className="text-muted-foreground text-sm">
                        Tested on {script.testResult.timestamp}
                      </span>
                    </div>
                  </div>
                )
              )}

              {/* Action buttons */}
              <div className="flex flex-wrap gap-3">
                <Button asChild>
                  <a href={githubUrl} target="_blank" rel="noopener noreferrer">
                    <Github className="mr-2 h-4 w-4" />
                    View on GitHub
                    <ExternalLink className="ml-2 h-3 w-3" />
                  </a>
                </Button>
                {!script.githubPath?.endsWith(".sh") &&
                  script.scriptType !== "remediation" && (
                    <Button
                      variant="secondary"
                      onClick={handleDeployToAzure}
                      disabled={isDeployingToAzure}
                      className="cursor-pointer border-[#0078d4] bg-[#0078d4] text-white hover:border-[#106ebe] hover:bg-[#106ebe]"
                    >
                      {isDeployingToAzure ? (
                        <>
                          <Cloud className="mr-2 h-4 w-4 animate-pulse" />
                          Deploying to Azure...
                        </>
                      ) : (
                        <>
                          <Cloud className="mr-2 h-4 w-4" />
                          Deploy to Azure
                        </>
                      )}
                    </Button>
                  )}
                <Button
                  variant="outline"
                  onClick={handleDownload}
                  className="cursor-pointer"
                >
                  <Download className="mr-2 h-4 w-4" />
                  {script.scriptType === "remediation"
                    ? "Download Both Scripts"
                    : "Download Script"}
                </Button>
              </div>
            </div>

            {/* Permissions section */}
            {script.permissions && script.permissions.length > 0 && (
              <div className="mb-8">
                <h2 className="mb-3 flex items-center gap-2 text-lg font-semibold">
                  <Key className="h-4 w-4" />
                  Required Permissions
                </h2>
                <div className="border-border bg-muted/30 rounded-lg border p-3">
                  <div className="space-y-2">
                    {script.permissions.map((permission, index) => {
                      const permissionInfo = permissionsData?.[permission];
                      return (
                        <div
                          key={permission}
                          className={`${index !== script.permissions!.length - 1 ? "border-border/50 border-b pb-2" : ""}`}
                        >
                          <code className="text-primary text-xs font-medium">
                            {permission}
                          </code>
                          {permissionInfo?.description && (
                            <p className="text-muted-foreground mt-0.5 text-xs leading-relaxed">
                              {permissionInfo.description}
                            </p>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              </div>
            )}

            {/* Code block */}
            <div
              className={`${isFullscreen ? "bg-background fixed inset-0 z-50" : "border-border bg-muted/50 overflow-hidden rounded-lg border"}`}
            >
              <div
                className={`${isFullscreen ? "border-b" : "border-border border-b"} bg-muted flex items-center justify-between px-4 py-2`}
              >
                <div className="flex items-center gap-2">
                  <Code2 className="text-muted-foreground h-4 w-4" />
                  <span className="text-muted-foreground text-sm font-medium">
                    {script.id}.
                    {script.githubPath?.endsWith(".sh") ? "sh" : "ps1"}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={handleCopyScript}
                    className="hover:bg-muted-foreground/10 h-8 cursor-pointer px-2 transition-colors"
                  >
                    {copied ? (
                      <>
                        <Check className="h-4 w-4 text-green-600" />
                        <span className="ml-2 text-xs">Copied!</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-4 w-4" />
                        <span className="ml-2 text-xs">Copy</span>
                      </>
                    )}
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={handleFullscreen}
                    className="hover:bg-muted-foreground/10 h-8 cursor-pointer px-2 transition-colors"
                  >
                    {isFullscreen ? (
                      <>
                        <Minimize2 className="h-4 w-4" />
                        <span className="ml-2 text-xs">Exit Fullscreen</span>
                      </>
                    ) : (
                      <>
                        <Maximize2 className="h-4 w-4" />
                        <span className="ml-2 text-xs">Fullscreen</span>
                      </>
                    )}
                  </Button>
                  <div className="ml-2 flex gap-1">
                    <div className="h-2 w-2 rounded-full bg-red-500/60" />
                    <div className="h-2 w-2 rounded-full bg-yellow-500/60" />
                    <div className="h-2 w-2 rounded-full bg-green-500/60" />
                  </div>
                </div>
              </div>
              {script.scriptType === "remediation" && script.remediationPair ? (
                <Tabs
                  value={activeRemediationTab}
                  onValueChange={(value) =>
                    setActiveRemediationTab(
                      value as "detection" | "remediation",
                    )
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
                  <div
                    className={`${isFullscreen ? "h-[calc(100vh-3.5rem-2.5rem)]" : "max-h-[560px]"} overflow-auto bg-[#2d2d2d]`}
                  >
                    <TabsContent value="detection" className="m-0">
                      <pre
                        ref={detectionCodeRef}
                        className={`${script.remediationPair.detection.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-sm leading-relaxed`}
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
                    </TabsContent>
                    <TabsContent value="remediation" className="m-0">
                      <pre
                        ref={remediationCodeRef}
                        className={`${script.remediationPair.remediation.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-sm leading-relaxed`}
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
                    </TabsContent>
                  </div>
                </Tabs>
              ) : (
                <div
                  className={`${isFullscreen ? "h-[calc(100vh-3.5rem)]" : "max-h-[600px]"} overflow-auto bg-[#2d2d2d]`}
                >
                  <pre
                    ref={codeRef}
                    className={`${script.githubPath?.endsWith(".sh") ? "language-bash" : "language-powershell"} p-6 text-sm leading-relaxed`}
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

            {/* Related scripts section */}
            {allScripts && allScripts.length > 1 && (
              <RelatedScripts
                currentScript={script}
                allScripts={allScripts}
                limit={3}
              />
            )}
          </div>

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
