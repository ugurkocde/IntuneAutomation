"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useScripts } from "~/components/scripts-provider";
import { type ScriptTag, allTags } from "~/lib/scripts";
import { cn } from "~/lib/utils";
import { Badge } from "~/components/ui/badge";
import { Button } from "~/components/ui/button";
import {
  Shield,
  Smartphone,
  CheckCircle,
  Package,
  BarChart3,
  Stethoscope,
  Settings,
  X,
  Filter,
  Cog,
  Activity,
  Bell,
} from "lucide-react";

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
    "bg-red-500/10 text-red-700 border-red-200 hover:bg-red-500/20 dark:text-red-400 dark:border-red-800",
  Devices:
    "bg-blue-500/10 text-blue-700 border-blue-200 hover:bg-blue-500/20 dark:text-blue-400 dark:border-blue-800",
  Compliance:
    "bg-green-500/10 text-green-700 border-green-200 hover:bg-green-500/20 dark:text-green-400 dark:border-green-800",
  Apps: "bg-purple-500/10 text-purple-700 border-purple-200 hover:bg-purple-500/20 dark:text-purple-400 dark:border-purple-800",
  Reporting:
    "bg-orange-500/10 text-orange-700 border-orange-200 hover:bg-orange-500/20 dark:text-orange-400 dark:border-orange-800",
  Diagnostics:
    "bg-cyan-500/10 text-cyan-700 border-cyan-200 hover:bg-cyan-500/20 dark:text-cyan-400 dark:border-cyan-800",
  Configuration:
    "bg-slate-500/10 text-slate-700 border-slate-200 hover:bg-slate-500/20 dark:text-slate-400 dark:border-slate-800",
  Operational:
    "bg-yellow-500/10 text-yellow-700 border-yellow-200 hover:bg-yellow-500/20 dark:text-yellow-400 dark:border-yellow-800",
  Monitoring:
    "bg-indigo-500/10 text-indigo-700 border-indigo-200 hover:bg-indigo-500/20 dark:text-indigo-400 dark:border-indigo-800",
  Notification:
    "bg-violet-500/10 text-violet-700 border-violet-200 hover:bg-violet-500/20 dark:text-violet-400 dark:border-violet-800",
  Remediation:
    "bg-emerald-500/10 text-emerald-700 border-emerald-200 hover:bg-emerald-500/20 dark:text-emerald-400 dark:border-emerald-800",
};

interface TagFilterProps {
  sortControl?: React.ReactNode;
}

export function TagFilter({ sortControl }: TagFilterProps) {
  const { selectedTags, toggleTag, setSelectedTags, filteredScripts } =
    useScripts();

  const clearAllFilters = () => {
    setSelectedTags([]);
  };

  return (
    <div className="w-full">
      {/* Mobile Layout */}
      <div className="md:hidden">
        {/* Sort control - full width on mobile */}
        <div className="mb-4">{sortControl}</div>

        {/* Filter header */}
        <div className="mb-3 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Filter className="text-muted-foreground h-4 w-4" />
            <span className="text-muted-foreground text-sm font-medium">
              Filter by Category
            </span>
            {selectedTags.length > 0 && (
              <Badge variant="outline" className="text-xs">
                {filteredScripts.length}
              </Badge>
            )}
          </div>

          {/* Clear all button */}
          <AnimatePresence>
            {selectedTags.length > 0 && (
              <motion.div
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ duration: 0.2 }}
              >
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={clearAllFilters}
                  className="h-7 gap-1 px-2 text-xs"
                >
                  <X className="h-3 w-3" />
                  Clear
                </Button>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Compact tag grid for mobile */}
        <div className="grid grid-cols-2 gap-2">
          {allTags.map((tag, index) => (
            <MobileTagButton
              key={tag}
              tag={tag}
              isSelected={selectedTags.includes(tag)}
              onClick={() => toggleTag(tag)}
              delay={index * 0.02}
            />
          ))}
        </div>
      </div>

      {/* Desktop Layout */}
      <div className="hidden md:block">
        {/* Header section - desktop */}
        <div className="mb-4 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-2">
            <Filter className="text-muted-foreground h-4 w-4" />
            <span className="text-muted-foreground text-sm font-medium">
              Filter by Category
            </span>
            {selectedTags.length > 0 && (
              <Badge variant="outline" className="text-xs">
                {filteredScripts.length} script
                {filteredScripts.length !== 1 ? "s" : ""}
              </Badge>
            )}
          </div>

          {/* Right side - sort control and clear button */}
          <div className="flex items-center gap-3">
            {/* Sort control passed from parent */}
            {sortControl}

            {/* Clear all button */}
            <AnimatePresence>
              {selectedTags.length > 0 && (
                <motion.div
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.8 }}
                  transition={{ duration: 0.2 }}
                >
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={clearAllFilters}
                    className="h-7 gap-1 px-2 text-xs"
                  >
                    <X className="h-3 w-3" />
                    Clear all
                  </Button>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>

        {/* Desktop tag filters */}
        <div className="flex flex-wrap gap-3">
          {allTags.map((tag, index) => (
            <TagButton
              key={tag}
              tag={tag}
              isSelected={selectedTags.includes(tag)}
              onClick={() => toggleTag(tag)}
              delay={index * 0.05}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

interface TagButtonProps {
  tag: ScriptTag;
  isSelected: boolean;
  onClick: () => void;
  delay?: number;
}

function TagButton({ tag, isSelected, onClick, delay = 0 }: TagButtonProps) {
  const Icon = tagIcons[tag];

  return (
    <motion.button
      initial={{ opacity: 0, y: 5 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2, delay, ease: "easeOut" }}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={cn(
        "group relative flex items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-medium transition-all duration-150",
        isSelected ? "ring-primary/20 shadow-sm ring-2" : "hover:shadow-sm",
        isSelected ? tagColors[tag].replace("hover:", "") : tagColors[tag],
      )}
    >
      {/* Content */}
      <div className="relative flex items-center gap-2">
        <Icon
          className={cn(
            "h-4 w-4 transition-transform duration-150",
            isSelected ? "scale-110" : "group-hover:scale-105",
          )}
        />
        <span>{tag}</span>

        {/* Selection indicator */}
        <AnimatePresence mode="wait">
          {isSelected && (
            <motion.div
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0, opacity: 0 }}
              transition={{ duration: 0.15, ease: "easeOut" }}
              className="bg-primary h-2 w-2 rounded-full"
            />
          )}
        </AnimatePresence>
      </div>
    </motion.button>
  );
}

function MobileTagButton({
  tag,
  isSelected,
  onClick,
  delay = 0,
}: TagButtonProps) {
  const Icon = tagIcons[tag];

  return (
    <motion.button
      initial={{ opacity: 0, y: 3 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.15, delay, ease: "easeOut" }}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={cn(
        "group relative flex items-center justify-center gap-1.5 rounded-lg border px-3 py-2 text-xs font-medium transition-all duration-150",
        isSelected ? "ring-primary/20 shadow-sm ring-1" : "",
        isSelected ? tagColors[tag].replace("hover:", "") : tagColors[tag],
      )}
    >
      <Icon
        className={cn(
          "h-3.5 w-3.5 shrink-0 transition-transform duration-150",
          isSelected ? "scale-110" : "group-hover:scale-105",
        )}
      />
      <span className="truncate">{tag}</span>
      {isSelected && (
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          exit={{ scale: 0, opacity: 0 }}
          transition={{ duration: 0.1, ease: "easeOut" }}
          className="bg-primary h-1.5 w-1.5 shrink-0 rounded-full"
        />
      )}
    </motion.button>
  );
}
