import fs from "fs";
import path from "path";
import matter from "gray-matter";
import { cache } from "react";

export interface BlogPost {
  slug: string;
  title: string;
  description: string;
  date: string;
  author: string;
  tags: string[];
  category: string;
  readingTime?: string;
  image?: string;
  published: boolean;
}

export interface BlogPostWithContent extends BlogPost {
  content: string;
}

const postsDirectory = path.join(process.cwd(), "src/content/blog");

function ensurePostsDirectory() {
  if (!fs.existsSync(postsDirectory)) {
    fs.mkdirSync(postsDirectory, { recursive: true });
  }
}

export const getAllPosts = cache(async (): Promise<BlogPost[]> => {
  ensurePostsDirectory();

  const fileNames = fs.readdirSync(postsDirectory);
  const allPosts = fileNames
    .filter((fileName) => fileName.endsWith(".mdx"))
    .map((fileName) => {
      const slug = fileName.replace(/\.mdx$/, "");
      const fullPath = path.join(postsDirectory, fileName);
      const fileContents = fs.readFileSync(fullPath, "utf8");
      const { data } = matter(fileContents);

      return {
        slug,
        title: data.title || slug,
        description: data.description || "",
        date: data.date || new Date().toISOString(),
        author: data.author || "IntuneAutomation Team",
        tags: data.tags || [],
        category: data.category || "general",
        readingTime: data.readingTime,
        image: data.image,
        published: data.published !== false,
      };
    })
    .filter((post) => post.published)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  return allPosts;
});

export const getPostBySlug = cache(
  async (slug: string): Promise<BlogPostWithContent | null> => {
    ensurePostsDirectory();

    const fullPath = path.join(postsDirectory, `${slug}.mdx`);

    if (!fs.existsSync(fullPath)) {
      return null;
    }

    const fileContents = fs.readFileSync(fullPath, "utf8");
    const { data, content } = matter(fileContents);

    return {
      slug,
      title: data.title || slug,
      description: data.description || "",
      date: data.date || new Date().toISOString(),
      author: data.author || "IntuneAutomation Team",
      tags: data.tags || [],
      category: data.category || "general",
      readingTime: data.readingTime,
      image: data.image,
      published: data.published !== false,
      content,
    };
  },
);

export const getPostsByCategory = cache(
  async (category: string): Promise<BlogPost[]> => {
    const allPosts = await getAllPosts();
    return allPosts.filter((post) => post.category === category);
  },
);

export const getPostsByTag = cache(async (tag: string): Promise<BlogPost[]> => {
  const allPosts = await getAllPosts();
  return allPosts.filter((post) => post.tags.includes(tag));
});

export const getRelatedPosts = cache(
  async (slug: string, limit = 3): Promise<BlogPost[]> => {
    const allPosts = await getAllPosts();
    const currentPost = allPosts.find((post) => post.slug === slug);

    if (!currentPost) return [];

    const relatedPosts = allPosts
      .filter((post) => post.slug !== slug)
      .map((post) => {
        const commonTags = post.tags.filter((tag) =>
          currentPost.tags.includes(tag),
        );
        const sameCategory = post.category === currentPost.category;
        const score = commonTags.length * 2 + (sameCategory ? 1 : 0);
        return { ...post, score };
      })
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);

    return relatedPosts;
  },
);

export const getAllTags = cache(async (): Promise<string[]> => {
  const allPosts = await getAllPosts();
  const tags = new Set<string>();

  allPosts.forEach((post) => {
    post.tags.forEach((tag) => tags.add(tag));
  });

  return Array.from(tags).sort();
});

export const getAllCategories = cache(async (): Promise<string[]> => {
  const allPosts = await getAllPosts();
  const categories = new Set<string>();

  allPosts.forEach((post) => {
    categories.add(post.category);
  });

  return Array.from(categories).sort();
});
