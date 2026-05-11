import Link from "next/link";
import { ChevronRight, Home } from "lucide-react";
import { cn } from "~/lib/utils";

export interface BreadcrumbItem {
  name: string;
  href?: string;
}

interface BreadcrumbProps {
  items: BreadcrumbItem[];
  className?: string;
}

export function Breadcrumb({ items, className }: BreadcrumbProps) {
  return (
    <nav
      aria-label="Breadcrumb"
      className={cn("flex items-center space-x-1 text-sm text-muted-foreground", className)}
    >
      {items.map((item, index) => {
        const isLast = index === items.length - 1;
        const isFirst = index === 0;

        return (
          <div key={index} className="flex items-center">
            {index > 0 && (
              <ChevronRight className="mx-2 h-4 w-4 flex-shrink-0" />
            )}
            {isLast ? (
              <span className="font-medium text-foreground truncate max-w-[200px]">
                {isFirst && <Home className="mr-1 h-4 w-4 inline" />}
                {item.name}
              </span>
            ) : item.href ? (
              <Link
                href={item.href}
                className="hover:text-foreground transition-colors truncate max-w-[150px]"
              >
                {isFirst && <Home className="mr-1 h-4 w-4 inline" />}
                {item.name}
              </Link>
            ) : (
              <span className="truncate max-w-[150px]">
                {isFirst && <Home className="mr-1 h-4 w-4 inline" />}
                {item.name}
              </span>
            )}
          </div>
        );
      })}
    </nav>
  );
}