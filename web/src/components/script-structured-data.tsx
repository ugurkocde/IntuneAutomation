import type { Script } from "~/lib/scripts";

interface ScriptStructuredDataProps {
  script: Script;
  url: string;
}

export function ScriptStructuredData({ script, url }: ScriptStructuredDataProps) {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: script.title,
    description: script.description,
    applicationCategory: "BusinessApplication",
    applicationSubCategory: script.category || "DeviceManagement",
    operatingSystem: "Windows 10, Windows 11",
    softwareVersion: script.version || "1.0.0",
    author: {
      "@type": "Organization",
      name: script.author || "IntuneAutomation.com",
      url: "https://intuneautomation.com",
    },
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
    url,
    downloadUrl: script.githubUrl || url,
    softwareRequirements: "PowerShell 5.1 or later, Microsoft Graph PowerShell SDK",
    keywords: [...script.tags, "PowerShell", "Microsoft Intune", "Automation", "Script"].join(", "),
    datePublished: script.lastUpdated || new Date().toISOString(),
    dateModified: script.lastUpdated || new Date().toISOString(),
    interactionStatistic: script.usageStats ? [
      {
        "@type": "InteractionCounter",
        interactionType: "https://schema.org/ViewAction",
        userInteractionCount: script.usageStats.totalViews || 0,
      },
      {
        "@type": "InteractionCounter",
        interactionType: "https://schema.org/DownloadAction",
        userInteractionCount: script.usageStats.totalDownloads || 0,
      },
    ] : undefined,
    softwareHelp: {
      "@type": "WebPage",
      url: "https://intuneautomation.com/blog/",
    },
    isAccessibleForFree: true,
    license: "https://opensource.org/licenses/MIT",
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}

export function BreadcrumbStructuredData({ items }: { items: Array<{ name: string; url?: string }> }) {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      ...(item.url && { item: item.url }),
    })),
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}