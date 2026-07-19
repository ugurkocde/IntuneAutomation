<#
.TITLE
    Disk Cleanup Remediation Script

.SYNOPSIS
    Cleans temporary files and empties recycle bin

.DESCRIPTION
    Removes Windows temp files, user temp files, and empties the recycle bin.
    Also runs Windows disk cleanup utility.

.TAGS
    Remediation,Action
    
.REMEDIATIONTYPE
    Remediation

.PAIRSCRIPT
    detect-disk-cleanup-needed.ps1

.PLATFORM
    Windows

.MINROLE
    Intune Service Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All

.AUTHOR
    Ugur Koc

.VERSION
    1.1

.CHANGELOG
    1.1 - Added freed space reporting, per-target failure tracking with all-failed exit 1, and cleanmgr timeout handling
    1.0 - Initial version

.LASTUPDATE
    2026-07-19

.EXAMPLE
    .\remediate-disk-cleanup.ps1

.NOTES
    Runs in SYSTEM context
#>

$ErrorActionPreference = "Stop"

function Remove-FolderContent {
    param([string]$Path)
    
    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | 
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    $targetCount = 0
    $failedCount = 0
    $freeBefore = (Get-PSDrive C).Free

    # Clean Windows Temp
    $targetCount++
    try {
        Remove-FolderContent "$env:WINDIR\Temp"
    }
    catch { $failedCount++ }

    # Clean User Temp folders
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $targetCount++
        try {
            Remove-FolderContent "$($_.FullName)\AppData\Local\Temp"
        }
        catch { $failedCount++ }
    }

    # Empty Recycle Bin
    $targetCount++
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
    }
    catch { $failedCount++ }

    # Run Windows Cleanup
    $targetCount++
    try {
        # Enable cleanup categories
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "StateFlags0100" -Value 2 -Type DWORD -ErrorAction SilentlyContinue
        }

        # Run cleanup with timeout so a hung cleanmgr does not block remediation
        $cleanmgrProcess = Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:100" -NoNewWindow -PassThru
        Wait-Process -Id $cleanmgrProcess.Id -Timeout 300 -ErrorAction Stop
    }
    catch {
        # Stop cleanmgr if it is still running, count as failure and continue
        if ($cleanmgrProcess -and -not $cleanmgrProcess.HasExited) {
            Stop-Process -Id $cleanmgrProcess.Id -Force -ErrorAction SilentlyContinue
        }
        $failedCount++
    }

    $freeAfter = (Get-PSDrive C).Free
    $freedMB = [math]::Round(($freeAfter - $freeBefore) / 1MB, 2)
    Write-Output "Freed space: $freedMB MB"

    if ($failedCount -ge $targetCount) {
        Write-Error "All $targetCount cleanup targets failed"
        exit 1
    }

    Write-Output "Disk cleanup completed ($($targetCount - $failedCount) of $targetCount targets succeeded)"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}