# Contributing to IntuneAutomation

Thank you for your interest in contributing to the IntuneAutomation project! This guide will help you create high-quality PowerShell scripts that benefit the community.

## 🚀 Quick Start

1. **Fork the repository** and clone it to your local machine
2. **Create a new branch** for your contribution
3. **Use the script template** from `templates/script-template.ps1`
4. **Follow the coding standards** outlined below
5. **Test your script thoroughly**
6. **Submit a pull request**

## 📁 Project Structure

```
IntuneAutomation/
├── scripts/
│   ├── operational/        # Device operations (sync, restart, wipe)
│   ├── apps/              # Application management (install, uninstall, reporting)
│   ├── compliance/        # Compliance reporting and remediation
│   ├── security/          # Security operations (policies, conditional access)
│   └── devices/           # Device management (enrollment, configuration)
├── templates/             # Templates for contributors
├── .github/              # GitHub templates and workflows
├── CONTRIBUTING.md       # This file
├── LICENSE
└── README.md
```

## 📝 Script Categories

### Operational (`scripts/operational/`)
Scripts for day-to-day device operations:
- Device synchronization
- Remote actions (restart, shutdown, lock)
- Bulk operations
- Device troubleshooting

### Apps (`scripts/apps/`)
Application management scripts:
- App deployment automation
- Application reporting
- License management
- App removal/cleanup

### Compliance (`scripts/compliance/`)
Compliance and reporting scripts:
- Compliance reporting
- Policy assessment
- Remediation scripts
- Audit reports

### Security (`scripts/security/`)
Security-focused scripts:
- Security policy management
- Conditional access automation
- Threat protection configuration
- Security reporting

### Devices (`scripts/devices/`)
Device lifecycle management:
- Device enrollment automation
- Configuration profile management
- Device inventory
- Hardware/software reporting

## 🛠️ Coding Standards

### Script Header Requirements

Every script must include a comprehensive header with the following sections:

```powershell
<#
.TITLE
    [Descriptive title - what the script does]

.SYNOPSIS
    [One-line summary of functionality]

.DESCRIPTION
    [Detailed description including use cases and prerequisites]

.TAGS
    [Category],[Subcategory] (e.g., Operational,Devices)

.MINROLE
    [Minimum required role - e.g., Intune Administrator]

.PERMISSIONS
    [Required Graph API permissions - comma separated]

.AUTHOR
    [Your name or GitHub username]

.VERSION
    [Version number - start with 1.0]

.CHANGELOG
    [Version history with descriptions]

.EXAMPLE
    [Usage examples with descriptions]

.NOTES
    [Additional information, requirements, limitations]
#>
```

### PowerShell Best Practices

1. **Use CmdletBinding**: All scripts should use `[CmdletBinding()]`
2. **Parameter Validation**: Use proper parameter attributes and validation
3. **Error Handling**: Implement comprehensive try-catch blocks
4. **Information Output**: Use `Write-Information` for progress updates
5. **Consistent Naming**: Use PascalCase for variables and functions
6. **Comments**: Include inline comments for complex logic
7. **Modules**: Check for and import required modules
8. **Graph Connection**: Always include authentication and disconnection

### Code Structure

1. **Header**: Complete script documentation
2. **Parameters**: Well-defined parameters with validation
3. **Module Checks**: Verify required modules are available
4. **Authentication**: Microsoft Graph connection
5. **Helper Functions**: Reusable functions (include pagination helper)
6. **Main Logic**: Core script functionality
7. **Error Handling**: Comprehensive error management
8. **Cleanup**: Proper disconnection and cleanup
9. **Summary**: Execution summary output

### Required Elements

- **Rate Limiting**: Handle Graph API throttling
- **Pagination**: Use the provided `Get-MgGraphAllPages` function
- **Progress Feedback**: Show real-time progress to users
- **Parameter Validation**: Validate all inputs
- **Graceful Failures**: Handle errors without breaking the system
- **Documentation**: Clear examples and usage instructions

## 🔒 Security Considerations

1. **Least Privilege**: Request only the minimum required permissions
2. **Input Validation**: Validate all user inputs
3. **Secure Practices**: Never hardcode credentials or sensitive data
4. **Graph Permissions**: Clearly document all required permissions
5. **Role Requirements**: Specify minimum role requirements

## 🧪 Testing Guidelines

Before submitting your script:

1. **Test in a lab environment** - Never test in production first
2. **Test with different parameters** - Verify all parameter combinations
3. **Test error scenarios** - Ensure graceful failure handling
4. **Test permissions** - Verify script works with minimum required permissions
5. **Test rate limiting** - Ensure script handles API throttling
6. **Document test results** - Include testing information in your PR

## 📋 Script Template Usage

1. Copy `templates/script-template.ps1` to the appropriate category folder
2. Rename the file to describe its function (e.g., `get-device-inventory.ps1`)
3. Update all header sections with your script's information
4. Replace placeholder functions with your logic
5. Update the required modules and permissions
6. Test thoroughly before submitting

## 🔄 Submission Process

### Before You Submit

- [ ] Script follows the template structure
- [ ] All header sections are complete and accurate
- [ ] Script has been tested in a lab environment
- [ ] Required permissions are documented
- [ ] Examples are provided and tested
- [ ] Error handling is implemented
- [ ] Code follows PowerShell best practices

### Pull Request Guidelines

1. **Branch Naming**: Use descriptive branch names (e.g., `feature/device-compliance-report`)
2. **Commit Messages**: Write clear, descriptive commit messages
3. **PR Title**: Use format: `[Category] Script Name - Brief Description`
4. **PR Description**: Include:
   - What the script does
   - Testing performed
   - Any special considerations
   - Screenshots if applicable

### PR Template Checklist

When you submit a PR, ensure you've completed the checklist in the PR template.

## 🏷️ Tagging Guidelines

Use consistent tags for categorizing scripts:

**Primary Categories:**
- `Operational` - Day-to-day operations
- `Apps` - Application management
- `Compliance` - Compliance and reporting
- `Security` - Security operations
- `Devices` - Device management

**Secondary Tags:**
- `Reporting` - Generates reports
- `Bulk` - Bulk operations
- `Remediation` - Fixes issues
- `Automation` - Automates processes
- `Monitoring` - Monitoring/alerting

## 🤝 Community Guidelines

- **Be Respectful**: Treat all contributors with respect
- **Share Knowledge**: Help others learn and improve
- **Quality Focus**: Prioritize code quality and documentation
- **Security First**: Always consider security implications
- **Test Thoroughly**: Test your contributions properly

## 📞 Getting Help

- **Issues**: Create an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check existing scripts for examples
- **Template**: Always start with the provided template

## 🏆 Recognition

Contributors will be:
- Listed in script headers as authors
- Recognized in release notes
- Added to the project contributors list

Thank you for contributing to IntuneAutomation! Your scripts help IT professionals worldwide manage their environments more effectively.

## 📚 Additional Resources

- [Microsoft Graph PowerShell SDK Documentation](https://docs.microsoft.com/en-us/powershell/microsoftgraph/)
- [Microsoft Graph API Reference](https://docs.microsoft.com/en-us/graph/api/overview)
- [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)
- [Intune PowerShell Samples](https://github.com/microsoftgraph/powershell-intune-samples) 