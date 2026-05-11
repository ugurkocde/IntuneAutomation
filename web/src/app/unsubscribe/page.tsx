"use client";

import { useState, useEffect, Suspense } from "react";
import { createClient } from "@supabase/supabase-js";
import { useSearchParams } from "next/navigation";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

function UnsubscribeContent() {
  const searchParams = useSearchParams();
  const token = searchParams.get("token");

  const [status, setStatus] = useState<
    "loading" | "success" | "error" | "invalid"
  >("loading");
  const [message, setMessage] = useState("");

  useEffect(() => {
    if (!token) {
      setStatus("invalid");
      setMessage(
        "Invalid unsubscribe link. Please check your email for the correct link.",
      );
      return;
    }

    handleUnsubscribe();
  }, [token]);

  const handleUnsubscribe = async () => {
    if (!token) return;

    try {
      // Update the subscriber's status to inactive using the unsubscribe token
      const { error } = await supabase
        .from("script_subscribers")
        .update({ is_active: false })
        .eq("unsubscribe_token", token)
        .setHeader("unsubscribe_token", token);

      if (error) {
        throw error;
      }

      setStatus("success");
      setMessage(
        `You have been successfully unsubscribed. We're sorry to see you go!`,
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
      setMessage("You have been successfully re-subscribed to script updates!");
    } catch (error) {
      console.error("Resubscribe error:", error);
      setStatus("error");
      setMessage("An error occurred. Please try again.");
    }
  };

  return (
    <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
      <Navbar />

      <main className="flex-1">
        <div className="flex min-h-[calc(100vh-8rem)] items-center justify-center px-4 py-16">
          <div className="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 shadow-xl dark:border-gray-700 dark:bg-gray-800">
            <div className="text-center">
              {status === "loading" && (
                <>
                  <div className="mx-auto mb-4 h-12 w-12 animate-spin rounded-full border-b-2 border-blue-600"></div>
                  <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
                    Processing your request...
                  </h2>
                </>
              )}

              {status === "success" && (
                <>
                  <div className="mb-4 text-6xl">✅</div>
                  <h2 className="mb-4 text-2xl font-bold text-gray-900 dark:text-gray-100">
                    Unsubscribe Successful
                  </h2>
                  <p className="mb-6 text-gray-600 dark:text-gray-300">
                    {message}
                  </p>
                  <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">
                    Changed your mind? You can re-subscribe anytime.
                  </p>
                  <button
                    onClick={handleResubscribe}
                    className="transform rounded-lg bg-gradient-to-r from-blue-600 to-purple-600 px-6 py-3 font-medium text-white shadow-md transition-all duration-200 hover:scale-105 hover:from-blue-700 hover:to-purple-700 hover:shadow-lg"
                  >
                    Re-subscribe
                  </button>
                </>
              )}

              {status === "error" && (
                <>
                  <div className="mb-4 text-6xl">❌</div>
                  <h2 className="mb-4 text-2xl font-bold text-gray-900 dark:text-gray-100">
                    Something went wrong
                  </h2>
                  <p className="mb-6 text-gray-600 dark:text-gray-300">
                    {message}
                  </p>
                  <button
                    onClick={handleUnsubscribe}
                    className="transform rounded-lg bg-gradient-to-r from-blue-600 to-purple-600 px-6 py-3 font-medium text-white shadow-md transition-all duration-200 hover:scale-105 hover:from-blue-700 hover:to-purple-700 hover:shadow-lg"
                  >
                    Try Again
                  </button>
                </>
              )}

              {status === "invalid" && (
                <>
                  <div className="mb-4 text-6xl">⚠️</div>
                  <h2 className="mb-4 text-2xl font-bold text-gray-900 dark:text-gray-100">
                    Invalid Link
                  </h2>
                  <p className="text-gray-600 dark:text-gray-300">{message}</p>
                </>
              )}
            </div>

            <div className="mt-8 border-t border-gray-200 pt-6 text-center dark:border-gray-700">
              <a
                href="/"
                className="text-sm text-blue-600 transition-colors duration-200 hover:text-blue-700 hover:underline dark:text-blue-400 dark:hover:text-blue-300"
              >
                Return to homepage
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

function UnsubscribePageContent() {
  return (
    <Suspense
      fallback={
        <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
          <Navbar />
          <main className="flex-1">
            <div className="flex min-h-[calc(100vh-8rem)] items-center justify-center px-4 py-16">
              <div className="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 shadow-xl dark:border-gray-700 dark:bg-gray-800">
                <div className="text-center">
                  <div className="mx-auto mb-4 h-12 w-12 animate-spin rounded-full border-b-2 border-blue-600"></div>
                  <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
                    Loading...
                  </h2>
                </div>
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
