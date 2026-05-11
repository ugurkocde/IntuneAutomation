// RelatedScripts v4 — manifest-style related-script list for the script detail page.
// Mono numeric IDs in a hairline-bordered table-of-contents layout, with mono tag pills,
// display-weight titles, and a single cyan accent. No cards, no shadows, no rainbow tags
// — the table itself does the visual work, matching the footer + faq manifest pattern.

import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { type Script } from "~/lib/scripts";

interface RelatedScriptsProps {
  currentScript: Script;
  allScripts: Script[];
  limit?: number;
}

export function RelatedScripts({
  currentScript,
  allScripts,
  limit = 3,
}: RelatedScriptsProps) {
  // Relevance scoring — identical to v1.
  const scoredScripts = allScripts
    .filter((script) => script.id !== currentScript.id)
    .map((script) => {
      let score = 0;
      const sharedTags = script.tags.filter((tag) =>
        currentScript.tags.includes(tag),
      );
      score += sharedTags.length * 3;
      if (script.category === currentScript.category) score += 2;
      if (script.scriptType === currentScript.scriptType) score += 1;
      if (
        script.remediationType &&
        currentScript.remediationType &&
        script.remediationType === currentScript.remediationType
      ) {
        score += 2;
      }
      return { script, relevanceScore: score };
    })
    .filter(({ relevanceScore }) => relevanceScore > 0)
    .sort((a, b) => b.relevanceScore - a.relevanceScore)
    .slice(0, limit);

  if (scoredScripts.length === 0) return null;

  return (
    <section className="mt-16" aria-labelledby="related-scripts-heading">
      {/* Section opener — mono kicker + display headline */}
      <div
        className="border-t pt-10"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <p className="font-mono-label text-accent-hi">// RELATED</p>
        <h2
          id="related-scripts-heading"
          className="font-display text-foreground mt-3 text-2xl leading-tight tracking-[-0.02em] sm:text-3xl"
        >
          Scripts that travel together.
        </h2>
        <p className="text-muted-foreground mt-3 max-w-xl text-sm leading-relaxed sm:text-base">
          Picked by shared tags, category, and script type — nothing magic, just
          metadata overlap.
        </p>
      </div>

      {/* Manifest list — hairline-bordered rows, mono index, display title.
       * Each row is a real <Link>; click target spans the full row. */}
      <ol
        className="bg-card/40 mt-8 overflow-hidden rounded-md border backdrop-blur-md"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        {scoredScripts.map(({ script }, index) => {
          const sharedTags = script.tags.filter((tag) =>
            currentScript.tags.includes(tag),
          );
          return (
            <li
              key={script.id}
              className={
                index === 0
                  ? ""
                  : "border-t"
              }
              style={
                index === 0
                  ? undefined
                  : { borderColor: "var(--brand-rule)" }
              }
            >
              <Link
                href={`/script/${script.slug}/`}
                className="group focus-visible:ring-accent grid grid-cols-[auto_1fr_auto] items-start gap-x-5 gap-y-2 px-5 py-5 transition-colors hover:bg-[color-mix(in_oklab,var(--brand-accent)_5%,transparent)] focus-visible:ring-1 focus-visible:ring-inset focus-visible:outline-none sm:px-6 sm:py-6"
              >
                {/* Numeric index — mono tabular */}
                <span
                  aria-hidden="true"
                  className="text-muted-foreground/60 mt-1.5 font-mono text-[11px] tabular-nums tracking-widest"
                >
                  {String(index + 1).padStart(2, "0")}
                </span>

                {/* Title + description + tags */}
                <div className="min-w-0">
                  <h3 className="font-display text-foreground group-hover:text-accent-hi text-lg leading-snug tracking-[-0.015em] transition-colors sm:text-xl">
                    {script.title}
                  </h3>
                  <p className="text-muted-foreground mt-1.5 line-clamp-2 text-sm leading-relaxed">
                    {script.description}
                  </p>

                  {sharedTags.length > 0 && (
                    <div className="mt-3 flex flex-wrap gap-1.5">
                      {sharedTags.map((tag) => (
                        <span
                          key={tag}
                          className="text-muted-foreground inline-flex items-center rounded-sm border px-1.5 py-0.5 font-mono text-[10px] tracking-[0.14em] uppercase"
                          style={{ borderColor: "var(--brand-rule)" }}
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                {/* Affordance arrow — slides on hover */}
                <span
                  aria-hidden="true"
                  className="text-muted-foreground/60 group-hover:text-accent-hi mt-1.5 inline-flex shrink-0 items-center justify-center transition-all duration-200 group-hover:-translate-y-px group-hover:translate-x-0.5"
                >
                  <ArrowUpRight className="h-4 w-4" />
                </span>
              </Link>
            </li>
          );
        })}
      </ol>

      {/* Footer link — mono affordance to browse all */}
      <div className="mt-6 flex justify-center">
        <Link
          href="/scripts/"
          className="text-muted-foreground hover:text-foreground focus-visible:ring-accent group inline-flex items-center gap-2 rounded-sm font-mono text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none"
        >
          Browse all scripts
          <ArrowUpRight
            className="h-3 w-3 transition-transform group-hover:-translate-y-px group-hover:translate-x-0.5"
            aria-hidden="true"
          />
        </Link>
      </div>
    </section>
  );
}
