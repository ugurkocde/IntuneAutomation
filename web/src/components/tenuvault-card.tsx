"use client";

// One labelled card for TenuVault, the desktop app by the author of these
// scripts. Where the page has a topic TenuVault covers, the caller passes the
// matching message. Elsewhere the day's general message is used.

import { useEffect, useState } from "react";
import { ArrowUpRight } from "lucide-react";
import {
  GENERAL_MESSAGES,
  GENERAL_MESSAGE_IDS,
  generalMessageFor,
  tenuvaultMessageUrl,
  type TenuVaultMessage,
  type TenuVaultPlacement,
} from "~/lib/tenuvault";

type PlausibleWindow = Window & {
  plausible?: (
    event: string,
    options?: { props?: Record<string, string> },
  ) => void;
};

interface TenuVaultCardProps {
  placement: TenuVaultPlacement;
  // A message that fits the page. Without one, the day's general message is
  // used.
  message?: TenuVaultMessage;
  // For narrow columns such as the generator's inspector.
  compact?: boolean;
  className?: string;
}

export function TenuVaultCard({
  placement,
  message,
  compact = false,
  className = "",
}: TenuVaultCardProps) {
  const [general, setGeneral] = useState<TenuVaultMessage | null>(null);

  useEffect(() => {
    if (!message) setGeneral(generalMessageFor(new Date()));
  }, [message]);

  // The pages are static and may be served a day after they were built, so
  // the day's general message is only known in the browser. Until then
  // nothing is shown or clickable, and the card already has its final size.
  const shown = message ?? general;
  // Every message the card may show is laid out in the same grid cell, so the
  // card is as tall as the longest one at any width and never changes size.
  const candidates: TenuVaultMessage[] = message
    ? [message]
    : GENERAL_MESSAGE_IDS.map((id) => GENERAL_MESSAGES[id]);
  const link = shown ?? candidates[0]!;

  // A generated script is not the author's work, so the generator names the
  // site instead.
  const origin =
    placement === "generator"
      ? "From the maker of IntuneAutomation"
      : "From the author of these scripts";

  const track = () => {
    (window as PlausibleWindow).plausible?.("House Ad Click", {
      props: { message: link.tag, placement },
    });
  };

  return (
    <aside
      aria-label={`TenuVault, ${origin.charAt(0).toLowerCase()}${origin.slice(1)}`}
      data-tenuvault-card={shown ? shown.id : "pending"}
      className={`bg-card/40 rounded-md border backdrop-blur-md ${compact ? "px-4 py-4" : "px-5 py-5 sm:px-6"} ${className}`}
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <p className="font-mono-label text-accent-hi">
        <span aria-hidden="true">// </span>TenuVault · {origin}
      </p>
      <div className="grid">
        {candidates.map((candidate) => {
          const active = candidate.id === shown?.id;
          return (
            <div
              key={candidate.id}
              aria-hidden={!active}
              className={`col-start-1 row-start-1 transition-opacity duration-300 ${active ? "opacity-100" : "invisible opacity-0"}`}
            >
              <p
                className={`font-display text-foreground mt-3 leading-tight tracking-[-0.02em] ${compact ? "text-base" : "text-xl sm:text-2xl"}`}
              >
                {candidate.headline}
              </p>
              <p
                className={`text-muted-foreground mt-2 leading-relaxed ${compact ? "text-[12.5px]" : "max-w-3xl text-sm"}`}
              >
                {candidate.body}
              </p>
            </div>
          );
        })}
      </div>
      <a
        href={tenuvaultMessageUrl(link, placement)}
        target="_blank"
        rel="sponsored noopener"
        onClick={track}
        className={`text-accent-hi mt-4 inline-flex items-center gap-1.5 font-medium underline decoration-[color:var(--brand-rule)] underline-offset-[5px] transition-[opacity,text-decoration-color] duration-300 hover:decoration-[color:var(--brand-accent)] focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:outline-none ${compact ? "text-[12.5px]" : "text-sm"} ${shown ? "opacity-100" : "invisible opacity-0"}`}
      >
        {link.action}
        <span className="sr-only"> (opens in new tab)</span>
        <ArrowUpRight
          className="h-4 w-4"
          aria-hidden="true"
          strokeWidth={1.5}
        />
      </a>
    </aside>
  );
}
