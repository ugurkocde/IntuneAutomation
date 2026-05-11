"use client";

// Footer — editorial-technical. Giant mono wordmark anchors the brand.
// Simple "Built by Ugur Koc · UgurLabs" attribution (no credential claims).
// Three columns of useful links plus a thin meta rule with the no-tracking line.

import Link from "next/link";
import { Github, Linkedin, ArrowUpRight } from "lucide-react";
import { useEffect, useState } from "react";

const GITHUB_REPO_URL = "https://github.com/ugurkocde/IntuneAutomation";
const LICENSE_URL = `${GITHUB_REPO_URL}/blob/main/LICENSE`;
const CONTRIBUTING_URL = `${GITHUB_REPO_URL}/blob/main/CONTRIBUTING.md`;
const ISSUES_URL = `${GITHUB_REPO_URL}/issues`;
const MAINTAINER_LINKEDIN = "https://www.linkedin.com/in/ugurkocde/";
const UGURLABS_URL = "https://ugurlabs.com";

interface FooterColumn {
  title: string;
  links: Array<{
    label: string;
    href: string;
    external?: boolean;
  }>;
}

const COLUMNS: FooterColumn[] = [
  {
    title: "LIBRARY",
    links: [{ label: "Browse scripts", href: "/scripts/" }],
  },
  {
    title: "PROJECT",
    links: [
      { label: "GitHub repository", href: GITHUB_REPO_URL, external: true },
      { label: "MIT License", href: LICENSE_URL, external: true },
      { label: "Contributing", href: CONTRIBUTING_URL, external: true },
      { label: "Report an issue", href: ISSUES_URL, external: true },
    ],
  },
  {
    title: "BUILT BY",
    links: [
      { label: "UgurLabs", href: UGURLABS_URL, external: true },
      { label: "Ugur Koc — LinkedIn", href: MAINTAINER_LINKEDIN, external: true },
    ],
  },
];

export default function Footer() {
  const [year, setYear] = useState<number>(2026);

  useEffect(() => {
    setYear(new Date().getFullYear());
  }, []);

  return (
    <footer
      className="relative isolate overflow-hidden border-t border-border/60"
      aria-labelledby="footer-heading"
    >
      <h2 id="footer-heading" className="sr-only">
        Footer
      </h2>

      {/* Atmosphere — subtle cyan glow anchored center-bottom, matches hero.
       * Lower opacity on light so cream paper isn't tinted teal. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-32 left-1/2 -z-10 h-[520px] w-[520px] -translate-x-1/2 rounded-full opacity-15 blur-3xl dark:opacity-30"
        style={{
          background:
            "radial-gradient(circle at center, color-mix(in oklab, var(--brand-accent) 22%, transparent) 0%, transparent 65%)",
        }}
      />
      <div
        aria-hidden="true"
        className="bg-grain pointer-events-none absolute inset-0 -z-10 opacity-[0.02] mix-blend-multiply dark:opacity-[0.03] dark:mix-blend-overlay"
      />

      <div className="relative mx-auto max-w-7xl px-4 pt-20 pb-12 sm:px-6 sm:pt-24 sm:pb-14">
        {/* Top tier — brand blurb + three link columns */}
        <div className="grid grid-cols-1 gap-12 md:grid-cols-[1.1fr_2fr] md:gap-16">
          <div className="flex flex-col gap-4">
            <div className="flex items-center gap-2">
              <span
                aria-hidden="true"
                className="h-1.5 w-1.5 rounded-full"
                style={{ backgroundColor: "var(--brand-accent)" }}
              />
              <span className="font-mono text-[13px] font-medium tracking-[0.18em] uppercase">
                IntuneAutomation
              </span>
            </div>
            <p className="text-muted-foreground max-w-sm text-sm leading-relaxed">
              Open-source PowerShell scripts for Microsoft Intune. MIT licensed,
              community maintained, free forever.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-8 sm:grid-cols-3 sm:gap-10">
            {COLUMNS.map((column) => (
              <div key={column.title} className="space-y-4">
                <p className="font-mono-label text-accent-hi">{column.title}</p>
                <ul className="space-y-3">
                  {column.links.map((link) => (
                    <li key={link.label}>
                      {link.external ? (
                        <a
                          href={link.href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-sm transition-colors"
                        >
                          {link.label}
                        </a>
                      ) : (
                        <Link
                          href={link.href}
                          className="text-muted-foreground hover:text-foreground text-sm transition-colors"
                        >
                          {link.label}
                        </Link>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>

        {/* Bottom tier — giant mono wordmark + meta strip */}
        <div className="mt-20 sm:mt-24">
          <div className="flex items-end gap-3">
            <span
              aria-hidden="true"
              className="mb-3 h-2 w-2 shrink-0 rounded-full sm:mb-5 md:mb-7"
              style={{ backgroundColor: "var(--brand-accent)" }}
            />
            <p
              className="font-mono text-foreground/85 text-[2.25rem] leading-none tracking-[-0.03em] sm:text-[3.5rem] md:text-[5rem] lg:text-[6.5rem]"
              aria-hidden="true"
            >
              IntuneAutomation
            </p>
          </div>

          {/* Hairline + meta */}
          <div
            className="mt-10 flex flex-col gap-4 border-t pt-6 sm:flex-row sm:items-center sm:justify-between"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-[11px]">
              <p className="text-muted-foreground font-mono tracking-[0.18em] uppercase">
                © {year} · MIT License
              </p>
              <span
                aria-hidden="true"
                className="text-muted-foreground/40"
              >
                ·
              </span>
              <p className="text-muted-foreground font-mono tracking-[0.18em] uppercase">
                Built by{" "}
                <a
                  href={UGURLABS_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-foreground inline-flex items-center gap-0.5 transition-opacity hover:opacity-70"
                >
                  UgurLabs
                  <ArrowUpRight className="h-2.5 w-2.5" aria-hidden="true" />
                </a>
              </p>
            </div>
            <div className="flex items-center gap-1.5">
              <a
                href={UGURLABS_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="border-border/70 hover:border-accent/40 text-muted-foreground hover:text-foreground font-mono inline-flex h-8 items-center gap-1.5 rounded-md border px-2.5 text-[10px] tracking-[0.14em] uppercase transition-colors"
              >
                UgurLabs
                <ArrowUpRight className="h-3 w-3" aria-hidden="true" />
              </a>
              <a
                href={GITHUB_REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="border-border/70 hover:border-accent/40 text-muted-foreground hover:text-foreground inline-flex h-8 w-8 items-center justify-center rounded-md border transition-colors"
                aria-label="IntuneAutomation on GitHub"
              >
                <Github className="h-4 w-4" strokeWidth={1.5} />
              </a>
              <a
                href={MAINTAINER_LINKEDIN}
                target="_blank"
                rel="noopener noreferrer"
                className="border-border/70 hover:border-accent/40 text-muted-foreground hover:text-foreground inline-flex h-8 w-8 items-center justify-center rounded-md border transition-colors"
                aria-label="Ugur Koc on LinkedIn"
              >
                <Linkedin className="h-4 w-4" strokeWidth={1.5} />
              </a>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
