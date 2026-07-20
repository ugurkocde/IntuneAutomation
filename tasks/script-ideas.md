# Script ideas backlog

Curated list of new script ideas for the IntuneAutomation catalog. Checked against the current 34 scripts in `scripts/` for overlap (2026-07-20).

Status: all 30 ideas below were implemented on 2026-07-20 (34 script files; remediation ideas are detection + action pairs). Every Graph endpoint was verified against the live tenant via the Lokka MCP before implementation, including create/delete round trips for the restore paths. Idea names map 1:1 to the script filenames, except idea 25 whose detection script is detect-winget-updates-available.ps1.

Hard constraint: every idea must be runnable by a native Intune Administrator (`.MINROLE` Intune Administrator). No idea may require Security Reader, Conditional Access Administrator, Global Admin, or other roles an Intune admin does not hold. Scopes listed are delegated scopes for the interactive MgGraphCommunity path; the Azure Automation runbook path uses the matching application permissions on the managed identity.

Before implementing any idea:

1. Verify its Graph endpoints, scopes, and role requirements end-to-end with the Lokka MCP and the msgraph skill, using an Intune-admin-only connection as the probe. Never rely on assumed endpoints, payloads, or response shapes.
2. Start authoring from `get_script_authoring_guide` (intuneautomation MCP) and the matching template in `templates/`, per CONTRIBUTING.md.

## configuration (new folder, activates the unused Configuration tag)

1. backup-intune-configuration - Export all configuration profiles, compliance policies, and platform scripts to JSON for backup and versioning. Scopes: DeviceManagementConfiguration.Read.All
2. restore-intune-configuration - Companion restore/import of the JSON backup. Scopes: DeviceManagementConfiguration.ReadWrite.All
3. get-assignment-matrix-report - "Who gets what": every policy, app, and profile mapped to its target groups and filters, CSV + HTML. Scopes: DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All, Group.Read.All
4. get-group-assignments - Given an Entra group, list everything Intune assigns to it. Scopes: same as idea 3
5. get-policy-drift-report - Diff current settings catalog policies against an exported baseline and report changed settings. Scopes: DeviceManagementConfiguration.Read.All
6. get-assignment-filter-audit - Assignment filters that are unused, duplicated, or overly broad. Scopes: DeviceManagementConfiguration.Read.All

## diagnostics (new folder, activates the unused Diagnostics tag)

7. collect-device-diagnostics - Trigger the remote collectDiagnostics action on Windows devices and download the resulting logs. Scopes: DeviceManagementManagedDevices.PrivilegedOperations.All, DeviceManagementManagedDevices.Read.All
8. get-enrollment-failure-report - Enrollment and Autopilot failure events with error codes and plain-language explanations. Scopes: DeviceManagementManagedDevices.Read.All, DeviceManagementServiceConfig.Read.All
9. get-device-checkin-health - Devices whose sync cadence is degrading (still enrolled but drifting), distinct from the stale-device report. Scopes: DeviceManagementManagedDevices.Read.All

## devices

10. get-windows11-readiness-report - Windows 11 upgrade readiness from Endpoint Analytics work-from-anywhere signals. Scopes: DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All
11. cleanup-duplicate-device-records - Find duplicate Intune device objects sharing a serial number, report and optionally delete the older ones. Scopes: DeviceManagementManagedDevices.ReadWrite.All
12. rename-devices-from-csv - Bulk rename via the setDeviceName action from CSV or a naming convention. Scopes: DeviceManagementManagedDevices.PrivilegedOperations.All
13. fix-primary-user-assignment - Set the primary user to the most frequent recent logged-on user. Scopes: DeviceManagementManagedDevices.ReadWrite.All, User.Read.All

## apps

14. get-vpp-license-report - Apple VPP apps: used vs total licenses, flag near-exhaustion. Scopes: DeviceManagementApps.Read.All
15. cleanup-orphaned-apps - Apps with no assignments or superseded old Win32 versions, report plus optional delete. Scopes: DeviceManagementApps.ReadWrite.All
16. get-app-assignment-conflicts - Same app targeted required plus uninstall, or available across overlapping groups. Scopes: DeviceManagementApps.Read.All, Group.Read.All

## security

17. get-windows-laps-audit - Windows LAPS escrow status and password age (catalog only covers macOS LAPS today). Intune Administrator is one of the roles allowed to read LAPS credentials. Scopes: DeviceLocalCredential.Read.All, Device.Read.All
18. get-defender-status-report - windowsProtectionState across devices: signature age, real-time protection, active threats. Scopes: DeviceManagementManagedDevices.Read.All
19. get-compliance-policy-coverage - Platforms and OS versions present in the tenant that no compliance policy targets. Scopes: DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.Read.All
20. get-firewall-and-asr-status - Firewall state and ASR rule coverage from Intune security reporting. Scopes: DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.Read.All

## monitoring

21. check-connector-health - One report for all tenant connectors: NDES, certificate connectors, Managed Google Play sync, VPP/DEP (extends the Apple-only check). Scopes: DeviceManagementServiceConfig.Read.All, DeviceManagementConfiguration.Read.All
22. get-windows-update-compliance-report - Update ring, feature update, and expedite deployment status. Scopes: DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.Read.All
23. check-certificate-profile-expiry - SCEP/PKCS certificate state and expiry across devices. Scopes: DeviceManagementConfiguration.Read.All, DeviceManagementManagedDevices.Read.All

## remediation (detection + action pairs, run as SYSTEM on device, no Graph scopes)

24. reboot-pending - Detect devices with a pending reboot, notify the user or schedule a restart
25. winget-app-updates - Detect outdated third-party apps via winget, remediate by upgrading
26. onedrive-kfm - Detect OneDrive Known Folder Move not configured, remediate
27. local-admin-drift - Detect unauthorized members of the local Administrators group, remediate by removing them

## notification (Azure Automation runbook email alerts; managed identity gets the application-permission equivalents plus Mail.Send)

28. windows-update-failure-alert - Email alert for devices failing update deployments. Scopes: as idea 22 plus Mail.Send
29. new-device-enrollment-digest - Daily or weekly digest of newly enrolled devices with platform and ownership breakdown. Scopes: DeviceManagementManagedDevices.Read.All plus Mail.Send
30. license-threshold-alert - Alert when Intune-licensed user count approaches purchased licenses (subscribedSkus is readable by any member user). Scopes: Organization.Read.All plus Mail.Send

## Dropped ideas and why

- Conditional Access coverage report: requires Policy.Read.All and at least Security Reader, which a native Intune Administrator does not have. Replaced by idea 19.
