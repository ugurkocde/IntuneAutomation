# Notification Scripts

This folder contains PowerShell scripts designed specifically for Azure Automation runbooks to send proactive notifications about important Intune management events. These scripts are **runbook-only** and use Microsoft Graph Mail API exclusively for email notifications.

## 📧 Available Scripts

### Apple Token Expiration Alert (`apple-token-expiration-alert.ps1`)

Monitors Apple DEP tokens and APNS certificates for expiration and sends email alerts when tokens are approaching expiration or have expired.

**Key Features:**
- Monitors Apple DEP tokens and APNS certificates
- Configurable notification threshold (days before expiration)
- HTML formatted email reports with critical/warning status
- Uses Microsoft Graph Mail API exclusively
- Supports both Azure Automation and local execution

### Stale Device Cleanup Alert (`stale-device-cleanup-alert.ps1`)

Monitors devices that haven't checked in for a specified number of days and sends cleanup recommendations to administrators.

**Key Features:**
- Monitors device last check-in times across all platforms
- Configurable staleness threshold (days since last check-in)
- Platform-specific device categorization (Windows, iOS, Android, macOS)
- Cleanup recommendations and licensing impact analysis
- Warning notifications for devices approaching staleness threshold
- HTML formatted email reports with device inventory details

### Device Compliance Drift Alert (`device-compliance-drift-alert.ps1`)

Monitors device compliance status and sends alerts when compliance falls below threshold or when compliance issues are detected.

**Key Features:**
- Monitors device compliance status across all platforms
- Configurable compliance percentage threshold
- Tracks compliance trends and deterioration patterns
- Identifies non-compliant, conflict, error, and grace period devices
- Platform and policy-specific compliance analysis
- Visual compliance meter in email reports
- Compliance improvement recommendations

### App Deployment Failure Alert (`app-deployment-failure-alert.ps1`)

Monitors application deployment status and sends alerts when deployment failure rates exceed acceptable thresholds.

**Key Features:**
- Monitors application deployment success/failure rates
- Configurable failure percentage threshold
- Prioritizes required application failures (critical impact)
- Application type and platform-specific analysis
- Visual failure rate meters and progress bars
- Deployment improvement recommendations
- Tracks Win32, Store, Web, and mobile app deployments

## 🚀 Quick Setup Guide

### Prerequisites

1. **Azure Automation Account** with Managed Identity enabled
2. **Required PowerShell Modules** in your Automation Account:
   - `Microsoft.Graph.Authentication`
   - `Microsoft.Graph.Mail`
3. **Microsoft Graph Permissions** assigned to the Managed Identity

### Step 1: Deploy the Runbook

Use the Azure deployment template to automatically deploy the runbook:

```bash
# Deploy using Azure CLI
az deployment group create \
  --resource-group "your-rg" \
  --template-file "../azure-templates/apple-token-expiration-alert-azure-deployment.json" \
  --parameters \
    automationAccountName="your-automation-account" \
    notificationDays=30 \
    emailRecipients="admin@company.com,security@company.com"
```

### Step 2: Install Required Modules

In your Azure Automation Account:

1. Go to **Modules** > **Browse Gallery**
2. Search and install these modules:
   - `Microsoft.Graph.Authentication`
   - `Microsoft.Graph.Mail`
3. Wait for installation to complete (this can take 10-15 minutes)

### Step 3: Grant Permissions to Managed Identity

Run the provided permission script to grant the necessary Microsoft Graph permissions:

```powershell
# Run this from the root of the repository
.\grant-permissions-managed-identity.ps1 -AutomationAccountName "your-automation-account" -ResourceGroupName "your-rg"
```

**Required Permissions:**

**For Apple Token Expiration Alert:**
- `DeviceManagementServiceConfig.Read.All` - Read DEP tokens and APNS certificates
- `DeviceManagementConfiguration.Read.All` - Read device management configuration
- `Mail.Send` - Send emails via Microsoft Graph

**For Stale Device Cleanup Alert:**
- `DeviceManagementManagedDevices.Read.All` - Read managed device information
- `Mail.Send` - Send emails via Microsoft Graph

**For Device Compliance Drift Alert:**
- `DeviceManagementManagedDevices.Read.All` - Read managed device information
- `DeviceManagementConfiguration.Read.All` - Read compliance policies
- `Mail.Send` - Send emails via Microsoft Graph

**For App Deployment Failure Alert:**
- `DeviceManagementApps.Read.All` - Read application information and deployment status
- `DeviceManagementManagedDevices.Read.All` - Read managed device information
- `Mail.Send` - Send emails via Microsoft Graph

### Step 4: Test the Runbook

1. Navigate to your Automation Account in Azure Portal
2. Go to **Runbooks** > **apple-token-expiration-alert**
3. Click **Test pane**
4. Provide test parameters:
   - **NotificationDays**: `30`
   - **EmailRecipients**: `your-email@company.com`
5. Click **Start** to test

## 📋 Script Parameters

### Apple Token Expiration Alert

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `NotificationDays` | int | Yes | Days before expiration to trigger alerts | `30` |
| `EmailRecipients` | string | Yes | Comma-separated email addresses | `"admin@company.com,security@company.com"` |

**Minimal Example:**
```powershell
.\apple-token-expiration-alert.ps1 -NotificationDays 30 -EmailRecipients "admin@company.com"
```

### Stale Device Cleanup Alert

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `StaleAfterDays` | int | Yes | Days since last check-in to consider device stale | `90` |
| `EmailRecipients` | string | Yes | Comma-separated email addresses | `"admin@company.com,security@company.com"` |

**Minimal Example:**
```powershell
.\stale-device-cleanup-alert.ps1 -StaleAfterDays 90 -EmailRecipients "admin@company.com"
```

### Device Compliance Drift Alert

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `ComplianceThresholdPercent` | int | Yes | Minimum compliance percentage to trigger alerts | `85` |
| `EmailRecipients` | string | Yes | Comma-separated email addresses | `"admin@company.com,security@company.com"` |

**Minimal Example:**
```powershell
.\device-compliance-drift-alert.ps1 -ComplianceThresholdPercent 85 -EmailRecipients "admin@company.com"
```

### App Deployment Failure Alert

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `FailureThresholdPercent` | int | Yes | Maximum acceptable failure percentage for app deployments | `20` |
| `EmailRecipients` | string | Yes | Comma-separated email addresses | `"admin@company.com,appsupport@company.com"` |

**Minimal Example:**
```powershell
.\app-deployment-failure-alert.ps1 -FailureThresholdPercent 20 -EmailRecipients "admin@company.com"
```

## 🔧 Configuration

### Scheduling

The Azure deployment template automatically creates a schedule that runs daily. You can modify the schedule in Azure Portal:

1. Go to **Automation Account** > **Schedules**
2. Edit **apple-token-expiration-daily-check**
3. Adjust frequency, time zone, and start time as needed

### Email Customization

The script automatically generates HTML emails with:
- **Critical Issues**: Expired or invalid tokens (red)
- **Warnings**: Tokens expiring within threshold (yellow)
- **Summary**: Total counts and health status
- **Next Steps**: Actionable guidance for token renewal

### Notification Thresholds

**Apple Token Expiration Alert:**
Choose appropriate notification days based on your renewal process:
- **7 days**: Last-minute alerts for critical environments
- **30 days**: Standard notice period for planning renewals
- **60 days**: Early warning for complex renewal processes

**Stale Device Cleanup Alert:**
Choose appropriate staleness thresholds based on your organization's device usage patterns:
- **30 days**: Aggressive cleanup for highly managed environments
- **60 days**: Standard threshold for most organizations
- **90 days**: Conservative approach for flexible work environments
- **180 days**: Extended threshold for seasonal workers or long-term projects

**Device Compliance Drift Alert:**
Choose appropriate compliance thresholds based on your security requirements:
- **95%**: High-security environments requiring strict compliance
- **90%**: Standard threshold for most organizations
- **85%**: Balanced approach allowing for some normal drift
- **80%**: Relaxed threshold for environments with complex compliance requirements

**App Deployment Failure Alert:**
Choose appropriate failure thresholds based on your application deployment requirements:
- **10%**: Strict threshold for critical business applications
- **15%**: Standard threshold for most organizations
- **20%**: Balanced approach for mixed application portfolios
- **25%**: Relaxed threshold for environments with complex application dependencies

## 🛠️ Troubleshooting

### Common Issues

#### 1. Module Not Found Error
```
Module 'Microsoft.Graph.Mail' is not available in this Azure Automation Account.
```

**Solution:**
- Install the missing module in Azure Portal > Automation Account > Modules > Browse Gallery
- Wait for installation to complete before testing

#### 2. Permission Denied Error
```
Insufficient privileges to complete the operation.
```

**Solution:**
- Run the `grant-permissions-managed-identity.ps1` script
- Ensure all required permissions are granted to the Managed Identity
- Wait 5-10 minutes for permissions to propagate

#### 3. Authentication Failed
```
Failed to connect to Microsoft Graph: The provided authentication credentials are invalid.
```

**Solution:**
- Ensure Managed Identity is enabled on your Automation Account
- Verify the runbook is running in Azure Automation (not locally)
- Check that the Managed Identity has the required permissions

#### 4. No Tokens Found
```
Found 0 DEP token entries
```

**Possible Causes:**
- No Apple DEP tokens configured in Intune
- Insufficient permissions to read device management configuration
- Network connectivity issues

#### 5. No Devices Found (Stale Device Script)
```
Found 0 managed devices
```

**Possible Causes:**
- No devices enrolled in Intune
- Insufficient permissions to read managed devices
- All devices are actively checking in (no stale devices)

#### 6. Compliance Data Issues (Compliance Drift Script)
```
Found 0 compliance policies
```

**Possible Causes:**
- No compliance policies configured in Intune
- Insufficient permissions to read compliance policies
- All devices are compliant (no compliance issues)

#### 7. Application Data Issues (App Deployment Script)
```
Found 0 applications
```

**Possible Causes:**
- No applications deployed in Intune
- Insufficient permissions to read application data
- All applications are deploying successfully (no failures above threshold)

### Manual Permission Grant

If the automated script doesn't work, manually grant permissions:

```powershell
# Connect to Microsoft Graph as Global Administrator
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Get the Managed Identity
$managedIdentity = Get-MgServicePrincipal -Filter "displayName eq 'your-automation-account'"

# Grant permissions
$permissions = @(
    "DeviceManagementServiceConfig.Read.All",
    "DeviceManagementConfiguration.Read.All", 
    "Mail.Send"
)

foreach ($permission in $permissions) {
    $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
    $appRole = $graphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $permission }
    
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentity.Id -PrincipalId $managedIdentity.Id -ResourceId $graphServicePrincipal.Id -AppRoleId $appRole.Id
}
```

## 📊 Monitoring and Maintenance

### Runbook Execution Monitoring

Monitor runbook execution in Azure Portal:
1. Go to **Automation Account** > **Jobs**
2. Filter by runbook name
3. Review execution logs and any errors

### Regular Maintenance Tasks

1. **Monthly**: Review notification thresholds and adjust as needed
2. **Quarterly**: Test email delivery and verify recipient lists
3. **Quarterly**: Review stale device cleanup recommendations and action them
4. **Quarterly**: Analyze compliance trends and adjust policies as needed
5. **Quarterly**: Review application deployment success rates and optimize problematic apps
6. **Annually**: Review and update Microsoft Graph permissions
7. **Annually**: Analyze device usage patterns and adjust staleness thresholds
8. **Annually**: Review compliance thresholds and organizational security requirements
9. **Annually**: Evaluate application deployment strategies and failure thresholds

### Log Analysis

Check runbook logs for:
- **Information**: Normal execution flow and token counts
- **Warnings**: Non-critical issues like missing optional data
- **Errors**: Authentication failures or critical script errors

## 🔒 Security Considerations

### Managed Identity Best Practices

1. **Principle of Least Privilege**: Only grant required permissions
2. **Regular Audits**: Review assigned permissions quarterly
3. **Access Monitoring**: Monitor Managed Identity usage in Azure AD logs

### Email Security

1. **Recipient Validation**: Verify email addresses before deployment
2. **Content Review**: Emails contain tenant-specific information
3. **Delivery Monitoring**: Ensure emails reach intended recipients

### Token Security

1. **Access Logs**: Monitor who accesses Apple token information
2. **Rotation Planning**: Plan token renewals before expiration
3. **Backup Procedures**: Document token renewal processes

## 📚 Additional Resources

- [Azure Automation Runbooks Documentation](https://docs.microsoft.com/en-us/azure/automation/automation-runbook-execution)
- [Microsoft Graph Mail API](https://docs.microsoft.com/en-us/graph/api/user-sendmail)
- [Intune Apple Device Management](https://docs.microsoft.com/en-us/mem/intune/enrollment/device-enrollment-program-enroll-ios)
- [Azure Managed Identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

## 🤝 Contributing

When adding new notification scripts to this folder:

1. **Follow the Template**: Use the existing script structure and patterns
2. **Graph API Only**: Only use Microsoft Graph API for external communications
3. **Minimal Parameters**: Keep required parameters to a minimum
4. **Error Handling**: Implement comprehensive error handling and logging
5. **Documentation**: Update this README with script details and setup instructions

For questions or issues, please refer to the main repository documentation or open an issue.