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
| Generated (UTC) | 2026-10-09 17:46:00 |
| Files | 20 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 8.9 | `3173A26B88DA68EC02E1E88C9D7322AA1C3CE1BC167548501E0DFA332A8CE5FE` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 46.1 | `9835CAE2163F7BC1F59858375ACC5F6A28099D909AC9E50BBAA5E15AE1EC23A6` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 7.3 | `68534A21CE2D20D5950D10DFB864475361C9B65B6450AF2F2AB816D40B43C321` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1425.7 | `376F37C1B45EBA10ABC858929ECC5EA859C13C76DDCBD148DA5A304A210A612C` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `7A7DCE6AD49DE2634FB5014D2E02594E36A5A212FA0BF3C21C3E6C5ACC64B235` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 2.9 | `DA0A9097595C3D10B0E5C13CA7B1E73B8026A5F7F627E90A28844F4512F962E7` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 102.5 | `75416497921B7779404549E42142BB0AE87041FCE59F6842578BB5019A847A43` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 67.5 | `109F75DA03B2E74CAD82411C17CED5ED32BCE1A418E29F2EA096753279AA69C3` |
| Invoke-DATToastTest.ps1 | `Modules/DriverAutomationToolCore/Templates/Invoke-DATToastTest.ps1` | 29.7 | `B57BEF1E6128B9CE9CC65E36428EBB7F82268C311F84B0D9D8FEE0CDCBFC4B96` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1705.1 | `E127E93EEAD78D360CBBDF27973CF4C152A2DCD76BB06EE761496D9B8A11BDFD` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.9 | `B7C6D8D529D3581C7EDCD79092F24F2550BE2B3DD7CB647DF690CC161520933A` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 162.1 | `C2CD9E72A2773AAF2CCD710523D840EB1D3E5CD9FD015C857DC1D8D60DC81AD2` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 104.6 | `9FFFC02E26D950CB1E57FDD0F90D202564C4310D334D8C499E6BEED047942F4E` |
| Invoke-DellBIOSUpdate.ps1 | `Scripts/Invoke-DellBIOSUpdate.ps1` | 20.9 | `3601FF8D76D2BEBD695C54AC533EA232B16DF9C8A6A33BC270317836F989E62B` |
| Invoke-HPBIOSUpdate.ps1 | `Scripts/Invoke-HPBIOSUpdate.ps1` | 16.1 | `B9C60BAB70CD6343583A12EE85AD5534146FF6FA1C8A683340BE2F204A715E5F` |
| Invoke-LenovoBIOSUpdate.ps1 | `Scripts/Invoke-LenovoBIOSUpdate.ps1` | 17.2 | `F58CBEB46260958712F35043D5E96865B51873F927533208CA9A5770AB3506A0` |
| Invoke-MicrosoftBIOSUpdate.ps1 | `Scripts/Invoke-MicrosoftBIOSUpdate.ps1` | 8.0 | `75ADC861848562C7AFF0C326193EC94F29F8F7F602F3152501A9B0A0809EB053` |
| Remove-DATStaleBIOSMarkers.ps1 | `Scripts/Remove-DATStaleBIOSMarkers.ps1` | 5.2 | `0D2CD832AE710A421E3790D5366D5F6C630418E9E96ED0E35FBA227F59AF0F60` |

---

Verify a copy of the tool against this manifest:

```powershell
Get-FileHash -Path .\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1 -Algorithm SHA256
```
