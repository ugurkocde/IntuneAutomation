"use client";

import { useEffect, useState } from "react";
import { Plus, Minus } from "lucide-react";
import { Button } from "~/components/ui/button";

interface FAQItem {
  question: string;
  content: React.ReactNode;
}

const faqData: FAQItem[] = [
  {
    question:
      "Why do you use Invoke-MgGraphRequest instead of the Graph PowerShell commandlets?",
    content: (
      <div className="space-y-4">
        <p>
          We use Invoke-MgGraphRequest instead of the specific Microsoft Graph
          PowerShell commandlets for several important reasons:
        </p>
        <ul className="ml-2 space-y-2 sm:ml-4">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1 flex-shrink-0">•</span>
            <div>
              <strong>Browser Network Inspection:</strong> When you browse the
              Intune Portal in your browser, you can use the developer tools
              (F12) to inspect the actual Microsoft Graph API calls being made.
              This allows you to see the exact endpoints, parameters, and
              request structure.
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Minimal Dependencies:</strong> Using Invoke-MgGraphRequest
              only requires the Microsoft.Graph.Authentication module, rather
              than installing multiple specific Graph modules.
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Direct API Access:</strong> You get direct access to the
              raw Microsoft Graph REST API, giving you more control and
              flexibility over the requests.
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Easier Troubleshooting:</strong> You can easily replicate
              and test the same API calls that the Intune Portal uses, making
              debugging much more straightforward.
            </div>
          </li>
        </ul>
      </div>
    ),
  },
  {
    question: "What are the different ways to run these scripts?",
    content: (
      <div className="space-y-4">
        <p>
          You can run these Intune automation scripts in two main ways, each
          with its own advantages:
        </p>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-3 font-semibold">
            Local Execution
          </h4>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Interactive authentication:</strong> Uses your personal
                credentials with Connect-MgGraph
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Manual execution:</strong> Run scripts on-demand from
                PowerShell ISE, VS Code, or terminal
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Best for:</strong> Testing, one-time operations, and
                development
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-3 font-semibold">
            Azure Automation Runbooks
          </h4>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Managed Identity authentication:</strong> Uses
                system-assigned managed identity (no credentials needed)
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Scheduled execution:</strong> Run scripts automatically
                on a schedule
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Best for:</strong> Production environments, recurring
                tasks, and unattended operations
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 pl-4"
          style={{ borderColor: "var(--brand-accent-hi)" }}
        >
          <p className="text-sm">
            <strong>Environment Detection:</strong> Our scripts automatically
            detect the execution environment using{" "}
            <code className="bg-muted rounded px-2 py-1 text-xs">
              $PSPrivateMetadata.JobId.Guid
            </code>
            . When running in Azure Automation, they use Managed Identity
            authentication. When running locally, they prompt for interactive
            authentication.
          </p>
        </div>
      </div>
    ),
  },
  {
    question:
      "How do I deploy scripts to Azure Automation using the Deploy to Azure button?",
    content: (
      <div className="space-y-4">
        <p>
          Many of our scripts include a "Deploy to Azure" button for easy
          deployment to Azure Automation. Here's how it works:
        </p>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-3 font-semibold">
            One-Click Deployment Process
          </h4>
          <ol className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span
                className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium"
                style={{
                  backgroundColor: "var(--brand-accent-hi)",
                  color: "var(--background)",
                }}
              >
                1
              </span>
              <div>
                <strong>Click the Deploy to Azure button</strong> in the
                script's README or documentation
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span
                className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium"
                style={{
                  backgroundColor: "var(--brand-accent-hi)",
                  color: "var(--background)",
                }}
              >
                2
              </span>
              <div>
                <strong>Sign in to Azure Portal</strong> when prompted
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span
                className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium"
                style={{
                  backgroundColor: "var(--brand-accent-hi)",
                  color: "var(--background)",
                }}
              >
                3
              </span>
              <div>
                <strong>Configure deployment parameters:</strong> Choose
                subscription, resource group, and automation account name
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span
                className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium"
                style={{
                  backgroundColor: "var(--brand-accent-hi)",
                  color: "var(--background)",
                }}
              >
                4
              </span>
              <div>
                <strong>Review and create</strong> - Azure will deploy the
                automation account and import the runbook
              </div>
            </li>
          </ol>
        </div>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-3 font-semibold">
            System-Assigned Managed Identity Setup
          </h4>
          <p className="mb-3">
            The deployment automatically configures a system-assigned managed
            identity for secure, credential-free authentication:
          </p>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>No stored credentials:</strong> The managed identity
                eliminates the need to store usernames and passwords
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Automatic permissions:</strong> The deployment template
                assigns the necessary Microsoft Graph permissions
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Azure-managed security:</strong> Azure handles identity
                lifecycle and credential rotation
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-3 font-semibold">
            Post-Deployment Configuration
          </h4>
          <p className="mb-3">After deployment, you may need to:</p>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Grant admin consent:</strong> Approve the Graph API
                permissions in Azure AD
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Configure schedules:</strong> Set up recurring execution
                schedules if needed
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Test the runbook:</strong> Run a test execution to
                verify everything works correctly
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 pl-4"
          style={{ borderColor: "var(--brand-accent-hi)" }}
        >
          <p className="text-sm">
            <strong>Learn more:</strong> For detailed information about managed
            identities in Azure Automation, visit{" "}
            <a
              href="https://learn.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation"
              target="_blank"
              rel="noopener noreferrer"
              className="text-accent-hi underline-offset-4 hover:underline"
            >
              Microsoft's official documentation
            </a>
            .
          </p>
        </div>
      </div>
    ),
  },
  {
    question: "What prerequisites do I need to run these scripts?",
    content: (
      <div className="space-y-4">
        <p>To run the Intune automation scripts, you'll need:</p>
        <ul className="ml-4 space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>PowerShell 5.1 or PowerShell 7+</strong> installed on your
              system
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Microsoft.Graph.Authentication module</strong> - Install
              with:{" "}
              <code className="bg-muted rounded px-2 py-1 text-sm">
                Install-Module Microsoft.Graph.Authentication
              </code>
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Appropriate Azure AD permissions</strong> for your user
              account or app registration
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Microsoft Intune license</strong> and access to the Intune
              portal
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Global Administrator or Intune Administrator role</strong>{" "}
              (depending on the script's requirements)
            </div>
          </li>
        </ul>
      </div>
    ),
  },
  {
    question: "How do I authenticate with Microsoft Graph?",
    content: (
      <div className="space-y-4">
        <p>
          Authentication is typically handled using Connect-MgGraph. Most
          scripts include authentication steps like:
        </p>
        <div className="bg-muted rounded-lg p-3 sm:p-4">
          <pre className="overflow-x-auto text-xs sm:text-sm">
            <code>{`# Interactive authentication
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# Or using app registration
Connect-MgGraph -ClientId "your-app-id" -TenantId "your-tenant-id"`}</code>
          </pre>
        </div>
        <p>
          Make sure to use the minimum required scopes for your specific use
          case.
        </p>
      </div>
    ),
  },
  {
    question: "Are these scripts safe to use in production?",
    content: (
      <div className="space-y-4">
        <p>
          While these scripts are thoroughly tested and used by the community,
          you should:
        </p>
        <ul className="ml-4 space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Always test in a non-production environment first</strong>
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Review the script code</strong> to understand what changes
              it will make
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Backup your current configurations</strong> before running
              any scripts
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Start with a small test group</strong> of devices or users
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Monitor the results</strong> and verify the expected
              outcomes
            </div>
          </li>
        </ul>
        <p className="text-accent-hi font-medium">
          Remember: automation scripts can make widespread changes quickly, so
          proceed with caution.
        </p>
      </div>
    ),
  },
  {
    question: "How are these scripts tested before release?",
    content: (
      <div className="space-y-4">
        <p>
          All scripts undergo automated testing to ensure they work correctly:
        </p>
        <ul className="ml-4 space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Functional testing:</strong> Scripts are tested with a
              demo tenant to verify all Graph API endpoints work correctly and
              produce expected results
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>PSScriptAnalyzer:</strong> PowerShell scripts are
              automatically validated for best practices and potential issues
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>ShellCheck:</strong> Shell scripts are tested using
              ShellCheck for common bugs and code quality
            </div>
          </li>
        </ul>
      </div>
    ),
  },
  {
    question: "Can I modify these scripts for my organization's needs?",
    content: (
      <div className="space-y-4">
        <p>
          Absolutely! These scripts are open-source and designed to be
          customizable:
        </p>
        <ul className="ml-4 space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Fork the repository</strong> to create your own version
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Modify variables and parameters</strong> to match your
              environment
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Add additional logic</strong> for your specific
              requirements
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Contribute improvements</strong> back to the community via
              pull requests
            </div>
          </li>
        </ul>
        <p>
          Just ensure you thoroughly test any modifications before deploying
          them.
        </p>
      </div>
    ),
  },
  {
    question: "How often are the scripts updated?",
    content: (
      <div className="space-y-4">
        <p>The scripts are regularly maintained and updated:</p>
        <ul className="ml-4 space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Bug fixes</strong> are applied as soon as issues are
              identified
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>New features</strong> are added based on community
              feedback and Microsoft Intune updates
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>API changes</strong> are incorporated when Microsoft
              updates the Graph API
            </div>
          </li>
          <li className="flex items-start gap-2">
            <span className="text-accent-hi mt-1">•</span>
            <div>
              <strong>Community contributions</strong> are reviewed and merged
              regularly
            </div>
          </li>
        </ul>
        <p>
          Check the GitHub repository for the latest updates and version
          history.
        </p>
      </div>
    ),
  },
  {
    question: "What should I do if a script doesn't work?",
    content: (
      <div className="space-y-4">
        <p>If you encounter issues with a script:</p>
        <ol className="ml-2 space-y-2 sm:ml-4">
          <li className="flex items-start gap-2 sm:gap-3">
            <span
              className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium sm:h-6 sm:w-6 sm:text-sm"
              style={{
                backgroundColor: "var(--brand-accent-hi)",
                color: "var(--background)",
              }}
            >
              1
            </span>
            <div>
              <strong>Check the prerequisites</strong> - ensure you have the
              required modules and permissions
            </div>
          </li>
          <li className="flex items-start gap-2 sm:gap-3">
            <span
              className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium sm:h-6 sm:w-6 sm:text-sm"
              style={{
                backgroundColor: "var(--brand-accent-hi)",
                color: "var(--background)",
              }}
            >
              2
            </span>
            <div>
              <strong>Review the error message</strong> - PowerShell errors
              often provide specific guidance
            </div>
          </li>
          <li className="flex items-start gap-2 sm:gap-3">
            <span
              className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium sm:h-6 sm:w-6 sm:text-sm"
              style={{
                backgroundColor: "var(--brand-accent-hi)",
                color: "var(--background)",
              }}
            >
              3
            </span>
            <div>
              <strong>Verify your authentication</strong> - ensure you're
              connected to Microsoft Graph with appropriate scopes
            </div>
          </li>
          <li className="flex items-start gap-2 sm:gap-3">
            <span
              className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium sm:h-6 sm:w-6 sm:text-sm"
              style={{
                backgroundColor: "var(--brand-accent-hi)",
                color: "var(--background)",
              }}
            >
              4
            </span>
            <div>
              <strong>Check the GitHub Issues</strong> - someone might have
              already reported and solved the issue
            </div>
          </li>
          <li className="flex items-start gap-2 sm:gap-3">
            <span
              className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-medium sm:h-6 sm:w-6 sm:text-sm"
              style={{
                backgroundColor: "var(--brand-accent-hi)",
                color: "var(--background)",
              }}
            >
              5
            </span>
            <div>
              <strong>Create a new issue</strong> on GitHub with details about
              your environment and the error
            </div>
          </li>
        </ol>
        <p>The community is active and helpful in resolving issues quickly.</p>
      </div>
    ),
  },
  {
    question: "Should I use the v1.0 or beta Microsoft Graph API endpoints?",
    content: (
      <div className="space-y-4">
        <p>
          For Intune automation, we generally recommend using the{" "}
          <strong>beta</strong> endpoints:
        </p>
        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-2 font-semibold">
            Why Beta is Better for Automation:
          </h4>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Richer response data:</strong> Beta endpoints provide
                more detailed information and additional properties
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Latest features:</strong> New Intune capabilities are
                available in beta before being promoted to v1.0
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Better for complex automation:</strong> More
                comprehensive data means fewer API calls needed
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 py-2 pl-5"
          style={{
            borderColor:
              "color-mix(in oklab, var(--brand-accent) 35%, transparent)",
          }}
        >
          <h4 className="text-foreground mb-2 font-semibold">
            Important Considerations:
          </h4>
          <ul className="ml-4 space-y-2">
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Response structure may change:</strong> Beta endpoints
                can have breaking changes between versions
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Already stable in practice:</strong> Most beta Intune
                endpoints are very stable and widely used
              </div>
            </li>
            <li className="flex items-start gap-2">
              <span className="text-accent-hi mt-1">•</span>
              <div>
                <strong>Monitor for changes:</strong> Subscribe to Microsoft
                Graph changelog for any breaking changes
              </div>
            </li>
          </ul>
        </div>

        <div
          className="border-l-2 pl-4"
          style={{ borderColor: "var(--brand-accent-hi)" }}
        >
          <p className="text-muted-foreground text-sm">
            <strong>Our recommendation:</strong> Use beta endpoints for
            automation scripts, as the benefits (richer data, latest features)
            outweigh the minimal risk of changes for most Intune scenarios.
          </p>
        </div>
      </div>
    ),
  },
];

export default function FAQSection() {
  const [openItems, setOpenItems] = useState<number[]>([]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (window.location.hash !== "#faq-section") return;
    document
      .getElementById("faq-section")
      ?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, []);

  const toggleItem = (index: number) => {
    setOpenItems((prev) =>
      prev.includes(index) ? prev.filter((i) => i !== index) : [...prev, index],
    );
  };

  return (
    <section
      id="faq-section"
      aria-labelledby="faq-heading"
      className="border-border/60 border-t px-4 py-24 sm:py-32"
    >
      <div className="mx-auto max-w-3xl">
        {/* Opener */}
        <div className="mb-14 sm:mb-16">
          <p className="font-mono-label text-accent-hi mb-4">// FAQ</p>
          <h2
            id="faq-heading"
            className="font-display text-foreground mb-4 text-4xl leading-[1.05] sm:text-5xl md:text-6xl"
          >
            Questions you might have.
          </h2>
          <p className="text-muted-foreground max-w-xl text-base sm:text-lg">
            Prerequisites, security posture, how to deploy, and the technical
            choices behind the library.
          </p>
        </div>

        {/* FAQ items — numbered manifest accordion */}
        <ul className="border-b" style={{ borderColor: "var(--brand-rule)" }}>
          {faqData.map((faq, index) => {
            const isOpen = openItems.includes(index);
            const num = String(index + 1).padStart(2, "0");

            return (
              <li
                key={index}
                className="border-t"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                <button
                  type="button"
                  onClick={() => toggleItem(index)}
                  aria-expanded={isOpen}
                  className="group flex w-full items-baseline gap-5 py-6 text-left transition-colors"
                >
                  <span
                    className="text-accent w-8 shrink-0 font-mono text-xs tracking-widest sm:text-sm"
                    aria-hidden="true"
                  >
                    {num}
                  </span>
                  <span className="font-display text-foreground flex-1 text-xl leading-snug sm:text-2xl">
                    {faq.question}
                  </span>
                  <span
                    className="text-muted-foreground group-hover:text-accent-hi shrink-0 transition-colors"
                    aria-hidden="true"
                  >
                    {isOpen ? (
                      <Minus className="h-4 w-4" strokeWidth={1.5} />
                    ) : (
                      <Plus className="h-4 w-4" strokeWidth={1.5} />
                    )}
                  </span>
                </button>

                {isOpen && (
                  <div className="animate-in fade-in pb-8 pl-[3.25rem] duration-200">
                    <div className="text-muted-foreground max-w-2xl text-sm leading-relaxed sm:text-base">
                      {faq.content}
                    </div>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
}
