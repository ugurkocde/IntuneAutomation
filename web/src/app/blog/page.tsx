import { type Metadata } from "next";
import {
  BlogCollectionSchema,
  BreadcrumbSchema,
} from "~/components/structured-data";
import { getAllPosts } from "~/lib/blog";
import BlogPageClient from "./page-client";

const BASE_URL = "https://intuneautomation.com";

export const metadata: Metadata = {
  // Short title — root layout's title template appends "| IntuneAutomation".
  title: "Blog",
  description:
    "Learn Microsoft Intune automation with our comprehensive guides, tutorials, and best practices for PowerShell scripting and device management.",
  alternates: { canonical: "/blog/" },
  openGraph: {
    title: "Blog | IntuneAutomation",
    description:
      "Guides, tutorials, and best practices for Microsoft Intune automation.",
    url: `${BASE_URL}/blog/`,
    type: "website",
    siteName: "IntuneAutomation",
  },
  twitter: {
    card: "summary_large_image",
    title: "Blog | IntuneAutomation",
    description:
      "Guides, tutorials, and best practices for Microsoft Intune automation.",
  },
};

export default async function BlogPage() {
  const posts = await getAllPosts();
  return (
    <>
      <BreadcrumbSchema
        baseUrl={BASE_URL}
        items={[
          { name: "Home", url: "/" },
          { name: "Blog", url: "/blog/" },
        ]}
      />
      <BlogCollectionSchema baseUrl={BASE_URL} posts={posts} />
      <BlogPageClient />
    </>
  );
}
