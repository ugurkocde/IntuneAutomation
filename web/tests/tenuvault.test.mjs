// @ts-nocheck -- Node's test runner executes TypeScript imports directly.
import assert from "node:assert/strict";
import test from "node:test";

import {
  GENERAL_MESSAGES,
  GENERAL_MESSAGE_KEY,
  TENUVAULT_COMPANION_URL,
  TOPIC_MESSAGES,
  pickGeneralMessage,
  scriptTopicMessage,
  tenuvaultMessageUrl,
  writesConfiguration,
} from "../src/lib/tenuvault.ts";

function memoryStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    values,
  };
}

test("message links carry source, medium, placement and message", () => {
  assert.equal(
    tenuvaultMessageUrl(GENERAL_MESSAGES.restore, "script_page"),
    "https://www.tenuvault.com/intune-restore?utm_source=intuneautomation.com&utm_medium=house_ad&utm_campaign=script_page&utm_content=restore",
  );
  assert.equal(
    tenuvaultMessageUrl(TOPIC_MESSAGES.config_write, "generator"),
    "https://www.tenuvault.com/intune-backup?utm_source=intuneautomation.com&utm_medium=house_ad&utm_campaign=generator&utm_content=config_write",
  );
});

test("the companion card is tagged as a listing", () => {
  assert.equal(
    TENUVAULT_COMPANION_URL,
    "https://www.tenuvault.com/?utm_source=intuneautomation.com&utm_medium=listing&utm_campaign=companion",
  );
});

test("only the backup, restore and drift scripts get a topic message", () => {
  assert.equal(
    scriptTopicMessage("backup-intune-configuration")?.id,
    "backup_script",
  );
  assert.equal(
    scriptTopicMessage("restore-intune-configuration")?.id,
    "restore_script",
  );
  assert.equal(
    scriptTopicMessage("get-policy-drift-report")?.id,
    "drift_script",
  );
  assert.equal(scriptTopicMessage("device-compliance-report"), undefined);
  assert.equal(
    scriptTopicMessage("backup-bitlocker-keys-to-keyvault"),
    undefined,
  );
});

test("only a configuration write scope counts as changing configuration", () => {
  assert.equal(
    writesConfiguration(["DeviceManagementConfiguration.ReadWrite.All"]),
    true,
  );
  assert.equal(
    writesConfiguration([
      "DeviceManagementConfiguration.Read.All",
      "DeviceManagementManagedDevices.ReadWrite.All",
      "DeviceManagementApps.ReadWrite.All",
    ]),
    false,
  );
  assert.equal(writesConfiguration([]), false);
});

test("a first visit picks a message at random and stores it", () => {
  const storage = memoryStorage();
  assert.equal(pickGeneralMessage(storage, () => 0).id, "restore");
  assert.equal(storage.values.get(GENERAL_MESSAGE_KEY), "restore");

  const other = memoryStorage();
  assert.equal(pickGeneralMessage(other, () => 0.99).id, "free");
  assert.equal(pickGeneralMessage(memoryStorage(), () => 1).id, "free");
});

test("a returning visitor keeps the stored message", () => {
  const storage = memoryStorage({ [GENERAL_MESSAGE_KEY]: "free" });
  assert.equal(pickGeneralMessage(storage, () => 0).id, "free");
});

test("an unknown stored value is replaced by a fresh pick", () => {
  const storage = memoryStorage({ [GENERAL_MESSAGE_KEY]: "toString" });
  assert.equal(pickGeneralMessage(storage, () => 0).id, "restore");
  assert.equal(storage.values.get(GENERAL_MESSAGE_KEY), "restore");
});

test("blocked or missing storage still yields a message", () => {
  const blocked = {
    getItem() {
      throw new Error("blocked");
    },
    setItem() {
      throw new Error("blocked");
    },
  };
  assert.equal(pickGeneralMessage(blocked, () => 0).id, "restore");
  assert.equal(pickGeneralMessage(undefined, () => 0.6).id, "free");
});
