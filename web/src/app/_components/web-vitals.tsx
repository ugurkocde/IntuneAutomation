"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

export function WebVitals() {
  const pathname = usePathname();

  useEffect(() => {
    if (typeof window === "undefined") return;

    const reportWebVitals = async () => {
      if ("web-vitals" in window) return;

      const { onCLS, onFCP, onLCP, onTTFB, onINP } = await import("web-vitals");

      const sendToAnalytics = (metric: any) => {
        // Send to Plausible as custom event
        if (window.plausible) {
          window.plausible("Web Vitals", {
            props: {
              metric_name: metric.name,
              metric_value: Math.round(metric.value),
              metric_rating: metric.rating,
              page: pathname,
            },
          });
        }

        // Log in development
        if (process.env.NODE_ENV === "development") {
          console.log(`[Web Vitals] ${metric.name}:`, {
            value: metric.value,
            rating: metric.rating,
            entries: metric.entries,
          });
        }
      };

      onCLS(sendToAnalytics);
      onFCP(sendToAnalytics);
      onLCP(sendToAnalytics);
      onTTFB(sendToAnalytics);
      onINP(sendToAnalytics);
    };

    reportWebVitals();
  }, [pathname]);

  return null;
}

// Add type declaration for plausible
declare global {
  interface Window {
    plausible?: (
      event: string,
      options?: { props: Record<string, any> },
    ) => void;
  }
}
