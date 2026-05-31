export type AbuseCheckResult =
  | { allowed: true }
  | { allowed: false; category: "prompt-injection" | "harmful-request" };

export type MaliciousScriptCheckResult =
  | { malicious: false }
  | { malicious: true; reason: string };

const PROMPT_INJECTION_PATTERNS = [
  /\bignore\s+(?:all\s+)?(?:previous|prior|above|system|developer)\s+instructions?\b/i,
  /\bdisregard\s+(?:all\s+)?(?:previous|prior|above|system|developer)\s+instructions?\b/i,
  /\byou\s+are\s+now\b/i,
  /\bact\s+as\b/i,
  /\bpretend\s+(?:to\s+be|you\s+are)\b/i,
  /\bdeveloper\s+mode\b/i,
  /\bjailbreak\b/i,
  /\bDAN\b/,
  /\bnew\s+persona\b/i,
  /\breveal\s+(?:the\s+)?(?:system|developer)\s+prompt\b/i,
  /\bprint\s+(?:the\s+)?(?:system|developer)\s+prompt\b/i,
  /\brespond\s+(?:in|with)\s+(?:json|plain\s+text|prose|a\s+story|a\s+poem)\b/i,
  /\bwrite\s+(?:me\s+)?(?:a\s+)?(?:poem|story|essay|joke|recipe)\b/i,
];

const HARMFUL_PROMPT_PATTERNS = [
  /\b(?:steal(?:s|ing)?|dump(?:s|ing)?|extract(?:s|ing)?|harvest(?:s|ing)?|exfiltrat(?:e|es|ing)|collect(?:s|ing)?)\b[\s\S]{0,120}\b(?:passwords?|credentials?|tokens?|cookies?|browser\s+passwords?|secrets?|private\s+keys?)\b/i,
  /\b(?:passwords?|credentials?|tokens?|cookies?|browser\s+passwords?|secrets?|private\s+keys?)\b[\s\S]{0,120}\b(?:steal(?:s|ing)?|dump(?:s|ing)?|extract(?:s|ing)?|harvest(?:s|ing)?|exfiltrat(?:e|es|ing)|send\s+to\s+me|email\s+.+\s+to\s+me)\b/i,
  /\b(?:steal(?:s|ing)?|dump(?:s|ing)?|extract(?:s|ing)?|harvest(?:s|ing)?|exfiltrat(?:e|es|ing))\b[\s\S]{0,160}\b(?:users?|user\s+data|tenant\s+data|directory\s+data|all\s+data)\b[\s\S]{0,160}\b(?:https?:\/\/|send|email|post|upload)\b/i,
  /\b(?:users?|user\s+data|tenant\s+data|directory\s+data|all\s+data)\b[\s\S]{0,160}\b(?:send|email|post|upload)\b[\s\S]{0,80}\bhttps?:\/\/(?!graph\.microsoft\.com|.*\.microsoft\.com|.*\.office\.com)/i,
  /\b(?:ransomware|keylogger|credential\s+stealer|reverse\s+shell|meterpreter|c2\s+agent|command\s+and\s+control)\b/i,
  /\b(?:encrypt|lock)\b[\s\S]{0,80}\b(?:user\s+)?files?\b[\s\S]{0,120}\b(?:delete|remove|wipe)\b[\s\S]{0,80}\b(?:backups?|shadow\s+copies|restore\s+points?)\b/i,
  /\b(?:delete|remove|wipe)\b[\s\S]{0,80}\b(?:backups?|shadow\s+copies|restore\s+points?)\b[\s\S]{0,120}\b(?:encrypt|lock)\b[\s\S]{0,80}\b(?:user\s+)?files?\b/i,
  /\b(?:disable(?:s|d|ing)?|bypass(?:es|ed|ing)?|evad(?:e|es|ed|ing)|turn\s+off)\b[\s\S]{0,80}\b(?:defender|antivirus|anti-virus|edr|amsi|tamper\s+protection)\b[\s\S]{0,160}\b(?:payload|malware|persist(?:s|ed|ing)?|persistence|startup|scheduled\s+task|download(?:s|ed|ing)?|invoke-webrequest|invoke-restmethod)\b/i,
  /\b(?:payload|malware|persist(?:s|ed|ing)?|persistence|startup|scheduled\s+task|download(?:s|ed|ing)?|invoke-webrequest|invoke-restmethod)\b[\s\S]{0,160}\b(?:disable(?:s|d|ing)?|bypass(?:es|ed|ing)?|evad(?:e|es|ed|ing)|turn\s+off)\b[\s\S]{0,80}\b(?:defender|antivirus|anti-virus|edr|amsi|tamper\s+protection)\b/i,
  /\b(?:bypass(?:es|ed|ing)?|evad(?:e|es|ed|ing))\b[\s\S]{0,80}\b(?:detection|security\s+tools?|edr|antivirus|anti-virus|defender|amsi)\b/i,
  /\b(?:make|create|write|generate)\b[\s\S]{0,80}\b(?:malware|ransomware|keylogger|credential\s+stealer|reverse\s+shell)\b/i,
];

const MALICIOUS_SCRIPT_PATTERNS: Array<{ reason: string; pattern: RegExp }> = [
  {
    reason: "Disables security tooling while downloading or running a payload.",
    pattern:
      /\b(?:Set-MpPreference|Add-MpPreference|sc\.exe|Set-Service|Stop-Service|reg(?:\.exe)?)\b[\s\S]{0,500}\b(?:DisableRealtimeMonitoring|DisableIOAVProtection|DisableBehaviorMonitoring|WinDefend|TamperProtection|AMSI|Defender)\b[\s\S]{0,800}\b(?:Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadString|FromBase64String|Start-Process|schtasks(?:\.exe)?)\b/i,
  },
  {
    reason:
      "Collects credentials, browser secrets, or tokens for exfiltration.",
    pattern:
      /\b(?:Login Data|Cookies|Local State|History|SAM|NTDS\.dit|Credential Manager|Get-StoredCredential|vaultcmd|Browser)\b[\s\S]{0,800}\b(?:Invoke-WebRequest|Invoke-RestMethod|Send-MailMessage|SmtpClient|WebClient|UploadString|UploadFile)\b/i,
  },
  {
    reason: "Creates a reverse shell or command-and-control channel.",
    pattern:
      /\b(?:TcpClient|Net\.Sockets|reverse\s+shell|meterpreter|command\s+and\s+control|c2)\b[\s\S]{0,500}\b(?:cmd\.exe|powershell\.exe|Start-Process|IEX|Invoke-Expression)\b/i,
  },
  {
    reason: "Encrypts files while deleting recovery points or backups.",
    pattern:
      /\b(?:Get-ChildItem|gci)\b[\s\S]{0,500}\b(?:Encrypt|Aes|Rijndael|ProtectedData)\b[\s\S]{0,800}\b(?:vssadmin|wbadmin|Delete\s+Shadows|shadowcopy|restore\s+point)\b/i,
  },
  {
    reason:
      "Uses encoded or downloaded code execution with risky execution primitives.",
    pattern:
      /\b(?:FromBase64String|DownloadString|EncodedCommand)\b[\s\S]{0,400}\b(?:Invoke-Expression|\biex\b|powershell(?:\.exe)?\s+-|Start-Process)\b/i,
  },
];

export function checkForPromptAbuse(prompt: string): AbuseCheckResult {
  for (const pattern of PROMPT_INJECTION_PATTERNS) {
    if (pattern.test(prompt)) {
      return { allowed: false, category: "prompt-injection" };
    }
  }

  for (const pattern of HARMFUL_PROMPT_PATTERNS) {
    if (pattern.test(prompt)) {
      return { allowed: false, category: "harmful-request" };
    }
  }

  return { allowed: true };
}

export function checkForMaliciousScript(
  code: string,
): MaliciousScriptCheckResult {
  const codeWithoutHelpBlock = code.replace(/<#[\s\S]*?#>/g, "");
  for (const { pattern, reason } of MALICIOUS_SCRIPT_PATTERNS) {
    if (pattern.test(codeWithoutHelpBlock)) {
      return { malicious: true, reason };
    }
  }
  return { malicious: false };
}
