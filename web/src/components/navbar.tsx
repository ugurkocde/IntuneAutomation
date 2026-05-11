"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import {
  Github,
  Menu,
  X,
  Search,
  ExternalLink,
  HelpCircle,
  BookOpen,
} from "lucide-react";
import { Button } from "~/components/ui/button";
import { ThemeToggle } from "~/components/theme-toggle";
import { useScripts } from "~/components/scripts-provider";
import { cn } from "~/lib/utils";

export default function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const { setSearchOpen } = useScripts();

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 10);
    };

    window.addEventListener("scroll", handleScroll);

    // Add keyboard shortcut for search
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
        "sticky top-0 z-50 w-full transition-all duration-500 ease-out",
        isScrolled
          ? "bg-background/95 border-border/50 border-b shadow-sm backdrop-blur-xl"
          : "bg-background/60 backdrop-blur-sm",
      )}
    >
      <div className="container mx-auto px-4">
        <div className="flex h-16 items-center justify-between">
          {/* Logo and Brand */}
          <div className="flex items-center gap-3">
            <Link
              href="/"
              className="group flex items-center gap-3 transition-all duration-300 hover:scale-105"
            >
              <div className="relative">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-blue-500 via-purple-600 to-blue-700 shadow-lg transition-all duration-300 group-hover:from-blue-400 group-hover:via-purple-500 group-hover:to-blue-600 group-hover:shadow-xl">
                  <span className="text-lg font-bold text-white">IA</span>
                </div>
                <div className="absolute -inset-1 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 opacity-0 blur-sm transition-opacity duration-300 group-hover:opacity-20" />
              </div>
              <div className="hidden sm:block">
                <span className="bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-xl font-bold text-transparent">
                  IntuneAutomation
                </span>
                <p className="text-muted-foreground hidden text-xs lg:block">
                  Automate Intune, one script at a time
                </p>
              </div>
            </Link>
          </div>

          {/* Desktop Actions */}
          <div className="hidden items-center gap-3 md:flex">
            <Button
              variant="outline"
              className="group gap-2 text-sm transition-all duration-200 hover:border-blue-300 hover:bg-blue-50/50 dark:hover:bg-blue-950/50"
              onClick={() => setSearchOpen(true)}
            >
              <Search className="h-4 w-4 transition-transform duration-200 group-hover:scale-110" />
              <span>Search scripts</span>
              <kbd className="bg-muted pointer-events-none ml-1 inline-flex h-5 items-center gap-1 rounded border px-1.5 font-mono text-[10px] font-medium opacity-70 transition-opacity duration-200 select-none group-hover:opacity-100">
                <span className="text-xs">⌘</span>K
              </kbd>
            </Button>

            <Button
              variant="ghost"
              size="sm"
              asChild
              className="gap-2 text-sm transition-all duration-200 hover:bg-blue-50/50 dark:hover:bg-blue-950/50"
            >
              <Link href="/blog/">
                <BookOpen className="h-4 w-4" />
                <span>Blog</span>
              </Link>
            </Button>

            <Button
              variant="ghost"
              size="sm"
              className="gap-2 text-sm transition-all duration-200 hover:bg-blue-50/50 dark:hover:bg-blue-950/50"
              onClick={() => {
                document.getElementById("faq-section")?.scrollIntoView({
                  behavior: "smooth",
                  block: "start",
                });
              }}
            >
              <HelpCircle className="h-4 w-4" />
              <span>FAQ</span>
            </Button>

            <ThemeToggle />

            <Button
              asChild
              variant="default"
              size="sm"
              className="gap-2 bg-gradient-to-r from-blue-600 to-purple-600 shadow-md transition-all duration-200 hover:from-blue-700 hover:to-purple-700 hover:shadow-lg"
            >
              <a
                href="https://github.com/ugurkocde/intuneautomation"
                target="_blank"
                rel="noopener noreferrer"
              >
                <Github className="h-4 w-4" />
                <span>Contribute</span>
                <ExternalLink className="h-3 w-3 opacity-70" />
              </a>
            </Button>
          </div>

          {/* Mobile Actions */}
          <div className="flex items-center gap-2 md:hidden">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setSearchOpen(true)}
              className="p-2"
            >
              <Search className="h-4 w-4" />
            </Button>
            <ThemeToggle />
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
              aria-label="Toggle menu"
              className="transition-transform duration-200 hover:scale-105"
            >
              {isMobileMenuOpen ? (
                <X className="h-5 w-5" />
              ) : (
                <Menu className="h-5 w-5" />
              )}
            </Button>
          </div>
        </div>

        {/* Mobile menu */}
        {isMobileMenuOpen && (
          <div className="border-border/50 bg-background/95 border-t backdrop-blur-xl md:hidden">
            <div className="animate-in slide-in-from-top-5 space-y-4 px-4 py-6 duration-300">
              <div className="space-y-3">
                <Button
                  variant="outline"
                  className="w-full justify-start gap-3 text-sm"
                  onClick={() => {
                    setSearchOpen(true);
                    setIsMobileMenuOpen(false);
                  }}
                >
                  <Search className="h-4 w-4" />
                  Search scripts
                  <kbd className="bg-muted pointer-events-none ml-auto inline-flex h-5 items-center gap-1 rounded border px-1.5 font-mono text-[10px] font-medium opacity-70 select-none">
                    <span className="text-xs">⌘</span>K
                  </kbd>
                </Button>

                <Button
                  variant="ghost"
                  asChild
                  className="w-full justify-start gap-3 text-sm"
                  onClick={() => setIsMobileMenuOpen(false)}
                >
                  <Link href="/blog/">
                    <BookOpen className="h-4 w-4" />
                    Blog
                  </Link>
                </Button>

                <Button
                  variant="ghost"
                  className="w-full justify-start gap-3 text-sm"
                  onClick={() => {
                    document.getElementById("faq-section")?.scrollIntoView({
                      behavior: "smooth",
                      block: "start",
                    });
                    setIsMobileMenuOpen(false);
                  }}
                >
                  <HelpCircle className="h-4 w-4" />
                  FAQ
                </Button>

                <Button
                  asChild
                  variant="default"
                  size="sm"
                  className="w-full justify-start gap-3 bg-gradient-to-r from-blue-600 to-purple-600"
                >
                  <a
                    href="https://github.com/ugurkocde/intuneautomation"
                    target="_blank"
                    rel="noopener noreferrer"
                    onClick={() => setIsMobileMenuOpen(false)}
                  >
                    <Github className="h-4 w-4" />
                    <span>Contribute on GitHub</span>
                    <ExternalLink className="ml-auto h-3 w-3 opacity-70" />
                  </a>
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </header>
  );
}
