<#
.TITLE
    Check Certificate Profile Expiry

.SYNOPSIS
    Audits SCEP, PKCS, and trusted root certificate profiles: validity settings, deployment errors, and root certificates nearing expiry.

.DESCRIPTION
    This script inventories all certificate-related configuration profiles (SCEP,
    PKCS, and trusted certificate profiles) across platforms, reports their validity
    period settings and assignment state, and pulls per-profile deployment status to
    surface devices where certificate delivery is failing. For trusted certificate
    profiles it decodes the embedded root certificate and reports its actual expiry
    date, catching root or issuing CA certificates that will silently break SCEP
    enrollment when they lapse.

.TAGS
    Monitoring,Security

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementConfiguration.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2026-07-20

.EXAMPLE
    .\check-certificate-profile-expiry.ps1
    Audits all certificate profiles with a 90-day expiry warning window

.EXAMPLE
    .\check-certificate-profile-expiry.ps1 -ExpiryWarningDays 180 -ExportToCsv
    Uses a 180-day warning window for embedded root certificates and exports to CSV

.NOTES
    - Requires Microsoft.Graph.Authentication module
    - Individual issued device certificates are not exposed via Graph; this script audits the profiles, their embedded CA certificates, and delivery status
    - Trusted certificate payloads are decoded locally to read the real certificate expiry
    - Uses beta Graph endpoints for the device configuration surface
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Days before an embedded certificate expiry to raise a warning")]
    [ValidateRange(1, 730)]
    [int]$ExpiryWarningDays = 90,

    [Parameter(Mandatory = $false, HelpMessage = "Export results to CSV")]
    [switch]$ExportToCsv,

    [Parameter(Mandatory = $false, HelpMessage = "Output path for exports")]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [switch]$ForceModuleInstall
)

# ============================================================================
# ENVIRONMENT DETECTION AND SETUP
# ============================================================================

function Initialize-RequiredModule {
    param(
        [string[]]$ModuleNames,
        [bool]$IsAutomationEnvironment,
        [bool]$ForceInstall = $false
    )

    foreach ($ModuleName in $ModuleNames) {
        Write-Verbose "Checking module: $ModuleName"

        $module = Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1

        if (-not $module) {
            if ($IsAutomationEnvironment) {
                throw "Module '$ModuleName' is not available in Azure Automation"
            }
            else {
                Write-Information "Module '$ModuleName' not found. Installing..." -InformationAction Continue

                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }

                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }

        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
}

# Detect execution environment
$IsAzureAutomation = $null -ne $PSPrivateMetadata.JobId.Guid

# Initialize required modules
$RequiredModules = @("Microsoft.Graph.Authentication")

# MgGraphCommunity gives WAM-free interactive sign-in for local runs
if (-not $IsAzureAutomation) {
    $RequiredModules += "MgGraphCommunity"
}

try {
    Initialize-RequiredModule -ModuleNames $RequiredModules -IsAutomationEnvironment $IsAzureAutomation -ForceInstall $ForceModuleInstall
    Write-Verbose "✓ All required modules are available"
}
catch {
    Write-Error "Module initialization failed: $_"
    exit 1
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

try {
    if ($IsAzureAutomation) {
        Write-Output "Connecting to Microsoft Graph using Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
        $Scopes = @(
            "DeviceManagementConfiguration.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
    Write-Information "✓ Successfully connected to Microsoft Graph" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-MgGraphAllPage {
    param(
        [string]$Uri,
        [int]$DelayMs = 100
    )

    $allResults = @()
    $nextLink = $Uri

    do {
        try {
            if ($allResults.Count -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET

            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }

            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            if ($_.Exception.Message -like "*429*") {
                Write-Information "Rate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            Write-Warning "Error fetching data: $($_.Exception.Message)"
            break
        }
    } while ($nextLink)

    return $allResults
}

function Get-EmbeddedCertificateExpiry {
    param([object]$CertProfile)

    # Trusted cert profiles embed the certificate as base64 in trustedRootCertificate
    if (-not $CertProfile.trustedRootCertificate) { return $null }

    try {
        $certBytes = [Convert]::FromBase64String($CertProfile.trustedRootCertificate)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
        return [PSCustomObject]@{
            Subject   = $cert.Subject
            NotAfter  = $cert.NotAfter
            Thumbprint = $cert.Thumbprint
        }
    }
    catch {
        Write-Verbose "Could not decode certificate in '$($CertProfile.displayName)': $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Information "Retrieving configuration profiles..." -InformationAction Continue
    $allConfigurations = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=assignments"

    # Certificate-related profile types across all platforms
    $certificateProfiles = @($allConfigurations | Where-Object {
            $_.'@odata.type' -match "ScepCertificateProfile|PkcsCertificateProfile|TrustedRootCertificate|TrustedCertificate"
        })

    if ($certificateProfiles.Count -eq 0) {
        Write-Information "`nNo SCEP, PKCS, or trusted certificate profiles found in this tenant." -InformationAction Continue
        return
    }
    Write-Information "✓ Found $($certificateProfiles.Count) certificate profiles" -InformationAction Continue

    $now = Get-Date
    [System.Collections.Generic.List[Object]]$report = @()

    foreach ($certProfile in $certificateProfiles) {
        $typeName = ([string]$certProfile.'@odata.type') -replace "#microsoft.graph.", ""

        $kind = if ($typeName -match "Scep") { "SCEP" }
        elseif ($typeName -match "Pkcs") { "PKCS" }
        else { "Trusted Certificate" }

        # Deployment health per profile
        $deviceStatuses = Get-MgGraphAllPage -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($certProfile.id)/deviceStatuses"
        $errorCount = @($deviceStatuses | Where-Object { $_.status -in @("error", "conflict", "nonCompliant") }).Count
        $okCount = @($deviceStatuses | Where-Object { $_.status -in @("compliant", "succeeded") }).Count

        # Real certificate expiry for trusted cert profiles
        $embedded = if ($kind -eq "Trusted Certificate") { Get-EmbeddedCertificateExpiry -CertProfile $certProfile } else { $null }
        $embeddedExpiry = ""
        $flag = ""

        if ($embedded) {
            $daysLeft = [math]::Round(($embedded.NotAfter - $now).TotalDays, 0)
            $embeddedExpiry = "$($embedded.NotAfter.ToString('yyyy-MM-dd')) ($daysLeft days)"
            if ($daysLeft -lt 0) { $flag = "CertificateExpired" }
            elseif ($daysLeft -le $ExpiryWarningDays) { $flag = "CertificateExpiring" }
        }

        if (-not $flag) {
            if (@($certProfile.assignments).Count -eq 0) { $flag = "NotAssigned" }
            elseif ($errorCount -gt 0) { $flag = "DeploymentErrors" }
        }

        $validity = ""
        if ($certProfile.certificateValidityPeriodValue) {
            $validity = "$($certProfile.certificateValidityPeriodValue) $($certProfile.certificateValidityPeriodScale)"
        }

        $report.Add([PSCustomObject]@{
                ProfileName     = $certProfile.displayName
                Kind            = $kind
                ProfileType     = $typeName
                IsAssigned      = (@($certProfile.assignments).Count -gt 0)
                ValiditySetting = $validity
                EmbeddedCertExpiry = $embeddedExpiry
                DevicesOk       = $okCount
                DevicesError    = $errorCount
                Flag            = $flag
                ProfileId       = $certProfile.id
            })
    }

    # ----- Display results -----
    Write-Information "`nCERTIFICATE PROFILE AUDIT" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Expiry warning window: $ExpiryWarningDays days | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue

    foreach ($kindGroup in ($report | Group-Object -Property Kind | Sort-Object Name)) {
        Write-Information "`n$($kindGroup.Name) profiles ($($kindGroup.Count)):" -InformationAction Continue
        foreach ($row in ($kindGroup.Group | Sort-Object ProfileName)) {
            $assignedLabel = if ($row.IsAssigned) { "assigned" } else { "NOT ASSIGNED" }
            $line = "  $($row.ProfileName) [$assignedLabel]"
            if ($row.Flag) { $line += " [$($row.Flag)]" }
            Write-Information $line -InformationAction Continue

            if ($row.ValiditySetting) {
                Write-Information "    Issued cert validity: $($row.ValiditySetting)" -InformationAction Continue
            }
            if ($row.EmbeddedCertExpiry) {
                Write-Information "    Embedded certificate expires: $($row.EmbeddedCertExpiry)" -InformationAction Continue
            }
            Write-Information "    Deployment: $($row.DevicesOk) ok, $($row.DevicesError) errors" -InformationAction Continue
        }
    }

    # Summary
    $flagged = @($report | Where-Object { $_.Flag })
    Write-Information "`n" -InformationAction Continue
    Write-Information ("=" * 50) -InformationAction Continue
    Write-Information "Summary: $($report.Count) certificate profiles | $($flagged.Count) flagged" -InformationAction Continue
    foreach ($row in $flagged) {
        Write-Information "  [$($row.Flag)] $($row.ProfileName)" -InformationAction Continue
    }
    Write-Information ("=" * 50) -InformationAction Continue

    # Export to CSV if requested
    if ($ExportToCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $csvPath = Join-Path $OutputPath "Certificate_Profile_Audit_$timestamp.csv"
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Information "✓ CSV report saved: $csvPath" -InformationAction Continue
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        $null = Disconnect-MgGraph
        Write-Information "✓ Disconnected from Microsoft Graph" -InformationAction Continue
    }
    catch {
        Write-Verbose "Graph disconnection completed"
    }
}
