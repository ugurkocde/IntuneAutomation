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
      className={cn(
        "text-muted-foreground flex items-center space-x-1 text-sm",
        className,
      )}
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
              <span className="text-foreground max-w-[200px] truncate font-medium">
                {isFirst && <Home className="mr-1 inline h-4 w-4" />}
                {item.name}
              </span>
            ) : item.href ? (
              <Link
                href={item.href}
                className="hover:text-foreground max-w-[150px] truncate transition-colors"
              >
                {isFirst && <Home className="mr-1 inline h-4 w-4" />}
                {item.name}
              </Link>
            ) : (
              <span className="max-w-[150px] truncate">
                {isFirst && <Home className="mr-1 inline h-4 w-4" />}
                {item.name}
              </span>
            )}
          </div>
        );
      })}
    </nav>
  );
}
