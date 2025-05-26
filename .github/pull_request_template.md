# Pull Request: [Category] Script Name

## 📋 Description

**What does this script do?**
<!-- Provide a clear description of the script's functionality -->

**Problem/Use Case:**
<!-- Describe the problem this script solves or the use case it addresses -->

## 📁 Script Details

**Category:** `scripts/[category]/`
**Script Name:** `script-name.ps1`
**Version:** `1.0`

**Required Permissions:**
<!-- List all Microsoft Graph API permissions required -->
- Permission.ReadWrite.All
- Permission.Read.All

**Minimum Role:** 
<!-- Specify the minimum Intune/Azure AD role required -->

## ✅ Testing Checklist

- [ ] **Lab Testing**: Script has been thoroughly tested in a lab environment
- [ ] **Parameter Testing**: All parameter combinations have been tested
- [ ] **Error Handling**: Error scenarios have been tested and handled gracefully
- [ ] **Permissions**: Script works with minimum required permissions
- [ ] **Rate Limiting**: Script handles Graph API throttling appropriately
- [ ] **Edge Cases**: Common edge cases have been considered and tested

## 🔍 Code Quality Checklist

- [ ] **Template Used**: Started with `templates/script-template.ps1`
- [ ] **Header Complete**: All header sections are filled out correctly
- [ ] **CmdletBinding**: Script uses `[CmdletBinding()]`
- [ ] **Parameter Validation**: Proper parameter attributes and validation
- [ ] **Error Handling**: Comprehensive try-catch blocks implemented
- [ ] **Graph Connection**: Proper authentication and disconnection
- [ ] **Helper Functions**: Includes pagination helper function
- [ ] **Comments**: Code is well-commented and readable
- [ ] **Naming**: Consistent PascalCase naming convention

## 📖 Documentation Checklist

- [ ] **Synopsis**: Clear one-line description
- [ ] **Description**: Detailed explanation of functionality
- [ ] **Examples**: At least 2 working examples provided
- [ ] **Parameters**: All parameters documented with help text
- [ ] **Notes**: Important information and requirements listed
- [ ] **Tags**: Appropriate category tags assigned
- [ ] **Changelog**: Version history documented

## 🚀 Usage Examples

**Example 1:**
```powershell
./script-name.ps1 -Parameter1 "value1"
```
<!-- Describe what this example does -->

**Example 2:**
```powershell
./script-name.ps1 -Parameter1 "value1" -Parameter2 "value2"
```
<!-- Describe what this example does -->

## 🔒 Security Considerations

- [ ] **Least Privilege**: Requests only minimum required permissions
- [ ] **Input Validation**: All user inputs are validated
- [ ] **No Hardcoded Secrets**: No credentials or sensitive data hardcoded
- [ ] **Safe Operations**: Script performs safe operations only

## 📊 Test Results

**Environment Tested:**
- PowerShell Version: 
- Graph Module Version: 
- Tenant Type: (Lab/Test)
- Device Count: 

**Test Summary:**
<!-- Provide a brief summary of your testing results -->

## 🔄 Breaking Changes

- [ ] **No Breaking Changes**: This script doesn't break existing functionality
- [ ] **New Dependencies**: List any new module dependencies
- [ ] **Permission Changes**: List any new permission requirements

## 📝 Additional Notes

<!-- Any additional information that reviewers should know -->

## 🔗 Related Issues

Closes #[issue-number]
Related to #[issue-number]

---

**Reviewer Notes:**
<!-- This section can be used by reviewers for feedback -->

## 📋 Reviewer Checklist

- [ ] **Code Review**: Code follows project standards and best practices
- [ ] **Testing**: Testing appears thorough and appropriate
- [ ] **Documentation**: Documentation is complete and accurate
- [ ] **Security**: Security considerations have been addressed
- [ ] **Functionality**: Script performs as described
- [ ] **Category**: Script is in the correct category folder 