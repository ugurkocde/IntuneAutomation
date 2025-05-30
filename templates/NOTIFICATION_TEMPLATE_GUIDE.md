# Notification Script Template Guide

This template provides a comprehensive foundation for creating your own notification scripts that monitor specific aspects of your Microsoft Intune environment and send email alerts when conditions are met.

## 🎯 What This Template Provides

- **Complete notification script structure** following project standards
- **Azure Automation optimized** with Managed Identity support
- **Professional HTML email templates** with responsive design
- **Comprehensive error handling** and logging
- **Rate limiting and pagination** for Microsoft Graph API calls
- **Configurable thresholds and filtering** options
- **Detailed documentation** and examples

## 📋 Prerequisites

Before using this template, ensure you have:

1. **Azure Automation Account** with Managed Identity enabled
2. **Required PowerShell modules** installed in your Automation Account:
   - `Microsoft.Graph.Authentication`
   - `Microsoft.Graph.Mail`
   - Additional modules based on what you're monitoring
3. **Microsoft Graph permissions** assigned to your Managed Identity
4. **Basic PowerShell knowledge** for customization

## 🚀 Quick Start Guide

### Step 1: Copy and Rename the Template

1. Copy `notification-script-template.ps1` to a new file
2. Rename it to describe your monitoring purpose (e.g., `certificate-expiration-alert.ps1`)
3. Update the script header with your specific information

### Step 2: Customize the Header

Update these sections in the comment header:

```powershell
.TITLE
    Your Custom Notification Script Title

.SYNOPSIS
    Brief description of what your script monitors

.DESCRIPTION
    Detailed description of your monitoring logic

.TAGS
    Notification,YourCategory,RunbookOnly,Email,Monitoring,SpecificTags

.PERMISSIONS
    Your.Required.Graph.Permissions,Mail.Send
```

### Step 3: Define Your Parameters

Customize the script parameters based on what you need to monitor:

```powershell
param(
    # Your main threshold parameter
    [Parameter(Mandatory = $true)]
    [int]$ThresholdParameter,
    
    # Always keep email recipients
    [Parameter(Mandatory = $true)]
    [string]$EmailRecipients,
    
    # Add additional parameters as needed
    [Parameter(Mandatory = $false)]
    [string]$AdditionalFilter = "DefaultValue"
)
```

### Step 4: Implement Your Monitoring Logic

The main areas to customize are:

#### A. Update Required Modules and Permissions

```powershell
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Mail",
    "Microsoft.Graph.DeviceManagement"  # Add modules you need
)

# Update scopes for local testing
$Scopes = @(
    "DeviceManagementManagedDevices.Read.All",  # Your required permissions
    "Mail.Send"
)
```

#### B. Customize the `Get-MonitoringData` Function

Replace the sample monitoring logic with your specific API calls:

```powershell
function Get-MonitoringData {
    param([hashtable]$Config)
    
    # Example: Monitor device compliance
    $Devices = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=complianceState ne 'compliant'"
    
    # Example: Monitor certificate expiration
    $Certificates = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
    
    # Process and return your monitoring data
    return $ProcessedData
}
```

#### C. Customize the `Get-AlertAnalysis` Function

Define your specific alert criteria:

```powershell
function Get-AlertAnalysis {
    param([array]$MonitoringData, [hashtable]$Config)
    
    foreach ($Item in $MonitoringData) {
        # Your specific alert logic
        if ($Item.SomeProperty -gt $Config.ThresholdValue) {
            # Create alert
            $AlertData += [PSCustomObject]@{
                Title = "Alert: $($Item.Name)"
                Details = "Your specific alert details"
                Level = "Critical"  # or "Warning"
            }
        }
    }
    
    return @{ AlertData = $AlertData; Summary = $Summary }
}
```

#### D. Customize the Email Template

Update the `New-EmailBody` function to include relevant information for your monitoring type:

```powershell
function New-EmailBody {
    # Customize the HTML template
    # Add specific sections for your monitoring data
    # Include relevant charts, tables, or metrics
    # Provide specific recommendations
}
```

### Step 5: Test Your Script

1. **Test locally first** with your own credentials:
   ```powershell
   .\your-notification-script.ps1 -ThresholdParameter 10 -EmailRecipients "yourtestemail@domain.com"
   ```

2. **Deploy to Azure Automation** and test with Managed Identity

3. **Create a schedule** for automated execution

## 🎨 Customization Examples

### Example 1: Certificate Expiration Monitoring

```powershell
# Monitor certificates expiring within threshold days
function Get-MonitoringData {
    $Certificates = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
    $ExpiringCerts = @()
    
    foreach ($Cert in $Certificates) {
        if ($Cert.expiryDate) {
            $DaysUntilExpiry = (([DateTime]$Cert.expiryDate) - (Get-Date)).Days
            if ($DaysUntilExpiry -le $Config.ThresholdValue) {
                $ExpiringCerts += [PSCustomObject]@{
                    Name = $Cert.displayName
                    ExpiryDate = $Cert.expiryDate
                    DaysRemaining = $DaysUntilExpiry
                    Status = if ($DaysUntilExpiry -le 0) { "Critical" } else { "Warning" }
                }
            }
        }
    }
    
    return $ExpiringCerts
}
```

### Example 2: Application Deployment Failure Monitoring

```powershell
function Get-MonitoringData {
    $Apps = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
    $FailedDeployments = @()
    
    foreach ($App in $Apps) {
        $InstallSummary = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$($App.id)/installSummary"
        
        $FailureRate = if ($InstallSummary.installedDeviceCount -gt 0) {
            ($InstallSummary.failedDeviceCount / ($InstallSummary.installedDeviceCount + $InstallSummary.failedDeviceCount)) * 100
        } else { 0 }
        
        if ($FailureRate -gt $Config.ThresholdValue) {
            $FailedDeployments += [PSCustomObject]@{
                Name = $App.displayName
                FailureRate = [math]::Round($FailureRate, 2)
                FailedDevices = $InstallSummary.failedDeviceCount
                TotalDevices = $InstallSummary.installedDeviceCount + $InstallSummary.failedDeviceCount
                Status = if ($FailureRate -gt 50) { "Critical" } else { "Warning" }
            }
        }
    }
    
    return $FailedDeployments
}
```

## 📊 Email Template Customization

The template includes a professional HTML email template. Customize these sections:

### 1. Header and Branding
```html
<div class="header">
    <h1>🔔 Your Custom Alert Title</h1>
    <div class="subtitle">Your custom subtitle</div>
</div>
```

### 2. Summary Cards
Add relevant metrics for your monitoring type:
```html
<div class="summary-card">
    <h3>Your Metric</h3>
    <div class="value">$($Summary.YourValue)</div>
    <div class="label">Your Description</div>
</div>
```

### 3. Alert Sections
Customize how alerts are displayed:
```html
<div class="alert-item critical">
    <div class="item-title">$($Item.YourTitle)</div>
    <div class="item-details">$($Item.YourDetails)</div>
</div>
```

### 4. Recommendations
Provide specific guidance for your alert type:
```html
<div class="recommendations">
    <h3>📋 Recommended Actions</h3>
    <ul>
        <li>Your specific recommendation 1</li>
        <li>Your specific recommendation 2</li>
    </ul>
</div>
```

## 🔧 Configuration Options

The template supports various configuration options:

### Email Configuration
```powershell
$EmailConfig = @{
    Subject = "Your Custom Subject Line"
    FromAddress = "noreply@yourdomain.com"
    Priority = "High"  # Low, Normal, High
}
```

### Monitoring Configuration
```powershell
$MonitoringConfig = @{
    ThresholdValue = $ThresholdParameter
    PlatformFilter = $PlatformFilter
    # Add custom configuration options
    WarningThreshold = $ThresholdParameter + 10
    CriticalThreshold = $ThresholdParameter
}
```

## 🚀 Deployment Guide

### 1. Azure Automation Setup

1. **Create/Upload Script**: Upload your customized script to Azure Automation
2. **Install Modules**: Ensure required Graph modules are installed
3. **Configure Managed Identity**: Enable and configure with required permissions
4. **Create Schedule**: Set up automated execution schedule
5. **Test Execution**: Run manually first to verify functionality

### 2. Required Permissions

Grant these permissions to your Managed Identity (customize based on your needs):

- `Mail.Send` (always required for notifications)
- `DeviceManagementManagedDevices.Read.All` (for device monitoring)
- `DeviceManagementConfiguration.Read.All` (for configuration monitoring)
- `DeviceManagementApps.Read.All` (for application monitoring)
- Additional permissions based on your specific monitoring needs

### 3. Scheduling Recommendations

- **Daily**: For critical monitoring (compliance, security)
- **Weekly**: For trending analysis (stale devices, certificate expiration)
- **Monthly**: For long-term planning (license optimization)

## 🔍 Troubleshooting

### Common Issues

1. **Module Not Found**
   - Ensure required modules are installed in Azure Automation
   - Check module versions and compatibility

2. **Permission Denied**
   - Verify Managed Identity has required Graph permissions
   - Check permission scope and application vs delegated permissions

3. **Email Not Sending**
   - Verify `Mail.Send` permission is granted
   - Check email addresses are valid
   - Review error logs in Azure Automation

4. **No Data Retrieved**
   - Verify Graph API endpoints are correct
   - Check filtering logic and parameters
   - Ensure data exists to monitor

### Debugging Tips

1. **Enable Verbose Logging**:
   ```powershell
   Write-Information "Debug info: $($Variable | ConvertTo-Json)" -InformationAction Continue
   ```

2. **Test API Calls Separately**:
   ```powershell
   $TestData = Invoke-MgGraphRequest -Uri "your-endpoint" -Method GET
   ```

3. **Validate Email Template**:
   Save email body to file and open in browser for visual verification

## 📚 Additional Resources

- [Microsoft Graph PowerShell SDK Documentation](https://docs.microsoft.com/en-us/powershell/microsoftgraph/)
- [Azure Automation Runbooks](https://docs.microsoft.com/en-us/azure/automation/automation-runbook-execution)
- [Microsoft Graph API Reference](https://docs.microsoft.com/en-us/graph/api/overview)
- [Intune Graph API Examples](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview)

## 🤝 Contributing

When you create a notification script using this template:

1. **Test thoroughly** in your environment
2. **Document your customizations** clearly
3. **Consider contributing back** your script as an example
4. **Share feedback** on template improvements

## 📝 Template Checklist

Before deploying your notification script:

- [ ] Updated script header with your information
- [ ] Customized monitoring logic for your use case
- [ ] Updated required modules and permissions
- [ ] Customized email template and styling
- [ ] Added specific alert criteria and thresholds
- [ ] Tested locally with your credentials
- [ ] Deployed and tested in Azure Automation
- [ ] Configured appropriate schedule
- [ ] Documented your customizations
- [ ] Set up monitoring for the script itself

## 🎯 Success Criteria

Your notification script should:

- ✅ **Monitor specific conditions** relevant to your environment
- ✅ **Send actionable alerts** with clear next steps
- ✅ **Run reliably** on schedule without manual intervention
- ✅ **Handle errors gracefully** with appropriate logging
- ✅ **Provide value** by preventing issues or reducing response time
- ✅ **Follow security best practices** with minimal required permissions

Happy monitoring! 🎉