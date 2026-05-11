// /unsubscribe page — v4 vocabulary.
// Plain page background (atmosphere primitives are landing-only), v4 card with
// hairline border, mono kickers, Lucide status icons, cyan-accent button.

"use client";

import { useState, useEffect, Suspense } from "react";
import { createClient } from "@supabase/supabase-js";
import { useSearchParams } from "next/navigation";
import { AlertTriangle, CheckCircle, XCircle, Loader2 } from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  },
);

type Status = "loading" | "success" | "error" | "invalid";

function UnsubscribeContent() {
  const searchParams = useSearchParams();
  const token = searchParams.get("token");

  const [status, setStatus] = useState<Status>("loading");
  const [message, setMessage] = useState("");

  useEffect(() => {
    if (!token) {
      setStatus("invalid");
      setMessage(
        "Invalid unsubscribe link. Please check your email for the correct link.",
      );
      return;
    }
    void handleUnsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  const handleUnsubscribe = async () => {
    if (!token) return;
    try {
      const { error } = await supabase
        .from("script_subscribers")
        .update({ is_active: false })
        .eq("unsubscribe_token", token)
        .setHeader("unsubscribe_token", token);

      if (error) throw error;

      setStatus("success");
      setMessage(
        "You have been successfully unsubscribed. We're sorry to see you go.",
      );
    } catch (error) {
      console.error("Unsubscribe error:", error);
      setStatus("error");
      setMessage(
        "An error occurred while unsubscribing. Please try again or contact support.",
      );
    }
  };

  const handleResubscribe = async () => {
    if (!token) return;
    setStatus("loading");
    try {
      const { error } = await supabase
        .from("script_subscribers")
        .update({ is_active: true })
        .eq("unsubscribe_token", token)
        .setHeader("unsubscribe_token", token);

      if (error) throw error;

      setStatus("success");
      setMessage("You have been successfully re-subscribed to script updates.");
    } catch (error) {
      console.error("Resubscribe error:", error);
      setStatus("error");
      setMessage("An error occurred. Please try again.");
    }
  };

  return (
    <div className="bg-background flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-md items-center px-4 py-20">
          <div
            className="bg-card/40 w-full overflow-hidden rounded-lg border backdrop-blur-md"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <div
              className="flex items-center justify-between border-b px-5 py-3"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
                // SUBSCRIPTION
              </p>
              <StatusKicker status={status} />
            </div>

            <div className="px-6 py-10 text-center">
              {status === "loading" && (
                <>
                  <Loader2
                    className="text-muted-foreground mx-auto mb-5 h-10 w-10 animate-spin"
                    strokeWidth={1.5}
                    aria-hidden="true"
                  />
                  <h2 className="font-display text-foreground text-xl tracking-tight">
                    Processing your request
                  </h2>
                </>
              )}

              {status === "success" && (
                <>
                  <span
                    aria-hidden="true"
                    className="mx-auto mb-5 inline-flex h-12 w-12 items-center justify-center rounded-full"
                    style={{
                      backgroundColor:
                        "color-mix(in oklab, var(--brand-accent) 14%, transparent)",
                    }}
                  >
                    <CheckCircle
                      className="h-6 w-6"
                      strokeWidth={1.75}
                      style={{ color: "var(--brand-accent-hi)" }}
                      aria-hidden="true"
                    />
                  </span>
                  <h2 className="font-display text-foreground mb-3 text-2xl tracking-tight">
                    Unsubscribe successful
                  </h2>
                  <p className="text-muted-foreground mb-2 text-sm leading-relaxed">
                    {message}
                  </p>
                  <p className="text-muted-foreground mb-7 font-mono text-[11px] tracking-[0.12em] uppercase">
                    Changed your mind? Re-subscribe anytime.
                  </p>
                  <button
                    onClick={handleResubscribe}
                    className="ring-accent inline-flex h-11 items-center gap-2 rounded-md bg-foreground px-5 text-sm font-medium text-background shadow-[inset_0_1px_0_color-mix(in_oklab,white_18%,transparent)] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none active:translate-y-0"
                  >
                    Re-subscribe
                  </button>
                </>
              )}

              {status === "error" && (
                <>
                  <span
                    aria-hidden="true"
                    className="mx-auto mb-5 inline-flex h-12 w-12 items-center justify-center rounded-full bg-destructive/15"
                  >
                    <XCircle
                      className="text-destructive h-6 w-6"
                      strokeWidth={1.75}
                      aria-hidden="true"
                    />
                  </span>
                  <h2 className="font-display text-foreground mb-3 text-2xl tracking-tight">
                    Something went wrong
                  </h2>
                  <p className="text-muted-foreground mb-7 text-sm leading-relaxed">
                    {message}
                  </p>
                  <button
                    onClick={handleUnsubscribe}
                    className="ring-accent inline-flex h-11 items-center gap-2 rounded-md bg-foreground px-5 text-sm font-medium text-background shadow-[inset_0_1px_0_color-mix(in_oklab,white_18%,transparent)] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none active:translate-y-0"
                  >
                    Try again
                  </button>
                </>
              )}

              {status === "invalid" && (
                <>
                  <span
                    aria-hidden="true"
                    className="mx-auto mb-5 inline-flex h-12 w-12 items-center justify-center rounded-full"
                    style={{
                      backgroundColor:
                        "color-mix(in oklab, var(--brand-warn) 18%, transparent)",
                    }}
                  >
                    <AlertTriangle
                      className="h-6 w-6"
                      strokeWidth={1.75}
                      style={{ color: "var(--brand-warn)" }}
                      aria-hidden="true"
                    />
                  </span>
                  <h2 className="font-display text-foreground mb-3 text-2xl tracking-tight">
                    Invalid link
                  </h2>
                  <p className="text-muted-foreground text-sm leading-relaxed">
                    {message}
                  </p>
                </>
              )}
            </div>

            <div
              className="border-t px-5 py-3 text-center"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <a
                href="/"
                className="text-muted-foreground hover:text-foreground font-mono inline-flex items-center gap-1 text-[11px] tracking-[0.14em] uppercase transition-colors"
              >
                ← Return to homepage
              </a>
            </div>
          </div>
        </div>
      </main>
      <SearchDialog />
      <Footer />
    </div>
  );
}

function StatusKicker({ status }: { status: Status }) {
  const label =
    status === "loading"
      ? "PROCESSING"
      : status === "success"
        ? "CONFIRMED"
        : status === "error"
          ? "ERROR"
          : "INVALID";
  const color =
    status === "loading"
      ? "var(--brand-accent-hi)"
      : status === "success"
        ? "var(--brand-accent-hi)"
        : status === "error"
          ? "var(--destructive)"
          : "var(--brand-warn)";
  return (
    <span
      className="font-mono text-[10px] tracking-[0.18em] uppercase"
      style={{ color }}
    >
      {label}
    </span>
  );
}

function UnsubscribePageContent() {
  return (
    <Suspense
      fallback={
        <div className="bg-background flex min-h-screen flex-col">
          <Navbar />
          <main className="flex-1">
            <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-md items-center px-4 py-20">
              <div
                className="bg-card/40 w-full overflow-hidden rounded-lg border px-6 py-10 text-center backdrop-blur-md"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                <Loader2
                  className="text-muted-foreground mx-auto mb-5 h-10 w-10 animate-spin"
                  strokeWidth={1.5}
                  aria-hidden="true"
                />
                <p className="font-mono text-muted-foreground text-[11px] tracking-[0.18em] uppercase">
                  Loading
                </p>
              </div>
            </div>
          </main>
          <SearchDialog />
          <Footer />
        </div>
      }
    >
      <UnsubscribeContent />
    </Suspense>
  );
}

export default function UnsubscribePage() {
  return (
    <ScriptsProvider>
      <UnsubscribePageContent />
    </ScriptsProvider>
  );
}
