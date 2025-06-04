#!/bin/bash

# TITLE: Network Requirements Connectivity Checker
# SYNOPSIS: Checks connectivity to essential Apple security and software update services
# DESCRIPTION: This script validates network connectivity to critical Apple services including 
#              security services (OCSP, CRL, PPQ, CloudKit) and software update services 
#              (OS recovery, software distribution, updates). Designed for Intune custom attributes
#              and monitoring purposes to ensure devices can properly communicate with Apple services.
# TAGS: Monitoring,Network
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: IntuneMacAdmins
# VERSION: 1.0
# LASTUPDATE: $(date +%Y-%m-%d)
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   check_network_requirements.sh
#   Outputs connectivity status for Apple security and update services
#
# NOTES:
#   - Requires nc (netcat) command for TCP connectivity testing
#   - Uses 2-second timeout for connection attempts
#   - Logs detailed results to custom attributes log directory
#   - Output format suitable for Intune custom attributes
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Script version
SCRIPT_VERSION="1.0"

# Get the current console user
loggedInUser=$(stat -f "%Su" /dev/console 2>/dev/null)

# Set up logging paths
if [ -n "$loggedInUser" ] && [ "$loggedInUser" != "root" ] && [ "$loggedInUser" != "_windowserver" ]; then
    USER_HOME=$(dscl . -read /Users/"$loggedInUser" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    LOG_DIR="$USER_HOME/Library/Logs/Microsoft/Custom Attributes"
else
    LOG_DIR="/var/log"
fi

LOG_FILE="$LOG_DIR/network_connectivity.log"

# Connection timeout in seconds
CONNECTION_TIMEOUT=2

# Initialize arrays for unreachable services
security_unreachable=()
update_unreachable=()

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to output result (for Intune custom attributes)
output_result() {
    echo "$1"
    exit 0
}

# Function to check minimum OS version
check_os_version() {
    local required_version=$1
    local current_version=$(sw_vers -productVersion)
    
    if [[ $(echo -e "$current_version\n$required_version" | sort -V | head -n1) != "$required_version" ]]; then
        log_message "ERROR" "macOS $required_version or higher is required. Current version: $current_version"
        output_result "Unsupported OS: $current_version (requires $required_version+)"
    fi
}

# Function to create log directory
setup_logging() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        if [ $? -ne 0 ]; then
            output_result "Error: Failed to create log directory"
        fi
    fi
}

# Function to check if required commands are available
check_prerequisites() {
    for cmd in nc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            local error_msg="Required command not found: $cmd"
            log_message "ERROR" "$error_msg"
            output_result "Error: $error_msg"
        fi
    done
}

# Function to check TCP connectivity
check_tcp_connection() {
    local domain="$1"
    local port="$2"

    log_message "INFO" "Checking TCP connectivity to $domain:$port"
    
    # Use nc (netcat) to test TCP connection with timeout
    if nc -zw"$CONNECTION_TIMEOUT" "$domain" "$port" 2>/dev/null; then
        log_message "INFO" "$domain:$port is CONNECTED"
        return 0
    else
        log_message "WARN" "$domain:$port connection FAILED"
        return 1
    fi
}

# Function to check security services
check_security_services() {
    log_message "INFO" "Checking security services"
    
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
}

# Function to check update services
check_update_services() {
    log_message "INFO" "Checking update services"
    
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
}

# Function to format final result
format_result() {
    local result=""

    # Check security services status
    if [ ${#security_unreachable[@]} -eq 0 ]; then
        result="Security services: All reachable"
    else
        local security_list=$(IFS=,; echo "${security_unreachable[*]}")
        result="Security services unreachable: $security_list"
    fi

    # Add update services status
    if [ ${#update_unreachable[@]} -eq 0 ]; then
        result="$result | Update services: All reachable"
    else
        local update_list=$(IFS=,; echo "${update_unreachable[*]}")
        result="$result | Update services unreachable: $update_list"
    fi

    echo "$result"
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    log_message "INFO" "Starting network connectivity checks (v$SCRIPT_VERSION)"
    
    # Check OS version requirement
    check_os_version "10.15"
    
    # Set up logging
    setup_logging
    
    # Check prerequisites
    check_prerequisites
    
    # Perform connectivity checks
    check_security_services
    check_update_services
    
    # Format and output result
    local result=$(format_result)
    log_message "INFO" "Check completed. Result: $result"
    
    # Output result for Intune custom attributes
    output_result "$result"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Handle errors gracefully for Intune custom attributes
trap 'output_result "Error: Script failed unexpectedly"' ERR

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# ============================================================================
# CLEANUP
# ============================================================================

# Exit successfully (handled by output_result function)