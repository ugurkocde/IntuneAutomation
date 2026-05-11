import "~/styles/globals.css";

import { type Metadata } from "next";
import { Geist } from "next/font/google";

import { TRPCReactProvider } from "~/trpc/react";
import { Toaster } from "~/components/ui/toaster";
import { ThemeProvider } from "~/components/theme-provider";
import { SessionProvider } from "~/components/session-provider";
import { WebVitals } from "./_components/web-vitals";

export const metadata: Metadata = {
  title: "IntuneAutomation.com - Automate Intune, one script at a time",
  description:
    "Free PowerShell scripts for Microsoft Intune automation. Streamline device management, reporting, and compliance with ready-to-use detection and remediation scripts.",
  keywords:
    "Microsoft Intune, PowerShell scripts, Intune automation, detection scripts, remediation scripts, device management, MDM, endpoint management, compliance scripts, Windows automation",
  authors: [{ name: "IntuneAutomation.com" }],
  creator: "IntuneAutomation.com",
  publisher: "IntuneAutomation.com",
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
    title: "IntuneAutomation.com - Automate Intune, one script at a time",
    description:
      "Free PowerShell scripts for Microsoft Intune automation. Streamline device management, reporting, and compliance with ready-to-use detection and remediation scripts.",
    url: "https://intuneautomation.com",
    siteName: "IntuneAutomation.com",
    type: "website",
    locale: "en_US",
    images: [
      {
        url: "/og/intuneautomation-og.png",
        width: 1200,
        height: 630,
        alt: "IntuneAutomation.com - Automate Intune, one script at a time",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "IntuneAutomation.com - Automate Intune, one script at a time",
    description:
      "Free PowerShell scripts for Microsoft Intune automation. Streamline device management, reporting, and compliance with ready-to-use detection and remediation scripts.",
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
  icons: [{ rel: "icon", url: "/favicon.ico" }],
};

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
});

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${geist.variable}`} suppressHydrationWarning>
      <head>
        {/* Essential meta tags for mobile and SEO */}
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0078d4" />

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
        <link rel="dns-prefetch" href="https://plausible.io" />
        <link rel="dns-prefetch" href="https://opengraph.b-cdn.net" />
        <link rel="preconnect" href="https://plausible.io" />
        <link rel="dns-prefetch" href="https://api.github.com" />
        <link rel="preconnect" href="https://api.github.com" />
        <link rel="dns-prefetch" href="https://raw.githubusercontent.com" />
        <link rel="preconnect" href="https://raw.githubusercontent.com" />

        {/* Preload critical font */}
        <link
          rel="preload"
          href="https://fonts.gstatic.com/s/geist/v1/0FlxVP2r__VD6kOG4SVEa3Xm.woff2"
          as="font"
          type="font/woff2"
          crossOrigin="anonymous"
        />

        <script
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
            <TRPCReactProvider>{children}</TRPCReactProvider>
            <Toaster />
            <WebVitals />
          </SessionProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
