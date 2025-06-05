#!/bin/bash

# TITLE: Check Available Microsoft Updates
# SYNOPSIS: Checks for available updates for Microsoft applications via MAU
# DESCRIPTION: This script uses Microsoft AutoUpdate (MAU) to check for available updates
#              for Microsoft Office applications and other Microsoft software on macOS.
#              It runs the msupdate command in the context of the logged-in user to ensure
#              proper access to user-specific update information. Results are formatted
#              for Intune custom attributes to provide visibility into pending updates.
# TAGS: Monitoring,Updates
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: Ugur Koc
# VERSION: 1.0
# LASTUPDATE: 2025-06-04
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   ./check-available-msupdate-updates.sh
#   Checks for available Microsoft application updates and outputs the list
#
# NOTES:
#   - Requires Microsoft AutoUpdate to be installed on the device
#   - Runs msupdate in the context of the logged-in user
#   - Designed for Intune custom attributes (single line output)
#   - Returns "No updates available" or lists available updates
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Path to msupdate CLI
MSUPDATE="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"

# Get the current console user (if needed)
loggedInUser=$(stat -f "%Su" /dev/console 2>/dev/null)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to output result (for Intune custom attributes)
output_result() {
    # For Intune custom attributes, output should be a single line
    echo "$1"
    exit 0
}

# Function to check if MAU is installed
check_mau_installed() {
    if [[ ! -f "$MSUPDATE" ]]; then
        output_result "Microsoft AutoUpdate not installed"
    fi
}

# Function to check if msupdate is executable
check_msupdate_executable() {
    if [[ ! -x "$MSUPDATE" ]]; then
        output_result "Error: msupdate not executable"
    fi
}

# Function to validate user context
validate_user_context() {
    if [ -z "$loggedInUser" ] || [ "$loggedInUser" = "root" ] || [ "$loggedInUser" = "_windowserver" ]; then
        output_result "Error: No user logged in"
    fi
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check if MAU is installed
    check_mau_installed

    # Check if msupdate is executable
    check_msupdate_executable

    # Validate user context
    validate_user_context

    # Get user ID for the logged-in user
    local user_id
    user_id=$(id -u "$loggedInUser" 2>/dev/null)

    if [[ -z "$user_id" ]]; then
        output_result "Error: Unable to get user ID"
    fi

    # Run msupdate using the user's launchctl session
    local raw_output
    if ! raw_output=$(launchctl asuser "$user_id" sudo -u "$loggedInUser" "$MSUPDATE" --list 2>&1); then
        # Check for specific error messages
        if echo "$raw_output" | grep -q "Failed to connect"; then
            output_result "Error: Failed to connect to MAU service"
        else
            output_result "Error: Unable to check for updates"
        fi
    fi

    # Check if "No updates available" is in the output
    if echo "$raw_output" | grep -q "No updates available"; then
        output_result "No updates available"
    else
        # Process available updates for single-line output
        # Extract update information and format for Intune
        local updates
        updates=$(echo "$raw_output" | grep -E "^\s*[A-Za-z]" | grep -v "Updates available:" | tr '\n' ' ' | sed 's/  */ /g' | xargs)

        if [[ -n "$updates" ]]; then
            output_result "Updates available: $updates"
        else
            output_result "Updates available (check MAU for details)"
        fi
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
