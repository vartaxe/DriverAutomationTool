BeforeAll {
    $hadRegPath = $null -ne (Get-Variable -Name RegPath -Scope Global -ErrorAction SilentlyContinue)
    $savedRegPath = $global:RegPath
    $global:RegPath = 'HKLM:\DATHeadlessTests'
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $corePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $headlessPath = Join-Path $repoRoot 'Driver Automation Tool\Start-DATHeadlessBuild.ps1'
    $coreAst = [Management.Automation.Language.Parser]::ParseFile($corePath, [ref]$null, [ref]$null)
    foreach ($name in @('Export-DATBuildConfig', 'Import-DATBuildConfig')) {
        $node = $coreAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name
        }.GetNewClosure(), $true)
        if ($null -eq $node) { throw "Config function not found: $name" }
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $headlessAst = [Management.Automation.Language.Parser]::ParseFile($headlessPath, [ref]$null, [ref]$null)
    $buildTry = $headlessAst.Find({
        param($item)
        $item -is [Management.Automation.Language.TryStatementAst] -and
            @($item.Body.Statements | Where-Object {
                $_ -is [Management.Automation.Language.PipelineAst] -and
                    $_.Extent.Text -eq 'Start-DATModelProcessing @processingParams'
            }).Count -eq 1
    }, $true)
    if ($null -eq $buildTry) { throw 'Headless build lifecycle not found' }
    $buildLifecycle = [scriptblock]::Create($buildTry.Extent.Text)
    function Write-DATLogEntry { param($Value, $Severity, [switch]$UpdateUI) }
    function Start-DATModelProcessing { throw 'Unmocked build' }
    function Get-DATUpgradeRequiredState { throw 'Unmocked upgrade state' }
    function Clear-DATUpgradeRequiredState { throw 'Unmocked upgrade state cleanup' }
    function Set-DATRunState { param($State, $Detail) throw 'Unmocked run state write' }
    function Get-ScheduledTask { [CmdletBinding()] param($TaskPath, $TaskName) throw 'Unmocked task lookup' }
    function Unregister-ScheduledTask { param($TaskPath, $TaskName, [switch]$Confirm) throw 'Unmocked task removal' }
    function Send-DATSummaryReport { param($DriverPackagesCreated, $BiosPackagesCreated, $ModelsProcessed, $Platform, $ExecutionMode) throw 'Unmocked telemetry' }
    function Invoke-DATPackageRetention { param($OEM, $Model, $OS, $Architecture, $PackageType, $RetainCount) throw 'Unmocked retention' }
    function Set-DATRegistryValue { param($Name, $Value, $Type) throw 'Unmocked progress write' }
    function Write-DATOfflineManifestAndScript { param($OfflineRoot, $Packages) throw 'Unmocked offline export' }

    $processingNode = $coreAst.Find({
        param($item)
        $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq 'Start-DATModelProcessing'
    }, $true)
    $completionNode = $processingNode.Find({
        param($item)
        $item -is [Management.Automation.Language.IfStatementAst] -and
            $item.Clauses[0].Item1.Extent.Text -eq '$completedCount -eq $totalModels'
    }, $true)
    $offlineNode = $processingNode.Find({
        param($item)
        $item -is [Management.Automation.Language.IfStatementAst] -and
            $item.Clauses[0].Item1.Extent.Text -eq '$isOfflineCM' -and
            $item.Extent.Text -like '*Write-DATOfflineManifestAndScript*'
    }, $true)
    if ($null -eq $completionNode -or $null -eq $offlineNode) { throw 'Model completion/export lifecycle not found' }
    $completionTail = [scriptblock]::Create((
        $completionNode.Parent.Statements |
            Where-Object { $_.Extent.StartOffset -ge $offlineNode.Extent.StartOffset -and $_.Extent.EndOffset -le $completionNode.Extent.EndOffset } |
            ForEach-Object { $_.Extent.Text }
    ) -join "`r`n")
}

AfterAll {
    if ($hadRegPath) {
        $global:RegPath = $savedRegPath
    } else {
        Remove-Variable -Name RegPath -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Scheduled build configuration round trips' {
    BeforeEach {
        Mock Write-DATLogEntry {}
        $configPath = Join-Path $TestDrive 'BuildConfig.json'
        $exportParams = @{
            ConfigPath = $configPath
            Platform = 'Download Only'
            OS = 'Windows 11'
            Architecture = 'x64'
            Models = @([pscustomobject]@{ OEM = 'Dell'; Model = 'Example' })
        }
    }
    It 'preserves DisableRestart=<Disabled> through export and import' -ForEach @(
        @{ Disabled = $true }
        @{ Disabled = $false }
    ) {
        Export-DATBuildConfig @exportParams -DisableRestart $Disabled
        (Import-DATBuildConfig -ConfigPath $configPath).DisableRestart | Should -BeExactly $Disabled
    }
    It 'defaults omitted DisableRestart to false for older configuration files' {
        Export-DATBuildConfig @exportParams
        $raw = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $raw.PSObject.Properties.Remove('DisableRestart')
        $raw | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8
        (Import-DATBuildConfig -ConfigPath $configPath).DisableRestart | Should -BeExactly $false
    }
    It 'round trips a configuration filename containing wildcard characters literally' {
        $exportParams.ConfigPath = Join-Path $TestDrive '[BuildConfig].json'
        Export-DATBuildConfig @exportParams -DisableRestart $true
        (Import-DATBuildConfig -ConfigPath $exportParams.ConfigPath).Models[0].Model | Should -Be 'Example'
    }
}

Describe 'Headless build outcomes and post-build actions' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $config = [pscustomobject]@{
            Platform = 'Download Only'
            PackageType = 'Drivers'
            Architecture = 'x64'
            OS = 'Windows 11'
            Models = @([pscustomobject]@{ OEM = 'Dell'; Model = 'Example'; OS = 'Windows 11'; Architecture = 'x64' })
            CleanTempOnExit = $false
            PackageRetention = [pscustomobject]@{ Enabled = $true; RetainCount = 0; DeleteSourceFolderOnRemoval = $false }
            ConfigMgr = $null
        }

        $headlessModels = $config.Models
        $ConfigPath = 'C:\mock\BuildConfig.json'
        $storagePath = 'C:\mock\storage'
        $processingParams = @{}
        $buildExitCode = 0
        Mock Write-DATLogEntry {}
        Mock Start-DATModelProcessing {}
        Mock Get-ItemProperty { [pscustomobject]@{ RunningState = 'Completed' } }
        Mock Get-DATUpgradeRequiredState { $null }
        Mock Clear-DATUpgradeRequiredState {}
        Mock Set-DATRunState {}
        Mock Send-DATSummaryReport {}
        Mock Get-ScheduledTask { $null }
        Mock Unregister-ScheduledTask { throw 'No task should be removed' }
        Mock Invoke-DATPackageRetention {}
        Mock Test-Path { $false }
    }
    It 'reports <State> as success' -ForEach @(
        @{ State = 'Completed' }
        @{ State = 'CompletedNoMatch' }
    ) {
        Mock Get-ItemProperty { [pscustomobject]@{ RunningState = $State } }
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 0
        Should -Invoke Set-DATRunState -Times 1 -Exactly -ParameterFilter { $State -eq 'Completed' }
        Should -Invoke Send-DATSummaryReport -Times 1 -Exactly
    }
    It 'rejects non-success state <State> before retention or success reporting' -ForEach @(
        @{ State = 'CompletedWithErrors' }
        @{ State = 'Aborted' }
        @{ State = 'Error' }
        @{ State = 'Running' }
        @{ State = '' }
    ) {
        $config.Platform = 'Configuration Manager'
        Mock Get-ItemProperty { [pscustomobject]@{ RunningState = $State } }
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 1
        Should -Invoke Invoke-DATPackageRetention -Times 0 -Exactly
        Should -Invoke Send-DATSummaryReport -Times 0 -Exactly
        Should -Invoke Set-DATRunState -Times 1 -Exactly -ParameterFilter { $State -eq 'Failed' }
    }
    It 'fails closed when the build outcome cannot be read' {
        Mock Get-ItemProperty { throw 'Registry unavailable' }
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 1
        Should -Invoke Send-DATSummaryReport -Times 0 -Exactly
        Should -Invoke Set-DATRunState -Times 1 -Exactly -ParameterFilter { $State -eq 'Failed' }
    }
    It 'still permits configured retention after a successful build' {
        $config.Platform = 'Configuration Manager'
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 0
        Should -Invoke Invoke-DATPackageRetention -Times 1 -Exactly
    }
    It 'logs an ordinary failure and completes cleanup without rethrowing error output' {
        Mock Start-DATModelProcessing { throw 'Build failed deliberately' }
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 1
        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 3 -and $Value -like '*Build failed deliberately*'
        }
        Should -Invoke Set-DATRunState -Times 1 -Exactly -ParameterFilter { $State -eq 'Failed' }
    }
    It 'preserves upgrade-required exit code 2 and clears the upgrade marker' {
        Mock Start-DATModelProcessing { throw 'DATUpgradeRequired: test upgrade' }
        Mock Get-DATUpgradeRequiredState {
            [pscustomobject]@{ Message = 'Upgrade required'; DownloadUrl = 'https://example.invalid/upgrade' }
        }
        . $buildLifecycle 2>$null
        $buildExitCode | Should -Be 2
        Should -Invoke Clear-DATUpgradeRequiredState -Times 1 -Exactly
        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 3 -and $Value -like '*Upgrade required (HTTP 426)*'
        }
        Should -Invoke Set-DATRunState -Times 1 -Exactly -ParameterFilter { $State -eq 'Failed' }
    }
}

Describe 'Model completion publication' {
    BeforeEach {
        $script:finalState = 'Running'
        $isOfflineCM = $true
        $offlineRoot = 'C:\mock\offline'
        $offlinePackages = [Collections.Generic.List[object]]::new()
        $offlinePackages.Add([pscustomobject]@{ Name = 'Example' })
        $GenerateXmlLogicPackage = $false
        $completedCount = 1
        $totalModels = 1
        $effectivePackageType = 'Drivers'
        $biosNoMatchCount = 0
        Mock Get-ItemProperty { [pscustomobject]@{ RunningState = 'Running' } }
        Mock Write-DATOfflineManifestAndScript { 'C:\mock\offline\manifest.json' }
        Mock Write-DATLogEntry { if ($UpdateUI) { $script:finalState = 'Running' } }
        Mock Set-DATRegistryValue { if ($Name -eq 'RunningState') { $script:finalState = $Value } }
    }
    It 'publishes completion only after the offline export block' {
        $completionNode.Extent.StartOffset | Should -BeGreaterThan $offlineNode.Extent.EndOffset
    }
    It 'leaves a completed offline build completed after progress logging' {
        . $completionTail
        $script:finalState | Should -Be 'Completed'
        Should -Invoke Write-DATOfflineManifestAndScript -Times 1 -Exactly
    }
    It 'does not overwrite an abort requested during post-processing' {
        Mock Get-ItemProperty { [pscustomobject]@{ RunningState = 'Aborted' } }
        . $completionTail
        Should -Invoke Set-DATRegistryValue -Times 0 -Exactly -ParameterFilter { $Name -eq 'RunningState' }
    }
}
