import { NextResponse } from "next/server";
import { getRelatedPosts } from "~/lib/blog";

export async function GET(
  request: Request,
  context: { params: Promise<{ slug: string }> }
) {
  try {
    const { slug } = await context.params;
    const relatedPosts = await getRelatedPosts(slug, 3);
    return NextResponse.json(relatedPosts);
  } catch (error) {
    console.error("Error fetching related posts:", error);
    return NextResponse.json([], { status: 500 });
  }
}