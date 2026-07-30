# Azure Automation Deployment Guide

This guide explains how to deploy IntuneAutomation scripts as Azure Automation runbooks using the one-click deployment feature.

The current templates reuse an existing Automation account by default, link the runbook to a PowerShell 7.4 Runtime Environment, and import `Microsoft.Graph.Authentication`. The location field is used only when **Create Automation Account** is set to `true`.

## 🚀 Quick Start

1. Visit [intuneautomation.com](https://intuneautomation.com)
2. Browse to any script detail page
3. Click the **"Deploy to Azure"** button
4. Follow the Azure portal deployment wizard

## 📋 Prerequisites

### Azure Automation Account Setup

1. **Choose an existing Automation Account**, or create one if needed

   ```bash
   az automation account create \
     --resource-group "rg-automation" \
     --name "aa-intune-automation" \
     --location "East US"
   ```

2. **Enable System-assigned Managed Identity**

   - Go to your Automation Account in Azure portal
   - Navigate to **Identity** > **System assigned**
   - Set Status to **On** and save

3. **Verify the Runtime Environment**
   - The deployment creates or updates `IntuneAutomation-PS74`
   - Verify `Microsoft.Graph.Authentication` reaches a successful provisioning state

### Microsoft Graph Permissions

Assign the required permissions to your Automation Account's Managed Identity:

Managed identity Graph app roles are assigned through Microsoft Graph. Use the repository permission script or Cloud Shell, then verify the service principal under **Microsoft Entra ID > Enterprise applications > Permissions**.

#### Using PowerShell

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"

# Get the Managed Identity
$automationAccount = "aa-intune-automation"
$managedIdentity = Get-MgServicePrincipal -Filter "displayName eq '$automationAccount'"

# Get Microsoft Graph service principal
$graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Exact permissions copied from the selected script's .PERMISSIONS metadata
$permissions = @(
    "Permission.From.Script.Metadata"
)

foreach ($permission in $permissions) {
    $appRole = $graphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $permission }
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $managedIdentity.Id `
        -PrincipalId $managedIdentity.Id `
        -ResourceId $graphServicePrincipal.Id `
        -AppRoleId $appRole.Id
}
```

## 🔄 How Dual Environment Support Works

All scripts automatically detect their execution environment:

```powershell
# Environment detection
if ($PSPrivateMetadata.JobId.Guid) {
    Write-Output "Running inside Azure Automation Runbook"
    $IsRunbook = $true
} else {
    Write-Output "Running locally in IDE or terminal"
    $IsRunbook = $false
}

# Smart authentication
if ($IsRunbook) {
    # Azure Automation - Use Managed Identity
    Connect-MgGraph -Identity -NoWelcome
} else {
    # Local execution - Use interactive authentication
    Connect-MgGraph -Scopes $Scopes -NoWelcome
}
```

## 📝 Deployment Process

### Step 1: Click Deploy to Azure

The website generates an ARM template and redirects you to Azure portal.

### Step 2: Configure Deployment Parameters

In the Azure portal deployment form:

#### **Important: Resource Group Selection**

- **Select the resource group** that contains your existing Automation Account
- ⚠️ **Do NOT create a new resource group** unless you want to create a new Automation Account

#### **Automation Account Name**

- **Enter the exact name** of your existing Automation Account
- ❌ **No dropdown available** - you must type the name manually
- ✅ **Case sensitive** - ensure exact spelling and capitalization
- Leave **Create Automation Account** set to `false`
- **New Automation Account Location** is ignored when an existing account is reused

#### **Runbook Name**

- **Customize if needed** (defaults to script name)
- This will be the name of the new runbook created in your Automation Account

#### **Example Configuration:**

```
Subscription: Production Subscription
Resource Group: rg-automation (where your Automation Account exists)
Automation Account Name: aa-intune-automation (your existing account)
Runbook Name: rotate-bitlocker-keys (or customize)
```

### Step 3: Deploy

- Click **Review + create**
- Verify all parameters are correct
- Click **Create** to deploy the runbook

### Step 4: Publish and Test

After successful deployment:

1. Go to your Automation Account > **Runbooks**
2. Find the deployed runbook
3. Verify it is published and linked to the expected Runtime Environment
4. Test the runbook using **Start**

## ⚠️ Common Deployment Issues

### "Resource Not Found" Error

**Cause**: Automation Account name doesn't exist in the selected resource group
**Solution**:

- Verify the Automation Account name is spelled correctly
- Ensure you selected the correct resource group
- Check that the Automation Account exists in that resource group

### "Insufficient Permissions" Error

**Cause**: You don't have permissions to create resources in the Automation Account
**Solution**:

- Ensure you have **Automation Contributor** role on the resource group
- Or **Automation Operator** role specifically on the Automation Account

### "Runbook Already Exists" Error

**Cause**: A runbook with the same name already exists
**Solution**:

- Change the **Runbook Name** parameter to something unique
- Or delete the existing runbook if you want to replace it

## 🔧 Common Permissions by Script Category

### Security Scripts

- `DeviceManagementManagedDevices.ReadWrite.All`
- `BitlockerKey.ReadBasic.All`

### Device Management

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementManagedDevices.ReadWrite.All`

### Compliance Scripts

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementConfiguration.Read.All`

### App Management

- `DeviceManagementApps.Read.All`
- `DeviceManagementApps.ReadWrite.All`

## 🚨 Troubleshooting

### "Authentication needed" Error

**Cause**: Managed Identity not enabled or permissions not assigned
**Solution**:

1. Enable Managed Identity in Automation Account
2. Assign required Microsoft Graph permissions

### "Module not found" Error

**Cause**: Required PowerShell modules not imported
**Solution**:

1. Go to Automation Account > **Modules**
2. Import `Microsoft.Graph.Authentication`
3. Import any script-specific modules

### "Insufficient privileges" Error

**Cause**: Missing Microsoft Graph permissions
**Solution**:

1. Check script documentation for required permissions
2. Assign missing permissions to Managed Identity
3. Grant admin consent

### Runbook Fails to Start

**Cause**: Various issues with runbook configuration
**Solution**:

1. Check runbook is published
2. Verify all required modules are imported
3. Review Activity Logs for detailed errors

## 📊 Monitoring and Logging

### View Runbook Execution

1. Go to Automation Account > **Jobs**
2. Click on a job to view detailed logs
3. Check **Output** and **Errors** tabs

### Set Up Alerts

```powershell
# Example: Alert on runbook failures
$actionGroup = Get-AzActionGroup -ResourceGroupName "rg-monitoring" -Name "ag-alerts"

$condition = New-AzMetricAlertRuleV2Criteria `
    -MetricName "TotalJob" `
    -Operator GreaterThan `
    -Threshold 0 `
    -TimeAggregation Total

New-AzMetricAlertRuleV2 `
    -Name "Runbook-Failures" `
    -ResourceGroupName "rg-automation" `
    -WindowSize 00:05:00 `
    -Frequency 00:01:00 `
    -TargetResourceId "/subscriptions/{subscription-id}/resourceGroups/rg-automation/providers/Microsoft.Automation/automationAccounts/aa-intune-automation" `
    -Condition $condition `
    -ActionGroupId $actionGroup.Id `
    -Severity 2
```

## 🔄 Scheduling Runbooks

### Using Azure Portal

1. Go to runbook > **Schedules**
2. Click **Add a schedule**
3. Configure frequency and parameters

### Using PowerShell

```powershell
# Create a daily schedule
$schedule = New-AzAutomationSchedule `
    -AutomationAccountName "aa-intune-automation" `
    -ResourceGroupName "rg-automation" `
    -Name "Daily-Device-Check" `
    -StartTime (Get-Date).AddHours(1) `
    -DayInterval 1

# Link schedule to runbook
Register-AzAutomationScheduledRunbook `
    -AutomationAccountName "aa-intune-automation" `
    -ResourceGroupName "rg-automation" `
    -RunbookName "get-stale-devices" `
    -ScheduleName "Daily-Device-Check"
```

## 🎯 Best Practices

### Security

- Use least-privilege permissions
- Regularly review and audit permissions
- Monitor runbook execution logs

### Performance

- Import only required modules
- Use efficient PowerShell patterns
- Consider execution time limits

### Maintenance

- Keep modules updated
- Test scripts in development environment
- Document custom modifications

## 📚 Additional Resources

- [Azure Automation Documentation](https://docs.microsoft.com/en-us/azure/automation/)
- [Microsoft Graph Permissions Reference](https://docs.microsoft.com/en-us/graph/permissions-reference)
- [PowerShell in Azure Automation](https://docs.microsoft.com/en-us/azure/automation/automation-powershell)

## 🤝 Support

- **Issues**: Report on [GitHub Issues](https://github.com/ugurkocde/IntuneAutomation/issues)
- **Discussions**: Join [GitHub Discussions](https://github.com/ugurkocde/IntuneAutomation/discussions)
- **Website**: Visit [intuneautomation.com](https://intuneautomation.com)
