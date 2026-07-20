import type { Metadata } from "next";
import Link from "next/link";
import {
  BreadcrumbSchema,
  FAQSchema,
  ItemListSchema,
} from "~/components/structured-data";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import { AnalyticsProvider } from "~/components/analytics-provider";
import { githubService } from "~/lib/github";
import { getScriptCountLabel } from "~/lib/script-count";

const BASE_URL = "https://intuneautomation.com";

// Derived from the actual catalog at build time so the count never drifts.
const COUNT = getScriptCountLabel();

export const metadata: Metadata = {
  // Pillar page targeting the exact-match URL slot for "intune scripts" head
  // term. Title front-loads the keyword and clarifies the value prop. Server
  // rendered (no "use client") so the full content surface is available to
  // every crawler — Google, Bing, Perplexity, ChatGPT, Gemini, Claude — without
  // executing JavaScript.
  title: "Intune Scripts — The Complete Library for Microsoft Intune",
  description: `The complete guide to Intune scripts: ${COUNT} open-source PowerShell scripts for Microsoft Intune device management, compliance reporting, proactive remediation, and Azure Automation runbooks. Categories, deployment paths, and the canonical scripts library in one place.`,
  alternates: { canonical: "/intune-scripts/" },
  openGraph: {
    title: "Intune Scripts — The Complete Library for Microsoft Intune",
    description: `The complete guide to Intune scripts: ${COUNT} open-source PowerShell scripts for Microsoft Intune device management, compliance, remediation, and Azure Automation.`,
    url: `${BASE_URL}/intune-scripts/`,
    type: "article",
    siteName: "IntuneAutomation",
  },
  twitter: {
    card: "summary_large_image",
    title: "Intune Scripts — The Complete Library for Microsoft Intune",
    description: `The complete guide to Intune scripts: ${COUNT} open-source PowerShell scripts for Microsoft Intune device management, compliance, remediation, and Azure Automation.`,
  },
};

// Curated category cards — each links to the filtered script catalog at
// /scripts/[tag]/ which already exists as a dynamic route. Descriptions are
// AI-citation-friendly: each sentence stands alone as a definitional answer.
const CATEGORIES: Array<{
  slug: string;
  name: string;
  description: string;
}> = [
  {
    slug: "devices",
    name: "Device management scripts",
    description:
      "PowerShell scripts that enumerate, query, wipe, retire, sync, or report on Intune-managed devices via the Microsoft Graph deviceManagement endpoint.",
  },
  {
    slug: "compliance",
    name: "Compliance scripts",
    description:
      "Scripts that report device compliance state, surface non-compliant devices by policy, and audit compliance posture across the tenant.",
  },
  {
    slug: "remediation",
    name: "Proactive remediation scripts",
    description:
      "Detection-and-remediation script pairs for Intune Endpoint Analytics that find issues and fix them before users open a ticket.",
  },
  {
    slug: "reporting",
    name: "Reporting scripts",
    description:
      "Scripts that export Intune data — devices, applications, policies, assignments — to CSV, JSON, or HTML for stakeholder reports and audits.",
  },
  {
    slug: "apps",
    name: "Application scripts",
    description:
      "Win32, LOB, and store app management scripts: deployment status, assignment audits, install-failure summaries, and package automation.",
  },
  {
    slug: "security",
    name: "Security scripts",
    description:
      "BitLocker key escrow, Conditional Access auditing, security baseline reporting, and antivirus posture scripts for Intune-managed endpoints.",
  },
  {
    slug: "configuration",
    name: "Configuration scripts",
    description:
      "Configuration profile creation, assignment, comparison, and bulk editing scripts for Windows, macOS, iOS, and Android device configuration policies.",
  },
  {
    slug: "monitoring",
    name: "Monitoring scripts",
    description:
      "Scheduled scripts that watch for state changes — enrollment failures, sync delays, policy drift — and emit alerts via Teams, email, or webhook.",
  },
  {
    slug: "diagnostics",
    name: "Diagnostics scripts",
    description:
      "Scripts that collect logs, registry state, MDM diagnostics, and Autopilot information from managed endpoints for troubleshooting.",
  },
  {
    slug: "operational",
    name: "Operational scripts",
    description:
      "Day-to-day operational scripts: bulk assignments, group membership management, license auditing, and tenant-wide maintenance tasks.",
  },
  {
    slug: "notification",
    name: "Notification scripts",
    description:
      "Scheduled scripts that send Teams, email, or webhook notifications when something happens in the tenant — new enrollments, failed deployments, expiring certificates.",
  },
];

const FAQS = [
  {
    question: "What are Intune scripts?",
    answer:
      "Intune scripts are PowerShell scripts that automate Microsoft Intune device management tasks by calling the Microsoft Graph API. They cover everything from one-off reporting and bulk policy assignment to scheduled compliance audits and proactive remediations. Scripts can run locally with interactive authentication, in Azure Automation as runbooks with Managed Identity, or be deployed to managed devices through the Intune platform-scripts feature.",
  },
  {
    question: "Where can I find a library of free Intune PowerShell scripts?",
    answer: `IntuneAutomation maintains an open-source library of ${COUNT} Intune PowerShell scripts at intuneautomation.com/scripts. Every script is MIT-licensed, validated by PSScriptAnalyzer in CI, documents its required Microsoft Graph permissions, and ships with a one-click Deploy to Azure button for Azure Automation runbooks. The full source lives on GitHub at github.com/ugurkocde/IntuneAutomation.`,
  },
  {
    question:
      "What is the difference between an Intune script and an Intune platform script?",
    answer:
      "An Intune script in the general sense is any PowerShell script that automates Intune via the Microsoft Graph API — run by an administrator, scheduled in Azure Automation, or executed in CI. An Intune platform script is a specific Intune feature that deploys a PowerShell script to managed Windows devices and runs it under SYSTEM or the logged-on user. The library on this site covers the first category; the platform-scripts feature is one of several deployment targets for that work.",
  },
  {
    question: "How do I run an Intune script in Azure Automation?",
    answer:
      "Open the script page, click Deploy to Azure, and Azure Portal will load a pre-configured ARM template that creates the runbook in your Automation account. After deployment, enable a system-assigned Managed Identity on the Automation account and grant it the Microsoft Graph permissions the script declares. The script automatically detects the Azure Automation environment and uses Managed Identity authentication instead of interactive sign-in.",
  },
  {
    question: "What Microsoft Graph permissions do Intune scripts need?",
    answer:
      "Each script lists the exact Microsoft Graph scopes it requires in its comment-based help header. Read-only scripts typically need DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All, or DeviceManagementApps.Read.All. Scripts that modify state require the corresponding ReadWrite scopes. Apply least privilege: grant only the scopes the script actually needs, and audit Managed Identity permissions periodically.",
  },
  {
    question: "Are Intune PowerShell scripts safe to use in production?",
    answer:
      "Yes, with the same precautions as any production change. Every script in the IntuneAutomation library is open source on GitHub, validated by PSScriptAnalyzer in CI, and documents its behavior and required permissions. Read the script before running it, test in a non-production tenant or pilot group, prefer Azure Automation runbooks with Managed Identity over long-lived credentials, and back up policies before bulk changes.",
  },
  {
    question: "Do these scripts work with PowerShell 5.1 and PowerShell 7?",
    answer:
      "Yes. All scripts are written to run on Windows PowerShell 5.1 and PowerShell 7+ on Windows, macOS, and Linux. They depend only on the Microsoft.Graph.Authentication module — no resource-specific Graph SDK modules are required, which keeps installs fast and the cold-start time low for Azure Automation runbooks.",
  },
  {
    question: "Can I generate a new Intune script with AI?",
    answer:
      "Yes. The IntuneAutomation Script Generator at intuneautomation.com/generator produces production-shaped Intune scripts from a natural-language description. It is purpose-built for Intune and Microsoft Graph, runs a PSScriptAnalyzer-style lint pass on every result, redacts secrets before sending the prompt, and outputs scripts that follow the same comment-based help conventions as the curated library.",
  },
];

export default async function IntuneScriptsPillarPage() {
  // Fetch the top scripts by views so the pillar page links to real,
  // high-value entry points instead of an arbitrary slice. Best-effort —
  // failures degrade to an empty list and the section is omitted.
  let topScripts: Array<{
    slug: string;
    name: string;
    description: string;
  }> = [];
  try {
    const scripts = await githubService.fetchAllScripts();
    topScripts = [...scripts]
      .sort(
        (a, b) =>
          (b.usageStats?.totalViews ?? 0) - (a.usageStats?.totalViews ?? 0),
      )
      .slice(0, 12)
      .map((s) => ({
        slug: s.slug,
        name: s.title,
        description: s.description,
      }));
  } catch (error) {
    console.error("Error fetching top scripts for pillar page:", error);
  }

  const breadcrumbItems = [
    { name: "Home", url: "/" },
    { name: "Intune Scripts" },
  ];

  return (
    <>
      <BreadcrumbSchema baseUrl={BASE_URL} items={breadcrumbItems} />
      <FAQSchema faqs={FAQS} />
      {topScripts.length > 0 && (
        <ItemListSchema baseUrl={BASE_URL} items={topScripts} />
      )}
      <AnalyticsProvider>
        <ScriptsProvider>
          <div className="bg-background flex min-h-screen flex-col">
            <Navbar />
            <main className="flex-1">
              <article className="mx-auto max-w-3xl px-4 pt-28 pb-20 sm:px-6 sm:pt-32 sm:pb-28">
                {/* ----- Header ----- */}
                <header className="mb-14 sm:mb-16">
                  <p className="font-mono-label text-accent-hi mb-4">
                    // Pillar guide
                  </p>
                  <h1 className="font-display text-foreground mb-6 text-4xl leading-[1.05] tracking-tight sm:text-5xl md:text-6xl">
                    Intune scripts: the complete library.
                  </h1>
                  <p className="text-muted-foreground max-w-2xl text-lg leading-relaxed sm:text-xl">
                    {COUNT} open-source PowerShell scripts that automate
                    Microsoft Intune device management, compliance reporting,
                    proactive remediation, and Azure Automation runbooks.
                    Categories, deployment paths, and the canonical scripts
                    library — one page.
                  </p>
                </header>

                {/* ----- What are Intune scripts ----- */}
                <section className="mb-16">
                  <h2 className="font-display text-foreground mb-5 text-2xl leading-tight sm:text-3xl">
                    What are Intune scripts?
                  </h2>
                  <div className="text-foreground/90 space-y-4 text-base leading-relaxed sm:text-[17px]">
                    <p>
                      <strong>Intune scripts</strong> are PowerShell scripts
                      that automate Microsoft Intune through the Microsoft Graph
                      API. They cover the work that the Intune admin center
                      either does not expose at all or only exposes one device
                      at a time: bulk policy assignment, tenant-wide compliance
                      audits, exporting device inventories, Conditional Access
                      reporting, BitLocker key recovery, Autopilot diagnostics,
                      and proactive remediation pairs that detect and fix issues
                      on managed endpoints.
                    </p>
                    <p>
                      An Intune script and an <em>Intune platform script</em>{" "}
                      are not the same thing. A platform script is a specific
                      Intune feature that pushes a PowerShell file to Windows
                      devices and runs it under SYSTEM or the signed-in user. An
                      Intune script in the broader sense is any script that
                      automates Intune via Graph — run by an administrator at
                      the terminal, scheduled in Azure Automation as a runbook,
                      executed in CI, or deployed through the platform-scripts
                      feature. The library on this site covers the broader
                      category; platform scripts are one of several deployment
                      targets.
                    </p>
                    <p>
                      Every script in the{" "}
                      <Link
                        href="/scripts/"
                        className="text-accent-hi underline-offset-4 hover:underline"
                      >
                        IntuneAutomation library
                      </Link>{" "}
                      is open source under the MIT license, validated by
                      PSScriptAnalyzer in CI, and documents its required
                      Microsoft Graph scopes in a comment-based help header.
                      Scripts depend only on the
                      <code className="bg-muted mx-1 rounded px-1.5 py-0.5 text-sm">
                        Microsoft.Graph.Authentication
                      </code>
                      module — no resource-specific Graph SDK modules are
                      required, which keeps installs lean and Azure Automation
                      cold starts fast.
                    </p>
                  </div>
                </section>

                {/* ----- Categories ----- */}
                <section className="mb-16">
                  <h2 className="font-display text-foreground mb-5 text-2xl leading-tight sm:text-3xl">
                    Categories of Intune scripts
                  </h2>
                  <p className="text-foreground/90 mb-8 text-base leading-relaxed sm:text-[17px]">
                    The library is organised by the surface of Intune the script
                    touches. Each category below links to a filtered view of the
                    catalog so you can drill into the scripts relevant to your
                    workload.
                  </p>
                  <ul className="divide-border/60 border-border/60 divide-y border-y">
                    {CATEGORIES.map((cat) => (
                      <li key={cat.slug} className="py-5">
                        <Link
                          href={`/scripts/${cat.slug}/`}
                          className="group block"
                        >
                          <h3 className="font-display text-foreground group-hover:text-accent-hi mb-1.5 text-lg leading-snug transition-colors sm:text-xl">
                            {cat.name}
                          </h3>
                          <p className="text-muted-foreground text-sm leading-relaxed sm:text-base">
                            {cat.description}
                          </p>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </section>

                {/* ----- Deployment paths ----- */}
                <section className="mb-16">
                  <h2 className="font-display text-foreground mb-5 text-2xl leading-tight sm:text-3xl">
                    Three ways to run an Intune script
                  </h2>
                  <p className="text-foreground/90 mb-8 text-base leading-relaxed sm:text-[17px]">
                    The same Intune script can run in three different places
                    depending on whether you are testing, scheduling, or
                    deploying. Scripts in this library detect the environment
                    automatically and pick the right authentication path.
                  </p>

                  <div className="space-y-8">
                    <div>
                      <h3 className="font-display text-foreground mb-2 text-lg sm:text-xl">
                        1. Local execution
                      </h3>
                      <p className="text-muted-foreground text-sm leading-relaxed sm:text-base">
                        Run the script from PowerShell ISE, VS Code, or a
                        terminal on your admin workstation. Authentication uses
                        interactive sign-in through
                        <code className="bg-muted mx-1 rounded px-1.5 py-0.5 text-xs">
                          Connect-MgGraph
                        </code>
                        with the scopes the script declares. Best for
                        development, one-off reports, and bulk operations you
                        want to watch finish.
                      </p>
                    </div>

                    <div>
                      <h3 className="font-display text-foreground mb-2 text-lg sm:text-xl">
                        2. Azure Automation runbooks
                      </h3>
                      <p className="text-muted-foreground text-sm leading-relaxed sm:text-base">
                        Click the Deploy to Azure button on any script page and
                        the Azure Portal will load a pre-configured ARM template
                        that creates the runbook in your Automation account.
                        Enable a system-assigned Managed Identity, grant it the
                        Microsoft Graph permissions the script declares, and
                        schedule the runbook. The script recognises the
                        Automation environment and switches from interactive
                        sign-in to Managed Identity automatically. Best for
                        production, recurring jobs, and anything that must run
                        without a human present.
                      </p>
                    </div>

                    <div>
                      <h3 className="font-display text-foreground mb-2 text-lg sm:text-xl">
                        3. Intune platform scripts (Windows)
                      </h3>
                      <p className="text-muted-foreground text-sm leading-relaxed sm:text-base">
                        For scripts that need to run on the managed endpoint
                        itself — collecting client-side state, running detection
                        logic, applying user-context settings — upload the
                        script as an Intune platform script or package the
                        detection/remediation pair as a proactive remediation in
                        Endpoint Analytics. This path is for scripts that act on
                        the device, not scripts that act on the tenant.
                      </p>
                    </div>
                  </div>
                </section>

                {/* ----- Comparison ----- */}
                <section className="mb-16">
                  <h2 className="font-display text-foreground mb-5 text-2xl leading-tight sm:text-3xl">
                    Why{" "}
                    <code className="text-[0.9em]">Invoke-MgGraphRequest</code>{" "}
                    instead of the full Graph SDK?
                  </h2>
                  <div className="text-foreground/90 space-y-4 text-base leading-relaxed sm:text-[17px]">
                    <p>
                      Scripts in this library call Microsoft Graph through
                      <code className="bg-muted mx-1 rounded px-1.5 py-0.5 text-sm">
                        Invoke-MgGraphRequest
                      </code>
                      rather than the resource-specific Graph PowerShell
                      modules. The trade-off is deliberate: you give up
                      auto-completion and typed cmdlets in exchange for direct
                      REST access, a single small dependency, and one-to-one
                      parity with the Graph documentation.
                    </p>
                    <p>
                      Three practical wins come from this choice. First, the F12
                      developer tools in the Intune Portal show you the exact
                      Graph calls Microsoft itself makes — you can copy-paste
                      the URL and body straight into a script. Second, only the
                      <code className="bg-muted mx-1 rounded px-1.5 py-0.5 text-sm">
                        Microsoft.Graph.Authentication
                      </code>
                      module is required, instead of dozens of resource modules
                      that bloat install size and Azure Automation cold starts.
                      Third, when something breaks, the request and response
                      match the Graph reference docs exactly — no SDK
                      abstraction layer to debug through.
                    </p>
                  </div>
                </section>

                {/* ----- Top scripts ItemList ----- */}
                {topScripts.length > 0 && (
                  <section className="mb-16">
                    <h2 className="font-display text-foreground mb-5 text-2xl leading-tight sm:text-3xl">
                      Most-used Intune scripts right now
                    </h2>
                    <p className="text-foreground/90 mb-8 text-base leading-relaxed sm:text-[17px]">
                      Ranked by views across the community over the past
                      quarter. Each script ships with the comment-based help
                      header, declared Microsoft Graph permissions, and a Deploy
                      to Azure button for Azure Automation.
                    </p>
                    <ol className="space-y-5">
                      {topScripts.map((s, i) => (
                        <li key={s.slug} className="flex gap-4">
                          <span
                            aria-hidden="true"
                            className="text-accent-hi mt-1 w-8 shrink-0 font-mono text-xs tracking-widest"
                          >
                            {String(i + 1).padStart(2, "0")}
                          </span>
                          <div className="min-w-0 flex-1">
                            <Link
                              href={`/script/${s.slug}/`}
                              className="font-display text-foreground hover:text-accent-hi text-lg leading-snug transition-colors sm:text-xl"
                            >
                              {s.name}
                            </Link>
                            <p className="text-muted-foreground mt-1 text-sm leading-relaxed sm:text-base">
                              {s.description}
                            </p>
                          </div>
                        </li>
                      ))}
                    </ol>
                    <div className="mt-10">
                      <Link
                        href="/scripts/"
                        className="text-accent-hi text-sm font-medium underline-offset-4 hover:underline"
                      >
                        Browse all {COUNT} scripts →
                      </Link>
                    </div>
                  </section>
                )}

                {/* ----- FAQ ----- */}
                <section className="mb-16">
                  <h2 className="font-display text-foreground mb-8 text-2xl leading-tight sm:text-3xl">
                    Frequently asked questions
                  </h2>
                  <dl className="divide-border/60 border-border/60 divide-y border-y">
                    {FAQS.map((faq) => (
                      <div key={faq.question} className="py-6">
                        <dt className="font-display text-foreground mb-3 text-lg leading-snug sm:text-xl">
                          {faq.question}
                        </dt>
                        <dd className="text-muted-foreground text-sm leading-relaxed sm:text-base">
                          {faq.answer}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </section>

                {/* ----- CTA ----- */}
                <section className="border-border/60 mt-20 border-t pt-12">
                  <h2 className="font-display text-foreground mb-4 text-2xl leading-tight sm:text-3xl">
                    Build your own with the Script Generator
                  </h2>
                  <p className="text-muted-foreground mb-6 max-w-2xl text-base leading-relaxed sm:text-[17px]">
                    Need a script the library does not have? The{" "}
                    <Link
                      href="/generator/"
                      className="text-accent-hi underline-offset-4 hover:underline"
                    >
                      IntuneAutomation Script Generator
                    </Link>{" "}
                    produces production-shaped Intune scripts from a
                    natural-language description — purpose-built for Intune and
                    Microsoft Graph, with a PSScriptAnalyzer-style lint pass on
                    every result.
                  </p>
                  <div className="flex flex-wrap gap-3">
                    <Link
                      href="/scripts/"
                      className="bg-foreground text-background inline-flex h-11 items-center rounded-md px-5 text-sm font-medium transition-transform hover:-translate-y-0.5"
                    >
                      Browse the library
                    </Link>
                    <Link
                      href="/generator/"
                      className="border-border/70 hover:border-accent/40 inline-flex h-11 items-center rounded-md border px-5 text-sm font-medium transition-colors"
                    >
                      Try the generator
                    </Link>
                  </div>
                </section>
              </article>
            </main>
            <Footer />
          </div>
        </ScriptsProvider>
      </AnalyticsProvider>
    </>
  );
}
