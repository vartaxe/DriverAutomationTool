BeforeAll {
    $Root = Split-Path -Parent $PSScriptRoot
    $Path = Join-Path $Root 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw 'Core module does not parse.' }
    $Function = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -eq 'Stop-DATCustomDismProcess'
    }, $true)
    if ($null -eq $Function) { throw 'Cancellation function was not found.' }
    . ([scriptblock]::Create($Function.Extent.Text))

    function Write-DATLogEntry { param($Value, $Severity) }
    function Resolve-DATCustomDismIdentity { param($Process, $BatchFile) throw 'Unmocked identity lookup' }
    function Get-DATCustomBuildProcessTree {
        param($RootProcessId, $RootCreationTimeUtcTicks, $RootExecutablePath, $RootCommandLine)
        throw 'Unmocked process enumeration'
    }
    function Stop-DATCustomBuildProcessTree { param($ProcessTree, $RootProcess) throw 'Unmocked process stop' }
}

Describe 'Custom DISM cancellation result and dependency contracts' {
    BeforeEach {
        $Process = [pscustomobject]@{ Id = 4200; HasExited = $false }
        $BatchFile = 'C:\DAT staging\HP EliteBook\capture.cmd'
        $Identity = [pscustomobject]@{
            ProcessId = 4200
            CreationTimeUtcTicks = ([datetime]'2026-10-09T21:00:00Z').ToUniversalTime().Ticks
            ExecutablePath = 'C:\Windows\System32\cmd.exe'
            CommandLine = 'cmd.exe /c "C:\DAT staging\HP EliteBook\capture.cmd"'
        }
        $Script:Tree = @(
            [pscustomobject]@{ ProcessId = 4200; Depth = 0; CreationTimeUtcTicks = $Identity.CreationTimeUtcTicks }
            [pscustomobject]@{ ProcessId = 4201; Depth = 1; CreationTimeUtcTicks = $Identity.CreationTimeUtcTicks + 10000000 }
        )
        Mock Write-DATLogEntry {}
        Mock Resolve-DATCustomDismIdentity { [pscustomobject]@{ Status = 'Verified'; Identity = $Identity } }
        Mock Get-DATCustomBuildProcessTree { $Script:Tree }
        Mock Stop-DATCustomBuildProcessTree {
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; StoppedCount = 2; FailedCount = 0 }
        }
    }

    It 'stops the verified tree using the supplied retained process and identity' {
        $Result = Stop-DATCustomDismProcess -Process $Process -Identity $Identity -BatchFile $BatchFile

        $Result.RootStopped | Should -BeTrue
        $Result.StoppedCount | Should -Be 2
        $Result.FailedCount | Should -Be 0
        Should -Invoke Resolve-DATCustomDismIdentity -Times 0 -Exactly
        Should -Invoke Get-DATCustomBuildProcessTree -Times 1 -Exactly -ParameterFilter {
            $RootProcessId -eq 4200 -and $RootCreationTimeUtcTicks -eq $Identity.CreationTimeUtcTicks -and
                $RootExecutablePath -eq $Identity.ExecutablePath -and $RootCommandLine -eq $Identity.CommandLine
        }
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 1 -Exactly -ParameterFilter {
            $RootProcess -eq $Process -and @($ProcessTree).Count -eq 2
        }
    }

    It 'resolves missing identity before enumerating or stopping processes' {
        $Result = Stop-DATCustomDismProcess -Process $Process -BatchFile $BatchFile

        $Result.RootStopped | Should -BeTrue
        Should -Invoke Resolve-DATCustomDismIdentity -Times 1 -Exactly -ParameterFilter {
            $Process.Id -eq 4200 -and $BatchFile -eq 'C:\DAT staging\HP EliteBook\capture.cmd'
        }
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 1 -Exactly
    }

    It 'returns without external process calls when the wrapper already exited' {
        $Process.HasExited = $true
        $Result = Stop-DATCustomDismProcess -Process $Process -BatchFile $BatchFile

        $Result | Should -BeNullOrEmpty
        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 1 -and $Value -like '*already exited*'
        }
        Should -Invoke Resolve-DATCustomDismIdentity -Times 0 -Exactly
        Should -Invoke Get-DATCustomBuildProcessTree -Times 0 -Exactly
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 0 -Exactly
    }

    It 'warns and stops nothing when the resolved identity does not match' {
        Mock Resolve-DATCustomDismIdentity { [pscustomobject]@{ Status = 'Mismatch'; Identity = $null } }
        $Result = Stop-DATCustomDismProcess -Process $Process -BatchFile $BatchFile

        $Result | Should -BeNullOrEmpty
        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 2 -and $Value -like '*does not match*No process was stopped*'
        }
        Should -Invoke Get-DATCustomBuildProcessTree -Times 0 -Exactly
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 0 -Exactly
    }

    It 'surfaces identity lookup errors without attempting cancellation' {
        Mock Resolve-DATCustomDismIdentity { throw 'CIM identity lookup denied' }
        $Result = Stop-DATCustomDismProcess -Process $Process -BatchFile $BatchFile

        $Result | Should -BeNullOrEmpty
        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 2 -and $Value -like '*CIM identity lookup denied*No process was stopped*'
        }
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 0 -Exactly
    }

    It 'does not attempt a stop when the verified tree is empty' {
        Mock Get-DATCustomBuildProcessTree { @() }
        $Result = Stop-DATCustomDismProcess -Process $Process -Identity $Identity -BatchFile $BatchFile

        $Result | Should -BeNullOrEmpty
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 0 -Exactly
    }

    It 'rejects null process and empty batch path before calling dependencies' {
        { Stop-DATCustomDismProcess -Process $null -BatchFile $BatchFile } | Should -Throw '*Process*'
        { Stop-DATCustomDismProcess -Process $Process -BatchFile '' } | Should -Throw '*BatchFile*'

        Should -Invoke Resolve-DATCustomDismIdentity -Times 0 -Exactly
        Should -Invoke Get-DATCustomBuildProcessTree -Times 0 -Exactly
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 0 -Exactly
    }

    It 'marks enumeration failure incomplete even if the verified wrapper is stopped' {
        Mock Get-DATCustomBuildProcessTree { throw 'CIM process enumeration denied' }
        Mock Stop-DATCustomBuildProcessTree {
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; StoppedCount = 1; FailedCount = 0 }
        }
        $Result = Stop-DATCustomDismProcess -Process $Process -Identity $Identity -BatchFile $BatchFile

        Should -Invoke Write-DATLogEntry -Times 1 -Exactly -ParameterFilter {
            $Severity -eq 2 -and $Value -like '*CIM process enumeration denied*'
        }
        Should -Invoke Stop-DATCustomBuildProcessTree -Times 1 -Exactly -ParameterFilter {
            $RootProcess -eq $Process -and @($ProcessTree).Count -eq 1 -and $ProcessTree[0].ProcessId -eq 4200
        }
        $Result.FailedCount | Should -BeGreaterThan 0
    }
}
