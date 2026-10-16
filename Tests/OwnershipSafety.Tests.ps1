BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $corePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $coreAst = [Management.Automation.Language.Parser]::ParseFile($corePath, [ref]$null, [ref]$null)
    foreach ($name in @('Get-DATTakeownDefaultAnswer', 'New-DATOwnershipProcess',
            'Get-DATProtectedTakeownPath', 'Get-DATEffectiveFileSystemRights',
            'Invoke-DATOwnershipProcess', 'Invoke-DATTakeown', 'Test-DATSafeContentRoot')) {
        $node = $coreAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name
        }.GetNewClosure(), $true)
        if ($null -eq $node) { throw "Ownership function not found: $name" }
        . ([scriptblock]::Create($node.Extent.Text))
    }
    function Write-DATLogEntry { param($Value, $Severity) throw 'Unmocked logging' }
    function Set-Phase { param($Phase, $Percent, $Message, $Step) throw 'Unmocked UI write' }

    $englishHelp = @'
 /D prompt Default answer when access is denied recursively (/R).
           Valid values "Y" to take ownership or "N" to skip.
 /SKIPSL   Do not follow symbolic links.
'@
    $germanHelp = @'
 /D Antwort Standardantwort bei fehlendem Zugriff mit (/R).
            Werte "J" zur Besitzuebernahme oder "N" zum Ueberspringen.
 /SKIPSL    Symbolischen Links nicht folgen.
'@
    $uiPath = Join-Path $repoRoot 'Driver Automation Tool\UI\MainApplication.ps1'
    $uiAst = [Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$null, [ref]$null)
    $permissionNodes = @($coreAst.FindAll({
        param($item)
        $item -is [Management.Automation.Language.TryStatementAst] -and
            $item.Body.Extent.Text -match 'Invoke-DATTakeown -Path \$DriverFolder' -and
            $item.Body.Statements.Count -lt 10
    }, $true))
    $customPermissionNode = $uiAst.Find({
        param($item)
        $item -is [Management.Automation.Language.TryStatementAst] -and
            $item.Body.Extent.Text -match 'Invoke-DATTakeown -Path \$exportDir' -and
            $item.Body.Statements.Count -lt 10
    }, $true)
}

Describe 'Localized takeown help discovery' {
    It 'discovers the English ownership response from the installed format' {
        Get-DATTakeownDefaultAnswer -HelpText $englishHelp | Should -BeExactly 'Y'
    }
    It 'discovers the German response without a culture-to-language mapping' {
        Get-DATTakeownDefaultAnswer -HelpText $germanHelp | Should -BeExactly 'J'
    }
    It 'accepts another constrained response without guessing the OS language' {
        Get-DATTakeownDefaultAnswer -HelpText ($germanHelp.Replace('"J"', '"S"')) | Should -BeExactly 'S'
    }
    It 'ignores quoted letters in unrelated options' {
        Get-DATTakeownDefaultAnswer -HelpText (" /R Option `"Z`"`n" + $englishHelp) | Should -BeExactly 'Y'
    }
    It 'rejects unsupported or ambiguous help: <Name>' -ForEach @(
        @{ Name = 'missing section'; Help = 'No usable help' }
        @{ Name = 'duplicate choices'; Help = " /D prompt (/R) `"Y`" `"Y`"`n /R option" }
        @{ Name = 'extra choice'; Help = " /D prompt (/R) `"Y`" `"N`" `"X`"`n /R option" }
        @{ Name = 'no recursion marker'; Help = " /D prompt `"Y`" `"N`"`n /R option" }
        @{ Name = 'missing section end'; Help = ' /D prompt (/R) "Y" "N"' }
        @{ Name = 'injected token'; Help = " /D prompt (/R) `"Y & other.exe`" `"N`"`n /R option" }
        @{ Name = 'duplicate section'; Help = " /D prompt (/R) `"Y`" `"N`"`n /D prompt (/R) `"J`" `"N`"`n /R option" }
        @{ Name = 'oversized help'; Help = ('A' * 65537) }
    ) {
        { Get-DATTakeownDefaultAnswer -HelpText $Help } | Should -Throw
    }
}

Describe 'Trusted bounded ownership orchestration' {
    BeforeEach {
        Mock Get-Item {
            param($LiteralPath)
            [pscustomobject]@{
                PSIsContainer = $LiteralPath -notlike '*takeown.exe'
                Attributes = [IO.FileAttributes]::Normal
            }
        }
        $acl = [pscustomobject]@{ Rules = @() }
        $acl | Add-Member -MemberType ScriptMethod -Name GetOwner -Value {
            param($Type)
            [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        }
        $acl | Add-Member -MemberType ScriptMethod -Name GetAccessRules -Value {
            param($IncludeExplicit, $IncludeInherited, $TargetType)
            if ($TargetType -ne [Security.Principal.SecurityIdentifier]) { throw 'Account-name resolution is forbidden' }
            return $this.Rules
        }
        Mock Get-Acl { $acl }
        Mock Invoke-DATOwnershipProcess {
            param($Arguments)
            [pscustomobject]@{ ExitCode = 0; Output = $germanHelp }
        }
    }
    It 'uses the absolute protected OS executable and discovered answer with links skipped' {
        Invoke-DATTakeown -Path 'C:\DATContent\Drivers'
        $expectedTool = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'takeown.exe'
        Should -Invoke Get-Acl -Exactly 1 -ParameterFilter {
            $LiteralPath -eq [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
        }
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 1 -ParameterFilter {
            $FilePath -eq $expectedTool -and $Arguments -eq '/?' -and $TimeoutSeconds -eq 10 -and $CaptureOutput
        }
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 1 -ParameterFilter {
            $FilePath -eq $expectedTool -and $Arguments -eq '/F "C:\DATContent\Drivers" /R /A /SKIPSL /D J' -and $TimeoutSeconds -eq 900
        }
    }
    It 'does not attempt ownership after failed help' {
        Mock Invoke-DATOwnershipProcess { [pscustomobject]@{ ExitCode = 1; Output = $germanHelp } }
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*help failed*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 1
    }
    It 'normalizes trailing separators before quoting the native directory argument' {
        Invoke-DATTakeown -Path 'C:\DATContent\Drivers\'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 1 -ParameterFilter {
            $Arguments -eq '/F "C:\DATContent\Drivers" /R /A /SKIPSL /D J'
        }
    }
    It 'does not launch any process for WhatIf' {
        Invoke-DATTakeown -Path 'C:\DATContent\Drivers' -WhatIf
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'does not attempt ownership after ambiguous help' {
        Mock Invoke-DATOwnershipProcess { [pscustomobject]@{ ExitCode = 0; Output = 'Unknown help format' } }
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 1
    }
    It 'propagates a failed ownership result' {
        Mock Invoke-DATOwnershipProcess { [pscustomobject]@{ ExitCode = 5; Output = '' } } -ParameterFilter { $Arguments -ne '/?' }
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*exit code 5*'
    }
    It 'refuses an OS executable writable by a non-administrator' {
        $acl.Rules = @([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),
            [Security.AccessControl.FileSystemRights]::WriteData,
            [Security.AccessControl.AccessControlType]::Allow))
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*not protected*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'refuses an untrusted system directory before executing help' {
        Mock Get-Acl { throw 'Untrusted system directory' } -ParameterFilter {
            $LiteralPath -eq [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
        }
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*Untrusted system*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'refuses an untrusted executable owner without resolving account names' {
        $acl | Add-Member -MemberType ScriptMethod -Name GetOwner -Value {
            param($Type)
            [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
        } -Force
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*untrusted owner*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'refuses unsafe content paths: <Path>' -ForEach @(
        @{ Path = 'C:\' }
        @{ Path = 'relative\Drivers' }
        @{ Path = '\\server\share\Drivers' }
        @{ Path = 'C:\DATContent\evil" /F C:\' }
        @{ Path = 'C:\DATContent\*' }
    ) {
        { Invoke-DATTakeown -Path $Path } | Should -Throw
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'refuses ownership of Windows descendants' {
        $path = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'System32\Drivers'
        { Invoke-DATTakeown -Path $path } | Should -Throw '*Windows directory*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
    It 'refuses reparse-point content ancestry' {
        Mock Get-Item { [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::ReparsePoint } }
        { Invoke-DATTakeown -Path 'C:\DATContent\Drivers' } | Should -Throw '*reparse-point*'
        Should -Invoke Invoke-DATOwnershipProcess -Exactly 0
    }
}

Describe 'Noninteractive ownership process lifecycle' {
    BeforeEach {
        $inputPipe = [pscustomobject]@{ Closed = $false }
        $inputPipe | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed = $true }
        $stdoutPipe = [pscustomobject]@{ Text = $englishHelp; BaseStream = [IO.MemoryStream]::new() }
        $stderrPipe = [pscustomobject]@{ Text = ''; BaseStream = [IO.MemoryStream]::new() }
        foreach ($pipe in @($stdoutPipe, $stderrPipe)) {
            $pipe | Add-Member -MemberType ScriptMethod -Name ReadToEndAsync -Value {
                $completion = [Threading.Tasks.TaskCompletionSource[string]]::new()
                $completion.SetResult($this.Text)
                return $completion.Task
            }
        }
        $fakeProcess = [pscustomobject]@{
            StartInfo = $null; StandardInput = $inputPipe; StandardOutput = $stdoutPipe
            StandardError = $stderrPipe; ExitCode = 0; HasExited = $false
            Started = $false; Killed = $false; Disposed = $false; TimesOut = $false
            Waits = [Collections.Generic.List[int]]::new(); Id = 123
        }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Start -Value { $this.Started = $true; return $true }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param($Milliseconds)
            $this.Waits.Add($Milliseconds)
            if ($this.TimesOut -and -not $this.Killed) { return $false }
            $this.HasExited = $true
            return $true
        }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true; $this.HasExited = $true }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
        Mock New-DATOwnershipProcess { $fakeProcess }
        Mock Write-DATLogEntry {}
    }
    AfterEach {
        $stdoutPipe.BaseStream.Dispose()
        $stderrPipe.BaseStream.Dispose()
    }
    It 'closes input, redirects and drains both streams, disables shell use and disposes its handle' {
        $result = Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -TimeoutSeconds 10 -CaptureOutput
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '/D prompt'
        $fakeProcess.StandardInput.Closed | Should -BeTrue
        $fakeProcess.StartInfo.UseShellExecute | Should -BeFalse
        $fakeProcess.StartInfo.RedirectStandardInput | Should -BeTrue
        $fakeProcess.StartInfo.RedirectStandardOutput | Should -BeTrue
        $fakeProcess.StartInfo.RedirectStandardError | Should -BeTrue
        $fakeProcess.Waits | Should -Contain 10000
        $fakeProcess.Killed | Should -BeFalse
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'discards ownership output rather than buffering a line per file' {
        $stdoutPipe.BaseStream.WriteByte(1)
        $stdoutPipe.BaseStream.Position = 0
        $stderrPipe.BaseStream.WriteByte(2)
        $stderrPipe.BaseStream.Position = 0
        $result = Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/F "C:\DATContent\Drivers" /R /D Y'
        $result.Output | Should -BeExactly ''
        $stdoutPipe.BaseStream.Position | Should -Be 1
        $stderrPipe.BaseStream.Position | Should -Be 1
        $fakeProcess.Waits | Should -Contain 900000
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'kills only its retained process on timeout and confirms termination with a bounded wait' {
        $fakeProcess.TimesOut = $true
        { Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -TimeoutSeconds 10 -CaptureOutput } | Should -Throw '*timed out*'
        $fakeProcess.Killed | Should -BeTrue
        $fakeProcess.Waits | Should -Contain 5000
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'cleans up a process whose stdin could not be closed' {
        $inputPipe | Add-Member -MemberType ScriptMethod -Name Close -Value { throw 'Broken stdin' } -Force
        { Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -CaptureOutput } | Should -Throw '*Broken stdin*'
        $fakeProcess.Killed | Should -BeTrue
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'disposes a process that could not start without attempting termination' {
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Start -Value { return $false } -Force
        { Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -CaptureOutput } | Should -Throw '*Could not start*'
        $fakeProcess.Killed | Should -BeFalse
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'preserves a native nonzero exit code for fail-closed orchestration' {
        $fakeProcess.ExitCode = 5
        (Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -CaptureOutput).ExitCode | Should -Be 5
        $fakeProcess.Disposed | Should -BeTrue
    }
    It 'disposes its handle even when termination and diagnostic logging both fail' {
        $fakeProcess.TimesOut = $true
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Kill -Value { throw 'Access denied' } -Force
        Mock Write-DATLogEntry { throw 'Logger unavailable' }
        { Invoke-DATOwnershipProcess -FilePath 'C:\Windows\System32\takeown.exe' -Arguments '/?' -TimeoutSeconds 10 -CaptureOutput } | Should -Throw
        $fakeProcess.Disposed | Should -BeTrue
    }
}

Describe 'Ownership caller failure propagation' {
    BeforeEach {
        Mock Invoke-DATTakeown { throw 'Unsupported ownership help' }
        Mock Write-DATLogEntry {}
        Mock Set-Phase {}
        Mock Start-Process { throw 'Must not launch a capture or ACL command' }
        $DriverFolder = 'C:\DATContent\Drivers'
        $exportDir = $DriverFolder
        $OEM = 'Dell'
        $Version = '1'
        $driverCount = 1
    }
    It 'stops both regular and retry ownership paths when discovery fails' {
        $permissionNodes | Should -HaveCount 2
        foreach ($node in $permissionNodes) {
            $operation = [scriptblock]::Create($node.Extent.Text)
            { & $operation } | Should -Throw '*Unsupported ownership help*'
        }
        Should -Invoke Start-Process -Exactly 0
    }
    It 'returns a custom-capture failure before starting capture when discovery fails' {
        $customPermissionNode | Should -Not -BeNullOrEmpty
        $operation = [scriptblock]::Create($customPermissionNode.Extent.Text)
        $result = & $operation
        $result.Success | Should -BeFalse
        $result.PackagePath | Should -BeExactly ''
        Should -Invoke Start-Process -Exactly 0
    }
    It 'exports the shared helper for background UI runspaces' {
        $manifestPath = Join-Path (Split-Path -Parent $corePath) 'DriverAutomationToolCore.psd1'
        (Import-PowerShellDataFile -LiteralPath $manifestPath).FunctionsToExport | Should -Contain 'Invoke-DATTakeown'
    }
    It 'has no active shell takeown command or hardcoded affirmative response' {
        $coreAst.Extent.Text | Should -Not -Match '(?i)-FilePath\s+"(?:[^"]*\\)?takeown\.exe"'
        $uiAst.Extent.Text | Should -Not -Match '(?i)-FilePath\s+"takeown\.exe"'
        $coreAst.Extent.Text | Should -Not -Match '/D Y'
        $uiAst.Extent.Text | Should -Not -Match '/D Y'
    }
}

Describe 'Generated Dell firmware result safety' {
    BeforeAll {
        $templatePath = Join-Path (Split-Path -Parent $corePath) 'Templates\Install-BIOS.ps1'
        $template = (Get-Content -LiteralPath $templatePath -Raw) -replace '\{\{[A-Z0-9_]+\}\}', ''
        $ast = [Management.Automation.Language.Parser]::ParseInput($template, [ref]$null, [ref]$null)
        $resultNode = $ast.Find({
            param($item)
            $item -is [Management.Automation.Language.IfStatementAst] -and
                $item.Clauses[0].Item1.Extent.Text -eq '$flashExitCode -in @(0, 2, 6)' -and
                $item.Extent.Text -like '*Dell BIOS update completed successfully*'
        }, $true)
        if ($null -eq $resultNode) { throw 'Generated Dell result classification not found' }
        $classifyDellResult = [scriptblock]::Create($resultNode.Extent.Text)
        function Write-CMTraceLog { param($Message, $Severity) throw 'Unmocked firmware logger' }
    }
    BeforeEach {
        Mock Write-CMTraceLog {}
    }
    It 'preserves established success code <Code>' -ForEach @(
        @{ Code = 0 }; @{ Code = 2 }; @{ Code = 6 }
    ) {
        $flashExitCode = $Code
        { & $classifyDellResult } | Should -Not -Throw
    }
    It 'fails closed for error code <Code> rather than reporting completion or an AC-only retry' -ForEach @(
        @{ Code = 1 }; @{ Code = 10 }; @{ Code = 42 }
    ) {
        $flashExitCode = $Code
        { & $classifyDellResult } | Should -Throw "*failed with exit code: $Code"
    }
}
