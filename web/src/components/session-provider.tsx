"use client";

import { useEffect } from "react";

export function SessionProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    // Generate session ID if it doesn't exist
    if (
      typeof window !== "undefined" &&
      !sessionStorage.getItem("session_id")
    ) {
      const sessionId = crypto.randomUUID();
      sessionStorage.setItem("session_id", sessionId);
    }
  }, []);

  return <>{children}</>;
}
