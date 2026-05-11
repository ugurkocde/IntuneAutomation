"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@supabase/supabase-js";
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

  return (
    <div className="my-8 rounded-lg bg-gray-50 p-6 dark:bg-gray-800">
      <h3 className="mb-2 flex items-center gap-2 text-xl font-semibold">
        <span>📧</span>
        <span>Subscribe to Script Updates</span>
      </h3>
      <p className="mb-4 text-gray-600 dark:text-gray-300">
        Get notified when new Intune automation scripts are added or updated.
      </p>

      <form onSubmit={handleSubscribe} className="flex gap-3">
        <input
          type="email"
          placeholder="Enter your email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          disabled={loading}
          className="flex-1 rounded-md border border-gray-300 bg-white px-4 py-2 text-gray-900 placeholder-gray-400 focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:opacity-60 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-500"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-md bg-blue-600 px-6 py-2 font-medium text-white transition-colors hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {loading ? "Subscribing..." : "Subscribe"}
        </button>
      </form>

      {status && (
        <p
          className={`mt-4 ${status.includes("Error") ? "text-red-600 dark:text-red-400" : "text-green-600 dark:text-green-400"}`}
        >
          {status}
        </p>
      )}
    </div>
  );
}
