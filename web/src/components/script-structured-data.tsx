import type { Script } from "~/lib/scripts";

interface ScriptStructuredDataProps {
  script: Script;
  url: string;
}

export function ScriptStructuredData({
  script,
  url,
}: ScriptStructuredDataProps) {
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
    softwareRequirements:
      "PowerShell 5.1 or later, Microsoft Graph PowerShell SDK",
    keywords: [
      ...script.tags,
      "PowerShell",
      "Microsoft Intune",
      "Automation",
      "Script",
    ].join(", "),
    datePublished: script.lastUpdated || new Date().toISOString(),
    dateModified: script.lastUpdated || new Date().toISOString(),
    interactionStatistic: script.usageStats
      ? [
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
        ]
      : undefined,
    softwareHelp: {
      "@type": "WebPage",
      url: "https://intuneautomation.com/blog/",
    },
    isAccessibleForFree: true,
    license: "https://opensource.org/licenses/MIT",
  };

  // Trusted, server-controlled JSON-LD payload — safe from XSS.
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}

/**
 * Per-script FAQPage JSON-LD. Synthesises 4-6 Q&A pairs from the script's
 * already-parsed metadata (description, permissions, tags, lastUpdated,
 * execution mode) rather than re-parsing the PowerShell comment-based help
 * block — the structured fields are higher signal and don't drift when the
 * script body is reformatted. Each script page becomes individually eligible
 * for FAQ rich results in Google and citation-friendly for AI engines.
 *
 * The visible page already contains the same information across the
 * description, permissions list, and metadata strip, so the FAQPage schema
 * does not violate Google's "content must be visible to users" requirement.
 */
export function ScriptFAQStructuredData({ script }: { script: Script }) {
  const faqs = buildScriptFaqs(script);
  if (faqs.length === 0) return null;

  const structuredData = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((faq) => ({
      "@type": "Question",
      name: faq.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: faq.answer,
      },
    })),
  };

  // Trusted, server-controlled JSON-LD payload — safe from XSS.
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}

function buildScriptFaqs(
  script: Script,
): Array<{ question: string; answer: string }> {
  const faqs: Array<{ question: string; answer: string }> = [];
  const title = script.title;

  if (script.description) {
    faqs.push({
      question: `What does the ${title} script do?`,
      answer: `${script.description} It is part of the open-source IntuneAutomation library and runs against the Microsoft Graph API.`,
    });
  }

  if (script.permissions && script.permissions.length > 0) {
    const permList = script.permissions.join(", ");
    faqs.push({
      question: `What Microsoft Graph permissions does the ${title} script require?`,
      answer: `The ${title} script requires the following Microsoft Graph permissions: ${permList}. Grant these scopes interactively when running locally with Connect-MgGraph, or assign them to the Azure Automation Managed Identity when running as a runbook.`,
    });
  }

  if (script.tags && script.tags.length > 0) {
    const tagList = script.tags.join(", ");
    faqs.push({
      question: `Which Intune areas does the ${title} script cover?`,
      answer: `The ${title} script applies to: ${tagList}. It targets Microsoft Intune device management workflows in those areas via the Microsoft Graph API.`,
    });
  }

  const isRunbookOnly = script.execution === "RunbookOnly";
  faqs.push({
    question: `How do I run the ${title} script?`,
    answer: isRunbookOnly
      ? `The ${title} script is designed to run as an Azure Automation runbook. Click the Deploy to Azure button on the script page to load a pre-configured ARM template, enable a system-assigned Managed Identity on the Automation account, and grant it the required Microsoft Graph permissions. Schedule the runbook or trigger it on demand from the Automation portal.`
      : `You can run the ${title} script locally from PowerShell 5.1 or PowerShell 7 with interactive authentication via Connect-MgGraph, or deploy it as an Azure Automation runbook with Managed Identity using the Deploy to Azure button on the script page. The script automatically detects the execution environment and uses the appropriate authentication method.`,
  });

  if (script.minRole) {
    faqs.push({
      question: `What Intune role do I need to run the ${title} script?`,
      answer: `Running the ${title} script requires at least the ${script.minRole} role in Microsoft Entra ID (Azure AD), in addition to the declared Microsoft Graph permissions. Apply least privilege and avoid using Global Administrator unless a script explicitly requires it.`,
    });
  }

  if (script.lastUpdated) {
    const dateLabel = new Date(script.lastUpdated).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
    faqs.push({
      question: `When was the ${title} script last updated?`,
      answer: `The ${title} script was last updated on ${dateLabel}. The full commit history and any open issues are available in the IntuneAutomation GitHub repository.`,
    });
  }

  return faqs;
}

export function BreadcrumbStructuredData({
  items,
}: {
  items: Array<{ name: string; url?: string }>;
}) {
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

  // Trusted, server-controlled JSON-LD payload — safe from XSS.
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}
