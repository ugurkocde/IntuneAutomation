/**
 * Run `build` or `dev` with `SKIP_ENV_VALIDATION` to skip env validation. This is especially useful
 * for Docker builds.
 */
import "./src/env.js";
import createMDX from "@next/mdx";

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

// Plugins are named as strings, not imported function references: Turbopack has
// to serialize the loader options, and a function reference is not serializable.
const withMDX = createMDX({
  options: {
    remarkPlugins: [["remark-gfm", {}]],
    rehypePlugins: [["rehype-slug", {}]],
  },
});

export default withMDX(config);
