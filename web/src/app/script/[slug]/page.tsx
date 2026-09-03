import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ScriptDetailPageWrapper } from "~/components/script-detail-page-wrapper";
import {
  ScriptStructuredData,
  ScriptFAQStructuredData,
  BreadcrumbStructuredData,
} from "~/components/script-structured-data";
import type { Script } from "~/lib/scripts";
import { githubService } from "~/lib/github";

interface PageProps {
  params: Promise<{ slug: string }>;
}

// Support both slug and ID for backward compatibility with older links.
function findScript(scripts: Script[], slug: string): Script | undefined {
  return scripts.find((s) => s.slug === slug || s.id === slug);
}

// This function generates metadata for each script page
export async function generateMetadata({
  params,
}: PageProps): Promise<Metadata> {
  const { slug } = await params;

  let scripts: Script[];
  try {
    scripts = await githubService.fetchAllScripts();
  } catch (error) {
    console.error(
      `Error loading catalog for metadata of /script/${slug}:`,
      error,
    );
    return {
      title: "Error Loading Script",
      description: "An error occurred while loading the script.",
      robots: { index: false, follow: false },
    };
  }

  const script = findScript(scripts, slug);
  if (!script) {
    return {
      title: "Script Not Found",
      description: "The requested script could not be found.",
      robots: { index: false, follow: false },
    };
  }

  return {
    // Short title — root layout's title template appends "| IntuneAutomation".
    title: script.title,
    description:
      script.description ||
      `PowerShell script for ${script.title}. Automate Microsoft Intune tasks efficiently.`,
    keywords: [
      "Microsoft Intune",
      "PowerShell",
      "Automation",
      "Script",
      script.title,
      ...script.tags,
    ].join(", "),
    openGraph: {
      title: `${script.title} | IntuneAutomation`,
      description:
        script.description || `PowerShell script for ${script.title}`,
      type: "article",
      url: `https://intuneautomation.com/script/${slug}/`,
      siteName: "IntuneAutomation",
    },
    twitter: {
      card: "summary",
      title: `${script.title} | IntuneAutomation`,
      description:
        script.description || `PowerShell script for ${script.title}`,
    },
    alternates: {
      canonical: `/script/${slug}/`,
    },
  };
}

export default async function ScriptPage({ params }: PageProps) {
  const { slug } = await params;

  // No blanket try/catch here on purpose. If the catalog cannot be loaded,
  // fetchAllScripts throws and Next.js renders error.tsx with an uncached 500.
  // Wrapping that in notFound() would let ISR cache a 404 for every script
  // requested during a transient GitHub outage.
  const [scripts, permissionsData] = await Promise.all([
    githubService.fetchAllScripts(),
    githubService.fetchPermissionsData(),
  ]);

  if (scripts.length === 0) {
    throw new Error("Script catalog is empty; refusing to render a 404");
  }

  const script = findScript(scripts, slug);
  if (!script) {
    notFound();
  }

  const scriptUrl = `https://intuneautomation.com/script/${slug}/`;
  const breadcrumbItems = [
    { name: "Home", url: "https://intuneautomation.com/" },
    { name: "Scripts", url: "https://intuneautomation.com/scripts/" },
    { name: script.title },
  ];

  // Pass script data and permissions as JSON to avoid serialization issues
  return (
    <>
      <ScriptStructuredData script={script} url={scriptUrl} />
      <ScriptFAQStructuredData script={script} />
      <BreadcrumbStructuredData items={breadcrumbItems} />
      <ScriptDetailPageWrapper
        script={JSON.parse(JSON.stringify(script))}
        allScripts={JSON.parse(JSON.stringify(scripts))}
        permissionsData={JSON.parse(JSON.stringify(permissionsData))}
      />
    </>
  );
}

// Generate static paths for better SEO (optional, for most popular scripts)
export async function generateStaticParams() {
  try {
    const scripts = await githubService.fetchAllScripts();

    // Generate paths for all scripts (both slug and ID for backward compatibility)
    const paths: { slug: string }[] = [];
    scripts.forEach((script: Script) => {
      paths.push({ slug: script.slug });
      paths.push({ slug: script.id }); // Keep ID for backward compatibility
    });
    return paths;
  } catch (error) {
    console.error("Error generating static params:", error);
    return [];
  }
}
