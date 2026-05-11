"use client";

// Blog index — reskinned to the v4 design system.
// Vocabulary: mono kicker + display headline opener, hairline-bordered manifest
// list (one row per post, numbered, display-headline title, mono metadata strip,
// ArrowUpRight affordance on hover). No gradient backgrounds. No rounded-2xl/3xl.
// Surface: plain page background; rows hover into bg-card/60 fill.

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { type BlogPost } from "~/lib/blog";

function formatDateMono(dateString: string): string {
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "short",
    day: "2-digit",
  })
    .format(date)
    .toUpperCase();
}

export default function BlogPageClient() {
  const [posts, setPosts] = useState<BlogPost[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchPosts() {
      try {
        const response = await fetch("/api/blog/posts");
        if (response.ok) {
          const data = (await response.json()) as BlogPost[];
          setPosts(data);
        }
      } catch (error) {
        console.error("Failed to fetch blog posts:", error);
      } finally {
        setLoading(false);
      }
    }
    void fetchPosts();
  }, []);

  const kicker = loading
    ? "// BLOG"
    : posts.length > 0
      ? `// BLOG · ${posts.length} POST${posts.length === 1 ? "" : "S"}`
      : "// BLOG";

  return (
    <ScriptsProvider>
      <div className="flex min-h-screen flex-col bg-background">
        <Navbar />
        <main className="flex-1 pt-20">
          <section
            aria-labelledby="blog-index-heading"
            className="px-4 py-20 sm:py-24"
          >
            <div className="mx-auto max-w-4xl">
              {/* Header — mono kicker + display headline + lead */}
              <header className="mb-14 sm:mb-16">
                <p className="font-mono-label text-accent-hi mb-4">{kicker}</p>
                <h1
                  id="blog-index-heading"
                  className="font-display text-foreground mb-4 text-4xl leading-[1.05] tracking-[-0.02em] sm:text-5xl md:text-6xl"
                >
                  Notes from the library.
                </h1>
                <p className="text-muted-foreground max-w-xl text-base leading-relaxed sm:text-lg">
                  Writing about Microsoft Intune automation — guides,
                  tutorials, and the technical choices behind the scripts.
                </p>
              </header>

              {/* Body */}
              {loading ? (
                <SkeletonList />
              ) : posts.length === 0 ? (
                <EmptyState />
              ) : (
                <PostManifest posts={posts} />
              )}
            </div>
          </section>
        </main>
        <Footer />
        <SearchDialog />
      </div>
    </ScriptsProvider>
  );
}

/* -------------------------------------------------------------------------- */
/*  Post manifest — hairline-bordered list of post rows.                       */
/* -------------------------------------------------------------------------- */

function PostManifest({ posts }: { posts: BlogPost[] }) {
  return (
    <ul className="border-b" style={{ borderColor: "var(--brand-rule)" }}>
      {posts.map((post, index) => {
        const num = String(index + 1).padStart(2, "0");
        const date = formatDateMono(post.date);

        return (
          <li
            key={post.slug}
            className="group/row border-t transition-colors duration-200 hover:bg-card/60"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            <Link
              href={`/blog/${post.slug}/`}
              className="flex items-baseline gap-5 px-2 py-7 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-2 focus-visible:ring-offset-background sm:gap-8"
              aria-label={`Read ${post.title}`}
            >
              {/* Index marker */}
              <span
                aria-hidden="true"
                className="font-mono text-accent-hi w-10 shrink-0 text-xs tracking-widest sm:w-12 sm:text-sm"
              >
                {num}
              </span>

              {/* Title + excerpt + metadata */}
              <div className="min-w-0 flex-1">
                <h2 className="font-display text-foreground group-hover/row:text-accent-hi text-xl leading-snug transition-colors sm:text-2xl">
                  {post.title}
                </h2>

                {post.description && (
                  <p className="text-muted-foreground mt-2 line-clamp-2 text-sm leading-relaxed sm:text-base">
                    {post.description}
                  </p>
                )}

                <p className="text-muted-foreground/90 mt-3 font-mono text-[11px] tracking-[0.14em] uppercase">
                  <span>{date}</span>
                  {post.author && (
                    <>
                      <span aria-hidden="true" className="px-2 opacity-50">
                        ·
                      </span>
                      <span>{post.author}</span>
                    </>
                  )}
                  {post.category && (
                    <>
                      <span aria-hidden="true" className="px-2 opacity-50">
                        ·
                      </span>
                      <span>{post.category}</span>
                    </>
                  )}
                </p>
              </div>

              {/* Affordance */}
              <ArrowUpRight
                className="text-muted-foreground group-hover/row:text-accent-hi h-4 w-4 shrink-0 transition-all group-hover/row:-translate-y-0.5 group-hover/row:translate-x-0.5"
                aria-hidden="true"
              />
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

/* -------------------------------------------------------------------------- */
/*  Skeleton — uses the same manifest geometry so layout doesn't shift.        */
/* -------------------------------------------------------------------------- */

function SkeletonList() {
  return (
    <ul
      className="border-b animate-pulse"
      style={{ borderColor: "var(--brand-rule)" }}
      aria-hidden="true"
    >
      {[0, 1, 2].map((i) => (
        <li
          key={i}
          className="border-t"
          style={{ borderColor: "var(--brand-rule)" }}
        >
          <div className="flex items-baseline gap-5 px-2 py-7 sm:gap-8">
            <span className="w-10 shrink-0 sm:w-12">
              <span className="block h-3 w-6 rounded bg-muted" />
            </span>
            <div className="min-w-0 flex-1 space-y-3">
              <span className="block h-6 w-3/4 rounded bg-muted" />
              <span className="block h-4 w-full rounded bg-muted" />
              <span className="block h-3 w-1/3 rounded bg-muted" />
            </div>
            <span className="block h-4 w-4 shrink-0 rounded bg-muted" />
          </div>
        </li>
      ))}
    </ul>
  );
}

/* -------------------------------------------------------------------------- */
/*  Empty state.                                                              */
/* -------------------------------------------------------------------------- */

function EmptyState() {
  return (
    <div
      className="rounded-md border bg-card/40 px-6 py-16 text-center backdrop-blur-md"
      style={{ borderColor: "var(--brand-rule)" }}
    >
      <p className="font-mono-label text-accent-hi mb-3">// NO POSTS YET</p>
      <p className="text-muted-foreground text-sm sm:text-base">
        Nothing published yet. Check back soon.
      </p>
    </div>
  );
}
