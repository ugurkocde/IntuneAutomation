import type { Metadata } from "next";
import { Plug, ShieldCheck } from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";

function ClaudeLogo() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className="h-5 w-5 text-[#d97757]"
      fill="currentColor"
    >
      <path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" />
    </svg>
  );
}

function OpenAiLogo() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className="h-5 w-5 text-[#10a37f]"
      fill="currentColor"
    >
      <path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729Zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944Zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464ZM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872Zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667Zm2.0107-3.0231-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66ZM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813Zm1.0976-2.3654 2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" />
    </svg>
  );
}

function CopilotLogo() {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className="h-5 w-5 text-[#8250df]"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 18v-5.5c0-.667.167-1.333.5-2" />
      <path d="M12 7.5c0-1-.01-4.07-4-3.5-3.5.5-4 2.5-4 3.5 0 1.5 0 4 3 4 4 0 5-2.5 5-4Z" />
      <path d="M4 12c-1.333.667-2 1.333-2 2 0 1 0 3 1.5 4 3 2 6.5 3 8.5 3s5.499-1 8.5-3c1.5-1 1.5-3 1.5-4 0-.667-.667-1.333-2-2" />
      <path d="M20 18v-5.5c0-.667-.167-1.333-.5-2" />
      <path d="M12 7.5c0-1 .01-4.07 4-3.5 3.5.5 4 2.5 4 3.5 0 1.5 0 4-3 4-4 0-5-2.5-5-4Z" />
      <path d="M10 15v2M14 15v2" />
    </svg>
  );
}

const MCP_URL = "https://intuneautomation.com/mcp";
const CLAUDE_CODE_COMMAND = `claude mcp add --transport http --scope user intuneautomation ${MCP_URL}`;
const CODEX_COMMAND = `codex mcp add intuneautomation --url ${MCP_URL}`;

export const metadata: Metadata = {
  title: "MCP Server",
  description:
    "Connect the IntuneAutomation script library to Claude Desktop, Claude Code, Codex, ChatGPT, GitHub Copilot, or any Streamable HTTP MCP client. Hosted, read-only, no API key.",
  alternates: { canonical: "/mcp" },
  robots: { index: true, follow: true },
};

const TOOLS = [
  {
    name: "search_scripts",
    text: "Search or browse the catalog with ranked results and category, tag, platform, and permission filters.",
  },
  {
    name: "get_script_metadata",
    text: "Permissions, minimum role, parameters, examples, and Azure runbook eligibility for one script.",
  },
  {
    name: "get_script",
    text: "Retrieve complete or safely chunked PowerShell source with metadata.",
  },
  {
    name: "get_script_authoring_guide",
    text: "The exact conventions the script generator follows, for writing new library-grade scripts.",
  },
  {
    name: "list_script_catalog",
    text: "Explore categories, tags, platforms, Graph permissions, and roles with usage counts.",
  },
];

function CommandBlock({ children }: { children: string }) {
  return (
    <pre className="border-border/70 bg-background/60 mt-4 overflow-x-auto rounded-lg border p-3 font-mono text-xs leading-relaxed">
      <code>{children}</code>
    </pre>
  );
}

function Card({
  icon,
  kind,
  title,
  step,
  children,
  wide = false,
}: {
  icon?: React.ReactNode;
  kind?: string;
  title: string;
  step?: string;
  children: React.ReactNode;
  wide?: boolean;
}) {
  return (
    <article
      className={`border-border/70 bg-card/60 rounded-xl border p-6 ${
        wide ? "md:col-span-2" : ""
      }`}
    >
      <div className="mb-4 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          {icon ? (
            <span className="border-border/70 text-accent grid h-10 w-10 place-items-center rounded-lg border">
              {icon}
            </span>
          ) : null}
          <div>
            <p className="text-sm font-semibold">{title}</p>
            {kind ? (
              <p className="text-muted-foreground font-mono text-[10px] tracking-wider uppercase">
                {kind}
              </p>
            ) : null}
          </div>
        </div>
        {step ? (
          <span className="text-muted-foreground font-mono text-[10px] tracking-wider uppercase">
            {step}
          </span>
        ) : null}
      </div>
      <div className="text-muted-foreground text-sm leading-relaxed">
        {children}
      </div>
    </article>
  );
}

export default function McpPage() {
  return (
    <ScriptsProvider>
      <div className="bg-background text-foreground min-h-screen">
        <Navbar />
        <div className="container mx-auto max-w-5xl px-4 py-10 sm:py-16">
          <div className="max-w-3xl">
            <p className="text-accent flex items-center gap-2 font-mono text-xs tracking-wider uppercase">
              <Plug className="h-3.5 w-3.5" strokeWidth={2} />
              Live · Read-only MCP
            </p>
            <h1 className="mt-4 text-3xl font-semibold tracking-tight sm:text-5xl">
              Intune automation scripts, inside your AI workflow.
            </h1>
            <p className="text-muted-foreground mt-4 text-base leading-relaxed sm:text-lg">
              Search, retrieve, and author production-grade Microsoft Intune
              PowerShell scripts from Claude, Codex, GitHub Copilot, ChatGPT, or
              any Streamable HTTP MCP client. Every script ships with its
              required Graph permissions, minimum role, and parameters.
            </p>
          </div>

          <div className="border-accent/30 bg-card/60 mt-8 mb-12 flex flex-col justify-between gap-4 rounded-xl border p-5 sm:flex-row sm:items-center">
            <div>
              <p className="text-muted-foreground mb-1 font-mono text-[10px] tracking-wider uppercase">
                MCP endpoint
              </p>
              <code className="font-mono text-sm break-all sm:text-base">
                {MCP_URL}
              </code>
            </div>
            <span className="text-accent bg-accent/10 self-start rounded-full px-3 py-1 font-mono text-xs sm:self-auto">
              Streamable HTTP
            </span>
          </div>

          <section
            aria-label="Setup instructions"
            className="grid gap-4 md:grid-cols-2"
          >
            <Card
              icon={<ClaudeLogo />}
              title="Claude Desktop"
              kind="Desktop connector"
              step="01"
            >
              <ol className="list-decimal space-y-1 pl-5">
                <li>Open Customize or Settings, then Connectors.</li>
                <li>Choose + and Add custom connector.</li>
                <li>Name it IntuneAutomation and paste the endpoint.</li>
                <li>Leave OAuth Client ID and Secret empty.</li>
                <li>In a new chat, enable it under + and Connectors.</li>
              </ol>
              <a
                className="text-accent mt-4 inline-block text-xs underline underline-offset-4"
                href="https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp"
                target="_blank"
                rel="noopener noreferrer"
              >
                Official Claude instructions
              </a>
            </Card>

            <Card
              icon={<ClaudeLogo />}
              title="Claude Code"
              kind="Terminal"
              step="02"
            >
              <p>
                Add the hosted server at user scope, then confirm it appears
                with <code className="font-mono text-xs">claude mcp list</code>.
              </p>
              <CommandBlock>{CLAUDE_CODE_COMMAND}</CommandBlock>
            </Card>

            <Card
              icon={<OpenAiLogo />}
              title="Codex"
              kind="App and terminal"
              step="03"
            >
              <p>
                Register the hosted server, verify it with{" "}
                <code className="font-mono text-xs">codex mcp list</code>, then
                open a new Codex session.
              </p>
              <CommandBlock>{CODEX_COMMAND}</CommandBlock>
            </Card>

            <Card
              icon={<OpenAiLogo />}
              title="ChatGPT"
              kind="Web app"
              step="04"
            >
              <ol className="list-decimal space-y-1 pl-5">
                <li>
                  Enable Developer mode in Settings, Apps, Advanced Settings.
                </li>
                <li>Choose Apps and Create, then paste the endpoint.</li>
                <li>Select no authentication, then Scan Tools and Create.</li>
                <li>
                  In a new chat, select IntuneAutomation from the tools menu.
                </li>
              </ol>
              <p className="mt-3 text-xs">
                OpenAI currently documents custom MCP apps as web-only; use
                ChatGPT in a desktop browser.
              </p>
            </Card>

            <Card
              icon={<CopilotLogo />}
              title="GitHub Copilot"
              kind="VS Code"
              step="05"
            >
              <ol className="list-decimal space-y-1 pl-5">
                <li>
                  Run <code className="font-mono text-xs">MCP: Add Server</code>{" "}
                  from the Command Palette.
                </li>
                <li>
                  Choose HTTP, paste the endpoint, and name it{" "}
                  <code className="font-mono text-xs">intuneautomation</code>.
                </li>
                <li>Save it globally or to the workspace, then trust it.</li>
                <li>Enable the IntuneAutomation tools in Copilot Chat.</li>
              </ol>
            </Card>

            <Card title="Any other MCP client" step="06">
              <p>
                Point your client or custom harness at the endpoint. No API key
                or OAuth credentials are required.
              </p>
              <CommandBlock>{`{ "mcpServers": { "intuneautomation": { "type": "http", "url": "${MCP_URL}" } } }`}</CommandBlock>
            </Card>

            <Card title="Connection test" wide>
              <p>
                A successful test visibly calls the IntuneAutomation tools and
                cites required Graph permissions from the catalog. Try this
                prompt:
              </p>
              <blockquote className="border-accent/50 bg-background/60 mt-4 rounded-r-lg border-l-2 p-4 font-mono text-xs leading-relaxed">
                Use IntuneAutomation to find scripts that report on
                non-compliant devices. Show the required Microsoft Graph
                permissions and minimum role for the best match, then retrieve
                its full source and tell me which tools you called.
              </blockquote>
            </Card>

            <Card title="Available tools" wide>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {TOOLS.map((tool) => (
                  <div
                    key={tool.name}
                    className="border-border/70 bg-background/40 rounded-lg border p-4"
                  >
                    <code className="text-accent font-mono text-xs">
                      {tool.name}
                    </code>
                    <p className="text-muted-foreground mt-2 text-xs leading-relaxed">
                      {tool.text}
                    </p>
                  </div>
                ))}
              </div>
              <div className="border-border/70 mt-5 flex items-start gap-3 border-t pt-5">
                <ShieldCheck
                  className="text-accent mt-0.5 h-5 w-5 shrink-0"
                  strokeWidth={2}
                />
                <p className="text-xs leading-relaxed">
                  <span className="text-foreground font-semibold">
                    No tenant access.
                  </span>{" "}
                  This server is read-only. It never connects to your Microsoft
                  tenant, never runs PowerShell, and never asks for credentials.
                  Scripts you retrieve run on your side, with your own Microsoft
                  Graph authentication.
                </p>
              </div>
            </Card>
          </section>

          <p className="text-muted-foreground mt-8 text-xs">
            This page and the MCP protocol share one URL: browsers see the
            guide, MCP clients speak Streamable HTTP.
          </p>
        </div>
        <Footer />
      </div>
    </ScriptsProvider>
  );
}
