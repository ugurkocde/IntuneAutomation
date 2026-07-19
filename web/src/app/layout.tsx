import "~/styles/globals.css";

import { type Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";

import { TRPCReactProvider } from "~/trpc/react";
import { AnnouncementBanner } from "~/components/announcement-banner";
import { Toaster } from "~/components/ui/toaster";
import { ThemeProvider } from "~/components/theme-provider";
import { SessionProvider } from "~/components/session-provider";
import { WebVitals } from "./_components/web-vitals";

const SITE_NAME = "IntuneAutomation";
const SITE_DESCRIPTION =
  "Open-source PowerShell scripts for Microsoft Intune. Copy them or one-click deploy to Azure Automation as scheduled runbooks.";

export const metadata: Metadata = {
  title: {
    default: "IntuneAutomation — PowerShell scripts for Microsoft Intune",
    template: "%s | IntuneAutomation",
  },
  applicationName: SITE_NAME,
  description: SITE_DESCRIPTION,
  keywords: [
    "Microsoft Intune",
    "PowerShell scripts",
    "Intune automation",
    "Azure Automation runbooks",
    "Microsoft Graph PowerShell",
    "detection scripts",
    "remediation scripts",
    "endpoint management",
    "mobile device management",
    "compliance reporting",
  ],
  authors: [
    { name: "Ugur Koc", url: "https://www.linkedin.com/in/ugurkocde/" },
  ],
  creator: "Ugur Koc",
  publisher: SITE_NAME,
  category: "DevOps",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  metadataBase: new URL("https://intuneautomation.com"),
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "IntuneAutomation — PowerShell scripts for Microsoft Intune",
    description: SITE_DESCRIPTION,
    url: "https://intuneautomation.com",
    siteName: SITE_NAME,
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og/intuneautomation-og.png",
        width: 1200,
        height: 630,
        alt: "IntuneAutomation — open-source PowerShell scripts for Microsoft Intune",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "IntuneAutomation — PowerShell scripts for Microsoft Intune",
    description: SITE_DESCRIPTION,
    creator: "@intuneautomation",
    images: ["/og/intuneautomation-og.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/icon-192.png", type: "image/png", sizes: "192x192" },
      { url: "/icon-512.png", type: "image/png", sizes: "512x512" },
    ],
    shortcut: "/favicon.ico",
    apple: "/apple-touch-icon.png",
  },
};

// Two-voice type system, same family:
//   Geist        — body, headlines, UI. Distinctive at display sizes with
//                  tight tracking + medium weight.
//   Geist Mono   — labels, code, stats.
// One designer, one design — coherent and simple.
const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
  display: "swap",
});

const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
  display: "swap",
});

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${geist.variable} ${geistMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        {/* Essential meta tags for mobile and SEO */}
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        {/* Theme-color matches the dark/light --background tokens in globals.css. */}
        <meta
          name="theme-color"
          content="#0c1326"
          media="(prefers-color-scheme: dark)"
        />
        <meta
          name="theme-color"
          content="#f7f5ee"
          media="(prefers-color-scheme: light)"
        />

        {/* PWA meta tags */}
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="default" />
        <meta name="apple-mobile-web-app-title" content="IntuneAutomation" />
        <meta name="mobile-web-app-capable" content="yes" />

        {/* Icons and manifest */}
        <link rel="manifest" href="/manifest.json" />
        <link rel="icon" type="image/x-icon" href="/favicon.ico" />

        {/* Resource hints for performance */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        {/* Resource hints — preconnect implies dns-prefetch, so we use preconnect
            alone for hosts we'll definitely contact (no need to duplicate). */}
        <link rel="preconnect" href="https://plausible.io" />
        <link rel="preconnect" href="https://api.github.com" />
        <link rel="preconnect" href="https://raw.githubusercontent.com" />
        <link rel="dns-prefetch" href="https://opengraph.b-cdn.net" />

        {/* Geist font is self-hosted via next/font with its own preload tags */}

        <script
          async
          defer
          data-domain="intuneautomation.com"
          src="https://plausible.io/js/script.file-downloads.outbound-links.tagged-events.js"
        />
      </head>
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <SessionProvider>
            <AnnouncementBanner />
            <TRPCReactProvider>{children}</TRPCReactProvider>
            <Toaster />
            <WebVitals />
          </SessionProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
