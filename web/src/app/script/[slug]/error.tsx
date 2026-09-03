"use client";

import Link from "next/link";
import { useEffect } from "react";
import { Button } from "~/components/ui/button";

// Rendered when the script catalog cannot be loaded (for example a GitHub API
// outage). Next.js serves this with a 500 that is never cached, so the page
// recovers on the next request instead of serving a stale 404.
export default function ScriptError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("Script page failed to render:", error);
  }, [error]);

  return (
    <main className="container mx-auto flex min-h-[60vh] max-w-2xl flex-col items-center justify-center px-4 py-16 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">
        This script could not be loaded right now
      </h1>
      <p className="text-muted-foreground mt-3">
        The script library is temporarily unavailable. The script has not been
        removed. Please try again in a moment.
      </p>
      <div className="mt-8 flex gap-3">
        <Button onClick={() => reset()}>Try again</Button>
        <Button asChild variant="outline">
          <Link href="/scripts/">Browse all scripts</Link>
        </Button>
      </div>
    </main>
  );
}
