import {
  OrganizationSchema,
  WebSiteSchema,
  FAQSchema,
} from "~/components/structured-data";
import HomeClient from "./page-client";

export default function Home() {
  const baseUrl = "https://intuneautomation.com";

  // FAQ data for structured data
  const faqs = [
    {
      question:
        "Why do you use Invoke-MgGraphRequest instead of the Graph PowerShell commandlets?",
      answer:
        "We use Invoke-MgGraphRequest for several reasons: Browser Network Inspection - you can use F12 developer tools to inspect actual Microsoft Graph API calls in the Intune Portal; Minimal Dependencies - only requires Microsoft.Graph.Authentication module; Direct API Access - provides direct access to the raw Microsoft Graph REST API; Easier Troubleshooting - easily replicate and test the same API calls that the Intune Portal uses.",
    },
    {
      question: "What are the different ways to run these scripts?",
      answer:
        "You can run these scripts in two main ways: Local Execution - uses interactive authentication with Connect-MgGraph, manual execution from PowerShell ISE/VS Code/terminal, best for testing and development. Azure Automation Runbooks - uses Managed Identity authentication, scheduled execution for automation, best for production environments and recurring tasks. Our scripts automatically detect the execution environment and use appropriate authentication.",
    },
    {
      question:
        "How do I deploy scripts to Azure Automation using the Deploy to Azure button?",
      answer:
        "Click the Deploy to Azure button on any script page. This will open Azure Portal with a pre-configured ARM template. Fill in required parameters like Resource Group and Automation Account name, then click Create. The script will be automatically imported as a runbook in your Azure Automation account.",
    },
    {
      question: "What permissions do I need to run these scripts?",
      answer:
        "Required permissions vary by script, but typically include Microsoft Graph API permissions like DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All, or User.Read.All. Each script lists its specific required permissions. For Azure Automation, grant these permissions to the Managed Identity.",
    },
    {
      question: "How can I contribute my own scripts?",
      answer:
        "We welcome contributions! Fork the GitHub repository, add your script following our template format, include proper metadata (title, description, required permissions), test your script thoroughly, then submit a pull request. We'll review and merge quality contributions.",
    },
  ];

  return (
    <>
      <OrganizationSchema baseUrl={baseUrl} />
      <WebSiteSchema baseUrl={baseUrl} />
      <FAQSchema faqs={faqs} />
      <HomeClient />
    </>
  );
}
