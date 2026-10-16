BeforeAll {
    $Root = Split-Path -Parent $PSScriptRoot
    $UiPath = Join-Path $Root 'Driver Automation Tool\UI\MainApplication.ps1'
    $Tokens = $null
    $Errors = $null
    $UiAst = [System.Management.Automation.Language.Parser]::ParseFile($UiPath, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw 'UI does not parse.' }
    $CustomAbort = $UiAst.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.IfStatementAst] -and
            $Node.Clauses[0].Item1.Extent.Text -like '*CustomBuildAbortRequested*' -and
            $Node.Extent.Text -like '*Stop-DATCustomDismProcess -Process $dismProcess*'
    }, $true)
    $CustomSuccess = $UiAst.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.IfStatementAst] -and
            $Node.Clauses[0].Item1.Extent.Text -like '*stdoutCheck*operation completed successfully*'
    }, $true)
    if ($null -eq $CustomAbort -or $null -eq $CustomSuccess) { throw 'Custom capture guards were not found.' }
    if (($CustomAbort.Extent.Text + $CustomSuccess.Extent.Text) -match 'Stop-Process|\.Kill\(') {
        throw 'Unsafe custom capture cancellation detected; refusing to execute extracted code.'
    }
    function Write-DATLogEntry { param($Value, $Severity) }
    function Stop-DATCustomDismProcess { param($Process, $Identity, $BatchFile) throw 'Unmocked cancellation' }
    function Get-ItemPropertyValue { param($Path, $Name) throw 'Unmocked abort flag lookup' }
}

Describe 'Custom capture cancellation guards' {
    BeforeEach {
        $dismProcess = [pscustomobject]@{ Id = 4200; HasExited = $false }
        $dismLaunch = [pscustomobject]@{ Identity = [pscustomobject]@{ ProcessId = 4200 } }
        $dismBatchFile = 'C:\mock\custom-capture.cmd'
        $stdoutCheck = 'The operation completed successfully'
        $effectiveExitCode = 1
        Mock Write-DATLogEntry {}
        Mock Get-ItemPropertyValue { 1 }
        Mock Stop-DATCustomDismProcess {
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; FailedCount = 0 }
        }
    }

    It 'reports an abort rather than treating successful cancellation as packaging success' {
        { . ([scriptblock]::Create($CustomAbort.Extent.Text)) } | Should -Throw 'Custom build aborted.'
        $effectiveExitCode | Should -Be 1
        Should -Invoke Stop-DATCustomDismProcess -Times 1 -Exactly
    }

    It 'rejects incomplete custom capture cancellation in both callers' -ForEach @(
        @{ StopResult = $null }
        @{ StopResult = [pscustomobject]@{ RootStopped = $true; RootExited = $false; FailedCount = 1 } }
        @{ StopResult = [pscustomobject]@{ RootStopped = $false; RootExited = $false; FailedCount = 0 } }
    ) {
        $Script:CustomStopResult = $StopResult
        Mock Stop-DATCustomDismProcess { $Script:CustomStopResult }

        { . ([scriptblock]::Create($CustomAbort.Extent.Text)) } | Should -Throw '*could not be verified as complete*'
        { . ([scriptblock]::Create($CustomSuccess.Extent.Text)) } | Should -Throw '*could not be verified as complete*'
        $effectiveExitCode | Should -Be 1
    }

    It 'accepts a success marker only after the verified tree was completely stopped' {
        . ([scriptblock]::Create($CustomSuccess.Extent.Text))

        $effectiveExitCode | Should -Be 0
        Should -Invoke Stop-DATCustomDismProcess -Times 1 -Exactly -ParameterFilter {
            $Process.Id -eq 4200 -and $BatchFile -eq 'C:\mock\custom-capture.cmd'
        }
    }
}
