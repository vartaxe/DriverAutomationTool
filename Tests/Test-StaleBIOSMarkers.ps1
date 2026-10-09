$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Driver Automation Tool\Scripts\Remove-DATStaleBIOSMarkers.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Marker cleanup script did not parse: $($parseErrors[0].Message)"
}

$loop = $ast.Find({
        param ($node)
        $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
        $node.Variable.VariablePath.UserPath -eq 'oemKey'
    }, $true)
if ($null -eq $loop) {
    throw 'Could not find the OEM/model marker cleanup loop.'
}

$script:ModelsByOem = @{}
$script:Markers = @{}
$script:Removals = [System.Collections.Generic.List[string]]::new()
$script:Messages = [System.Collections.Generic.List[string]]::new()

function Get-ChildItem {
    param ([string]$LiteralPath, [string]$ErrorAction)

    if ($LiteralPath -eq $BiosRoot) {
        return @($script:OemKeys)
    }
    if ($script:ModelsByOem.ContainsKey($LiteralPath)) {
        return @($script:ModelsByOem[$LiteralPath])
    }
    throw "Unexpected mocked registry path: $LiteralPath"
}

function Get-ItemProperty {
    param ([string]$LiteralPath, [string]$ErrorAction)
    [pscustomobject]@{ Version = $script:Markers[$LiteralPath] }
}

function Remove-ItemProperty {
    param ([string]$LiteralPath, [string[]]$Name, [switch]$Force, [string]$ErrorAction)
    foreach ($propertyName in $Name) {
        $script:Removals.Add("$LiteralPath|$propertyName")
    }
}

function Write-Log {
    param ([string]$Message)
    $script:Messages.Add($Message)
}

$BiosRoot = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
$liveVersion = '2.0'
$liveParsed = [version]$liveVersion
$liveIsVersion = $true
$script:OemKeys = @(
    [pscustomobject]@{ PSPath = "$BiosRoot\HP" },
    [pscustomobject]@{ PSPath = "$BiosRoot\Dell" }
)
$script:ModelsByOem["$BiosRoot\HP"] = @(
    [pscustomobject]@{ PSPath = "$BiosRoot\HP\Model A" },
    [pscustomobject]@{ PSPath = "$BiosRoot\HP\Model B" }
)
$script:ModelsByOem["$BiosRoot\Dell"] = @(
    [pscustomobject]@{ PSPath = "$BiosRoot\Dell\Model C" },
    [pscustomobject]@{ PSPath = "$BiosRoot\Dell\Model D" }
)
$script:Markers["$BiosRoot\HP\Model A"] = '3.0'
$script:Markers["$BiosRoot\HP\Model B"] = '1.0'
$script:Markers["$BiosRoot\Dell\Model C"] = '2.0'
$script:Markers["$BiosRoot\Dell\Model D"] = '4.0'

$removed = 0
. ([scriptblock]::Create($loop.Extent.Text))

$expectedRemovals = @(
    "$BiosRoot\HP\Model A|Version",
    "$BiosRoot\HP\Model A|PendingReboot",
    "$BiosRoot\HP\Model A|PendingRebootBootTime",
    "$BiosRoot\Dell\Model D|Version",
    "$BiosRoot\Dell\Model D|PendingReboot",
    "$BiosRoot\Dell\Model D|PendingRebootBootTime"
)
if ($removed -ne 2 -or (@($script:Removals) -join "`n") -ne ($expectedRemovals -join "`n")) {
    throw "Unexpected removals for multiple OEM/model keys: removed=$removed; actions=$($script:Removals -join ', ')"
}
if (@($script:Messages | Where-Object { $_ -match '\[HP\\Model A\] Removed stale marker' }).Count -ne 1 -or
    @($script:Messages | Where-Object { $_ -match '\[Dell\\Model D\] Removed stale marker' }).Count -ne 1 -or
    @($script:Messages | Where-Object { $_ -match '\[HP\\Model B\] Marker 1\.0 not ahead' }).Count -ne 1 -or
    @($script:Messages | Where-Object { $_ -match '\[Dell\\Model C\] Marker 2\.0 not ahead' }).Count -ne 1) {
    throw 'OEM/model names were not retained in the cleanup log messages.'
}
Write-Host 'PASS: only stale markers are removed across multiple OEM/model keys, with OEM/model labels retained'

$script:Removals.Clear()
$script:Messages.Clear()
$script:Markers["$BiosRoot\HP\Model A"] = '2.0'
$script:Markers["$BiosRoot\HP\Model B"] = '1.0'
$script:Markers["$BiosRoot\Dell\Model C"] = 'not-a-version'
$script:Markers["$BiosRoot\Dell\Model D"] = '2.0'
$removed = 0
. ([scriptblock]::Create($loop.Extent.Text))
if ($removed -ne 0 -or $script:Removals.Count -ne 0) {
    throw "Markers equal to, behind, or incomparable with firmware were removed: $($script:Removals -join ', ')"
}
Write-Host 'PASS: equal, older, and unparseable markers produce no registry removals'

$scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($scriptAst.ParamBlock -and $scriptAst.ParamBlock.Attributes.TypeName.FullName -contains 'CmdletBinding' -and
    $scriptAst.ParamBlock.Attributes | Where-Object { $_.Extent.Text -match 'SupportsShouldProcess' }) {
    Write-Host 'PASS: script advertises WhatIf support'
} else {
    Write-Host 'INFO: script does not implement ShouldProcess/-WhatIf; no-removal behavior is verified using equal, older, and unparseable versions'
}
