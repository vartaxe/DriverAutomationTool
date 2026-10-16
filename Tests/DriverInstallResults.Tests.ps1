BeforeAll {
    function Write-CMTraceLog { param($Message, $Severity) }
    function Set-DATInstallStatus { param($RegPath, $Result, $Phase, $ToolExitCode, $ScriptExitCode, $ErrorMessage) }

    function Get-TestGuard {
        param($Ast, $Condition)
        $guard = $Ast.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
                $Node.Clauses[0].Item1.Extent.Text -eq $Condition
        }.GetNewClosure(), $true)
        if ($null -eq $guard) { throw "Install guard not found: $Condition" }
        $text = $guard.Extent.Text
        $exits = @($guard.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.ExitStatementAst]
        }, $true) | Sort-Object { $_.Extent.StartOffset } -Descending)
        foreach ($exit in $exits) {
            if ($exit.Extent.Text -ne 'exit 1') { throw 'Unexpected driver failure exit.' }
            $offset = $exit.Extent.StartOffset - $guard.Extent.StartOffset
            $text = $text.Remove($offset, $exit.Extent.Text.Length).Insert($offset, "throw 'TestExit:1'")
        }
        [scriptblock]::Create($text)
    }
}

Describe 'Driver install result guards in <Template>' -ForEach @(
    @{ Template = 'Driver Automation Tool\Modules\DriverAutomationToolCore\Templates\Install-Drivers.ps1'; HasStatus = $true }
    @{ Template = 'HotFix\10.1.5\Modules\DriverAutomationToolCore\Templates\Install-Drivers.ps1'; HasStatus = $false }
) {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $root $Template), [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw 'Driver template does not parse.' }
        $emptyGuard = Get-TestGuard -Ast $ast -Condition '$infCount -eq 0'
        $exitGuard = Get-TestGuard -Ast $ast -Condition '$pnpProcess.ExitCode -notin @(0, 259, 3010)'
    }

    BeforeEach {
        $VersionRegPath = 'HKLM:\Mock\DAT'
        $WhatIf = $false
        Mock Write-CMTraceLog {}
        Mock Set-DATInstallStatus {}
    }

    It 'fails an empty INF package and never records success' {
        $infCount = 0

        { . $emptyGuard } | Should -Throw 'TestExit:1'
        if ($HasStatus) {
            Should -Invoke Set-DATInstallStatus -Times 1 -Exactly -ParameterFilter {
                $Result -eq 'NoContent' -and $Phase -eq 'InfScan' -and $ScriptExitCode -eq 1
            }
        } else {
            Should -Invoke Set-DATInstallStatus -Times 0 -Exactly
        }
    }

    It 'does not write installation state while previewing an empty package' {
        $infCount = 0
        $WhatIf = $true

        { . $emptyGuard } | Should -Throw 'TestExit:1'
        Should -Invoke Set-DATInstallStatus -Times 0 -Exactly
    }

    It 'preserves accepted pnputil result <Code>' -ForEach @(
        @{ Code = 0 }, @{ Code = 259 }, @{ Code = 3010 }
    ) {
        $pnpProcess = [pscustomobject]@{ ExitCode = $Code }

        { . $exitGuard } | Should -Not -Throw
        Should -Invoke Set-DATInstallStatus -Times 0 -Exactly
    }

    It 'fails pnputil result <Code> without recording success' -ForEach @(
        @{ Code = 1 }, @{ Code = 5 }
    ) {
        $pnpProcess = [pscustomobject]@{ ExitCode = $Code }

        { . $exitGuard } | Should -Throw 'TestExit:1'
        if ($HasStatus) {
            Should -Invoke Set-DATInstallStatus -Times 1 -Exactly -ParameterFilter {
                $Result -eq 'Failed' -and $Phase -eq 'PnpUtil' -and
                    $ToolExitCode -eq $Code -and $ScriptExitCode -eq 1
            }
        } else {
            Should -Invoke Set-DATInstallStatus -Times 0 -Exactly
        }
    }
}
