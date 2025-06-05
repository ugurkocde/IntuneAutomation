#!/bin/bash

# TITLE: Get Last Reboot Time
# SYNOPSIS: Retrieves the last system reboot time on macOS
# DESCRIPTION: This script extracts the system boot time from the kernel and formats it
#              in a human-readable format. It uses the sysctl command to query the
#              kern.boottime value, which contains the timestamp of the last system boot.
#              The output is formatted for Intune custom attributes to provide visibility
#              into device uptime and reboot patterns.
# TAGS: Monitoring,Device
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: Ugur Koc
# VERSION: 1.0
# LASTUPDATE: 2025-06-04
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   ./last-reboot.sh
#   Outputs the last reboot time in YYYY-MM-DD HH:MM:SS format
#
# NOTES:
#   - Uses sysctl to query kern.boottime
#   - No external dependencies required
#   - Designed for Intune custom attributes (single line output)
#   - Time is displayed in local system timezone
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

# Function to validate sysctl availability
check_prerequisites() {
    if ! command -v sysctl >/dev/null 2>&1; then
        output_result "Error: sysctl command not found"
    fi
}

# Function to get boot time
get_boot_time() {
    # Get the boot time from sysctl
    local boot_info
    boot_info=$(sysctl -n kern.boottime 2>/dev/null)

    if [[ -z "$boot_info" ]]; then
        output_result "Error: Unable to retrieve boot time"
    fi

    # Extract the timestamp (sec value)
    local timestamp
    timestamp=$(echo "$boot_info" | awk '{print $4}' | tr -d ',')

    # Validate timestamp
    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
        output_result "Error: Invalid boot time format"
    fi

    echo "$timestamp"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check prerequisites
    check_prerequisites

    # Get the boot timestamp
    local timestamp
    timestamp=$(get_boot_time)

    # Convert timestamp to formatted date
    local formatted_date
    formatted_date=$(date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    if [[ -z "$formatted_date" ]]; then
        output_result "Error: Unable to format boot time"
    fi

    # Calculate uptime for additional context
    local current_time
    current_time=$(date +%s)
    local uptime_seconds=$((current_time - timestamp))
    local uptime_days=$((uptime_seconds / 86400))
    local uptime_hours=$(((uptime_seconds % 86400) / 3600))

    # Format output with uptime information
    if [[ $uptime_days -gt 0 ]]; then
        output_result "Last Reboot: $formatted_date (${uptime_days}d ${uptime_hours}h ago)"
    else
        output_result "Last Reboot: $formatted_date (${uptime_hours}h ago)"
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
