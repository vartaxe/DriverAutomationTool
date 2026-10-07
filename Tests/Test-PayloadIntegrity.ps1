$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$modulePaths = @(
    @{
        Name = 'current'
        Path = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    },
    @{
        Name = 'HotFix'
        Path = Join-Path $repoRoot 'HotFix\10.1.5\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    }
)
$currentBiosTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1') -Raw
$hotFixBiosTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'HotFix\10.1.5\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1') -Raw

function Assert-True {
    param (
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not $Condition) {
        throw "FAILED: $Description"
    }
    Write-Host "PASS: $Description"
}

function Assert-False {
    param (
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Description
    )

    Assert-True -Condition (-not $Condition) -Description $Description
}

function Assert-Equal {
    param (
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Actual -ne $Expected) {
        throw "FAILED: $Description (expected '$Expected', got '$Actual')"
    }
    Write-Host "PASS: $Description"
}

function Assert-Contains {
    param (
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Description
    )

    Assert-True -Condition $Content.Contains($Expected) -Description $Description
}

function Assert-NotContains {
    param (
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Unexpected,
        [Parameter(Mandatory)][string]$Description
    )

    Assert-False -Condition $Content.Contains($Unexpected) -Description $Description
}

function Get-FunctionDefinition {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "Unable to parse $Path`: $($parseErrors[0].Message)"
    }

    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $Name
    }, $true)
    if ($null -eq $functionAst) {
        throw "Function '$Name' was not found in $Path"
    }
    return $functionAst.Extent.Text
}

function New-SignatureFixture {
    param (
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Thumbprint
    )

    return [pscustomobject]@{
        Status = $Status
        StatusMessage = "Fixture status: $Status"
        SignerCertificate = [pscustomobject]@{
            Thumbprint = $Thumbprint
            Subject = 'CN=fixture'
        }
    }
}

function Write-DATLogEntry {
    param($Value, $Severity)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DATPayloadIntegrity_$([guid]::NewGuid().ToString('N'))"
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $fixtureFile = Join-Path $tempRoot 'payload.exe'
    [System.IO.File]::WriteAllBytes($fixtureFile, [byte[]](1, 2, 3, 4))
    $pinnedThumbprint = 'E456B946A5848AF5A8FAEDAA7DF2888EA03B5C4C'
    $script:SignatureFixture = $null

    function Get-AuthenticodeSignature {
        [CmdletBinding()]
        param ([string]$FilePath)
        return $script:SignatureFixture
    }

    function Expand-DATArchiveSafely {
        [CmdletBinding()]
        param ([string]$Path, [string]$DestinationPath)
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $DestinationPath 'nested.cab'), [byte[]](5, 6, 7))
    }

    function Expand-Archive {
        [CmdletBinding()]
        param ([string]$Path, [string]$DestinationPath, [switch]$Force)
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $DestinationPath 'nested.cab'), [byte[]](5, 6, 7))
    }

    foreach ($module in $modulePaths) {
        Invoke-Expression (Get-FunctionDefinition -Path $module.Path -Name 'Test-DATPinnedUntrustedRootSignature')
        Invoke-Expression (Get-FunctionDefinition -Path $module.Path -Name 'Test-DATFileSignature')

        $script:SignatureFixture = New-SignatureFixture -Status 'UnknownError' -Thumbprint $pinnedThumbprint
        $accepted = Test-DATPinnedUntrustedRootSignature -FilePath $fixtureFile `
            -Signature $script:SignatureFixture -AllowedThumbprints @($pinnedThumbprint) `
            -NativeVerifier { param($Path) -2146762487 }
        Assert-True -Condition $accepted `
            -Description "$($module.Name) accepts exact CERT_E_UNTRUSTEDROOT with the exact pinned thumbprint"

        $badDigest = Test-DATPinnedUntrustedRootSignature -FilePath $fixtureFile `
            -Signature $script:SignatureFixture -AllowedThumbprints @($pinnedThumbprint) `
            -NativeVerifier { param($Path) -2146869232 }
        Assert-False -Condition $badDigest `
            -Description "$($module.Name) rejects TRUST_E_BAD_DIGEST with the pinned thumbprint"

        $unrelatedUnknownError = Test-DATPinnedUntrustedRootSignature -FilePath $fixtureFile `
            -Signature $script:SignatureFixture -AllowedThumbprints @($pinnedThumbprint) `
            -NativeVerifier { param($Path) -2146762486 }
        Assert-False -Condition $unrelatedUnknownError `
            -Description "$($module.Name) rejects an unrelated native UnknownError"

        $script:SignatureFixture = New-SignatureFixture -Status 'UnknownError' `
            -Thumbprint '0000000000000000000000000000000000000000'
        $wrongThumbprint = Test-DATPinnedUntrustedRootSignature -FilePath $fixtureFile `
            -Signature $script:SignatureFixture -AllowedThumbprints @($pinnedThumbprint) `
            -NativeVerifier { param($Path) -2146762487 }
        Assert-False -Condition $wrongThumbprint `
            -Description "$($module.Name) rejects CERT_E_UNTRUSTEDROOT from the wrong certificate"

        $zipFixture = Join-Path $tempRoot "$($module.Name)-nested-cab.zip"
        [System.IO.File]::WriteAllBytes($zipFixture, [byte[]](8, 9, 10))
        $nestedCab = Test-DATFileSignature -FilePath $zipFixture -AllowedPublishers @() `
            -AllowedUntrustedRootThumbprints @($pinnedThumbprint)
        Assert-False -Condition $nestedCab `
            -Description "$($module.Name) rejects a ZIP containing nested CAB content"
    }

    function Set-DATRegistryValue {
        param($Name, $Value, $Type)
    }

    function Get-DATVerificationHash {
        param($FilePath, $Algorithm)
        return (Get-FileHash -LiteralPath $FilePath -Algorithm $Algorithm).Hash
    }

    function Test-DATAcerDownloadUri {
        param($Uri)
        return $true
    }

    $script:DownloadFixture = Join-Path $tempRoot 'download-source.exe'
    $script:DownloadFileName = 'bios.exe'
    [System.IO.File]::WriteAllBytes($script:DownloadFixture, [byte[]](11, 12, 13, 14))

    function Invoke-DATContentDownload {
        param($DownloadURL, $DownloadDestination)
        $script:DownloadCalls++
        Copy-Item -LiteralPath $script:DownloadFixture `
            -Destination (Join-Path $DownloadDestination $script:DownloadFileName) -Force
    }

    $biosEntry = [pscustomobject]@{
        DownloadURL = 'https://example.invalid/bios.exe'
        FileName = $script:DownloadFileName
        FileHash = ('0' * 64)
        HashMethod = 'SHA256'
        DisplayName = 'Integrity fixture'
    }

    foreach ($module in $modulePaths) {
        Invoke-Expression (Get-FunctionDefinition -Path $module.Path -Name 'Start-DATBiosDownload')

        function Test-DATFileSignature {
            $script:SignatureCalls++
            return $true
        }

        $moduleTemp = Join-Path $tempRoot "$($module.Name)-bios"
        New-Item -Path $moduleTemp -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $script:DownloadFixture `
            -Destination (Join-Path $moduleTemp $script:DownloadFileName) -Force
        $script:DownloadCalls = 0
        $script:SignatureCalls = 0

        $cachedResult = Start-DATBiosDownload -BiosEntry $biosEntry `
            -DownloadDestination $moduleTemp -OEM 'Dell'
        Assert-Equal -Actual $script:DownloadCalls -Expected 1 `
            -Description "$($module.Name) discards a cached published SHA-256 mismatch and downloads once"
        Assert-Equal -Actual $script:SignatureCalls -Expected 0 `
            -Description "$($module.Name) does not use Authenticode to override cached or fresh SHA-256 mismatches"
        Assert-True -Condition ($null -eq $cachedResult) `
            -Description "$($module.Name) rejects a fresh published SHA-256 mismatch after replacing cache"
        Assert-False -Condition (Test-Path -LiteralPath (Join-Path $moduleTemp $script:DownloadFileName)) `
            -Description "$($module.Name) deletes the fresh mismatched BIOS payload"

        $script:DownloadCalls = 0
        $script:SignatureCalls = 0
        $freshResult = Start-DATBiosDownload -BiosEntry $biosEntry `
            -DownloadDestination $moduleTemp -OEM 'Dell'
        Assert-Equal -Actual $script:DownloadCalls -Expected 1 `
            -Description "$($module.Name) downloads a missing BIOS payload once"
        Assert-Equal -Actual $script:SignatureCalls -Expected 0 `
            -Description "$($module.Name) does not use Authenticode to override a fresh SHA-256 mismatch"
        Assert-True -Condition ($null -eq $freshResult) `
            -Description "$($module.Name) rejects a fresh published SHA-256 mismatch"
        Assert-False -Condition (Test-Path -LiteralPath (Join-Path $moduleTemp $script:DownloadFileName)) `
            -Description "$($module.Name) removes the rejected fresh BIOS payload"
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Assert-Contains -Content $currentBiosTemplate `
    -Expected "`$datContentFiles = @('Install-BIOS.ps1', 'Show-ToastNotification.ps1', 'Show-ProgressToast.ps1', 'HPPasswordFile.bin')" `
    -Description 'current ConfigMgr loose BIOS payload exclusion assignment includes the generated progress script'
Assert-NotContains -Content $hotFixBiosTemplate -Unexpected '$looseContent' `
    -Description 'HotFix BIOS template has no loose-payload path requiring the exclusion'

$currentBiosTemplatePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1'
$currentBiosTemplateAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $currentBiosTemplatePath,
    [ref]$null,
    [ref]$null
)
$lenovoFirmwareFunction = $currentBiosTemplateAst.Find(
    {
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-LenovoSystemFirmwareVersion'
    },
    $true
)
Assert-True -Condition ($null -ne $lenovoFirmwareFunction) `
    -Description 'current BIOS template exposes Lenovo ESRT version detection'

Invoke-Expression $lenovoFirmwareFunction.Extent.Text
$script:MockFirmwareDevices = @()
$script:MockRegistryVersion = $null

function Get-CimInstance {
    @($script:MockFirmwareDevices)
}

function Test-Path {
    param([string]$Path)
    return $null -ne $script:MockRegistryVersion
}

function Get-ItemProperty {
    param([string]$Path, [string]$Name)
    [pscustomobject]@{ Version = $script:MockRegistryVersion }
}

try {
    $script:MockFirmwareDevices = @(
        [pscustomobject]@{
            Name = 'Lenovo TrackPoint Firmware'
            CompatibleID = @('UEFI\CC_00010002')
            HardwareID = @('UEFI\RES_{11111111-1111-1111-1111-111111111111}&REV_43D518')
            DeviceID = 'UEFI\RES_{11111111-1111-1111-1111-111111111111}\0'
        },
        [pscustomobject]@{
            Name = 'Systemfirmware'
            CompatibleID = @('UEFI\CC_00010001')
            HardwareID = @('UEFI\RES_{22222222-2222-2222-2222-222222222222}&REV_10012')
            DeviceID = 'UEFI\RES_{22222222-2222-2222-2222-222222222222}\0'
        }
    )
    Assert-Equal -Actual (Get-LenovoSystemFirmwareVersion) -Expected '1.18' `
        -Description 'Lenovo ESRT detection selects system firmware independently of locale and device order'

    $script:MockFirmwareDevices = @($script:MockFirmwareDevices[0])
    Assert-Equal -Actual (Get-LenovoSystemFirmwareVersion) -Expected '' `
        -Description 'Lenovo ESRT detection rejects a lone TrackPoint firmware resource'

    $script:MockFirmwareDevices = @(
        [pscustomobject]@{
            Name = 'System Firmware'
            CompatibleID = @('UEFI\CC_00010001')
            HardwareID = @('UEFI\RES_{33333333-3333-3333-3333-333333333333}')
            DeviceID = 'UEFI\RES_{33333333-3333-3333-3333-333333333333}\0'
        }
    )
    $script:MockRegistryVersion = [uint32]0x00010013
    Assert-Equal -Actual (Get-LenovoSystemFirmwareVersion) -Expected '1.19' `
        -Description 'Lenovo ESRT detection falls back to the matching registry resource'

    $script:MockRegistryVersion = $null
    $script:MockFirmwareDevices[0].HardwareID = @('UEFI\RES_{33333333-3333-3333-3333-333333333333}&REV_43D518')
    Assert-Equal -Actual (Get-LenovoSystemFirmwareVersion) -Expected '' `
        -Description 'Lenovo ESRT detection rejects values outside Lenovo version bounds'

    $script:MockFirmwareDevices = @($script:MockFirmwareDevices[0], $script:MockFirmwareDevices[0])
    Assert-Equal -Actual (Get-LenovoSystemFirmwareVersion) -Expected '' `
        -Description 'Lenovo ESRT detection rejects ambiguous system-firmware resources'
} finally {
    Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-ItemProperty -ErrorAction SilentlyContinue
}

Write-Host 'Payload integrity harness completed successfully.'
