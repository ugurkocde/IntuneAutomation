import type { Metadata } from "next";
import UnsubscribeClient from "./page-client";

export const metadata: Metadata = {
  title: "Unsubscribe",
  description: "Manage your IntuneAutomation newsletter subscription.",
  // Token-bearing utility page — should not appear in search results.
  robots: {
    index: false,
    follow: false,
    googleBot: {
      index: false,
      follow: false,
    },
  },
};

export default function UnsubscribePage() {
  return <UnsubscribeClient />;
}
