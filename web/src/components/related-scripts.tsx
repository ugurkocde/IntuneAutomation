import Link from "next/link";
import { type Script } from "~/lib/scripts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "~/components/ui/card";
import { Badge } from "~/components/ui/badge";
import { ArrowRight, Code2, FileText, Tag } from "lucide-react";

interface RelatedScriptsProps {
  currentScript: Script;
  allScripts: Script[];
  limit?: number;
}

export function RelatedScripts({ currentScript, allScripts, limit = 3 }: RelatedScriptsProps) {
  // Calculate relevance score for each script
  const scoredScripts = allScripts
    .filter((script) => script.id !== currentScript.id)
    .map((script) => {
      let score = 0;

      // Score based on shared tags (weighted heavily)
      const sharedTags = script.tags.filter((tag) => currentScript.tags.includes(tag));
      score += sharedTags.length * 3;

      // Score based on same category
      if (script.category === currentScript.category) {
        score += 2;
      }

      // Score based on same script type
      if (script.scriptType === currentScript.scriptType) {
        score += 1;
      }

      // Score based on similar remediation type
      if (script.remediationType && currentScript.remediationType) {
        if (script.remediationType === currentScript.remediationType) {
          score += 2;
        }
      }

      return { ...script, relevanceScore: score };
    })
    .filter((script) => script.relevanceScore > 0)
    .sort((a, b) => b.relevanceScore - a.relevanceScore)
    .slice(0, limit);

  if (scoredScripts.length === 0) {
    return null;
  }

  return (
    <div className="mt-12 border-t pt-8">
      <div className="mb-6">
        <h2 className="text-2xl font-bold">Related Scripts</h2>
        <p className="text-muted-foreground mt-1">
          Discover similar scripts that might be useful for your automation needs
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        {scoredScripts.map((script) => {
          const sharedTags = script.tags.filter((tag) => currentScript.tags.includes(tag));

          return (
            <Card key={script.id} className="group relative hover:shadow-lg transition-shadow">
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between">
                  <Code2 className="h-5 w-5 text-muted-foreground" />
                  {script.relevanceScore >= 5 && (
                    <Badge variant="secondary" className="text-xs">
                      Highly Related
                    </Badge>
                  )}
                </div>
                <CardTitle className="text-lg line-clamp-2 group-hover:text-primary transition-colors">
                  <Link href={`/script/${script.slug}/`} className="after:absolute after:inset-0">
                    {script.title}
                  </Link>
                </CardTitle>
                <CardDescription className="line-clamp-2 text-sm">
                  {script.description}
                </CardDescription>
              </CardHeader>
              <CardContent className="pt-0">
                {sharedTags.length > 0 && (
                  <div className="mb-3 flex flex-wrap gap-1.5">
                    {sharedTags.map((tag) => (
                      <Badge key={tag} variant="outline" className="text-xs">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                )}

                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <div className="flex items-center gap-3">
                    {script.category && (
                      <span className="flex items-center gap-1">
                        <FileText className="h-3 w-3" />
                        {script.category}
                      </span>
                    )}
                  </div>
                  <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      <div className="mt-6 text-center">
        <Link
          href="/scripts/"
          className="inline-flex items-center gap-2 text-sm font-medium text-primary hover:underline"
        >
          Browse all scripts
          <ArrowRight className="h-4 w-4" />
        </Link>
      </div>
    </div>
  );
}