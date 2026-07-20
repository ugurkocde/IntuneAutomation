<p align="center">
  <img src="https://github.com/user-attachments/assets/90e81af6-faca-47a6-92ae-00d916977860" alt="Intune Automation Logo" />
</p>

<p align="center">
  <strong>A collection of PowerShell scripts for automating Microsoft Intune device management tasks.</strong>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#scripts-overview">Scripts</a> •
  <a href="#prerequisites">Prerequisites</a> •
  <a href="#contributing">Contributing</a> •
  <a href="TESTING.md">Testing</a> •
  <a href="https://intuneautomation.com">Website</a>
</p>

<p align="center">
  <a href="https://github.com/ugurkocde/IntuneAutomation/actions/workflows/script-analysis.yml"><img src="https://github.com/ugurkocde/IntuneAutomation/actions/workflows/script-analysis.yml/badge.svg" alt="Script tests"></a>
</p>

---

## 🚀 Overview

This repository contains PowerShell scripts designed to help IT administrators automate common Microsoft Intune management operations. All scripts use the Microsoft Graph API and are organized by functional category for easy discovery and use.

### ✨ Key Features

- **📱 Device Management**: Automated device operations and lifecycle management
- **🔒 Security & Compliance**: Automated compliance reporting and security operations  
- **📦 Application Management**: Streamlined app deployment and management
- **📊 Monitoring & Reporting**: Comprehensive monitoring and analytics tools
- **☁️ Azure Integration**: Native support for Azure Automation runbooks
- **🔐 Security-First**: Built with enterprise security best practices

## 🚀 Quick Start

### Option 1: Local Execution (Recommended for Testing)

The simplest way to use these scripts is to **download and run them locally**:

1. **📥 Download the scripts** you need from this repository
2. **📦 Install required modules** (the scripts will prompt you if needed)
3. **▶️ Run the scripts** directly from PowerShell with appropriate parameters
4. **📋 Review the output** and logs for results

Most scripts are designed to work immediately without additional setup beyond the required PowerShell modules.

**Example:**
```powershell
# Download a script and run it
.\Get-DeviceComplianceReport.ps1 -TenantId "your-tenant-id"
```

### Option 2: Azure Automation (unattended execution and scheduling)

For **scheduling**, **unattended execution**, or **more complex automation**, you can deploy these scripts as Azure Automation Runbooks:

> **Step-by-step guide with screenshots:** [Deploy a script as a runbook with Managed Identity](docs/deploy-runbook-managed-identity.md) walks through the full flow from the Deploy to Azure button on intuneautomation.com to a scheduled runbook: deployment, granting Graph permissions to the managed identity in Cloud Shell, module import, and the first successful job.

#### Step 1: Create Managed Identity
Create a **User Assigned Managed Identity** in your Azure tenant through the Azure Portal.

#### Step 2: Grant Permissions
Use our setup script to grant necessary Microsoft Graph permissions:

```powershell
# Grant default Intune permissions to your managed identity
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "YourManagedIdentityName"

# Or grant custom permissions for specific use cases
.\grant-permissions-managed-identity.ps1 -ManagedIdentityDisplayName "YourManagedIdentityName" -CustomPermissions @("User.Read.All", "Group.Read.All")
```

#### Step 3: Configure Azure Automation
1. **Assign the managed identity** to your Azure Automation Account
2. **Import the scripts** as runbooks
3. **Schedule execution** as needed

This approach enables:
- **⏰ Scheduled execution** (daily, weekly, etc.)
- **🤖 Unattended operations** without user interaction
- **📈 Centralized logging** and monitoring
- **🔗 Integration** with other Azure services

### Default Permissions for Automation

The `grant-permissions-managed-identity.ps1` script grants these Microsoft Graph API permissions by default:

| Permission | Description |
|------------|-------------|
| `DeviceManagementManagedDevices.ReadWrite.All` | Full device management access |
| `DeviceManagementConfiguration.ReadWrite.All` | Configuration policy management |
| `DeviceManagementApps.ReadWrite.All` | Application management |
| `DeviceManagementServiceConfig.ReadWrite.All` | Service configuration |
| `DeviceManagementRBAC.ReadWrite.All` | Role-based access control |
| `DeviceManagementManagedDevices.PrivilegedOperations.All` | Advanced device operations |

These permissions cover most common Intune automation scenarios.

### Option 3: Ask Claude (MCP Server)

Use the [`@ugurkocde/intuneautomation-mcp`](mcp/) server to **search and retrieve these scripts from inside Claude Code** (or any MCP client) using natural language — no API key, no login, nothing to host.

```bash
claude mcp add intuneautomation -- npx -y @ugurkocde/intuneautomation-mcp
```

Then just ask: _"Which Intune scripts report on non-compliant devices?"_ or _"Show me the script to rotate BitLocker keys and what permissions it needs."_ Claude returns the right script with its required Microsoft Graph permissions, minimum role, parameters, and full source.

It can also **write new scripts** that follow the project's conventions: the server exposes the same authoring guide used by [intuneautomation.com/generator](https://intuneautomation.com/generator), so asking _"write me an Intune script to report stale devices"_ produces a script matching the library's strict format, auth patterns, and safety rules. See [mcp/README.md](mcp/README.md) for details.

## 📁 Scripts Overview

```
IntuneAutomation/
├── 🔧 grant-permissions-managed-identity.ps1  # Setup script for managed identity permissions
├── 📂 scripts/
│   ├── 🔄 operational/       # Device operations (restart, wipe, sync)
│   ├── 📱 apps/              # Application management and deployment
│   ├── ✅ compliance/        # Compliance reporting and remediation
│   ├── 🔒 security/          # Security operations and policies
│   ├── 💻 devices/           # Device management and inventory
│   └── 📊 monitoring/        # Monitoring, reporting, and analytics
├── 📄 templates/             # Script templates for contributors
├── 📋 LICENSE
├── 🤝 CONTRIBUTING.md
└── 📖 README.md
```

### Popular Scripts

- **Device Operations**: Bulk device actions, automated device cleanup
- **Compliance Reporting**: Automated compliance dashboards and alerts
- **App Management**: Silent app deployment and update automation
- **Security Monitoring**: Threat detection and response automation

> 💡 **Tip**: Each script category includes detailed documentation and usage examples.

## 📋 Prerequisites

### If you are running the scripts locally
- **PowerShell 5.1** or later (PowerShell 7+ recommended)
- **Microsoft Graph PowerShell modules**: 
  - `Microsoft.Graph.Authentication`
- **You have to sign in with an Intune Admin account**

### If you are running the scripts in Azure Automation as a Runbook
- **Azure Automation Account**
- **User Assigned Managed Identity** with the following permissions:
  - `DeviceManagementManagedDevices.ReadWrite.All`
  - `DeviceManagementConfiguration.ReadWrite.All`
  - `DeviceManagementApps.ReadWrite.All`
  - `DeviceManagementServiceConfig.ReadWrite.All`
  - `DeviceManagementRBAC.ReadWrite.All`
  - `DeviceManagementManagedDevices.PrivilegedOperations.All`

> 💡 **Tip**: Check `grant-permissions-managed-identity.ps1` for more details and how to grant the permissions

- **Your Environment in the Azure Automation Account has to have the following modules installed:**
  - `Az.Accounts`
  - `Az.Resources`
  - `Microsoft.Graph.Applications`
  - `Microsoft.Graph.Authentication`

### Authentication Methods Supported
- **Interactive Authentication** (default for local execution)
- **Managed Identity** (recommended for Azure Automation)

## 🤝 Contributing

We welcome contributions from the community! Whether you're fixing bugs, improving existing scripts, or adding new automation tools, your contributions help IT professionals worldwide.

### Quick Start for Contributors

1. **🍴 Fork the repository** and clone it locally
2. **📝 Use our script template**: Copy `templates/script-template.ps1` to get started
3. **📏 Follow our guidelines**: Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed instructions
4. **🧪 Test thoroughly**: Always test your scripts in a lab environment first
5. **🔄 Submit a pull request**: Use our PR template for faster reviews

See our [Contributing Guide](CONTRIBUTING.md) for detailed instructions, coding standards, and submission guidelines.

## ❓ Support & FAQ

### Common Issues

**Q: I have an Idea for a new script but I need someone to implement it?**
A: Open an issue and let me know. I'll be happy to implement it.

**Q: Scripts fail with authentication errors**
A: Ensure you have the required Microsoft Graph permissions and modules installed.

**Q: Can I use these scripts with GCC High/DoD tenants?**
A: Yes, but you may need to modify the Graph API endpoints for government clouds.

**Q: Are these scripts suitable for production use?**
A: Yes, but always test in a lab environment first and follow your organization's change management processes.

### Getting Help

- 📖 Check the [documentation](https://intuneautomation.com)
- 🐛 Report issues on [GitHub Issues](../../issues)
- 💬 Join discussions on [GitHub Discussions](../../discussions)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Ugur Koc** - Microsoft MVP  
- 🌐 Website: [https://ugurkoc.de](https://ugurkoc.de)
- 🐦 X: [@ugurkocde](https://x.com/ugurkocde)
- 💼 LinkedIn: [Ugur Koc](https://www.linkedin.com/in/ugurkocde/)

---

<p align="center">
  <strong>⭐ If this project helps you, please give it a star! ⭐</strong>
</p>
