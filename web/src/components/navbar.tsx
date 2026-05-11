"use client";

// Navbar v2 — slim, glass blur, mono wordmark, no gradients, no scale-on-hover.
// Brand becomes a typographic mark (Geist Mono uppercase + cyan dot) rather
// than a gradient icon. Reads as a serial number, not a logo. Sober.

import { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Github, Menu, X, Search, Sparkles } from "lucide-react";
import { Button } from "~/components/ui/button";
import { ThemeToggle } from "~/components/theme-toggle";
import { useScripts } from "~/components/scripts-provider";
import { cn } from "~/lib/utils";

const REPO_URL = "https://github.com/ugurkocde/IntuneAutomation";

export default function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const { setSearchOpen } = useScripts();
  const pathname = usePathname();
  const isHome = pathname === "/";

  const scrollToFaq = () => {
    document
      .getElementById("faq-section")
      ?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 8);
    window.addEventListener("scroll", handleScroll, { passive: true });

    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setSearchOpen(true);
      }
    };
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("scroll", handleScroll);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [setSearchOpen]);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 w-full transition-colors duration-300",
        isScrolled
          ? "bg-background/85 border-border/60 border-b backdrop-blur-xl"
          : "bg-background/60 backdrop-blur-md",
      )}
    >
      <div className="container mx-auto max-w-7xl px-4">
        <div className="flex h-14 items-center justify-between sm:h-16">
          {/* Wordmark */}
          <Link
            href="/"
            className="group flex items-center gap-2.5 transition-opacity duration-200 hover:opacity-90"
            aria-label="IntuneAutomation home"
          >
            <span
              className="text-accent inline-block h-1.5 w-1.5 rounded-full"
              style={{ backgroundColor: "var(--brand-accent)" }}
              aria-hidden="true"
            />
            <span className="font-mono text-[13px] font-medium tracking-[0.18em] uppercase">
              IntuneAutomation
            </span>
          </Link>

          {/* Desktop nav */}
          <nav
            className="hidden items-center gap-1 md:flex"
            aria-label="Primary"
          >
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              className="group text-muted-foreground hover:text-foreground focus-visible:ring-accent inline-flex cursor-pointer items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors focus-visible:ring-2 focus-visible:outline-none"
              aria-label="Search scripts"
            >
              <Search className="h-3.5 w-3.5" strokeWidth={2} />
              <span>Search</span>
              <kbd className="border-border/70 text-muted-foreground ml-1 inline-flex h-5 items-center rounded border px-1.5 font-mono text-[10px] opacity-70 select-none">
                /
              </kbd>
            </button>

            <Link
              href="/generator/"
              className="text-muted-foreground hover:text-foreground focus-visible:ring-accent inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-sm transition-colors focus-visible:ring-2 focus-visible:outline-none"
            >
              <Sparkles className="h-3.5 w-3.5" strokeWidth={2} />
              Generator
              <span className="border-accent/40 text-accent rounded border px-1 py-0.5 font-mono text-[9px] leading-none tracking-wider uppercase">
                New
              </span>
            </Link>

            {isHome ? (
              <button
                type="button"
                onClick={scrollToFaq}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent cursor-pointer rounded-md px-3 py-2 text-sm transition-colors focus-visible:ring-2 focus-visible:outline-none"
              >
                FAQ
              </button>
            ) : (
              <Link
                href="/#faq-section"
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent rounded-md px-3 py-2 text-sm transition-colors focus-visible:ring-2 focus-visible:outline-none"
              >
                FAQ
              </Link>
            )}

            <span className="bg-border/80 mx-1 h-4 w-px" aria-hidden="true" />

            <ThemeToggle />

            <a
              href={REPO_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="border-border/70 hover:border-accent/40 ml-2 inline-flex items-center gap-2 rounded-md border bg-transparent px-3 py-1.5 text-sm transition-colors"
            >
              <Github className="h-3.5 w-3.5" strokeWidth={2} />
              <span>GitHub</span>
            </a>
          </nav>

          {/* Mobile actions */}
          <div className="flex items-center gap-1 md:hidden">
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              className="text-muted-foreground hover:text-foreground inline-flex h-9 w-9 cursor-pointer items-center justify-center rounded-md transition-colors"
              aria-label="Search scripts"
            >
              <Search className="h-4 w-4" strokeWidth={2} />
            </button>
            <ThemeToggle />
            <button
              type="button"
              onClick={() => setIsMobileMenuOpen((v) => !v)}
              aria-label="Toggle menu"
              aria-expanded={isMobileMenuOpen}
              className="text-muted-foreground hover:text-foreground inline-flex h-9 w-9 cursor-pointer items-center justify-center rounded-md transition-colors"
            >
              {isMobileMenuOpen ? (
                <X className="h-4 w-4" strokeWidth={2} />
              ) : (
                <Menu className="h-4 w-4" strokeWidth={2} />
              )}
            </button>
          </div>
        </div>

        {/* Mobile menu */}
        {isMobileMenuOpen && (
          <div className="border-border/60 animate-in slide-in-from-top-2 border-t py-4 duration-200 md:hidden">
            <nav
              className="flex flex-col gap-1 text-sm"
              aria-label="Mobile primary"
            >
              <button
                type="button"
                onClick={() => {
                  setSearchOpen(true);
                  setIsMobileMenuOpen(false);
                }}
                className="text-foreground hover:bg-card flex cursor-pointer items-center justify-between rounded-md px-3 py-2.5 transition-colors"
              >
                <span className="inline-flex items-center gap-2">
                  <Search className="h-4 w-4" /> Search
                </span>
                <span className="border-border/70 text-muted-foreground inline-flex h-5 items-center rounded border px-1.5 font-mono text-[10px] opacity-70">
                  /
                </span>
              </button>

              <Link
                href="/generator/"
                onClick={() => setIsMobileMenuOpen(false)}
                className="text-foreground hover:bg-card flex items-center gap-2 rounded-md px-3 py-2.5 transition-colors"
              >
                <Sparkles className="h-4 w-4" strokeWidth={2} />
                Generator
                <span className="border-accent/40 text-accent ml-auto rounded border px-1.5 py-0.5 font-mono text-[10px] leading-none tracking-wider uppercase">
                  New
                </span>
              </Link>

              {isHome ? (
                <button
                  type="button"
                  onClick={() => {
                    scrollToFaq();
                    setIsMobileMenuOpen(false);
                  }}
                  className="text-foreground hover:bg-card cursor-pointer rounded-md px-3 py-2.5 text-left transition-colors"
                >
                  FAQ
                </button>
              ) : (
                <Link
                  href="/#faq-section"
                  onClick={() => setIsMobileMenuOpen(false)}
                  className="text-foreground hover:bg-card rounded-md px-3 py-2.5 transition-colors"
                >
                  FAQ
                </Link>
              )}

              <a
                href={REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                onClick={() => setIsMobileMenuOpen(false)}
                className="border-border/70 mt-2 inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm transition-colors"
              >
                <Github className="h-4 w-4" />
                <span>GitHub repository</span>
              </a>
            </nav>
          </div>
        )}
      </div>
    </header>
  );
}
