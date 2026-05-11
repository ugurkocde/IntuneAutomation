/**
 * Run `build` or `dev` with `SKIP_ENV_VALIDATION` to skip env validation. This is especially useful
 * for Docker builds.
 */
import "./src/env.js";
import createMDX from "@next/mdx";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import rehypeAutolinkHeadings from "rehype-autolink-headings";

/** @type {import("next").NextConfig} */
const config = {
  pageExtensions: ["js", "jsx", "mdx", "ts", "tsx"],
  // Enable static generation for better SEO
  trailingSlash: true,
  images: {
    // Enable Next.js Image Optimization
    unoptimized: false,
    formats: ["image/avif", "image/webp"],
    domains: ["opengraph.b-cdn.net"],
    minimumCacheTTL: 60 * 60 * 24 * 365, // 1 year
  },
  // Enable experimental features for better performance
  experimental: {
    optimizePackageImports: [
      "@radix-ui/react-icons",
      "lucide-react",
      "framer-motion",
    ],
  },
  // Compress output files
  compress: true,
  // Generate source maps only in development
  productionBrowserSourceMaps: false,
  // Add security headers
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          {
            key: "X-DNS-Prefetch-Control",
            value: "on",
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          {
            key: "X-Frame-Options",
            value: "SAMEORIGIN",
          },
          {
            key: "X-XSS-Protection",
            value: "1; mode=block",
          },
        ],
      },
    ];
  },
};

const withMDX = createMDX({
  options: {
    remarkPlugins: [remarkGfm],
    rehypePlugins: [
      rehypeSlug,
    ],
  },
});

export default withMDX(config);
