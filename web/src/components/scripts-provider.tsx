"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  type ReactNode,
} from "react";
import { type Script, type ScriptTag } from "~/lib/scripts";

interface ScriptsContextType {
  allScripts: Script[];
  filteredScripts: Script[];
  selectedScript: Script | null;
  selectedTags: ScriptTag[];
  searchQuery: string;
  isSearchOpen: boolean;
  isDetailOpen: boolean;
  isLoading: boolean;
  error: string | null;
  lastFetched: string | null;
  setSelectedScript: (script: Script | null) => void;
  setSelectedTags: (tags: ScriptTag[]) => void;
  setSearchQuery: (query: string) => void;
  setSearchOpen: (isOpen: boolean) => void;
  setIsDetailOpen: (isOpen: boolean) => void;
  toggleTag: (tag: ScriptTag) => void;
  refetchScripts: () => Promise<void>;
  updateScriptStats: (scriptId: string, type: "view" | "download") => void;
}

const ScriptsContext = createContext<ScriptsContextType | undefined>(undefined);

export function ScriptsProvider({ children }: { children: ReactNode }) {
  const [allScripts, setAllScripts] = useState<Script[]>([]);
  const [selectedScript, setSelectedScript] = useState<Script | null>(null);
  const [selectedTags, setSelectedTags] = useState<ScriptTag[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [isSearchOpen, setSearchOpen] = useState(false);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastFetched, setLastFetched] = useState<string | null>(null);

  const fetchScripts = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/scripts");
      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.message || "Failed to fetch scripts");
      }

      if (result.success && result.data) {
        setAllScripts(result.data);
        setLastFetched(result.lastFetched);
      } else {
        throw new Error("Invalid response format");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      setError(errorMessage);
      // Don't use fallback scripts - keep the array empty
      setAllScripts([]);
    } finally {
      setIsLoading(false);
    }
  };

  const refetchScripts = async () => {
    await fetchScripts();
  };

  // Update script stats - removed optimistic updates
  const updateScriptStats = (scriptId: string, type: "view" | "download") => {
    // Analytics are now handled through real-time polling
    // No need for optimistic updates that can conflict with actual data
  };

  // Fetch scripts on component mount
  useEffect(() => {
    fetchScripts();

    // Refresh analytics data every 2 minutes to show updated view counts
    const interval = setInterval(() => {
      fetchScripts();
    }, 120000); // 2 minutes

    return () => clearInterval(interval);
  }, []);

  const toggleTag = (tag: ScriptTag) => {
    if (selectedTags.includes(tag)) {
      setSelectedTags(selectedTags.filter((t) => t !== tag));
    } else {
      setSelectedTags([...selectedTags, tag]);
    }
  };

  // Filter scripts based on selected tags and search query
  const filteredScripts = allScripts.filter((script) => {
    const matchesTags =
      selectedTags.length === 0 ||
      selectedTags.every((tag) => script.tags.includes(tag));

    const matchesSearch =
      searchQuery === "" ||
      script.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      script.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (script.author &&
        script.author.toLowerCase().includes(searchQuery.toLowerCase()));

    return matchesTags && matchesSearch;
  });

  return (
    <ScriptsContext.Provider
      value={{
        allScripts,
        filteredScripts,
        selectedScript,
        selectedTags,
        searchQuery,
        isSearchOpen,
        isDetailOpen,
        isLoading,
        error,
        lastFetched,
        setSelectedScript,
        setSelectedTags,
        setSearchQuery,
        setSearchOpen,
        setIsDetailOpen,
        toggleTag,
        refetchScripts,
        updateScriptStats,
      }}
    >
      {children}
    </ScriptsContext.Provider>
  );
}

export function useScripts() {
  const context = useContext(ScriptsContext);
  if (context === undefined) {
    throw new Error("useScripts must be used within a ScriptsProvider");
  }
  return context;
}
