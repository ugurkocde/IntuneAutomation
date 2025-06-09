# Script Templates

This directory contains templates to help contributors create consistent, high-quality scripts for the IntuneAutomation project.

## 📄 Available Templates

### `script-template.ps1`
A comprehensive PowerShell script template that includes all the required elements for IntuneAutomation scripts.

### `notification-script-template.ps1` 🆕
A specialized template for creating notification scripts that monitor Intune environments and send email alerts. These scripts are designed specifically for Azure Automation runbooks with email notification capabilities.

**Key Features:**
- Azure Automation optimized with Managed Identity support
- Professional HTML email templates with responsive design
- Comprehensive error handling and Microsoft Graph integration
- Rate limiting and pagination for API calls
- Configurable thresholds and filtering options

**Use Cases:**
- Monitor certificate expiration dates
- Track device compliance drift
- Alert on application deployment failures
- Monitor token and license expiration
- Custom threshold-based monitoring

See `NOTIFICATION_TEMPLATE_GUIDE.md` for detailed usage instructions.

### `remediation-detection-template.ps1` & `remediation-action-template.ps1` 🆕
Specialized templates for creating Intune Proactive Remediation script pairs. These templates provide a structured approach to detecting and fixing compliance issues automatically.

**Key Features:**
- Detection and remediation script pair structure
- Standard exit codes for Intune compatibility
- Pre and post-remediation validation
- Comprehensive error handling and logging
- Rollback support for safe remediation

**Use Cases:**
- Enforce security configurations
- Fix compliance drift
- Automate common IT support tasks
- Maintain device health
- Implement self-healing systems

See `REMEDIATION_TEMPLATE_GUIDE.md` for detailed usage instructions.

## 🚀 How to Use the Templates

### For Standard Scripts (script-template.ps1)

1. **Copy the template** to the appropriate category directory:
   ```bash
   cp templates/script-template.ps1 scripts/[category]/your-script-name.ps1
   ```

2. **Rename the file** to describe your script's function (use kebab-case):
   - `get-device-inventory.ps1`
   - `sync-all-devices.ps1`
   - `export-compliance-report.ps1`

3. **Update the header sections** with your script's information

4. **Replace placeholder code** with your implementation

5. **Test thoroughly** before submitting

### For Notification Scripts (notification-script-template.ps1) 🆕

1. **Copy the notification template** to the notification directory:
   ```bash
   cp templates/notification-script-template.ps1 scripts/notification/your-notification-alert.ps1
   ```

2. **Rename the file** to describe your monitoring purpose:
   - `certificate-expiration-alert.ps1`
   - `license-usage-alert.ps1`
   - `policy-drift-alert.ps1`

3. **Follow the detailed guide** in `NOTIFICATION_TEMPLATE_GUIDE.md`

4. **Customize monitoring logic** for your specific use case

5. **Test in Azure Automation** with Managed Identity

6. **Set up automated scheduling** for continuous monitoring

### For Remediation Scripts (remediation-detection-template.ps1 & remediation-action-template.ps1) 🆕

1. **Create a new directory** for your remediation pair:
   ```bash
   mkdir scripts/remediation/your-remediation-name
   ```

2. **Copy both templates** to your new directory:
   ```bash
   cp templates/remediation-detection-template.ps1 scripts/remediation/your-remediation-name/detect-your-issue.ps1
   cp templates/remediation-action-template.ps1 scripts/remediation/your-remediation-name/remediate-your-issue.ps1
   ```

3. **Update the metadata** in both scripts to link them together

4. **Follow the detailed guide** in `REMEDIATION_TEMPLATE_GUIDE.md`

5. **Test locally** before deploying to Intune

6. **Deploy as Proactive Remediation** in Intune portal

## 📋 Template Sections Explained

### Header Documentation

#### `.TITLE`
- Brief, descriptive name for your script
- Should clearly indicate what the script does
- Example: "Bulk Device Synchronization"

#### `.SYNOPSIS`
- One-line summary of functionality
- Keep it concise and clear
- Example: "Triggers synchronization on multiple Intune managed devices"

#### `.DESCRIPTION`
- Detailed explanation of what the script does
- Include use cases and prerequisites
- Mention any important considerations
- Explain the business value

#### `.TAGS`
- Use the format: `[Primary Category],[Secondary Tag]`
- Primary categories: `Operational`, `Apps`, `Compliance`, `Security`, `Devices`
- Secondary tags: `Reporting`, `Bulk`, `Remediation`, `Automation`, `Monitoring`

#### `.MINROLE`
- Specify the minimum Azure AD/Intune role required
- Examples: `Intune Administrator`, `Global Administrator`, `Security Administrator`

#### `.PERMISSIONS`
- List all required Microsoft Graph API permissions
- Use exact permission names from Microsoft documentation
- Separate multiple permissions with commas

#### `.AUTHOR`
- Your name or GitHub username
- Will be used for attribution

#### `.VERSION`
- Start with `1.0` for new scripts
- Follow semantic versioning (major.minor.patch)

#### `.CHANGELOG`
- Document all changes by version
- Format: `[Version] - [Description]`

#### `.EXAMPLE`
- Provide at least 2 realistic usage examples
- Include parameter values and descriptions
- Show different use cases

#### `.NOTES`
- List requirements, limitations, or important information
- Include links to relevant documentation
- Mention performance considerations

### Code Structure

#### Parameters
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Description")]
    [ValidateNotNullOrEmpty()]
    [string]$RequiredParameter
)
```

#### Module Checks
- Always verify required modules are installed
- We only use Microsoft.Graph.Authentication module for Connect-MgGraph and Invoke-MgGraphRequest
- Provide clear installation instructions
- Import modules explicitly

#### Authentication
- Use only Microsoft.Graph.Authentication module for authentication and API calls
- Connect with Connect-MgGraph and make API calls with Invoke-MgGraphRequest
```powershell
Connect-MgGraph -Scopes $Scopes -NoWelcome
```

#### Helper Functions
- Include the `Get-MgGraphAllPages` function for pagination
- Add custom helper functions as needed
- Use proper error handling

#### Main Logic
- Implement your core functionality
- Use try-catch blocks for error handling
- Provide progress feedback
- Validate inputs

#### Cleanup
- Always disconnect from Graph API
- Handle disconnection errors gracefully

## 🔧 Customization Guidelines

### Required Sections (Don't Remove)
- Header documentation blocks
- Parameter validation
- Module checks and imports
- Graph authentication
- `Get-MgGraphAllPages` helper function
- Error handling blocks
- Cleanup/disconnection

### Customizable Sections
- Parameter definitions
- Required modules list
- Graph permissions scope
- Helper functions
- Main script logic
- Output formatting

### Best Practices
1. **Module Usage**: Use only Microsoft.Graph.Authentication module with Connect-MgGraph and Invoke-MgGraphRequest
2. **Validation**: Validate all user inputs
3. **Error Handling**: Use comprehensive try-catch blocks
4. **Progress**: Show real-time progress to users
5. **Permissions**: Request only minimum required permissions
6. **Documentation**: Comment complex logic
7. **Testing**: Test all scenarios thoroughly

## 📝 Header Examples

### Operational Script Example
```powershell
<#
.TITLE
    Bulk Device Restart

.SYNOPSIS
    Remotely restarts multiple Intune managed devices

.DESCRIPTION
    This script connects to Microsoft Graph and sends restart commands to specified devices.
    Devices can be targeted by name, ID, or group membership. The script provides real-time
    feedback on restart operations and handles errors gracefully.

.TAGS
    Operational,Bulk

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementManagedDevices.Read.All

.AUTHOR
    Your Name

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\restart-devices.ps1 -DeviceNames "LAPTOP001","DESKTOP002"
    Restarts specific devices by name

.NOTES
    - Requires only Microsoft.Graph.Authentication module
    - Uses Connect-MgGraph and Invoke-MgGraphRequest for all Graph operations
    - Devices must be online to receive restart command
    - Use with caution in production environments
#>
```

### Reporting Script Example
```powershell
<#
.TITLE
    Device Compliance Dashboard Report

.SYNOPSIS
    Generates comprehensive device compliance reporting dashboard

.DESCRIPTION
    Creates detailed compliance reports showing device compliance status, policy violations,
    and remediation recommendations. Exports data to CSV and generates HTML dashboard
    for executive reporting.

.TAGS
    Compliance,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,DeviceManagementConfiguration.Read.All

.AUTHOR
    Your Name

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\compliance-dashboard.ps1 -OutputPath "C:\Reports"
    Generates reports and saves to specified directory

.NOTES
    - Generates CSV and HTML output files
    - Includes charts and visualizations
    - Can be scheduled for automated reporting
#>
```

## 🤝 Getting Help

- Review existing scripts for examples
- Check the [CONTRIBUTING.md](../CONTRIBUTING.md) guide
- Create an issue if you need assistance
- Ask questions in GitHub Discussions

## 📚 Additional Resources

- [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)
- [Microsoft Graph PowerShell SDK](https://docs.microsoft.com/en-us/powershell/microsoftgraph/)
- [Intune PowerShell Samples](https://github.com/microsoftgraph/powershell-intune-samples) 