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
    1.0

.CHANGELOG
    1.0 - Initial version

.LASTUPDATE
    2025-06-09

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
    # Clean Windows Temp
    Remove-FolderContent "$env:WINDIR\Temp"
    
    # Clean User Temp folders
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-FolderContent "$($_.FullName)\AppData\Local\Temp"
    }
    
    # Empty Recycle Bin
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    # Run Windows Cleanup
    try {
        # Enable cleanup categories
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "StateFlags0100" -Value 2 -Type DWORD -ErrorAction SilentlyContinue
        }
        
        # Run cleanup
        Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:100" -Wait -NoNewWindow
    }
    catch { 
        # Continue if Windows cleanup fails
    }
    
    Write-Output "Disk cleanup completed"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}