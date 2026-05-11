import { type Metadata } from "next";
import BlogPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Blog - IntuneAutomation.com",
  description: "Learn Microsoft Intune automation with our comprehensive guides, tutorials, and best practices for PowerShell scripting and device management.",
  openGraph: {
    title: "Blog - IntuneAutomation.com",
    description: "Learn Microsoft Intune automation with our comprehensive guides and tutorials.",
    type: "website",
  },
};

export default function BlogPage() {
  return <BlogPageClient />;
}