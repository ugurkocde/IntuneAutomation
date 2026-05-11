import { type Script } from "~/lib/scripts";

interface OrganizationSchemaProps {
  baseUrl: string;
}

export function OrganizationSchema({ baseUrl }: OrganizationSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "IntuneAutomation",
    alternateName: "IntuneAutomation.com",
    url: baseUrl,
    logo: {
      "@type": "ImageObject",
      url: `${baseUrl}/logo.png`,
      width: 512,
      height: 512,
    },
    description:
      "Open-source library of community-maintained PowerShell scripts that automate Microsoft Intune device management, compliance reporting, and Azure Automation runbooks.",
    sameAs: [
      "https://twitter.com/intuneautomation",
      "https://github.com/ugurkocde/IntuneAutomation",
      "https://www.linkedin.com/in/ugurkocde/",
    ],
    foundingDate: "2023",
    founder: {
      "@type": "Person",
      name: "Ugur Koc",
      url: "https://ugurlabs.com",
    },
    parentOrganization: {
      "@type": "Organization",
      name: "UgurLabs",
      url: "https://ugurlabs.com",
    },
    knowsAbout: [
      "Microsoft Intune",
      "PowerShell",
      "Microsoft Graph API",
      "Azure Automation",
      "Endpoint Management",
      "Device Compliance",
      "Mobile Device Management",
    ],
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface WebSiteSchemaProps {
  baseUrl: string;
}

export function WebSiteSchema({ baseUrl }: WebSiteSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "IntuneAutomation",
    alternateName: "IntuneAutomation.com",
    url: baseUrl,
    inLanguage: "en-US",
    publisher: {
      "@type": "Organization",
      name: "IntuneAutomation",
      url: baseUrl,
    },
    potentialAction: {
      "@type": "SearchAction",
      target: {
        "@type": "EntryPoint",
        urlTemplate: `${baseUrl}/?search={search_term_string}`,
      },
      "query-input": "required name=search_term_string",
    },
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface BreadcrumbSchemaProps {
  baseUrl: string;
  items: Array<{
    name: string;
    url?: string;
  }>;
}

export function BreadcrumbSchema({ baseUrl, items }: BreadcrumbSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.url ? `${baseUrl}${item.url}` : undefined,
    })),
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface FAQSchemaProps {
  faqs: Array<{
    question: string;
    answer: string;
  }>;
}

export function FAQSchema({ faqs }: FAQSchemaProps) {
  const schema = {
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

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface SoftwareSourceCodeSchemaProps {
  script: Script;
  baseUrl: string;
}

export function SoftwareSourceCodeSchema({
  script,
  baseUrl,
}: SoftwareSourceCodeSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "SoftwareSourceCode",
    name: script.title,
    description: script.description,
    programmingLanguage: "PowerShell",
    runtimePlatform: "Microsoft Intune",
    codeRepository: script.githubUrl,
    dateModified: script.lastUpdated,
    author: {
      "@type": "Person",
      name: script.author || "IntuneAutomation.com",
    },
    version: script.version,
    keywords: script.tags.join(", "),
    url: `${baseUrl}/script/${script.slug}`,
    isPartOf: {
      "@type": "WebSite",
      name: "IntuneAutomation",
      url: baseUrl,
    },
    license: "https://opensource.org/licenses/MIT",
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
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface PersonSchemaProps {
  baseUrl: string;
}

export function PersonSchema({ baseUrl }: PersonSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "Person",
    name: "Ugur Koc",
    url: "https://ugurlabs.com",
    image: `${baseUrl}/logo.png`,
    sameAs: [
      "https://ugurlabs.com",
      "https://www.linkedin.com/in/ugurkocde/",
      "https://github.com/ugurkocde",
      "https://twitter.com/ugurkocde",
    ],
    knowsAbout: [
      "Microsoft Intune",
      "PowerShell",
      "Microsoft Graph API",
      "Azure Automation",
      "Endpoint Management",
      "Mobile Device Management",
      "Windows Autopilot",
    ],
    worksFor: {
      "@type": "Organization",
      name: "UgurLabs",
      url: "https://ugurlabs.com",
    },
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface HowToSchemaProps {
  baseUrl: string;
}

export function HowToSchema({ baseUrl }: HowToSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "HowTo",
    name: "How to use IntuneAutomation PowerShell scripts",
    description:
      "Browse the IntuneAutomation library, then either copy the PowerShell script and run it locally with Connect-MgGraph, or one-click deploy it to Azure Automation as a scheduled runbook.",
    totalTime: "PT5M",
    supply: [
      {
        "@type": "HowToSupply",
        name: "Microsoft 365 tenant with Intune licenses",
      },
      {
        "@type": "HowToSupply",
        name: "PowerShell 5.1 or later (local) or Azure subscription (cloud)",
      },
    ],
    tool: [
      {
        "@type": "HowToTool",
        name: "Microsoft Graph PowerShell SDK",
      },
    ],
    step: [
      {
        "@type": "HowToStep",
        position: 1,
        name: "Browse the script library",
        text: "Search or filter the IntuneAutomation script library by category, tag, or keyword to find a script that matches your task.",
        url: `${baseUrl}/scripts/`,
      },
      {
        "@type": "HowToStep",
        position: 2,
        name: "Run locally with PowerShell",
        text: "Copy the script, connect to Microsoft Graph with Connect-MgGraph, and execute the script from PowerShell ISE, VS Code, or a terminal.",
      },
      {
        "@type": "HowToStep",
        position: 3,
        name: "Deploy to Azure Automation in one click",
        text: "Click Deploy to Azure on any script page to import the script as a runbook in Azure Automation using a pre-configured ARM template. Schedule the runbook to run on a recurring basis using Managed Identity authentication.",
      },
    ],
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}

interface ItemListSchemaProps {
  baseUrl: string;
  items: Array<{
    name: string;
    slug: string;
    description?: string;
  }>;
}

export function ItemListSchema({ baseUrl, items }: ItemListSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "ItemList",
    name: "Popular IntuneAutomation scripts",
    itemListOrder: "https://schema.org/ItemListOrderDescending",
    numberOfItems: items.length,
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      url: `${baseUrl}/script/${item.slug}/`,
      name: item.name,
      ...(item.description ? { description: item.description } : {}),
    })),
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}
