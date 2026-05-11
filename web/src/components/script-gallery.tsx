"use client";

import type React from "react";

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ScriptCard } from "~/components/script-card";
import { ScriptDetail } from "~/components/script-detail";
import { TagFilter } from "~/components/tag-filter";
import { useScripts } from "~/components/scripts-provider";
import { AnalyticsService } from "~/lib/supabase-analytics";
import {
  Search,
  RefreshCw,
  AlertCircle,
  Github,
  ChevronLeft,
  ChevronRight,
  ArrowUpDown,
  Eye,
  Calendar,
  Download as DownloadIcon,
  SortAsc,
} from "lucide-react";
import { Input } from "~/components/ui/input";
import { Button } from "~/components/ui/button";
import { Alert, AlertDescription } from "~/components/ui/alert";

type SortOption = "views" | "recent" | "alphabetical" | "downloads";

export default function ScriptGallery() {
  const {
    filteredScripts,
    selectedScript,
    setSelectedScript,
    searchQuery,
    setSearchQuery,
    setSearchOpen,
    isDetailOpen,
    setIsDetailOpen,
    isLoading,
    error,
    lastFetched,
    refetchScripts,
    updateScriptStats,
  } = useScripts();

  const [localSearchQuery, setLocalSearchQuery] = useState("");
  const [sortBy, setSortBy] = useState<SortOption>("views");
  const [currentPage, setCurrentPage] = useState(0);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const hasHandledInitialUrl = useRef(false);

  // Pagination settings
  const scriptsPerPage = 6; // 2 rows of 3 cards each

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
        // If dates are the same, sort by title alphabetically for consistent ordering
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
  }, [filteredScripts, sortBy]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (isDropdownOpen) {
        const target = event.target as Element;
        if (!target.closest(".relative")) {
          setIsDropdownOpen(false);
        }
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, [isDropdownOpen]);

  useEffect(() => {
    setLocalSearchQuery(searchQuery);
  }, [searchQuery]);

  const handlePrevPage = () => {
    if (currentPage > 0) {
      setCurrentPage(currentPage - 1);
      scrollToTop();
    }
  };

  const handleNextPage = () => {
    if (currentPage < totalPages - 1) {
      setCurrentPage(currentPage + 1);
      scrollToTop();
    }
  };

  const scrollToTop = () => {
    const scriptsSection = document.getElementById("scripts-section");
    if (scriptsSection) {
      scriptsSection.scrollIntoView({ behavior: "smooth" });
    }
  };

  const getSortIcon = (option: SortOption) => {
    switch (option) {
      case "views":
        return <Eye className="h-4 w-4" />;
      case "downloads":
        return <DownloadIcon className="h-4 w-4" />;
      case "recent":
        return <Calendar className="h-4 w-4" />;
      case "alphabetical":
        return <SortAsc className="h-4 w-4" />;
      default:
        return <ArrowUpDown className="h-4 w-4" />;
    }
  };

  const getSortLabel = (option: SortOption) => {
    switch (option) {
      case "views":
        return "Most Viewed";
      case "downloads":
        return "Most Downloaded";
      case "recent":
        return "Recently Added";
      case "alphabetical":
        return "Alphabetical";
      default:
        return "Sort";
    }
  };

  useEffect(() => {
    // Handle initial URL params for deep linking
    if (!hasHandledInitialUrl.current) {
      const params = new URLSearchParams(window.location.search);
      const scriptParam = params.get("script");

      if (scriptParam) {
        const script = filteredScripts.find(
          (s) => s.slug === scriptParam || s.id === scriptParam, // Support both slug and ID for backward compatibility
        );

        if (script) {
          setSelectedScript(script);
          setIsDetailOpen(true);
        }
      }
      hasHandledInitialUrl.current = true;
    }

    // Listen for browser back/forward navigation
    const handlePopState = () => {
      const params = new URLSearchParams(window.location.search);
      const scriptParam = params.get("script");

      if (scriptParam) {
        const script = filteredScripts.find(
          (s) => s.slug === scriptParam || s.id === scriptParam, // Support both slug and ID for backward compatibility
        );

        if (script && script !== selectedScript) {
          setSelectedScript(script);
          setIsDetailOpen(true);
        }
      } else if (selectedScript) {
        setSelectedScript(null);
        setIsDetailOpen(false);
      }
    };

    window.addEventListener("popstate", handlePopState);

    return () => {
      window.removeEventListener("popstate", handlePopState);
    };
  }, [filteredScripts, selectedScript, setSelectedScript]);

  useEffect(() => {
    // Update URL when selected script changes
    if (selectedScript && isDetailOpen) {
      const scriptSlug = selectedScript.slug;
      window.history.pushState(null, "", `?script=${scriptSlug}`);
    } else if (!isDetailOpen && selectedScript === null) {
      window.history.pushState(null, "", "/");
    }
  }, [selectedScript, isDetailOpen]);

  const handleScriptClick = (script: any) => {
    // Update stats immediately in the UI for real-time feedback
    updateScriptStats(script.id, "view");

    // Track analytics in the background (don't block UI)
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

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setSearchQuery(localSearchQuery);
  };

  return (
    <section
      id="scripts-section"
      className="container mx-auto max-w-7xl px-4 py-16"
    >
      <div className="mb-12 text-center">
        <h2 className="mb-4 text-3xl font-bold">Script Collection</h2>
        <p className="text-muted-foreground mx-auto max-w-2xl">
          Browse our curated collection of PowerShell scripts to automate
          Microsoft Intune tasks. Filter by tags or search to find exactly what
          you need.
        </p>

        {/* Status Information */}
        <div className="mt-6 flex flex-col items-center gap-4">
          {isLoading && (
            <div className="text-muted-foreground flex items-center gap-2 text-sm">
              <RefreshCw className="h-4 w-4 animate-spin" />
              <span>Fetching latest scripts from GitHub...</span>
            </div>
          )}

          {error && (
            <Alert variant="destructive" className="max-w-2xl">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription className="flex items-center justify-between">
                <span>Failed to fetch scripts from GitHub: {error}</span>
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

          {lastFetched && !isLoading && !error && (
            <div className="text-muted-foreground flex items-center gap-2 text-xs">
              <Github className="h-3 w-3" />
              <Button
                variant="ghost"
                size="sm"
                onClick={refetchScripts}
                className="h-6 px-2 text-xs"
              >
                <RefreshCw className="h-3 w-3" />
              </Button>
            </div>
          )}
        </div>
      </div>

      <div className="mb-10 space-y-8">
        {/* Search Section */}
        <div className="flex flex-col items-center justify-center">
          <form
            onSubmit={handleSearchSubmit}
            className="relative w-full max-w-lg"
          >
            <Search className="text-muted-foreground absolute top-1/2 left-4 h-5 w-5 -translate-y-1/2" />
            <Input
              type="text"
              placeholder="Search scripts by name, description, or tags..."
              className="focus:border-primary/50 focus:ring-primary/20 h-12 rounded-xl border-2 py-3 pr-4 pl-12 text-base transition-all duration-200 focus:ring-2"
              value={localSearchQuery}
              onChange={(e) => setLocalSearchQuery(e.target.value)}
              onFocus={() => setSearchOpen(true)}
            />
          </form>
        </div>

        {/* Divider */}
        <div className="bg-border mx-auto h-px w-24"></div>

        {/* Filter Section with integrated Sort Control */}
        <TagFilter
          sortControl={
            <div className="flex items-center gap-3">
              <span className="text-muted-foreground text-sm font-medium">
                Sort by:
              </span>
              <div className="relative">
                <Button
                  variant="outline"
                  onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                  className="w-[180px] justify-between"
                >
                  <div className="flex items-center gap-2">
                    {getSortIcon(sortBy)}
                    <span>{getSortLabel(sortBy)}</span>
                  </div>
                  <ChevronRight
                    className={`h-4 w-4 transition-transform ${isDropdownOpen ? "rotate-90" : ""}`}
                  />
                </Button>

                {isDropdownOpen && (
                  <div className="bg-popover absolute top-full right-0 z-50 mt-1 w-[180px] rounded-md border p-1 shadow-md">
                    {(
                      [
                        "views",
                        "downloads",
                        "recent",
                        "alphabetical",
                      ] as SortOption[]
                    ).map((option) => (
                      <button
                        key={option}
                        onClick={() => {
                          setSortBy(option);
                          setIsDropdownOpen(false);
                        }}
                        className={`hover:bg-accent hover:text-accent-foreground flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm ${
                          sortBy === option
                            ? "bg-accent text-accent-foreground"
                            : ""
                        }`}
                      >
                        {getSortIcon(option)}
                        {getSortLabel(option)}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          }
        />
      </div>

      {isLoading ? (
        <div className="py-12 text-center">
          <div className="inline-flex flex-col items-center gap-4">
            <RefreshCw className="text-muted-foreground h-8 w-8 animate-spin" />
            <p className="text-muted-foreground">
              Loading scripts from GitHub...
            </p>
          </div>
        </div>
      ) : filteredScripts.length === 0 ? (
        <div className="py-12 text-center">
          <p className="text-muted-foreground">
            No scripts found matching your criteria.
          </p>
        </div>
      ) : (
        <>
          {/* Scripts Grid */}
          <motion.div
            className="grid min-h-[600px] grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ staggerChildren: 0.1 }}
          >
            {currentScripts.map((script, index) => (
              <motion.div
                key={script.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.1 }}
              >
                <ScriptCard
                  script={script}
                  onClick={() => handleScriptClick(script)}
                />
              </motion.div>
            ))}
          </motion.div>

          {/* Pagination Controls */}
          {totalPages > 1 && (
            <div className="mt-12 flex items-center justify-center gap-4">
              <Button
                variant="outline"
                size="sm"
                onClick={handlePrevPage}
                disabled={currentPage === 0}
                className="flex items-center gap-2 shadow-sm"
              >
                <ChevronLeft className="h-4 w-4" />
                Previous
              </Button>

              {/* Page Indicators */}
              <div className="flex items-center gap-1">
                {Array.from({ length: totalPages }, (_, i) => (
                  <button
                    key={i}
                    onClick={() => {
                      setCurrentPage(i);
                      scrollToTop();
                    }}
                    className={`h-9 w-9 rounded-lg text-sm font-medium transition-all duration-200 ${
                      i === currentPage
                        ? "bg-primary text-primary-foreground scale-105 shadow-sm"
                        : "bg-muted/50 text-muted-foreground hover:bg-muted hover:scale-105"
                    }`}
                  >
                    {i + 1}
                  </button>
                ))}
              </div>

              <Button
                variant="outline"
                size="sm"
                onClick={handleNextPage}
                disabled={currentPage === totalPages - 1}
                className="flex items-center gap-2 shadow-sm"
              >
                Next
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          )}

          {/* Results Summary */}
          <div className="mt-8 text-center">
            <div className="bg-muted/30 inline-flex items-center gap-2 rounded-full border px-4 py-2">
              <span className="text-sm font-medium">
                Showing {currentPage * scriptsPerPage + 1}-
                {Math.min(
                  (currentPage + 1) * scriptsPerPage,
                  sortedScripts.length,
                )}{" "}
                of {sortedScripts.length} scripts
              </span>
              {sortBy !== "views" && (
                <span className="text-muted-foreground text-xs">
                  • sorted by{" "}
                  {sortBy === "recent"
                    ? "recently added"
                    : sortBy === "alphabetical"
                      ? "name"
                      : sortBy}
                </span>
              )}
            </div>
          </div>
        </>
      )}

      <AnimatePresence>
        {selectedScript && isDetailOpen && (
          <ScriptDetail
            script={selectedScript}
            updateScriptStats={updateScriptStats}
            onClose={() => {
              setIsDetailOpen(false);
              setSelectedScript(null);
              // Navigate back to homepage when closing modal
              window.history.pushState(null, "", "/");
            }}
          />
        )}
      </AnimatePresence>
    </section>
  );
}
