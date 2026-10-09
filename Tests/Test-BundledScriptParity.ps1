$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$driverScript = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMApplyDriverPackage.ps1'
$biosScript = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMDownloadBIOSPackage.ps1'
$scriptsRoot = Join-Path $repoRoot 'Driver Automation Tool\Scripts'
$parityContract = Join-Path $repoRoot 'Data\BundledScriptParity.md'
$mdmLicense = Join-Path $repoRoot 'LICENSES\MSEndpointMgr-MIT.txt'

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
Assert-Parity (Test-Path -LiteralPath $mdmLicense) 'MSEndpointMgr MIT attribution is retained'

$driver = Get-Content -LiteralPath $driverScript -Raw
$bios = Get-Content -LiteralPath $biosScript -Raw
$contract = Get-Content -LiteralPath $parityContract -Raw

foreach ($script in @(@($driver, 'driver'), @($bios, 'BIOS'))) {
    Assert-Parity ($script[0] -match 'XMLPackage') "$($script[1]) script retains XMLPackage deployment support"
    Assert-Parity ($script[0] -match 'AdminService') "$($script[1]) script retains AdminService deployment support"
    Assert-Parity ($script[0] -match 'errors != SslPolicyErrors\.RemoteCertificateChainErrors') "$($script[1]) pinning never overrides host-name or missing-certificate errors"
    Assert-Parity ($script[0] -match 'MDMSiteCode') "$($script[1]) script reads the hierarchy site-code task-sequence variable"
    Assert-Parity ($script[0].Contains("SourceSite eq '`$(`$Script:SiteCode)'")) "$($script[1]) script scopes AdminService package queries by source site"
}

Assert-Parity ($driver -match 'Enable-AdminServiceCertificatePinning') 'driver script retains scoped certificate pinning'
Assert-Parity ($driver -match 'Disable-AdminServiceCertificatePinning') 'driver script restores its certificate callback'
Assert-Parity ($driver -match 'function Expand-ArchiveSafely') 'driver script retains Zip Slip-safe archive extraction'
Assert-Parity ($driver -match 'Expand-ArchiveSafely -Path \$DriverPackageCompressedFile') 'driver package extraction uses the safe archive helper'
Assert-Parity ($bios -match 'DATPinnedCertificateValidation') 'BIOS script retains DAT certificate pinning compatibility'
Assert-Parity ($bios -match 'Reset-PinnedCertificateValidationCallback') 'BIOS script restores its certificate callback'
Assert-Parity ($contract -match 'ffd45de80ae58ece1dd83e9c10fa2406fa320e70') 'driver maintenance baseline is pinned'
Assert-Parity ($contract -match '3859244657c7a05b62203cb174576f2c3720d060') 'BIOS maintenance baseline is pinned'
Assert-Parity ($contract -match 'canonical maintained home') 'consolidated ownership is documented'
Assert-Parity ($driver -match '"\*Getac\*"\s*\{\s*\$ComputerDetails\.Manufacturer = "Getac"') 'Getac manufacturer normalization is retained'
Assert-Parity ($contract -match 'Getac manufacturer\s+normalization') 'Getac manual-package parity boundary is documented'
Assert-Parity ($contract -match 'does not represent automated catalog acquisition or BIOS\s+firmware support') 'Getac automation and firmware exclusions are documented'

foreach ($fileName in @(
    'Invoke-DellBIOSUpdate.ps1',
    'Invoke-HPBIOSUpdate.ps1',
    'Invoke-LenovoBIOSUpdate.ps1',
    'Invoke-MicrosoftBIOSUpdate.ps1'
)) {
    Assert-Parity (Test-Path -LiteralPath (Join-Path $scriptsRoot $fileName)) "$fileName is consolidated into DAT"
}

Write-Host 'Bundled script parity contract completed successfully.'
