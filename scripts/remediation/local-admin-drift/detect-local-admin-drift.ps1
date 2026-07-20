<#
.TITLE
    Local Admin Drift Detection Script

.SYNOPSIS
    Detects unauthorized members of the local Administrators group.

.DESCRIPTION
    Enumerates the local Administrators group and compares every member against an
    allowlist of approved accounts and well-known SIDs (built-in Administrator, the
    Entra-joined device admin roles, and configurable extra entries). Returns exit
    code 1 when unauthorized members are present, triggering the paired remediation
    that removes them. This catches technician accounts, self-elevation leftovers,
    and helpdesk additions that were never cleaned up.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-local-admin-drift.ps1

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
    2026-07-20

.EXAMPLE
    .\detect-local-admin-drift.ps1
    Returns exit 1 if the local Administrators group contains unauthorized members

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - Keep $AllowedNames in sync with the remediation script; add your LAPS-managed admin account name there
    - The built-in Administrator (RID 500) and the Entra device administrator role SIDs (S-1-12-1-...) are always allowed
    - Uses ADSI enumeration because Get-LocalGroupMember fails on orphaned SIDs
#>

$ErrorActionPreference = "Stop"

# Account names that are allowed local admins (keep in sync with remediation script)
$AllowedNames = @(
    "LocalAdmin"
)

function Get-AdministratorsGroupMember {
    # ADSI enumeration handles orphaned SIDs that break Get-LocalGroupMember
    $adminGroupSid = "S-1-5-32-544"
    $group = [ADSI]"WinNT://./$((Get-LocalGroup -SID $adminGroupSid).Name),group"

    $members = @($group.Invoke("Members")) | ForEach-Object {
        $path = ([ADSI]$_).InvokeGet("AdsPath")
        $name = ([ADSI]$_).InvokeGet("Name")
        $sid = $null
        try {
            $sidBytes = ([ADSI]$_).InvokeGet("objectSID")
            $sid = (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
        }
        catch {
            # Orphaned entries may not expose a SID - fall back to the path
        }
        [PSCustomObject]@{ Name = $name; Path = $path; Sid = $sid }
    }

    return @($members)
}

function Test-AllowedMember {
    param([object]$Member)

    # Built-in Administrator account (RID 500) is always allowed
    if ($Member.Sid -and $Member.Sid -match "-500$") { return $true }

    # Entra role SIDs (Global Administrator / Azure AD Joined Device Local Admin)
    # are provisioned by the join process and always allowed
    if ($Member.Sid -and $Member.Sid -like "S-1-12-1-*") { return $true }

    # Domain Admins / Enterprise Admins for hybrid-joined devices
    if ($Member.Sid -and ($Member.Sid -match "-512$" -or $Member.Sid -match "-519$")) { return $true }

    if ($AllowedNames -contains $Member.Name) { return $true }

    return $false
}

try {
    $members = Get-AdministratorsGroupMember

    $unauthorized = @($members | Where-Object { -not (Test-AllowedMember -Member $_) })

    if ($unauthorized.Count -eq 0) {
        Write-Output "Local Administrators group contains only approved members ($($members.Count) total)."
        exit 0
    }

    $names = ($unauthorized | ForEach-Object { $_.Name }) -join ", "
    Write-Output "Unauthorized local administrators found: $names"
    exit 1
}
catch {
    Write-Error $_
    exit 2
}
