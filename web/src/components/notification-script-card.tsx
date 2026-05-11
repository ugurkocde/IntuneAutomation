"use client";
import React from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { Badge } from "~/components/ui/badge";
import { useAnalyticsContext } from "~/components/analytics-provider";
import {
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
  Apple,
  AppWindow,
  Activity,
  Bell,
  Mail,
  CloudLightning,
} from "lucide-react";

interface EnhancedScriptCardProps {
  script: Script;
  onClick: () => void;
}

// Updated icon mapping to include Notification
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

// Updated color mapping to include Notification
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

// Utility function to get file extension from githubPath
const getFileExtension = (path?: string): string => {
  if (!path) return "";
  const lastDot = path.lastIndexOf(".");
  return lastDot > 0 ? path.substring(lastDot) : "";
};

// Utility function to get script type info based on file extension
const getScriptTypeInfo = (extension: string) => {
  switch (extension) {
    case ".ps1":
      return {
        icon: AppWindow,
        text: "PowerShell Script",
      };
    case ".sh":
      return {
        icon: Apple,
        text: "Shell Script",
      };
    default:
      return {
        icon: Code2,
        text: "PowerShell Script",
      };
  }
};

export function NotificationScriptCard({
  script,
  onClick,
}: EnhancedScriptCardProps) {
  const primaryTag = script.tags[0];
  const PrimaryIcon = primaryTag ? tagIcons[primaryTag] : Code2;
  const scriptUrl = `/script/${script.id}`;

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

  // Get script type info based on file extension
  const fileExtension = getFileExtension(script.githubPath);
  const scriptTypeInfo = getScriptTypeInfo(fileExtension);

  const handleClick = (e: React.MouseEvent) => {
    // Allow cmd/ctrl+click for opening in new tab
    if (e.metaKey || e.ctrlKey) {
      return; // Let the Link handle it
    }
    e.preventDefault();
    onClick();
  };

  // Check if this is a macOS-specific script
  const isMacOS = script.testedPlatforms?.some(
    (platform) =>
      platform.toLowerCase().includes("macos") ||
      platform.toLowerCase().includes("mac os"),
  );

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
          className={`bg-card hover:border-primary/30 relative flex h-full min-h-[280px] flex-col overflow-hidden rounded-2xl border p-5 shadow-sm transition-all duration-200 ease-out hover:shadow-lg ${
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
            <div className="mb-3 flex items-center justify-between">
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
                  {primaryTag && (
                    <Badge
                      variant="outline"
                      className={`border text-xs font-medium ${tagColors[primaryTag]}`}
                    >
                      {primaryTag}
                    </Badge>
                  )}
                  {isMacOS && (
                    <Badge
                      variant="outline"
                      className="border-gray-300 bg-gray-50 text-gray-700 dark:border-gray-700 dark:bg-gray-950/50 dark:text-gray-300"
                    >
                      <Apple className="mr-1 h-3 w-3" />
                      macOS
                    </Badge>
                  )}
                  {isNotification && (
                    <>
                      <Badge
                        variant="outline"
                        className="border-violet-300 bg-violet-50 text-violet-700 dark:border-violet-700 dark:bg-violet-950/50 dark:text-violet-300"
                      >
                        <CloudLightning className="mr-1 h-3 w-3" />
                        Runbook Only
                      </Badge>
                      {isEmail && (
                        <Badge
                          variant="outline"
                          className="border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-700 dark:bg-blue-950/50 dark:text-blue-300"
                        >
                          <Mail className="mr-1 h-3 w-3" />
                          Email
                        </Badge>
                      )}
                    </>
                  )}
                </div>
              </div>
              <ArrowRight
                className="text-muted-foreground/50 group-hover:text-primary h-4 w-4 transition-all duration-200 group-hover:translate-x-1"
                style={{ willChange: "transform, color" }}
              />
            </div>

            {/* Title */}
            <h3 className="group-hover:text-primary mb-2 line-clamp-2 text-lg font-bold transition-colors duration-200">
              {script.title}
            </h3>

            {/* Description */}
            <p className="text-muted-foreground mb-3 line-clamp-3 text-sm leading-relaxed">
              {script.description}
            </p>

            {/* Footer metadata */}
            <div className="text-muted-foreground border-border/50 mt-auto border-t pt-3 text-xs">
              <div className="flex items-center justify-between">
                {/* Left side: Usage stats */}
                {usageStats && (
                  <div className="flex items-center gap-4">
                    <div className="flex items-center gap-1">
                      <Eye className="h-3 w-3" />
                      <span className="font-medium">
                        {formatCompactNumber(usageStats.totalViews)}
                      </span>
                      <span className="text-muted-foreground/70">views</span>
                      {usageStats.weeklyViews > 0 && (
                        <span className="ml-1 text-[10px] font-medium text-green-600 dark:text-green-400">
                          +{usageStats.weeklyViews}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-1">
                      <Download className="h-3 w-3" />
                      <span className="font-medium">
                        {formatCompactNumber(usageStats.totalDownloads)}
                      </span>
                      {usageStats.weeklyDownloads > 0 && (
                        <span className="ml-1 text-[10px] font-medium text-green-600 dark:text-green-400">
                          +{usageStats.weeklyDownloads}
                        </span>
                      )}
                    </div>
                  </div>
                )}

                {/* Right side: Test result badge */}
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
