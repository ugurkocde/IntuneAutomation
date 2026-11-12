// TenuVault is a desktop app by the author of these scripts. The site shows
// it in a few labelled places. Every link carries UTM parameters, so
// tenuvault.com can tell which placement and which message a visitor came
// from.

const TENUVAULT_ORIGIN = "https://www.tenuvault.com";
const UTM_SOURCE = "intuneautomation.com";

export type TenuVaultPlacement = "script_page" | "generator" | "companion";

export type TenuVaultMessageId =
  | "restore"
  | "free"
  | "backup_script"
  | "restore_script"
  | "drift_script"
  | "config_write";

export interface TenuVaultMessage {
  id: TenuVaultMessageId;
  // Sent as utm_content and with the click event. The number goes up when
  // the wording changes, so results for old and new wording stay apart.
  tag: string;
  headline: string;
  body: string;
  action: string;
  path: string;
}

// Shown where the page has no topic of its own. The two take turns by day.
export const GENERAL_MESSAGES = {
  restore: {
    id: "restore",
    tag: "restore_v1",
    headline: "Deleted an Intune policy? Intune has no recycle bin.",
    body: "TenuVault backs up your Intune configuration and restores a deleted policy from the backup. Free for one tenant.",
    action: "See how restore works",
    path: "/intune-restore",
  },
  free: {
    id: "free",
    tag: "free_v1",
    headline: "Back up your Intune configuration in minutes.",
    body: "TenuVault is a desktop app for Windows and macOS. Free for one tenant, with no card and no TenuVault account.",
    action: "Download free",
    path: "/download",
  },
} as const satisfies Record<string, TenuVaultMessage>;

export type GeneralMessageId = keyof typeof GENERAL_MESSAGES;
export const GENERAL_MESSAGE_IDS = Object.keys(
  GENERAL_MESSAGES,
) as GeneralMessageId[];

// Shown where the page itself is about backup, restore or drift. Each one
// says what the free script does and what the app adds, so a reader can tell
// when the script is enough.
export const TOPIC_MESSAGES = {
  backup_script: {
    id: "backup_script",
    tag: "backup_script_v1",
    headline: "When this script is enough, and when an app helps",
    body: "This script exports five configuration areas, with their assignments, to JSON files. You run it and keep the files yourself, which covers a snapshot before a change or change tracking in source control. TenuVault backs up over 40 Intune object types on a schedule, encrypted on your device, and keeps a history you can compare and restore from. It is free for one tenant.",
    action: "See what TenuVault backs up",
    path: "/intune-backup",
  },
  restore_script: {
    id: "restore_script",
    tag: "restore_script_v1",
    headline: "When this script is enough, and when an app helps",
    body: "This script recreates objects from a backup folder as new entries. Assignments are left out unless you turn them on, and they need the same group IDs in the target tenant. TenuVault shows what a restore will change before it runs. The free plan restores one item at a time as an unassigned copy. The paid plans replace existing policies in place and restore assignments.",
    action: "See how TenuVault restores",
    path: "/intune-restore",
  },
  drift_script: {
    id: "drift_script",
    tag: "drift_script_v1",
    headline: "When this script is enough, and when an app helps",
    body: "This script compares three policy types with a baseline folder and reports what was added, removed or changed. TenuVault compares any two backups setting by setting across all backed-up types, on the free plan too. Reverting a drifted policy needs a paid plan.",
    action: "See drift detection in TenuVault",
    path: "/intune-drift-detection",
  },
  config_write: {
    id: "config_write",
    tag: "config_write_v1",
    headline: "This script can change Intune configuration.",
    body: "Take a backup before you run it. TenuVault backs up your Intune configuration and restores a policy from the backup. Free for one tenant.",
    action: "Back up with TenuVault",
    path: "/intune-backup",
  },
} as const satisfies Record<string, TenuVaultMessage>;

// Script pages whose topic TenuVault covers, by the script's path in the
// repository. A path is unique, while a slug comes from the title and would
// move to another script that got the same title.
const SCRIPT_TOPICS: Record<string, keyof typeof TOPIC_MESSAGES> = {
  "scripts/configuration/backup-intune-configuration.ps1": "backup_script",
  "scripts/configuration/restore-intune-configuration.ps1": "restore_script",
  "scripts/configuration/get-policy-drift-report.ps1": "drift_script",
};

export function scriptTopicMessage(
  githubPath: string | undefined,
): TenuVaultMessage | undefined {
  if (!githubPath || !Object.hasOwn(SCRIPT_TOPICS, githubPath)) {
    return undefined;
  }
  return TOPIC_MESSAGES[SCRIPT_TOPICS[githubPath]!];
}

// What the generator's permission check knows about a script.
export interface ScriptPermissions {
  // Minimum scopes for the calls the check could resolve.
  required: ReadonlyArray<{ scope: string }>;
  // Scopes the script itself declares.
  declared: readonly string[];
  // False when the script writes in a way the check could not resolve, for
  // example through Mg SDK cmdlets.
  writesResolved: boolean;
}

// Write scopes for things a TenuVault backup can bring back: policies and
// profiles, platform and compliance scripts, and Intune roles.
const RESTORABLE_WRITE =
  /^DeviceManagement(?:Configuration|Scripts|RBAC)\.ReadWrite\b/i;

// A generated script that changes policies, scripts or roles gets a reminder
// to back up first. Scripts that change devices, apps or the enrollment
// service (Autopilot devices among them) get the general message: a backup
// does not undo all of those, so the reminder would promise too much. When
// the check could not resolve a write, the scopes the script declares decide.
export function writesConfiguration(
  permissions: ScriptPermissions | null | undefined,
): boolean {
  if (!permissions) return false;
  const scopes = permissions.required.map((r) => r.scope);
  if (!permissions.writesResolved) scopes.push(...permissions.declared);
  return scopes.some((scope) => RESTORABLE_WRITE.test(scope));
}

function tagged(
  path: string,
  medium: string,
  campaign: TenuVaultPlacement,
  content?: string,
): string {
  const url = new URL(path, TENUVAULT_ORIGIN);
  url.searchParams.set("utm_source", UTM_SOURCE);
  url.searchParams.set("utm_medium", medium);
  url.searchParams.set("utm_campaign", campaign);
  if (content) url.searchParams.set("utm_content", content);
  return url.toString();
}

export function tenuvaultMessageUrl(
  message: TenuVaultMessage,
  placement: TenuVaultPlacement,
): string {
  return tagged(message.path, "house_ad", placement, message.tag);
}

// The companion card on the home page is a plain listing, not a message.
export const TENUVAULT_COMPANION_URL = tagged("/", "listing", "companion");

// The general messages take turns by calendar day (Berlin time), so each one
// is shown on every weekday over two weeks and their clicks can be compared.
// Nothing is stored in the visitor's browser for this.
export function generalMessageFor(now: Date): TenuVaultMessage {
  return GENERAL_MESSAGES[GENERAL_MESSAGE_IDS[dayIndex(now)]!];
}

function dayIndex(now: Date): number {
  const count = GENERAL_MESSAGE_IDS.length;
  let dayNumber: number;
  try {
    // Read the parts by name: the layout of a formatted date string is locale
    // data, not something to rely on.
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Berlin",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(now);
    const part = (type: "year" | "month" | "day") =>
      Number(parts.find((p) => p.type === type)?.value);
    dayNumber = Date.UTC(part("year"), part("month") - 1, part("day"));
  } catch {
    // A browser without time zone data falls back to the UTC day.
    dayNumber = now.getTime();
  }
  const day = Math.floor(dayNumber / 86_400_000);
  return Number.isFinite(day) ? ((day % count) + count) % count : 0;
}
