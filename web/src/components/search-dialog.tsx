"use client";

import { useEffect, useState, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Command } from "cmdk";
import { useScripts } from "~/components/scripts-provider";
import { Search, Tag, X } from "lucide-react";
import { Badge } from "~/components/ui/badge";
import { Button } from "~/components/ui/button";
import { cn } from "~/lib/utils";
import { AnalyticsService } from "~/lib/supabase-analytics";

export default function SearchDialog() {
  const {
    allScripts,
    isSearchOpen,
    setSearchOpen,
    setSelectedScript,
    setIsDetailOpen,
    searchQuery,
    setSearchQuery,
    updateScriptStats,
  } = useScripts();

  const [inputValue, setInputValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setInputValue(searchQuery);
  }, [searchQuery]);

  useEffect(() => {
    if (isSearchOpen && inputRef.current) {
      // Small timeout to ensure the dialog is fully rendered
      setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
    }
  }, [isSearchOpen]);

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isSearchOpen) {
        setSearchOpen(false);
      }
    };

    document.addEventListener("keydown", down);
    return () => document.removeEventListener("keydown", down);
  }, [isSearchOpen, setSearchOpen]);

  const handleSelect = (scriptId: string) => {
    const script = allScripts.find((s) => s.id === scriptId);
    if (script) {
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

      setSelectedScript(script);
      setIsDetailOpen(true);
      setSearchOpen(false);
    }
  };

  if (!isSearchOpen) return null;

  return (
    <AnimatePresence>
      {isSearchOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="bg-background/80 fixed inset-0 z-50 backdrop-blur-sm"
          onClick={() => setSearchOpen(false)}
        >
          <motion.div
            initial={{ scale: 0.95, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.95, opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="fixed top-[50%] left-[50%] z-50 w-full max-w-lg translate-x-[-50%] translate-y-[-50%] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <Command
              className="bg-card overflow-hidden rounded-xl border shadow-md"
              loop
            >
              <div className="flex items-center border-b px-3">
                <Search className="mr-2 h-4 w-4 shrink-0 opacity-50" />
                <Command.Input
                  ref={inputRef}
                  value={inputValue}
                  onValueChange={setInputValue}
                  placeholder="Search scripts..."
                  className="placeholder:text-muted-foreground flex h-12 w-full rounded-md bg-transparent py-3 text-sm outline-none disabled:cursor-not-allowed disabled:opacity-50"
                />
                {inputValue && (
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6"
                    onClick={() => setInputValue("")}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                )}
              </div>
              <Command.List className="max-h-[300px] overflow-y-auto p-2">
                <Command.Empty className="py-6 text-center text-sm">
                  No scripts found.
                </Command.Empty>

                {allScripts
                  .filter(
                    (script) =>
                      script.title
                        .toLowerCase()
                        .includes(inputValue.toLowerCase()) ||
                      script.description
                        .toLowerCase()
                        .includes(inputValue.toLowerCase()) ||
                      script.tags.some((tag) =>
                        tag.toLowerCase().includes(inputValue.toLowerCase()),
                      ),
                  )
                  .map((script) => (
                    <Command.Item
                      key={script.id}
                      value={script.id}
                      onSelect={handleSelect}
                      className={cn(
                        "flex cursor-pointer flex-col items-start gap-1 rounded-lg px-4 py-3 text-sm",
                        "aria-selected:bg-accent aria-selected:text-accent-foreground",
                      )}
                    >
                      <div className="font-medium">{script.title}</div>
                      <div className="text-muted-foreground line-clamp-1 text-xs">
                        {script.description}
                      </div>
                      <div className="mt-1 flex gap-1">
                        {script.tags.map((tag) => (
                          <Badge
                            key={tag}
                            variant="secondary"
                            className="text-xs"
                          >
                            {tag}
                          </Badge>
                        ))}
                      </div>
                    </Command.Item>
                  ))}
              </Command.List>

              <div className="text-muted-foreground flex items-center justify-end border-t p-2 text-xs">
                <div>
                  <kbd className="bg-muted pointer-events-none inline-flex h-5 items-center gap-1 rounded border px-1.5 font-mono text-[10px] font-medium opacity-100 select-none">
                    <span className="text-xs">ESC</span>
                  </kbd>
                  <span className="ml-1">to close</span>
                </div>
              </div>
            </Command>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
