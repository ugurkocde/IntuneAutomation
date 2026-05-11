"use client";

import { useRef, useEffect, useState, useMemo, useCallback } from "react";
import {
  motion,
  useScroll,
  useTransform,
  useReducedMotion,
} from "framer-motion";
import { ChevronDown, Play, Search, Star, Check, Eye } from "lucide-react";
import { useScripts } from "~/components/scripts-provider";

// Move features outside component to prevent recreation on each render
// Reduced to 7 core features for better UX
const FEATURES = [
  "Get compliance reports without the headache",
  "Sync multiple devices at once",
  "Identify and fix non-compliant devices quickly",
  "Generate HTML or CSV reports with one command",
  "Automate RBAC and permission audits",
  "Bulk deploy and update apps across platforms",
  "Detect and remove unused or stale objects",
] as const;

interface Particle {
  left: number;
  top: number;
  duration: number;
  delay: number;
}

// Fast feature rotation hook with smooth transitions
// Slowed to 4 seconds for better readability
const useFeatureRotation = (features: readonly string[], duration = 4000) => {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isVisible, setIsVisible] = useState(true);

  useEffect(() => {
    const interval = setInterval(() => {
      setIsVisible(false);
      setTimeout(() => {
        setCurrentIndex((prev) => (prev + 1) % features.length);
        setIsVisible(true);
      }, 150); // Quick fade out/in
    }, duration);

    return () => clearInterval(interval);
  }, [features.length, duration]);

  return { currentFeature: features[currentIndex], isVisible };
};

export default function HeroSection() {
  const { setSearchOpen, allScripts, isLoading, error } = useScripts();
  const sectionRef = useRef<HTMLDivElement>(null);
  const prefersReducedMotion = useReducedMotion();

  const { scrollYProgress } = useScroll({
    target: sectionRef,
    offset: ["start start", "end start"],
  });

  const y = useTransform(scrollYProgress, [0, 1], ["0%", "50%"]);
  const opacity = useTransform(scrollYProgress, [0, 0.5], [1, 0]);

  const [isHovered, setIsHovered] = useState(false);

  // Use fast feature rotation for immediate engagement
  const { currentFeature, isVisible } = useFeatureRotation(FEATURES, 4000);

  // State for particles to prevent hydration mismatch
  const [particles, setParticles] = useState<Particle[]>([]);

  // State for total views count
  const [totalViews, setTotalViews] = useState<number | null>(null);

  // Fetch total views from stats API
  useEffect(() => {
    fetch("/api/stats/totals")
      .then((res) => res.json())
      .then((data: { totalViews: number }) => {
        setTotalViews(data.totalViews);
      })
      .catch((error) => {
        console.warn("Failed to fetch stats:", error);
      });
  }, []);

  // Generate particles only on client side to prevent hydration mismatch
  useEffect(() => {
    if (prefersReducedMotion) {
      setParticles([]);
      return;
    }

    // Reduce particle count on mobile for better performance
    const isMobile = window.innerWidth < 768;
    const particleCount = isMobile ? 15 : 40;

    const newParticles = Array.from({ length: particleCount }, () => ({
      left: Math.random() * 100,
      top: Math.random() * 100,
      duration: 3 + Math.random() * 4,
      delay: Math.random() * 5,
    }));
    setParticles(newParticles);
  }, [prefersReducedMotion]);

  const scrollToScripts = useCallback(() => {
    const scriptsSection = document.getElementById("popular-scripts-section");
    if (scriptsSection) {
      scriptsSection.scrollIntoView({ behavior: "smooth" });
    }
  }, []);

  const navigateToScripts = useCallback(() => {
    window.location.href = "/scripts";
  }, []);

  const handleSearchClick = useCallback(() => {
    setSearchOpen(true);
  }, [setSearchOpen]);

  // Enhanced keyboard navigation
  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        scrollToScripts();
      }
    },
    [scrollToScripts],
  );

  return (
    <section
      ref={sectionRef}
      className="relative flex min-h-[calc(100vh-4rem)] flex-col items-center justify-center overflow-hidden px-4 py-8 text-center sm:py-12"
      aria-label="Hero section with IntuneAutomation introduction"
    >
      {/* Enhanced Background with Animated Elements */}
      <div className="absolute inset-0 z-0" aria-hidden="true">
        <div className="from-background/20 via-background/60 to-background absolute inset-0 bg-gradient-to-b"></div>

        {/* Animated gradient orbs - only animate if user allows motion */}
        {!prefersReducedMotion && (
          <>
            <motion.div
              className="absolute top-1/4 left-1/4 h-48 w-48 rounded-full bg-blue-500/10 blur-3xl sm:h-72 sm:w-72 md:h-96 md:w-96"
              animate={{
                scale: [1, 1.2, 1],
                opacity: [0.3, 0.5, 0.3],
              }}
              transition={{
                duration: 8,
                repeat: Number.POSITIVE_INFINITY,
                ease: "easeInOut",
              }}
            />
            <motion.div
              className="absolute right-1/4 bottom-1/4 h-48 w-48 rounded-full bg-purple-500/10 blur-3xl sm:h-72 sm:w-72 md:h-96 md:w-96"
              animate={{
                scale: [1.2, 1, 1.2],
                opacity: [0.5, 0.3, 0.5],
              }}
              transition={{
                duration: 8,
                repeat: Number.POSITIVE_INFINITY,
                ease: "easeInOut",
                delay: 4,
              }}
            />
            <motion.div
              className="absolute top-1/2 left-1/2 h-32 w-32 rounded-full bg-green-500/5 blur-3xl sm:h-48 sm:w-48 md:h-72 md:w-72"
              animate={{
                x: [-30, 30, -30],
                y: [-20, 20, -20],
              }}
              transition={{
                duration: 12,
                repeat: Number.POSITIVE_INFINITY,
                ease: "easeInOut",
              }}
            />
          </>
        )}

        {/* Floating particles */}
        {particles.map((particle, index) => (
          <motion.div
            key={index}
            className="bg-primary/20 absolute h-1 w-1 rounded-full"
            style={{
              left: `${particle.left}%`,
              top: `${particle.top}%`,
            }}
            animate={{
              y: [-20, -100, -20],
              opacity: [0, 1, 0],
            }}
            transition={{
              duration: particle.duration,
              repeat: Number.POSITIVE_INFINITY,
              delay: particle.delay,
            }}
          />
        ))}
      </div>

      <motion.div className="z-10 mx-auto max-w-6xl" style={{ y, opacity }}>
        {/* Enhanced Badge with Live Stats */}
        <motion.div
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.2, duration: 0.8 }}
          className="mb-6 inline-block sm:mb-8"
        >
          <div className="border-primary/20 text-primary rounded-full border bg-gradient-to-r from-blue-500/10 to-purple-500/10 px-4 py-2 text-sm font-medium backdrop-blur-sm sm:px-6 sm:text-sm">
            <span className="inline-flex items-center gap-1.5 sm:gap-2">
              <Star className="h-3 w-3 sm:h-4 sm:w-4" />
              <span className="hidden sm:inline">
                Scripts for Microsoft Intune
              </span>
              <span className="sm:hidden">Intune Scripts</span>
            </span>
          </div>
        </motion.div>

        {/* Main Heading with Enhanced Accessibility */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.8 }}
          className="mb-4 sm:mb-6"
        >
          <h1 className="mb-3 text-4xl leading-tight font-bold tracking-tight sm:mb-4 sm:text-5xl md:text-7xl lg:text-8xl">
            <span
              className="bg-size-200 animate-gradient bg-gradient-to-r from-blue-500 via-purple-600 to-blue-500 bg-clip-text text-transparent"
              style={prefersReducedMotion ? { animation: "none" } : {}}
            >
              IntuneAutomation
            </span>
          </h1>
        </motion.div>

        {/* Enhanced Dynamic Subtitle */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.8 }}
          className="mb-6 sm:mb-8"
        >
          <p className="text-muted-foreground mb-3 text-xl leading-relaxed sm:mb-4 sm:text-2xl md:text-3xl">
            <span className="text-foreground font-semibold">
              Save 20+ hours per week
            </span>{" "}
            automating Microsoft Intune.
          </p>
          <div className="relative flex h-10 items-center justify-center px-4 sm:h-12">
            {prefersReducedMotion ? (
              <p className="text-primary absolute inset-0 flex items-center justify-center text-center text-base font-medium sm:text-lg md:text-xl">
                {currentFeature}
              </p>
            ) : (
              <motion.div
                className="text-primary absolute inset-0 flex items-center justify-center text-center text-base font-medium sm:text-lg md:text-xl"
                key={currentFeature}
                initial={{ opacity: 0, y: 20 }}
                animate={{
                  opacity: isVisible ? 1 : 0,
                  y: isVisible ? 0 : -10,
                }}
                transition={{ duration: 0.3, ease: "easeInOut" }}
              >
                {currentFeature}
              </motion.div>
            )}
          </div>
        </motion.div>

        {/* Enhanced Call-to-Action Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.8 }}
          className="mb-8 flex flex-col justify-center gap-3 px-4 sm:mb-12 sm:flex-row sm:gap-4 sm:px-0"
        >
          <motion.button
            onClick={handleSearchClick}
            onMouseEnter={() => setIsHovered(true)}
            onMouseLeave={() => setIsHovered(false)}
            disabled={isLoading}
            className="group focus:ring-offset-background relative cursor-pointer overflow-hidden rounded-2xl bg-gradient-to-r from-blue-600 to-purple-700 px-10 py-5 text-lg font-bold text-white shadow-2xl transition-all duration-150 hover:from-blue-700 hover:to-purple-800 hover:shadow-2xl focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 sm:px-10 sm:py-5"
            whileHover={
              prefersReducedMotion
                ? {}
                : { scale: isLoading ? 1 : 1.08, y: isLoading ? 0 : -3 }
            }
            whileTap={
              prefersReducedMotion ? {} : { scale: isLoading ? 1 : 0.95 }
            }
            transition={{ duration: 0.15, ease: "easeOut" }}
            aria-label="Open search dialog to find scripts"
          >
            {/* Animated background effect */}
            <motion.div
              className="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0"
              initial={{ x: "-100%" }}
              animate={isHovered && !isLoading ? { x: "100%" } : { x: "-100%" }}
              transition={{ duration: 0.5 }}
            />
            <span className="relative flex items-center justify-center gap-2">
              <Search
                className={`h-4 w-4 transition-transform sm:h-5 sm:w-5 ${isLoading ? "animate-spin" : "group-hover:rotate-12"}`}
              />
              <span className="text-sm sm:text-base">
                {isLoading ? "Loading..." : "Search Scripts"}
              </span>
            </span>
          </motion.button>

          <motion.button
            onClick={navigateToScripts}
            className="group bg-background/80 text-foreground hover:bg-background border-border focus:ring-primary focus:ring-offset-background cursor-pointer rounded-2xl border px-8 py-4 font-medium backdrop-blur-sm transition-all duration-150 hover:border-primary/30 focus:ring-2 focus:ring-offset-2 focus:outline-none sm:px-8 sm:py-4"
            whileHover={prefersReducedMotion ? {} : { scale: 1.02, y: -1 }}
            whileTap={prefersReducedMotion ? {} : { scale: 0.98 }}
            transition={{ duration: 0.15, ease: "easeOut" }}
            aria-label="Navigate to scripts collection page"
          >
            <span className="flex items-center justify-center gap-2">
              <Play className="h-4 w-4 transition-transform group-hover:translate-x-1 sm:h-5 sm:w-5" />
              <span className="text-sm sm:text-base">Browse Collection</span>
            </span>
          </motion.button>
        </motion.div>

        {/* Trust Badges */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.8 }}
          className="mb-8 flex flex-wrap items-center justify-center gap-3 px-4 sm:mb-10 sm:gap-4"
        >
          <div className="flex items-center gap-1.5 rounded-full border border-green-500/20 bg-green-500/10 px-3 py-1.5 text-xs font-medium text-green-600 backdrop-blur-sm dark:text-green-400 sm:text-sm">
            <Check className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Open Source</span>
          </div>
          <div className="flex items-center gap-1.5 rounded-full border border-blue-500/20 bg-blue-500/10 px-3 py-1.5 text-xs font-medium text-blue-600 backdrop-blur-sm dark:text-blue-400 sm:text-sm">
            <Check className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Community Tested</span>
          </div>
          {totalViews && (
            <div className="flex items-center gap-1.5 rounded-full border border-purple-500/20 bg-purple-500/10 px-3 py-1.5 text-xs font-medium text-purple-600 backdrop-blur-sm dark:text-purple-400 sm:text-sm">
              <Eye className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
              <span>{(totalViews / 1000).toFixed(1)}K+ Views</span>
            </div>
          )}
          <div className="flex items-center gap-1.5 rounded-full border border-amber-500/20 bg-amber-500/10 px-3 py-1.5 text-xs font-medium text-amber-600 backdrop-blur-sm dark:text-amber-400 sm:text-sm">
            <Check className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>PSScriptAnalyzer Validated</span>
          </div>
        </motion.div>

        {/* Error State */}
        {error && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="mb-6 rounded-lg border border-red-500/20 bg-red-500/10 p-4 text-sm text-red-400"
          >
            <p>⚠️ Having trouble loading scripts. Please try again later.</p>
          </motion.div>
        )}
      </motion.div>

      {/* Enhanced Scroll Indicator with Keyboard Support */}
      <motion.div
        className="group focus:ring-primary focus:ring-offset-background absolute bottom-4 left-1/2 -translate-x-1/2 cursor-pointer rounded-lg focus:ring-2 focus:ring-offset-2 focus:outline-none sm:bottom-8"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.8, duration: 0.5 }}
        onClick={scrollToScripts}
        onKeyDown={handleKeyDown}
        tabIndex={0}
        role="button"
        aria-label="Scroll down to see popular scripts"
        whileHover={prefersReducedMotion ? {} : { scale: 1.1 }}
      >
        <motion.div
          animate={prefersReducedMotion ? {} : { y: [0, 8, 0] }}
          transition={{ repeat: Number.POSITIVE_INFINITY, duration: 2 }}
          className="flex flex-col items-center gap-1 p-2 sm:gap-2"
        >
          <span className="text-muted-foreground group-hover:text-foreground text-xs transition-colors">
            Popular Scripts
          </span>
          <ChevronDown className="text-muted-foreground group-hover:text-foreground h-6 w-6 transition-colors sm:h-8 sm:w-8" />
        </motion.div>
      </motion.div>
    </section>
  );
}
