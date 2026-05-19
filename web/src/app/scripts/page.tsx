import type { Metadata } from "next";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import SearchDialog from "~/components/search-dialog";
import { ScriptsProvider } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";
import FullScriptGallery from "~/components/full-script-gallery";
import FloatingSubscriptionCTA from "~/components/floating-subscription-cta";
import { BreadcrumbSchema, ItemListSchema } from "~/components/structured-data";
import { githubService } from "~/lib/github";

const BASE_URL = "https://intuneautomation.com";

export const metadata: Metadata = {
  // Short title — root layout's title template appends "| IntuneAutomation".
  // Title front-loads the head keyword "Intune PowerShell Scripts" because
  // /scripts/ is the page we most want ranking for catalog-intent searches.
  title: "Intune PowerShell Scripts — 120+ Free, Ready-to-Run",
  description:
    "Browse 120+ free PowerShell scripts for Microsoft Intune automation. Detection, remediation, compliance, reporting and Azure Automation runbooks. Filter by category, deploy in one click.",
  alternates: { canonical: "/scripts/" },
  openGraph: {
    title: "Intune PowerShell Scripts — 120+ Free, Ready-to-Run",
    description:
      "Browse 120+ free PowerShell scripts for Microsoft Intune automation, including Azure Automation runbooks.",
    url: `${BASE_URL}/scripts/`,
    type: "website",
    siteName: "IntuneAutomation",
  },
  twitter: {
    card: "summary_large_image",
    title: "Intune PowerShell Scripts — 120+ Free, Ready-to-Run",
    description:
      "Browse 120+ free PowerShell scripts for Microsoft Intune automation, including Azure Automation runbooks.",
  },
};

export default async function ScriptsPage() {
  const breadcrumbItems = [{ name: "Home", url: "/" }, { name: "All Scripts" }];

  // Fetch scripts server-side so the catalog can expose an ItemList JSON-LD
  // for sitelinks / list-style rich results. Best-effort: failures fall back
  // to an empty list rather than blocking the page render.
  let listItems: Array<{ name: string; slug: string; description?: string }> =
    [];
  try {
    const scripts = await githubService.fetchAllScripts();
    listItems = scripts.slice(0, 25).map((script) => ({
      name: script.title,
      slug: script.slug,
      description: script.description,
    }));
  } catch (error) {
    console.error("Error generating ItemList schema for /scripts:", error);
  }

  return (
    <>
      <BreadcrumbSchema baseUrl={BASE_URL} items={breadcrumbItems} />
      {listItems.length > 0 && (
        <ItemListSchema baseUrl={BASE_URL} items={listItems} />
      )}
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
