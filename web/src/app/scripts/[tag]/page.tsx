import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import SearchDialog from "~/components/search-dialog";
import { ScriptsProvider } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";
import FloatingSubscriptionCTA from "~/components/floating-subscription-cta";
import { BreadcrumbSchema } from "~/components/structured-data";
import TagScriptGallery from "~/components/tag-script-gallery";
import { allTags, type ScriptTag } from "~/lib/scripts";

interface PageProps {
  params: Promise<{ tag: string }>;
}

// Tag descriptions for SEO
const tagDescriptions: Record<ScriptTag, string> = {
  Devices:
    "PowerShell scripts for managing and automating Microsoft Intune device operations, including enrollment, compliance, and inventory management.",
  Compliance:
    "Automate Intune compliance policies and monitoring with these PowerShell scripts. Track device compliance status and enforce security policies.",
  Apps: "Scripts for managing Intune application deployment, updates, and monitoring. Automate app assignments and track installation status.",
  Reporting:
    "Generate comprehensive reports from Microsoft Intune data. Export device, user, and application information for analysis.",
  Diagnostics:
    "Troubleshoot and diagnose Intune issues with these PowerShell scripts. Collect logs, analyze errors, and resolve common problems.",
  Security:
    "Enhance Intune security with automated scripts for threat detection, security baselines, and vulnerability management.",
  Configuration:
    "Automate Intune configuration profiles and settings management. Deploy consistent configurations across your device fleet.",
  Operational:
    "Streamline day-to-day Intune operations with these automation scripts. Bulk operations, maintenance tasks, and workflow automation.",
  Monitoring:
    "Monitor Intune health, performance, and alerts with PowerShell automation. Set up proactive monitoring and alerting systems.",
  Notification:
    "Set up automated notifications and alerts for Intune events. Email reports, Teams notifications, and custom alerting solutions.",
  Remediation:
    "Automated detection and remediation scripts for Intune. Fix common issues automatically and maintain device health.",
};

// Normalize tag for URL
function normalizeTag(tag: string): ScriptTag | null {
  const normalized = tag.toLowerCase().replace(/-/g, "");
  return allTags.find((t) => t.toLowerCase() === normalized) || null;
}

export async function generateMetadata({
  params,
}: PageProps): Promise<Metadata> {
  const { tag } = await params;
  const scriptTag = normalizeTag(tag);

  if (!scriptTag) {
    return {
      title: "Tag Not Found - IntuneAutomation.com",
      description: "The requested tag could not be found.",
    };
  }

  return {
    title: `${scriptTag} Scripts - IntuneAutomation.com`,
    description: tagDescriptions[scriptTag],
    openGraph: {
      title: `${scriptTag} PowerShell Scripts for Microsoft Intune`,
      description: tagDescriptions[scriptTag],
      type: "website",
      url: `https://intuneautomation.com/scripts/${tag}`,
    },
    alternates: {
      canonical: `https://intuneautomation.com/scripts/${tag}`,
    },
  };
}

export default async function TagPage({ params }: PageProps) {
  const { tag } = await params;
  const scriptTag = normalizeTag(tag);

  if (!scriptTag) {
    notFound();
  }

  const baseUrl = "https://intuneautomation.com";
  const breadcrumbItems = [
    { name: "Home", url: "/" },
    { name: "Scripts", url: "/scripts" },
    { name: scriptTag },
  ];

  return (
    <>
      <BreadcrumbSchema baseUrl={baseUrl} items={breadcrumbItems} />
      <AnalyticsProvider>
        <ScriptsProvider>
          <div className="bg-background flex min-h-screen flex-col">
            <Navbar />
            <main className="flex-1">
              <TagScriptGallery
                tag={scriptTag}
                description={tagDescriptions[scriptTag]}
              />
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

// Generate static params for all tags
export async function generateStaticParams() {
  return allTags.map((tag) => ({
    tag: tag.toLowerCase(),
  }));
}
