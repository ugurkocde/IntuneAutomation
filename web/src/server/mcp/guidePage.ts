const MCP_URL = "https://intuneautomation.com/mcp";
const REPO_URL = "https://github.com/ugurkocde/IntuneAutomation";

const CLAUDE_CODE_COMMAND =
  "claude mcp add --transport http --scope user intuneautomation " + MCP_URL;
const CODEX_COMMAND = "codex mcp add intuneautomation --url " + MCP_URL;
const CLAUDE_LOGO = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" /></svg>`;
const OPENAI_LOGO = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729Zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944Zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464ZM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872Zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667Zm2.0107-3.0231-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66ZM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813Zm1.0976-2.3654 2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" /></svg>`;
const COPILOT_LOGO = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 18v-5.5c0-.667.167-1.333.5-2"/><path d="M12 7.5c0-1-.01-4.07-4-3.5-3.5.5-4 2.5-4 3.5 0 1.5 0 4 3 4 4 0 5-2.5 5-4Z"/><path d="M4 12c-1.333.667-2 1.333-2 2 0 1 0 3 1.5 4 3 2 6.5 3 8.5 3s5.499-1 8.5-3c1.5-1 1.5-3 1.5-4 0-.667-.667-1.333-2-2"/><path d="M20 18v-5.5c0-.667-.167-1.333-.5-2"/><path d="M12 7.5c0-1 .01-4.07 4-3.5 3.5.5 4 2.5 4 3.5 0 1.5 0 4-3 4-4 0-5-2.5-5-4Z"/><path d="M10 15v2M14 15v2"/></svg>`;

export const wantsMcpGuide = (request: Request) => {
  if (request.method !== "GET") return false;

  const accept = request.headers.get("accept")?.toLowerCase() ?? "";
  return (
    accept.includes("text/html") &&
    !accept.includes("text/event-stream") &&
    !accept.includes("application/json")
  );
};

type McpGetHandler = (request: Request) => Promise<Response>;

export const createGuideAwareMcpGetHandler =
  (mcpHandler: McpGetHandler) => async (request: Request) =>
    wantsMcpGuide(request) ? createMcpGuideResponse() : mcpHandler(request);

const guideHtml = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#0a1220" />
    <meta name="description" content="Connect the IntuneAutomation script library to Claude Desktop, Claude Code, Codex, GitHub Copilot, ChatGPT, or any Streamable HTTP MCP client." />
    <link rel="canonical" href="${MCP_URL}" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&amp;family=Outfit:wght@400;500;600;700&amp;display=swap" rel="stylesheet" />
    <title>IntuneAutomation MCP</title>
    <style>
      html {
        color-scheme: dark;
      }
      :root {
        --ink: #f8fafc;
        --muted: #94a3b8;
        --line: rgba(148, 163, 184, 0.16);
        --panel: rgba(15, 23, 42, 0.72);
        --primary: #60a5fa;
        --accent: #38bdf8;
        --green: #34d399;
        --display: "Outfit", sans-serif;
        --mono: "JetBrains Mono", monospace;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        color: var(--ink);
        font-family: var(--display);
        background:
          radial-gradient(circle at 15% 10%, rgba(59, 130, 246, 0.2), transparent 34rem),
          radial-gradient(circle at 88% 82%, rgba(56, 189, 248, 0.12), transparent 30rem),
          #0a1220;
      }
      body::before {
        content: "";
        position: fixed;
        inset: 0;
        pointer-events: none;
        opacity: 0.16;
        background-image: linear-gradient(var(--line) 1px, transparent 1px), linear-gradient(90deg, var(--line) 1px, transparent 1px);
        background-size: 44px 44px;
        mask-image: linear-gradient(to bottom, black, transparent 75%);
      }
      a { color: inherit; touch-action: manipulation; }
      .skip-link { position: fixed; top: 12px; left: 12px; z-index: 10; padding: 9px 12px; border-radius: 8px; color: #0a1220; background: var(--accent); transform: translateY(-160%); }
      .skip-link:focus-visible { transform: translateY(0); }
      .shell { width: min(1080px, calc(100% - 32px)); margin: 0 auto; padding: 42px 0 64px; }
      .topbar { display: flex; align-items: center; justify-content: space-between; gap: 20px; margin-bottom: 72px; }
      .brand { display: flex; align-items: center; gap: 12px; text-decoration: none; font-weight: 650; letter-spacing: -0.02em; }
      .mark {
        display: grid;
        width: 42px;
        height: 42px;
        place-items: center;
        border: 1px solid rgba(96, 165, 250, 0.35);
        border-radius: 12px;
        color: #fff;
        font-family: var(--mono);
        font-size: 13px;
        font-weight: 600;
        background: linear-gradient(145deg, rgba(59, 130, 246, 0.3), rgba(56, 189, 248, 0.08));
        box-shadow: 0 14px 40px rgba(0, 0, 0, 0.24);
      }
      .home { color: var(--muted); font-size: 14px; text-decoration: none; }
      .home:hover { color: var(--ink); }
      .hero { max-width: 860px; }
      .eyebrow { display: flex; align-items: center; gap: 9px; color: var(--green); font-family: var(--mono); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; }
      .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); box-shadow: 0 0 20px rgba(52, 211, 153, 0.75); }
      h1 { margin: 20px 0 18px; max-width: 780px; font-size: clamp(42px, 6.6vw, 74px); line-height: 0.98; letter-spacing: -0.055em; text-wrap: balance; }
      .lead { margin: 0; max-width: 700px; color: #b8c4d6; font-size: clamp(18px, 2.4vw, 23px); line-height: 1.55; }
      .endpoint {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 18px;
        margin: 34px 0 54px;
        padding: 18px 20px;
        border: 1px solid rgba(96, 165, 250, 0.28);
        border-radius: 16px;
        background: rgba(15, 23, 42, 0.82);
        box-shadow: 0 24px 80px rgba(0, 0, 0, 0.22);
      }
      .endpoint-label { display: block; margin-bottom: 6px; color: var(--muted); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; }
      code { font-family: var(--mono); }
      .endpoint code { color: #dbeafe; font-size: clamp(12px, 2.3vw, 15px); overflow-wrap: anywhere; }
      .pill { flex: 0 0 auto; padding: 8px 11px; border-radius: 999px; color: var(--accent); font-family: var(--mono); font-size: 11px; background: rgba(56, 189, 248, 0.1); }
      .grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 16px; }
      .card { grid-column: span 6; padding: 25px; border: 1px solid var(--line); border-radius: 18px; background: var(--panel); backdrop-filter: blur(18px); }
      .card.wide { grid-column: span 12; }
      .card-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 18px; }
      .platform { display: flex; align-items: center; gap: 11px; }
      .platform-icon { display: grid; width: 40px; height: 40px; flex: 0 0 auto; place-items: center; border: 1px solid var(--line); border-radius: 12px; }
      .platform-icon svg { width: 21px; height: 21px; fill: currentColor; }
      .platform-icon.claude { color: #f0a27e; background: rgba(217, 119, 87, 0.12); }
      .platform-icon.openai { color: #a7f3d0; background: rgba(16, 163, 127, 0.12); }
      .platform-icon.copilot { color: #d8b4fe; background: rgba(126, 34, 206, 0.14); }
      .platform-icon.copilot svg { fill: none; stroke: currentColor; }
      .platform-copy { display: grid; gap: 2px; }
      .platform-name { color: var(--ink); font-size: 15px; font-weight: 600; }
      .platform-kind, .card-number { color: var(--muted); font-family: var(--mono); font-size: 10px; letter-spacing: 0.06em; text-transform: uppercase; }
      h2 { margin: 0 0 9px; font-size: 22px; letter-spacing: -0.025em; text-wrap: balance; }
      .card p { margin: 0; color: var(--muted); line-height: 1.55; }
      .steps { margin: 18px 0 0; padding-left: 21px; color: #cbd5e1; line-height: 1.75; }
      .command { margin-top: 17px; padding: 14px 15px; overflow-x: auto; border: 1px solid var(--line); border-radius: 12px; color: #dbeafe; font-size: 12px; line-height: 1.65; background: rgba(2, 6, 23, 0.66); }
      .notice { margin-top: 16px; padding: 13px 14px; border: 1px solid rgba(251, 191, 36, 0.22); border-radius: 12px; color: #fde68a; font-size: 13px; line-height: 1.5; background: rgba(120, 53, 15, 0.14); }
      .docs-link { display: inline-block; margin-top: 15px; color: #bae6fd; font-size: 13px; text-underline-offset: 3px; }
      .docs-link:hover { color: #fff; }
      .test-prompt { margin-top: 17px; padding: 17px 18px; border-left: 3px solid var(--accent); border-radius: 4px 12px 12px 4px; color: #dbeafe; font-family: var(--mono); font-size: 12px; line-height: 1.7; background: rgba(2, 6, 23, 0.66); }
      .tools { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-top: 18px; }
      .tool { padding: 15px; border: 1px solid var(--line); border-radius: 13px; background: rgba(2, 6, 23, 0.34); }
      .tool code { color: var(--accent); font-size: 12px; }
      .tool span { display: block; margin-top: 7px; color: var(--muted); font-size: 14px; line-height: 1.45; }
      .trust { display: flex; gap: 14px; align-items: flex-start; margin-top: 18px; padding-top: 18px; border-top: 1px solid var(--line); }
      .trust strong { color: var(--green); white-space: nowrap; }
      footer { display: flex; justify-content: space-between; gap: 20px; margin-top: 30px; color: #94a3b8; font-size: 13px; }
      footer a:hover { color: var(--ink); }
      :focus-visible { outline: 2px solid var(--accent); outline-offset: 4px; border-radius: 4px; }
      @media (max-width: 720px) {
        .shell { padding-top: 24px; }
        .topbar { margin-bottom: 48px; }
        .endpoint { align-items: flex-start; flex-direction: column; }
        .card, .card.wide { grid-column: span 12; }
        .tools { grid-template-columns: 1fr; }
        .trust, footer { flex-direction: column; }
      }
      @media (prefers-reduced-motion: no-preference) {
        .hero, .grid { animation: enter 650ms cubic-bezier(.22,1,.36,1) both; }
        .grid { animation-delay: 90ms; }
        @keyframes enter { from { opacity: 0; transform: translateY(14px); } }
      }
    </style>
  </head>
  <body>
    <a class="skip-link" href="#setup">Skip to setup</a>
    <main class="shell">
      <nav class="topbar" aria-label="Primary navigation">
        <a class="brand" href="/"><span class="mark">IA</span><span>IntuneAutomation</span></a>
        <a class="home" href="/scripts/">Browse the script library &rarr;</a>
      </nav>

      <section class="hero">
        <div class="eyebrow"><span class="dot"></span> Live &middot; Read-only MCP</div>
        <h1>Intune automation scripts, inside your AI workflow.</h1>
        <p class="lead">Search, retrieve, and author production-grade Microsoft Intune PowerShell scripts from Claude, Codex, GitHub Copilot, ChatGPT, or any Streamable HTTP MCP client. Every script ships with its required Graph permissions, minimum role, and parameters.</p>
      </section>

      <div class="endpoint">
        <div><span class="endpoint-label">MCP endpoint</span><code translate="no">${MCP_URL}</code></div>
        <span class="pill">Streamable HTTP</span>
      </div>

      <section class="grid" id="setup" aria-label="Setup instructions">
        <article class="card">
          <div class="card-head">
            <div class="platform"><span class="platform-icon claude">${CLAUDE_LOGO}</span><span class="platform-copy"><span class="platform-name">Claude Desktop</span><span class="platform-kind">Desktop connector</span></span></div>
            <span class="card-number">01</span>
          </div>
          <h2>Add a Custom Connector</h2>
          <ol class="steps">
            <li>Open Customize or Settings &rarr; Connectors.</li>
            <li>Choose + &rarr; Add custom connector.</li>
            <li>Name it IntuneAutomation and paste the endpoint.</li>
            <li>Leave OAuth Client ID and Secret empty.</li>
            <li>In a new chat, enable it under + &rarr; Connectors.</li>
          </ol>
          <a class="docs-link" href="https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp">Official Claude instructions &rarr;</a>
        </article>

        <article class="card">
          <div class="card-head">
            <div class="platform"><span class="platform-icon claude">${CLAUDE_LOGO}</span><span class="platform-copy"><span class="platform-name">Claude Code</span><span class="platform-kind">Terminal</span></span></div>
            <span class="card-number">02</span>
          </div>
          <h2>Connect from Your Terminal</h2>
          <p>Add the hosted server at user scope, then confirm it appears with <code translate="no">claude mcp list</code>.</p>
          <div class="command"><code translate="no">${CLAUDE_CODE_COMMAND}</code></div>
        </article>

        <article class="card">
          <div class="card-head">
            <div class="platform"><span class="platform-icon openai">${OPENAI_LOGO}</span><span class="platform-copy"><span class="platform-name">Codex</span><span class="platform-kind">App &amp; terminal</span></span></div>
            <span class="card-number">03</span>
          </div>
          <h2>Connect from Your Terminal</h2>
          <p>Register the hosted server, verify it with <code translate="no">codex mcp list</code>, then open a new Codex session.</p>
          <div class="command"><code translate="no">${CODEX_COMMAND}</code></div>
        </article>

        <article class="card">
          <div class="card-head">
            <div class="platform"><span class="platform-icon openai">${OPENAI_LOGO}</span><span class="platform-copy"><span class="platform-name">ChatGPT</span><span class="platform-kind">Web app</span></span></div>
            <span class="card-number">04</span>
          </div>
          <h2>Create a Custom MCP App</h2>
          <ol class="steps">
            <li>On ChatGPT web, enable Developer mode in Settings &rarr; Apps &rarr; Advanced Settings.</li>
            <li>Choose Apps &rarr; Create and paste the endpoint.</li>
            <li>Select no authentication, then Scan Tools &rarr; Create.</li>
            <li>In a new chat, select IntuneAutomation from the tools menu.</li>
          </ol>
          <div class="notice"><strong>Native desktop status:</strong> OpenAI currently documents custom MCP apps as web-only. Use ChatGPT in a desktop browser for now. An eligible plan or workspace permission is required.</div>
          <a class="docs-link" href="https://help.openai.com/en/articles/12584461-developer-mode-and-full-mcp-connectors-in-chatgpt">Official ChatGPT instructions &rarr;</a>
        </article>

        <article class="card">
          <div class="card-head">
            <div class="platform"><span class="platform-icon copilot">${COPILOT_LOGO}</span><span class="platform-copy"><span class="platform-name">GitHub Copilot</span><span class="platform-kind">VS Code</span></span></div>
            <span class="card-number">05</span>
          </div>
          <h2>Add the Server in VS Code</h2>
          <ol class="steps">
            <li>Open the Command Palette and run <code translate="no">MCP: Add Server</code>.</li>
            <li>Choose HTTP, paste the endpoint, and name it <code translate="no">intuneautomation</code>.</li>
            <li>Save it globally or to the workspace, then trust the server.</li>
            <li>Open Copilot Chat and enable the IntuneAutomation tools.</li>
          </ol>
        </article>

        <article class="card">
          <span class="card-number">Any other MCP client</span>
          <h2>Use Streamable HTTP</h2>
          <p>Point your client or custom harness at the endpoint. No API key or OAuth credentials are required.</p>
          <div class="command"><code translate="no">{ "mcpServers": { "intuneautomation": { "type": "http", "url": "${MCP_URL}" } } }</code></div>
        </article>

        <article class="card wide">
          <span class="card-number">Connection test</span>
          <h2>Ask Your Client to Use IntuneAutomation</h2>
          <p>A successful test visibly calls the IntuneAutomation tools and cites required Graph permissions from the catalog.</p>
          <div class="test-prompt">Use IntuneAutomation to find scripts that report on non-compliant devices. Show the required Microsoft Graph permissions and minimum role for the best match, then retrieve its full source and tell me which tools you called.</div>
        </article>

        <article class="card wide">
          <span class="card-number">Available tools</span>
          <h2>A Small, Focused Surface</h2>
          <div class="tools">
            <div class="tool"><code translate="no">search_scripts</code><span>Search or browse the catalog with ranked results and category, tag, platform, and permission filters.</span></div>
            <div class="tool"><code translate="no">get_script_metadata</code><span>Permissions, minimum role, parameters, examples, and Azure runbook eligibility for one script.</span></div>
            <div class="tool"><code translate="no">get_script</code><span>Retrieve complete or safely chunked PowerShell source with metadata.</span></div>
            <div class="tool"><code translate="no">get_script_authoring_guide</code><span>The exact conventions the script generator follows, for writing new library-grade scripts.</span></div>
            <div class="tool"><code translate="no">list_script_catalog</code><span>Explore categories, tags, platforms, Graph permissions, and roles with usage counts.</span></div>
          </div>
          <div class="trust"><strong>No tenant access</strong><p>This server is read-only. It never connects to your Microsoft tenant, never runs PowerShell, and never asks for credentials. Scripts you retrieve run on your side, with your own Microsoft Graph authentication.</p></div>
        </article>
      </section>

      <footer><span>This browser page and the MCP protocol share one URL.</span><a href="${REPO_URL}">View source on GitHub</a></footer>
    </main>
  </body>
</html>`;

export const createMcpGuideResponse = (headOnly = false) =>
  new Response(headOnly ? null : guideHtml, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300, stale-while-revalidate=3600",
      "Content-Security-Policy":
        "default-src 'none'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "X-Content-Type-Options": "nosniff",
      Vary: "Accept",
    },
  });
