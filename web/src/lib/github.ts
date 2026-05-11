import { env } from "~/env";
import type {
  Script,
  ScriptTag,
  PSScriptAnalyzerResult,
  ScriptUsageStats,
  RemediationType,
  ScriptType,
} from "./scripts";
import { generateSlug, ensureUniqueSlug } from "./scripts";
import { AnalyticsService } from "./supabase-analytics";

interface GitHubFile {
  name: string;
  path: string;
  sha: string;
  size: number;
  url: string;
  html_url: string;
  git_url: string;
  download_url: string;
  type: string;
}

interface GitHubContent {
  name: string;
  path: string;
  sha: string;
  size: number;
  url: string;
  html_url: string;
  git_url: string;
  download_url: string;
  type: string;
  content: string;
  encoding: string;
}

const GITHUB_API_BASE = "https://api.github.com";
const REPO_OWNER = "ugurkocde";
const REPO_NAME = "IntuneAutomation";
const SCRIPTS_PATH = "scripts";
const TEST_RESULTS_URL =
  "https://raw.githubusercontent.com/ugurkocde/IntuneAutomation/refs/heads/main/testresults.json";
const PERMISSIONS_URL =
  "https://raw.githubusercontent.com/ugurkocde/IntuneAutomation/refs/heads/main/permissions.json";

class GitHubService {
  private token: string;

  constructor() {
    this.token = env.PAT;
  }

  private async fetchWithAuth(url: string): Promise<Response> {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: "application/vnd.github.v3+json",
        "User-Agent": "IntuneAutomation-Website",
      },
      next: { revalidate: 300 }, // Cache for 5 minutes
    });

    if (!response.ok) {
      throw new Error(
        `GitHub API error: ${response.status} ${response.statusText}`,
      );
    }

    return response;
  }

  async getRepositoryFiles(path: string = SCRIPTS_PATH): Promise<GitHubFile[]> {
    const url = `${GITHUB_API_BASE}/repos/${REPO_OWNER}/${REPO_NAME}/contents/${path}`;
    const response = await this.fetchWithAuth(url);
    return response.json() as Promise<GitHubFile[]>;
  }

  async getFileContent(path: string): Promise<string> {
    const url = `${GITHUB_API_BASE}/repos/${REPO_OWNER}/${REPO_NAME}/contents/${path}`;
    const response = await this.fetchWithAuth(url);
    const content = (await response.json()) as GitHubContent;

    if (content.encoding === "base64") {
      return Buffer.from(content.content, "base64").toString("utf-8");
    }

    return content.content;
  }

  async getAllScriptFiles(): Promise<GitHubFile[]> {
    const allFiles: GitHubFile[] = [];

    const processDirectory = async (path: string): Promise<void> => {
      try {
        const files = await this.getRepositoryFiles(path);

        for (const file of files) {
          if (
            file.type === "file" &&
            (file.name.endsWith(".ps1") || file.name.endsWith(".sh"))
          ) {
            allFiles.push(file);
          } else if (file.type === "dir") {
            // Recursively process subdirectories
            await processDirectory(file.path);
          }
        }
      } catch (error) {
        console.warn(`Failed to process directory ${path}:`, error);
      }
    };

    await processDirectory(SCRIPTS_PATH);
    return allFiles;
  }

  parseScriptMetadata(content: string, fileExtension: string): Partial<Script> {
    const metadata: Partial<Script> = {};

    let commentBlock: string | undefined;

    if (fileExtension === ".ps1") {
      // Extract PowerShell comment block metadata
      const commentBlockMatch = content.match(/<#([\s\S]*?)#>/m);
      if (!commentBlockMatch) {
        return metadata;
      }
      commentBlock = commentBlockMatch[1]!;
    } else if (fileExtension === ".sh") {
      // Extract shell script comment metadata (lines starting with #)
      const lines = content.split("\n");
      const commentLines: string[] = [];
      let inHeader = false;

      for (const line of lines) {
        if (line.startsWith("#!")) continue; // Skip shebang
        if (line.startsWith("# ") && !inHeader) {
          inHeader = true;
        }
        if (inHeader && line.startsWith("# ")) {
          commentLines.push(line.substring(2)); // Remove '# ' prefix
        } else if (inHeader && !line.startsWith("#")) {
          break; // End of header comments
        }
      }

      commentBlock = commentLines.join("\n");
    }

    if (!commentBlock) {
      return metadata;
    }

    // Parse each metadata field
    const parseField = (fieldName: string): string | undefined => {
      if (fileExtension === ".ps1") {
        const regex = new RegExp(
          `\\.${fieldName}\\s*([\\s\\S]*?)(?=\\n\\s*\\.|\\n\\s*#>|$)`,
          "i",
        );
        const match = commentBlock.match(regex);
        return match?.[1]?.trim().replace(/^\s+/gm, "");
      } else if (fileExtension === ".sh") {
        // For shell scripts, handle multi-line values
        const lines = commentBlock.split("\n");
        let capturing = false;
        let capturedLines: string[] = [];

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          if (!line) continue;

          // Check if this line starts with the field we're looking for
          if (line.match(new RegExp(`^${fieldName}:\\s*(.*)$`, "i"))) {
            capturing = true;
            const match = line.match(
              new RegExp(`^${fieldName}:\\s*(.*)$`, "i"),
            );
            if (match?.[1]) {
              capturedLines.push(match[1]);
            }
            continue;
          }

          // If we're capturing and hit a new field (line with FIELDNAME:), stop
          if (capturing && line.match(/^[A-Z]+:/)) {
            break;
          }

          // If we're capturing and the line continues the previous field (indented or continuation)
          if (capturing && line.match(/^\s+/) && line.trim()) {
            capturedLines.push(line.trim());
          } else if (capturing && !line.trim()) {
            // Empty line might signal end of field
            break;
          }
        }

        return capturedLines.length > 0 ? capturedLines.join(" ") : undefined;
      }
    };

    // Extract title from TITLE field
    const title = parseField("TITLE");
    if (title) {
      metadata.title = title;
    }

    // Extract description
    const description = parseField("DESCRIPTION");
    if (description) {
      metadata.description = description;
    }

    // Extract and parse tags
    const tagsString = parseField("TAGS");
    if (tagsString) {
      const tags = tagsString
        .split(",")
        .map((tag) => tag.trim())
        .filter((tag): tag is ScriptTag =>
          [
            "Devices",
            "Compliance",
            "Apps",
            "Reporting",
            "Diagnostics",
            "Security",
            "Configuration",
            "Operational",
            "Monitoring",
            "Notification",
          ].includes(tag),
        );
      metadata.tags = tags;
    }

    // Extract minimum role
    const minRole = parseField("MINROLE");
    if (minRole) {
      metadata.minRole = minRole;
    }

    // Extract tested platforms
    const testedPlatforms = parseField("TESTEDPLATFORMS");
    if (testedPlatforms) {
      metadata.testedPlatforms = testedPlatforms
        .split(",")
        .map((p) => p.trim());
    }

    // For shell scripts, also check for PLATFORM field
    if (fileExtension === ".sh") {
      const platform = parseField("PLATFORM");
      if (platform && !metadata.testedPlatforms) {
        metadata.testedPlatforms = [platform];
      }
    }

    // Extract last update date
    const lastUpdate = parseField("LASTUPDATE");
    if (lastUpdate) {
      metadata.lastUpdated = lastUpdate;
    }

    // Extract author
    const author = parseField("AUTHOR");
    if (author) {
      metadata.author = author;
    }

    // Extract version
    const version = parseField("VERSION");
    if (version) {
      metadata.version = version;
    }

    // Extract permissions
    const permissions = parseField("PERMISSIONS");
    if (permissions) {
      metadata.permissions = permissions.split(",").map((p) => p.trim());
    }

    // Extract examples
    const example = parseField("EXAMPLE");
    if (example) {
      metadata.example = example;
    }

    // Extract notes
    const notes = parseField("NOTES");
    if (notes) {
      metadata.notes = notes;
    }

    // Extract changelog - improved parsing
    const changelog = parseField("CHANGELOG");
    if (changelog) {
      metadata.changelog = changelog
        .split("\n")
        .map((line) => line.trim())
        .filter(
          (line) => line && !line.startsWith("#") && !line.startsWith("."),
        )
        .map((line) => line.replace(/^\s*-\s*/, "")); // Remove leading dash and spaces
    }

    // Extract remediation metadata
    const pairScript = parseField("PAIRSCRIPT");
    if (pairScript) {
      metadata.pairScript = pairScript;
    }

    const remediationType = parseField("REMEDIATIONTYPE");
    if (remediationType) {
      metadata.remediationType = remediationType as RemediationType;
    }

    return metadata;
  }

  async fetchTestResults(): Promise<PSScriptAnalyzerResult[]> {
    try {
      const response = await fetch(TEST_RESULTS_URL, {
        next: { revalidate: 300 }, // Cache for 5 minutes
      });

      if (!response.ok) {
        console.warn("Failed to fetch test results:", response.statusText);
        return [];
      }

      const testResults = (await response.json()) as PSScriptAnalyzerResult[];
      return testResults;
    } catch (error) {
      console.warn("Failed to fetch PSScriptAnalyzer test results:", error);
      return [];
    }
  }

  async fetchPermissionsData(): Promise<
    Record<string, { displayName: string; description: string }>
  > {
    try {
      const response = await fetch(PERMISSIONS_URL, {
        next: { revalidate: 300 }, // Cache for 5 minutes
      });

      if (!response.ok) {
        console.warn("Failed to fetch permissions data:", response.statusText);
        return {};
      }

      const permissions = await response.json();
      return permissions;
    } catch (error) {
      console.warn("Failed to fetch permissions data:", error);
      return {};
    }
  }

  // Generate mock usage statistics (in a real app, this would come from your analytics/database)
  private generateMockUsageStats(scriptId: string): ScriptUsageStats {
    // Create pseudo-random but consistent values based on script ID
    const seed = scriptId
      .split("")
      .reduce((acc, char) => acc + char.charCodeAt(0), 0);
    const random = (min: number, max: number) => min + (seed % (max - min));

    const totalViews = random(50, 2500);
    const totalDownloads = random(10, Math.floor(totalViews * 0.6));
    const weeklyViews = random(0, Math.floor(totalViews * 0.1));
    const weeklyDownloads = random(0, Math.floor(weeklyViews * 0.4));

    return {
      totalViews,
      totalDownloads,
      weeklyViews,
      weeklyDownloads,
      lastViewedAt: new Date(
        Date.now() - random(0, 7 * 24 * 60 * 60 * 1000),
      ).toISOString(),
    };
  }

  async fetchAllScripts(): Promise<Script[]> {
    try {
      const [files, testResults, analyticsData] = await Promise.all([
        this.getAllScriptFiles(),
        this.fetchTestResults(),
        AnalyticsService.getAllScriptAnalytics(),
      ]);

      const scripts: Script[] = [];
      const remediationScripts = new Map<
        string,
        { detection?: Script; remediation?: Script }
      >();
      const existingSlugs: string[] = [];

      for (const file of files) {
        try {
          const content = await this.getFileContent(file.path);
          const fileExtension = file.name.endsWith(".ps1") ? ".ps1" : ".sh";
          const metadata = this.parseScriptMetadata(content, fileExtension);

          // Generate ID from filename
          const id = file.name.replace(/\.(ps1|sh)$/, "");

          // Find matching test result
          const testResult = testResults.find(
            (result) =>
              result.filename === file.name || result.filename === id + ".ps1",
          );

          // Get analytics data for this script, fallback to mock data if not available
          const analytics = analyticsData[id];
          const usageStats: ScriptUsageStats = analytics
            ? {
                totalViews: analytics.total_views,
                totalDownloads: analytics.total_downloads,
                weeklyViews: analytics.weekly_views,
                weeklyDownloads: analytics.weekly_downloads,
                lastViewedAt: analytics.last_viewed_at,
              }
            : this.generateMockUsageStats(id);

          // Determine script type
          const isRemediationScript = file.path.includes(
            "scripts/remediation/",
          );
          const scriptType: ScriptType = isRemediationScript
            ? "remediation"
            : "standalone";

          // Generate title and slug
          const title =
            metadata.title ||
            file.name.replace(/\.(ps1|sh)$/, "").replace(/-/g, " ");
          const baseSlug = generateSlug(title);
          const slug = ensureUniqueSlug(baseSlug, existingSlugs);
          existingSlugs.push(slug);

          // Create script object with defaults
          const script: Script = {
            id,
            slug,
            title,
            description: metadata.description || "No description available",
            code: content,
            tags:
              metadata.tags ||
              (isRemediationScript ? ["Remediation"] : ["Configuration"]),
            lastUpdated: metadata.lastUpdated,
            minRole: metadata.minRole,
            testedPlatforms: metadata.testedPlatforms,
            author: metadata.author,
            version: metadata.version,
            permissions: metadata.permissions,
            example: metadata.example,
            notes: metadata.notes,
            changelog: metadata.changelog,
            githubPath: file.path,
            githubUrl: file.html_url,
            testResult: testResult,
            usageStats: usageStats,
            scriptType: scriptType,
            pairScript: metadata.pairScript,
            remediationType: metadata.remediationType,
          };

          // Handle remediation scripts separately
          if (isRemediationScript && metadata.remediationType) {
            // Extract folder name from path (e.g., "antivirus-definition-updates")
            const pathParts = file.path.split("/");
            const folderName = pathParts[pathParts.length - 2];

            if (folderName && !remediationScripts.has(folderName)) {
              remediationScripts.set(folderName, {});
            }

            const remediationGroup = folderName
              ? remediationScripts.get(folderName)!
              : null;
            if (!remediationGroup) continue;
            if (metadata.remediationType === "Detection") {
              remediationGroup.detection = script;
            } else if (metadata.remediationType === "Remediation") {
              remediationGroup.remediation = script;
            }
          } else {
            // Regular standalone script
            scripts.push(script);
          }
        } catch (error) {
          console.warn(`Failed to process script ${file.name}:`, error);
        }
      }

      // Process remediation scripts and create combined entries
      for (const [folderName, pair] of remediationScripts.entries()) {
        if (pair.detection && pair.remediation) {
          // Create a combined remediation script entry
          const remediationTitle = pair.detection.title.replace(
            " Detection",
            "",
          );
          const remediationSlug = ensureUniqueSlug(
            generateSlug(remediationTitle),
            existingSlugs,
          );
          existingSlugs.push(remediationSlug);

          const remediationScript: Script = {
            id: folderName,
            slug: remediationSlug,
            title: remediationTitle,
            description: pair.detection.description,
            code: pair.detection.code, // Default to detection code
            tags: [
              "Remediation",
              ...pair.detection.tags.filter((t) => t !== "Remediation"),
            ],
            lastUpdated:
              pair.detection.lastUpdated || pair.remediation.lastUpdated,
            minRole: pair.detection.minRole,
            testedPlatforms: pair.detection.testedPlatforms,
            author: pair.detection.author,
            version: pair.detection.version,
            permissions: pair.detection.permissions,
            example: pair.detection.example,
            notes: pair.detection.notes,
            changelog: pair.detection.changelog,
            githubPath: `scripts/remediation/${folderName}`,
            githubUrl: `https://github.com/${REPO_OWNER}/${REPO_NAME}/tree/main/scripts/remediation/${folderName}`,
            testResult: pair.detection.testResult,
            usageStats: pair.detection.usageStats,
            scriptType: "remediation",
            category: "remediation",
            remediationPair: {
              detection: pair.detection,
              remediation: pair.remediation,
            },
          };

          scripts.push(remediationScript);
        } else {
          // If we don't have both scripts, add them individually
          if (pair.detection) scripts.push(pair.detection);
          if (pair.remediation) scripts.push(pair.remediation);
        }
      }

      return scripts;
    } catch (error) {
      console.error("Failed to fetch scripts from GitHub:", error);
      return [];
    }
  }
}

export const githubService = new GitHubService();
