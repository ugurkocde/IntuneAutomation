"use client";

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Mail, CheckCircle, RefreshCw } from "lucide-react";
import { Button } from "~/components/ui/button";
import { createClient } from "@supabase/supabase-js";
import { useToast } from "~/hooks/use-toast";

// SSR-safe init — avoids the localStorage polyfill present in Node 22+.
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

interface FloatingSubscriptionCTAProps {
  triggerAfterViews?: number;
  triggerAfterScroll?: number;
}

// Triggers are intentionally activation-gated. We require at least one script
// interaction before showing the CTA (or an explicit "show subscription form"
// event from elsewhere in the app). The pure time-based trigger was removed —
// asking for email before the visitor has received any value is an anti-pattern
// for a trust-sensitive admin audience.
export default function FloatingSubscriptionCTA({
  triggerAfterViews = 1,
  triggerAfterScroll = 75,
}: FloatingSubscriptionCTAProps) {
  const { toast } = useToast();
  const [isVisible, setIsVisible] = useState(false);
  const [isDismissed, setIsDismissed] = useState(false);
  const [email, setEmail] = useState("");
  const [isSubscribing, setIsSubscribing] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [viewCount, setViewCount] = useState(0);
  const [isSuccess, setIsSuccess] = useState(false);
  const [subscriberCount, setSubscriberCount] = useState<number | null>(null);

  // Refs survive effect re-registration so each trigger can only fire once
  // per session, regardless of how many times `isVisible` flips.
  const hasTriggeredByScroll = useRef(false);
  const hasTriggeredByExitIntent = useRef(false);
  const isVisibleRef = useRef(isVisible);
  const isDismissedRef = useRef(isDismissed);

  useEffect(() => {
    isVisibleRef.current = isVisible;
  }, [isVisible]);

  useEffect(() => {
    isDismissedRef.current = isDismissed;
  }, [isDismissed]);

  useEffect(() => {
    // Fetch subscriber count from Supabase
    const fetchSubscriberCount = async () => {
      try {
        const { count } = await supabase
          .from("script_subscribers")
          .select("*", { count: "exact", head: true });

        if (count !== null) {
          setSubscriberCount(count);
        }
      } catch (error) {
        console.warn("Failed to fetch subscriber count:", error);
      }
    };

    void fetchSubscriberCount();
  }, []);

  useEffect(() => {
    // Check if user has already dismissed or subscribed
    const dismissed = localStorage.getItem("subscription_cta_dismissed");
    const subscribed = localStorage.getItem("user_subscribed");

    if (dismissed === "true" || subscribed === "true") {
      setIsDismissed(true);
      return;
    }

    // Track script views — funcitonal setState reads the latest count without
    // re-registering, and we check isVisibleRef so the listener doesn't need
    // to be torn down when isVisible flips.
    const handleScriptView = () => {
      setViewCount((prev) => {
        const newCount = prev + 1;
        if (newCount >= triggerAfterViews && !isVisibleRef.current) {
          setIsVisible(true);
        }
        return newCount;
      });
    };
    window.addEventListener("scriptViewed", handleScriptView);

    // Listen for show subscription form event
    const handleShowForm = () => {
      if (!isDismissedRef.current) {
        setIsVisible(true);
        setShowForm(true);
      }
    };
    window.addEventListener("showSubscriptionForm", handleShowForm);

    // Track scroll depth — once per session, guarded by ref so the trigger
    // can't fire again after isVisible flips and the effect re-runs.
    const handleScroll = () => {
      if (hasTriggeredByScroll.current) return;
      if (isDismissedRef.current) return;

      const scrollPercentage =
        (window.scrollY /
          (document.documentElement.scrollHeight - window.innerHeight)) *
        100;

      if (scrollPercentage >= triggerAfterScroll && !isVisibleRef.current) {
        hasTriggeredByScroll.current = true;
        setIsVisible(true);
      }
    };
    window.addEventListener("scroll", handleScroll, { passive: true });

    // Exit-intent trigger (when mouse leaves viewport from top edge) — also
    // ref-guarded so it can only fire once per session.
    const handleMouseLeave = (e: MouseEvent) => {
      if (hasTriggeredByExitIntent.current) return;
      if (isDismissedRef.current) return;

      if (e.clientY <= 0 && !isVisibleRef.current) {
        hasTriggeredByExitIntent.current = true;
        setIsVisible(true);
      }
    };
    document.addEventListener("mouseleave", handleMouseLeave);

    return () => {
      window.removeEventListener("scriptViewed", handleScriptView);
      window.removeEventListener("showSubscriptionForm", handleShowForm);
      window.removeEventListener("scroll", handleScroll);
      document.removeEventListener("mouseleave", handleMouseLeave);
    };
    // Listeners no longer depend on isVisible/isDismissed (refs handle that),
    // so the effect runs only once on mount unless the trigger thresholds
    // change via props.
  }, [triggerAfterViews, triggerAfterScroll]);

  const handleDismiss = () => {
    setIsVisible(false);
    setIsDismissed(true);
    localStorage.setItem("subscription_cta_dismissed", "true");

    // Reset dismiss after 7 days
    setTimeout(
      () => {
        localStorage.removeItem("subscription_cta_dismissed");
      },
      7 * 24 * 60 * 60 * 1000,
    );
  };

  const handleSubscribe = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubscribing(true);

    try {
      // Check if email already exists
      const { data: existing } = await supabase
        .from("script_subscribers")
        .select("email, is_active")
        .eq("email", email)
        .single();

      if (existing) {
        if (existing.is_active) {
          toast({
            title: "Already subscribed!",
            description: "You're already receiving script updates.",
          });
        } else {
          // Reactivate subscription
          const { error } = await supabase
            .from("script_subscribers")
            .update({ is_active: true })
            .eq("email", email);

          if (error) throw error;

          toast({
            title: "Welcome back!",
            description: "Your subscription has been reactivated.",
          });
        }
      } else {
        // Add new subscriber
        const { error } = await supabase
          .from("script_subscribers")
          .insert([{ email }]);

        if (error) throw error;

        setIsSuccess(true);

        // Show success state for 3 seconds before closing
        setTimeout(() => {
          localStorage.setItem("user_subscribed", "true");
          setIsVisible(false);
          setIsDismissed(true);
        }, 3000);
      }

      setEmail("");
    } catch (error) {
      toast({
        title: "Subscription failed",
        description: "Please try again later.",
        variant: "destructive",
      });
    } finally {
      setIsSubscribing(false);
    }
  };

  if (isDismissed || !isVisible) return null;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, scale: 0.8, y: 100 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.8, y: 100 }}
        transition={{
          type: "spring",
          damping: 20,
          stiffness: 300,
          duration: 0.4,
        }}
        className="fixed right-4 bottom-4 z-50 sm:right-6 sm:bottom-6"
      >
        <div className="relative">
          {!showForm ? (
            // Slim cyan-outlined pill with a sibling dismiss button (avoids
            // nested interactive content — keeps tab order to two stops).
            <div
              className="bg-background/90 inline-flex items-center gap-1 rounded-full border pl-4 pr-1 py-1 text-sm shadow-lg backdrop-blur-xl sm:pl-5"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              <button
                type="button"
                onClick={() => setShowForm(true)}
                className="group focus-visible:ring-accent inline-flex items-center gap-2.5 rounded-full py-1 transition-colors focus-visible:ring-2 focus-visible:outline-none sm:py-1.5"
                aria-label="Open subscription form"
              >
                <span
                  aria-hidden="true"
                  className="h-1.5 w-1.5 rounded-full"
                  style={{ backgroundColor: "var(--brand-accent)" }}
                />
                <span className="text-foreground font-medium">
                  Script updates
                </span>
              </button>
              <button
                type="button"
                onClick={handleDismiss}
                className="text-muted-foreground hover:text-foreground focus-visible:ring-accent flex h-7 w-7 items-center justify-center rounded-full transition-colors focus-visible:ring-2 focus-visible:outline-none"
                aria-label="Dismiss subscription prompt"
              >
                <X className="h-3 w-3" strokeWidth={1.75} />
              </button>
            </div>
          ) : (
            // Expanded form — sober card, cyan accent rule on top, no gradients
            <motion.div
              initial={{ opacity: 0, scale: 0.98, y: 8 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              className="bg-card relative w-[calc(100vw-2rem)] max-w-[380px] overflow-hidden rounded-lg border shadow-2xl backdrop-blur-xl"
              style={{ borderColor: "var(--brand-rule)" }}
            >
              {/* Single cyan top rule replaces gradient header */}
              <div
                className="relative h-px"
                style={{ backgroundColor: "var(--brand-accent)" }}
              />

              {/* Success state */}
              {isSuccess ? (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="p-4 text-center sm:p-6"
                >
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{
                      type: "spring",
                      delay: 0.2,
                      damping: 15,
                      stiffness: 300,
                    }}
                  >
                    <div
                      className="mx-auto mb-3 flex h-10 w-10 items-center justify-center rounded-full sm:mb-4 sm:h-12 sm:w-12"
                      style={{
                        backgroundColor:
                          "color-mix(in oklab, var(--brand-accent) 14%, transparent)",
                      }}
                    >
                      <CheckCircle
                        className="h-5 w-5 sm:h-6 sm:w-6"
                        style={{ color: "var(--brand-accent-hi)" }}
                      />
                    </div>
                  </motion.div>

                  <h3 className="font-display text-foreground mb-1 text-xl sm:text-2xl">
                    You're in.
                  </h3>
                  <p className="text-muted-foreground text-xs sm:text-sm">
                    Next email arrives the first Monday of the month.
                  </p>
                </motion.div>
              ) : (
                <>
                  <div className="p-5 sm:p-6">
                    <div className="mb-4 flex items-start justify-between gap-3">
                      <div>
                        <p className="font-mono-label text-accent-hi mb-2">
                          // MONTHLY DIGEST
                        </p>
                        <h3 className="font-display text-foreground text-2xl leading-tight sm:text-[1.625rem]">
                          New scripts in your inbox.
                        </h3>
                      </div>
                      <button
                        type="button"
                        onClick={() => setShowForm(false)}
                        className="text-muted-foreground hover:text-foreground -mt-1 -mr-1 rounded-md p-1.5 transition-colors"
                        aria-label="Close"
                      >
                        <X className="h-4 w-4" strokeWidth={1.75} />
                      </button>
                    </div>

                    <p className="text-muted-foreground mb-5 text-sm leading-relaxed">
                      One email a month: new scripts and Microsoft Graph API
                      breakage alerts. No marketing.
                      {subscriberCount !== null && subscriberCount > 0 ? (
                        <>
                          {" "}
                          <span className="text-foreground font-mono text-xs">
                            ({subscriberCount.toLocaleString()} subscribers)
                          </span>
                        </>
                      ) : null}
                    </p>

                    <form onSubmit={handleSubscribe} className="space-y-2.5">
                      <div className="relative">
                        <Mail
                          className="text-muted-foreground absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2"
                          aria-hidden="true"
                        />
                        <input
                          type="email"
                          placeholder="you@company.com"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          required
                          disabled={isSubscribing}
                          className="bg-background text-foreground placeholder:text-muted-foreground focus-visible:border-accent focus-visible:ring-accent w-full rounded-md border py-2.5 pr-3 pl-10 text-sm transition-colors focus-visible:ring-1 focus-visible:outline-none disabled:opacity-60"
                          style={{ borderColor: "var(--brand-rule)" }}
                        />
                      </div>

                      <div className="flex gap-2">
                        <Button
                          type="submit"
                          disabled={isSubscribing}
                          className="ring-accent flex-1 h-10 rounded-md text-sm font-medium focus-visible:ring-2 focus-visible:ring-offset-2"
                        >
                          {isSubscribing ? (
                            <motion.div
                              animate={{ rotate: 360 }}
                              transition={{
                                duration: 1,
                                repeat: Infinity,
                                ease: "linear",
                              }}
                            >
                              <RefreshCw className="h-4 w-4" />
                            </motion.div>
                          ) : (
                            "Subscribe"
                          )}
                        </Button>

                        <Button
                          type="button"
                          variant="outline"
                          onClick={handleDismiss}
                          className="h-10 rounded-md px-4 text-sm"
                        >
                          Later
                        </Button>
                      </div>
                    </form>
                  </div>

                  {/* Trust footer */}
                  <div
                    className="bg-background/40 flex items-center justify-between border-t px-5 py-3 sm:px-6"
                    style={{ borderColor: "var(--brand-rule)" }}
                  >
                    <span className="text-muted-foreground font-mono text-[10px] tracking-widest uppercase">
                      No spam
                    </span>
                    <span className="text-muted-foreground font-mono text-[10px] tracking-widest uppercase">
                      Unsubscribe anytime
                    </span>
                  </div>
                </>
              )}
            </motion.div>
          )}
        </div>
      </motion.div>
    </AnimatePresence>
  );
}
