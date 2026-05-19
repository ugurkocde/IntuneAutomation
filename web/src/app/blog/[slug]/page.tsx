import { type Metadata } from "next";
import { notFound } from "next/navigation";
import {
  BlogPostingSchema,
  BreadcrumbSchema,
} from "~/components/structured-data";
import { getAllPosts, getPostBySlug } from "~/lib/blog";
import BlogPostClient from "./page-client";

const BASE_URL = "https://intuneautomation.com";

interface BlogPostPageProps {
  params: Promise<{ slug: string }>;
}

export async function generateStaticParams() {
  const posts = await getAllPosts();
  return posts.map((post) => ({
    slug: post.slug,
  }));
}

export async function generateMetadata({
  params,
}: BlogPostPageProps): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPostBySlug(slug);

  if (!post) {
    return {
      title: "Post Not Found",
      robots: { index: false, follow: false },
    };
  }

  const publishedTime = new Date(post.date).toISOString();
  const modifiedTime = new Date(post.lastUpdated).toISOString();
  const url = `${BASE_URL}/blog/${slug}/`;

  return {
    // Short title — root layout's title template appends "| IntuneAutomation".
    title: post.title,
    description: post.description,
    authors: [{ name: post.author }],
    alternates: { canonical: `/blog/${slug}/` },
    openGraph: {
      title: post.title,
      description: post.description,
      type: "article",
      url,
      siteName: "IntuneAutomation",
      publishedTime,
      modifiedTime,
      authors: [post.author],
      tags: post.tags,
      images: post.image
        ? [
            {
              url: post.image,
              alt: post.title,
            },
          ]
        : undefined,
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description: post.description,
      images: post.image ? [post.image] : undefined,
    },
  };
}

export default async function BlogPostPage({ params }: BlogPostPageProps) {
  const { slug } = await params;
  const post = await getPostBySlug(slug);

  if (!post) {
    notFound();
  }

  return (
    <>
      <BreadcrumbSchema
        baseUrl={BASE_URL}
        items={[
          { name: "Home", url: "/" },
          { name: "Blog", url: "/blog/" },
          { name: post.title },
        ]}
      />
      <BlogPostingSchema
        baseUrl={BASE_URL}
        slug={slug}
        title={post.title}
        description={post.description}
        date={post.date}
        lastUpdated={post.lastUpdated}
        author={post.author}
        image={post.image}
        tags={post.tags}
      />
      <BlogPostClient slug={slug} />
    </>
  );
}
