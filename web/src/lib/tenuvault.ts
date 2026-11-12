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
  headline: string;
  body: string;
  action: string;
  path: string;
}

// Shown where the page has no topic of its own. A visitor gets one of the two
// and keeps it.
export const GENERAL_MESSAGES = {
  restore: {
    id: "restore",
    headline: "Deleted an Intune policy? Intune has no recycle bin.",
    body: "TenuVault backs up your Intune configuration and restores a deleted policy from the backup. Free for one tenant.",
    action: "See how restore works",
    path: "/intune-restore",
  },
  free: {
    id: "free",
    headline: "Back up your Intune tenant in minutes.",
    body: "TenuVault is a desktop app for Windows and macOS. Free for one tenant, with no card and no TenuVault account.",
    action: "Download free",
    path: "/download",
  },
} as const satisfies Record<string, TenuVaultMessage>;

export type GeneralMessageId = keyof typeof GENERAL_MESSAGES;
export const GENERAL_MESSAGE_IDS = Object.keys(
  GENERAL_MESSAGES,
) as GeneralMessageId[];
export const GENERAL_MESSAGE_KEY = "intuneautomation-tenuvault-message";

// Shown where the page itself is about backup, restore or drift. Each one
// says what the free script does and what the app adds, so a reader can tell
// when the script is enough.
export const TOPIC_MESSAGES = {
  backup_script: {
    id: "backup_script",
    headline: "When this script is enough, and when an app helps",
    body: "This script exports five configuration areas to JSON files that you run and store yourself. That covers a snapshot before a change, or change tracking in source control. TenuVault backs up 40 Intune object types on a schedule, keeps the backups encrypted and shows their history. It is free for one tenant.",
    action: "See what TenuVault backs up",
    path: "/intune-backup",
  },
  restore_script: {
    id: "restore_script",
    headline: "When this script is enough, and when an app helps",
    body: "This script recreates objects from a backup folder as new entries, and restores assignments when the group IDs still exist. TenuVault restores from its own backups after you review a restore plan. The free plan restores one item at a time as an unassigned copy. The paid plans replace existing policies in place and restore assignments.",
    action: "See how TenuVault restores",
    path: "/intune-restore",
  },
  drift_script: {
    id: "drift_script",
    headline: "When this script is enough, and when an app helps",
    body: "This script compares three policy types with a baseline folder and reports what was added, removed or changed. TenuVault compares its backups and shows the drift setting by setting, on the free plan too. Reverting a drifted policy needs a paid plan.",
    action: "See drift detection in TenuVault",
    path: "/intune-drift-detection",
  },
  config_write: {
    id: "config_write",
    headline: "This script changes Intune configuration.",
    body: "Take a backup before you run it. TenuVault backs up your Intune configuration and restores a policy from the backup. Free for one tenant.",
    action: "Back up with TenuVault",
    path: "/intune-backup",
  },
} as const satisfies Record<string, TenuVaultMessage>;

// Script pages whose topic TenuVault covers, by script slug.
const SCRIPT_TOPICS: Record<string, keyof typeof TOPIC_MESSAGES> = {
  "backup-intune-configuration": "backup_script",
  "restore-intune-configuration": "restore_script",
  "get-policy-drift-report": "drift_script",
};

export function scriptTopicMessage(slug: string): TenuVaultMessage | undefined {
  const topic = SCRIPT_TOPICS[slug];
  return topic ? TOPIC_MESSAGES[topic] : undefined;
}

// A generated script that needs a configuration write scope can change or
// delete policies, which a configuration backup can bring back. Scripts that
// only change devices or apps get the general message: a configuration backup
// does not undo those.
export function writesConfiguration(scopes: readonly string[]): boolean {
  return scopes.some((scope) =>
    /^DeviceManagementConfiguration\.ReadWrite\b/i.test(scope),
  );
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
  return tagged(message.path, "house_ad", placement, message.id);
}

// The companion card on the home page is a plain listing, not a message.
export const TENUVAULT_COMPANION_URL = tagged("/", "listing", "companion");

type MessageStorage = Pick<Storage, "getItem" | "setItem">;

// Each visitor gets one general message at random and keeps it, so a click or
// a download can be credited to one message. Without usable storage the
// message is picked again on every page load.
export function pickGeneralMessage(
  storage: MessageStorage | undefined,
  random: () => number = Math.random,
): TenuVaultMessage {
  try {
    const saved = storage?.getItem(GENERAL_MESSAGE_KEY);
    const known = GENERAL_MESSAGE_IDS.find((id) => id === saved);
    if (known) {
      return GENERAL_MESSAGES[known];
    }
  } catch {
    // Fall through to a fresh pick.
  }
  const index = Math.min(
    GENERAL_MESSAGE_IDS.length - 1,
    Math.floor(random() * GENERAL_MESSAGE_IDS.length),
  );
  const picked = GENERAL_MESSAGES[GENERAL_MESSAGE_IDS[index]!];
  try {
    storage?.setItem(GENERAL_MESSAGE_KEY, picked.id);
  } catch {
    // The pick still holds for this page view.
  }
  return picked;
}
