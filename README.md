# IntuneAutomation

A collection of PowerShell scripts for automating Microsoft Intune device management tasks.

## Overview

This repository contains PowerShell scripts designed to help IT administrators automate common Intune management operations. All scripts use the Microsoft Graph API and are organized by functional category.

## Quick Start

### Local Execution

The simplest way to use these scripts is to **download and run them locally**:

1. **Download the scripts** you need from this repository
2. **Install required modules** (the scripts will prompt you if needed)
3. **Run the scripts** directly from PowerShell with appropriate parameters
4. **Review the output** and logs for results

Most scripts are designed to work immediately without additional setup beyond the required PowerShell modules.

### Advanced: Azure Automation Runbooks

For **scheduling**, **unattended execution**, or **enterprise-scale automation**, you can deploy these scripts as Azure Automation Runbooks:

1. **Create a User Assigned Managed Identity** in your Azure tenant
2. **Grant necessary permissions** using our setup script:

```powershell
# Grant default Intune permissions to your managed identity
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "YourManagedIdentityName"

# Or grant custom permissions for specific use cases
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "YourManagedIdentityName" -CustomPermissions @("User.Read.All", "Group.Read.All")
```

3. **Assign the managed identity** to your Azure Automation Account
4. **Import and schedule** the scripts as runbooks

This approach enables:
- **Scheduled execution** (daily, weekly, etc.)
- **Unattended operations** without user interaction
- **Centralized logging** and monitoring
- **Integration** with other Azure services

### Default Permissions for Automation

The `grant-permissions-managed-identity.ps1` script grants these Microsoft Graph API permissions by default:

- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `DeviceManagementRBAC.ReadWrite.All`
- `DeviceManagementManagedDevices.PrivilegedOperations.All`

These permissions cover most common Intune automation scenarios.

## Structure

```
IntuneAutomation/
├── grant-permissions-managed-identity.ps1  # Setup script for managed identity permissions
├── scripts/
│   ├── operational/       # Device operations
│   ├── apps/              # Application management
│   ├── compliance/        # Compliance reporting
│   ├── security/          # Security operations
│   └── devices/           # Device management
│   └── monitoring/        # Monitoring and reporting
├── LICENSE
├── CONTRIBUTING.md
└── README.md
```

## Prerequisites

- **PowerShell 5.1** or later
- **Azure PowerShell modules**: Az.Accounts, Az.Resources
- **Microsoft Graph PowerShell modules**: Microsoft.Graph.Applications
- **Appropriate permissions** in your Azure/Entra ID tenant to:
  - Create and manage managed identities
  - Grant application permissions
  - Manage Azure Automation accounts

## Companion Website

This project includes a companion web interface that provides documentation, interactive tools, and best practices for Intune automation. Visit [https://intuneautomation.com](https://intuneautomation.com) for more information.

## Contributing

We welcome contributions from the community! Whether you're fixing bugs, improving existing scripts, or adding new automation tools, your contributions help IT professionals worldwide.

### Quick Start for Contributors

1. **Fork the repository** and clone it locally
2. **Use our script template**: Copy `templates/script-template.ps1` to get started
3. **Follow our guidelines**: Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed instructions
4. **Test thoroughly**: Always test your scripts in a lab environment first
5. **Submit a pull request**: Use our PR template for faster reviews

### What We're Looking For

- **PowerShell scripts** for Intune automation tasks
- **Comprehensive documentation** and examples
- **Proper error handling** and security considerations
- **Real-world use cases** that benefit the community

See our [Contributing Guide](CONTRIBUTING.md) for detailed instructions, coding standards, and submission guidelines.

## License

MIT License - see LICENSE file for details.

## Author

Ugur Koc - Microsoft MVP