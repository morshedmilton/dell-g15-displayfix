<#
.SYNOPSIS
    Root wrapper for DisplayFix build system.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'scripts\build.ps1'

if (-not (Test-Path $targetScript)) {
    throw "Target build script missing at $targetScript"
}

if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
    & $targetScript @RemainingArgs
} else {
    & $targetScript
}
exit $LASTEXITCODE
