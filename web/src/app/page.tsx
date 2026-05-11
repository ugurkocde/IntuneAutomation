import {
  OrganizationSchema,
  WebSiteSchema,
  FAQSchema,
  PersonSchema,
  HowToSchema,
  BreadcrumbSchema,
} from "~/components/structured-data";
import HomeClient from "./page-client";

export default function Home() {
  const baseUrl = "https://intuneautomation.com";

  // FAQ JSON-LD — mirrors the visible FAQ in src/components/faq-section.tsx
  // exactly (same 11 questions, identical wording). Ordered to match the user
  // evaluation funnel: prerequisites → security → how to run → Deploy to Azure
  // → maintenance → technical opinions. Google rich results require the
  // structured data to match the visible page content, and AI engines cite
  // these strings verbatim, so keep answers self-contained and authoritative.
  const faqs = [
    {
      question: "What prerequisites do I need to run these scripts?",
      answer:
        "You need PowerShell 5.1 or later, the Microsoft.Graph.Authentication module installed, an active Microsoft 365 tenant with Intune licenses, appropriate Microsoft Graph API permissions (such as DeviceManagementManagedDevices.Read.All), and either interactive sign-in rights or a configured Managed Identity for Azure Automation runbooks. Each script lists the exact Graph scopes it requires.",
    },
    {
      question: "Are these scripts safe to use in production?",
      answer:
        "Yes, but apply the same precautions you would for any production change. Every script is open source on GitHub, validated by PSScriptAnalyzer, and contains a comment-based help header documenting required permissions and behavior. Read the script before running it, test in a non-production tenant or pilot group first, and use Azure Automation runbooks with Managed Identity rather than long-lived credentials.",
    },
    {
      question: "How do I authenticate with Microsoft Graph?",
      answer:
        "Scripts use Connect-MgGraph from the Microsoft.Graph.Authentication module. For local execution they use interactive sign-in, opening a browser window so you can sign in with your admin account. For Azure Automation runbooks they use Managed Identity authentication, which is more secure than storing credentials. Each script automatically detects the execution environment and uses the appropriate method.",
    },
    {
      question: "What are the different ways to run these scripts?",
      answer:
        "There are two main approaches. Local execution uses interactive authentication with Connect-MgGraph, with the script run from PowerShell ISE, VS Code, or a terminal — best for testing, development, and one-off tasks. Azure Automation runbooks use Managed Identity authentication and scheduled execution — best for production environments and recurring tasks. Scripts automatically detect the execution environment and use the appropriate authentication method.",
    },
    {
      question:
        "How do I deploy scripts to Azure Automation using the Deploy to Azure button?",
      answer:
        "Click the Deploy to Azure button on any script page. This opens the Azure Portal with a pre-configured ARM template. Fill in the required parameters such as Resource Group and Automation Account name, then click Create. The script is automatically imported as a runbook in your Azure Automation account, ready to be scheduled or triggered. You'll then need to grant your Managed Identity the Microsoft Graph permissions the script declares.",
    },
    {
      question: "How are these scripts tested before release?",
      answer:
        "Every script in the library is validated by PSScriptAnalyzer in CI and reviewed before merge. Scripts are tested against a real Microsoft 365 tenant for the documented Intune scenarios. Because every script is open source on GitHub, anyone can audit the test history, contributor activity, and issue tracker.",
    },
    {
      question: "How often are the scripts updated?",
      answer:
        "Scripts are updated whenever the underlying Microsoft Graph API changes, when bugs are reported, or when contributors add new functionality. The repository follows standard semantic versioning. Subscribe to the newsletter or watch the GitHub repository to be notified of changes that affect scripts you depend on.",
    },
    {
      question: "What should I do if a script doesn't work?",
      answer:
        "First, check that you have all required prerequisites and Graph permissions, and that you're using the latest version of the script and the Microsoft.Graph.Authentication module. Then open the GitHub repository and search existing issues — if your problem hasn't been reported, file a new issue with the error message, PowerShell version, and a minimal reproduction case.",
    },
    {
      question:
        "Can I modify these scripts for my organization's needs?",
      answer:
        "Yes. All scripts are licensed under the MIT License, so you can copy, modify, redistribute, and use them in commercial settings. We recommend forking the repository so you can track your modifications and pull in upstream improvements when they're released.",
    },
    {
      question:
        "Should I use the v1.0 or beta Microsoft Graph API endpoints?",
      answer:
        "Scripts default to v1.0 endpoints whenever the required functionality is available there, because v1.0 is stable and supported. Some Intune capabilities are only exposed through the beta endpoint — in those cases the script uses beta and clearly documents it in the header. Be aware that Microsoft can change beta endpoints without notice.",
    },
    {
      question:
        "Why do you use Invoke-MgGraphRequest instead of the Graph PowerShell commandlets?",
      answer:
        "Invoke-MgGraphRequest gives direct access to the underlying Microsoft Graph REST API. That means you can use the F12 developer tools in the Intune Portal to inspect the exact API calls Microsoft itself uses and replicate them, you only need the Microsoft.Graph.Authentication module installed (not dozens of resource-specific modules), and troubleshooting is straightforward because the request and response shapes match the Graph documentation exactly.",
    },
  ];

  return (
    <>
      <OrganizationSchema baseUrl={baseUrl} />
      <WebSiteSchema baseUrl={baseUrl} />
      <PersonSchema baseUrl={baseUrl} />
      <HowToSchema baseUrl={baseUrl} />
      <BreadcrumbSchema baseUrl={baseUrl} items={[{ name: "Home", url: "/" }]} />
      <FAQSchema faqs={faqs} />
      <HomeClient />
    </>
  );
}
