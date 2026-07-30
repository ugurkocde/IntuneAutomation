<#
.TITLE
    Endpoint Analytics Report

.SYNOPSIS
    Generate comprehensive Endpoint Analytics reports from Microsoft Intune including startup performance, application reliability, battery health, and work from anywhere metrics.

.DESCRIPTION
    This script connects to Microsoft Graph API (beta) and retrieves Endpoint Analytics data from Intune.
    It collects metrics across multiple categories including device startup performance, application reliability,
    battery health, work from anywhere readiness, and overall device scores. Results are exported to CSV and HTML
    formats for analysis and reporting purposes.

.TAGS
    Monitoring,Reporting

.MINROLE
    Intune Administrator

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All

.AUTHOR
    Ugur Koc

.VERSION
    1.4

.CHANGELOG
    1.4 - Added Azure Automation contract validation, portal-safe boolean parameters, beta Graph endpoints, and terminating paging errors
    1.3 - Azure Automation now records script progress, outcomes, and summaries in job history
    1.2 - The ShowProgress switch now drives Write-Progress during metric collection; analytics queries select only the fields the report consumes; output directory is created automatically before exports; pagination helper keeps single-item results as arrays
    1.1 - Local runs now use MgGraphCommunity for WAM-free interactive sign-in (auto-installed if missing); work from anywhere metrics now use the allDevices metricDevices endpoint
    1.0 - Initial release

.LASTUPDATE
    2026-07-30

.EXAMPLE
    .\get-endpoint-analytics-report.ps1
    Generates a complete Endpoint Analytics report with all metrics

.EXAMPLE
    .\get-endpoint-analytics-report.ps1 -OutputPath "C:\Reports" -IncludeStartupPerformance "true"
    Generates report with only startup performance metrics

.EXAMPLE
    .\get-endpoint-analytics-report.ps1 -IncludeAll "true" -ExportJson "true"
    Generates report with all metrics and exports to both CSV and JSON formats

.NOTES
    - Requires Microsoft.Graph.Authentication module: Install-Module Microsoft.Graph.Authentication
    - Uses Microsoft Graph Beta API endpoints
    - Some features require Intune Advanced Analytics license
    - Battery Health metrics require Windows 10/11 devices
    - Endpoint Analytics must be enabled in Intune
    - Documentation: https://learn.microsoft.com/en-us/intune/analytics/overview
    - Local interactive sign-in uses the MgGraphCommunity module to avoid the Graph SDK's mandatory WAM broker on Windows
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Directory path to save reports")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Include startup performance metrics")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeStartupPerformance,

    [Parameter(Mandatory = $false, HelpMessage = "Include application reliability metrics")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeAppReliability,

    [Parameter(Mandatory = $false, HelpMessage = "Include battery health metrics")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeBatteryHealth,

    [Parameter(Mandatory = $false, HelpMessage = "Include work from anywhere metrics")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeWorkFromAnywhere,

    [Parameter(Mandatory = $false, HelpMessage = "Include all available metrics")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$IncludeAll,

    [Parameter(Mandatory = $false, HelpMessage = "Export results in JSON format as well")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ExportJson,

    [Parameter(Mandatory = $false, HelpMessage = "Show progress during processing")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ShowProgress,

    [Parameter(Mandatory = $false, HelpMessage = "Force module installation without prompting")]
    [ValidateSet("true", "false", "1", "0", '$true', '$false')]
    [string]$ForceModuleInstall
)

# Normalize the local module-install override for Azure Automation parameter binding.
$forceModuleInstallRaw = [string]$ForceModuleInstall
Remove-Variable -Name ForceModuleInstall
if ([string]::IsNullOrWhiteSpace($forceModuleInstallRaw)) {
    $ForceModuleInstall = $false
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("true", "1", '$true')) {
    $ForceModuleInstall = $true
}
elseif ($forceModuleInstallRaw.Trim().ToLowerInvariant() -in @("false", "0", '$false')) {
    $ForceModuleInstall = $false
}
else {
    throw "Parameter 'ForceModuleInstall' accepts only true, false, 1, 0, $true, or $false."
}

# Azure Automation supplies portal parameter values as strings. Normalize the
# public boolean parameters once so local and runbook execution use real booleans.
foreach ($runbookBooleanParameter in @('IncludeStartupPerformance', 'IncludeAppReliability', 'IncludeBatteryHealth', 'IncludeWorkFromAnywhere', 'IncludeAll', 'ExportJson', 'ShowProgress')) {
    $runbookBooleanRaw = [string](Get-Variable -Name $runbookBooleanParameter -ValueOnly)
    Remove-Variable -Name $runbookBooleanParameter

    if ([string]::IsNullOrWhiteSpace($runbookBooleanRaw)) {
        Set-Variable -Name $runbookBooleanParameter -Value $false
        continue
    }

    switch ($runbookBooleanRaw.Trim().ToLowerInvariant()) {
        { $_ -in @("true", "1", '$true') } {
            Set-Variable -Name $runbookBooleanParameter -Value $true
        }
        { $_ -in @("false", "0", '$false') } {
            Set-Variable -Name $runbookBooleanParameter -Value $false
        }
        default {
            throw "Parameter '$runbookBooleanParameter' accepts only true, false, 1, 0, $true, or $false."
        }
    }
}

# If no specific category is selected, include all by default
if (-not ($IncludeStartupPerformance -or $IncludeAppReliability -or $IncludeBatteryHealth -or $IncludeWorkFromAnywhere -or $IncludeAll)) {
    $IncludeAll = $true
}

# If IncludeAll is set, enable all categories
if ($IncludeAll) {
    $IncludeStartupPerformance = $true
    $IncludeAppReliability = $true
    $IncludeBatteryHealth = $true
    $IncludeWorkFromAnywhere = $true
}

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
                $errorMessage = @"
Module '$ModuleName' is not available in this Azure Automation Account.

To resolve this issue:
1. Go to Azure Portal
2. Navigate to your Automation Account
3. Go to 'Modules' > 'Browse Gallery'
4. Search for '$ModuleName'
5. Click 'Import' and wait for installation to complete
"@
                throw $errorMessage
            }
            else {
                Write-Information "Module '$ModuleName' not found. Attempting to install..." -InformationAction Continue

                if (-not $ForceInstall) {
                    $response = Read-Host "Install module '$ModuleName'? (Y/N)"
                    if ($response -notmatch '^[Yy]') {
                        throw "Module '$ModuleName' is required but installation was declined."
                    }
                }

                try {
                    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                    $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }

                    Write-Information "Installing '$ModuleName' in scope '$scope'..." -InformationAction Continue
                    Install-Module -Name $ModuleName -Scope $scope -Force -AllowClobber -Repository PSGallery
                    Write-Information "✓ Successfully installed '$ModuleName'" -InformationAction Continue
                }
                catch {
                    throw "Failed to install module '$ModuleName': $($_.Exception.Message)"
                }
            }
        }

        try {
            Write-Verbose "Importing module: $ModuleName"
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Verbose "✓ Successfully imported '$ModuleName'"
        }
        catch {
            throw "Failed to import module '$ModuleName': $($_.Exception.Message)"
        }
    }
}

# Detect execution environment
if ($PSPrivateMetadata.JobId.Guid) {
    Write-Output "Running inside Azure Automation Runbook"
    $IsAzureAutomation = $true
}
else {
    Write-Output "Running locally in IDE or terminal"
    $IsAzureAutomation = $false
}

# Initialize required modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication"
)

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
        Write-Output "✓ Successfully connected to Microsoft Graph using Managed Identity"
    }
    else {
        Write-Output "Connecting to Microsoft Graph with interactive authentication..."
        $Scopes = @(
            "DeviceManagementManagedDevices.Read.All"
        )
        Connect-MgGraphCommunity -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-Output "✓ Successfully connected to Microsoft Graph"
    }
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
    $requestCount = 0

    do {
        try {
            if ($requestCount -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }

            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
            $requestCount++

            if ($response.value) {
                $allResults += $response.value
            }
            else {
                $allResults += $response
            }

            $nextLink = $response.'@odata.nextLink'

            if ($requestCount % 10 -eq 0) {
                Write-Verbose "Processed $requestCount requests..."
            }
        }
        catch {
            if ($_.Exception.Message -like "*429*" -or $_.Exception.Message -like "*throttled*") {
                Write-Information "`nRate limit hit, waiting 60 seconds..." -InformationAction Continue
                Start-Sleep -Seconds 60
                continue
            }
            throw "Error fetching data from $nextLink : $($_.Exception.Message)"
        }
    } while ($nextLink)

    # Comma prevents unrolling so single-element results stay arrays
    return , $allResults
}

function Get-SafeAverage {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Property,

        [double]$Divisor = 1
    )

    $numericValues = @(
        foreach ($item in $InputObject) {
            $propertyValue = $item.PSObject.Properties[$Property].Value
            if ($null -ne $propertyValue -and $propertyValue -is [System.IConvertible]) {
                try { [double]$propertyValue } catch { continue }
            }
        }
    )

    if ($numericValues.Count -eq 0) { return 0 }
    return [math]::Round(($numericValues | Measure-Object -Average).Average / $Divisor, 1)
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

try {
    Write-Output "Starting Endpoint Analytics report generation..."

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $allMetrics = @{}

    # Device Scores - Always collect for overview
    Write-Output "Retrieving device scores..."
    if ($ShowProgress -and -not $IsAzureAutomation) {
        Write-Progress -Activity "Endpoint Analytics Report" -Status "Retrieving device scores" -PercentComplete 10
    }
    try {
        $deviceScoresUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDeviceScores?`$select=id,deviceName,model,endpointAnalyticsScore,startupPerformanceScore,appReliabilityScore,batteryHealthScore"
        $deviceScores = Get-MgGraphAllPage -Uri $deviceScoresUri
        $allMetrics['DeviceScores'] = $deviceScores
        Write-Output "✓ Retrieved $($deviceScores.Count) device score records"
    }
    catch {
        Write-Warning "Failed to retrieve device scores: $($_.Exception.Message)"
        $allMetrics['DeviceScores'] = @()
    }

    # Startup Performance
    if ($IncludeStartupPerformance) {
        Write-Output "Retrieving startup performance metrics..."
        if ($ShowProgress -and -not $IsAzureAutomation) {
            Write-Progress -Activity "Endpoint Analytics Report" -Status "Retrieving startup performance metrics" -PercentComplete 30
        }
        try {
            $startupHistoryUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDeviceStartupHistory"
            $startupHistory = Get-MgGraphAllPage -Uri $startupHistoryUri
            $allMetrics['StartupHistory'] = $startupHistory
            Write-Output "✓ Retrieved $($startupHistory.Count) startup history records"

            $devicePerformanceUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsDevicePerformance?`$select=id,deviceName,model,manufacturer,coreBootTimeInMs,groupPolicyBootTimeInMs"
            $devicePerformance = Get-MgGraphAllPage -Uri $devicePerformanceUri
            $allMetrics['DevicePerformance'] = $devicePerformance
            Write-Output "✓ Retrieved $($devicePerformance.Count) device performance records"
        }
        catch {
            Write-Warning "Failed to retrieve startup performance: $($_.Exception.Message)"
            $allMetrics['StartupHistory'] = @()
            $allMetrics['DevicePerformance'] = @()
        }
    }

    # Application Reliability
    if ($IncludeAppReliability) {
        Write-Output "Retrieving application reliability metrics..."
        if ($ShowProgress -and -not $IsAzureAutomation) {
            Write-Progress -Activity "Endpoint Analytics Report" -Status "Retrieving application reliability metrics" -PercentComplete 50
        }
        try {
            $appHealthDeviceUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthDevicePerformanceDetails"
            $appHealthDevice = Get-MgGraphAllPage -Uri $appHealthDeviceUri
            $allMetrics['AppHealthDevice'] = $appHealthDevice
            Write-Output "✓ Retrieved $($appHealthDevice.Count) app health device records"

            $appHealthAppUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsAppHealthApplicationPerformance?`$select=appDisplayName,appCrashCount,activeDeviceCount"
            $appHealthApp = Get-MgGraphAllPage -Uri $appHealthAppUri
            $allMetrics['AppHealthApplication'] = $appHealthApp
            Write-Output "✓ Retrieved $($appHealthApp.Count) app health application records"
        }
        catch {
            Write-Warning "Failed to retrieve application reliability: $($_.Exception.Message)"
            $allMetrics['AppHealthDevice'] = @()
            $allMetrics['AppHealthApplication'] = @()
        }
    }

    # Battery Health
    if ($IncludeBatteryHealth) {
        Write-Output "Retrieving battery health metrics..."
        if ($ShowProgress -and -not $IsAzureAutomation) {
            Write-Progress -Activity "Endpoint Analytics Report" -Status "Retrieving battery health metrics" -PercentComplete 70
        }
        try {
            $batteryOsUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsBatteryHealthOsPerformance"
            $batteryOs = Get-MgGraphAllPage -Uri $batteryOsUri
            $allMetrics['BatteryOsPerformance'] = $batteryOs
            Write-Output "✓ Retrieved $($batteryOs.Count) battery OS performance records"

            $batteryDeviceUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsBatteryHealthDevicePerformance?`$select=id,deviceName,model,deviceBatteryHealthScore,maxCapacityPercentage,batteryAgeInDays"
            $batteryDevice = Get-MgGraphAllPage -Uri $batteryDeviceUri
            $allMetrics['BatteryDevicePerformance'] = $batteryDevice
            Write-Output "✓ Retrieved $($batteryDevice.Count) battery device performance records"
        }
        catch {
            Write-Warning "Failed to retrieve battery health: $($_.Exception.Message)"
            $allMetrics['BatteryOsPerformance'] = @()
            $allMetrics['BatteryDevicePerformance'] = @()
        }
    }

    # Work From Anywhere
    if ($IncludeWorkFromAnywhere) {
        Write-Output "Retrieving work from anywhere metrics..."
        if ($ShowProgress -and -not $IsAzureAutomation) {
            Write-Progress -Activity "Endpoint Analytics Report" -Status "Retrieving work from anywhere metrics" -PercentComplete 90
        }
        try {
            $wfaUri = "https://graph.microsoft.com/beta/deviceManagement/userExperienceAnalyticsWorkFromAnywhereMetrics('allDevices')/metricDevices"
            $wfaMetrics = Get-MgGraphAllPage -Uri $wfaUri
            $allMetrics['WorkFromAnywhere'] = $wfaMetrics
            Write-Output "✓ Retrieved $($wfaMetrics.Count) work from anywhere records"
        }
        catch {
            Write-Warning "Failed to retrieve work from anywhere metrics: $($_.Exception.Message)"
            $allMetrics['WorkFromAnywhere'] = @()
        }
    }

    if ($ShowProgress -and -not $IsAzureAutomation) {
        Write-Progress -Activity "Endpoint Analytics Report" -Completed
    }

    # Create output directory if it does not exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Output "Created output directory: $OutputPath"
    }

    # Export results to CSV
    Write-Output "Exporting results to CSV..."

    foreach ($key in $allMetrics.Keys) {
        if ($allMetrics[$key].Count -gt 0) {
            $csvPath = Join-Path $OutputPath "EndpointAnalytics_${key}_$timestamp.csv"
            try {
                $allMetrics[$key] | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
                Write-Output "✓ Exported $key to: $csvPath"
            }
            catch {
                Write-Warning "Failed to export $key to CSV: $($_.Exception.Message)"
            }
        }
    }

    # Export to JSON if requested
    if ($ExportJson) {
        Write-Output "Exporting results to JSON..."
        foreach ($key in $allMetrics.Keys) {
            if ($allMetrics[$key].Count -gt 0) {
                $jsonPath = Join-Path $OutputPath "EndpointAnalytics_${key}_$timestamp.json"
                try {
                    $allMetrics[$key] | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8
                    Write-Output "✓ Exported $key to: $jsonPath"
                }
                catch {
                    Write-Warning "Failed to export $key to JSON: $($_.Exception.Message)"
                }
            }
        }
    }

    # Calculate Analytics and Statistics
    Write-Output "Calculating analytics statistics..."

    # Device Scores Analytics
    $avgEndpointScore = Get-SafeAverage -InputObject @($allMetrics['DeviceScores']) -Property 'endpointAnalyticsScore'
    $avgStartupScore = Get-SafeAverage -InputObject @($allMetrics['DeviceScores']) -Property 'startupPerformanceScore'
    $avgAppReliabilityScore = Get-SafeAverage -InputObject @($allMetrics['DeviceScores']) -Property 'appReliabilityScore'

    # Startup Performance Analytics
    $slowBootDevices = @()
    $avgBootTime = 0
    if ($IncludeStartupPerformance -and $allMetrics['DevicePerformance'].Count -gt 0) {
        # Calculate total boot time (core + group policy)
        $bootTimeRecords = @(
            $allMetrics['DevicePerformance'] | ForEach-Object {
                [pscustomobject]@{
                    totalBootTime = [double]$_.coreBootTimeInMs + [double]$_.groupPolicyBootTimeInMs
                }
            }
        )
        $avgBootTime = Get-SafeAverage -InputObject $bootTimeRecords -Property 'totalBootTime' -Divisor 1000
        $slowBootDevices = $allMetrics['DevicePerformance'] |
            Where-Object { ($_.coreBootTimeInMs + $_.groupPolicyBootTimeInMs) -gt 60000 } |
            Sort-Object { $_.coreBootTimeInMs + $_.groupPolicyBootTimeInMs } -Descending |
            Select-Object -First 10 deviceName, @{N='BootTimeSec';E={[math]::Round(($_.coreBootTimeInMs + $_.groupPolicyBootTimeInMs)/1000,1)}}, model, manufacturer
    }

    # App Reliability Analytics
    $topCrashingApps = @()
    if ($IncludeAppReliability -and $allMetrics['AppHealthApplication'].Count -gt 0) {
        $topCrashingApps = $allMetrics['AppHealthApplication'] |
            Where-Object { $_.appCrashCount -gt 0 } |
            Sort-Object appCrashCount -Descending |
            Select-Object -First 10 appDisplayName, appCrashCount, activeDeviceCount
    }

    # Battery Health Analytics
    $lowBatteryDevices = @()
    $avgBatteryHealth = 0
    if ($IncludeBatteryHealth -and $allMetrics['BatteryDevicePerformance'].Count -gt 0) {
        $avgBatteryHealth = Get-SafeAverage -InputObject @($allMetrics['BatteryDevicePerformance']) -Property 'deviceBatteryHealthScore'
        $lowBatteryDevices = $allMetrics['BatteryDevicePerformance'] |
            Where-Object { $_.maxCapacityPercentage -lt 60 } |
            Sort-Object maxCapacityPercentage |
            Select-Object -First 10 deviceName, maxCapacityPercentage, batteryAgeInDays, model
    }

    # Generate HTML Summary Report
    Write-Output "Generating HTML summary report..."

    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Endpoint Analytics Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .summary-item { text-align: center; padding: 20px; background-color: #f8f9fa; border-radius: 8px; border-left: 4px solid #0078d4; }
        .summary-number { font-size: 36px; font-weight: bold; color: #0078d4; margin-bottom: 5px; }
        .summary-label { font-size: 14px; color: #666; }
        .score-good { color: #107c10; }
        .score-warning { color: #ff8c00; }
        .score-bad { color: #d13438; }
        .section { background-color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-top: 0; color: #0078d4; border-bottom: 2px solid #0078d4; padding-bottom: 10px; margin-bottom: 15px; }
        .section h3 { color: #333; font-size: 18px; margin-top: 20px; margin-bottom: 10px; }
        .top-lists { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
        .top-list { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .top-item { display: flex; justify-content: space-between; padding: 12px; margin-bottom: 8px; background-color: #f8f9fa; border-radius: 4px; border-left: 3px solid #d13438; }
        .top-item span:first-child { font-weight: 600; }
        .top-item span:last-child { color: #666; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 12px; border-bottom: 1px solid #e1e5e9; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e3f2fd; }
        .metric-badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; }
        .badge-good { background-color: #dff6dd; color: #107c10; }
        .badge-warning { background-color: #fff4ce; color: #ff8c00; }
        .badge-bad { background-color: #fde7e9; color: #d13438; }
        .insight-box { background-color: #f0f8ff; border-left: 4px solid #0078d4; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .insight-box h4 { margin: 0 0 10px 0; color: #0078d4; }
        .footer { margin-top: 20px; text-align: center; color: #6c757d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Endpoint Analytics Report</h1>
        <p>Generated on: $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss")</p>
    </div>

    <div class="summary">
        <h2>Overall Experience Scores</h2>
        <div class="summary-grid">
            <div class="summary-item">
                <div class="summary-number $(if($avgEndpointScore -ge 70){'score-good'}elseif($avgEndpointScore -ge 50){'score-warning'}else{'score-bad'})">$avgEndpointScore</div>
                <div class="summary-label">Endpoint Score</div>
            </div>
            <div class="summary-item">
                <div class="summary-number $(if($avgStartupScore -ge 70){'score-good'}elseif($avgStartupScore -ge 50){'score-warning'}else{'score-bad'})">$avgStartupScore</div>
                <div class="summary-label">Startup Score</div>
            </div>
            <div class="summary-item">
                <div class="summary-number $(if($avgAppReliabilityScore -ge 70){'score-good'}elseif($avgAppReliabilityScore -ge 50){'score-warning'}else{'score-bad'})">$avgAppReliabilityScore</div>
                <div class="summary-label">App Reliability Score</div>
            </div>
            <div class="summary-item">
                <div class="summary-number">$($allMetrics['DeviceScores'].Count)</div>
                <div class="summary-label">Total Devices</div>
            </div>
        </div>
    </div>
"@

    # Startup Performance Section
    if ($IncludeStartupPerformance -and $slowBootDevices.Count -gt 0) {
        $htmlContent += @"
    <div class="top-lists">
        <div class="top-list">
            <h2>Startup Performance</h2>
            <div class="insight-box">
                <h4>Key Insights</h4>
                <p>Average boot time: <strong>$avgBootTime seconds</strong></p>
                <p>Devices with slow boot (&gt;60s): <strong>$($slowBootDevices.Count)</strong></p>
            </div>
            <h3>Slowest Booting Devices</h3>
"@
        foreach ($device in $slowBootDevices) {
            $htmlContent += @"
            <div class="top-item">
                <span>$($device.deviceName)</span>
                <span>$($device.BootTimeSec)s</span>
            </div>
"@
        }
        $htmlContent += "</div>"
    }

    # App Reliability Section
    if ($IncludeAppReliability -and $topCrashingApps.Count -gt 0) {
        if (-not $IncludeStartupPerformance) {
            $htmlContent += '<div class="top-lists">'
        }
        $htmlContent += @"
        <div class="top-list">
            <h2>Application Reliability</h2>
            <div class="insight-box">
                <h4>Key Insights</h4>
                <p>Applications monitored: <strong>$($allMetrics['AppHealthApplication'].Count)</strong></p>
                <p>Apps with crashes: <strong>$($topCrashingApps.Count)</strong></p>
            </div>
            <h3>Top Crashing Applications</h3>
"@
        foreach ($app in $topCrashingApps) {
            $htmlContent += @"
            <div class="top-item">
                <span>$($app.appDisplayName)</span>
                <span>$($app.appCrashCount) crashes</span>
            </div>
"@
        }
        $htmlContent += "</div>"
        if ($IncludeStartupPerformance -or (-not $IncludeBatteryHealth)) {
            $htmlContent += "</div>"
        }
    }

    # Battery Health Section
    if ($IncludeBatteryHealth -and $lowBatteryDevices.Count -gt 0) {
        if (-not ($IncludeStartupPerformance -or $IncludeAppReliability)) {
            $htmlContent += '<div class="top-lists">'
        }
        $htmlContent += @"
        <div class="top-list">
            <h2>Battery Health</h2>
            <div class="insight-box">
                <h4>Key Insights</h4>
                <p>Devices monitored: <strong>$($allMetrics['BatteryDevicePerformance'].Count)</strong></p>
                <p>Devices with low battery (&lt;60%): <strong>$($lowBatteryDevices.Count)</strong></p>
            </div>
            <h3>Devices Needing Battery Replacement</h3>
"@
        foreach ($device in $lowBatteryDevices) {
            $htmlContent += @"
            <div class="top-item">
                <span>$($device.deviceName)</span>
                <span>$($device.maxCapacityPercentage)% capacity</span>
            </div>
"@
        }
        $htmlContent += "</div></div>"
    }

    # Detailed Device Scores Table
    if ($allMetrics['DeviceScores'].Count -gt 0) {
        $htmlContent += @"
    <div class="section">
        <h2>Detailed Device Scores</h2>
        <table>
            <thead>
                <tr>
                    <th>Device Name</th>
                    <th>Model</th>
                    <th>Endpoint Score</th>
                    <th>Startup Score</th>
                    <th>App Reliability</th>
                    <th>Battery Health</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
"@
        foreach ($device in $allMetrics['DeviceScores'] | Sort-Object deviceName) {
            $status = if ($device.endpointAnalyticsScore -ge 70) { "<span class='metric-badge badge-good'>Good</span>" }
                      elseif ($device.endpointAnalyticsScore -ge 50) { "<span class='metric-badge badge-warning'>Fair</span>" }
                      else { "<span class='metric-badge badge-bad'>Poor</span>" }

            $htmlContent += @"
                <tr>
                    <td>$($device.deviceName)</td>
                    <td>$($device.model)</td>
                    <td>$($device.endpointAnalyticsScore)</td>
                    <td>$($device.startupPerformanceScore)</td>
                    <td>$($device.appReliabilityScore)</td>
                    <td>$($device.batteryHealthScore)</td>
                    <td>$status</td>
                </tr>
"@
        }
        $htmlContent += @"
            </tbody>
        </table>
    </div>
"@
    }

    $htmlContent += @"
    <div class="footer">Report generated by Endpoint Analytics Script v1.0</div>
</body>
</html>
"@

    $htmlPath = Join-Path $OutputPath "EndpointAnalytics_Summary_$timestamp.html"
    try {
        $htmlContent | Out-File -FilePath $htmlPath -Encoding utf8
        Write-Output "✓ HTML summary report saved: $htmlPath"
    }
    catch {
        Write-Warning "Failed to generate HTML report: $($_.Exception.Message)"
    }

    Write-Output "`n✓ Endpoint Analytics report generation completed successfully!"
    Write-Output "Reports saved to: $OutputPath"
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph | Out-Null
        Write-Output "✓ Disconnected from Microsoft Graph"
    }
    catch {
        Write-Verbose "Graph disconnection completed (may have already been disconnected)"
    }
}
