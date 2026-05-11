"use client";

import type React from "react";
import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ScriptCard } from "~/components/script-card";
import { ScriptListItem } from "~/components/script-list-item";
import { ScriptDetail } from "~/components/script-detail";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import { type ScriptTag } from "~/lib/scripts";
import {
  Search,
  RefreshCw,
  AlertCircle,
  Github,
  ChevronLeft,
  ChevronRight,
  Grid2X2,
  List,
  ArrowUpDown,
  Eye,
  Calendar,
  Download as DownloadIcon,
  SortAsc,
  Package,
  Shield,
  Smartphone,
  CheckCircle,
  BarChart3,
  Stethoscope,
  Settings,
  Cog,
  Bell,
  AlertTriangle,
  Wrench,
} from "lucide-react";
import { Input } from "~/components/ui/input";
import { Button } from "~/components/ui/button";
import { Alert, AlertDescription } from "~/components/ui/alert";
import { Badge } from "~/components/ui/badge";

type SortOption = "views" | "recent" | "alphabetical" | "downloads";
type ViewMode = "grid" | "list";

interface TagScriptGalleryProps {
  tag: ScriptTag;
  description: string;
}

// Icon mapping for each tag
const tagIcons: Record<ScriptTag, React.ElementType> = {
  Security: Shield,
  Devices: Smartphone,
  Compliance: CheckCircle,
  Apps: Package,
  Reporting: BarChart3,
  Diagnostics: Stethoscope,
  Configuration: Settings,
  Operational: Cog,
  Monitoring: Eye,
  Notification: Bell,
  Remediation: Wrench,
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
    "text-rose-600 bg-rose-50 border-rose-200 dark:text-rose-400 dark:bg-rose-950/50 dark:border-rose-800/50",
};

export default function TagScriptGallery({
  tag,
  description,
}: TagScriptGalleryProps) {
  const {
    allScripts,
    selectedScript,
    setSelectedScript,
    isDetailOpen,
    setIsDetailOpen,
    isLoading,
    error,
    lastFetched,
    refetchScripts,
    updateScriptStats,
  } = useScripts();

  const [searchQuery, setSearchQuery] = useState("");
  const [sortBy, setSortBy] = useState<SortOption>("views");
  const [viewMode, setViewMode] = useState<ViewMode>("grid");
  const [currentPage, setCurrentPage] = useState(0);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

  // Filter scripts by tag
  const tagScripts = allScripts.filter((script) => script.tags.includes(tag));

  // Further filter by search query
  const filteredScripts = tagScripts.filter((script) => {
    if (!searchQuery) return true;
    const query = searchQuery.toLowerCase();
    return (
      script.title.toLowerCase().includes(query) ||
      script.description.toLowerCase().includes(query) ||
      script.tags.some((t) => t.toLowerCase().includes(query))
    );
  });

  // Pagination settings
  const scriptsPerPage = viewMode === "grid" ? 12 : 20;

  // Sort scripts based on selected option
  const sortedScripts = [...filteredScripts].sort((a, b) => {
    switch (sortBy) {
      case "views":
        const aViews = a.usageStats?.totalViews || 0;
        const bViews = b.usageStats?.totalViews || 0;
        return bViews - aViews;

      case "downloads":
        const aDownloads = a.usageStats?.totalDownloads || 0;
        const bDownloads = b.usageStats?.totalDownloads || 0;
        return bDownloads - aDownloads;

      case "recent":
        const aDate = new Date(a.lastUpdated || 0).getTime();
        const bDate = new Date(b.lastUpdated || 0).getTime();
        if (aDate === bDate) {
          return a.title.localeCompare(b.title);
        }
        return bDate - aDate;

      case "alphabetical":
        return a.title.localeCompare(b.title);

      default:
        return 0;
    }
  });

  const totalPages = Math.ceil(sortedScripts.length / scriptsPerPage);

  // Get current page scripts
  const currentScripts = sortedScripts.slice(
    currentPage * scriptsPerPage,
    (currentPage + 1) * scriptsPerPage,
  );

  // Reset to first page when filters change
  useEffect(() => {
    setCurrentPage(0);
  }, [searchQuery, sortBy]);

  const handleScriptClick = (script: any) => {
    // Update stats immediately in the UI for real-time feedback
    updateScriptStats(script.id, "view");

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
    });

    // Update URL to match the script page for better navigation
    window.history.pushState(null, "", `/script/${script.slug}`);

    setSelectedScript(script);
    setIsDetailOpen(true);
  };

  const TagIcon = tagIcons[tag];
  const tagColor = tagColors[tag];

  return (
    <section className="container mx-auto max-w-7xl px-4 py-16">
      <div className="mb-12">
        {/* Tag header */}
        <div className="mb-8 flex items-center gap-4">
          <div className={`rounded-xl p-3 ${tagColor}`}>
            <TagIcon className="h-8 w-8" />
          </div>
          <div>
            <h1 className="text-3xl font-bold">{tag} Scripts</h1>
            <p className="text-muted-foreground mt-2 max-w-3xl">
              {description}
            </p>
          </div>
        </div>

        {/* Stats */}
        <div className="mb-8 flex flex-wrap gap-4">
          <Badge variant="outline" className="gap-2 px-4 py-2">
            <Package className="h-4 w-4" />
            {tagScripts.length} {tagScripts.length === 1 ? "Script" : "Scripts"}
          </Badge>
          <Badge variant="outline" className="gap-2 px-4 py-2">
            <Eye className="h-4 w-4" />
            {tagScripts
              .reduce((sum, s) => sum + (s.usageStats?.totalViews || 0), 0)
              .toLocaleString()}{" "}
            Total Views
          </Badge>
          <Badge variant="outline" className="gap-2 px-4 py-2">
            <DownloadIcon className="h-4 w-4" />
            {tagScripts
              .reduce((sum, s) => sum + (s.usageStats?.totalDownloads || 0), 0)
              .toLocaleString()}{" "}
            Total Downloads
          </Badge>
        </div>

        {/* Search and controls */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <form
            onSubmit={(e) => {
              e.preventDefault();
            }}
            className="flex-1 sm:max-w-md"
          >
            <div className="relative">
              <Search className="text-muted-foreground absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2" />
              <Input
                type="search"
                placeholder={`Search ${tag} scripts...`}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>
          </form>

          <div className="flex items-center gap-2">
            {/* Sort dropdown */}
            <div className="relative">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                className="gap-2"
              >
                <ArrowUpDown className="h-4 w-4" />
                Sort by
              </Button>
              {isDropdownOpen && (
                <div className="bg-background absolute right-0 z-10 mt-2 w-48 overflow-hidden rounded-md border shadow-lg">
                  {[
                    { value: "views", label: "Most Viewed", icon: Eye },
                    {
                      value: "downloads",
                      label: "Most Downloaded",
                      icon: DownloadIcon,
                    },
                    {
                      value: "recent",
                      label: "Recently Updated",
                      icon: Calendar,
                    },
                    {
                      value: "alphabetical",
                      label: "Alphabetical",
                      icon: SortAsc,
                    },
                  ].map((option) => (
                    <button
                      key={option.value}
                      onClick={() => {
                        setSortBy(option.value as SortOption);
                        setIsDropdownOpen(false);
                      }}
                      className={`hover:bg-muted flex w-full items-center gap-2 px-3 py-2 text-sm transition-colors ${
                        sortBy === option.value ? "bg-muted" : ""
                      }`}
                    >
                      <option.icon className="h-4 w-4" />
                      {option.label}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* View mode toggle */}
            <div className="flex rounded-md border">
              <Button
                variant={viewMode === "grid" ? "secondary" : "ghost"}
                size="sm"
                onClick={() => setViewMode("grid")}
                className="rounded-r-none"
              >
                <Grid2X2 className="h-4 w-4" />
              </Button>
              <Button
                variant={viewMode === "list" ? "secondary" : "ghost"}
                size="sm"
                onClick={() => setViewMode("list")}
                className="rounded-l-none"
              >
                <List className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>

        {/* Status information */}
        {error && (
          <Alert variant="destructive" className="mt-4">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription className="flex items-center justify-between">
              <span>Failed to fetch scripts: {error}</span>
              <Button
                variant="outline"
                size="sm"
                onClick={refetchScripts}
                className="ml-4"
              >
                <RefreshCw className="mr-2 h-4 w-4" />
                Retry
              </Button>
            </AlertDescription>
          </Alert>
        )}
      </div>

      {isLoading ? (
        <div className="py-12 text-center">
          <div className="inline-flex flex-col items-center gap-4">
            <RefreshCw className="text-muted-foreground h-8 w-8 animate-spin" />
            <p className="text-muted-foreground">Loading {tag} scripts...</p>
          </div>
        </div>
      ) : filteredScripts.length === 0 ? (
        <div className="py-12 text-center">
          <p className="text-muted-foreground">
            {searchQuery
              ? `No ${tag} scripts found matching "${searchQuery}"`
              : `No ${tag} scripts available`}
          </p>
        </div>
      ) : (
        <>
          {/* Scripts grid/list */}
          {viewMode === "grid" ? (
            <motion.div
              className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3"
              initial="hidden"
              animate="visible"
              variants={{
                visible: {
                  transition: {
                    staggerChildren: 0.05,
                  },
                },
              }}
            >
              {currentScripts.map((script) => (
                <ScriptCard
                  key={script.id}
                  script={script}
                  onClick={() => handleScriptClick(script)}
                />
              ))}
            </motion.div>
          ) : (
            <div className="space-y-2">
              {currentScripts.map((script) => (
                <ScriptListItem
                  key={script.id}
                  script={script}
                  onClick={() => handleScriptClick(script)}
                />
              ))}
            </div>
          )}

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="mt-8 flex items-center justify-center gap-4">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setCurrentPage(currentPage - 1)}
                disabled={currentPage === 0}
              >
                <ChevronLeft className="h-4 w-4" />
                Previous
              </Button>

              <div className="flex items-center gap-2">
                <span className="text-muted-foreground text-sm">
                  Page {currentPage + 1} of {totalPages}
                </span>
              </div>

              <Button
                variant="outline"
                size="sm"
                onClick={() => setCurrentPage(currentPage + 1)}
                disabled={currentPage >= totalPages - 1}
              >
                Next
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          )}
        </>
      )}

      {/* Script detail modal */}
      <AnimatePresence>
        {selectedScript && isDetailOpen && (
          <ScriptDetail
            script={selectedScript}
            updateScriptStats={updateScriptStats}
            onClose={() => {
              setIsDetailOpen(false);
              setSelectedScript(null);
              // Clear URL state when closing modal
              window.history.pushState(
                null,
                "",
                `/scripts/${tag.toLowerCase()}`,
              );
            }}
          />
        )}
      </AnimatePresence>
    </section>
  );
}
