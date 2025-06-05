#!/bin/bash

# TITLE: Check Microsoft AutoUpdate Status
# SYNOPSIS: Checks the status of Microsoft AutoUpdate (MAU) on macOS devices
# DESCRIPTION: This script retrieves and displays the current status of Microsoft AutoUpdate (MAU),
#              including the installed version, update channel configuration, and the timestamp
#              of the last update check. The information is formatted for Intune custom attributes
#              to provide visibility into the update configuration of Microsoft applications.
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
#   ./check-msupdate-status.sh
#   Outputs MAU version, channel, and last update check time
#
# NOTES:
#   - Requires Microsoft AutoUpdate to be installed on the device
#   - Uses the msupdate CLI tool provided with MAU
#   - Designed for Intune custom attributes (single line output)
#   - Output format: MAU Version: X.X.X | Channel: ChannelName | Last Update Check: DateTime
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Path to msupdate CLI
MSUPDATE="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"

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

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check if MAU is installed
    check_mau_installed

    # Check if msupdate is executable
    check_msupdate_executable

    # Get the configuration output
    local config_output
    if ! config_output=$("$MSUPDATE" --config 2>/dev/null) || [[ -z "$config_output" ]]; then
        output_result "Error: Unable to retrieve MAU configuration"
    fi

    # Extract MAU version
    local mau_version
    mau_version=$(echo "$config_output" | grep "AutoUpdateVersion =" | awk -F'"' '{print $2}')
    if [[ -z "$mau_version" ]]; then
        mau_version="Unknown"
    fi

    # Extract channel name
    local channel_name
    channel_name=$(echo "$config_output" | grep "ChannelName = " | head -n 1 | awk -F'=' '{print $2}' | sed 's/;//' | xargs)
    if [[ -z "$channel_name" ]]; then
        channel_name="Unknown"
    fi

    # Extract last update check time
    local last_check
    last_check=$(echo "$config_output" | grep "LastCheckForUpdates =" | awk -F'"' '{print $2}')
    if [[ -z "$last_check" ]]; then
        last_check="Never"
    fi

    # Format and output the result
    output_result "MAU Version: $mau_version | Channel: $channel_name | Last Update Check: $last_check"
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
