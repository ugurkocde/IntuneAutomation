"use client";

import { useEffect, useState } from "react";
import { Info, X } from "lucide-react";

// Site-wide announcement bar. Renders nothing after EXPIRES_AT (checked in the
// browser, so it disappears on time even without a redeploy) or once dismissed.
const BANNER_ID = "auth-mggraphcommunity-2026-07";
const EXPIRES_AT = Date.parse("2026-07-26T23:59:59Z");

export function AnnouncementBanner() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (Date.now() >= EXPIRES_AT) return;
    if (window.localStorage.getItem(`banner-dismissed-${BANNER_ID}`)) return;
    setVisible(true);
  }, []);

  if (!visible) return null;

  const dismiss = () => {
    window.localStorage.setItem(`banner-dismissed-${BANNER_ID}`, "1");
    setVisible(false);
  };

  return (
    <div className="border-border bg-muted/60 relative border-b text-sm">
      <div className="container mx-auto flex items-start gap-2 px-4 py-2.5 pr-10 sm:items-center">
        <Info className="text-primary mt-0.5 h-4 w-4 shrink-0 sm:mt-0" />
        <p className="text-muted-foreground">
          <span className="text-foreground font-medium">
            Authentication change:
          </span>{" "}
          local interactive sign-in in our scripts now uses the{" "}
          <a
            href="https://github.com/ugurkocde/MgGraphCommunity"
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary font-medium underline underline-offset-2"
          >
            MgGraphCommunity
          </a>{" "}
          module (installed automatically) because Microsoft Graph PowerShell
          v2.34.0+ enforces the WAM broker on Windows, which breaks sign-in with
          separate admin accounts. Azure Automation runbooks are unchanged.
        </p>
      </div>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss announcement"
        className="text-muted-foreground hover:bg-muted hover:text-foreground absolute top-1/2 right-2 -translate-y-1/2 rounded-md p-1.5 transition-colors"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
