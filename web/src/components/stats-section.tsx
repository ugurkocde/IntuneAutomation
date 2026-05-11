"use client";

import { motion, useReducedMotion } from "framer-motion";
import { Eye, Download, FileCode, Users } from "lucide-react";
import { useEffect, useState } from "react";

interface StatsData {
  totalViews: number;
  totalDownloads: number;
  totalScripts: number;
}

export default function StatsSection() {
  const prefersReducedMotion = useReducedMotion();
  const [stats, setStats] = useState<StatsData>({
    totalViews: 0,
    totalDownloads: 0,
    totalScripts: 0,
  });
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // Fetch stats from API
    fetch("/api/stats/totals")
      .then((res) => res.json())
      .then((data: StatsData) => {
        setStats(data);
        setIsLoading(false);
      })
      .catch((error) => {
        console.warn("Failed to fetch stats:", error);
        setIsLoading(false);
      });
  }, []);

  const formatNumber = (num: number): string => {
    if (num >= 1000) {
      return (num / 1000).toFixed(1) + "K";
    }
    return num.toLocaleString();
  };

  const statsItems = [
    {
      icon: Eye,
      value: isLoading ? "..." : formatNumber(stats.totalViews),
      label: "Script Views",
      color: "text-blue-600 dark:text-blue-400",
      bgColor: "bg-blue-50 dark:bg-blue-950/30",
    },
    {
      icon: Download,
      value: isLoading ? "..." : formatNumber(stats.totalDownloads),
      label: "Downloads",
      color: "text-green-600 dark:text-green-400",
      bgColor: "bg-green-50 dark:bg-green-950/30",
    },
    {
      icon: FileCode,
      value: isLoading ? "..." : stats.totalScripts.toString(),
      label: "Active Scripts",
      color: "text-purple-600 dark:text-purple-400",
      bgColor: "bg-purple-50 dark:bg-purple-950/30",
    },
  ];

  return (
    <section className="border-border/40 relative border-y bg-gradient-to-b from-transparent via-blue-50/30 to-transparent py-8 backdrop-blur-sm dark:via-blue-950/10">
      <div className="container mx-auto max-w-7xl px-4">
        {/* Optional header */}
        <div className="mb-6 text-center">
          <p className="text-muted-foreground flex items-center justify-center gap-2 text-sm font-medium">
            <Users className="h-4 w-4" />
            Trusted by IT Professionals Worldwide
          </p>
        </div>

        {/* Stats Grid */}
        <motion.div
          className="grid grid-cols-1 gap-4 sm:grid-cols-3 sm:gap-6"
          initial={{ opacity: 0, y: prefersReducedMotion ? 0 : 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
        >
          {statsItems.map((stat, index) => {
            const IconComponent = stat.icon;
            return (
              <motion.div
                key={stat.label}
                className="group relative"
                initial={
                  prefersReducedMotion
                    ? { opacity: 1, y: 0 }
                    : { opacity: 0, y: 20 }
                }
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.1 * index, duration: 0.4 }}
                whileHover={
                  prefersReducedMotion ? {} : { y: -4, transition: { duration: 0.2 } }
                }
              >
                <div className="bg-card/50 hover:bg-card relative flex flex-col items-center rounded-xl border p-4 text-center backdrop-blur-sm transition-all duration-300 hover:shadow-lg sm:p-6">
                  {/* Icon */}
                  <div
                    className={`mb-3 rounded-lg p-2.5 transition-all duration-300 group-hover:scale-110 ${stat.bgColor}`}
                  >
                    <IconComponent className={`h-5 w-5 sm:h-6 sm:w-6 ${stat.color}`} />
                  </div>

                  {/* Value */}
                  <div className="mb-1 text-2xl font-bold sm:text-3xl">
                    {stat.value}
                  </div>

                  {/* Label */}
                  <div className="text-muted-foreground text-xs font-medium sm:text-sm">
                    {stat.label}
                  </div>

                  {/* Hover glow effect */}
                  <div
                    className={`absolute -inset-1 -z-10 rounded-xl opacity-0 blur-sm transition-opacity duration-300 group-hover:opacity-20 ${stat.bgColor}`}
                  />
                </div>
              </motion.div>
            );
          })}
        </motion.div>
      </div>
    </section>
  );
}