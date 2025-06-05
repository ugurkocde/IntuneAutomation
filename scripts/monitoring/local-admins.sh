#!/bin/bash

# TITLE: List Local Admin Users
# SYNOPSIS: Lists all users with local administrator privileges on macOS
# DESCRIPTION: This script retrieves the list of users who are members of the local admin
#              group on macOS. It uses the Directory Service command line utility (dscl)
#              to query the admin group membership. The output is formatted for Intune
#              custom attributes to provide visibility into privileged access on managed devices.
# TAGS: Monitoring,Security
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: Ugur Koc
# VERSION: 1.0
# LASTUPDATE: 2025-06-04
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   ./local-admins.sh
#   Outputs the list of local admin users
#
# NOTES:
#   - Uses dscl to query admin group membership
#   - No external dependencies required
#   - Designed for Intune custom attributes (single line output)
#   - Includes count of admin users for quick assessment
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to output result (for Intune custom attributes)
output_result() {
    # For Intune custom attributes, output should be a single line
    echo "$1"
    exit 0
}

# Function to check prerequisites
check_prerequisites() {
    if ! command -v dscl >/dev/null 2>&1; then
        output_result "Error: dscl command not found"
    fi
}

# Function to get admin users
get_admin_users() {
    # Query the admin group membership
    local admin_output
    if ! admin_output=$(dscl . -read /Groups/admin GroupMembership 2>&1); then
        # Check if it's a permission issue
        if echo "$admin_output" | grep -q "eDSPermissionError"; then
            output_result "Error: Permission denied"
        else
            output_result "Error: Unable to query admin group"
        fi
    fi

    # Extract just the user list (remove "GroupMembership:" prefix)
    local admin_list
    admin_list=${admin_output#GroupMembership: }

    # Check if we got valid output
    if [[ -z "$admin_list" ]] || [[ "$admin_list" == "$admin_output" ]]; then
        output_result "Error: No admin users found or invalid format"
    fi

    echo "$admin_list"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check prerequisites
    check_prerequisites

    # Get the list of admin users
    local admin_users
    admin_users=$(get_admin_users)

    # Count the number of admin users
    local admin_count
    admin_count=$(echo "$admin_users" | wc -w | tr -d ' ')

    # Format output for Intune custom attributes
    if [[ $admin_count -eq 0 ]]; then
        output_result "Admin Users: None found"
    elif [[ $admin_count -eq 1 ]]; then
        output_result "Admin Users (1): $admin_users"
    else
        # For multiple users, show count and list
        output_result "Admin Users ($admin_count): $admin_users"
    fi
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# For Intune custom attributes - handle errors gracefully
trap 'output_result "Error: Script failed"' ERR

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Exit successfully (if not using output_result)
exit 0
