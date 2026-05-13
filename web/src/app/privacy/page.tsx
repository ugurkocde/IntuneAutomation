import type { Metadata } from "next";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How IntuneAutomation.com handles data, including the AI Script Generator.",
  alternates: { canonical: "/privacy" },
  robots: { index: true, follow: true },
};

export default function PrivacyPage() {
  return (
    <ScriptsProvider>
      <div className="bg-background text-foreground min-h-screen">
        <Navbar />
        <div className="container mx-auto max-w-3xl px-4 py-10 sm:py-16">
          <h1 className="mb-2 text-3xl font-semibold tracking-tight">
            Privacy Policy
          </h1>
          <p className="text-muted-foreground mb-10 text-sm">
            Effective: May 11, 2026
          </p>

          <div className="legal-prose text-[15px] leading-relaxed">
            <p>
              This Privacy Policy describes how IntuneAutomation.com (the
              &quot;Service&quot;) handles your data. The Service is designed
              with a privacy-first approach: it stores no prompts, no generated
              output, and no personally identifiable information on its own
              servers.
            </p>

            <h2>Data Access</h2>
            <p>
              The Service does <em>not</em> use OAuth, does not authenticate
              against Microsoft Graph on your behalf, and does not access your
              Microsoft tenant, Intune environment, or any data within them. The
              AI Script Generator is fully read-only at the source level — it
              takes a natural-language description from you and returns a
              PowerShell script your browser can copy or download.
            </p>

            <h2>Data Processing</h2>
            <p>
              The Service minimizes data persistence. When you submit a prompt
              to the Script Generator:
            </p>
            <ul>
              <li>
                The prompt is transmitted from your browser to a serverless
                function on Vercel
              </li>
              <li>
                Before being sent to the language-model provider, the prompt is
                scrubbed by a server-side regex pass that redacts GUIDs (tenant
                / app / object IDs), JWT tokens, bearer tokens, common API key
                prefixes, email addresses, and long encoded blobs. The redaction
                summary is shown to you so you can verify
              </li>
              <li>
                The scrubbed prompt is forwarded to Anthropic PBC for processing
                by the Claude Haiku 4.5 language model. The streaming response
                is sent back through our function to your browser
              </li>
              <li>
                <strong>
                  The full prompt content and generated output are never stored
                  on our servers.
                </strong>{" "}
                Vercel function logs are not retained with request body content
              </li>
              <li>
                For rate limiting only, we store an SHA-256 hash of your IP
                address (truncated to 128 bits) and a counter of how many
                generations you have run in the last 24 hours. The hash is not
                reversible to your real IP
              </li>
              <li>
                For the daily spend cap, we store an aggregate counter of total
                tokens used per UTC day, with no prompt or user association
              </li>
            </ul>

            <h2>Analytics</h2>
            <p>
              The website uses Plausible Analytics, which is 100% cookieless and
              does not track personal data. Only aggregate metrics such as page
              views, referrers, and device types are collected anonymously. The
              Service also stores anonymous, aggregate counters of script views
              and downloads from the script library in Supabase; these counters
              contain no personally identifiable information.
            </p>

            <h2>Third-Party Processors</h2>
            <p>The Service relies on the following sub-processors:</p>
            <ul>
              <li>
                <strong>Anthropic PBC</strong> (United States) — processes
                Script Generator prompts via the Claude API. Anthropic does not
                use API inputs to train its models. Anthropic retains API
                content for up to 30 days for trust-and-safety review and may
                retain content flagged by their automated systems for up to 24
                months. See{" "}
                <a
                  href="https://www.anthropic.com/legal/privacy"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Anthropic&apos;s Privacy Policy
                </a>
              </li>
              <li>
                <strong>Vercel</strong> (United States) — hosting and serverless
                function execution
              </li>
              <li>
                <strong>Cloudflare</strong> — Turnstile bot verification on the
                Script Generator form. Turnstile may set short-lived cookies for
                verification only
              </li>
              <li>
                <strong>Upstash</strong> — Redis cache used to store the
                hashed-IP rate-limit counter and the daily token cap counter
              </li>
              <li>
                <strong>Supabase</strong> — stores anonymous, aggregate
                script-library counters (views, downloads). No personal data
              </li>
              <li>
                <strong>Plausible Analytics</strong> (European Union) —
                privacy-friendly website analytics
              </li>
            </ul>

            <h2>Data Sharing</h2>
            <p>
              We do not sell or share your prompts, generated output, or any
              other data with parties other than the sub-processors listed
              above, which are used strictly to operate the Service. We do not
              share data for advertising purposes.
            </p>

            <h2>Cookies</h2>
            <p>
              The Service does not use tracking cookies. Your theme preference
              (light / dark mode) is stored in your browser&apos;s local
              storage. Cloudflare Turnstile may set short-lived cookies as part
              of bot verification only.
            </p>

            <h2>Your Rights (GDPR / EEA)</h2>
            <p>
              If you are located in the European Economic Area, the United
              Kingdom, or another region with comparable data-protection law,
              you have rights including access, rectification, erasure, and
              objection to processing. Because the Service stores no prompts, no
              output, and no personally identifiable information, most requests
              have nothing to act on. If you have questions or wish to exercise
              a right, contact us at the address below.
            </p>

            <h2>Children</h2>
            <p>
              The Service is intended for IT professionals and is not directed
              to children under 16. We do not knowingly collect data from
              children.
            </p>

            <h2>Security</h2>
            <p>
              The Service is served over HTTPS. The Anthropic API key and other
              secrets are server-side environment variables and are never
              exposed to the browser. The generation endpoint is protected by
              Cloudflare Turnstile, per-IP rate limiting, and a daily spend cap
              to prevent abuse.
            </p>

            <h2>Changes</h2>
            <p>
              We may modify this Privacy Policy from time to time. Material
              changes will be reflected on this page with an updated effective
              date.
            </p>

            <h2>Contact</h2>
            <p>
              Privacy questions:{" "}
              <a href="mailto:support@ugurlabs.com">support@ugurlabs.com</a>
            </p>
          </div>
        </div>
        <Footer />
      </div>
    </ScriptsProvider>
  );
}
