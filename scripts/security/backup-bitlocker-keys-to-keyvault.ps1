<#
.TITLE
    BitLocker Keys Backup to Azure Key Vault

.SYNOPSIS
    Backs up BitLocker recovery keys from Entra ID (Azure AD) to Azure Key Vault using REST API.

.DESCRIPTION
    This script connects to Microsoft Graph API to retrieve BitLocker recovery keys for Windows devices,
    then stores them securely in Azure Key Vault using REST API. Each key is stored as a secret with
    device information (name and serial number) included in tags. The script ensures secure storage
    The script uses Microsoft Graph authentication for both Graph API and Key Vault API calls,
    eliminating the need for the large Az.Accounts module. Simply provide your Key Vault URI
    and the script handles the rest. On first run, you will be prompted to consent to the required
    permissions including Key Vault access.

.TAGS
    Security,Compliance

.PLATFORM
    Windows

.MINROLE
    Intune Administrator, Key Vault Secrets Officer (ABAC) or Key Vault Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All,BitlockerKey.Read.All,https://vault.azure.net/user_impersonation

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.EXAMPLE
    .\backup-bitlocker-keys-to-keyvault.ps1 -VaultUri "https://bitlockerfilevaultkeys.vault.azure.net"
    Backs up all BitLocker keys to the specified Azure Key Vault

.EXAMPLE
    .\backup-bitlocker-keys-to-keyvault.ps1 -VaultUri "https://myvault.vault.azure.net" -OverwriteExisting -ShowProgress
    Backs up keys with overwrite option and progress display


.NOTES
    - Requires only Microsoft.Graph.Authentication module (no Az modules needed)
    - Uses REST API directly for Key Vault operations
    - Keys are stored with naming convention: BitLocker-{DeviceName}-{SerialNumber}
    - Each secret includes tags for easy identification and management
    - Consider implementing retention policies in Key Vault
    - Regular backups ensure recovery key availability
    - Vault URI format: https://yourvault.vault.azure.net
    
    PERMISSION CONSENT:
    On first run, you'll be prompted to consent to the following permissions:
    - Azure Key Vault access (https://vault.azure.net/user_impersonation)
    - Read Intune devices (DeviceManagementManagedDevices.Read.All)
    - Read BitLocker keys (BitlockerKey.Read.All)
    
    To avoid the consent prompt:
    - Accept once and check "Consent on behalf of your organization" (admin only)
    - Pre-consent in Azure AD portal under Enterprise Applications
    - For automation, use a service principal with pre-configured permissions
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure Key Vault URI (e.g., https://myvault.vault.azure.net)")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https://[a-zA-Z0-9-]+\.vault\.azure\.net/?$')]
    [string]$VaultUri,
    
    [Parameter(Mandatory = $false, HelpMessage = "Overwrite existing secrets in Key Vault")]
    [switch]$OverwriteExisting,
    
    [Parameter(Mandatory = $false, HelpMessage = "Show progress during processing")]
    [switch]$ShowProgress
)

# ============================================================================
# MODULES AND AUTHENTICATION
# ============================================================================

# Check if required modules are installed
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Error "$Module module is required. Install it using: Install-Module $Module -Scope CurrentUser"
        exit 1
    }
}

# Import required modules
foreach ($Module in $RequiredModules) {
    Import-Module $Module
}

# Ensure VaultUri ends without trailing slash for consistency
$VaultUri = $VaultUri.TrimEnd('/')

# ============================================================================
# AUTHENTICATION
# ============================================================================

# Connect to Microsoft Graph with required scopes including Key Vault
try {
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    $Scopes = @(
        "DeviceManagementManagedDevices.Read.All",
        "BitlockerKey.Read.All",
        "https://vault.azure.net/user_impersonation"  # Required for Key Vault access
    )
    Connect-MgGraph -Scopes $Scopes -NoWelcome
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to get all pages of results from Graph API
function Get-MgGraphAllPage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [int]$DelayMs = 100
    )
    
    $AllResults = @()
    $NextLink = $Uri
    $RequestCount = 0
    
    do {
        try {
            # Add delay to respect rate limits
            if ($RequestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
            
            $Response = Invoke-MgGraphRequest -Uri $NextLink -Method GET
            $RequestCount++
            
            if ($Response.value) {
                $AllResults += $Response.value
            }
            else {
                $AllResults += $Response
            }
            
            $NextLink = $Response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data from $NextLink : $($_.Exception.Message)"
            break
        }
    } while ($NextLink)
    
    return $AllResults
}

# Function to get BitLocker recovery key for a device from Intune
function Get-BitLockerRecoveryKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName = "Unknown"
    )

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        Write-Verbose "Device $DeviceName has no Device ID"
        return $null
    }

    try {
        # Get BitLocker recovery keys from Intune for this device
        # Using the Intune device ID to get recovery keys
        $keyUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/deviceConfigurationStates"
        $configResponse = Invoke-MgGraphRequest -Uri $keyUri -Method GET
        
        # Alternative: Try direct BitLocker key endpoint for Intune managed device
        $bitlockerUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')?`$select=hardwareInformation"
        $hardwareResponse = Invoke-MgGraphRequest -Uri $bitlockerUri -Method GET
        
        # Get BitLocker recovery keys using the Intune endpoint
        # Note: BitLocker keys in Intune are part of the device's configuration
        $recoveryKeyUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceId/windowsProtectionState"
        $protectionResponse = Invoke-MgGraphRequest -Uri $recoveryKeyUri -Method GET
        
        # Check if we have BitLocker info
        if ($protectionResponse.bitLockerStatus -ne "encrypted") {
            Write-Verbose "Device $DeviceName is not BitLocker encrypted"
            return $null
        }
        
        # Try to get the actual recovery key
        # For Intune, we need to use a different approach
        $keys = @()
        
        # Get recovery keys from the device's BitLocker configuration
        $bitlockerKeysUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/securityBaselineStates"
        $keysResponse = Invoke-MgGraphRequest -Uri $bitlockerKeysUri -Method GET -ErrorAction SilentlyContinue
        
        if (-not $keysResponse -or $keysResponse.value.Count -eq 0) {
            # Fallback: Try to get from Azure AD if device is AAD joined
            if ($hardwareResponse.azureADDeviceId) {
                return Get-BitLockerRecoveryKeyFromAzureAD -AzureADDeviceId $hardwareResponse.azureADDeviceId -DeviceName $DeviceName
            }
            
            Write-Verbose "No BitLocker keys found in Intune for device $DeviceName"
            return $null
        }
        
        # Process the keys if found
        foreach ($keyInfo in $keysResponse.value) {
            if ($keyInfo.settingName -like "*BitLocker*" -or $keyInfo.settingName -like "*RecoveryKey*") {
                $keys += @{
                    Id = $keyInfo.id
                    Key = $keyInfo.state
                    VolumeType = "OS"
                    CreatedDateTime = $keyInfo.lastModifiedDateTime
                }
            }
        }
        
        return if ($keys.Count -gt 0) { $keys } else { $null }
    }
    catch {
        Write-Warning "Error retrieving BitLocker key from Intune for device $DeviceName : $($_.Exception.Message)"
        return $null
    }
}

# Helper function to get BitLocker recovery key from Azure AD (fallback)
function Get-BitLockerRecoveryKeyFromAzureAD {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AzureADDeviceId,
        [Parameter(Mandatory = $false)]
        [string]$DeviceName = "Unknown"
    )

    try {
        # Get the key IDs from Azure AD
        $keyIdUri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$AzureADDeviceId'"
        $keyIdResponse = Invoke-MgGraphRequest -Uri $keyIdUri -Method GET
        
        if ($keyIdResponse.value.Count -eq 0) {
            Write-Verbose "No BitLocker keys found in Azure AD for device $DeviceName"
            return $null
        }
        
        $keys = @()
        foreach ($keyInfo in $keyIdResponse.value) {
            # Get the actual recovery key
            $keyUri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($keyInfo.id)?`$select=key"
            $keyResponse = Invoke-MgGraphRequest -Uri $keyUri -Method GET
            
            $keys += @{
                Id = $keyInfo.id
                Key = $keyResponse.key
                VolumeType = $keyInfo.volumeType
                CreatedDateTime = $keyInfo.createdDateTime
            }
        }
        
        return $keys
    }
    catch {
        Write-Warning "Error retrieving BitLocker key from Azure AD for device $DeviceName : $($_.Exception.Message)"
        return $null
    }
}

# Function to get access token for Key Vault
function Get-KeyVaultAccessToken {
    try {
        # Use Microsoft Graph PowerShell to get token
        $token = Get-MgGraphAccessToken
        return $token
    }
    catch {
        Write-Error "Failed to get access token: $($_.Exception.Message)"
        return $null
    }
}

# Function to create or update secret in Key Vault using REST API
function Set-KeyVaultSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretName,
        [Parameter(Mandatory = $true)]
        [string]$SecretValue,
        [Parameter(Mandatory = $true)]
        [hashtable]$Tags,
        [Parameter(Mandatory = $true)]
        [string]$VaultUri
    )
    
    try {
        # Sanitize secret name (remove invalid characters)
        $SecretName = $SecretName -replace '[^a-zA-Z0-9-]', '-'
        
        # Get access token for Key Vault
        $accessToken = Get-KeyVaultAccessToken
        
        # Construct the URI for the Key Vault secret
        $uri = "$VaultUri/secrets/$SecretName`?api-version=7.4"
        
        # Prepare the request body
        $body = @{
            value = $SecretValue
            tags = $Tags
            attributes = @{
                enabled = $true
            }
        } | ConvertTo-Json
        
        # Set headers
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        }
        
        # Make the REST API call
        $response = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body
        
        return @{
            Success = $true
            SecretId = $response.id
            Version = $response.attributes.version
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 'Conflict' -and -not $OverwriteExisting) {
            return @{
                Success = $false
                Error = "Secret already exists. Use -OverwriteExisting to update."
            }
        }
        else {
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Starting BitLocker keys backup to Azure Key Vault..." -InformationAction Continue
    
    # Get all Windows devices from Intune
    Write-Information "Retrieving Windows devices from Intune..." -InformationAction Continue
    $devicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'"
    $devices = Get-MgGraphAllPage -Uri $devicesUri
    
    if ($devices.Count -eq 0) {
        Write-Warning "No Windows devices found in Intune"
        return
    }
    
    Write-Information "Found $($devices.Count) Windows devices. Processing BitLocker keys..." -InformationAction Continue
    
    $results = @()
    $processedCount = 0
    $successCount = 0
    $failedCount = 0
    $skippedCount = 0
    
    foreach ($device in $devices) {
        $processedCount++
        
        if ($ShowProgress) {
            $percentComplete = [math]::Round(($processedCount / $devices.Count) * 100, 1)
            Write-Progress -Activity "Backing up BitLocker Keys" -Status "Processing device: $($device.deviceName)" -PercentComplete $percentComplete
        }
        
        # Get BitLocker recovery keys using Intune device ID
        $recoveryKeys = Get-BitLockerRecoveryKey -DeviceId $device.id -DeviceName $device.deviceName
        
        if (-not $recoveryKeys) {
            Write-Verbose "No BitLocker keys found for device: $($device.deviceName)"
            $results += [PSCustomObject]@{
                DeviceName = $device.deviceName
                SerialNumber = $device.serialNumber
                Status = "No Keys Found"
                KeyVaultSecret = "N/A"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            $skippedCount++
            continue
        }
        
        foreach ($recoveryKey in $recoveryKeys) {
            $secretName = "BitLocker-$($device.deviceName)-$($device.serialNumber)"
            if ($recoveryKeys.Count -gt 1) {
                $secretName += "-$($recoveryKey.VolumeType)"
            }
            
            $tags = @{
                DeviceName = if ($device.deviceName) { $device.deviceName } else { "Unknown" }
                SerialNumber = if ($device.serialNumber) { $device.serialNumber } else { "NoSerial" }
                AzureADDeviceId = $device.azureADDeviceId
                VolumeType = $recoveryKey.VolumeType
                Model = if ($device.model) { $device.model } else { "Unknown" }
                Manufacturer = if ($device.manufacturer) { $device.manufacturer } else { "Unknown" }
                BackupDate = (Get-Date -Format "yyyy-MM-dd")
                Source = "IntuneAutomation"
            }
            
            # Store in Key Vault
            $kvResult = Set-KeyVaultSecret -SecretName $secretName -SecretValue $recoveryKey.Key -Tags $tags -VaultUri $VaultUri
            
            if ($kvResult.Success) {
                Write-Information "✓ Successfully backed up key for: $($device.deviceName)" -InformationAction Continue
                $successCount++
                $status = "Success"
            }
            else {
                Write-Warning "✗ Failed to backup key for $($device.deviceName): $($kvResult.Error)"
                $failedCount++
                $status = "Failed: $($kvResult.Error)"
            }
            
            $results += [PSCustomObject]@{
                DeviceName = $device.deviceName
                SerialNumber = $device.serialNumber
                Status = $status
                KeyVaultSecret = $secretName
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    }
    
    if ($ShowProgress) {
        Write-Progress -Activity "Backing up BitLocker Keys" -Completed
    }
    
    # Display results
    Write-Information "`nBitLocker Keys Backup Results:" -InformationAction Continue
    $results | Format-Table -AutoSize
    
    Write-Information "✓ BitLocker keys backup completed successfully" -InformationAction Continue
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup operations
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Information "Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        # Ignore disconnect errors
    }
    
    # No Azure disconnect needed since we're not using Az modules
}

# ============================================================================
# SCRIPT SUMMARY
# ============================================================================

Write-Information "
========================================
Script Execution Summary
========================================
Script: BitLocker Keys Backup to Key Vault
Total Devices Processed: $processedCount
Successfully Backed Up: $successCount
Failed: $failedCount
Skipped (No Keys): $skippedCount
Key Vault: $VaultUri
Status: Completed
========================================
" -InformationAction Continue