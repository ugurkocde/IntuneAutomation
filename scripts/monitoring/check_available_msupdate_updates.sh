#!/bin/bash

# TITLE: Check Available Microsoft Updates
# SYNOPSIS: Displays available updates for Microsoft Apps by checking MAU
# DESCRIPTION: This script uses Microsoft AutoUpdate (MAU) to check for available updates
#              for Microsoft applications installed on macOS systems. It runs the msupdate
#              command in the logged-in user's context to properly detect available updates.
# TAGS: Monitoring,Device
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: IntuneMacAdmins
# VERSION: 1.0
# LASTUPDATE: $(date +%Y-%m-%d)
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   check_available_msupdate_updates.sh
#   Checks for Microsoft App updates and displays results
#
# NOTES:
#   - Requires Microsoft AutoUpdate (MAU) to be installed
#   - Must be run with appropriate permissions to access user context
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Script version
SCRIPT_VERSION="1.0"

# Path to msupdate CLI
MSUPDATE="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"

# Get the current console user
loggedInUser=$(stat -f "%Su" /dev/console 2>/dev/null)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to output result (for Intune custom attributes)
output_result() {
    echo "$1"
    exit 0
}

# Function to check if MAU is installed
check_mau_installed() {
    if [[ ! -f "$MSUPDATE" ]]; then
        output_result "Error: Microsoft AutoUpdate not found"
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    # Check if MAU is installed
    check_mau_installed
    
    # Check if we have a valid logged-in user
    if [[ -z "$loggedInUser" ]] || [[ "$loggedInUser" == "root" ]] || [[ "$loggedInUser" == "_windowserver" ]]; then
        output_result "Error: No valid user logged in"
    fi
    
    return 0
}

# Function to check Microsoft updates
check_microsoft_updates() {
    # Get user ID for launchctl
    local USER_ID=$(id -u "$loggedInUser" 2>/dev/null)
    
    if [[ -z "$USER_ID" ]]; then
        output_result "Error: Unable to get user ID for $loggedInUser"
    fi
    
    # Run msupdate using the user's launchctl session
    local RAW_OUTPUT=$(launchctl asuser "$USER_ID" sudo -u "$loggedInUser" "$MSUPDATE" --list 2>&1)
    
    # Check if command was successful
    if [[ $? -ne 0 ]]; then
        output_result "Error: Failed to run msupdate command"
    fi
    
    # Check if "No updates available" is in the output
    if echo "$RAW_OUTPUT" | grep -q "No updates available"; then
        output_result "No updates available"
    else
        # Display the full output if updates are available
        echo "$RAW_OUTPUT"
    fi
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Validate prerequisites
    validate_prerequisites
    
    # Check for Microsoft updates
    check_microsoft_updates
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

# Exit successfully
exit 0