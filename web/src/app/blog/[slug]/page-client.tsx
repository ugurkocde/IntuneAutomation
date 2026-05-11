"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { MDXRemote } from "next-mdx-remote";
import { serialize } from "next-mdx-remote/serialize";
import { CalendarIcon, ClockIcon, UserIcon, ArrowLeftIcon } from "lucide-react";
import { Badge } from "~/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "~/components/ui/card";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { useMDXComponents } from "../../../../mdx-components";
import { type BlogPostWithContent, type BlogPost } from "~/lib/blog";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import rehypeAutolinkHeadings from "rehype-autolink-headings";

interface BlogPostClientProps {
  slug: string;
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

// Article structured data component
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
  const [mdxSource, setMdxSource] = useState<any>(null);
  const components = useMDXComponents({});

  useEffect(() => {
    async function fetchPost() {
      try {
        const [postResponse, relatedResponse] = await Promise.all([
          fetch(`/api/blog/posts/${slug}`),
          fetch(`/api/blog/posts/${slug}/related`)
        ]);

        if (!postResponse.ok) {
          notFound();
        }

        const postData = await postResponse.json();
        const relatedData = await relatedResponse.json();

        setPost(postData);
        setRelatedPosts(relatedData);

        // Serialize MDX content
        const serialized = await serialize(postData.content, {
          mdxOptions: {
            remarkPlugins: [remarkGfm],
            rehypePlugins: [
              rehypeSlug,
            ],
          },
        });
        setMdxSource(serialized);
      } catch (error) {
        console.error("Failed to fetch blog post:", error);
      } finally {
        setLoading(false);
      }
    }
    fetchPost();
  }, [slug]);

  if (loading) {
    return (
      <ScriptsProvider>
        <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
          <Navbar />
          <main className="flex-1 pt-20">
            <article className="container mx-auto px-4 py-12">
              <div className="mx-auto max-w-4xl">
                <div className="animate-pulse">
                  <div className="h-4 w-24 bg-muted rounded mb-8" />
                  <div className="h-10 w-3/4 bg-muted rounded mb-4" />
                  <div className="h-6 w-full bg-muted rounded mb-4" />
                  <div className="h-4 w-1/2 bg-muted rounded mb-8" />
                  <div className="space-y-4">
                    {[...Array(5)].map((_, i) => (
                      <div key={i} className="h-4 w-full bg-muted rounded" />
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

  return (
    <ScriptsProvider>
      <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
        <Navbar />
        <main className="flex-1 pt-20">
          <ArticleStructuredData post={post} />
          <article className="container mx-auto px-4 py-12">
            <div className="mx-auto max-w-4xl">
              {/* Back to blog link */}
              <Link
                href="/blog/"
                className="mb-8 inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                <ArrowLeftIcon className="h-4 w-4" />
                Back to Blog
              </Link>

              {/* Article header */}
              <header className="mb-8 space-y-4">
                <h1 className="text-4xl font-bold tracking-tight lg:text-5xl">
                  {post.title}
                </h1>
                <p className="text-xl text-muted-foreground">{post.description}</p>
              </header>

              {/* Article content */}
              <div className="prose prose-gray dark:prose-invert max-w-none">
                <MDXRemote {...mdxSource} components={components} />
              </div>

              {/* Related posts */}
              {relatedPosts.length > 0 && (
                <div className="mt-12 border-t pt-12">
                  <h2 className="mb-6 text-2xl font-bold">Related Articles</h2>
                  <div className="grid gap-6 md:grid-cols-3">
                    {relatedPosts.map((relatedPost) => (
                      <Card key={relatedPost.slug}>
                        <CardHeader>
                          <Link href={`/blog/${relatedPost.slug}/`}>
                            <CardTitle className="text-lg hover:text-primary transition-colors">
                              {relatedPost.title}
                            </CardTitle>
                          </Link>
                        </CardHeader>
                        <CardContent>
                          <p className="text-sm text-muted-foreground line-clamp-2">
                            {relatedPost.description}
                          </p>
                        </CardContent>
                      </Card>
                    ))}
                  </div>
                </div>
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