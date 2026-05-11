"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@supabase/supabase-js";
import { Mail } from "lucide-react";
import { getSubscriberHeaders } from "~/lib/supabase-headers";

// Initialize Supabase client
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

export default function SubscriptionForm() {
  const [email, setEmail] = useState<string>("");
  const [status, setStatus] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);

  const handleSubscribe = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);
    setStatus("");

    try {
      // Check if email already exists
      const { data: existing } = await supabase
        .from("script_subscribers")
        .select("email, is_active")
        .eq("email", email)
        .setHeader("check_email", email)
        .single();

      if (existing) {
        if (existing.is_active) {
          setStatus("You are already subscribed!");
          setLoading(false);
          return;
        } else {
          // Reactivate existing subscription
          const { error } = await supabase
            .from("script_subscribers")
            .update({ is_active: true })
            .eq("email", email)
            .setHeader("email", email);

          if (error) throw error;

          setStatus("Welcome back! Your subscription has been reactivated.");
          setEmail("");
          setLoading(false);
          return;
        }
      }

      // Add new subscriber
      const { error } = await supabase
        .from("script_subscribers")
        .insert([{ email, is_active: true }]);

      if (error) throw error;

      setStatus(
        "Successfully subscribed! You will receive notifications when scripts are added or updated.",
      );
      setEmail("");
    } catch (error: any) {
      if (error?.message?.includes("duplicate")) {
        setStatus("This email is already subscribed!");
      } else if (error?.message?.includes("RLS")) {
        setStatus("Database configuration error. Please contact support.");
      } else {
        setStatus("Error subscribing. Please try again.");
      }
      console.error("Subscription error:", error);
    } finally {
      setLoading(false);
    }
  };

  const isError = status.toLowerCase().includes("error");

  return (
    <div
      className="bg-card/40 my-8 overflow-hidden rounded-md border backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <div
        className="flex items-center justify-between border-b px-5 py-3"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <p className="text-muted-foreground font-mono text-[11px] tracking-[0.18em] uppercase">
          // SUBSCRIBE
        </p>
        <Mail
          className="h-3.5 w-3.5"
          strokeWidth={1.75}
          style={{ color: "var(--brand-accent-hi)" }}
          aria-hidden="true"
        />
      </div>

      <div className="px-6 py-6">
        <h3 className="font-display text-foreground mb-2 text-xl tracking-tight">
          Subscribe to script updates
        </h3>
        <p className="text-muted-foreground mb-5 text-sm leading-relaxed">
          Get notified when new Intune automation scripts are added or updated.
        </p>

        <form
          onSubmit={handleSubscribe}
          className="flex flex-col gap-3 sm:flex-row"
        >
          <input
            type="email"
            placeholder="you@company.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            disabled={loading}
            className="bg-background text-foreground placeholder:text-muted-foreground focus-visible:ring-accent flex-1 rounded-md border px-4 py-2.5 text-sm transition-colors focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none disabled:opacity-60"
            style={{ borderColor: "var(--brand-rule)" }}
          />
          <button
            type="submit"
            disabled={loading}
            className="bg-foreground text-background ring-accent inline-flex h-11 items-center justify-center gap-2 rounded-md px-5 text-sm font-medium shadow-[inset_0_1px_0_color-mix(in_oklab,white_18%,transparent)] transition-transform duration-150 hover:-translate-y-0.5 focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none active:translate-y-0 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:translate-y-0"
          >
            {loading ? "Subscribing..." : "Subscribe"}
          </button>
        </form>

        {status && (
          <p
            className="mt-4 font-mono text-[11px] tracking-[0.14em] uppercase"
            style={{
              color: isError
                ? "var(--destructive)"
                : "var(--brand-accent-hi)",
            }}
          >
            {status}
          </p>
        )}
      </div>
    </div>
  );
}
