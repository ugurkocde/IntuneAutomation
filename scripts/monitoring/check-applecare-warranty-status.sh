#!/bin/bash

# TITLE: Check AppleCare Warranty Status
# SYNOPSIS: Checks Apple warranty and AppleCare status on macOS devices
# DESCRIPTION: This script checks the warranty status of Apple devices by reading the local
#              warranty information stored by macOS. It retrieves the coverage end date
#              and displays it in a user-friendly format. The script is designed to work
#              with Intune-managed macOS devices.
# TAGS: Monitoring,Device
# PLATFORM: macOS
# MIN_OS_VERSION: 10.15
# AUTHOR: IntuneAutomation Contributors
# VERSION: 1.0
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
#   - Returns exit code 1 if warranty directory doesn't exist
#   - Returns exit code 0 if no warranty files are found (no coverage)
#   - For more scripts and guides, visit: IntuneMacAdmins.com
#   - Source: https://community.jamf.com/t5/jamf-pro/collecting-warranty-status/m-p/298357#M263560

# ============================================================================
# VARIABLES AND INITIALIZATION
# ============================================================================

# Get the current username
loggedInUser=$(stat -f "%Su" /dev/console)

# Set the warranty directory path
warrantyDir="/Users/$loggedInUser/Library/Application Support/com.apple.NewDeviceOutreach"

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

# Check if the directory exists
if [ ! -d "$warrantyDir" ]; then
    echo "Warranty directory not found. This device may not have warranty information available."
    exit 1
fi

# Check if any Warranty files exist
warrantyFiles=($(ls "$warrantyDir" 2>/dev/null | grep "_Warranty" || true))

if [ ${#warrantyFiles[@]} -eq 0 ]; then
    echo "No warranty information found for this device."
    exit 0
fi

# Initialize a variable for the final output
finalOutput=""

# Loop through each warranty file
for file in "${warrantyFiles[@]}"; do
    # Read the coverage end date from the warranty file
    expires=$(defaults read "$warrantyDir/$file" coverageEndDate 2>/dev/null || echo "")

    if [ -n "$expires" ]; then
        # Convert epoch to a US date format (MM/DD/YYYY)
        ACexpires=$(date -r $expires '+%m/%d/%Y' 2>/dev/null || echo "Unknown")
        
        # Check if the warranty has expired
        currentDate=$(date +%s)
        if [ "$expires" -lt "$currentDate" ]; then
            finalOutput+="Coverage expired on: $ACexpires\n"
        else
            finalOutput+="Coverage expires on: $ACexpires\n"
        fi
    fi
done

# Output the coverage expiration information
if [ -n "$finalOutput" ]; then
    echo -e "$finalOutput"
else
    echo "Unable to determine warranty status."
fi

# Exit successfully
exit 0