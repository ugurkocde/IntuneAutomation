"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { CalendarIcon, ClockIcon, TagIcon, UserIcon } from "lucide-react";
import { Badge } from "~/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "~/components/ui/card";
import Navbar from "~/components/navbar";
import Footer from "~/components/footer";
import { ScriptsProvider } from "~/components/scripts-provider";
import SearchDialog from "~/components/search-dialog";
import { type BlogPost } from "~/lib/blog";

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

export default function BlogPageClient() {
  const [posts, setPosts] = useState<BlogPost[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchPosts() {
      try {
        const response = await fetch("/api/blog/posts");
        if (response.ok) {
          const data = await response.json();
          setPosts(data);
        }
      } catch (error) {
        console.error("Failed to fetch blog posts:", error);
      } finally {
        setLoading(false);
      }
    }
    fetchPosts();
  }, []);

  return (
    <ScriptsProvider>
      <div className="from-background to-background/80 flex min-h-screen flex-col bg-gradient-to-b">
        <Navbar />
        <main className="flex-1 pt-20">
          <div className="container mx-auto px-4 py-12">
            <div className="mx-auto max-w-4xl">
              <div className="mb-8">
                <h1 className="text-4xl font-bold tracking-tight">Blog</h1>
                <p className="mt-4 text-lg text-muted-foreground">
                  Learn Microsoft Intune automation with our comprehensive guides,
                  tutorials, and best practices.
                </p>
              </div>

              {loading ? (
                <div className="space-y-8">
                  {[...Array(3)].map((_, i) => (
                    <Card key={i} className="animate-pulse">
                      <CardHeader>
                        <div className="h-6 w-3/4 bg-muted rounded" />
                        <div className="h-4 w-full bg-muted rounded mt-2" />
                      </CardHeader>
                      <CardContent>
                        <div className="h-4 w-1/2 bg-muted rounded" />
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : posts.length === 0 ? (
                <Card>
                  <CardContent className="flex flex-col items-center justify-center py-12 text-center">
                    <p className="text-lg text-muted-foreground">
                      No blog posts available yet. Check back soon!
                    </p>
                  </CardContent>
                </Card>
              ) : (
                <div className="space-y-8">
                  {posts.map((post) => (
                    <Card key={post.slug} className="transition-shadow hover:shadow-lg">
                      <CardHeader>
                        <Link href={`/blog/${post.slug}/`}>
                          <CardTitle className="text-2xl hover:text-primary transition-colors">
                            {post.title}
                          </CardTitle>
                        </Link>
                        <CardDescription className="text-base mt-2">
                          {post.description}
                        </CardDescription>
                      </CardHeader>
                    </Card>
                  ))}
                </div>
              )}
            </div>
          </div>
        </main>
        <Footer />
        <SearchDialog />
      </div>
    </ScriptsProvider>
  );
}