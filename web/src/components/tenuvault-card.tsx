"use client";

// One labelled card for TenuVault, the desktop app by the author of these
// scripts. Where the page has a topic TenuVault covers, the caller passes the
// matching message. Elsewhere the visitor's own general message is used.

import { useEffect, useState } from "react";
import { ArrowUpRight } from "lucide-react";
import {
  GENERAL_MESSAGES,
  pickGeneralMessage,
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

// Reading the property can throw where storage is blocked.
function browserStorage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

interface TenuVaultCardProps {
  placement: TenuVaultPlacement;
  // A message that fits the page. Without one, the visitor's general message
  // is picked in the browser.
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
    if (!message) setGeneral(pickGeneralMessage(browserStorage()));
  }, [message]);

  // The pages are static, so the general message is only known in the
  // browser. The longer one holds the space until then and the text fades in,
  // so nothing below the card moves.
  const shown = message ?? general ?? GENERAL_MESSAGES.restore;
  const ready = Boolean(message ?? general);
  const fade = `transition-opacity duration-300 ${ready ? "opacity-100" : "opacity-0"}`;

  const track = () => {
    (window as PlausibleWindow).plausible?.("House Ad Click", {
      props: { message: shown.id, placement },
    });
  };

  return (
    <aside
      aria-label="TenuVault, from the author of these scripts"
      data-tenuvault-card={ready ? shown.id : "pending"}
      className={`bg-card/40 rounded-md border backdrop-blur-md ${compact ? "px-4 py-4" : "px-5 py-5 sm:px-6"} ${className}`}
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <p className="font-mono-label text-accent-hi">
        // TenuVault · From the author of these scripts
      </p>
      <div
        className={`${fade} ${message ? "" : compact ? "min-h-[7.75rem]" : "min-h-[6.5rem] sm:min-h-[5rem]"}`}
        aria-hidden={!ready}
      >
        <p
          className={`font-display text-foreground mt-3 leading-tight tracking-[-0.02em] ${compact ? "text-base" : "text-xl sm:text-2xl"}`}
        >
          {shown.headline}
        </p>
        <p
          className={`text-muted-foreground mt-2 leading-relaxed ${compact ? "text-[12.5px]" : "max-w-3xl text-sm"}`}
        >
          {shown.body}
        </p>
      </div>
      <a
        href={tenuvaultMessageUrl(shown, placement)}
        target="_blank"
        rel="sponsored noopener"
        tabIndex={ready ? undefined : -1}
        onClick={track}
        className={`text-accent-hi mt-4 inline-flex items-center gap-1.5 font-medium underline decoration-[color:var(--brand-rule)] underline-offset-[5px] transition-colors hover:decoration-[color:var(--brand-accent)] focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:outline-none ${compact ? "text-[12.5px]" : "text-sm"} ${fade}`}
      >
        {shown.action}
        <ArrowUpRight
          className="h-4 w-4"
          aria-hidden="true"
          strokeWidth={1.5}
        />
      </a>
    </aside>
  );
}
