<#
.TITLE
    Local Admin Drift Remediation Script

.SYNOPSIS
    Removes unauthorized members from the local Administrators group.

.DESCRIPTION
    Enumerates the local Administrators group and removes every member that is not
    on the allowlist: the built-in Administrator (RID 500), the Entra device
    administrator role SIDs, Domain/Enterprise Admins for hybrid devices, and the
    configurable allowed account names. Removed members are logged in the output so
    the remediation history in Intune shows exactly what changed. Paired with
    detect-local-admin-drift.ps1.

.TAGS
    Remediation,Action

.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-local-admin-drift.ps1

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
    .\remediate-local-admin-drift.ps1
    Removes all unauthorized members from the local Administrators group

.NOTES
    - Runs in SYSTEM context via Intune Remediations
    - Keep $AllowedNames identical to the detection script or the pair will fight each other
    - Removal uses the group's Remove method via ADSI, which also handles orphaned SIDs
    - Test on a pilot group first: removing an account that users rely on locks them out of admin tasks
#>

$ErrorActionPreference = "Stop"

# Account names that are allowed local admins (keep in sync with detection script)
$AllowedNames = @(
    "LocalAdmin"
)

function Get-AdministratorsGroup {
    $adminGroupSid = "S-1-5-32-544"
    $groupName = (Get-LocalGroup -SID $adminGroupSid).Name
    return [ADSI]"WinNT://./$groupName,group"
}

function Test-AllowedMember {
    param([object]$Member)

    if ($Member.Sid -and $Member.Sid -match "-500$") { return $true }
    if ($Member.Sid -and $Member.Sid -like "S-1-12-1-*") { return $true }
    if ($Member.Sid -and ($Member.Sid -match "-512$" -or $Member.Sid -match "-519$")) { return $true }
    if ($AllowedNames -contains $Member.Name) { return $true }

    return $false
}

try {
    $group = Get-AdministratorsGroup

    $members = @($group.Invoke("Members")) | ForEach-Object {
        $adsiMember = [ADSI]$_
        $sid = $null
        try {
            $sidBytes = $adsiMember.InvokeGet("objectSID")
            $sid = (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
        }
        catch {
            # Orphaned entries may not expose a SID
        }
        [PSCustomObject]@{
            Name    = $adsiMember.InvokeGet("Name")
            AdsPath = $adsiMember.InvokeGet("AdsPath")
            Sid     = $sid
        }
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($member in @($members)) {
        if (Test-AllowedMember -Member $member) { continue }

        try {
            $group.Remove($member.AdsPath)
            $removed.Add($member.Name)
        }
        catch {
            $failed.Add("$($member.Name): $($_.Exception.Message)")
        }
    }

    if ($removed.Count -gt 0) {
        Write-Output "Removed from local Administrators: $($removed -join ', ')"
    }
    else {
        Write-Output "No unauthorized members needed removal."
    }

    if ($failed.Count -gt 0) {
        Write-Output "Failed to remove: $($failed -join ' | ')"
        exit 1
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
