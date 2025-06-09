<#
.TITLE
    [Brief Title - Detection Script]

.SYNOPSIS
    Detection script to check for [specific compliance issue]

.DESCRIPTION
    This detection script checks whether [describe what is being checked].
    Returns exit code 0 if compliant, 1 if non-compliant (needs remediation).
    
    This script is designed to be used with Intune Proactive Remediations and should
    be paired with the corresponding remediation script.

.TAGS
    Remediation,Detection,Compliance

.REMEDIATIONTYPE
    Detection

.PAIRSCRIPT
    remediation-action-template.ps1

.PLATFORM
    Windows

.MINROLE
    [Minimum Intune role required, e.g., Intune Service Administrator]

.PERMISSIONS
    [List required permissions if using Graph API]

.AUTHOR
    [Your Name]

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial version

.EXAMPLE
    .\remediation-detection-template.ps1
    
    Runs the detection script and returns:
    - Exit code 0 if compliant
    - Exit code 1 if non-compliant

.NOTES
    - This script runs in SYSTEM context by default in Intune
    - Keep detection logic lightweight for performance
    - Output is captured in Intune logs
    - JSON output provides detailed status for troubleshooting
#>

# Detection script configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

# Initialize detection result
$detectionResult = @{
    Status = "Unknown"
    Details = @()
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
}

try {
    Write-Output "Starting detection script..."
    
    #region Pre-flight Checks
    # Add any prerequisite checks here
    # Example: Check if running as SYSTEM or Admin
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Warning "Script is not running with administrative privileges"
    }
    #endregion

    #region Main Detection Logic
    # TODO: Replace this section with your actual detection logic
    # Example detection scenarios:
    
    # Example 1: Check registry value
    <#
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $registryName = "EnableSmartScreen"
    $expectedValue = 1
    
    if (Test-Path $registryPath) {
        $currentValue = Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction SilentlyContinue
        if ($currentValue.$registryName -eq $expectedValue) {
            $isCompliant = $true
            $detectionResult.Details += "Registry value is compliant"
        } else {
            $isCompliant = $false
            $detectionResult.Details += "Registry value is non-compliant. Expected: $expectedValue, Found: $($currentValue.$registryName)"
        }
    } else {
        $isCompliant = $false
        $detectionResult.Details += "Registry path does not exist"
    }
    #>
    
    # Example 2: Check file existence and version
    <#
    $filePath = "C:\Program Files\MyApp\app.exe"
    $minimumVersion = [Version]"2.0.0.0"
    
    if (Test-Path $filePath) {
        $fileVersion = [Version](Get-ItemProperty $filePath).VersionInfo.FileVersion
        if ($fileVersion -ge $minimumVersion) {
            $isCompliant = $true
            $detectionResult.Details += "Application version is compliant: $fileVersion"
        } else {
            $isCompliant = $false
            $detectionResult.Details += "Application version is outdated. Required: $minimumVersion, Found: $fileVersion"
        }
    } else {
        $isCompliant = $false
        $detectionResult.Details += "Application not found at expected location"
    }
    #>
    
    # Example 3: Check service status
    <#
    $serviceName = "Defender"
    $expectedStatus = "Running"
    
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq $expectedStatus) {
            $isCompliant = $true
            $detectionResult.Details += "Service '$serviceName' is in expected state: $expectedStatus"
        } else {
            $isCompliant = $false
            $detectionResult.Details += "Service '$serviceName' is not in expected state. Expected: $expectedStatus, Found: $($service.Status)"
        }
    } else {
        $isCompliant = $false
        $detectionResult.Details += "Service '$serviceName' not found"
    }
    #>
    
    # TODO: Set $isCompliant based on your detection logic
    $isCompliant = $true  # Change this based on actual detection
    
    #endregion

    #region Process Results
    if ($isCompliant) {
        $detectionResult.Status = "Compliant"
        Write-Output "Detection complete: System is compliant"
        
        # Output detailed result as JSON for logging
        $jsonOutput = $detectionResult | ConvertTo-Json -Compress
        Write-Output $jsonOutput
        
        # Exit with code 0 - Compliant, no remediation needed
        exit 0
    }
    else {
        $detectionResult.Status = "Non-Compliant"
        Write-Output "Detection complete: System is non-compliant"
        
        # Add remediation recommendations
        $detectionResult.RemediationRequired = $true
        $detectionResult.RemediationMessage = "System requires remediation to meet compliance requirements"
        
        # Output detailed result as JSON for logging
        $jsonOutput = $detectionResult | ConvertTo-Json -Compress
        Write-Output $jsonOutput
        
        # Exit with code 1 - Non-compliant, remediation needed
        exit 1
    }
    #endregion
}
catch {
    # Capture error details
    $detectionResult.Status = "Error"
    $detectionResult.Error = @{
        Message = $_.Exception.Message
        Type = $_.Exception.GetType().FullName
        StackTrace = $_.ScriptStackTrace
    }
    
    # Output error details
    Write-Error "Detection script failed: $_"
    $jsonOutput = $detectionResult | ConvertTo-Json -Compress
    Write-Output $jsonOutput
    
    # Exit with code 2 - Error during detection
    # Note: Intune may treat this as needing remediation depending on configuration
    exit 2
}