import { type MetadataRoute } from "next";
import { githubService } from "~/lib/github";
import { getAllPosts } from "~/lib/blog";

// Static fallback date — bump manually when home/blog index content meaningfully
// changes so crawlers don't get spurious "everything updated" signals on every
// deploy. Per-script/per-post pages still use their own lastUpdated dates.
const STATIC_LAST_MODIFIED = new Date("2026-05-19");

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const baseUrl = "https://intuneautomation.com";

  // Static pages
  const staticPages: MetadataRoute.Sitemap = [
    {
      url: `${baseUrl}/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "daily",
      priority: 1,
    },
    {
      url: `${baseUrl}/scripts/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "daily",
      priority: 0.95,
    },
    {
      url: `${baseUrl}/intune-scripts/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "weekly",
      priority: 0.95,
    },
    {
      url: `${baseUrl}/blog/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "weekly",
      priority: 0.9,
    },
    {
      url: `${baseUrl}/generator/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "weekly",
      priority: 0.9,
    },
    {
      url: `${baseUrl}/terms/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "yearly",
      priority: 0.2,
    },
    {
      url: `${baseUrl}/privacy/`,
      lastModified: STATIC_LAST_MODIFIED,
      changeFrequency: "yearly",
      priority: 0.2,
    },
  ];

  try {
    // Dynamic script pages
    const scripts = await githubService.fetchAllScripts();
    const scriptPages: MetadataRoute.Sitemap = scripts.map((script) => ({
      url: `${baseUrl}/script/${script.slug}/`,
      lastModified: script.lastUpdated
        ? new Date(script.lastUpdated)
        : STATIC_LAST_MODIFIED,
      changeFrequency: "weekly",
      priority: 0.8,
    }));

    // Blog posts — lastUpdated resolves frontmatter → file mtime → publish date
    // in src/lib/blog.ts, so this surfaces real freshness to search and AI
    // engines instead of pinning every post to the deploy date.
    const posts = await getAllPosts();
    const blogPages: MetadataRoute.Sitemap = posts.map((post) => ({
      url: `${baseUrl}/blog/${post.slug}/`,
      lastModified: new Date(post.lastUpdated),
      changeFrequency: "monthly",
      priority: 0.7,
    }));

    return [...staticPages, ...scriptPages, ...blogPages];
  } catch (error) {
    console.error("Error generating sitemap:", error);
    // Return just static pages if script fetching fails
    return staticPages;
  }
}
