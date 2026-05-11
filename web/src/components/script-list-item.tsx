"use client";
import React from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import type { Script, ScriptTag } from "~/lib/scripts";
import { Badge } from "~/components/ui/badge";
import { useAnalyticsContext } from "~/components/analytics-provider";
import { VerifiedBadge } from "~/components/verified-badge";
import {
  Code2,
  Shield,
  Smartphone,
  CheckCircle,
  Package,
  BarChart3,
  Stethoscope,
  Settings,
  Clock,
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
} from "lucide-react";

interface ScriptListItemProps {
  script: Script;
  onClick: () => void;
}

// Icon mapping for each tag (same as in script-card)
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

export function ScriptListItem({ script, onClick }: ScriptListItemProps) {
  const primaryTag = script.tags[0];
  const PrimaryIcon = primaryTag ? tagIcons[primaryTag] : Code2;
  const scriptUrl = `/script/${script.id}`;

  // Get analytics from centralized context
  const { getAnalytics } = useAnalyticsContext();
  const analytics = getAnalytics(script.id);

  // Use real-time analytics if available, otherwise fall back to script's cached data
  const usageStats = analytics || script.usageStats;

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

  return (
    <motion.div
      whileHover={{ scale: 1.01, y: -1 }}
      whileTap={{ scale: 0.99 }}
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
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
          className="bg-card hover:border-primary/30 relative overflow-hidden rounded-xl border p-4 shadow-sm transition-all duration-200 ease-out hover:shadow-md"
          style={{ willChange: "transform, box-shadow, border-color" }}
        >
          {/* Simplified background overlay */}
          <div className="from-primary/5 to-secondary/5 absolute inset-0 bg-gradient-to-r opacity-0 transition-opacity duration-200 group-hover:opacity-100" />

          {/* Mobile Layout (< md) */}
          <div className="relative z-10 flex flex-col gap-3 md:hidden">
            {/* Header Row - Icon, Title, Arrow */}
            <div className="flex items-center gap-3">
              <div
                className={`shrink-0 rounded-lg p-2 transition-transform duration-200 group-hover:scale-105 ${primaryTag ? tagColors[primaryTag] : "bg-primary/10 text-primary"}`}
                style={{ willChange: "transform" }}
              >
                <PrimaryIcon className="h-4 w-4" />
              </div>
              <h3 className="group-hover:text-primary line-clamp-1 min-w-0 flex-1 text-base font-semibold transition-colors duration-200">
                {script.title}
              </h3>
              <ArrowRight
                className="text-muted-foreground/50 group-hover:text-primary h-4 w-4 shrink-0 transition-all duration-200 group-hover:translate-x-1"
                style={{ willChange: "transform, color" }}
              />
            </div>

            {/* Description */}
            <p className="text-muted-foreground line-clamp-2 text-sm leading-relaxed">
              {script.description}
            </p>

            {/* Bottom Row - Tags and Stats */}
            <div className="flex items-center justify-between gap-3">
              {/* Primary Tag */}
              <div className="flex gap-1">
                {primaryTag && (
                  <Badge
                    variant="outline"
                    className={`text-xs ${tagColors[primaryTag]}`}
                  >
                    {primaryTag}
                  </Badge>
                )}
                {script.tags.length > 1 && (
                  <Badge variant="outline" className="text-xs">
                    +{script.tags.length - 1}
                  </Badge>
                )}
              </div>

              {/* Compact Stats */}
              {usageStats && (
                <div className="flex items-center gap-3 text-xs">
                  <div className="flex items-center gap-1">
                    <Eye className="h-3 w-3" />
                    <span className="font-medium">
                      {formatCompactNumber(usageStats.totalViews)}
                    </span>
                    {usageStats.weeklyViews > 0 && (
                      <span className="text-[10px] font-medium text-green-600 dark:text-green-400">
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
                      <span className="text-[10px] font-medium text-green-600 dark:text-green-400">
                        +{usageStats.weeklyDownloads}
                      </span>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Desktop Layout (>= md) */}
          <div className="relative z-10 hidden w-full items-center gap-6 md:flex">
            {/* Icon and Primary Tag */}
            <div className="flex items-center gap-3">
              <div
                className={`rounded-lg p-2 transition-transform duration-200 group-hover:scale-105 ${primaryTag ? tagColors[primaryTag] : "bg-primary/10 text-primary"}`}
                style={{ willChange: "transform" }}
              >
                <PrimaryIcon className="h-4 w-4" />
              </div>
            </div>

            {/* Main Content */}
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              {/* Title and Description */}
              <div className="flex min-w-0 flex-1 flex-col gap-1">
                <h3 className="group-hover:text-primary line-clamp-1 text-lg font-semibold transition-colors duration-200">
                  {script.title}
                </h3>
                <p className="text-muted-foreground line-clamp-2 text-sm leading-relaxed">
                  {script.description}
                </p>
              </div>

              {/* Tags */}
              <div className="flex flex-wrap gap-1">
                {script.tags.slice(0, 3).map((tag) => (
                  <Badge
                    key={tag}
                    variant="outline"
                    className={`text-xs ${tagColors[tag]}`}
                  >
                    {tag}
                  </Badge>
                ))}
                {script.tags.length > 3 && (
                  <Badge variant="outline" className="text-xs">
                    +{script.tags.length - 3} more
                  </Badge>
                )}
              </div>
            </div>

            {/* Stats and Metadata */}
            <div className="flex flex-col items-end gap-2 text-xs">
              {/* Usage Stats */}
              {usageStats && (
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-1">
                    <Eye className="h-3 w-3" />
                    <span className="font-medium">
                      {formatCompactNumber(usageStats.totalViews)}
                    </span>
                    {usageStats.weeklyViews > 0 && (
                      <span className="text-[10px] font-medium text-green-600 dark:text-green-400">
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
                      <span className="text-[10px] font-medium text-green-600 dark:text-green-400">
                        +{usageStats.weeklyDownloads}
                      </span>
                    )}
                  </div>
                </div>
              )}

              {/* Metadata Row */}
              <div className="text-muted-foreground flex items-center gap-4">
                <div className="flex items-center gap-1">
                  {React.createElement(scriptTypeInfo.icon, {
                    className: "h-3 w-3",
                  })}
                  <span>{scriptTypeInfo.text}</span>
                </div>
                <VerifiedBadge script={script} />
              </div>
            </div>

            {/* Arrow */}
            <div className="flex items-center">
              <ArrowRight
                className="text-muted-foreground/50 group-hover:text-primary h-4 w-4 transition-all duration-200 group-hover:translate-x-1"
                style={{ willChange: "transform, color" }}
              />
            </div>
          </div>
        </div>
      </Link>
    </motion.div>
  );
}
