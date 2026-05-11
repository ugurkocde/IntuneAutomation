"use client";

import { lazy, Suspense } from "react";
import dynamic from "next/dynamic";
import Navbar from "~/components/navbar";
import HeroSection from "~/components/hero-section";
import { ScriptsProvider, useScripts } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";

// Lazy load non-critical components
const Footer = lazy(() => import("~/components/footer"));
const SearchDialog = lazy(() => import("~/components/search-dialog"));
const EcosystemSection = lazy(() => import("~/components/ecosystem-section"));
const FAQSection = lazy(() => import("~/components/faq-section"));
const FloatingSubscriptionCTA = lazy(
  () => import("~/components/floating-subscription-cta"),
);
const StatsSection = lazy(() => import("~/components/stats-section"));
const HowItWorksSection = lazy(() => import("~/components/how-it-works-section"));

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
    <AnalyticsProvider>
      <ScriptsProvider>
        <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
          <Navbar />
          <main className="flex-1">
            <HeroSection />
            <Suspense fallback={<div className="h-24" />}>
              <StatsSection />
            </Suspense>
            <Suspense fallback={<div className="h-64" />}>
              <HowItWorksSection />
            </Suspense>
            <PopularScripts />
          </main>

          <Suspense fallback={<div className="h-0" />}>
            <SearchDialog />
            <FAQSection />
            <EcosystemSection />
            <FloatingSubscriptionCTA />
            <Footer />
          </Suspense>
        </div>
        <HomeScriptDetail />
      </ScriptsProvider>
    </AnalyticsProvider>
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
