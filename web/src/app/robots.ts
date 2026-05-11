import { type MetadataRoute } from "next";

// Explicitly allow major AI/search crawlers so generative engines
// (ChatGPT, Claude, Perplexity, Gemini, Apple Intelligence) can index
// and cite content from this site.
const AI_AND_SEARCH_BOTS = [
  "GPTBot",
  "ChatGPT-User",
  "OAI-SearchBot",
  "Google-Extended",
  "Googlebot",
  "GoogleOther",
  "ClaudeBot",
  "Claude-Web",
  "anthropic-ai",
  "PerplexityBot",
  "Perplexity-User",
  "Applebot",
  "Applebot-Extended",
  "Bingbot",
  "DuckDuckBot",
  "CCBot",
  "Bytespider",
  "Amazonbot",
  "YouBot",
  "PhindBot",
  "DiffBot",
  "FacebookBot",
  "facebookexternalhit",
  "LinkedInBot",
  "Twitterbot",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: ["/api/", "/_next/"],
      },
      ...AI_AND_SEARCH_BOTS.map((userAgent) => ({
        userAgent,
        allow: "/",
        disallow: ["/api/"],
      })),
    ],
    sitemap: "https://intuneautomation.com/sitemap.xml",
    host: "https://intuneautomation.com",
  };
}
