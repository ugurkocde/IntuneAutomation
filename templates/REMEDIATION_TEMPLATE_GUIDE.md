# Remediation Template Guide

This guide provides comprehensive instructions for using the Intune remediation script templates to create detection and remediation script pairs for use with Microsoft Intune Proactive Remediations (formerly known as Proactive Remediations).

## Overview

Remediation scripts in Intune consist of two components:
1. **Detection Script** - Identifies non-compliant conditions
2. **Remediation Script** - Fixes the identified issues

## Template Files

### 1. remediation-detection-template.ps1
Use this template to create detection scripts that:
- Check for specific compliance conditions
- Return appropriate exit codes (0 = compliant, 1 = non-compliant)
- Provide detailed logging for troubleshooting
- Run quickly and efficiently

### 2. remediation-action-template.ps1
Use this template to create remediation scripts that:
- Fix non-compliant conditions identified by the detection script
- Include pre and post-remediation validation
- Provide comprehensive logging
- Handle errors gracefully
- Support rollback when possible

## Exit Code Standards

### Detection Scripts
- **Exit Code 0**: System is compliant, no action needed
- **Exit Code 1**: System is non-compliant, remediation required
- **Exit Code 2**: Error during detection (Intune may treat as non-compliant)

### Remediation Scripts
- **Exit Code 0**: Remediation successful
- **Exit Code 1**: Remediation failed
- **Any other code**: Treated as failure

## Creating a Remediation Script Pair

### Step 1: Define the Compliance Requirement
Clearly identify what condition you're checking and remediating:
- Registry settings
- File presence/version
- Service configuration
- Security settings
- Application installation

### Step 2: Create the Detection Script
1. Copy `remediation-detection-template.ps1`
2. Update the metadata section:
   ```powershell
   .TITLE
       Check BitLocker Encryption Status - Detection
   
   .SYNOPSIS
       Detects if BitLocker encryption is enabled on the system drive
   
   .PAIRSCRIPT
       enable-bitlocker-remediation.ps1
   ```

3. Implement detection logic in the `Main Detection Logic` region:
   ```powershell
   # Check BitLocker status
   $bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
   if ($bitLockerStatus.ProtectionStatus -eq "On") {
       $isCompliant = $true
   } else {
       $isCompliant = $false
   }
   ```

### Step 3: Create the Remediation Script
1. Copy `remediation-action-template.ps1`
2. Update the metadata to match your detection script
3. Implement remediation logic:
   ```powershell
   # Enable BitLocker
   Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes256 -UsedSpaceEncryption
   ```

4. Add verification logic to confirm remediation success

### Step 4: Test the Scripts
1. Test detection script on compliant and non-compliant systems
2. Verify correct exit codes
3. Test remediation script manually
4. Confirm post-remediation detection passes

## Best Practices

### Detection Scripts
1. **Keep it lightweight**: Detection runs frequently, minimize resource usage
2. **Be specific**: Check exactly what you intend to remediate
3. **Handle errors**: Use try-catch blocks and return appropriate exit codes
4. **Log details**: Output helpful information for troubleshooting

### Remediation Scripts
1. **Validate first**: Confirm the issue exists before attempting fixes
2. **Create backups**: Save current state when modifying configurations
3. **Verify success**: Always validate remediation worked
4. **Handle failures**: Implement rollback for critical changes
5. **Document changes**: Log all actions taken

## Common Remediation Scenarios

### 1. Registry Configuration
```powershell
# Detection
$regPath = "HKLM:\SOFTWARE\Policies\Example"
$regName = "Setting"
$expectedValue = 1

$currentValue = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction SilentlyContinue
$isCompliant = ($currentValue -eq $expectedValue)

# Remediation
Set-ItemProperty -Path $regPath -Name $regName -Value $expectedValue -Type DWord -Force
```

### 2. Service Configuration
```powershell
# Detection
$service = Get-Service -Name "ExampleService" -ErrorAction SilentlyContinue
$isCompliant = ($service.Status -eq "Running" -and $service.StartType -eq "Automatic")

# Remediation
Set-Service -Name "ExampleService" -StartupType Automatic
Start-Service -Name "ExampleService"
```

### 3. Application Updates
```powershell
# Detection
$app = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq "Example App"}
$isCompliant = ($app.Version -ge "2.0.0")

# Remediation
Start-Process msiexec.exe -ArgumentList "/i \\server\share\app-v2.msi /quiet" -Wait
```

## Deployment in Intune

1. **Create Remediation**:
   - Navigate to Devices > Scripts and remediations > Remediations
   - Click "+ Create"
   - Provide name and description

2. **Upload Scripts**:
   - Upload detection script
   - Upload remediation script
   - Configure run behavior (32/64-bit, user/system context)

3. **Assignment**:
   - Assign to device groups
   - Configure schedule (once, hourly, daily)
   - Set monitoring thresholds

4. **Monitoring**:
   - View device status
   - Check detection/remediation rates
   - Review error logs

## Testing Guidelines

### Local Testing
```powershell
# Test detection
.\detect-script.ps1
Write-Host "Exit Code: $LASTEXITCODE"

# Test remediation (if detection returns 1)
.\remediate-script.ps1
Write-Host "Exit Code: $LASTEXITCODE"

# Re-run detection to verify
.\detect-script.ps1
Write-Host "Exit Code: $LASTEXITCODE"  # Should be 0
```

### Pilot Testing
1. Create a test device group
2. Deploy to test group first
3. Monitor results for 24-48 hours
4. Review logs and success rates
5. Adjust scripts if needed

## Troubleshooting

### Common Issues

1. **Scripts not running**:
   - Check assignment and schedule
   - Verify device is checking in
   - Review Intune device sync status

2. **Detection always fails**:
   - Test script locally as SYSTEM
   - Check for permissions issues
   - Verify detection logic

3. **Remediation fails**:
   - Check remediation has required permissions
   - Verify prerequisites are met
   - Review error logs in script output

### Logging Locations
- **Intune Logs**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`
- **Script Output**: Available in Intune portal under device details
- **Event Viewer**: Application and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider

## Security Considerations

1. **Least Privilege**: Scripts run as SYSTEM by default, be cautious
2. **Input Validation**: Validate any external data sources
3. **Secure Storage**: Don't hardcode credentials or secrets
4. **Audit Trail**: Log all changes made by remediation
5. **Test Thoroughly**: Ensure scripts don't cause unintended effects

## Examples Repository

For real-world examples, check the `/scripts/remediation/` directory (once created) for:
- BitLocker compliance
- Windows Update settings
- Firewall configuration
- Certificate management
- Application compliance

## Support

For questions or issues:
1. Review script output in Intune portal
2. Check local logs on affected devices
3. Test scripts locally in SYSTEM context
4. Consult Microsoft Intune documentation