<p align="center">
  <img src="Content/Screenshots/Dat_Logo.png" alt="Driver Automation Tool" width="150" />
</p>

# Driver Automation Tool

> **Fork notice:** This repository is a maintained fork of
> [Maurice Daly's Driver Automation Tool](https://github.com/maurice-daly/DriverAutomationTool).
> The original project, authorship, license, website, and product identity remain attributed to
> the upstream project. Fork-specific maintenance changes are recorded in this repository's pull
> request history.

<p align="center">
  Enterprise-grade automation for downloading, extracting, and packaging OEM driver and BIOS update packages for ConfigMgr and Intune.
  <br /><br />
  <a href="https://www.driverautomationtool.com"><strong>Website</strong></a> · <a href="https://www.driverautomationtool.com/setup-guide"><strong>Setup Guide</strong></a> · <a href="https://www.driverautomationtool.com/reports"><strong>Reports</strong></a>
  <br /><br />
  A free community tool — created by <strong>Maurice Daly</strong>
</p>

---

## Version notice

**Upstream notice, August 17, 2026:** Builds 10.1.9.0 and earlier are no longer
served by the API. Upgrade before using catalog-dependent workflows.

[Getting started](#getting-started) · [Requirements](#platform-requirements) ·
[Platform configuration](#platform-configuration) · [Troubleshooting](#troubleshooting) ·
[Contributing](#contributing)

## Overview

The Driver Automation Tool is a PowerShell WPF desktop application that automates the full lifecycle of OEM driver and BIOS package management — from catalog discovery and download through extraction, WIM packaging, and deployment to Configuration Manager or Microsoft Intune.

<p align="center">
  <img src="Content/Screenshots/MainUI.png" alt="Driver Automation Tool — Main Interface" width="900" />
</p>

## Supported OEMs

| OEM | Drivers | BIOS Updates |
|-----|---------|--------------|
| HP | ✅ | ✅ |
| Dell | ✅ | ✅ |
| Lenovo | ✅ | ✅ |
| Microsoft Surface | ✅ | — |
| Acer | ✅ | — |
| Panasonic | ✅ | — |
| Fujitsu | ✅ | — |
| ASUS | ✅ | — |

Driver catalog discovery and packaging covers all eight OEMs listed above. Standalone BIOS
package creation and installation is currently validated only for Dell, HP, and Lenovo.
Microsoft Surface firmware is delivered through driver packages; BIOS packages for Acer,
Panasonic, Fujitsu, and ASUS are not generated.

Getac is not an automated catalog provider in this project. The bundled apply script
recognizes Getac hardware, so administrators can use the **Custom Driver Pack** workflow
or import a package manually after sourcing and validating the applicable drivers through
Getac's published support channels. Package metadata must match the device manufacturer,
model/SystemSKU, operating system, and architecture. This recognition does not add
automated Getac catalog discovery, BIOS download, or firmware flashing.

## Consolidated ConfigMgr deployment scripts

The maintained Modern Driver Management and Modern BIOS Management deployment
scripts now live together under `Driver Automation Tool/Scripts`:

- `Invoke-CMApplyDriverPackage.ps1`
- `Invoke-CMDownloadBIOSPackage.ps1`
- `Invoke-DellBIOSUpdate.ps1`
- `Invoke-HPBIOSUpdate.ps1`
- `Invoke-LenovoBIOSUpdate.ps1`
- `Invoke-MicrosoftBIOSUpdate.ps1`

The two package selectors retain AdminService and XML package modes, virtual
platform safeguards, certificate validation controls, and the maintained
matching fixes. In ConfigMgr hierarchies, pass `-SiteCode ABC` or set the
`MDMSiteCode` task-sequence variable to restrict package selection to objects
whose `SMS_Package.SourceSite` is `ABC`. If neither is set, package selection
continues to consider every site as before.

The Microsoft apply script is retained for existing administrator-created
ConfigMgr BIOS package workflows; it does not imply automated Microsoft Surface
BIOS catalog support in DAT. Surface firmware delivered through driver packages
continues to use the driver workflow.

These imported MSEndpointMgr scripts remain MIT-licensed. Their required
copyright and license notice is preserved in
`LICENSES/MSEndpointMgr-MIT.txt`; DAT's existing license continues to govern
the rest of this repository. Reviewed source baselines and maintenance
boundaries are recorded in `Data/BundledScriptParity.md`.

## Core Features

- **Automated Driver Downloads** — Accelerated downloads via `curl.exe` with HTTP resume support, configurable retry logic (10 retries, 60s delay), and automatic hash verification
- **Multi-OEM Support** — Driver catalog discovery and packaging for HP, Dell, Lenovo, Microsoft Surface, Acer, Panasonic, Fujitsu, and ASUS
- **BIOS Update Management** — Version comparison, release classification (Recommended/Critical), minimum version validation, and hash verification
- **WIM Packaging** — Create WIM packages using DISM (built-in), wimlib (multi-threaded), or 7-Zip (recommended) with configurable compression
- **ConfigMgr Integration** — Automatic package creation, content distribution to DPs, WinRM/WMI connectivity, and deployment state tracking
- **Intune Integration** — Device code or app registration auth, chunked Azure Blob uploads, parallel threading, and Win32 app packaging

## Deployment Platforms

| Platform | Description |
|----------|-------------|
| **Configuration Manager** | Download → Extract → Create WIM → Create ConfigMgr package → Distribute to DPs |
| **Microsoft Intune** | Download → Extract → Create WIM → Wrap as .intunewin → Upload and create Win32 app |
| **WIM Package Only** | Download → Extract → Create WIM file only (no deployment) |
| **Download Only** | Download and extract packages without any WIM packaging or deployment |

### Windows deployment compatibility

Catalog recognition in DAT does not certify the Configuration Manager, Windows ADK,
WinPE, operating-system image, or OEM firmware combination used for deployment.
Windows 11 26H1 is a specialized new-hardware release rather than a general upgrade
target. Configuration Manager 2509 does not support Windows 11 26H2 clients; use
Configuration Manager 2603 or later for 26H2 task sequences. Current Windows 11 ADKs
do not include x86 WinPE.

Confirm the current
[Windows 11 support matrix](https://learn.microsoft.com/intune/configmgr/core/plan-design/configs/support-for-windows-11)
and
[Windows ADK support matrix](https://learn.microsoft.com/intune/configmgr/core/plan-design/configs/support-for-windows-adk)
before generating or deploying packages. MDT integration is retired and unsupported
with Configuration Manager 2509 and later; DAT's ConfigMgr workflows do not make
legacy MDT task-sequence steps supported.

## Getting Started

### 1. Download

For this maintenance fork, open the
[repository](https://github.com/vartaxe/DriverAutomationTool) and choose **Code >
Download ZIP**, or clone it:

```powershell
git clone https://github.com/vartaxe/DriverAutomationTool.git C:\DriverAutomationTool
```

For the original product, use the
[official upstream repository](https://github.com/maurice-daly/DriverAutomationTool)
or [project website](https://www.driverautomationtool.com). Do not mix files from
different versions or checkouts. The application is portable; no installer is
required. This maintenance fork does not publish independent GitHub Releases.

<p align="center">
  <img src="Content/Screenshots/GitHubDownload.png" alt="GitHub Download" width="700" />
</p>

### 2. Extract

If you downloaded a ZIP, extract it to a permanent location. A clone already
contains the extracted repository. The application files are in the
`Driver Automation Tool` subdirectory, not the repository root:

```text
C:\DriverAutomationTool\
  README.md
  Driver Automation Tool\
    Start-DriverAutomationTool.ps1
```

Only unblock a downloaded ZIP after verifying its source and following your
organization's security policy. Do not bypass antivirus or operating-system
warnings to run an untrusted copy.

### 3. Launch

Open **Windows PowerShell** as Administrator and run from the application folder
(adjust the path to your extraction location):

```powershell
Set-Location -LiteralPath 'C:\DriverAutomationTool\Driver Automation Tool'
.\Start-DriverAutomationTool.ps1

# Or launch with dark theme
.\Start-DriverAutomationTool.ps1 -Theme Dark
```

If execution policy blocks the script, first follow your organization's approved
policy. Where permitted, this override applies only to the current PowerShell
process and does not override Group Policy:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

<p align="center">
  <img src="Content/Screenshots/Launch.png" alt="Launching from PowerShell" width="700" />
</p>

### 4. Accept EULA

On first launch, review and accept the End User License Agreement.

<p align="center">
  <img src="Content/Screenshots/EULA.png" alt="EULA" width="700" />
</p>

### 5. Configure

Set your storage paths, select your deployment platform, and configure proxy settings if needed. See the [Setup Guide](https://www.driverautomationtool.com/setup-guide) for detailed configuration instructions.

## Platform Configuration

### Configuration Manager

Connect to your ConfigMgr site server via WinRM/WMI for automated package creation and content distribution.

<p align="center">
  <img src="Content/Screenshots/ConfigMgr1.png" alt="ConfigMgr Connection" width="700" />
</p>

| Setting | Description |
|---------|-------------|
| Site Server FQDN | Fully qualified domain name of your ConfigMgr site server |
| WinRM SSL | Enable SSL/TLS encryption for WinRM communications |
| Known Model Lookup | Query hardware inventory to highlight models in your environment |
| Replication Priority | Set content distribution priority (High / Normal / Low) |
| Binary Differential Replication | Transmit only changed binary blocks to reduce bandwidth |

<p align="center">
  <img src="Content/Screenshots/ConfigMgr2.png" alt="ConfigMgr Package Management" width="700" />
  <br /><em>ConfigMgr package management view</em>
</p>

<p align="center">
  <img src="Content/Screenshots/ConfigMgr3.png" alt="ConfigMgr Distribution" width="700" />
  <br /><em>Distribution point configuration</em>
</p>

### Microsoft Intune

Three authentication methods are supported for connecting to Intune via the Microsoft Graph API:

| Method | Description |
|--------|-------------|
| **Interactive (Browser)** | Browser-based sign-in with full MFA and Conditional Access support (Recommended) |
| **Interactive (Device Code)** | Device code flow for restricted environments |
| **App Registration** | Tenant ID, App ID, and Client Secret for automated/scheduled runs |

**Required Graph API Permissions (Application):**
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementManagedDevices.Read.All`
- `GroupMember.Read.All`

<p align="center">
  <img src="Content/Screenshots/Intune1.png" alt="Intune Authentication" width="700" />
  <br /><em>Intune authentication method selection</em>
</p>

<p align="center">
  <img src="Content/Screenshots/Intune4.png" alt="Intune Upload Options" width="700" />
  <br /><em>Package upload and deployment options</em>
</p>

#### Package Assignment

Assign packages directly to Entra ID groups from the Package Management section. Right-click any package to access assignment options — deploy as **Required** (automatic) or **Available** (user-initiated from Company Portal).

<p align="center">
  <img src="Content/Screenshots/IntuneAssignment1.png" alt="Intune Assignment" width="700" />
  <br /><em>Right-click to assign packages to Entra ID groups</em>
</p>

#### BIOS Security

For environments requiring BIOS passwords for firmware updates, the tool encrypts passwords using DPAPI with machine-scope protection and embeds them in detection/remediation scripts for Intune deployments. HP devices also support BIN files generated by HP BIOS Configuration Utility (BCU).

<p align="center">
  <img src="Content/Screenshots/IntuneBIOS.png" alt="BIOS Security Configuration" width="700" />
  <br /><em>BIOS security configuration</em>
</p>

## Intune Client Experience

Once published, packages deploy through the Intune Company Portal with toast notifications at every stage:

<p align="center">
  <img src="Content/Screenshots/IntuneClient1.png" alt="Company Portal — Available App" width="350" />
  <img src="Content/Screenshots/IntuneClient4.png" alt="Toast Notification" width="350" />
  <br /><em>Company Portal install flow with toast notification prompts</em>
</p>

### Toast Notifications

Fully customisable Windows toast notifications keep end users informed — from pending updates through to successful completion. Replace the default branding with your own logo and messaging.

<p align="center">
  <img src="Content/Screenshots/Toast1.png" alt="BIOS Update Pending" width="350" />
  <img src="Content/Screenshots/Toast2.png" alt="Driver Updates Pending" width="350" />
</p>
<p align="center">
  <img src="Content/Screenshots/Toast3.png" alt="BIOS Firmware Prestaged" width="350" />
  <img src="Content/Screenshots/Toast4.png" alt="Drivers Successfully Updated" width="350" />
</p>
<p align="center">
  <img src="Content/Screenshots/ToastCustomise.png" alt="Custom Branding" width="500" />
  <br /><em>Custom branding and messaging configuration</em>
</p>

## Common Settings

### WIM Packaging Engine

Three engines are supported for WIM creation:

| Engine | Description | Benchmark (~2551 MB) |
|--------|-------------|----------------------|
| DISM | Built-in Windows engine, single-threaded | ~3m 51s |
| wimlib | Multi-threaded third-party engine | ~2m 53s |
| **7-Zip** ✅ | High-performance multi-threaded (Recommended) | **~36s** |

*Estimates based on benchmark testing — actual times will vary based on hardware.*

### Compression Levels

| Level | Description |
|-------|-------------|
| Fast (XPRESS) | Fastest creation speed, moderate file size (Default) |
| Maximum (LZX) | Slower creation, smallest file size |
| None | Uncompressed — fastest creation, largest file size |

### Additional Options

<p align="center">
  <img src="Content/Screenshots/Options1.png" alt="Common Settings" width="700" />
  <br /><em>Common settings — General options</em>
</p>

| Setting | Description |
|---------|-------------|
| Proxy | System default, manual host:port, or bypass |
| CURL Engine | Bundled or system curl.exe with signature validation |
| Temporary Storage | Local path for downloads, extraction, and WIM staging |
| Package Storage | Final output path for WIM and .intunewin packages (supports UNC) |
| Config Export/Import | Backup and restore all settings via .reg file |
| Telemetry | Opt-in anonymous telemetry — only package counts and model data, no PII |

## Custom Driver Pack

Create custom driver packages from the drivers installed on the current system (via PNPUtil) or from a local folder of INF files — ideal for devices not covered by OEM catalogs.

Aborting a **Custom Driver Pack** build stops only the DISM process tree started for that build
after its process creation time, executable, and command line have been verified. DAT does not
terminate machine-wide DISM processes or clear unrelated Windows image-mount state. If a process
identity cannot be verified, nothing is stopped and a warning is logged.

<p align="center">
  <img src="Content/Screenshots/CustomDriverPack.png" alt="Custom Driver Pack" width="700" />
  <br /><em>Custom Driver Pack creation interface</em>
</p>

### Custom OEM Driver Injection

Supplement OEM packages with additional drivers by right-clicking a model in Package Management and selecting **Add Custom Drivers**. Useful for missing or outdated drivers in standard OEM packages.

<p align="center">
  <img src="Content/Screenshots/CustomDrivers.png" alt="Add Custom Drivers" width="700" />
  <br /><em>Add Custom Drivers via right-click context menu</em>
</p>

## Logging

All operations are logged in CMTrace-compatible XML format with a built-in log viewer and real-time activity display.

| Feature | Description |
|---------|-------------|
| Log Format | CMTrace-compatible XML — readable in ConfigMgr Trace Log Tool |
| Log Location | `<AppRoot>\Logs\DriverAutomationTool.log` |
| Severity Levels | Information, Warning, Error — color-coded in CMTrace |
| Auto-Rotation | Rotates at 1 MB with 5 archived copies retained |
| Activity Log | Real-time in-app display during builds (60,000 char buffer) |

<p align="center">
  <img src="Content/Screenshots/Logging.png" alt="Log Viewer" width="700" />
  <br /><em>Built-in log viewer and activity log</em>
</p>

## Theme Support

The tool supports both light and dark themes with instant runtime switching.

<p align="center">
  <img src="Content/Screenshots/LightMode.png" alt="Light Mode" width="400" />
  <img src="Content/Screenshots/DarkMode.png" alt="Dark Mode" width="400" />
</p>

## Platform Requirements

- **OS:** Windows 11 / Windows 10 / Windows Server 2016+
- **Architecture:** x64, Arm64
- **PowerShell:** Windows PowerShell 5.1+
- **Privileges:** Administrator (for registry access and DISM operations)

These are application requirements, not certification of a particular deployment
target. Review [Windows deployment compatibility](#windows-deployment-compatibility)
and validate packages in a lab before production rollout.

## Troubleshooting

| Symptom | First check |
|---------|-------------|
| Launcher is not found | Run from `Driver Automation Tool`, not the repository root. |
| Catalog requests fail | Check the [version notice](#version-notice), connectivity, and proxy configuration. |
| Package creation or upload fails | Review the [CMTrace log](#logging), platform credentials, and storage paths. |
| DISM cancellation cannot verify process ownership | Review the logged warning; do not manually terminate unrelated servicing processes. |

Do not treat antivirus detections as confirmed false positives. Have your security
team review the source and the reported detection before running the application.

## Contributing

Keep pull requests focused and preserve upstream attribution. Describe the issue,
the affected workflow, and the checks performed. Avoid including credentials,
tenant secrets, or sensitive logs.

The [cleanup notes](CLEANUP.md) describe recent maintainability changes. The
[payload manifest](Driver%20Automation%20Tool/FileHashes.md) records shipped file
hashes; update it when changing covered application files.

Offline regression checks use Windows PowerShell and Pester 6.2.0. From the
repository root:

```powershell
Import-Module Pester -RequiredVersion '6.2.0'
Invoke-Pester -Path .\Tests\DismCancellation.Tests.ps1 -Output Detailed
.\Tests\Test-ReviewedFixes.ps1
.\Tests\Test-StaleBIOSMarkers.ps1
```

These checks use extracted code and test doubles. Passing results do not replace
live UI, hardware, firmware, ConfigMgr, or Intune validation.

### Servicing cancellation fix

Regular WIM capture and external DISM timeouts now use the same identity-verified
cancellation as custom builds. PID-only process-tree termination could select an
unrelated orphan whose parent PID was later reused by DAT. Cancellation pins
the launched wrapper's handle and checks creation times and identities before
stopping descendants. Unreadable descendants and process-enumeration failures
remain incomplete cancellation even if the verified wrapper is stopped.
Unverified cancellation is reported as failure, never
successful packaging; native exit codes and timeout code 1460 are retained.

[Cancellation regression tests](Tests/DismCancellation.Tests.ps1) cover the
capture and timeout callers with test doubles. When reviewing similar code, a
parent PID alone is not proof of ownership, and an unused process-handle read can
still be required.

## Security

Follow [SECURITY.md](SECURITY.md) for supported versions and private vulnerability
reporting. Do not disclose unpatched vulnerabilities in public issues.

## Links

- 🌐 [Driver Automation Tool Website](https://www.driverautomationtool.com)
- 📖 [Setup Guide](https://www.driverautomationtool.com/setup-guide)
- 📊 [Reports & Statistics](https://www.driverautomationtool.com/reports)
- ℹ️ [About](https://www.driverautomationtool.com/about)

## License

This tool is provided **as-is**, without warranty of any kind. Use is entirely at your own risk. See the [LICENSE](LICENSE) file for details.

## Sponsor

If you find this tool useful and would like to support its continued development, please use the **Sponsor** button at the top of this page.
