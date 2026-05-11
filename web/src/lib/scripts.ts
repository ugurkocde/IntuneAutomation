export type ScriptTag =
  | "Devices"
  | "Compliance"
  | "Apps"
  | "Reporting"
  | "Diagnostics"
  | "Security"
  | "Configuration"
  | "Operational"
  | "Monitoring"
  | "Notification"
  | "Remediation";

export const allTags: ScriptTag[] = [
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
  "Remediation",
];

export type ExecutionMode = "Local" | "Runbook" | "RunbookOnly";
export type OutputType = "File" | "Email" | "Console";
export type ScheduleType = "OnDemand" | "Daily" | "Weekly" | "Monthly";
export type ScriptCategory =
  | "operational"
  | "reporting"
  | "notification"
  | "remediation";
export type ScriptType = "standalone" | "remediation";
export type RemediationType = "Detection" | "Remediation";

export interface PSScriptAnalyzerResult {
  filename: string;
  result: "pass" | "fail" | "warning";
  timestamp: string;
}

export interface ScriptUsageStats {
  totalViews: number;
  totalDownloads: number;
  weeklyViews: number;
  weeklyDownloads: number;
  lastViewedAt?: string;
}

export interface Script {
  id: string;
  slug: string;
  title: string;
  description: string;
  code: string;
  tags: ScriptTag[];
  lastUpdated?: string;
  minRole?: string;
  testedPlatforms?: string[];
  author?: string;
  version?: string;
  permissions?: string[];
  example?: string;
  notes?: string;
  githubPath?: string;
  githubUrl?: string;
  changelog?: string[];
  // PSScriptAnalyzer test results
  testResult?: PSScriptAnalyzerResult;
  // Usage statistics
  usageStats?: ScriptUsageStats;
  // Notification script metadata
  execution?: ExecutionMode;
  output?: OutputType;
  schedule?: ScheduleType;
  category?: ScriptCategory;
  emailRecipients?: string;
  thresholds?: Array<{
    parameter: string;
    description: string;
    recommended: string;
  }>;
  // Remediation script metadata
  scriptType?: ScriptType;
  pairScript?: string;
  remediationType?: RemediationType;
  remediationPair?: {
    detection: Script;
    remediation: Script;
  };
}

// Utility function to generate SEO-friendly slugs
export function generateSlug(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-+/g, "-");
}

// Helper function to ensure unique slugs
export function ensureUniqueSlug(
  slug: string,
  existingSlugs: string[],
): string {
  let uniqueSlug = slug;
  let counter = 1;

  while (existingSlugs.includes(uniqueSlug)) {
    uniqueSlug = `${slug}-${counter}`;
    counter++;
  }

  return uniqueSlug;
}
