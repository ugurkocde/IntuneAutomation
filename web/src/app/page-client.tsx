"use client";

import dynamic from "next/dynamic";
import { MotionConfig } from "framer-motion";
import Navbar from "~/components/navbar";
import HeroSection from "~/components/hero-section";
import PopularScripts from "~/components/popular-scripts";
import WhatsNewStrip from "~/components/whats-new-strip";
import HowItWorksSection from "~/components/how-it-works-section";
import FAQSection from "~/components/faq-section";
import EcosystemSection from "~/components/ecosystem-section";
import Footer from "~/components/footer";
import SearchDialog from "~/components/search-dialog";
import { ScriptsProvider, useScripts } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";

// FloatingSubscriptionCTA initialises a Supabase client at module load (for
// the subscriber-count query) which touches localStorage. Defer it to the
// client so it doesn't blow up during SSR.
const FloatingSubscriptionCTA = dynamic(
  () => import("~/components/floating-subscription-cta"),
  { ssr: false },
);

const ScriptDetail = dynamic(
  () =>
    import("~/components/script-detail").then((mod) => ({
      default: mod.ScriptDetail,
    })),
  {
    ssr: false,
  },
);

export default function Home({ scriptCount }: { scriptCount: number }) {
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
              <HeroSection fallbackCount={scriptCount} />
              <PopularScripts />
              <WhatsNewStrip />
              <HowItWorksSection />
              <FAQSection />
              <EcosystemSection />
            </main>

            <SearchDialog />
            <Footer />
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
