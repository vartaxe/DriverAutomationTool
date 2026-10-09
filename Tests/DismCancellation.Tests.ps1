BeforeAll {
    $Root = Split-Path -Parent $PSScriptRoot
    $Path = Join-Path $Root 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw 'Core module does not parse.' }
    $External = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -eq 'Invoke-DATDismExternal'
    }, $true)
    . ([scriptblock]::Create($External.Extent.Text))
    $Cancellation = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Left.Extent.Text -eq '$killDismTree'
    }, $true)
    if (($External.Extent.Text + $Cancellation.Extent.Text) -match 'taskkill|Stop-Process') {
        throw 'Unsafe PID-only cancellation detected; refusing to execute extracted code.'
    }
    function Write-DATLogEntry { param($Value, $Severity) }
    function Get-DATRetainedProcessStartTicks { param($Process) throw 'Unmocked handle check' }
    function Stop-DATCustomDismProcess { param($Process, $BatchFile) throw 'Unmocked cancellation' }

}

Describe 'External DISM cancellation ownership' {
    BeforeEach {
        $Script:Events = @()
        $Script:Completed = $true
        $Script:ExitCode = 0
        $Script:Process = [pscustomobject]@{ Id = 12345; ExitCode = 0 }
        $Script:Process | Add-Member ScriptMethod WaitForExit {
            param($Timeout)
            $Script:Events += 'wait'
            $Script:Completed
        }

        Mock Set-Content {}
        Mock Write-DATLogEntry {}
        Mock Start-Process { $Script:Events += 'launch'; $Script:Process }
        Mock Get-DATRetainedProcessStartTicks { $Script:Events += 'pin'; 1L }
        Mock Stop-DATCustomDismProcess {
            $Script:Events += 'verified-stop'
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; FailedCount = 0 }
        }
        Mock Test-Path { $false }
        Mock Remove-Item {}
    }

    It 'preserves native exit code <_> and pins the process before waiting' -ForEach @(0, 3010, 5) {
        $Script:Process.ExitCode = $_
        Invoke-DATDismExternal -Arguments '/mock' -WorkDir 'C:\mock' | Should -Be $_
        $Script:Events | Should -Be @('launch', 'pin', 'wait')
        Should -Invoke Stop-DATCustomDismProcess -Times 0 -Exactly
    }

    It 'uses verified cancellation on timeout and retains timeout result' {
        $Script:Completed = $false
        Invoke-DATDismExternal -Arguments '/mock' -WorkDir 'C:\mock' | Should -Be 1460
        $Script:Events | Should -Be @('launch', 'pin', 'wait', 'verified-stop')
        Should -Invoke Stop-DATCustomDismProcess -Times 1 -Exactly -ParameterFilter {
            $Process -eq $Script:Process -and $BatchFile -like 'C:\mock\DAT_DISM_*.cmd'
        }
    }

    It 'does not fall back to a PID kill when identity verification fails' {
        $Script:Completed = $false
        Mock Stop-DATCustomDismProcess { $null }
        Invoke-DATDismExternal -Arguments '/mock' -WorkDir 'C:\mock' | Should -Be 1460
        $External.Extent.Text | Should -Not -Match 'taskkill|Stop-Process'
    }

    It 'uses the same verified helper in capture abort and stall paths' {
        $Cancellation.Extent.Text | Should -Not -Match 'taskkill|Stop-Process'
        . ([scriptblock]::Create($Cancellation.Extent.Text))
        $dismBatchFile = 'C:\mock\capture.cmd'
        & $killDismTree $Script:Process
        Should -Invoke Stop-DATCustomDismProcess -Times 1 -Exactly -ParameterFilter {
            $Process -eq $Script:Process -and $BatchFile -eq 'C:\mock\capture.cmd'
        }
    }

    It 'fails capture cancellation explicitly when no stop can be verified' {
        . ([scriptblock]::Create($Cancellation.Extent.Text))
        $dismBatchFile = 'C:\mock\capture.cmd'
        Mock Stop-DATCustomDismProcess { $null }
        { & $killDismTree $Script:Process } | Should -Throw '*verify*'
    }

    It 'rejects incomplete capture cancellation instead of reporting packaging success' -ForEach @(
        @{ RootStopped = $false; RootExited = $false; FailedCount = 0 }
        @{ RootStopped = $true; RootExited = $false; FailedCount = 1 }
    ) {
        . ([scriptblock]::Create($Cancellation.Extent.Text))
        $dismBatchFile = 'C:\mock\capture.cmd'
        $Script:StopResult = [pscustomobject]@{
            RootStopped = $RootStopped; RootExited = $RootExited; FailedCount = $FailedCount
        }
        Mock Stop-DATCustomDismProcess { $Script:StopResult }
        { & $killDismTree $Script:Process } | Should -Throw '*verify*'
    }
}
