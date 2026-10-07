$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $repoRoot 'Data\Invoke-IntuneDriverUpdate.ps1'
$scriptContent = Get-Content -LiteralPath $scriptPath -Raw

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not $Condition) {
        throw "FAILED: $Description"
    }
    Write-Host "PASS: $Description"
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Description,
        [string]$MessagePattern
    )

    $exception = $null
    try {
        & $Action
    }
    catch {
        $exception = $_.Exception
    }

    Assert-True -Condition ($null -ne $exception) -Description $Description
    if (-not [string]::IsNullOrWhiteSpace($MessagePattern)) {
        Assert-True -Condition ($exception.Message -match $MessagePattern) `
            -Description "$Description returns an actionable error"
    }
}

function Get-FunctionDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
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

foreach ($functionName in @(
    'Test-DATSecureDownloadUri',
    'Set-DATRequestProxy',
    'Get-DATRedirectedUrl',
    'FindLenovoDriver',
    'Test-DATFileIntegrity',
    'Assert-DATVendorPayload',
    'Get-DATCatalogSha256',
    'Stop-DATMicrosoftLegacyCatalog'
)) {
    Invoke-Expression (Get-FunctionDefinition -Path $scriptPath -Name $functionName)
}

Assert-Throws -Action {
    Test-DATSecureDownloadUri -Uri 'http://downloads.dell.com/payload.cab' `
        -AllowedHosts @('downloads.dell.com')
} -Description 'initial HTTP URLs are rejected' -MessagePattern 'non-HTTPS'

Assert-Throws -Action {
    Get-DATRedirectedUrl -URL 'https://downloads.dell.com/start' `
        -AllowedHosts @('downloads.dell.com') -ResponseProvider {
            [pscustomobject]@{
                StatusCode = 302
                Headers = @{ Location = 'http://downloads.dell.com/payload.cab' }
            }
        }
} -Description 'HTTPS-to-HTTP redirects are rejected through the manual response seam' `
    -MessagePattern 'non-HTTPS'

Assert-Throws -Action {
    Test-DATSecureDownloadUri -Uri 'https://attacker.example/payload.cab' `
        -AllowedHosts @('downloads.dell.com')
} -Description 'hosts outside the per-use allowlist are rejected' -MessagePattern 'Allowed host'

$previousProxyOptions = $global:InvokeProxyOptions
try {
    $global:InvokeProxyOptions = @{
        Proxy = 'http://proxy.example:8080'
        ProxyUseDefaultCredentials = $true
    }
    $proxyRequest = [System.Net.HttpWebRequest]::Create('https://downloads.dell.com/catalog/DriverPackCatalog.cab')
    Set-DATRequestProxy -Request $proxyRequest
    Assert-True -Condition ($null -ne $proxyRequest.Proxy.Credentials) `
        -Description 'Windows-integrated proxy authentication receives default credentials'

    $explicitCredential = New-Object System.Net.NetworkCredential('proxy-user', 'proxy-password')
    $global:InvokeProxyOptions.ProxyCredential = $explicitCredential
    $explicitProxyRequest = [System.Net.HttpWebRequest]::Create('https://downloads.dell.com/catalog/DriverPackCatalog.cab')
    Set-DATRequestProxy -Request $explicitProxyRequest
    Assert-True -Condition ([object]::ReferenceEquals(
        $explicitProxyRequest.Proxy.Credentials,
        $explicitCredential
    )) -Description 'explicit proxy credentials take precedence over default credentials'
}
finally {
    $global:InvokeProxyOptions = $previousProxyOptions
}

Assert-Throws -Action {
    FindLenovoDriver -URI 'http://support.lenovo.com/example' -OS '11' -Architecture '64'
} -Description 'Lenovo discovery rejects HTTP pages' -MessagePattern 'non-HTTPS'

Assert-Throws -Action {
    FindLenovoDriver -URI 'https://support.lenovo.com.attacker.example/example' `
        -OS '11' -Architecture '64'
} -Description 'Lenovo discovery rejects malformed non-official hosts' -MessagePattern 'Allowed host'

$catalogHash = 'A' * 64
[xml]$dellHashFixture = "<DriverPackage><Cryptography><Hash algorithm=`"SHA256`">$catalogHash</Hash></Cryptography></DriverPackage>"
Assert-True -Condition ((Get-DATCatalogSha256 -CatalogNode $dellHashFixture.DriverPackage) -eq $catalogHash) `
    -Description 'Dell Cryptography/Hash SHA256 metadata is read exactly'
[xml]$hpHashFixture = "<SoftPaq><SHA256>$catalogHash</SHA256></SoftPaq>"
Assert-True -Condition ((Get-DATCatalogSha256 -CatalogNode $hpHashFixture.SoftPaq) -eq $catalogHash) `
    -Description 'HP SoftPaq SHA256 metadata is read exactly'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DATIntuneSecurity_$([guid]::NewGuid().ToString('N'))"
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $payloadPath = Join-Path $tempRoot 'payload.exe'
    [System.IO.File]::WriteAllBytes($payloadPath, [byte[]](1, 2, 3, 4))
    $expectedHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash

    Assert-True -Condition (Test-DATFileIntegrity -FilePath $payloadPath `
        -ExpectedSha256 $expectedHash -RequireHash) `
        -Description 'an exact authoritative SHA256 is accepted'

    Assert-Throws -Action {
        Test-DATFileIntegrity -FilePath $payloadPath -ExpectedSha256 ('0' * 64) -RequireHash
    } -Description 'an authoritative SHA256 mismatch is rejected' -MessagePattern 'SHA256 mismatch'
    Assert-True -Condition (-not (Test-Path -LiteralPath $payloadPath)) `
        -Description 'a payload with an authoritative hash mismatch is deleted'

    [System.IO.File]::WriteAllBytes($payloadPath, [byte[]](1, 2, 3, 4))
    $script:signatureCalls = 0
    Assert-Throws -Action {
        Test-DATFileIntegrity -FilePath $payloadPath -ExpectedSha256 ('0' * 64) `
            -PublisherPattern 'Lenovo' -SignatureProvider {
                $script:signatureCalls++
                [pscustomobject]@{
                    Status = 'Valid'
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Lenovo' }
                }
            }
    } -Description 'a signer cannot override an authoritative hash mismatch' `
        -MessagePattern 'SHA256 mismatch'
    Assert-True -Condition ($script:signatureCalls -eq 0) `
        -Description 'Authenticode is not consulted after an authoritative hash mismatch'

    [System.IO.File]::WriteAllBytes($payloadPath, [byte[]](5, 6, 7, 8))
    Assert-True -Condition (Test-DATFileIntegrity -FilePath $payloadPath `
        -PublisherPattern 'Lenovo' -SignatureProvider {
            [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Lenovo PC HK Limited, O=Lenovo'
                }
            }
        }) -Description 'a valid Lenovo signer is accepted when no vendor hash exists'

    foreach ($signatureFixture in @(
        [pscustomobject]@{
            Status = 'Valid'
            SignerCertificate = [pscustomobject]@{ Subject = 'CN=Unexpected Publisher' }
        },
        [pscustomobject]@{
            Status = 'NotSigned'
            SignerCertificate = $null
        }
    )) {
        [System.IO.File]::WriteAllBytes($payloadPath, [byte[]](5, 6, 7, 8))
        $script:signatureFixture = $signatureFixture
        Assert-Throws -Action {
            Test-DATFileIntegrity -FilePath $payloadPath -PublisherPattern 'Lenovo' `
                -SignatureProvider { $script:signatureFixture }
        } -Description 'a wrong or unsigned Lenovo payload is rejected' `
            -MessagePattern '(approved vendor publisher|Authenticode validation failed)'
    }

    [System.IO.File]::WriteAllBytes($payloadPath, [byte[]](9, 10, 11, 12))
    $cachedHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash
    Assert-True -Condition (Test-DATFileIntegrity -FilePath $payloadPath `
        -ExpectedSha256 $cachedHash -RequireHash) `
        -Description 'a valid cached payload passes revalidation'
    Add-Content -LiteralPath $payloadPath -Value 'tampered'
    Assert-Throws -Action {
        Test-DATFileIntegrity -FilePath $payloadPath -ExpectedSha256 $cachedHash -RequireHash
    } -Description 'a modified cached payload fails revalidation' -MessagePattern 'SHA256 mismatch'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Assert-Throws -Action {
    Stop-DATMicrosoftLegacyCatalog
} -Description 'the Microsoft legacy catalog path fails closed' `
    -MessagePattern 'legacy unsigned third-party Microsoft catalog'

Assert-True -Condition (-not $scriptContent.Contains('MicrosoftXMLSource')) `
    -Description 'the Microsoft legacy catalog source constant is absent'
Assert-True -Condition (-not $scriptContent.Contains('scconfigmgr.com/wp-content/uploads/xml/downloadlinks.xml')) `
    -Description 'the broken third-party Microsoft catalog URL is absent'
Assert-True -Condition (-not ($scriptContent -match '\b(Start-BitsTransfer|Start-Job|Get-BitsTransfer)\b')) `
    -Description 'BITS and background-job download paths are absent'
Assert-True -Condition ($scriptContent.Contains('Revalidating cached')) `
    -Description 'the cached payload path explicitly revalidates before use'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
$httpStringLiterals = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
    $node.Value -match '^http://'
}, $true)
Assert-True -Condition ($httpStringLiterals.Count -eq 0) `
    -Description 'no executable source string literal uses HTTP'

Write-Host 'All Intune driver update security tests passed.'
