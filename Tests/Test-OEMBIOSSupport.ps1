$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$currentCore = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
$hotFixCore = Join-Path $repoRoot 'HotFix\10.1.5\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
$readme = Get-Content (Join-Path $repoRoot 'README.md') -Raw
$supportedBIOSOEMs = @('Dell', 'HP', 'Lenovo')
$unsupportedBIOSOEMs = @('Microsoft', 'Acer', 'Panasonic', 'Fujitsu', 'ASUS')

function Assert-DAT {
    param ([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Set-DATModuleTestSeams {
    param (
        [System.Management.Automation.PSModuleInfo]$Module,
        [string]$TempRoot
    )

    & $Module {
        param ($TestRoot, $RepositoryRoot)

        $global:TempDirectory = $TestRoot
        $global:RegPath = 'HKCU:\Software\DriverAutomationTool\Tests'
        $global:ScriptDirectory = Join-Path $RepositoryRoot 'Driver Automation Tool'
        $global:ToolsDirectory = Join-Path $TestRoot 'Tools'
        $script:DATTestOEM = ''
        $script:DATTestExtractDir = ''
        $script:DATTestStartProcessCalls = 0

        Set-Item -Path Function:script:Set-DATRegistryValue -Value {
            param ([string]$Name, [object]$Value, [string]$Type)
        }

        Set-Item -Path Function:script:Write-DATLogEntry -Value {
            param ([string]$Value, [int]$Severity = 1, [switch]$UpdateUI)
        }

        Set-Item -Path Function:script:Assert-DATTemplateSourceTrusted -Value {
            param ([string]$Context)
        }

        Set-Item -Path Function:script:Invoke-DATCodeSign -Value {
            param ([string]$ScriptPath)
        }

        Set-Item -Path Function:script:Start-Process -Value {
            param (
                [string]$FilePath,
                [object]$ArgumentList,
                [object]$WindowStyle,
                [switch]$PassThru,
                [switch]$Wait,
                [switch]$NoNewWindow,
                [object]$ErrorAction
            )

            $script:DATTestStartProcessCalls++
            switch ($script:DATTestOEM) {
                'HP' {
                    Set-Content -LiteralPath (Join-Path $script:DATTestExtractDir 'HPFirmwareUpdRec64.exe') -Value 'mock hp flasher'
                }
                'Lenovo' {
                    Set-Content -LiteralPath (Join-Path $script:DATTestExtractDir 'WinUPTP64.exe') -Value 'mock lenovo flasher'
                    Set-Content -LiteralPath (Join-Path $script:DATTestExtractDir 'firmware.cap') -Value 'mock lenovo firmware'
                }
                default {
                    throw "Unexpected mocked process execution for $($script:DATTestOEM): $FilePath"
                }
            }

            $process = [pscustomobject]@{
                ExitCode = 0
                HasExited = $true
                Id = 4242
            }
            $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param ($TimeoutMilliseconds) $true }
            return $process
        }
    } $TempRoot $repoRoot
}

function Set-DATPackagingCase {
    param (
        [System.Management.Automation.PSModuleInfo]$Module,
        [string]$OEM,
        [string]$ExtractDir
    )

    & $Module {
        param ($TestOEM, $TestExtractDir)
        $script:DATTestOEM = $TestOEM
        $script:DATTestExtractDir = $TestExtractDir
    } $OEM $ExtractDir
}

function Get-DATStartProcessCallCount {
    param ([System.Management.Automation.PSModuleInfo]$Module)
    return & $Module { $script:DATTestStartProcessCalls }
}

function Test-DATModuleBehavior {
    param (
        [string]$Path,
        [string]$Label
    )

    Remove-Module DriverAutomationToolCore -Force -ErrorAction SilentlyContinue
    Import-Module $Path -Force
    $module = Get-Module DriverAutomationToolCore
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("DAT-OEMBIOS-$Label-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

    try {
        Set-DATModuleTestSeams -Module $module -TempRoot $tempRoot

        foreach ($oem in $supportedBIOSOEMs) {
            Assert-DAT (Test-DATBIOSInstallerSupport -OEM $oem) "$Label exposes $oem as a supported BIOS build OEM"

            $model = 'RegressionModel'
            $sourcePath = Join-Path $tempRoot "$oem-source.exe"
            Set-Content -LiteralPath $sourcePath -Value "mock $oem BIOS payload"
            $extractDir = Join-Path $tempRoot "BIOSExtract\$oem\$model"
            Set-DATPackagingCase -Module $module -OEM $oem -ExtractDir $extractDir

            $stagingPath = Invoke-DATBiosPackaging -BiosFilePath $sourcePath -OEM $oem -Model $model `
                -Version '1.2.3' -PackageDestination (Join-Path $tempRoot 'Packages') -SkipWim

            Assert-DAT (Test-Path -LiteralPath $stagingPath -PathType Container) "$Label builds a staged $oem BIOS package"
            $manifestPath = Join-Path $stagingPath 'DAT-BIOS-SHA256.txt'
            Assert-DAT (Test-Path -LiteralPath $manifestPath -PathType Leaf) "$Label emits an integrity manifest for $oem"
            $manifestEntries = @(Get-Content -LiteralPath $manifestPath)
            Assert-DAT ($manifestEntries.Count -ge 1 -and ($manifestEntries -notmatch 'DAT-BIOS-SHA256.txt')) "$Label manifests the staged $oem payload"
        }

        foreach ($oem in $unsupportedBIOSOEMs) {
            Assert-DAT (-not (Test-DATBIOSInstallerSupport -OEM $oem)) "$Label rejects $oem in the BIOS support contract"
            $sourcePath = Join-Path $tempRoot "$oem-source.exe"
            Set-Content -LiteralPath $sourcePath -Value "mock $oem BIOS payload"
            $extractDir = Join-Path $tempRoot "BIOSExtract\$oem\RegressionModel"
            Set-DATPackagingCase -Module $module -OEM $oem -ExtractDir $extractDir
            $callsBefore = Get-DATStartProcessCallCount -Module $module

            $message = ''
            try {
                Invoke-DATBiosPackaging -BiosFilePath $sourcePath -OEM $oem -Model 'RegressionModel' `
                    -Version '1.2.3' -PackageDestination (Join-Path $tempRoot 'Packages') -SkipWim | Out-Null
            } catch {
                $message = $_.Exception.Message
            }

            Assert-DAT ($message -match 'Standalone BIOS packaging is not supported') "$Label fails $oem packaging closed"
            Assert-DAT ((Get-DATStartProcessCallCount -Module $module) -eq $callsBefore) "$Label does not execute an installer while rejecting $oem"
            Assert-DAT (-not (Test-Path -LiteralPath $extractDir)) "$Label rejects $oem before creating package content"
        }

        $generatedRoot = Join-Path $tempRoot 'GeneratedInstallers'
        New-Item -Path $generatedRoot -ItemType Directory -Force | Out-Null
        foreach ($oem in @($supportedBIOSOEMs + $unsupportedBIOSOEMs)) {
            $outputPath = Join-Path $generatedRoot "$oem-Install-BIOS.ps1"
            New-DATIntuneInstallScript -OutputPath $outputPath -OEM $oem -Model 'RegressionModel' `
                -OS 'Windows 11' -Version '1.2.3' -UpdateType BIOS -DisableToast -DisableRestart | Out-Null
            Assert-DAT (Test-Path -LiteralPath $outputPath -PathType Leaf) "$Label generates the $oem BIOS installer preflight"

            $priorErrorActionPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                    -File $outputPath -ValidateManufacturerOnly 2>&1)
                $exitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $priorErrorActionPreference
            }
            if ($oem -in $supportedBIOSOEMs) {
                Assert-DAT ($exitCode -eq 0) "$Label generated installer accepts $oem"
                Assert-DAT (($output -join "`n") -match 'Validated standalone BIOS installer path') "$Label executes the $oem apply preflight"
            } else {
                Assert-DAT ($exitCode -eq 1) "$Label generated installer rejects $oem"
                Assert-DAT (($output -join "`n") -match 'Standalone BIOS installation is not supported') "$Label fails the $oem apply preflight closed"
            }
        }
    } finally {
        Remove-Module DriverAutomationToolCore -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$expectedMatrix = [ordered]@{
    'HP'                = @('✅', '✅')
    'Dell'              = @('✅', '✅')
    'Lenovo'            = @('✅', '✅')
    'Microsoft Surface' = @('✅', '—')
    'Acer'              = @('✅', '—')
    'Panasonic'         = @('✅', '—')
    'Fujitsu'           = @('✅', '—')
    'ASUS'              = @('✅', '—')
}

$supportedSection = [regex]::Match(
    $readme,
    '(?s)## Supported OEMs\s+(?<section>.*?)\s+## Core Features'
).Groups['section'].Value
$matrixRows = @($supportedSection -split "`r?`n" | Where-Object {
    $_ -match '^\|' -and $_ -notmatch '^\|\s*(OEM|-+)'
})
Assert-DAT ($matrixRows.Count -eq 8) 'README support matrix contains exactly eight OEM rows'

foreach ($oem in $expectedMatrix.Keys) {
    $escapedOEM = [regex]::Escape($oem)
    $matchingRows = @($matrixRows | Where-Object { $_ -match "^\|\s*$escapedOEM\s*\|" })
    Assert-DAT ($matchingRows.Count -eq 1) "README contains exactly one $oem support row"
    $columns = @($matchingRows[0].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    Assert-DAT ($columns.Count -eq 3) "README $oem support row has three columns"
    Assert-DAT ($columns[1] -ceq $expectedMatrix[$oem][0]) "README documents $oem driver support exactly"
    Assert-DAT ($columns[2] -ceq $expectedMatrix[$oem][1]) "README documents $oem standalone BIOS support exactly"
}

$allOEMsText = 'HP, Dell, Lenovo, Microsoft Surface, Acer, Panasonic, Fujitsu, and ASUS'
Assert-DAT ($readme.Contains("Driver catalog discovery and packaging for $allOEMsText")) 'README Multi-OEM text names all eight driver OEMs'
Assert-DAT ($readme -match 'Standalone BIOS\s+package creation and installation is currently validated only for Dell, HP, and Lenovo') 'README documents the validated BIOS boundary'
Assert-DAT ($readme -match 'Microsoft Surface firmware is delivered through driver packages') 'README keeps Microsoft standalone BIOS blocked'
Assert-DAT ($readme -match 'BIOS packages for Acer,\s+Panasonic, Fujitsu, and ASUS are not generated') 'README documents every unsupported standalone BIOS OEM'

Test-DATModuleBehavior -Path $currentCore -Label 'current'
Test-DATModuleBehavior -Path $hotFixCore -Label 'HotFix'

Write-Host 'OEM BIOS support behavior regression harness completed successfully.'
