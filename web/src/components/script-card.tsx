"use client";
import React from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { Badge } from "~/components/ui/badge";
import { useAnalyticsContext } from "~/components/analytics-provider";
import {
  Calendar,
  Code2,
  Shield,
  Smartphone,
  CheckCircle,
  Package,
  BarChart3,
  Stethoscope,
  Settings,
  ArrowRight,
  Cog,
  AlertTriangle,
  XCircle,
  Eye,
  Download,
  Activity,
  Bell,
  Mail,
  CloudLightning,
  Monitor,
  Apple,
  Copy,
  ExternalLink,
  Cloud,
  MoreHorizontal,
} from "lucide-react";

interface ScriptCardProps {
  script: Script;
  onClick: () => void;
}

// Icon mapping for each tag (same as in tag-filter)
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
    "text-amber-600 bg-amber-50 border-amber-200 dark:text-amber-400 dark:bg-amber-950/50 dark:border-amber-800/50",
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

// Utility function to format numbers compactly
const formatCompactNumber = (num: number): string => {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + "M";
  if (num >= 10000) return (num / 1000).toFixed(1) + "k";
  return num.toString();
};

export function ScriptCard({ script, onClick }: ScriptCardProps) {
  const [showActions, setShowActions] = React.useState(false);
  const [copiedScript, setCopiedScript] = React.useState(false);
  const menuRef = React.useRef<HTMLDivElement>(null);

  const primaryTag = script.tags[0];
  const PrimaryIcon = primaryTag ? tagIcons[primaryTag] : Code2;
  const scriptUrl = `/script/${script.id}`;

  // Close menu when clicking outside
  React.useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setShowActions(false);
      }
    };

    if (showActions) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => {
        document.removeEventListener("mousedown", handleClickOutside);
      };
    }
  }, [showActions]);

  // Get analytics from centralized context
  const { getAnalytics } = useAnalyticsContext();
  const analytics = getAnalytics(script.id);

  // Use real-time analytics if available, otherwise fall back to script's cached data
  const usageStats = analytics || script.usageStats;

  // Check if this is a notification script
  const isNotification =
    script.execution === "RunbookOnly" ||
    script.category === "notification" ||
    script.tags.includes("Notification" as ScriptTag);

  const isEmail = script.output === "Email";
  const schedule = script.schedule || (isNotification ? "Daily" : "OnDemand");

  const handleClick = (e: React.MouseEvent) => {
    // Allow cmd/ctrl+click for opening in new tab
    if (e.metaKey || e.ctrlKey) {
      return; // Let the Link handle it
    }
    e.preventDefault();
    onClick();
  };

  const handleCopyScript = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(script.code);
      setCopiedScript(true);
      setTimeout(() => setCopiedScript(false), 2000);
    } catch (error) {
      console.error("Failed to copy:", error);
    }
  };

  const handleDeployToAzure = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();

    try {
      // Fetch the pre-generated Azure deployment templates registry
      const templatesResponse = await fetch(
        "https://raw.githubusercontent.com/ugurkocde/IntuneAutomation/main/azure-deployment-templates.json",
      );

      if (!templatesResponse.ok) {
        throw new Error("Failed to fetch Azure deployment templates");
      }

      const templatesRegistry = (await templatesResponse.json()) as {
        templates: Record<string, { deployUrl: string }>;
      };
      const templateInfo = templatesRegistry.templates[script.id];

      if (!templateInfo) {
        throw new Error("Azure deployment template not found for this script");
      }

      // Open Azure portal with the pre-generated deployment URL
      window.open(templateInfo.deployUrl, "_blank");
    } catch (error) {
      console.error("Azure deployment failed:", error);
      // Fallback to script detail page
      window.location.href = scriptUrl;
    }
  };

  const handleViewDetails = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    window.location.href = scriptUrl;
  };

  return (
    <motion.div
      whileHover={{ y: -4 }}
      whileTap={{ scale: 0.98 }}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", damping: 25, stiffness: 400, mass: 0.5 }}
      className="group"
      style={{ willChange: "transform" }}
    >
      <Link
        href={scriptUrl}
        onClick={handleClick}
        className="block cursor-pointer"
      >
        <div
          className={`bg-card hover:border-primary/30 relative flex h-full cursor-pointer flex-col overflow-hidden rounded-2xl border p-6 shadow-sm transition-all duration-200 ease-out hover:shadow-lg ${
            isNotification ? "notification-script-card" : ""
          }`}
          style={{ willChange: "transform, box-shadow, border-color" }}
        >
          {/* Special background for notification scripts */}
          {isNotification ? (
            <div className="absolute inset-0 bg-gradient-to-br from-violet-500/5 to-indigo-500/5 opacity-100" />
          ) : (
            <div className="from-primary/5 to-secondary/5 absolute inset-0 bg-gradient-to-br opacity-0 transition-opacity duration-200 group-hover:opacity-100" />
          )}

          {/* Content */}
          <div className="relative z-10 flex h-full flex-col">
            {/* Header with icon, primary tag, and badges */}
            <div className="mb-4 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div
                  className={`rounded-xl p-2.5 transition-transform duration-200 group-hover:scale-105 ${
                    isNotification
                      ? "bg-gradient-to-br from-violet-500/20 to-indigo-500/20 text-violet-600 dark:text-violet-400"
                      : primaryTag
                        ? tagColors[primaryTag]
                        : "bg-primary/10 text-primary"
                  }`}
                  style={{ willChange: "transform" }}
                >
                  {isNotification ? (
                    <Bell className="h-5 w-5" />
                  ) : (
                    <PrimaryIcon className="h-5 w-5" />
                  )}
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {/* Show max 2 badges - prioritize most important */}
                  {isNotification ? (
                    <Badge
                      variant="outline"
                      className="border-violet-300 bg-violet-50 text-violet-700 dark:border-violet-700 dark:bg-violet-950/50 dark:text-violet-300"
                    >
                      <CloudLightning className="mr-1 h-3 w-3" />
                      Runbook
                    </Badge>
                  ) : script.scriptType === "remediation" ? (
                    <Badge
                      variant="outline"
                      className="border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300"
                    >
                      <Settings className="mr-1 h-3 w-3" />
                      Remediation
                    </Badge>
                  ) : (
                    primaryTag && (
                      <Badge
                        variant="outline"
                        className={`border text-xs font-medium ${tagColors[primaryTag]}`}
                      >
                        {primaryTag}
                      </Badge>
                    )
                  )}

                  {/* Show weekly activity badge if there's activity */}
                  {usageStats && (usageStats.weeklyViews > 10 || usageStats.weeklyDownloads > 5) && (
                    <Badge
                      variant="outline"
                      className="border-green-300 bg-green-50 text-green-700 dark:border-green-700 dark:bg-green-950/50 dark:text-green-300"
                    >
                      <Activity className="mr-1 h-3 w-3" />
                      Trending
                    </Badge>
                  )}
                </div>
              </div>

              {/* Quick Actions Menu */}
              <div className="relative" ref={menuRef}>
                <button
                  onClick={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    setShowActions(!showActions);
                  }}
                  className="text-muted-foreground hover:text-foreground cursor-pointer rounded-lg p-2 opacity-0 transition-all duration-200 group-hover:opacity-100 hover:bg-gray-100 dark:hover:bg-gray-800"
                  aria-label="Quick actions"
                >
                  <MoreHorizontal className="h-4 w-4" />
                </button>

                {/* Actions Dropdown */}
                {showActions && (
                  <div className="absolute right-0 top-full z-50 mt-2 w-48 rounded-lg border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-800">
                    <button
                      onClick={handleCopyScript}
                      className="flex w-full cursor-pointer items-center gap-2 rounded-t-lg px-4 py-2.5 text-left text-sm transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
                    >
                      <Copy className="h-4 w-4" />
                      {copiedScript ? "Copied!" : "Copy Script"}
                    </button>
                    <button
                      onClick={handleViewDetails}
                      className="flex w-full cursor-pointer items-center gap-2 px-4 py-2.5 text-left text-sm transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
                    >
                      <ExternalLink className="h-4 w-4" />
                      View Details
                    </button>
                    <button
                      onClick={handleDeployToAzure}
                      className="flex w-full cursor-pointer items-center gap-2 rounded-b-lg px-4 py-2.5 text-left text-sm transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
                    >
                      <Cloud className="h-4 w-4" />
                      Deploy to Azure
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* Title */}
            <h3 className="group-hover:text-primary mb-3 line-clamp-2 text-xl font-bold transition-colors duration-200">
              {script.title}
            </h3>

            {/* Description */}
            <p className="text-muted-foreground mb-4 line-clamp-3 flex-grow text-sm leading-relaxed">
              {script.description}
            </p>

            {/* Schedule info for notification scripts */}
            {isNotification && schedule !== "OnDemand" && (
              <div className="mb-4 flex items-center gap-2 text-sm text-violet-600 dark:text-violet-400">
                <Calendar className="h-4 w-4" />
                <span>Runs: {schedule}</span>
              </div>
            )}

            {/* Footer metadata */}
            <div className="text-muted-foreground border-border/50 mt-auto space-y-3 border-t pt-4 text-xs">
              {/* Usage Stats Row */}
              {usageStats && (
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="flex items-center gap-1.5">
                      <Eye className="h-3.5 w-3.5" />
                      <span className="font-semibold">
                        {formatCompactNumber(usageStats.totalViews)}
                      </span>
                      {usageStats.weeklyViews > 0 && (
                        <Badge
                          variant="outline"
                          className="ml-1 border-green-300 bg-green-50 px-1.5 py-0 text-[10px] font-semibold text-green-700 dark:border-green-700 dark:bg-green-950/50 dark:text-green-400"
                        >
                          +{usageStats.weeklyViews}
                        </Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-1.5">
                      <Download className="h-3.5 w-3.5" />
                      <span className="font-semibold">
                        {formatCompactNumber(usageStats.totalDownloads)}
                      </span>
                      {usageStats.weeklyDownloads > 0 && (
                        <Badge
                          variant="outline"
                          className="ml-1 border-green-300 bg-green-50 px-1.5 py-0 text-[10px] font-semibold text-green-700 dark:border-green-700 dark:bg-green-950/50 dark:text-green-400"
                        >
                          +{usageStats.weeklyDownloads}
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* Test result and platform row */}
              <div className="flex items-center justify-between">
                {/* Platform badges */}
                {script.testedPlatforms &&
                  script.testedPlatforms.length > 0 && (
                    <div className="flex items-center gap-2">
                      {script.testedPlatforms.includes("macOS") && (
                        <Badge
                          variant="outline"
                          className="gap-1 border border-gray-300 bg-gray-50 text-xs font-medium text-gray-700 dark:border-gray-700 dark:bg-gray-950/50 dark:text-gray-300"
                        >
                          <Apple className="h-3 w-3" />
                          macOS
                        </Badge>
                      )}
                      {(script.testedPlatforms.includes("Windows") ||
                        script.testedPlatforms.includes("Windows 10") ||
                        script.testedPlatforms.includes("Windows 11")) && (
                        <Badge
                          variant="outline"
                          className="gap-1 border border-blue-300 bg-blue-50 text-xs font-medium text-blue-700 dark:border-blue-700 dark:bg-blue-950/50 dark:text-blue-300"
                        >
                          <Monitor className="h-3 w-3" />
                          Windows
                        </Badge>
                      )}
                    </div>
                  )}

                {/* Test result badge */}
                {script.testResult && (
                  <Badge
                    variant="outline"
                    className={`gap-1 border text-xs font-medium ${testResultColors[script.testResult.result] || testResultColors.fail}`}
                  >
                    {React.createElement(
                      testResultIcons[script.testResult.result] ||
                        testResultIcons.fail,
                      { className: "h-3 w-3" },
                    )}
                    {script.testResult.result === "pass"
                      ? "Tested"
                      : script.testResult.result}
                  </Badge>
                )}
              </div>
            </div>
          </div>
        </div>
      </Link>
    </motion.div>
  );
}
