import type { Metadata } from "next";
import {
  Bot,
  Code2,
  MessageSquare,
  Plug,
  ShieldCheck,
  SquareTerminal,
  Terminal,
} from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";

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
              icon={<Bot className="h-5 w-5" strokeWidth={2} />}
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
              icon={<Terminal className="h-5 w-5" strokeWidth={2} />}
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
              icon={<SquareTerminal className="h-5 w-5" strokeWidth={2} />}
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
              icon={<MessageSquare className="h-5 w-5" strokeWidth={2} />}
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
              icon={<Code2 className="h-5 w-5" strokeWidth={2} />}
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
