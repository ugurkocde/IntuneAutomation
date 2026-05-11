"use client";

import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Bell, X, Mail, Sparkles, CheckCircle, RefreshCw } from "lucide-react";
import { Button } from "~/components/ui/button";
import { createClient } from "@supabase/supabase-js";
import { useToast } from "~/hooks/use-toast";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

interface FloatingSubscriptionCTAProps {
  triggerAfterViews?: number;
  triggerAfterScroll?: number;
  triggerAfterTime?: number;
}

export default function FloatingSubscriptionCTA({
  triggerAfterViews = 5,
  triggerAfterScroll = 50,
  triggerAfterTime = 60000, // 60 seconds
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

    // Track script views
    const handleScriptView = () => {
      setViewCount((prev) => {
        const newCount = prev + 1;
        if (newCount >= triggerAfterViews && !isVisible) {
          setIsVisible(true);
        }
        return newCount;
      });
    };

    // Listen for custom script view events
    window.addEventListener("scriptViewed", handleScriptView);

    // Listen for show subscription form event
    const handleShowForm = () => {
      if (!isDismissed) {
        setIsVisible(true);
        setShowForm(true);
      }
    };
    window.addEventListener("showSubscriptionForm", handleShowForm);

    // Track scroll depth
    let hasTriggeredByScroll = false;
    const handleScroll = () => {
      if (hasTriggeredByScroll) return;

      const scrollPercentage =
        (window.scrollY /
          (document.documentElement.scrollHeight - window.innerHeight)) *
        100;

      if (scrollPercentage >= triggerAfterScroll && !isVisible) {
        hasTriggeredByScroll = true;
        setIsVisible(true);
      }
    };

    window.addEventListener("scroll", handleScroll);

    // Exit-intent trigger (when mouse leaves viewport)
    let hasTriggeredByExitIntent = false;
    const handleMouseLeave = (e: MouseEvent) => {
      if (hasTriggeredByExitIntent) return;

      // Only trigger if mouse leaves from top of viewport
      if (e.clientY <= 0 && !isVisible && !isDismissed) {
        hasTriggeredByExitIntent = true;
        setIsVisible(true);
      }
    };

    document.addEventListener("mouseleave", handleMouseLeave);

    // Time-based trigger
    const timer = setTimeout(() => {
      if (!isVisible && !isDismissed) {
        setIsVisible(true);
      }
    }, triggerAfterTime);

    return () => {
      window.removeEventListener("scriptViewed", handleScriptView);
      window.removeEventListener("showSubscriptionForm", handleShowForm);
      window.removeEventListener("scroll", handleScroll);
      document.removeEventListener("mouseleave", handleMouseLeave);
      clearTimeout(timer);
    };
  }, [
    triggerAfterViews,
    triggerAfterScroll,
    triggerAfterTime,
    isVisible,
    isDismissed,
  ]);

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
            // Compact floating button with enhanced design
            <motion.div
              className="group relative cursor-pointer overflow-hidden rounded-full bg-gradient-to-r from-blue-600 via-blue-700 to-purple-700 p-[2px] shadow-2xl"
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => setShowForm(true)}
            >
              {/* Animated background gradient */}
              <div className="animate-gradient-x absolute inset-0 bg-gradient-to-r from-blue-400 via-purple-400 to-blue-400 opacity-0 transition-opacity duration-300 group-hover:opacity-100" />

              <div className="relative flex items-center gap-2 rounded-full bg-gradient-to-r from-blue-600 to-purple-700 px-4 py-2.5 sm:gap-3 sm:px-6 sm:py-3.5">
                {/* Animated bell icon */}
                <motion.div
                  animate={{
                    rotate: [0, -10, 10, -10, 10, 0],
                  }}
                  transition={{
                    duration: 2,
                    repeat: Infinity,
                    repeatDelay: 3,
                  }}
                >
                  <Bell className="h-4 w-4 text-white sm:h-5 sm:w-5" />
                </motion.div>

                <span className="text-xs font-semibold text-white transition-colors group-hover:text-blue-100 sm:text-sm">
                  Get script updates
                </span>

                {/* Sparkles decoration */}
                <Sparkles className="hidden h-3 w-3 animate-pulse text-white/70 sm:block sm:h-4 sm:w-4" />

                <button
                  onClick={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    handleDismiss();
                  }}
                  className="ml-1 cursor-pointer rounded-full bg-white/10 p-1 transition-all duration-200 hover:bg-white/20 sm:ml-2 sm:p-1.5"
                  aria-label="Dismiss"
                >
                  <X className="h-3 w-3 text-white sm:h-3.5 sm:w-3.5" />
                </button>
              </div>
            </motion.div>
          ) : (
            // Expanded form with enhanced design
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              className="relative w-[calc(100vw-2rem)] max-w-[380px] overflow-hidden rounded-2xl border border-gray-200/50 bg-white/95 shadow-2xl backdrop-blur-xl dark:border-gray-700/50 dark:bg-gray-800/95"
            >
              {/* Gradient header */}
              <div className="animate-gradient-x relative h-2 bg-gradient-to-r from-blue-600 via-purple-600 to-blue-600" />

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
                    <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-green-400 to-green-600 sm:mb-4 sm:h-16 sm:w-16">
                      <CheckCircle className="h-6 w-6 text-white sm:h-8 sm:w-8" />
                    </div>
                  </motion.div>

                  <h3 className="mb-1 text-base font-bold text-gray-900 sm:text-lg dark:text-gray-100">
                    You're all set! 🎉
                  </h3>
                </motion.div>
              ) : (
                <>
                  <div className="p-4 pb-3 sm:p-6 sm:pb-4">
                    <div className="mb-3 flex items-center justify-between sm:mb-4">
                      <div className="flex items-center gap-3">
                        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-blue-500 to-purple-600 sm:h-10 sm:w-10">
                          <Mail className="h-4 w-4 text-white sm:h-5 sm:w-5" />
                        </div>
                        <div>
                          <h3 className="text-sm font-bold text-gray-900 sm:text-base dark:text-gray-100">
                            Stay in the loop
                          </h3>
                          <p className="text-[10px] text-gray-500 sm:text-xs dark:text-gray-400">
                            Never miss a new script
                          </p>
                        </div>
                      </div>

                      <button
                        onClick={() => setShowForm(false)}
                        className="cursor-pointer rounded-full p-1.5 transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
                        aria-label="Close"
                      >
                        <X className="h-4 w-4 text-gray-500" />
                      </button>
                    </div>

                    <p className="mb-3 text-xs text-gray-600 sm:mb-4 sm:text-sm dark:text-gray-400">
                      Join{" "}
                      <span className="font-semibold text-gray-900 dark:text-gray-100">
                        {subscriberCount !== null ? `${subscriberCount}+` : "500+"}
                      </span>{" "}
                      IT professionals getting notified about new Intune
                      automation scripts.
                    </p>

                    <form onSubmit={handleSubscribe} className="space-y-3">
                      <div className="relative">
                        <input
                          type="email"
                          placeholder="Enter your email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          required
                          disabled={isSubscribing}
                          className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2.5 pr-10 text-xs text-gray-900 placeholder-gray-400 transition-all duration-200 focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 sm:px-4 sm:py-3 sm:pr-12 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-500"
                        />
                        <Mail className="absolute top-3 right-3 h-3 w-3 text-gray-400 sm:top-3.5 sm:right-4 sm:h-4 sm:w-4" />
                      </div>

                      <div className="flex gap-2">
                        <Button
                          type="submit"
                          size="sm"
                          disabled={isSubscribing}
                          className="flex-1 cursor-pointer bg-gradient-to-r from-blue-600 to-purple-600 py-2 text-xs font-medium text-white transition-all duration-200 hover:from-blue-700 hover:to-purple-700 disabled:cursor-not-allowed sm:py-2.5 sm:text-sm"
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
                          size="sm"
                          variant="outline"
                          onClick={handleDismiss}
                          className="cursor-pointer px-3 text-xs sm:px-4 sm:text-sm"
                        >
                          Later
                        </Button>
                      </div>
                    </form>
                  </div>

                  {/* Trust indicators */}
                  <div className="border-t border-gray-100 bg-gray-50/50 px-4 py-2 sm:px-6 sm:py-3 dark:border-gray-700 dark:bg-gray-900/50">
                    <div className="flex items-center justify-center gap-3 text-[10px] text-gray-500 sm:gap-4 sm:text-xs dark:text-gray-400">
                      <span className="flex items-center gap-1">
                        <CheckCircle className="h-2.5 w-2.5 sm:h-3 sm:w-3" />
                        No spam
                      </span>
                      <span className="flex items-center gap-1">
                        <CheckCircle className="h-2.5 w-2.5 sm:h-3 sm:w-3" />
                        Unsubscribe anytime
                      </span>
                    </div>
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
