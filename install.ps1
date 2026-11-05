<#
.SYNOPSIS
    Root wrapper for DisplayFix lifecycle installer.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'scripts\install.ps1'

if (-not (Test-Path $targetScript)) {
    throw "Target install script missing at $targetScript"
}

if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
    & $targetScript @RemainingArgs
} else {
    & $targetScript
}
exit $LASTEXITCODE
