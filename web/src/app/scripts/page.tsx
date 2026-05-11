import type { Metadata } from "next";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import SearchDialog from "~/components/search-dialog";
import { ScriptsProvider } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";
import FullScriptGallery from "~/components/full-script-gallery";
import FloatingSubscriptionCTA from "~/components/floating-subscription-cta";
import { BreadcrumbSchema } from "~/components/structured-data";

export const metadata: Metadata = {
  title: "All Scripts - IntuneAutomation.com",
  description:
    "Browse 50+ free PowerShell scripts for Intune automation. Find detection scripts, remediation scripts, and reporting tools. Filter by operational, reporting, or notification scripts.",
};

export default function ScriptsPage() {
  const baseUrl = "https://intuneautomation.com";
  const breadcrumbItems = [{ name: "Home", url: "/" }, { name: "All Scripts" }];

  return (
    <>
      <BreadcrumbSchema baseUrl={baseUrl} items={breadcrumbItems} />
      <AnalyticsProvider>
        <ScriptsProvider>
          <div className="bg-background flex min-h-screen flex-col">
            <Navbar />
            <main className="flex-1">
              <FullScriptGallery />
            </main>
            <SearchDialog />
            <FloatingSubscriptionCTA />
            <Footer />
          </div>
        </ScriptsProvider>
      </AnalyticsProvider>
    </>
  );
}
