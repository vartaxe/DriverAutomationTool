# File Hashes

SHA256 manifest of the core PowerShell files that make up the Driver Automation Tool.
Regenerate with the **update-file-hashes** skill whenever a core `.ps1`, `.psm1` or `.psd1` file changes.

Hashes are taken from the checked-out working copy. The repository `.gitattributes` pins
`.ps1`, `.psm1`, `.psd1` and `.xaml` files to CRLF line endings, so a `git clone` produces the
same bytes â€” and therefore the same SHA256 values â€” on every platform regardless of the local
`core.autocrlf` setting.

| | |
|---|---|
| Version | `10.3.2.0` |
| Generated (UTC) | 2026-10-09 23:45:49 |
| Files | 20 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 8.9 | `3173A26B88DA68EC02E1E88C9D7322AA1C3CE1BC167548501E0DFA332A8CE5FE` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 44.9 | `FE3061B6796B8CFD1F1F966284B55C002DE4AF3A4592606E01763B04FA6AA331` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 7.6 | `B8ABE6521AEACF22DCD470FAB4D49ACBBC78E05FFF3447BD597CD18F18F1DEED` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1447.9 | `C3C2A3EC92B0AC9924372AA03ACBB363874DDC67250540650EEBE4068A5DBC89` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `7A7DCE6AD49DE2634FB5014D2E02594E36A5A212FA0BF3C21C3E6C5ACC64B235` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 2.9 | `DA0A9097595C3D10B0E5C13CA7B1E73B8026A5F7F627E90A28844F4512F962E7` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 102.5 | `75416497921B7779404549E42142BB0AE87041FCE59F6842578BB5019A847A43` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 67.5 | `ED104016244CE1345A6B4B565CB151ED840478284A66B3B00B07C7A63ED21110` |
| Invoke-DATToastTest.ps1 | `Modules/DriverAutomationToolCore/Templates/Invoke-DATToastTest.ps1` | 29.7 | `B57BEF1E6128B9CE9CC65E36428EBB7F82268C311F84B0D9D8FEE0CDCBFC4B96` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1707.3 | `7DF5354F28CFD8B986E80A27DC6305FAD4FB5C14F5B7B176A0836925C63980DC` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.9 | `B7C6D8D529D3581C7EDCD79092F24F2550BE2B3DD7CB647DF690CC161520933A` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 162.1 | `FB72664ACEF88D7CE2B58615C76DAA8B305B3A26818E12C9DE1EC24E6990A4E1` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 104.6 | `9FFFC02E26D950CB1E57FDD0F90D202564C4310D334D8C499E6BEED047942F4E` |
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
