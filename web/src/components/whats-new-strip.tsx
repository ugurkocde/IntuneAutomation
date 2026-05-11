"use client";

// "What's new" strip — a return-visit lever. Shows the three most recently
// updated scripts. Editorial-technical: hairline dividers, mono kicker,
// Fraunces section opener.

import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowUpRight } from "lucide-react";
import { useScripts } from "~/components/scripts-provider";
import type { Script } from "~/lib/scripts";

function sortByMostRecent(a: Script, b: Script): number {
  const av = a.lastUpdated ? new Date(a.lastUpdated).getTime() : 0;
  const bv = b.lastUpdated ? new Date(b.lastUpdated).getTime() : 0;
  return bv - av;
}

export default function WhatsNewStrip() {
  const { allScripts, isLoading } = useScripts();
  const prefersReducedMotion = useReducedMotion();

  if (isLoading && allScripts.length === 0) return null;

  const recent = [...allScripts]
    .filter((s) => Boolean(s.lastUpdated))
    .sort(sortByMostRecent)
    .slice(0, 3);

  if (recent.length === 0) return null;

  const initial = prefersReducedMotion ? false : { opacity: 0, y: 10 };
  const animate = { opacity: 1, y: 0 };

  return (
    <section
      aria-labelledby="whats-new-heading"
      className="border-t border-border/60 px-4 py-20 sm:py-24"
    >
      <div className="mx-auto max-w-7xl">
        <div className="mb-10">
          <p className="font-mono-label text-accent-hi mb-3">// WHAT'S NEW</p>
          <h2
            id="whats-new-heading"
            className="font-display text-foreground text-3xl leading-[1.05] sm:text-4xl md:text-5xl"
          >
            Recently shipped.
          </h2>
        </div>

        <ul className="border-b" style={{ borderColor: "var(--brand-rule)" }}>
          {recent.map((script, index) => (
            <motion.li
              key={script.id}
              initial={initial}
              whileInView={animate}
              viewport={{ once: true, margin: "-80px" }}
              transition={{
                duration: prefersReducedMotion ? 0 : 0.45,
                delay: prefersReducedMotion ? 0 : index * 0.08,
                ease: [0.22, 1, 0.36, 1],
              }}
              className="border-t hover:bg-card/60 group/row transition-colors duration-200"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <Link
                href={`/script/${script.slug}/`}
                className="flex items-baseline gap-5 px-2 py-6 sm:gap-8"
                aria-label={`Open ${script.title}`}
              >
                <span
                  aria-hidden="true"
                  className="font-mono text-accent-hi w-12 shrink-0 text-xs tracking-widest sm:text-sm"
                >
                  {String(index + 1).padStart(2, "0")}
                </span>

                <div className="min-w-0 flex-1">
                  <p className="text-foreground group-hover/row:text-accent-hi text-sm font-medium leading-tight transition-colors sm:text-base">
                    {script.title}
                  </p>
                  <p className="text-muted-foreground mt-1 line-clamp-1 text-xs sm:text-sm">
                    {script.description}
                  </p>
                </div>

                <ArrowUpRight
                  className="text-muted-foreground group-hover/row:text-accent-hi h-4 w-4 shrink-0 transition-all group-hover/row:-translate-y-0.5 group-hover/row:translate-x-0.5"
                  aria-hidden="true"
                />
              </Link>
            </motion.li>
          ))}
        </ul>
      </div>
    </section>
  );
}
