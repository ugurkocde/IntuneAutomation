"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { Github, Menu, X, ExternalLink } from "lucide-react";
import { Button } from "~/components/ui/button";
import { ThemeToggle } from "~/components/theme-toggle";
import { cn } from "~/lib/utils";

export default function StaticNavbar() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 10);
    };

    window.addEventListener("scroll", handleScroll);

    return () => {
      window.removeEventListener("scroll", handleScroll);
    };
  }, []);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 w-full transition-all duration-500 ease-out",
        isScrolled
          ? "bg-background/80 border-border/50 border-b backdrop-blur-xl"
          : "bg-transparent",
      )}
    >
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        {/* Logo */}
        <Link
          href="/"
          className="text-foreground flex items-center gap-3 text-xl font-bold transition-colors duration-200 hover:opacity-80"
        >
          <div className="bg-primary flex h-8 w-8 items-center justify-center rounded-lg">
            <span className="text-primary-foreground text-sm font-black">
              IA
            </span>
          </div>
          <span className="hidden sm:inline">IntuneAutomation</span>
        </Link>

        {/* Desktop Actions */}
        <div className="hidden items-center gap-3 md:flex">
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

        {/* Mobile Menu Button */}
        <div className="flex items-center gap-3 md:hidden">
          <ThemeToggle />
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="h-9 w-9"
            aria-label="Toggle mobile menu"
          >
            {isMobileMenuOpen ? (
              <X className="h-5 w-5" />
            ) : (
              <Menu className="h-5 w-5" />
            )}
          </Button>
        </div>

        {/* Mobile Menu */}
        {isMobileMenuOpen && (
          <div className="border-border/50 bg-background/95 border-t backdrop-blur-xl md:hidden">
            <div className="animate-in slide-in-from-top-5 space-y-4 px-4 py-6 duration-300">
              <div className="space-y-3">
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
