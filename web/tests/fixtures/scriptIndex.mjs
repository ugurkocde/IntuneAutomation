export function makeScript(overrides = {}) {
  return {
    id: "get-device-report",
    title: "Get Device Report",
    synopsis: "Reports managed devices.",
    description: "Generates a device report from Intune.",
    category: "devices",
    categoryLabel: "Devices",
    tags: ["Devices", "Reporting"],
    permissions: ["DeviceManagementManagedDevices.Read.All"],
    minRole: "Intune Administrator",
    platform: "Windows",
    author: "Ugur Koc",
    version: "1.0",
    lastUpdate: "2026-01-01",
    schedule: "Daily",
    execution: "RunOnce",
    output: "CSV",
    remediationType: "",
    pairScript: "",
    parameters: [
      {
        name: "OutputPath",
        type: "string",
        mandatory: false,
        default: "report.csv",
        switch: false,
      },
    ],
    examples: [".\\get-device-report.ps1"],
    notes: "",
    path: "scripts/devices/get-device-report.ps1",
    rawUrl:
      "https://raw.githubusercontent.com/example/repo/main/scripts/devices/get-device-report.ps1",
    githubUrl:
      "https://github.com/example/repo/blob/main/scripts/devices/get-device-report.ps1",
    runbook: { eligible: true, runtime: "PowerShell 7.4", exclusionReason: "" },
    azureDeploy: {
      deployUrl: "https://portal.azure.com/#create/example",
      templateUrl: "https://example.com/template.json",
      supportsExistingAutomationAccount: true,
    },
    ...overrides,
  };
}

export function makeIndex(scripts) {
  return {
    repository: "example/repo",
    branch: "main",
    generated: "2026-08-18T00:00:00Z",
    count: scripts.length,
    categories: [...new Set(scripts.map((s) => s.category))].sort(),
    scripts,
  };
}

export const fixtureScripts = [
  makeScript(),
  makeScript({
    id: "rotate-bitlocker-keys",
    title: "Rotate BitLocker Keys",
    synopsis: "Rotates BitLocker recovery keys on managed devices.",
    description: "Triggers BitLocker key rotation via Microsoft Graph.",
    category: "security",
    tags: ["Security", "BitLocker"],
    permissions: ["DeviceManagementManagedDevices.ReadWrite.All"],
    runbook: {
      eligible: false,
      runtime: "",
      exclusionReason: "Local-only interactive script",
    },
    azureDeploy: null,
  }),
  makeScript({
    id: "detect-stale-devices",
    title: "Detect Stale Devices",
    synopsis: "Detection script for devices not synced recently.",
    description: "Remediation detection for stale devices.",
    category: "remediation",
    tags: ["Devices", "Remediation"],
    platform: "",
    permissions: ["DeviceManagementManagedDevices.Read.All"],
  }),
];

export const fixtureIndex = makeIndex(fixtureScripts);

export function makeRepository({
  index = fixtureIndex,
  instructions = "# Authoring guide\n\nHard rules apply.",
  source = "github",
  scriptSource = "<#\n.TITLE\nFixture\n#>\nparam()\nWrite-Output 'ok'",
} = {}) {
  const calls = { getIndex: 0, getInstructions: 0, getScriptSource: [] };
  return {
    calls,
    repository: {
      async getIndex() {
        calls.getIndex += 1;
        return { index, source };
      },
      async getInstructions() {
        calls.getInstructions += 1;
        return { text: instructions, source };
      },
      async getScriptSource(script) {
        calls.getScriptSource.push(script.id);
        return scriptSource;
      },
    },
  };
}
