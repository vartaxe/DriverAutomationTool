$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$headlessPath = Join-Path $repoRoot 'Driver Automation Tool\Start-DATHeadlessBuild.ps1'
$uiPath = Join-Path $repoRoot 'Driver Automation Tool\UI\MainApplication.ps1'
$coreModulePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
$corePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1'
$driverPath = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMApplyDriverPackage.ps1'
$biosPath = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Invoke-CMDownloadBIOSPackage.ps1'

function Assert-DAT {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

foreach ($path in @($headlessPath, $uiPath, $coreModulePath, $driverPath, $biosPath)) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-DAT ($errors.Count -eq 0) "$(Split-Path $path -Leaf) parses"

    if ($path -in @($headlessPath, $uiPath, $coreModulePath)) {
        $unsafeDismLookups = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Get-Process' -and
            $node.Extent.Text -match '(?i)-Name\s+(?:[''"]?(?:dism|dismhost)(?:\.exe)?[''"]?|\$procName)'
        }, $true))
        Assert-DAT ($unsafeDismLookups.Count -eq 0) "$(Split-Path $path -Leaf) has no machine-wide DISM process-name lookup/cleanup"

        $dynamicDismNames = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
            $node.Extent.Text -match '(?is)\$procName\s+in\s*@\(\s*[''"]dismhost[''"]\s*,\s*[''"]dism[''"]'
        }, $true))
        Assert-DAT ($dynamicDismNames.Count -eq 0) "$(Split-Path $path -Leaf) has no dynamic DISM process-name cleanup"

        $globalMountCleanup = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $node.Value -eq '/Cleanup-Wim'
        }, $true))
        Assert-DAT ($globalMountCleanup.Count -eq 0) "$(Split-Path $path -Leaf) does not invoke global DISM /Cleanup-Wim"

        $globalMountRegistryDeletes = @($ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.PipelineAst] -and
                $node.Extent.Text -match '(?is)Get-ChildItem\s+\$dismMountKey[^|]*\|\s*Remove-Item') -or
            ($node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Remove-Item' -and $node.Extent.Text -match '\$entry\.PSPath')
        }, $true))
        Assert-DAT ($globalMountRegistryDeletes.Count -eq 0) "$(Split-Path $path -Leaf) does not delete global DISM mount entries"
    }
}

function Import-DATTestFunction {
    param([string]$Path, [string[]]$Name)
    $fileTokens = $null
    $fileErrors = $null
    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$fileTokens, [ref]$fileErrors)
    foreach ($functionName in $Name) {
        $definition = $fileAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true) | Select-Object -First 1
        if ($null -eq $definition) { throw "FAIL: $functionName not found in $(Split-Path $Path -Leaf)" }
        $definition.Extent.Text
    }
}

# Offline mocks: no real process, CIM, registry or DISM operation is performed by these tests.
$script:Logs = [Collections.Generic.List[string]]::new()
$script:RegWrites = [Collections.Generic.List[string]]::new()
$script:RegValues = @{}
$script:CimMode = 'Snapshot'
$script:CimSnapshot = @()
$script:FakeProcesses = @{}
$script:GetProcessCalls = [Collections.Generic.List[int]]::new()
$script:StartProcessCalls = 0
$global:DATTestKills = [Collections.Generic.List[int]]::new()
function Write-DATLogEntry { param($Value, $Severity) $script:Logs.Add("$Severity|$Value") }
function Write-DATActivityLog { param($Message, $Level) $script:Logs.Add("$Level|$Message") }
function Set-DATRegistryValue { param($Name, $Value, $Type) $script:RegWrites.Add("$Name=$Value"); $script:RegValues[$Name] = $Value }
function Get-ItemPropertyValue {
    [CmdletBinding()] param($Path, $Name)
    if ($script:RegValues.ContainsKey('__Throw')) { throw [System.UnauthorizedAccessException]::new('Registry access denied') }
    if (-not $script:RegValues.ContainsKey($Name)) { throw [System.Management.Automation.PSArgumentException]::new("Property $Name does not exist") }
    $script:RegValues[$Name]
}
function Get-CimInstance {
    [CmdletBinding()] param($ClassName, $Filter)
    if ($script:CimMode -eq 'Fail') { throw [System.Runtime.InteropServices.COMException]::new('WMI provider failure') }
    if ($Filter -match 'ProcessId = (\d+)') {
        $id = [int]$Matches[1]
        return $script:CimSnapshot | Where-Object { $_.ProcessId -eq $id }
    }
    $script:CimSnapshot
}
function Get-Process {
    [CmdletBinding()] param($Id)
    $script:GetProcessCalls.Add([int]$Id)
    if (-not $script:FakeProcesses.ContainsKey([int]$Id)) {
        throw [Microsoft.PowerShell.Commands.ProcessCommandException]::new("Cannot find a process with the process identifier $Id.")
    }
    $script:FakeProcesses[[int]$Id]
}
function Start-Process {
    [CmdletBinding()] param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru)
    $script:StartProcessCalls++
    $script:FakeRoot
}
function New-DATFakeProcess {
    param([int]$Id, [datetime]$StartUtc, [switch]$HandleFails)
    $fake = [pscustomobject]@{ Id = $Id; StartTime = $StartUtc; HasExited = $false }
    if ($HandleFails) {
        $fake | Add-Member -MemberType ScriptProperty -Name Handle -Value { throw [System.ComponentModel.Win32Exception]::new(5) }
    } else {
        $fake | Add-Member -MemberType NoteProperty -Name Handle -Value ([IntPtr]1)
    }
    $fake | Add-Member -MemberType ScriptMethod -Name Kill -Value { $global:DATTestKills.Add([int]$this.Id); $this.HasExited = $true }
    $fake
}
function Reset-DATTestState {
    $script:Logs.Clear(); $script:RegWrites.Clear(); $script:RegValues = @{}; $script:CimMode = 'Snapshot'
    $script:FakeProcesses = @{}; $script:GetProcessCalls.Clear(); $script:StartProcessCalls = 0; $global:DATTestKills.Clear()
}

foreach ($definition in (Import-DATTestFunction -Path $coreModulePath -Name @(
    'ConvertTo-DATProcessIdentity', 'Get-DATCustomBuildProcessTree', 'Stop-DATCustomBuildProcessTree',
    'Get-DATRetainedProcessStartTicks', 'Resolve-DATCustomDismIdentity', 'Start-DATCustomDismProcess', 'Stop-DATCustomDismProcess'))) {
    . ([scriptblock]::Create($definition))
}
Assert-DAT ($null -ne (Get-Command Get-DATCustomBuildProcessTree -CommandType Function)) 'custom-build process ownership helpers are available for offline regression checks'
$exportedOwnershipFunctions = (Import-PowerShellDataFile -LiteralPath $corePath).FunctionsToExport
Assert-DAT (@('Get-DATCustomBuildProcessTree', 'Stop-DATCustomBuildProcessTree', 'Start-DATCustomDismProcess', 'Stop-DATCustomDismProcess' | Where-Object { $exportedOwnershipFunctions -notcontains $_ }).Count -eq 0) 'ownership helpers are exported for the UI and build runspace'

$rootCreated = [datetime]::SpecifyKind([datetime]'2026-01-01T00:00:00', [DateTimeKind]::Utc)
$processSnapshot = @(
    [pscustomobject]@{ ProcessId=500; ParentProcessId=100; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated); ExecutablePath='C:\Windows\System32\cmd.exe'; CommandLine='cmd.exe /c "C:\DAT\capture.cmd"'; Name='cmd.exe' },
    [pscustomobject]@{ ProcessId=501; ParentProcessId=500; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated.AddSeconds(1)); ExecutablePath='C:\Windows\System32\dism.exe'; CommandLine='dism.exe /Capture-Image'; Name='dism.exe' },
    [pscustomobject]@{ ProcessId=502; ParentProcessId=501; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated.AddSeconds(2)); ExecutablePath='C:\Windows\System32\dismhost.exe'; CommandLine='dismhost.exe'; Name='dismhost.exe' },
    [pscustomobject]@{ ProcessId=503; ParentProcessId=500; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated.AddSeconds(-1)); ExecutablePath='C:\Windows\System32\unrelated.exe'; CommandLine='unrelated.exe'; Name='unrelated.exe' },
    [pscustomobject]@{ ProcessId=601; ParentProcessId=999; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated.AddSeconds(1)); ExecutablePath='C:\Windows\System32\dism.exe'; CommandLine='other dism.exe'; Name='dism.exe' }
)
$ownedProcesses = @(Get-DATCustomBuildProcessTree -RootProcessId 500 -RootCreationTimeUtcTicks $rootCreated.Ticks `
    -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine 'cmd.exe /c "C:\DAT\capture.cmd"' `
    -ProcessSnapshot $processSnapshot)
Assert-DAT ((@($ownedProcesses.ProcessId) -join ',') -eq '500,501,502') 'process-tree ownership includes only current descendants with valid creation ordering'

$staleSnapshot = @($processSnapshot | ForEach-Object {
    if ($_.ProcessId -eq 500) {
        [pscustomobject]@{ ProcessId=$_.ProcessId; ParentProcessId=$_.ParentProcessId; CreationDate=[System.Management.ManagementDateTimeConverter]::ToDmtfDateTime($rootCreated.AddDays(1)); ExecutablePath=$_.ExecutablePath; CommandLine=$_.CommandLine; Name=$_.Name }
    } else { $_ }
})
$staleProcesses = @(Get-DATCustomBuildProcessTree -RootProcessId 500 -RootCreationTimeUtcTicks $rootCreated.Ticks `
    -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine 'cmd.exe /c "C:\DAT\capture.cmd"' `
    -ProcessSnapshot $staleSnapshot)
Assert-DAT ($staleProcesses.Count -eq 0) 'stale PID with a different creation time cannot claim unrelated descendants'

$reusedPidSnapshot = @($processSnapshot | ForEach-Object {
    if ($_.ProcessId -eq 500) {
        [pscustomobject]@{ ProcessId=$_.ProcessId; ParentProcessId=$_.ParentProcessId; CreationDate=$_.CreationDate; ExecutablePath='C:\Windows\System32\unrelated.exe'; CommandLine='unrelated.exe'; Name='unrelated.exe' }
    } else { $_ }
})
$reusedPidProcesses = @(Get-DATCustomBuildProcessTree -RootProcessId 500 -RootCreationTimeUtcTicks $rootCreated.Ticks `
    -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine 'cmd.exe /c "C:\DAT\capture.cmd"' `
    -ProcessSnapshot $reusedPidSnapshot)
Assert-DAT ($reusedPidProcesses.Count -eq 0) 'reused PID with a different executable and command line is rejected'

$uiText = Get-Content -LiteralPath $uiPath -Raw
Assert-DAT ($uiText -match "(?s)AddArgument\(\`$additionalDriversPath\)\s+Set-DATRegistryValue -Name 'CustomBuildAbortRequested' -Value 0.*?Set-DATRegistryValue -Name 'CustomDismProcessID' -Value 0.*?\`$script:CustomBuildAsyncResult = .*BeginInvoke") 'new custom builds reset process identity before the runspace can abort'
$uiAst = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors)
Assert-DAT (@($uiAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '(?i)taskkill'
}, $true)).Count -eq 0) 'custom-build cancellation has no PID-only taskkill tree path'

$rootStartUtc = [datetime]::SpecifyKind([datetime]'2026-02-01T10:00:00', [DateTimeKind]::Utc)
$batchFile = 'C:\DATTemp\DAT_DISM_custom_capture.cmd'
$rootCommandLine = "cmd.exe /c `"$batchFile`""
$launchSnapshot = @(
    [pscustomobject]@{ ProcessId=700; ParentProcessId=10; CreationDate=$rootStartUtc.ToLocalTime(); ExecutablePath='C:\Windows\System32\cmd.exe'; CommandLine=$rootCommandLine; Name='cmd.exe' },
    [pscustomobject]@{ ProcessId=701; ParentProcessId=700; CreationDate=$rootStartUtc.AddSeconds(1).ToLocalTime(); ExecutablePath='C:\Windows\System32\dism.exe'; CommandLine='dism.exe /Capture-Image'; Name='dism.exe' },
    [pscustomobject]@{ ProcessId=702; ParentProcessId=701; CreationDate=$rootStartUtc.AddSeconds(2).ToLocalTime(); ExecutablePath='C:\Windows\System32\dismhost.exe'; CommandLine='dismhost.exe'; Name='dismhost.exe' },
    [pscustomobject]@{ ProcessId=703; ParentProcessId=700; CreationDate=$rootStartUtc.AddMinutes(-5).ToLocalTime(); ExecutablePath='C:\Windows\System32\unrelated.exe'; CommandLine='unrelated.exe'; Name='unrelated.exe' },
    [pscustomobject]@{ ProcessId=704; ParentProcessId=700; CreationDate=$null; ExecutablePath=''; CommandLine=''; Name='protected.exe' }
)

# Identity retrieval failures fail closed and are surfaced.
Reset-DATTestState
$script:CimMode = 'Fail'
$snapshotFailed = $false
try { $null = Get-DATCustomBuildProcessTree -RootProcessId 700 -RootCreationTimeUtcTicks $rootStartUtc.Ticks -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine $rootCommandLine } catch { $snapshotFailed = $true }
Assert-DAT $snapshotFailed 'process snapshot failure is raised instead of silently returning no processes'

Reset-DATTestState
$script:CimSnapshot = @($launchSnapshot | ForEach-Object { if ($_.ProcessId -eq 700) { [pscustomobject]@{ ProcessId=700; ParentProcessId=10; CreationDate=$null; ExecutablePath=$_.ExecutablePath; CommandLine=$_.CommandLine; Name='cmd.exe' } } else { $_ } })
$rootUnreadable = $false
try { $null = Get-DATCustomBuildProcessTree -RootProcessId 700 -RootCreationTimeUtcTicks $rootStartUtc.Ticks -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine $rootCommandLine } catch { $rootUnreadable = $_.Exception.Message -notmatch [regex]::Escape($batchFile) }
Assert-DAT $rootUnreadable 'unreadable tracked root identity fails closed without exposing its command line'

Reset-DATTestState
$script:CimSnapshot = $launchSnapshot
$launchTree = @(Get-DATCustomBuildProcessTree -RootProcessId 700 -RootCreationTimeUtcTicks $rootStartUtc.Ticks -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine $rootCommandLine)
Assert-DAT ((@($launchTree.ProcessId) -join ',') -eq '700,701,702') 'unverifiable and pre-existing children are excluded from the owned tree'
Assert-DAT ($launchTree[0].UnverifiedDescendantCount -eq 1) 'unreadable descendant is carried as incomplete enumeration without claiming its PID'
Assert-DAT (@($script:Logs | Where-Object { $_ -match '^2\|.*PID 704 .*will not be stopped' }).Count -eq 1) 'unverifiable owned-child candidate is reported as a warning'

Reset-DATTestState
$script:CimSnapshot = @($launchSnapshot | Where-Object { $_.ProcessId -ne 700 })
$exitedTree = @(Get-DATCustomBuildProcessTree -RootProcessId 700 -RootCreationTimeUtcTicks $rootStartUtc.Ticks -RootExecutablePath 'C:\Windows\System32\cmd.exe' -RootCommandLine $rootCommandLine)
Assert-DAT ($exitedTree.Count -eq 0 -and @($script:Logs | Where-Object { $_ -match '^1\|.*PID 700 has already exited' }).Count -eq 1) 'already-exited tracked root is reported as benign and nothing is stopped'

# Stop verifies each target through a pinned handle and never addresses a stale PID.
Reset-DATTestState
$fakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc
$script:FakeProcesses[701] = New-DATFakeProcess -Id 701 -StartUtc $rootStartUtc.AddSeconds(1)
$script:FakeProcesses[702] = New-DATFakeProcess -Id 702 -StartUtc $rootStartUtc.AddSeconds(2)
$stopResult = Stop-DATCustomBuildProcessTree -ProcessTree $launchTree -RootProcess $fakeRoot
Assert-DAT ((@($global:DATTestKills) -join ',') -eq '702,701,700' -and $stopResult.RootStopped -and $stopResult.FailedCount -eq 1) 'owned tree is stopped deepest-first but unreadable descendants keep cancellation incomplete'
Assert-DAT ($script:GetProcessCalls -notcontains 704) 'unreadable descendant is not looked up or stopped by PID'
Assert-DAT ($script:GetProcessCalls -notcontains 700) 'root process is stopped through its retained handle rather than a PID lookup'

Reset-DATTestState
$script:FakeProcesses[701] = New-DATFakeProcess -Id 701 -StartUtc $rootStartUtc.AddHours(3)
$script:FakeProcesses[702] = New-DATFakeProcess -Id 702 -StartUtc $rootStartUtc.AddSeconds(2) -HandleFails
$stopResult = Stop-DATCustomBuildProcessTree -ProcessTree @($launchTree | Where-Object { $_.Depth -gt 0 })
Assert-DAT ($global:DATTestKills.Count -eq 0 -and $stopResult.FailedCount -eq 2) 'reused descendant PID and unverifiable handle are not stopped'
Assert-DAT (@($script:Logs | Where-Object { $_ -match '^2\|' }).Count -eq 2) 'descendant verification failures are surfaced as warnings'

Reset-DATTestState
$stopResult = Stop-DATCustomBuildProcessTree -ProcessTree @($launchTree | Where-Object { $_.Depth -gt 0 })
Assert-DAT ($stopResult.FailedCount -eq 0 -and @($script:Logs | Where-Object { $_ -match '^1\|.*already exited' }).Count -eq 2) 'already-exited descendants are benign, not failures'

# Launch lifecycle: pre-launch abort, identity failure and verified launch.
Reset-DATTestState
$script:RegValues['CustomBuildAbortRequested'] = 1
$preLaunchAborted = $false
try { $null = Start-DATCustomDismProcess -BatchFile $batchFile } catch { $preLaunchAborted = $_.Exception.Message -match 'before DISM started' }
Assert-DAT ($preLaunchAborted -and $script:StartProcessCalls -eq 0 -and $script:RegValues['CustomDismProcessID'] -eq 0) 'abort before launch throws without starting DISM and clears the no-process sentinel'

Reset-DATTestState
$script:RegValues['CustomBuildAbortRequested'] = 0
$script:FakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc
$script:CimMode = 'Fail'
$launch = Start-DATCustomDismProcess -BatchFile $batchFile
Assert-DAT ($null -eq $launch.Identity -and $script:RegValues['CustomDismProcessID'] -eq -1 -and -not ($script:RegWrites -match '^CustomDismProcessID=700$')) 'launch identity retrieval failure keeps the PID unpublished'
Assert-DAT (@($script:Logs | Where-Object { $_ -match '^2\|.*Unable to record the identity of wrapper process PID 700' -and $_ -notmatch [regex]::Escape($rootCommandLine) }).Count -eq 1) 'launch identity retrieval failure is logged without the command line'

$script:Logs.Clear()
$stopped = Stop-DATCustomDismProcess -Process $script:FakeRoot -Identity $launch.Identity -BatchFile $batchFile
Assert-DAT ($global:DATTestKills.Count -eq 0 -and $null -eq $stopped -and @($script:Logs | Where-Object { $_ -match '^2\|.*Unable to verify wrapper process PID 700.*No process was stopped' }).Count -eq 1) 'runspace cancellation with missing identity fails closed instead of killing by PID'

$script:CimMode = 'Snapshot'
$script:CimSnapshot = $launchSnapshot
$script:FakeProcesses[701] = New-DATFakeProcess -Id 701 -StartUtc $rootStartUtc.AddSeconds(1)
$script:FakeProcesses[702] = New-DATFakeProcess -Id 702 -StartUtc $rootStartUtc.AddSeconds(2)
$stopped = Stop-DATCustomDismProcess -Process $script:FakeRoot -Identity $null -BatchFile $batchFile
Assert-DAT ((@($global:DATTestKills) -join ',') -eq '702,701,700' -and $stopped.RootStopped) 'deferred runspace cancellation re-verifies identity then stops only the owned tree'

Reset-DATTestState
$script:RegValues['CustomBuildAbortRequested'] = 0
$script:FakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc
$script:CimSnapshot = $launchSnapshot
$launch = Start-DATCustomDismProcess -BatchFile $batchFile
$pidWriteIndex = $script:RegWrites.IndexOf('CustomDismProcessID=700')
Assert-DAT ($launch.Identity.ProcessId -eq 700 -and $pidWriteIndex -gt $script:RegWrites.IndexOf("CustomDismProcessCommandLine=$rootCommandLine") -and $pidWriteIndex -gt $script:RegWrites.IndexOf("CustomDismProcessCreationTime=$($rootStartUtc.Ticks)")) 'verified launch identity is recorded before its PID becomes abortable'

Reset-DATTestState
$script:RegValues['CustomBuildAbortRequested'] = 0
$script:FakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc
$script:CimSnapshot = @([pscustomobject]@{ ProcessId=700; ParentProcessId=10; CreationDate=$rootStartUtc.ToLocalTime(); ExecutablePath='C:\Windows\System32\unrelated.exe'; CommandLine='unrelated.exe'; Name='unrelated.exe' })
$mismatchRejected = $false
try { $null = Start-DATCustomDismProcess -BatchFile $batchFile } catch { $mismatchRejected = $_.Exception.Message -match 'does not match the expected identity' }
Assert-DAT ($mismatchRejected -and $script:RegValues['CustomDismProcessID'] -eq -1) 'launched process with an unexpected identity is never published or tracked'

# Windows PowerShell returns $null for failing property getters; an unopenable handle must still fail closed.
Reset-DATTestState
$script:RegValues['CustomBuildAbortRequested'] = 0
$script:FakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc -HandleFails
$script:CimSnapshot = $launchSnapshot
$launch = Start-DATCustomDismProcess -BatchFile $batchFile
Assert-DAT ($null -eq $launch.Identity -and $script:RegValues['CustomDismProcessID'] -eq -1 -and @($script:Logs | Where-Object { $_ -match '^2\|.*Unable to record the identity of wrapper process PID 700 -- Unable to open a handle' }).Count -eq 1) 'unopenable launch handle leaves the PID unpublished with a warning'

Reset-DATTestState
$script:RegValues['__Throw'] = $true
$script:FakeRoot = New-DATFakeProcess -Id 700 -StartUtc $rootStartUtc
$script:CimSnapshot = $launchSnapshot
$launch = Start-DATCustomDismProcess -BatchFile $batchFile
Assert-DAT ($script:StartProcessCalls -eq 1 -and $launch.Identity.ProcessId -eq 700 -and @($script:Logs | Where-Object { $_ -match '^2\|.*Unable to read the custom build abort flag before launch' }).Count -eq 1) 'unreadable pre-launch abort flag is surfaced and re-checked while DISM runs'

# UI abort lifecycle with mocked core/ownership calls.
foreach ($definition in (Import-DATTestFunction -Path $uiPath -Name @('Invoke-DATCustomBuildAbortCleanup', 'Complete-DATCustomBuildAbort'))) {
    . ([scriptblock]::Create($definition))
}
$script:TreeCalls = 0
$script:StopCalls = 0
$script:TreeMode = 'Owned'
function Get-DATCustomBuildProcessTree {
    param($RootProcessId, $RootCreationTimeUtcTicks, $RootExecutablePath, $RootCommandLine)
    $script:TreeCalls++
    if ($script:TreeMode -eq 'Fail') { throw 'Unable to verify the identity of tracked process PID 700 -- WMI provider failure' }
    if ($script:TreeMode -eq 'Empty') { return }
    [pscustomobject]@{ ProcessId = $RootProcessId; Depth = 0; CreationTimeUtcTicks = $RootCreationTimeUtcTicks }
}
function Stop-DATCustomBuildProcessTree {
    param($ProcessTree, $RootProcess)
    $script:StopCalls++
    [pscustomobject]@{ RootStopped = $true; RootExited = $false; StoppedCount = 1; FailedCount = 0 }
}
function New-DATFakeRunspaceState {
    $global:DATTestLifecycle = [Collections.Generic.List[string]]::new()
    $script:CustomBuildTimer = [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Stop -Value { $global:DATTestLifecycle.Add('timer-stop') } -PassThru
    $script:CustomBuildPS = [pscustomobject]@{} |
        Add-Member -MemberType ScriptMethod -Name Stop -Value { $global:DATTestLifecycle.Add('ps-stop') } -PassThru |
        Add-Member -MemberType ScriptMethod -Name Dispose -Value { $global:DATTestLifecycle.Add('ps-dispose') } -PassThru
    $script:CustomBuildRunspace = [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $global:DATTestLifecycle.Add('runspace-dispose') } -PassThru
    $script:CustomBuildAsyncResult = 'pending'
}
function Reset-DATAbortState { Reset-DATTestState; $script:TreeCalls = 0; $script:StopCalls = 0; $script:TreeMode = 'Owned'; New-DATFakeRunspaceState }

Reset-DATAbortState
$script:RegValues['CustomDismProcessID'] = -1
$deferred = Invoke-DATCustomBuildAbortCleanup
Complete-DATCustomBuildAbort -DeferStop $deferred
Assert-DAT ($deferred -and $script:TreeCalls -eq 0 -and $script:StopCalls -eq 0) 'abort during pending launch defers to the runspace without enumerating or stopping processes'
Assert-DAT ($global:DATTestLifecycle.Count -eq 0 -and $null -ne $script:CustomBuildPS -and $script:CustomBuildAsyncResult -eq 'pending') 'deferred abort keeps the build runspace and timer alive to finish cancellation'

Reset-DATAbortState
$script:RegValues['CustomDismProcessID'] = 700
$script:RegValues['CustomDismProcessCreationTime'] = [string]$rootStartUtc.Ticks
$script:RegValues['CustomDismProcessExecutable'] = 'C:\Windows\System32\cmd.exe'
$script:RegValues['CustomDismProcessCommandLine'] = $rootCommandLine
$script:TreeMode = 'Fail'
$deferred = Invoke-DATCustomBuildAbortCleanup
Assert-DAT ($deferred -and $script:TreeCalls -eq 0 -and $script:StopCalls -eq 0) 'UI abort delegates identity retrieval to the worker and stops nothing'

Reset-DATAbortState
$script:RegValues['CustomDismProcessID'] = 700
$script:RegValues['CustomDismProcessCreationTime'] = [string]$rootStartUtc.Ticks
$script:RegValues['CustomDismProcessExecutable'] = 'C:\Windows\System32\cmd.exe'
$script:RegValues['CustomDismProcessCommandLine'] = $rootCommandLine
$script:TreeMode = 'Empty'
$deferred = Invoke-DATCustomBuildAbortCleanup
Assert-DAT ($deferred -and $script:StopCalls -eq 0) 'stale or exited tracked PID is not stopped and abort defers to the runspace'

Reset-DATAbortState
$script:RegValues['CustomDismProcessID'] = 700
$script:RegValues['CustomDismProcessCreationTime'] = 'not-a-time'
$script:RegValues['CustomDismProcessExecutable'] = 'C:\Windows\System32\cmd.exe'
$script:RegValues['CustomDismProcessCommandLine'] = $rootCommandLine
$deferred = Invoke-DATCustomBuildAbortCleanup
Assert-DAT ($deferred -and $script:TreeCalls -eq 0 -and $script:StopCalls -eq 0) 'incomplete persisted identity defers to the retained worker handle'

Reset-DATAbortState
$script:RegValues['CustomDismProcessID'] = 700
$script:RegValues['CustomDismProcessCreationTime'] = [string]$rootStartUtc.Ticks
$script:RegValues['CustomDismProcessExecutable'] = 'C:\Windows\System32\cmd.exe'
$script:RegValues['CustomDismProcessCommandLine'] = $rootCommandLine
$deferred = Invoke-DATCustomBuildAbortCleanup
Complete-DATCustomBuildAbort -DeferStop $deferred
Assert-DAT ($deferred -and $script:StopCalls -eq 0 -and $global:DATTestLifecycle.Count -eq 0) 'even a verified root remains owned by the worker during UI abort'
Complete-DATCustomBuildAbort -DeferStop $false
Assert-DAT ((@($global:DATTestLifecycle) -join ',') -eq 'timer-stop,ps-stop,ps-dispose,runspace-dispose' -and $null -eq $script:CustomBuildPS -and $null -eq $script:CustomBuildRunspace -and $null -eq $script:CustomBuildAsyncResult -and $script:RegValues['CustomDismProcessID'] -eq 0 -and $script:RegValues['CustomDismProcessCommandLine'] -eq '') 'completed abort stops the runspace and clears persisted process identity'

Reset-DATAbortState
$deferred = Invoke-DATCustomBuildAbortCleanup
Assert-DAT (-not $deferred -and $script:TreeCalls -eq 0 -and $script:Logs.Count -eq 0) 'abort with no tracked DISM process keeps normal cancellation'

foreach ($mock in @('Write-DATLogEntry', 'Write-DATActivityLog', 'Set-DATRegistryValue', 'Get-ItemPropertyValue', 'Get-CimInstance', 'Get-Process', 'Start-Process',
    'Get-DATCustomBuildProcessTree', 'Stop-DATCustomBuildProcessTree', 'ConvertTo-DATProcessIdentity', 'Resolve-DATCustomDismIdentity',
    'Start-DATCustomDismProcess', 'Stop-DATCustomDismProcess', 'Invoke-DATCustomBuildAbortCleanup', 'Complete-DATCustomBuildAbort')) {
    Remove-Item -Path "Function:\$mock" -ErrorAction SilentlyContinue
}
Remove-Variable -Name DATTestKills, DATTestLifecycle -Scope Global -ErrorAction SilentlyContinue

$driverText = Get-Content -LiteralPath $driverPath -Raw
Assert-DAT ($driverText -match '(?s)Mount-WindowsImage[^\r\n]+\r?\n\s*\$WimMounted\s*=\s*\$true') 'WIM ownership is recorded only after mount succeeds'
Assert-DAT ($driverText -match '(?s)finally\s*\{\s*if\s*\(\$WimMounted\).*?Dismount-WindowsImage') 'mounted WIM is dismounted from a finally block'
Assert-DAT ($driverText -match 'DriverInstallCommand.*& pnputil\.exe' -and $driverText -match '-EncodedCommand' -and $driverText -match 'Out-File -LiteralPath') 'pnputil paths are quoted through an encoded command and a literal log path'
Assert-DAT ($driverText -match '\$ApplyDriverInvocation -in @\(0, 3010\)') 'pnputil accepts success and reboot-required while rejecting failures'

$biosText = Get-Content -LiteralPath $biosPath -Raw
$biosTokens = $null
$biosErrors = $null
$biosAst = [System.Management.Automation.Language.Parser]::ParseFile($biosPath, [ref]$biosTokens, [ref]$biosErrors)
$microsoftBranches = @(
    foreach ($ifStatement in $biosAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.IfStatementAst]
    }, $true)) {
        foreach ($clause in $ifStatement.Clauses) {
            if ($clause.Item1.Extent.Text -match '\$ComputerManufacturer\s+-match\s+"Microsoft"' -and
                $clause.Item2.Extent.Text -match 'NewBIOSAvailable') {
                $clause.Item2
            }
        }
    }
)
Assert-DAT ($microsoftBranches.Count -eq 2) 'both Microsoft package-selection branches are present'
foreach ($branch in $microsoftBranches) {
    Assert-DAT ($branch.Extent.Text -match 'Set-NewBIOSAvailableFlag -Value \$true') 'Microsoft branch sets the task-sequence NewBIOSAvailable variable through the shared helper'
}

Import-Module $corePath -Force
$module = Get-Module DriverAutomationToolCore
try {
    & $module {
        Set-Item Function:script:Write-DATLogEntry { param($Value, $Severity) }
        $script:RemovedRetentionApps = @()
        Set-Item Function:script:Remove-DATIntuneApp {
            param($AppId)
            $script:RemovedRetentionApps += $AppId
        }
    }

    $apps = @(
        [pscustomobject]@{ displayName='Drivers - Lenovo T14 - Windows 11 24H2 x64'; displayVersion='2'; createdDateTime='2026-02-01'; lastModifiedDateTime=$null; id='t14-24-new' },
        [pscustomobject]@{ displayName='Drivers - Lenovo T14 - Windows 11 24H2 x64'; displayVersion='1'; createdDateTime='2026-01-01'; lastModifiedDateTime=$null; id='t14-24-old' },
        [pscustomobject]@{ displayName='Drivers - Lenovo T14 - Windows 11 23H2 x64'; displayVersion='1'; createdDateTime='2025-12-01'; lastModifiedDateTime=$null; id='t14-23-only' },
        [pscustomobject]@{ displayName='Drivers - Lenovo T14s - Windows 11 24H2 x64'; displayVersion='9'; createdDateTime='2026-03-01'; lastModifiedDateTime=$null; id='t14s' }
    )
    $result = @(Invoke-DATPackageRetention -OEM Lenovo -Model T14 -OS 'Windows 11' -Architecture x64 `
        -Intune -IntuneApps $apps -RetainCount 0)
    $removed = @(& $module { $script:RemovedRetentionApps })

    Assert-DAT ($result.PackageId -eq 't14-24-old') 'retention removes only an old version from its exact package line'
    Assert-DAT ($removed -notcontains 't14s') 'T14 retention never includes T14s'
    Assert-DAT ($removed -notcontains 't14-23-only') 'retention groups each exact OS package line independently'
} finally {
    Remove-Module DriverAutomationToolCore -Force -ErrorAction SilentlyContinue
}

Write-Host 'Reviewed-fix regression harness completed successfully.'
