import type { Metadata } from "next";
import GeneratorClient from "./page-client";
import { env } from "~/env";

export const metadata: Metadata = {
  title: "Script Generator — AI-powered PowerShell for Intune",
  description:
    "Describe what you need in plain English and get a production-quality PowerShell script for Microsoft Intune. Free, no sign-in, copy or download instantly.",
  alternates: { canonical: "/generator" },
  openGraph: {
    title: "Script Generator — AI-powered PowerShell for Intune",
    description:
      "Describe what you need in plain English and get a production-quality PowerShell script for Microsoft Intune.",
    url: "https://intuneautomation.com/generator",
    type: "website",
  },
};

export default function GeneratorPage() {
  return (
    <GeneratorClient
      turnstileSiteKey={env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? null}
    />
  );
}
