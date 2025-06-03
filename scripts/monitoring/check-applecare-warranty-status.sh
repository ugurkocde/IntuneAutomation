#!/bin/bash

# TITLE: Check AppleCare Warranty Status
# SYNOPSIS: Checks Apple warranty and AppleCare status on macOS devices
# DESCRIPTION: This script checks the warranty status of Apple devices by reading the local
#              warranty information stored by macOS. It retrieves the coverage end date
#              and displays it in a user-friendly format. The script is designed to work
#              with Intune-managed macOS devices as a custom attribute.
# TAGS: Monitoring,Device
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: Ugur Koc
# VERSION: 1.0
# LASTUPDATE: 2025-06-02
# CHANGELOG:
#   1.0 - Initial release
#
# EXAMPLE:
#   ./check-applecare-warranty-status.sh
#   Checks the warranty status and outputs coverage expiration dates
#
# NOTES:
#   - Script reads warranty information from macOS system files
#   - No external dependencies required
#   - Designed for Intune custom attributes (single line output)
#   - Works when run as root or user context
#   - For more scripts and guides, visit: IntuneMacAdmins.com
#   - Source: https://community.jamf.com/t5/jamf-pro/collecting-warranty-status/m-p/298357#M263560

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Function to check warranty for a specific user
check_user_warranty() {
    local user_home="$1"
    local warrantyDir="$user_home/Library/Application Support/com.apple.NewDeviceOutreach"
    
    # Check if the directory exists
    if [ ! -d "$warrantyDir" ]; then
        return 1
    fi
    
    # Find warranty files
    local warrantyFiles
    warrantyFiles=$(find "$warrantyDir" -maxdepth 1 -name "*_Warranty*" -type f 2>/dev/null)
    
    if [ -z "$warrantyFiles" ]; then
        return 1
    fi
    
    # Get the most recent warranty file
    local latestFile
    latestFile=$(echo "$warrantyFiles" | xargs ls -t 2>/dev/null | head -n1)
    
    if [ -z "$latestFile" ]; then
        return 1
    fi
    
    # Read the coverage end date
    local expires
    expires=$(defaults read "$latestFile" coverageEndDate 2>/dev/null || echo "")
    
    if [ -n "$expires" ]; then
        # Convert epoch to ISO-8601 format for better compatibility
        local ACexpires
        ACexpires=$(date -r "$expires" '+%Y-%m-%d' 2>/dev/null || echo "")
        
        if [ -n "$ACexpires" ]; then
            # Check if warranty has expired
            local currentDate
            currentDate=$(date +%s)
            if [ "$expires" -lt "$currentDate" ]; then
                echo "Expired: $ACexpires"
            else
                echo "Expires: $ACexpires"
            fi
            return 0
        fi
    fi
    
    return 1
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

# Try to get warranty information
# First, try the current console user
loggedInUser=$(stat -f "%Su" /dev/console 2>/dev/null)

if [ -n "$loggedInUser" ] && [ "$loggedInUser" != "root" ] && [ "$loggedInUser" != "_windowserver" ]; then
    # Check logged in user's warranty
    userHome=$(dscl . -read /Users/"$loggedInUser" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    if [ -n "$userHome" ] && [ -d "$userHome" ]; then
        result=$(check_user_warranty "$userHome")
        if [ -n "$result" ]; then
            echo "$result"
            exit 0
        fi
    fi
fi

# If no console user or warranty not found, check all user directories
for userHome in /Users/*; do
    # Skip system directories
    if [[ "$userHome" == "/Users/Shared" ]] || [[ "$userHome" == "/Users/Guest" ]]; then
        continue
    fi
    
    if [ -d "$userHome" ]; then
        result=$(check_user_warranty "$userHome")
        if [ -n "$result" ]; then
            echo "$result"
            exit 0
        fi
    fi
done

# If we get here, no warranty information was found
echo "No warranty information"
exit 0