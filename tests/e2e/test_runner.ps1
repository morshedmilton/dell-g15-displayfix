# tests/e2e/test_runner.ps1
# Master E2E Test Runner for Dell G15 5530 DisplayFix Project

[CmdletBinding()]
param(
    [ValidateSet('1', '2', '3', '4', 'All')]
    [string]$Tier = 'All',

    [string]$Filter = '',

    [switch]$Json,

    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $testRoot)

# Import common framework
. (Join-Path $testRoot 'common\TestFramework.ps1')
. (Join-Path $testRoot 'common\SystemProbes.ps1')

# Reset test context
$global:GlobalTestContext.Suites.Clear()
$global:GlobalTestContext.JsonMode = $Json.IsPresent
$global:GlobalTestContext.VerboseMode = $VerboseOutput.IsPresent
$global:GlobalTestContext.TotalPassed = 0
$global:GlobalTestContext.TotalFailed = 0
$global:GlobalTestContext.TotalSkipped = 0

$tierMap = @{
    '1' = @('tier1_features')
    '2' = @('tier2_boundaries')
    '3' = @('tier3_combinations')
    '4' = @('tier4_scenarios')
    'All' = @('tier1_features', 'tier2_boundaries', 'tier3_combinations', 'tier4_scenarios')
}

$dirsToRun = $tierMap[$Tier]
$overallSw = [System.Diagnostics.Stopwatch]::StartNew()

$filterDesc = if ($Filter) { $Filter } else { '*' }
$dateStr = Get-Date -Format 'u'

if (-not $Json) {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " DELL G15 5530 DISPLAYFIX -- MASTER E2E TEST RUNNER" -ForegroundColor Cyan
    Write-Host " Running Tier: $Tier | Filter: '$filterDesc' | Time: $dateStr" -ForegroundColor DarkCyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

foreach ($tierDir in $dirsToRun) {
    $tierPath = Join-Path $testRoot $tierDir
    if (-not (Test-Path $tierPath)) {
        continue
    }

    $tierName = switch ($tierDir) {
        'tier1_features'     { 'Tier 1: Feature Coverage (F01-F16)' }
        'tier2_boundaries'   { 'Tier 2: Boundary & Corner Cases' }
        'tier3_combinations' { 'Tier 3: Pairwise Combinations' }
        'tier4_scenarios'    { 'Tier 4: Real-World Scenarios' }
        Default              { $tierDir }
    }

    Set-TestTier -Tier $tierName

    $testFiles = Get-ChildItem -Path $tierPath -Filter "test_*.ps1" | Sort-Object Name
    foreach ($file in $testFiles) {
        if ($Filter -and ($file.Name -notmatch $Filter -and $file.BaseName -notmatch $Filter)) {
            continue
        }

        try {
            . $file.FullName
        }
        catch {
            Write-Host "  [SCRIPT ERROR] Failed executing test script $($file.Name): $_" -ForegroundColor Red
            $global:GlobalTestContext.TotalFailed++
        }
    }
}

$overallSw.Stop()
$totalDurationMs = [int]$overallSw.ElapsedMilliseconds

$totalTests = $global:GlobalTestContext.TotalPassed + $global:GlobalTestContext.TotalFailed + $global:GlobalTestContext.TotalSkipped
$isSuccess = ($global:GlobalTestContext.TotalFailed -eq 0)

if ($Json) {
    $report = [PSCustomObject]@{
        Timestamp    = (Get-Date).ToUniversalTime().ToString("o")
        TargetSystem = @{
            Model = "Dell G15 5530"
            Gpu   = "NVIDIA GeForce RTX 4060 Laptop GPU / Intel UHD Graphics"
            Panel = "AU Optronics AUO AA9F 1080p 360Hz"
        }
        Summary      = @{
            Tier         = $Tier
            Filter       = $Filter
            TotalSuites  = $global:GlobalTestContext.Suites.Count
            TotalTests   = $totalTests
            Passed       = $global:GlobalTestContext.TotalPassed
            Failed       = $global:GlobalTestContext.TotalFailed
            Skipped      = $global:GlobalTestContext.TotalSkipped
            DurationMs   = $totalDurationMs
            Success      = $isSuccess
        }
        Suites       = $global:GlobalTestContext.Suites
    }
    $report | ConvertTo-Json -Depth 6
}
else {
    $failColor = if ($global:GlobalTestContext.TotalFailed -gt 0) { [System.ConsoleColor]::Red } else { [System.ConsoleColor]::Gray }
    $skipColor = if ($global:GlobalTestContext.TotalSkipped -gt 0) { [System.ConsoleColor]::Yellow } else { [System.ConsoleColor]::Gray }
    $resultText = if ($isSuccess) { "ALL TESTS PASSED" } else { "ONE OR MORE TESTS FAILED" }
    $resultColor = if ($isSuccess) { [System.ConsoleColor]::Green } else { [System.ConsoleColor]::Red }
    $durationSec = [math]::Round($totalDurationMs / 1000.0, 2)

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " TEST RUN SUMMARY" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " Total Suites: $($global:GlobalTestContext.Suites.Count)"
    Write-Host " Total Tests:  $totalTests"
    Write-Host " Passed:       $($global:GlobalTestContext.TotalPassed)" -ForegroundColor Green
    Write-Host " Failed:       $($global:GlobalTestContext.TotalFailed)" -ForegroundColor $failColor
    Write-Host " Skipped:      $($global:GlobalTestContext.TotalSkipped)" -ForegroundColor $skipColor
    Write-Host " Duration:     $durationSec seconds"
    Write-Host " Result:       $resultText" -ForegroundColor $resultColor
    Write-Host "================================================================================" -ForegroundColor Cyan
}

if ($isSuccess) {
    exit 0
} else {
    exit 1
}
