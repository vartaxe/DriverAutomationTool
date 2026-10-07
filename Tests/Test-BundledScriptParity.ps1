$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$driverScript = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMApplyDriverPackage.ps1'
$biosScript = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMDownloadBIOSPackage.ps1'
$parityContract = Join-Path $repoRoot 'Data\BundledScriptParity.md'

function Assert-Parity {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message"
}

Assert-Parity (Test-Path -LiteralPath $driverScript) 'bundled driver script exists'
Assert-Parity (Test-Path -LiteralPath $biosScript) 'bundled BIOS script exists'
Assert-Parity (Test-Path -LiteralPath $parityContract) 'parity contract exists'

$driver = Get-Content -LiteralPath $driverScript -Raw
$bios = Get-Content -LiteralPath $biosScript -Raw
$contract = Get-Content -LiteralPath $parityContract -Raw

foreach ($script in @(@($driver, 'driver'), @($bios, 'BIOS'))) {
    Assert-Parity ($script[0] -match 'XMLPackage') "$($script[1]) script retains XMLPackage deployment support"
    Assert-Parity ($script[0] -match 'AdminService') "$($script[1]) script retains AdminService deployment support"
    Assert-Parity ($script[0] -match 'DATPinnedCertificateValidation') "$($script[1]) script retains DAT certificate pinning"
}

Assert-Parity ($contract -match '87c57414428856159cbc599b4f2e9d1d1b62ede7') 'driver baseline is pinned'
Assert-Parity ($contract -match '4c8629dadfa94729f3269b8db7f8293db7da4f2a') 'BIOS baseline is pinned'
Assert-Parity ($contract -match 'not as byte-for-byte copies') 'intentional divergence is documented'
Assert-Parity ($contract -match 'Blind replacement is unsafe') 'unsafe blind replacement is explicitly prohibited'
Assert-Parity ($driver -match '"\*Getac\*"\s*\{\s*\$ComputerDetails\.Manufacturer = "Getac"') 'Getac manufacturer normalization is retained'
Assert-Parity ($contract -match 'Getac manufacturer\s+normalization') 'Getac manual-package parity boundary is documented'
Assert-Parity ($contract -match 'does not represent automated catalog acquisition or BIOS\s+firmware support') 'Getac automation and firmware exclusions are documented'

Write-Host 'Bundled script parity contract completed successfully.'
