#!/bin/bash

# TITLE: Check XProtect and Security Status
# SYNOPSIS: Checks XProtect, XProtect Remediator, MRT, and system security settings
# DESCRIPTION: This script retrieves the current versions of macOS security components including
#              XProtect, XProtect Remediator, and MRT (Malware Removal Tool). Additionally,
#              it checks the status of critical security features like System Integrity Protection
#              (SIP), Gatekeeper, and FileVault. Results are formatted for Intune custom attributes
#              to provide comprehensive visibility into device security posture.
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
#   ./check-xprotect-status.sh
#   Outputs XProtect versions and security settings status
#
# NOTES:
#   - Requires root privileges to access certain security settings
#   - Checks XProtect, XProtect Remediator, MRT versions
#   - Reports SIP, Gatekeeper, and FileVault status
#   - Designed for Intune custom attributes (single line output)
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Get macOS version
os_version=$(sw_vers -productVersion)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to output result (for Intune custom attributes)
output_result() {
    # For Intune custom attributes, output should be a single line
    echo "$1"
    exit 0
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        output_result "Error: Root access required"
    fi
}

# Function to check plist value with error handling
get_plist_value() {
    local plist="$1"
    local key="$2"

    if [ ! -f "$plist" ]; then
        return 1
    fi

    local value
    if ! value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null); then
        return 1
    fi
    echo "$value"
}

# Function to check XProtect version
check_xprotect() {
    local xprotect_meta="/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
    local xprotect_version=""

    if [ -f "$xprotect_meta" ]; then
        xprotect_version=$(get_plist_value "$xprotect_meta" "CFBundleShortVersionString")
    fi

    echo -n "XProtect: v${xprotect_version:-Unknown}"
}

# Function to check XProtect Remediator
check_xprotect_remediator() {
    local remediator_meta="/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"
    local remediator_version=""

    if [ -f "$remediator_meta" ]; then
        remediator_version=$(get_plist_value "$remediator_meta" "CFBundleShortVersionString")
    fi

    echo -n " | XProtect Remediator: v${remediator_version:-Unknown}"
}

# Function to check MRT version
check_mrt() {
    local mrt_meta="/Library/Apple/System/Library/CoreServices/MRT.app/Contents/Info.plist"
    local mrt_version=""

    if [ -f "$mrt_meta" ]; then
        mrt_version=$(get_plist_value "$mrt_meta" "CFBundleShortVersionString")
    fi

    echo -n " | MRT: v${mrt_version:-Unknown}"
}

# Function to check system security settings
check_system_security() {
    local security_status=""

    # Check SIP status
    local sip_output
    sip_output=$(csrutil status 2>&1)
    if echo "$sip_output" | grep -q "System Integrity Protection status: enabled"; then
        security_status="SIP:Enabled"
    else
        security_status="SIP:Disabled"
    fi

    # Check Gatekeeper status
    if spctl --status 2>&1 | grep -q "enabled"; then
        security_status="$security_status,GK:Enabled"
    else
        security_status="$security_status,GK:Disabled"
    fi

    # Check FileVault status
    if fdesetup status | grep -q "On"; then
        security_status="$security_status,FV:Enabled"
    else
        security_status="$security_status,FV:Disabled"
    fi

    echo -n " | Security: $security_status"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check root access
    check_root

    # Build output string
    local result=""

    # Add macOS version
    result="macOS: $os_version | "

    # Add XProtect information
    result="${result}$(check_xprotect)"
    result="${result}$(check_xprotect_remediator)"
    result="${result}$(check_mrt)"
    result="${result}$(check_system_security)"

    # Output the result
    output_result "$result"
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
