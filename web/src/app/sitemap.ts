import { type MetadataRoute } from "next";
import { githubService } from "~/lib/github";
import { getAllPosts } from "~/lib/blog";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const baseUrl = "https://intuneautomation.com";

  // Static pages
  const staticPages = [
    {
      url: baseUrl,
      lastModified: new Date(),
      changeFrequency: "daily" as const,
      priority: 1,
    },
    {
      url: `${baseUrl}/blog`,
      lastModified: new Date(),
      changeFrequency: "weekly" as const,
      priority: 0.9,
    },
  ];

  try {
    // Dynamic script pages
    const scripts = await githubService.fetchAllScripts();
    const scriptPages = scripts.map((script) => ({
      url: `${baseUrl}/script/${script.slug}`,
      lastModified: script.lastUpdated
        ? new Date(script.lastUpdated)
        : new Date(),
      changeFrequency: "weekly" as const,
      priority: 0.8,
    }));

    // Blog posts
    const posts = await getAllPosts();
    const blogPages = posts.map((post) => ({
      url: `${baseUrl}/blog/${post.slug}`,
      lastModified: new Date(),
      changeFrequency: "monthly" as const,
      priority: 0.7,
    }));

    return [...staticPages, ...scriptPages, ...blogPages];
  } catch (error) {
    console.error("Error generating sitemap:", error);
    // Return just static pages if script fetching fails
    return staticPages;
  }
}
