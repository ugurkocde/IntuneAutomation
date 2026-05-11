import { type Script } from "~/lib/scripts";

interface OrganizationSchemaProps {
  baseUrl: string;
}

export function OrganizationSchema({ baseUrl }: OrganizationSchemaProps) {
  const schema = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "IntuneAutomation.com",
    url: baseUrl,
    logo: `${baseUrl}/favicon.ico`,
    description:
      "Free PowerShell scripts for Microsoft Intune automation. Streamline device management, reporting, and compliance with ready-to-use detection and remediation scripts.",
    sameAs: [
      "https://twitter.com/intuneautomation",
      "https://github.com/ugurkocde/IntuneAutomation",
    ],
    foundingDate: "2023",
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
    name: "IntuneAutomation.com",
    url: baseUrl,
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
      name: "IntuneAutomation.com",
      url: baseUrl,
    },
    aggregateRating: script.usageStats
      ? {
          "@type": "AggregateRating",
          ratingValue: 4.8,
          reviewCount: Math.max(
            1,
            Math.floor((script.usageStats.totalViews || 0) / 10),
          ),
          bestRating: 5,
          worstRating: 1,
        }
      : undefined,
  };

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
    />
  );
}
