#!/bin/bash

# TITLE: Check Network Requirements
# SYNOPSIS: Checks connectivity to Apple security and software update services
# DESCRIPTION: This script validates connectivity to Apple's critical security and software update
#              services by testing TCP connections to required endpoints. It checks both security
#              services (OCSP, CRL, PPQ) and OS/software update services. Results are formatted
#              for Intune custom attributes to provide visibility into network connectivity issues
#              that may prevent proper device security and update functionality.
# TAGS: Monitoring,Network
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: Ugur Koc
# VERSION: 1.0
# LASTUPDATE: 2025-06-04
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   ./check-network-requirements.sh
#   Checks connectivity to Apple services and outputs reachability status
#
# NOTES:
#   - Tests TCP connectivity on port 443 for all Apple service endpoints
#   - Groups results by security services and update services
#   - Designed for Intune custom attributes (single line output)
#   - Uses nc (netcat) for TCP connection testing with 2 second timeout
#   - No external dependencies required beyond standard macOS tools
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Initialize unreachable arrays for each category
security_unreachable=()
update_unreachable=()

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to output result (for Intune custom attributes)
output_result() {
    # For Intune custom attributes, output should be a single line
    echo "$1"
    exit 0
}

# Function to check TCP connectivity
check_tcp_connection() {
    local domain="$1"
    local port="$2"

    # Use nc (netcat) to test TCP connection with 2 second timeout
    if nc -zw2 "$domain" "$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check required commands
check_prerequisites() {
    # Check for netcat availability
    if ! command -v nc >/dev/null 2>&1; then
        output_result "Error: Required command 'nc' not found"
    fi
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Check prerequisites
    check_prerequisites

    # Check security services
    if ! check_tcp_connection "ocsp.apple.com" "443"; then
        security_unreachable+=("ocsp.apple.com")
    fi

    if ! check_tcp_connection "crl.apple.com" "443"; then
        security_unreachable+=("crl.apple.com")
    fi

    if ! check_tcp_connection "ppq.apple.com" "443"; then
        security_unreachable+=("ppq.apple.com")
    fi

    if ! check_tcp_connection "api.apple-cloudkit.com" "443"; then
        security_unreachable+=("api.apple-cloudkit.com")
    fi

    # Check OS/Software update services
    if ! check_tcp_connection "osrecovery.apple.com" "443"; then
        update_unreachable+=("osrecovery.apple.com")
    fi

    if ! check_tcp_connection "oscdn.apple.com" "443"; then
        update_unreachable+=("oscdn.apple.com")
    fi

    if ! check_tcp_connection "swcdn.apple.com" "443"; then
        update_unreachable+=("swcdn.apple.com")
    fi

    if ! check_tcp_connection "swdist.apple.com" "443"; then
        update_unreachable+=("swdist.apple.com")
    fi

    if ! check_tcp_connection "swdownload.apple.com" "443"; then
        update_unreachable+=("swdownload.apple.com")
    fi

    if ! check_tcp_connection "swscan.apple.com" "443"; then
        update_unreachable+=("swscan.apple.com")
    fi

    if ! check_tcp_connection "updates.cdn-apple.com" "443"; then
        update_unreachable+=("updates.cdn-apple.com")
    fi

    # Format the output
    result=""

    # Check security services status
    if [ ${#security_unreachable[@]} -eq 0 ]; then
        result="Security services: All reachable"
    else
        security_list=$(
            IFS=,
            echo "${security_unreachable[*]}"
        )
        result="Security services unreachable: $security_list"
    fi

    # Add update services status
    if [ ${#update_unreachable[@]} -eq 0 ]; then
        result="$result | Update services: All reachable"
    else
        update_list=$(
            IFS=,
            echo "${update_unreachable[*]}"
        )
        result="$result | Update services unreachable: $update_list"
    fi

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
