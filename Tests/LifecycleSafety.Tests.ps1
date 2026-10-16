BeforeAll {
    $Root = Split-Path -Parent $PSScriptRoot
    $CorePath = Join-Path $Root 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $UiPath = Join-Path $Root 'Driver Automation Tool\UI\MainApplication.ps1'
    $CoreAst = [Management.Automation.Language.Parser]::ParseFile($CorePath, [ref]$null, [ref]$null)
    $UiAst = [Management.Automation.Language.Parser]::ParseFile($UiPath, [ref]$null, [ref]$null)
    foreach ($name in @('Stop-DATCustomBuildProcessTree', 'Dismount-DATOwnedImages', 'New-DATDismBatchFile',
        'Assert-DATDismRuntimePath', 'Get-DATEffectiveFileSystemRights')) {
        $node = $CoreAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name
        }.GetNewClosure(), $true)
        . ([scriptblock]::Create($node.Extent.Text))
        $node = $UiAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $item.Name -eq 'Test-DATCustomBuildRecoveryPending'
        }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
        $poll = $UiAst.Find({
            param($item)
            $item -is [Management.Automation.Language.WhileStatementAst] -and
                $item.Condition.Extent.Text -like '*dismProcess.HasExited*' -and
                $item.Extent.Text -like '*CustomBuildAbortRequested*'
        }, $true)
        if ($null -eq $poll) { throw 'Custom DISM polling loop not found' }
        $pollTry = $poll.Parent.Parent
        if ($pollTry -isnot [Management.Automation.Language.TryStatementAst]) { throw 'Polling cleanup guard not found' }
        $PollingText = $pollTry.Extent.Text
    }
    $node = $UiAst.Find({
        param($item)
        $item -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $item.Name -eq 'Invoke-DATCustomBuildAbortCleanup'
    }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
    function Write-DATLogEntry { param($Value, $Severity) }
    function Write-DATActivityLog { param($Message, $Level) }
    function Get-DATRetainedProcessStartTicks { param($Process) throw 'Unmocked process identity' }
    function Test-DATSafeContentRoot { param($Path) throw 'Unmocked storage root' }
    function Get-DATNonAdminWriteAccess { param($Path) throw 'Unmocked permissions check' }
    function Dismount-WindowsImage { param($Path, [switch]$Discard) throw 'Unmocked DISM' }
    function Get-ItemPropertyValue { param($Path, $Name) throw 'Unmocked registry' }
    function Set-DATRegistryValue { param($Name, $Value, $Type) throw 'Unmocked registry write' }
    function Stop-DATCustomDismProcess { param($Process, $Identity, $BatchFile) throw 'Unmocked cancellation' }
}

Describe 'Runtime ancestry trust' {
    BeforeEach {
        $Script:RuntimeAcl = New-Object Security.AccessControl.DirectorySecurity
        $Script:RuntimeAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        $Script:RuntimeItem = [pscustomobject]@{
            FullName = 'C:\Program Files\DATRuntime'
            PSIsContainer = $true
            Attributes = [IO.FileAttributes]::Directory
            Parent = $null
        }
        Mock Get-Item { $Script:RuntimeItem }
        Mock Get-Acl { $Script:RuntimeAcl }
        Mock Get-DATNonAdminWriteAccess { @() }
    }
    It 'rejects junctions before checking content permissions' {
        $Script:RuntimeItem.Attributes = [IO.FileAttributes]::ReparsePoint
        { Assert-DATDismRuntimePath -Path 'C:\Program Files\DATRuntime' } | Should -Throw '*Unsafe*'
        Should -Invoke Get-Acl -Times 0 -Exactly
    }
    It 'rejects a non-administrative owner even without writable ACEs' {
        $Script:RuntimeAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-21-1-2-3-1001')))
        { Assert-DATDismRuntimePath -Path 'C:\Program Files\DATRuntime' } | Should -Throw '*untrusted owner*'
    }
    It 'rejects writable runtime content' {
        Mock Get-DATNonAdminWriteAccess { [pscustomobject]@{ Identity = 'Everyone' } }
        { Assert-DATDismRuntimePath -Path 'C:\Program Files\DATRuntime' } | Should -Throw '*writable*'
    }
    It 'rejects a parent that permits ordinary users to replace protected children' {
        $Script:RuntimeItem.Parent = [pscustomobject]@{
            FullName = 'C:\Program Files'
            PSIsContainer = $true
            Attributes = [IO.FileAttributes]::Directory
            Parent = $null
        }
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),
            [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,
            [Security.AccessControl.AccessControlType]::Allow)
        $Script:RuntimeAcl.AddAccessRule($rule)
        { Assert-DATDismRuntimePath -Path 'C:\Program Files\DATRuntime' } | Should -Throw '*ancestry can be replaced*'
    }
    It 'accepts an administrator-owned runtime with trusted ancestry' {
        { Assert-DATDismRuntimePath -Path 'C:\Program Files\DATRuntime' } | Should -Not -Throw
    }
    It 'accepts raw DirectoryInfo ancestors without provider-only properties' {
        $Script:RuntimeItem = New-Object IO.DirectoryInfo($TestDrive)
        { Assert-DATDismRuntimePath -Path $TestDrive } | Should -Not -Throw
    }
    It 'exports all runtime and mount helpers at module scope' {
        $topLevelNames = @($CoreAst.EndBlock.Statements |
            Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } |
            ForEach-Object { $_.Name })
        $exports = (Import-PowerShellDataFile -LiteralPath ([IO.Path]::ChangeExtension($CorePath, '.psd1'))).FunctionsToExport
        foreach ($name in @('New-DATDismRuntimeDirectory', 'New-DATDismBatchFile', 'Dismount-DATOwnedImages')) {
            $topLevelNames | Should -Contain $name
            $exports | Should -Contain $name
        }
    }
}

Describe 'Verified process termination' {
    BeforeEach {
        Mock Write-DATLogEntry {}
        Mock Get-DATRetainedProcessStartTicks { 100L }
        $process = [pscustomobject]@{ Id = 4200; HasExited = $false; WaitResult = $true }
        $process | Add-Member ScriptMethod Kill {}
        $process | Add-Member ScriptMethod WaitForExit {
            param($Milliseconds)
            if ($Milliseconds -ne 5000) { throw 'Unbounded wait' }
            $this.HasExited = $this.WaitResult
            return $this.WaitResult
        }
        $tree = @([pscustomobject]@{ ProcessId = 4200; Depth = 0; CreationTimeUtcTicks = 100L })
    }
    It 'confirms asynchronous termination before reporting a stopped root' {
        $result = Stop-DATCustomBuildProcessTree -ProcessTree $tree -RootProcess $process
        $result.RootStopped | Should -BeTrue
        $result.FailedCount | Should -Be 0
        $process.HasExited | Should -BeTrue
    }
    It 'reports incomplete cancellation when the bounded wait expires' {
        $process.WaitResult = $false
        $result = Stop-DATCustomBuildProcessTree -ProcessTree $tree -RootProcess $process
        $result.RootStopped | Should -BeFalse
        $result.StoppedCount | Should -Be 0
        $result.FailedCount | Should -Be 1
    }
}

Describe 'WIM cleanup retention' {
    BeforeEach {
        Mock Write-DATLogEntry {}
        Mock Test-DATSafeContentRoot { 'C:\DATTemp' }
        Mock Test-Path { $true }
        Mock Get-ChildItem { [pscustomobject]@{ PSPath = 'HKLM:\mock\mount' } }
        Mock Get-ItemProperty { [pscustomobject]@{ 'Mount Path' = 'C:\DATTemp\mount' } }
        Mock Dismount-WindowsImage {}
        Mock Remove-Item {}
    }
    It 'removes the mount record only after successful dismount' {
        Dismount-DATOwnedImages -StorageRoot 'C:\DATTemp' | Should -BeTrue
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly
        Should -Invoke Remove-Item -Times 1 -Exactly
    }
    It 'retains the record and blocks content deletion after dismount failure' {
        Mock Dismount-WindowsImage { throw 'Mount is still active' }
        Dismount-DATOwnedImages -StorageRoot 'C:\DATTemp' | Should -BeFalse
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
    It 'fails closed when registry enumeration cannot verify active mounts' {
        Mock Get-ChildItem { throw 'Registry denied' }
        Dismount-DATOwnedImages -StorageRoot 'C:\DATTemp' | Should -BeFalse
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
    It 'leaves other servicing roots untouched' {
        Mock Get-ItemProperty { [pscustomobject]@{ 'Mount Path' = 'C:\DATTemp-other\mount' } }
        Dismount-DATOwnedImages -StorageRoot 'C:\DATTemp' | Should -BeTrue
        Should -Invoke Dismount-WindowsImage -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'UI abort ownership' {
    BeforeEach {
        Mock Write-DATActivityLog {}
        Mock Get-ItemPropertyValue { 4200 }
    }
    It 'defers cancellation to the worker even with a published PID' {
        Invoke-DATCustomBuildAbortCleanup | Should -BeTrue
        Should -Invoke Get-ItemPropertyValue -Times 1 -Exactly
    }
    It 'keeps the worker alive when registry state is unreadable' {
        Mock Get-ItemPropertyValue { throw 'Registry denied' }
        Invoke-DATCustomBuildAbortCleanup | Should -BeTrue
    }
    It 'blocks another build while recovery state is retained' {
        Test-DATCustomBuildRecoveryPending | Should -BeTrue
        Mock Get-ItemPropertyValue { 0 }
        Test-DATCustomBuildRecoveryPending | Should -BeFalse
    }
    It 'does not interrupt the regular worker between process launch and ownership registration' {
        $handler = $UiAst.Find({
            param($item)
            $item -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
                $item.Expression.Extent.Text -eq '$btn_Abort' -and $item.Member.Value -eq 'Add_Click'
        }, $true)
        $handler | Should -Not -BeNullOrEmpty
        $handler.Extent.Text | Should -Not -Match 'BeginStop|Stop-Process|Get-Process'
    }
}

Describe 'Custom capture polling and recovery lifecycle' {
    BeforeEach {
        $Script:PollingProcess = [pscustomobject]@{ Id = 4200; HasExited = $false }
        $dismProcess = $Script:PollingProcess
        $dismLaunch = [pscustomobject]@{ Identity = [pscustomobject]@{ ProcessId = 4200 } }
        $dismBatchFile = 'C:\mock\capture.cmd'
        $dismStdoutFile = 'C:\mock\stdout.log'
        $WimFile = 'C:\mock\output.wim'
        $dismCompletedButHung = $false
        $customCancellationIncomplete = $false
        $lastProgressBytes = 0L
        $lastProgressAt = [datetime]'2026-10-10T00:00:00'
        $effectiveExitCode = 1
        Mock Write-DATLogEntry {}
        Mock Get-ItemPropertyValue { 0 }
        Mock Set-DATRegistryValue {}
        Mock Test-Path { $false }
        Mock Start-Sleep { throw 'Unexpected unbounded polling' }
        Mock Get-Date { [datetime]'2026-10-10T00:10:01' }
        Mock Stop-DATCustomDismProcess {
            $Script:PollingProcess.HasExited = $true
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; FailedCount = 0 }
        }
    }
    It 'handles a success marker inside the live polling loop' {
        Mock Test-Path { $true }
        Mock Get-Content { 'The operation completed successfully' }
        . ([scriptblock]::Create($PollingText))
        $dismCompletedButHung | Should -BeTrue
        $effectiveExitCode | Should -Be 0
        Should -Invoke Set-DATRegistryValue -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'CustomDismProcessID' -and $Value -eq 0
        }
    }
    It 'preserves recovery identity after a failed descendant even when the root exits' {
        Mock Get-ItemPropertyValue { 1 }
        Mock Stop-DATCustomDismProcess {
            $Script:PollingProcess.HasExited = $true
            [pscustomobject]@{ RootStopped = $true; RootExited = $false; FailedCount = 1 }
        }
        { . ([scriptblock]::Create($PollingText)) } | Should -Throw '*could not be verified as complete*'
        Should -Invoke Set-DATRegistryValue -Times 0 -Exactly
    }
    It 'fails a stalled capture instead of polling forever or claiming success' {
        { . ([scriptblock]::Create($PollingText)) } | Should -Throw '*ten minutes without output or WIM growth*'
        Should -Invoke Stop-DATCustomDismProcess -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
}

Describe 'Fail-closed executable batch creation' {
    BeforeEach {
        Mock Write-DATLogEntry {}
        Mock Assert-DATDismRuntimePath {}
    }
    It 'does not overwrite preexisting executable content' {
        $path = Join-Path $TestDrive 'capture.cmd'
        Set-Content -LiteralPath $path -Value 'sentinel' -Encoding ASCII
        { New-DATDismBatchFile -Path $path -Command 'mock-command' } | Should -Throw
        (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be 'sentinel'
    }
    It 'rejects an untrusted parent before creating any executable file' {
        $path = Join-Path $TestDrive 'denied.cmd'
        Mock Assert-DATDismRuntimePath { throw 'Untrusted ancestor' }
        { New-DATDismBatchFile -Path $path -Command 'mock-command' } | Should -Throw '*Untrusted ancestor*'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
    It 'writes the full wrapper into a new file' {
        $path = Join-Path $TestDrive 'new.cmd'
        New-DATDismBatchFile -Path $path -Command 'mock-command'
        Get-Content -LiteralPath $path -Raw | Should -Be "@echo off`r`nmock-command`r`nexit /b %ERRORLEVEL%`r`n"
    }
}
