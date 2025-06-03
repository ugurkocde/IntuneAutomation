#!/bin/bash

# TITLE: [Script Title - Brief descriptive name]
# SYNOPSIS: [One-line description of what the script does]
# DESCRIPTION: [Detailed description of the script's functionality, purpose, and use cases]
# TAGS: [Category],[Subcategory] (e.g., Monitoring,Device or Security,Compliance)
# PLATFORM: macOS
# MIN_OS_VERSION: [Minimum macOS version required - e.g., 10.15]
# AUTHOR: [Your Name]
# VERSION: [Version number - start with 1.0]
# LASTUPDATE: [Date of last update]
# CHANGELOG:
#   [Version] - [Description of changes]
#   1.0 - Initial release
#
# EXAMPLE:
#   [Script filename]
#   [Description of what this example does]
#
# NOTES:
#   [Additional notes, requirements, or important information]
#   - [Any special requirements or dependencies]
#   - [Performance considerations]
#   - [Known limitations]
#   - For more scripts and guides, visit: IntuneMacAdmins.com

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Script version
SCRIPT_VERSION="1.0"

# Get the current console user (if needed)
# Note: Returns "root" or "_windowserver" when no user is logged in
loggedInUser=$(stat -f "%Su" /dev/console 2>/dev/null)

# Common paths (initialize only if user is valid)
if [ -n "$loggedInUser" ] && [ "$loggedInUser" != "root" ] && [ "$loggedInUser" != "_windowserver" ]; then
    USER_HOME=$(dscl . -read /Users/"$loggedInUser" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    LIBRARY_PATH="$USER_HOME/Library"
fi

# Optional: Logging setup (comment out for Intune custom attributes)
# LOG_DIR="/var/log"
# LOG_FILE="$LOG_DIR/intune-script-$(date +%Y%m%d).log"

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function to log messages (optional - remove for Intune custom attributes)
# log_message() {
#     local level=$1
#     local message=$2
#     local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
#     echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
# }

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
        # For logging scripts:
        # log_message "ERROR" "macOS $required_version or higher is required. Current version: $current_version"
        # For Intune custom attributes:
        output_result "Unsupported OS: $current_version (requires $required_version+)"
    fi
}

# Function to check if running as root (if needed)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        # For logging scripts:
        # log_message "ERROR" "This script must be run as root"
        # For Intune custom attributes:
        output_result "Error: Root access required"
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    # Add your prerequisite checks here
    # For logging scripts:
    # log_message "INFO" "Validating prerequisites..."
    
    # Example: Check if a specific directory exists
    # if [[ ! -d "/path/to/required/directory" ]]; then
    #     # For logging scripts:
    #     # log_message "ERROR" "Required directory not found"
    #     # For Intune custom attributes:
    #     # output_result "Error: Required directory not found"
    # fi
    
    return 0
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # For logging scripts:
    # log_message "INFO" "Starting script execution (v$SCRIPT_VERSION)"
    
    # Check OS version if required
    # check_os_version "10.15"
    
    # Check if root access is needed
    # check_root
    
    # Validate prerequisites
    validate_prerequisites
    
    # Add your main script logic here
    # For logging scripts:
    # log_message "INFO" "Executing main logic..."
    
    # Example: Process some data
    # if [[ -f "/path/to/file" ]]; then
    #     process_file "/path/to/file"
    # else
    #     # For logging scripts:
    #     # log_message "WARN" "File not found, skipping processing"
    #     # For Intune custom attributes:
    #     # output_result "File not found"
    # fi
    
    # Example: Collect information
    # device_info=$(system_profiler SPHardwareDataType)
    
    # Example: Check multiple user directories
    # for userHome in /Users/*; do
    #     if [[ "$userHome" == "/Users/Shared" ]] || [[ "$userHome" == "/Users/Guest" ]]; then
    #         continue
    #     fi
    #     # Process user directory
    # done
    
    # For Intune custom attributes - ensure single line output
    # output_result "Status: OK"
    
    # For logging scripts:
    # log_message "INFO" "Script completed successfully"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# For logging scripts - trap errors and log them
# trap 'log_message "ERROR" "Script failed at line $LINENO with exit code $?"' ERR

# For Intune custom attributes - handle errors gracefully
# trap 'output_result "Error: Script failed"' ERR

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

# Perform any cleanup operations if needed
# cleanup() {
#     log_message "INFO" "Performing cleanup..."
#     # Add cleanup logic here
# }

# trap cleanup EXIT

# Exit successfully (if not using output_result)
exit 0