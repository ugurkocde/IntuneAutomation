"use client";

import { lazy, Suspense } from "react";
import dynamic from "next/dynamic";
import { MotionConfig } from "framer-motion";
import Navbar from "~/components/navbar";
import HeroSection from "~/components/hero-section";
import { ScriptsProvider, useScripts } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";

// Lazy load non-critical components
const Footer = lazy(() => import("~/components/footer"));
const SearchDialog = lazy(() => import("~/components/search-dialog"));
const EcosystemSection = lazy(() => import("~/components/ecosystem-section"));
const FAQSection = lazy(() => import("~/components/faq-section"));
const HowItWorksSection = lazy(
  () => import("~/components/how-it-works-section"),
);
const WhatsNewStrip = lazy(() => import("~/components/whats-new-strip"));

// FloatingSubscriptionCTA initialises a Supabase client at module load (for
// the subscriber-count query) which touches localStorage. Defer it to the
// client so it doesn't blow up during SSR.
const FloatingSubscriptionCTA = dynamic(
  () => import("~/components/floating-subscription-cta"),
  { ssr: false },
);

// Dynamic import for heavy components with loading states
const PopularScripts = dynamic(() => import("~/components/popular-scripts"), {
  loading: () => (
    <div className="container mx-auto max-w-7xl px-4 py-16">
      <div className="animate-pulse">
        <div className="bg-muted mx-auto mb-4 h-8 w-48 rounded" />
        <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="bg-muted h-64 rounded-lg" />
          ))}
        </div>
      </div>
    </div>
  ),
});

const ScriptDetail = dynamic(
  () =>
    import("~/components/script-detail").then((mod) => ({
      default: mod.ScriptDetail,
    })),
  {
    ssr: false,
  },
);

export default function Home() {
  return (
    // reducedMotion="user" tells framer-motion to honor the user's OS
    // preference from the first SSR/CSR frame onward — avoids the one-frame
    // animation flash on devices that prefer reduced motion (which happens
    // when useReducedMotion() returns null on initial render).
    <MotionConfig reducedMotion="user">
      <AnalyticsProvider>
        <ScriptsProvider>
          <div className="bg-background flex min-h-screen flex-col">
            <Navbar />
            <main className="flex-1">
              <HeroSection />
              <PopularScripts />
              <Suspense fallback={<div className="h-40" />}>
                <WhatsNewStrip />
              </Suspense>
              <Suspense fallback={<div className="h-64" />}>
                <HowItWorksSection />
              </Suspense>
              {/* FAQSection lives inside main because the navbar scrolls to its
               * id anchor. Give it its own Suspense with min-height so the page
               * doesn't collapse while the chunk loads. */}
              <Suspense fallback={<div className="min-h-[400px]" />}>
                <FAQSection />
              </Suspense>
              <Suspense fallback={<div className="min-h-[300px]" />}>
                <EcosystemSection />
              </Suspense>
            </main>

            <Suspense fallback={<div className="h-0" />}>
              <SearchDialog />
              <Footer />
            </Suspense>
            <FloatingSubscriptionCTA />
          </div>
          <HomeScriptDetail />
        </ScriptsProvider>
      </AnalyticsProvider>
    </MotionConfig>
  );
}

// Component to handle script detail modal on home page
function HomeScriptDetail() {
  const {
    selectedScript,
    setSelectedScript,
    isDetailOpen,
    setIsDetailOpen,
    updateScriptStats,
  } = useScripts();

  return (
    <>
      {selectedScript && isDetailOpen && (
        <ScriptDetail
          script={selectedScript}
          updateScriptStats={updateScriptStats}
          onClose={() => {
            setIsDetailOpen(false);
            setSelectedScript(null);
            // Clear URL state when closing modal on home page
            window.history.pushState(null, "", "/");
          }}
        />
      )}
    </>
  );
}
