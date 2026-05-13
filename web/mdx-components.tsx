// MDX prose styling — v4 design system.
// Single source of truth for blog-post body typography. Maps every primitive
// MDX element to a styled component using the v4 vocabulary:
//   - Headings use .font-display (Geist tight-tracked semibold)
//   - Body uses Geist with generous line-height
//   - Links use accent-hi with underline-offset-4 hover:underline
//   - Inline code uses font-mono on a tinted card surface
//   - Code blocks live on a dark surface with hairline border, rounded-md
//   - Blockquotes use a cyan left border accent
//   - Lists use cyan bullet/number accent
//   - Images get rounded-md + hairline border
// Kept dependency-free of @tailwindcss/typography to retain full control over
// the visual contract; if Tailwind Typography is added later this file can
// be removed and the post page can drop in a `prose` class.

import type { MDXComponents } from "mdx/types";
import Link from "next/link";

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    // ── Headings ───────────────────────────────────────────────────────────
    h1: ({ children, ...props }) => (
      <h1
        {...props}
        className="font-display text-foreground mt-12 mb-6 scroll-m-20 text-3xl leading-[1.1] tracking-[-0.02em] first:mt-0 sm:text-4xl"
      >
        {children}
      </h1>
    ),
    h2: ({ children, ...props }) => (
      <h2
        {...props}
        className="font-display text-foreground mt-14 mb-5 scroll-m-20 border-b pb-3 text-2xl leading-[1.15] tracking-[-0.015em] first:mt-0 sm:text-3xl"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        {children}
      </h2>
    ),
    h3: ({ children, ...props }) => (
      <h3
        {...props}
        className="font-display text-foreground mt-10 mb-4 scroll-m-20 text-xl leading-[1.2] tracking-[-0.01em] sm:text-2xl"
      >
        {children}
      </h3>
    ),
    h4: ({ children, ...props }) => (
      <h4
        {...props}
        className="font-display text-foreground mt-8 mb-3 scroll-m-20 text-lg leading-[1.25] tracking-[-0.01em] sm:text-xl"
      >
        {children}
      </h4>
    ),

    // ── Body ───────────────────────────────────────────────────────────────
    p: ({ children, ...props }) => (
      <p
        {...props}
        className="text-foreground/90 leading-7 [&:not(:first-child)]:mt-6"
      >
        {children}
      </p>
    ),

    // ── Lists — cyan accent markers ────────────────────────────────────────
    ul: ({ children, ...props }) => (
      <ul
        {...props}
        className="text-foreground/90 my-6 ml-6 list-disc space-y-2 leading-7 marker:text-[color:var(--brand-accent-hi)]"
      >
        {children}
      </ul>
    ),
    ol: ({ children, ...props }) => (
      <ol
        {...props}
        className="text-foreground/90 my-6 ml-6 list-decimal space-y-2 leading-7 marker:font-mono marker:text-[color:var(--brand-accent-hi)]"
      >
        {children}
      </ol>
    ),
    li: ({ children, ...props }) => (
      <li {...props} className="pl-1">
        {children}
      </li>
    ),

    // ── Blockquote — cyan left border ──────────────────────────────────────
    blockquote: ({ children, ...props }) => (
      <blockquote
        {...props}
        className="text-muted-foreground my-6 border-l-2 pl-5 italic"
        style={{ borderColor: "var(--brand-accent-hi)" }}
      >
        {children}
      </blockquote>
    ),

    // ── Code (inline + block) ──────────────────────────────────────────────
    code: ({ children, className }) => {
      const isInlineCode = !className;
      if (isInlineCode) {
        return (
          <code
            className="bg-card/60 text-foreground rounded-md border px-1.5 py-0.5 font-mono text-[0.875em]"
            style={{ borderColor: "var(--brand-rule)" }}
          >
            {children}
          </code>
        );
      }
      // Code inside <pre> — let the <pre> own the surface; <code> just renders.
      return (
        <code className={`${className ?? ""} font-mono text-sm`}>
          {children}
        </code>
      );
    },
    pre: ({ children, ...props }) => (
      <pre
        {...props}
        className="my-8 overflow-x-auto rounded-md border p-4 text-sm leading-relaxed"
        style={{
          borderColor: "var(--brand-rule)",
          background:
            "color-mix(in oklab, var(--foreground) 5%, var(--background))",
        }}
      >
        {children}
      </pre>
    ),

    // ── Links ──────────────────────────────────────────────────────────────
    a: ({ href, children }) => {
      const isInternal = href && (href.startsWith("/") || href.startsWith("#"));
      const className =
        "text-accent-hi underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color:var(--brand-accent)] focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm";
      if (isInternal && href) {
        return (
          <Link href={href} className={className}>
            {children}
          </Link>
        );
      }
      return (
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          className={className}
        >
          {children}
        </a>
      );
    },

    // ── Tables ─────────────────────────────────────────────────────────────
    table: ({ children, ...props }) => (
      <div
        className="my-8 w-full overflow-x-auto rounded-md border"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        <table {...props} className="w-full border-collapse text-left text-sm">
          {children}
        </table>
      </div>
    ),
    thead: ({ children, ...props }) => (
      <thead {...props} className="bg-card/40">
        {children}
      </thead>
    ),
    tr: ({ children, ...props }) => (
      <tr
        {...props}
        className="border-b last:border-b-0"
        style={{ borderColor: "var(--brand-rule)" }}
      >
        {children}
      </tr>
    ),
    th: ({ children, ...props }) => (
      <th
        {...props}
        className="text-muted-foreground px-4 py-3 font-mono text-[11px] tracking-[0.14em] uppercase [&[align=center]]:text-center [&[align=right]]:text-right"
      >
        {children}
      </th>
    ),
    td: ({ children, ...props }) => (
      <td
        {...props}
        className="text-foreground/90 px-4 py-3 [&[align=center]]:text-center [&[align=right]]:text-right"
      >
        {children}
      </td>
    ),

    // ── Images ─────────────────────────────────────────────────────────────
    // eslint-disable-next-line @next/next/no-img-element, jsx-a11y/alt-text
    img: ({ alt, src, ...props }) => (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        {...props}
        alt={alt ?? ""}
        src={typeof src === "string" ? src : undefined}
        className="my-8 h-auto w-full rounded-md border"
        style={{ borderColor: "var(--brand-rule)" }}
      />
    ),

    // ── Horizontal rule ────────────────────────────────────────────────────
    hr: () => (
      <hr
        className="my-12 border-t"
        style={{ borderColor: "var(--brand-rule)" }}
      />
    ),

    ...components,
  };
}
