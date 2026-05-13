"use client";

// Blog post — reskinned to the v4 design system.
// Vocabulary: mono breadcrumb, mono category kicker, big display headline,
// dek in muted-foreground, mono metadata strip with hairline rule beneath,
// max-w-prose body, manifest-pattern related-posts list. No gradient hero.
// MDX prose styling lives in mdx-components.tsx (single source of truth).

import { useEffect, useState } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { MDXRemote, type MDXRemoteSerializeResult } from "next-mdx-remote";
import { serialize } from "next-mdx-remote/serialize";
import { ArrowLeft, ArrowUpRight } from "lucide-react";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { useMDXComponents } from "../../../../mdx-components";
import { type BlogPostWithContent, type BlogPost } from "~/lib/blog";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";

interface BlogPostClientProps {
  slug: string;
}

function formatDateLong(dateString: string): string {
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

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

// Article structured data — preserved verbatim from prior implementation.
// JSON.stringify output is safe to inline into a <script type="application/ld+json"> tag.
function ArticleStructuredData({ post }: { post: BlogPostWithContent }) {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.description,
    author: {
      "@type": "Person",
      name: post.author,
    },
    datePublished: new Date(post.date).toISOString(),
    dateModified: new Date(post.date).toISOString(),
    mainEntityOfPage: {
      "@type": "WebPage",
      "@id": `https://intuneautomation.com/blog/${post.slug}/`,
    },
    publisher: {
      "@type": "Organization",
      name: "IntuneAutomation.com",
      logo: {
        "@type": "ImageObject",
        url: "https://intuneautomation.com/logo.png",
      },
    },
    ...(post.image && {
      image: {
        "@type": "ImageObject",
        url: post.image,
      },
    }),
    keywords: post.tags.join(", "),
  };

  return (
    <script
      type="application/ld+json"
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(structuredData),
      }}
    />
  );
}

export default function BlogPostClient({ slug }: BlogPostClientProps) {
  const [post, setPost] = useState<BlogPostWithContent | null>(null);
  const [relatedPosts, setRelatedPosts] = useState<BlogPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [mdxSource, setMdxSource] = useState<MDXRemoteSerializeResult | null>(
    null,
  );
  const components = useMDXComponents({});

  useEffect(() => {
    async function fetchPost() {
      try {
        const [postResponse, relatedResponse] = await Promise.all([
          fetch(`/api/blog/posts/${slug}`),
          fetch(`/api/blog/posts/${slug}/related`),
        ]);

        if (!postResponse.ok) {
          notFound();
        }

        const postData = (await postResponse.json()) as BlogPostWithContent;
        const relatedData = (await relatedResponse.json()) as BlogPost[];

        setPost(postData);
        setRelatedPosts(relatedData);

        // Serialize MDX content — same plugin set as before.
        const serialized = await serialize(postData.content, {
          mdxOptions: {
            remarkPlugins: [remarkGfm],
            rehypePlugins: [rehypeSlug],
          },
        });
        setMdxSource(serialized);
      } catch (error) {
        console.error("Failed to fetch blog post:", error);
      } finally {
        setLoading(false);
      }
    }
    void fetchPost();
  }, [slug]);

  if (loading) {
    return (
      <ScriptsProvider>
        <div className="bg-background flex min-h-screen flex-col">
          <Navbar />
          <main className="flex-1 pt-20">
            <article className="px-4 py-16 sm:py-20">
              <div className="mx-auto max-w-4xl">
                <div className="animate-pulse" aria-hidden="true">
                  <div className="bg-muted mb-10 h-3 w-32 rounded" />
                  <div className="bg-muted mb-6 h-3 w-24 rounded" />
                  <div className="bg-muted mb-4 h-12 w-3/4 rounded" />
                  <div className="bg-muted mb-8 h-6 w-full rounded" />
                  <div className="bg-muted mb-10 h-3 w-1/2 rounded" />
                  <div className="space-y-4">
                    {[0, 1, 2, 3, 4].map((i) => (
                      <div key={i} className="bg-muted h-4 w-full rounded" />
                    ))}
                  </div>
                </div>
              </div>
            </article>
          </main>
          <Footer />
          <SearchDialog />
        </div>
      </ScriptsProvider>
    );
  }

  if (!post || !mdxSource) {
    notFound();
  }

  const categoryKicker = post.category
    ? `// ${post.category.toUpperCase()}`
    : "// BLOG";

  return (
    <ScriptsProvider>
      <div className="bg-background flex min-h-screen flex-col">
        <Navbar />
        <main className="flex-1 pt-20">
          <ArticleStructuredData post={post} />

          <article className="px-4 py-16 sm:py-20">
            <div className="mx-auto max-w-4xl">
              {/* Breadcrumb */}
              <Link
                href="/blog/"
                className="group text-muted-foreground hover:text-accent-hi focus-visible:ring-offset-background mb-12 inline-flex items-center gap-2 font-mono text-[11px] tracking-[0.14em] uppercase transition-colors focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-2 focus-visible:outline-none"
              >
                <ArrowLeft
                  className="h-3.5 w-3.5 transition-transform group-hover:-translate-x-0.5"
                  aria-hidden="true"
                />
                All posts
              </Link>

              {/* Header */}
              <header
                className="mb-12 border-b pb-10 sm:mb-14 sm:pb-12"
                style={{ borderColor: "var(--brand-rule)" }}
              >
                <p className="font-mono-label text-accent-hi mb-5">
                  {categoryKicker}
                </p>
                <h1 className="font-display text-foreground mb-6 text-4xl leading-[1.05] tracking-[-0.02em] sm:text-5xl md:text-6xl">
                  {post.title}
                </h1>
                {post.description && (
                  <p className="text-muted-foreground max-w-2xl text-lg leading-relaxed sm:text-xl">
                    {post.description}
                  </p>
                )}

                {/* Metadata strip */}
                <div className="text-muted-foreground/90 mt-8 flex flex-wrap items-center gap-x-1 gap-y-2 font-mono text-[11px] tracking-[0.14em] uppercase">
                  <time dateTime={new Date(post.date).toISOString()}>
                    {formatDateMono(post.date)}
                  </time>
                  {post.author && (
                    <>
                      <span aria-hidden="true" className="px-2 opacity-50">
                        ·
                      </span>
                      <span>{post.author}</span>
                    </>
                  )}
                  {post.readingTime && (
                    <>
                      <span aria-hidden="true" className="px-2 opacity-50">
                        ·
                      </span>
                      <span>{post.readingTime}</span>
                    </>
                  )}
                </div>
              </header>

              {/* Body — constrained reading width, MDX provides prose styling */}
              <div className="mx-auto max-w-prose">
                <MDXRemote {...mdxSource} components={components} />
              </div>

              {/* Tag strip (if present) */}
              {post.tags && post.tags.length > 0 && (
                <div
                  className="mx-auto mt-16 max-w-prose border-t pt-8"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <p className="font-mono-label text-accent-hi mb-4">// TAGS</p>
                  <ul className="flex flex-wrap gap-2">
                    {post.tags.map((tag) => (
                      <li key={tag}>
                        <span
                          className="text-muted-foreground inline-block rounded-md border px-2.5 py-1 font-mono text-[10.5px] tracking-[0.14em] uppercase"
                          style={{ borderColor: "var(--brand-rule)" }}
                        >
                          {tag}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {/* Author footer */}
              {post.author && (
                <footer
                  className="mx-auto mt-12 max-w-prose border-t pt-8"
                  style={{ borderColor: "var(--brand-rule)" }}
                >
                  <p className="font-mono-label text-accent-hi mb-3">
                    // ABOUT THE AUTHOR
                  </p>
                  <p className="text-foreground text-base">
                    Written by{" "}
                    <span className="font-medium">{post.author}</span>
                    {post.date && (
                      <span className="text-muted-foreground">
                        {" "}
                        on{" "}
                        <time dateTime={new Date(post.date).toISOString()}>
                          {formatDateLong(post.date)}
                        </time>
                      </span>
                    )}
                    .
                  </p>
                </footer>
              )}

              {/* Related posts */}
              {relatedPosts.length > 0 && (
                <section
                  aria-labelledby="related-heading"
                  className="mt-20 sm:mt-24"
                >
                  <p className="font-mono-label text-accent-hi mb-4">
                    // RELATED POSTS
                  </p>
                  <h2
                    id="related-heading"
                    className="font-display text-foreground mb-10 text-2xl leading-[1.05] sm:text-3xl"
                  >
                    Keep reading.
                  </h2>

                  <ul
                    className="border-b"
                    style={{ borderColor: "var(--brand-rule)" }}
                  >
                    {relatedPosts.map((relatedPost, index) => {
                      const num = String(index + 1).padStart(2, "0");
                      return (
                        <li
                          key={relatedPost.slug}
                          className="group/row hover:bg-card/60 border-t transition-colors duration-200"
                          style={{ borderColor: "var(--brand-rule)" }}
                        >
                          <Link
                            href={`/blog/${relatedPost.slug}/`}
                            className="focus-visible:ring-offset-background flex items-baseline gap-5 px-2 py-6 focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-2 focus-visible:outline-none sm:gap-8"
                            aria-label={`Read ${relatedPost.title}`}
                          >
                            <span
                              aria-hidden="true"
                              className="text-accent-hi w-10 shrink-0 font-mono text-xs tracking-widest sm:w-12 sm:text-sm"
                            >
                              {num}
                            </span>
                            <div className="min-w-0 flex-1">
                              <p className="font-display text-foreground group-hover/row:text-accent-hi text-lg leading-snug transition-colors sm:text-xl">
                                {relatedPost.title}
                              </p>
                              {relatedPost.description && (
                                <p className="text-muted-foreground mt-1.5 line-clamp-1 text-sm">
                                  {relatedPost.description}
                                </p>
                              )}
                            </div>
                            <ArrowUpRight
                              className="text-muted-foreground group-hover/row:text-accent-hi h-4 w-4 shrink-0 transition-all group-hover/row:translate-x-0.5 group-hover/row:-translate-y-0.5"
                              aria-hidden="true"
                            />
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                </section>
              )}
            </div>
          </article>
        </main>
        <Footer />
        <SearchDialog />
      </div>
    </ScriptsProvider>
  );
}
