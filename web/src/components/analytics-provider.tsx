"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  type ReactNode,
} from "react";

interface Analytics {
  totalViews: number;
  weeklyViews: number;
  totalDownloads: number;
  weeklyDownloads: number;
}

interface AnalyticsContextType {
  analytics: Record<string, Analytics>;
  isLoading: boolean;
  getAnalytics: (scriptId: string) => Analytics | null;
}

const AnalyticsContext = createContext<AnalyticsContextType | undefined>(
  undefined,
);

export function AnalyticsProvider({ children }: { children: ReactNode }) {
  const [analytics, setAnalytics] = useState<Record<string, Analytics>>({});
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const fetchAnalytics = async () => {
      try {
        // Add timestamp to prevent caching
        const response = await fetch(`/api/analytics/stats?t=${Date.now()}`);
        if (response.ok) {
          const data = await response.json();
          setAnalytics(data || {});
        }
      } catch (error) {
        console.error("Failed to fetch analytics:", error);
      } finally {
        setIsLoading(false);
      }
    };

    // Initial fetch
    fetchAnalytics();

    // Refresh analytics every 30 seconds (instead of every component doing it every 5 seconds)
    const interval = setInterval(fetchAnalytics, 30000);

    return () => clearInterval(interval);
  }, []);

  const getAnalytics = (scriptId: string): Analytics | null => {
    return analytics[scriptId] || null;
  };

  return (
    <AnalyticsContext.Provider value={{ analytics, isLoading, getAnalytics }}>
      {children}
    </AnalyticsContext.Provider>
  );
}

export function useAnalyticsContext() {
  const context = useContext(AnalyticsContext);
  if (!context) {
    throw new Error(
      "useAnalyticsContext must be used within AnalyticsProvider",
    );
  }
  return context;
}
