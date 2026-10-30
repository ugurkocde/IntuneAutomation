<#
.TITLE
    Software Usage Metering Detection Script

.SYNOPSIS
    Reports when selected Windows programs were last started and on how many days, without user names.

.DESCRIPTION
    Meters software usage on Windows devices for license reviews. The script reads
    process start events (Security event 4688) for a list of programs, keeps a small
    local checkpoint, and reports per program the last start and how many starts
    happened on how many days of the last 30. Programs that were not started since
    metering began are listed separately, which points to licenses nobody uses.
    The result is plain text in the detection output column of the Intune
    Remediations report. Requires Audit Process Creation (Success) on the device.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PLATFORM
    Windows

.MINROLE
    Intune Service Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-10-30

.EXAMPLE
    .\detect-software-usage.ps1
    Reports usage of the programs in $Programs. Returns exit 1 if Audit Process Creation is off. Example output:
    OK. Watching 6 programs since 2026-10-01 14:00 UTC. Used (2): winword.exe last 2026-10-30 08:12 UTC, 37 starts on 12 of 30 days; excel.exe last 2026-10-28 15:40 UTC, 5 starts on 3 of 30 days. Not started (4): powerpnt.exe, visio.exe, winproj.exe, acrobat.exe.

.NOTES
    - Runs in SYSTEM context via Intune Remediations. Detection only: deploy without a remediation script, in 64-bit PowerShell, on an hourly schedule
    - Edit $Programs before uploading. Use executable file names such as 'visio.exe'; matching ignores case and folder
    - Enable Audit Process Creation (Success) through a policy, for example the Auditing category of the settings catalog. The script never changes audit policy
    - Exit 0 = metering works. Exit 1 = Audit Process Creation is off. Exit 2 = invalid $Programs or a failed run. Intune lists exits 1 and 2 under "With issues", so that view shows the devices that do not meter
    - Counts program starts. It does not measure how long a program was in use and does not check installations
    - Collects no user names, command lines or paths and contacts no network endpoint. Its only file is a checkpoint in %ProgramData%\IntuneAutomation\SoftwareMetering
    - Intune keeps 2048 characters of output. Meter about 25 programs or fewer per script; longer results end with "+N more"
    - A busy device can overwrite the Security log between runs. The output then says which starts may be missing; a larger Security log prevents this
#>

$ErrorActionPreference = "Stop"

# Executable names of the programs to meter.
$Programs = @(
    'winword.exe'
    'excel.exe'
    'powerpnt.exe'
    'visio.exe'
    'winproj.exe'
    'acrobat.exe'
)

# Days of history per program, reported as "N starts on X of 30 days".
$WindowDays = 30

$ProgressPreference = 'SilentlyContinue'
$MaxOutput = 2048
$Invariant = [Globalization.CultureInfo]::InvariantCulture

function ConvertTo-UtcText([DateTime]$Value) { $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $Invariant) }
# PowerShell 7 already turns ISO strings from ConvertFrom-Json into dates.
function ConvertFrom-UtcText($Value) {
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    [DateTime]::Parse([string]$Value, $Invariant, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}
function Get-DayKey([DateTime]$Value) { $Value.ToUniversalTime().ToString('yyyyMMdd', $Invariant) }
function Format-UtcDisplay([DateTime]$Value) { $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm', $Invariant) + ' UTC' }
function Format-Count([int]$Number, [string]$Noun) { if ($Number -eq 1) { "1 $Noun" } else { "$Number ${Noun}s" } }

function Assert-NoReparsePoint([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing a redirected state path.'
    }
}

$watch = @{}
$invalid = @()
foreach ($program in $Programs) {
    $name = ([string]$program).Trim().ToLowerInvariant()
    if ($name -match '^[^\\/:*?"<>|]+\.exe$') { $watch[$name] = $true } else { $invalid += $name }
}
if ($invalid.Count -or -not $watch.Count) {
    Write-Output "Configuration error: `$Programs must list executable file names such as 'visio.exe'. Invalid: $($invalid -join ', ')"
    exit 2
}

$now = [DateTime]::UtcNow
# Per program: when watching began, last start, and starts per UTC day.
$apps = @{}
# When metering began on this device, and since when no starts can be missing.
$started = $now
$coverage = $now
$status = 'error'
$mutex = $null
$held = $false

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator access required.' }
    $mutex = New-Object Threading.Mutex($false, 'Global\IntuneAutomationSoftwareMetering')
    # Intune can start an on-demand and a scheduled run together. Wait for the
    # other run instead of reporting an error that would replace its result.
    try { $held = $mutex.WaitOne(150000) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw 'Metering already running.' }
    $now = [DateTime]::UtcNow
    $started = $now
    $coverage = $now

    # Locale-independent audit policy check. No policy changes are made.
    if (-not ('IntuneAutomationAuditPolicy' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IntuneAutomationAuditPolicy {
    [StructLayout(LayoutKind.Sequential)]
    public struct Info { public Guid Subcategory; public uint Options; public Guid Category; }
    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.U1)]
    public static extern bool AuditQuerySystemPolicy(ref Guid id, uint count, out IntPtr result);
    [DllImport("advapi32.dll")] public static extern void AuditFree(IntPtr buffer);
    public static bool CreationEnabled() {
        Guid id = new Guid("0CCE922B-69AE-11D9-BED3-505054503030");
        IntPtr result;
        if (!AuditQuerySystemPolicy(ref id, 1, out result)) throw new InvalidOperationException("Audit policy unavailable");
        try { return (((Info)Marshal.PtrToStructure(result, typeof(Info))).Options & 1) != 0; }
        finally { AuditFree(result); }
    }
}
'@
    }
    $root = Join-Path $env:ProgramData 'IntuneAutomation'
    $folder = Join-Path $root 'SoftwareMetering'
    foreach ($path in @($root, $folder)) {
        Assert-NoReparsePoint $path
        [void][IO.Directory]::CreateDirectory($path)
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $account = New-Object Security.Principal.SecurityIdentifier($sid)
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $path -AclObject $acl
    }
    $stateFile = Join-Path $folder 'state.json'
    Assert-NoReparsePoint $stateFile
    $status = 'ok'
    $previous = $null
    if (Test-Path -LiteralPath $stateFile) {
        try {
            if ((Get-Item -LiteralPath $stateFile).Length -gt 524288) { throw 'Oversize state' }
            $previous = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($previous.version -ne 1 -or -not $previous.record -or [long]$previous.record -lt 1) { throw 'Invalid checkpoint' }
            $started = ConvertFrom-UtcText $previous.started
            $coverage = ConvertFrom-UtcText $previous.coverage
            $priorEnd = ConvertFrom-UtcText $previous.end
            if ($started -gt $coverage -or $coverage -gt $priorEnd -or $priorEnd -gt $now) { throw 'Invalid coverage' }
            if ($previous.apps) {
                foreach ($property in $previous.apps.PSObject.Properties) {
                    $exe = $property.Name.ToLowerInvariant()
                    # Programs removed from the list are forgotten.
                    if (-not $watch.ContainsKey($exe)) { continue }
                    $entry = @{ first = (ConvertFrom-UtcText $property.Value.first); last = $null; days = @{} }
                    if ($property.Value.last) { $entry.last = ConvertFrom-UtcText $property.Value.last }
                    if ($entry.first -gt $now -or ($entry.last -and $entry.last -gt $now)) { throw 'Invalid entry' }
                    if ($property.Value.days) {
                        foreach ($day in $property.Value.days.PSObject.Properties) { $entry.days[$day.Name] = [int]$day.Value }
                    }
                    $apps[$exe] = $entry
                }
            }
        } catch {
            # An unreadable checkpoint starts metering over.
            $previous = $null
            $apps = @{}
        }
    }
    if (-not [IntuneAutomationAuditPolicy]::CreationEnabled()) {
        $status = 'audit_off'
        $apps = @{}
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
    } else {
        $newest = Get-WinEvent -LogName Security -MaxEvents 1
        # Capture the report time AFTER the upper bookmark. Otherwise starts
        # during initialization could be skipped while their bookmark advances.
        $now = [DateTime]::UtcNow
        if (-not $previous) { $started = $now; $coverage = $now }
        # Programs added to the list are watched from now on.
        foreach ($exe in $watch.Keys) {
            if (-not $apps.ContainsKey($exe)) { $apps[$exe] = @{ first = $now; last = $null; days = @{} } }
        }
        $upper = [long]$newest.RecordId
        $lower = $upper # The first run starts metering now, it never backdates.
        if ($previous) {
            $checkpoint = [long]$previous.record
            $boundary = @(Get-WinEvent -LogName Security -FilterXPath "*[System[EventRecordID=$checkpoint]]" -MaxEvents 1 -ErrorAction SilentlyContinue)
            if ($checkpoint -gt $upper -or $boundary.Count -ne 1 -or $boundary[0].TimeCreated.ToUniversalTime().Ticks.ToString() -ne $previous.recordTime) {
                # The log was cleared or rolled over since the last run.
                $coverage = $now
            } else { $lower = $checkpoint }
        }
        if ($lower -lt $upper) {
            $xpath = "*[System[(EventID=4688 or EventID=4719) and EventRecordID > $lower and EventRecordID <= $upper]]"
            $query = New-Object Diagnostics.Eventing.Reader.EventLogQuery('Security', [Diagnostics.Eventing.Reader.PathType]::LogName, $xpath)
            $reader = New-Object Diagnostics.Eventing.Reader.EventLogReader($query)
            $processed = 0
            $auditOff = $null
            try {
                while ($null -ne ($logEntry = $reader.ReadEvent())) {
                    try {
                        $processed++
                        if ($processed -gt 100000 -or ([DateTime]::UtcNow - $now).TotalSeconds -gt 90) {
                            # Skip the rest with an explicit gap so a busy device
                            # recovers on its next scheduled run.
                            $coverage = $now; break
                        }
                        [xml]$xml = $logEntry.ToXml()
                        $fields = @{}
                        foreach ($field in $xml.Event.EventData.Data) { $fields[$field.Name] = [string]$field.'#text' }
                        if ($logEntry.Id -eq 4719 -and $fields['SubcategoryGuid'] -eq '{0CCE922B-69AE-11D9-BED3-505054503030}') {
                            # Intune re-applies audit policy by removing Success
                            # auditing (%%8448) and adding it back (%%8449) within
                            # milliseconds. Only a real pause can lose starts.
                            $changes = [string]$fields['AuditPolicyChanges']
                            $changed = $logEntry.TimeCreated.ToUniversalTime()
                            if ($changes -match '%%8448') {
                                if ($null -eq $auditOff) { $auditOff = $changed }
                            } elseif ($changes -match '%%8449') {
                                if ($null -ne $auditOff -and ($changed - $auditOff).TotalSeconds -gt 5) { $coverage = $now }
                                $auditOff = $null
                            } elseif ($changes -notmatch '^[\s,]*(%%845[01][\s,]*)+$') {
                                # Failure-only changes do not matter; anything unknown does.
                                $coverage = $now
                            }
                        }
                        if ($logEntry.Id -eq 4688) {
                            $exe = [IO.Path]::GetFileName($fields['NewProcessName']).ToLowerInvariant()
                            if ($watch.ContainsKey($exe)) {
                                $startTime = $logEntry.TimeCreated.ToUniversalTime()
                                if ($startTime -le $now) {
                                    $entry = $apps[$exe]
                                    if ($null -eq $entry.last -or $startTime -gt $entry.last) { $entry.last = $startTime }
                                    # A program that starts copies of itself counts once.
                                    $parent = [IO.Path]::GetFileName([string]$fields['ParentProcessName']).ToLowerInvariant()
                                    if ($parent -ne $exe) {
                                        $key = Get-DayKey $startTime
                                        if ($entry.days.ContainsKey($key)) { $entry.days[$key]++ } else { $entry.days[$key] = 1 }
                                    }
                                }
                            }
                        }
                    } finally { $logEntry.Dispose() }
                }
            } finally { $reader.Dispose() }
            # Still off at the end of the scan: starts may be missing.
            if ($null -ne $auditOff) { $coverage = $now }
            # Detect rollover during collection as well as between runs.
            $oldest = Get-WinEvent -LogName Security -Oldest -MaxEvents 1
            if ([long]$oldest.RecordId -gt ($lower + 1)) { $coverage = $now }
        }
        $firstDay = Get-DayKey $now.AddDays(1 - $WindowDays)
        $saved = @{}
        foreach ($exe in $apps.Keys) {
            $entry = $apps[$exe]
            $days = @{}
            foreach ($key in $entry.days.Keys) { if ($key -ge $firstDay) { $days[$key] = $entry.days[$key] } }
            $entry.days = $days
            $saved[$exe] = @{ first = (ConvertTo-UtcText $entry.first); last = $(if ($entry.last) { ConvertTo-UtcText $entry.last } else { $null }); days = $days }
        }
        $state = @{ version = 1; started = (ConvertTo-UtcText $started); coverage = (ConvertTo-UtcText $coverage); end = (ConvertTo-UtcText $now); record = $upper; recordTime = $newest.TimeCreated.ToUniversalTime().Ticks.ToString(); apps = $saved }
        $temp = Join-Path $folder ('state-' + [Guid]::NewGuid().ToString() + '.tmp')
        try {
            [IO.File]::WriteAllText($temp, ($state | ConvertTo-Json -Depth 5 -Compress), (New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $temp -Destination $stateFile -Force
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    }
} catch {
    # No raw exception, event data or paths are returned to Intune.
    $status = 'error'
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}

if ($status -eq 'audit_off') {
    Write-Output 'Not metering: Audit Process Creation (Success) is off on this device. Enable it through policy; metering starts on the next run.'
    exit 1
}
if ($status -ne 'ok') {
    Write-Output 'Not metering: this run failed. The next scheduled run tries again.'
    exit 2
}

$today = $now.Date
$rows = @(foreach ($exe in $apps.Keys) {
    $entry = $apps[$exe]
    if (-not $entry.last) { continue }
    $window = [Math]::Min($WindowDays, ($today - $entry.first.Date).Days + 1)
    $starts = 0
    foreach ($count in $entry.days.Values) { $starts += $count }
    $usage = if ($entry.days.Count) { "$(Format-Count $starts 'start') on $($entry.days.Count) of $(Format-Count $window 'day')" } else { "no starts in the last $(Format-Count $window 'day')" }
    [pscustomobject]@{ Last = $entry.last; Text = "$exe last $(Format-UtcDisplay $entry.last), $usage" }
})
# Most recent first, so a long result leaves out the oldest starts.
$used = @($rows | Sort-Object Last -Descending | ForEach-Object { $_.Text })
$idle = @(foreach ($exe in ($apps.Keys | Sort-Object)) {
    $entry = $apps[$exe]
    if ($entry.last) { continue }
    # Programs added to the list later say since when they are watched.
    if ($entry.first -gt $started) { "$exe (watched since $(Format-UtcDisplay $entry.first))" } else { $exe }
})

$header = "OK. Watching $($watch.Count) programs since $(Format-UtcDisplay $started)."
if ($coverage -gt $started) { $header += " Some starts before $(Format-UtcDisplay $coverage) may be missing (Security log gap)." }

# Never cut text mid-entry: leave out the oldest entries and say how many.
$usedShown = $used.Count
$idleShown = $idle.Count
while ($true) {
    $output = $header
    if ($used.Count) {
        $items = @($used | Select-Object -First $usedShown)
        if ($usedShown -lt $used.Count) { $items += "+$($used.Count - $usedShown) more" }
        $output += " Used ($($used.Count)): " + ($items -join '; ') + '.'
    }
    if ($idle.Count) {
        $items = @($idle | Select-Object -First $idleShown)
        if ($idleShown -lt $idle.Count) { $items += "+$($idle.Count - $idleShown) more" }
        $output += " Not started ($($idle.Count)): " + ($items -join ', ') + '.'
    }
    if ($output.Length -le $MaxOutput) { break }
    if ($usedShown -gt 0) { $usedShown-- }
    elseif ($idleShown -gt 0) { $idleShown-- }
    else { $output = $output.Substring(0, $MaxOutput); break }
}
Write-Output $output
exit 0
