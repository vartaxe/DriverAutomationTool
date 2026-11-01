# File Hashes

SHA256 manifest of the core PowerShell files that make up the Driver Automation Tool.
Regenerate with the **update-file-hashes** skill whenever a core `.ps1`, `.psm1` or `.psd1` file changes.

Hashes are taken from the checked-out working copy. The repository `.gitattributes` pins
`.ps1`, `.psm1`, `.psd1` and `.xaml` files to CRLF line endings, so a `git clone` produces the
same bytes â€” and therefore the same SHA256 values â€” on every platform regardless of the local
`core.autocrlf` setting.

Git stores these text files with LF endings. Automatic GitHub source archives
and `git archive` can therefore differ from this CRLF working-copy manifest.
To publish a checksum-verifiable release ZIP, package the tracked files from a
clean checkout without rewriting their bytes, retain the required licenses,
and publish a SHA256 checksum for the ZIP itself.

| | |
|---|---|
| Version | `10.3.6.0` |
| Generated (UTC) | 2026-11-01 14:33:04 |
| Files | 20 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 15.8 | `938DA92A2645CEDF91455DE2A408E7D59D577FB5134812BCD7BFAD11050A50D3` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 46.0 | `2B3CB5F84C52821E98F6E6B44D7B804C6A821866E85C5993730DF8342B27410C` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 7.6 | `6926525056FAD473FF95F05504C27C4304B6C30D373056382A1D6B34A8E1D248` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1564.7 | `E717BDA82CBD6CC557E2084A413E197E7C5E193C1A12FD293D3E37520F98CFEC` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `7A7DCE6AD49DE2634FB5014D2E02594E36A5A212FA0BF3C21C3E6C5ACC64B235` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 3.2 | `04E95521191126AF41ACDED90CF6EA6C7FD16571B7DA203A3BE8E8E3DD0B4A3B` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 111.3 | `0F0F17D5C97D84C47BF6ABF80584C96210527F1617878D082263822636042246` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 67.5 | `ED104016244CE1345A6B4B565CB151ED840478284A66B3B00B07C7A63ED21110` |
| Invoke-DATToastTest.ps1 | `Modules/DriverAutomationToolCore/Templates/Invoke-DATToastTest.ps1` | 29.7 | `B57BEF1E6128B9CE9CC65E36428EBB7F82268C311F84B0D9D8FEE0CDCBFC4B96` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1713.5 | `334977CAD136DB7DB40934F1162AF99AD23BE2D88D9FA7CE56EBC492348E8ED1` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.9 | `B7C6D8D529D3581C7EDCD79092F24F2550BE2B3DD7CB647DF690CC161520933A` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 163.5 | `861061ACE4230FAC2469ADBF175C123D2BD85C378A51F1669A626A14B70AD4F1` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 105.2 | `D6064FD9834D75B7DE8185D852F3872B97AA4487819CFCCB462B4EF926F1CCF7` |
| Invoke-DellBIOSUpdate.ps1 | `Scripts/Invoke-DellBIOSUpdate.ps1` | 20.9 | `3601FF8D76D2BEBD695C54AC533EA232B16DF9C8A6A33BC270317836F989E62B` |
| Invoke-HPBIOSUpdate.ps1 | `Scripts/Invoke-HPBIOSUpdate.ps1` | 16.1 | `6BC4A441BDC949D0846D101DE430B4E5706ED8ADC1371751D8122E53279A8340` |
| Invoke-LenovoBIOSUpdate.ps1 | `Scripts/Invoke-LenovoBIOSUpdate.ps1` | 17.2 | `F58CBEB46260958712F35043D5E96865B51873F927533208CA9A5770AB3506A0` |
| Invoke-MicrosoftBIOSUpdate.ps1 | `Scripts/Invoke-MicrosoftBIOSUpdate.ps1` | 8.0 | `75ADC861848562C7AFF0C326193EC94F29F8F7F602F3152501A9B0A0809EB053` |
| Remove-DATStaleBIOSMarkers.ps1 | `Scripts/Remove-DATStaleBIOSMarkers.ps1` | 5.2 | `36102A498C7F9CCF36888A565B2CDFA3288D0EBB3ECC231CCD3C193157DD079F` |

---

Verify a copy of the tool against this manifest:

```powershell
Get-FileHash -Path .\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1 -Algorithm SHA256
```
