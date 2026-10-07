$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$currentCore = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
$currentTemplate = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1'
$hotFixCore = Join-Path $repoRoot 'HotFix\10.1.5\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
$hotFixTemplate = Join-Path $repoRoot 'HotFix\10.1.5\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1'
$readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw

function Assert-DAT {
    param ([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Test-DATModuleSupport {
    param ([string]$Path)
    Import-Module $Path -Force
    try {
        foreach ($oem in @('Dell', 'HP', 'Lenovo')) {
            Assert-DAT (Test-DATBIOSInstallerSupport -OEM $oem) "$Path supports $oem BIOS build path"
        }
        foreach ($oem in @('Microsoft', 'Acer', 'Panasonic', 'Fujitsu', 'ASUS')) {
            Assert-DAT (-not (Test-DATBIOSInstallerSupport -OEM $oem)) "$Path rejects $oem standalone BIOS build path"
        }
    } finally {
        Remove-Module (Get-Module | Where-Object { $_.Path -eq (Resolve-Path $Path).Path }) -Force -ErrorAction SilentlyContinue
    }
}

foreach ($module in @($currentCore, $hotFixCore)) {
    Test-DATModuleSupport -Path $module
}

foreach ($templatePath in @($currentTemplate, $hotFixTemplate)) {
    $template = Get-Content $templatePath -Raw
    $flashSection = $template.Substring($template.IndexOf('# -- Manufacturer-Specific BIOS Flash'))
    Assert-DAT ($flashSection -match "\'\*Dell\*\'" -and $flashSection -match "\'\*HP\*\'" -and $flashSection -match "\'\*Lenovo\*\'") "$templatePath has validated Dell/HP/Lenovo apply paths"
    Assert-DAT ($flashSection -match "\'\*Microsoft\*\'") "$templatePath retains the explicit Microsoft Surface apply path"
    Assert-DAT ($flashSection -match "Unsupported manufacturer") "$templatePath fails closed for unsupported BIOS apply paths"
    Assert-DAT ($flashSection -notmatch "\'\*Acer\*\'|\s\'Acer\'\s") "$templatePath has no unvalidated Acer BIOS apply path"
    Assert-DAT ($flashSection -notmatch "\'\*Panasonic\*\'|\s\'Panasonic\'\s|\s\'Fujitsu\'\s|\s\'ASUS\'\s") "$templatePath has no unvalidated non-supported OEM BIOS apply paths"
}

foreach ($oem in @('Acer', 'Panasonic', 'Fujitsu', 'ASUS')) {
    $matrixLine = @($readme -split "`r?`n" | Where-Object { $_ -match "^\| $oem \|" }) | Select-Object -First 1
    $columns = @($matrixLine -split '\|')
    Assert-DAT ($columns.Count -ge 4 -and $columns[2].Trim() -ne $columns[3].Trim()) "README documents $oem as drivers-only"
}
Assert-DAT ($readme -match 'Standalone BIOS\s+package creation and installation is currently validated only for Dell, HP, and Lenovo') 'README documents the validated BIOS support boundary'
Assert-DAT ($readme -match 'Microsoft Surface firmware is delivered through driver packages') 'README documents the Microsoft standalone BIOS restriction'

Write-Host 'OEM BIOS support regression harness completed successfully.'
