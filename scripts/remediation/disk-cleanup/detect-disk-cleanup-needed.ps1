<#
.TITLE
    Disk Cleanup Detection Script

.SYNOPSIS
    Detects if system requires disk cleanup based on temp file accumulation

.DESCRIPTION
    Checks Windows temp folders and recycle bin size.
    Returns exit code 1 if more than 1GB can be cleaned up.

.TAGS
    Remediation,Detection

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediate-disk-cleanup.ps1

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
    1.0 - Initial version

.LASTUPDATE
    2025-06-09

.EXAMPLE
    .\detect-disk-cleanup-needed.ps1

.NOTES
    Runs in SYSTEM context
#>

$ErrorActionPreference = "Stop"
$threshold = 1GB

function Get-FolderSize {
    param([string]$Path)
    
    if (Test-Path $Path) {
        try {
            $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum).Sum
            return if ($null -eq $size) { 0 } else { $size }
        }
        catch { return 0 }
    }
    return 0
}

try {
    $totalSize = 0
    
    # Windows Temp
    $totalSize += Get-FolderSize "$env:WINDIR\Temp"
    
    # User Temp folders
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $totalSize += Get-FolderSize "$($_.FullName)\AppData\Local\Temp"
    }
    
    # Recycle Bin
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.NameSpace(0xA).Items() | ForEach-Object {
            $totalSize += $_.ExtendedProperty("Size")
        }
    }
    catch { 
        # Silently continue if unable to access recycle bin
    }
    
    Write-Output "Cleanable space: $([math]::Round($totalSize / 1GB, 2)) GB"
    
    if ($totalSize -gt $threshold) {
        exit 1
    }
    exit 0
}
catch {
    Write-Error $_
    exit 2
}