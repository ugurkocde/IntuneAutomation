#!/bin/bash

# TITLE: Check Microsoft AutoUpdate Status
# SYNOPSIS: Checks the status of Microsoft AutoUpdate (MAU) and reports version, channel, and last update check
# DESCRIPTION: This script retrieves information about Microsoft AutoUpdate including the current version,
#              update channel, and the timestamp of the last update check. Outputs results in a single
#              line format suitable for Intune custom attributes monitoring.
# TAGS: Monitoring,Microsoft
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: IntuneMacAdmins
# VERSION: 1.0
# LASTUPDATE: $(date +%Y-%m-%d)
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   check_msupdate_status.sh
#   Outputs MAU version, channel, and last update check in pipe-delimited format
#
# NOTES:
#   - Requires Microsoft AutoUpdate to be installed
#   - Outputs single line result suitable for Intune custom attributes
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Script version
SCRIPT_VERSION="1.0"

# Path to Microsoft AutoUpdate CLI tool
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

# Function to check minimum OS version
check_os_version() {
    local required_version=$1
    local current_version=$(sw_vers -productVersion)
    
    if [[ $(echo -e "$current_version\n$required_version" | sort -V | head -n1) != "$required_version" ]]; then
        output_result "Unsupported OS: $current_version (requires $required_version+)"
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    # Check if Microsoft AutoUpdate is installed
    if [[ ! -f "$MSUPDATE" ]]; then
        output_result "Error: Microsoft AutoUpdate not found at expected location"
    fi
    
    # Check if msupdate is executable
    if [[ ! -x "$MSUPDATE" ]]; then
        output_result "Error: Microsoft AutoUpdate CLI not executable"
    fi
    
    return 0
}

# Function to get MAU status information
get_mau_status() {
    # Get the configuration output from msupdate
    local config_output
    config_output=$("$MSUPDATE" --config 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$config_output" ]]; then
        output_result "Error: Unable to retrieve Microsoft AutoUpdate configuration"
    fi
    
    # Extract version information
    local mau_version=$(echo "$config_output" | grep "AutoUpdateVersion =" | awk -F'"' '{print $2}')
    
    # Extract channel information
    local channel=$(echo "$config_output" | grep "ChannelName = " | head -n 1 | awk -F'=' '{print $2}' | sed 's/;//' | xargs)
    
    # Extract last update check timestamp
    local last_check=$(echo "$config_output" | grep "LastCheckForUpdates =" | awk -F'"' '{print $2}')
    
    # Handle missing values
    [[ -z "$mau_version" ]] && mau_version="Unknown"
    [[ -z "$channel" ]] && channel="Unknown"
    [[ -z "$last_check" ]] && last_check="Unknown"
    
    # Output in pipe-delimited format for Intune custom attributes
    output_result "MAU Version: $mau_version | Channel: $channel | Last Update Check: $last_check"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check OS version if required
    check_os_version "10.15"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Get and output MAU status
    get_mau_status
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# For Intune custom attributes - handle errors gracefully
trap 'output_result "Error: Script failed unexpectedly"' ERR

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Exit successfully (if not using output_result)
exit 0