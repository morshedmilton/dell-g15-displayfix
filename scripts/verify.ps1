<#
.SYNOPSIS
    Master Acceptance Validation Runner for Dell G15 5530 DisplayFix (Features F01-F16).

.DESCRIPTION
    Executes the complete end-to-end acceptance verification pipeline across:
      1. Repository & Deliverable File Contract Audit (Binaries, Scripts, Docs, Test Suites)
      2. DisplayFixDaemon CLI & Runtime Status Verification
      3. Live System Telemetry Probe (scripts/diagnostics/probe_system.ps1)
      4. DWM Health & Stability Monitor (scripts/diagnostics/dwm_health.ps1)
      5. Display Switching Stress Test Smoke Run (scripts/diagnostics/stress_test.ps1)
      6. Master 29-Suite / 136-Test Opaque-Box E2E Test Suite (tests/e2e/test_runner.ps1)

.PARAMETER StressIterations
    Number of stress test switch iterations to run during Phase 5 (default: 5).

.PARAMETER Quick
    If specified, runs a fast 2-iteration stress check with minimal settle delay.

.PARAMETER SkipBuild
    If specified, skips invoking scripts/build.ps1 when bin/DisplayFixDaemon.exe already exists.

.PARAMETER OutputFile
    Path to write the JSON acceptance report (default: 'C:\ProgramData\DisplayFix\logs\verification_report.json').

.PARAMETER Json
    Suppresses console banners and emits a pure JSON verification report to stdout.

.PARAMETER PassThru
    Returns the verification report object directly to the PowerShell pipeline.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$StressIterations = 5,

    [switch]$Quick,

    [switch]$SkipBuild = $true,

    [string]$OutputFile = 'C:\ProgramData\DisplayFix\logs\verification_report.json',

    [switch]$Json,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$overallSw = [System.Diagnostics.Stopwatch]::StartNew()
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$checks = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-CheckResult {
    param(
        [string]$Phase,
        [string]$Name,
        [bool]$Passed,
        [string]$Details,
        [int]$DurationMs = 0
    )
    $checks.Add([PSCustomObject]@{
        Phase      = $Phase
        Name       = $Name
        Status     = if ($Passed) { 'PASS' } else { 'FAIL' }
        Passed     = $Passed
        DurationMs = $DurationMs
        Details    = $Details
    })
    if (-not $Json) {
        $tag = if ($Passed) { '[PASS]' } else { '[FAIL]' }
        $color = if ($Passed) { 'Green' } else { 'Red' }
        Write-Host ("  {0} {1} ({2}ms) - {3}" -f $tag, $Name, $DurationMs, $Details) -ForegroundColor $color
    }
}

if (-not $Json) {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " DELL G15 5530 DISPLAYFIX -- MASTER ACCEPTANCE VERIFICATION RUNNER" -ForegroundColor Cyan
    Write-Host " Root: $projectRoot | Elevated: $isElevated" -ForegroundColor DarkCyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

# -------------------------------------------------------------------------
# Phase 1: Repository & Deliverable Contract Audit
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 1] Auditing Deliverable Files & Build Artifacts..." -ForegroundColor Yellow
}

$daemonExe = Join-Path $projectRoot 'bin\DisplayFixDaemon.exe'
$buildScript = Join-Path $projectRoot 'scripts\build.ps1'

if (-not (Test-Path $daemonExe) -or (-not $SkipBuild)) {
    $swBuild = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript 2>&1
        $buildOk = ($LASTEXITCODE -eq 0) -and (Test-Path $daemonExe)
        $swBuild.Stop()
        Add-CheckResult -Phase 'Phase 1: Deliverables' -Name 'Native csc.exe Build (DisplayFixDaemon.exe)' `
            -Passed $buildOk -Details "Binary: $daemonExe" -DurationMs ([int]$swBuild.ElapsedMilliseconds)
    } catch {
        $swBuild.Stop()
        Add-CheckResult -Phase 'Phase 1: Deliverables' -Name 'Native csc.exe Build (DisplayFixDaemon.exe)' `
            -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swBuild.ElapsedMilliseconds)
    }
} else {
    Add-CheckResult -Phase 'Phase 1: Deliverables' -Name 'DisplayFixDaemon.exe Binary Exists' `
        -Passed (Test-Path $daemonExe) -Details "Binary: $daemonExe" -DurationMs 1
}

$requiredFiles = @(
    'PROJECT.md',
    'TEST_INFRA.md',
    'TEST_READY.md',
    'README.md',
    'CHANGELOG.md',
    'build.ps1',
    'install.ps1',
    'uninstall.ps1',
    'scripts\build.ps1',
    'scripts\install.ps1',
    'scripts\uninstall.ps1',
    'scripts\verify.ps1',
    'scripts\diagnostics\probe_system.ps1',
    'scripts\diagnostics\dwm_health.ps1',
    'scripts\diagnostics\stress_test.ps1',
    'docs\verification_guide.md',
    'docs\architecture.md',
    'tests\e2e\test_runner.ps1'
)

$missingFiles = @()
foreach ($rel in $requiredFiles) {
    $full = Join-Path $projectRoot $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $missingFiles += $rel
    }
}

Add-CheckResult -Phase 'Phase 1: Deliverables' -Name 'All Required Repository Deliverables Present' `
    -Passed ($missingFiles.Count -eq 0) `
    -Details $(if ($missingFiles.Count -eq 0) { "Verified $($requiredFiles.Count)/$($requiredFiles.Count) files" } else { "Missing: $($missingFiles -join ', ')" }) `
    -DurationMs 5

# -------------------------------------------------------------------------
# Phase 2: DisplayFixDaemon CLI & Runtime Verification
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 2] Verifying DisplayFixDaemon CLI & Self-Healing Commands..." -ForegroundColor Yellow
}

$swStatus = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $statusOut = & $daemonExe --status 2>&1 | Out-String
    $statusExit = $LASTEXITCODE
    $swStatus.Stop()
    $statusOk = ($statusExit -eq 0) -and ($statusOut -match 'DisplayFixDaemon Status Telemetry')
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --status' `
        -Passed $statusOk -Details "ExitCode=$statusExit" -DurationMs ([int]$swStatus.ElapsedMilliseconds)
} catch {
    $swStatus.Stop()
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --status' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swStatus.ElapsedMilliseconds)
}

$swLock = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $lockOut = & $daemonExe --lock-360hz 2>&1 | Out-String
    $lockExit = $LASTEXITCODE
    $swLock.Stop()
    $lockOk = ($lockExit -eq 0) -and ($lockOut -match 'Success:\s*True')
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --lock-360hz' `
        -Passed $lockOk -Details "ExitCode=$lockExit" -DurationMs ([int]$swLock.ElapsedMilliseconds)
} catch {
    $swLock.Stop()
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --lock-360hz' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swLock.ElapsedMilliseconds)
}

$swDpi = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $dpiOut = & $daemonExe --sync-dpi 2>&1 | Out-String
    $dpiExit = $LASTEXITCODE
    $swDpi.Stop()
    $dpiOk = ($dpiExit -eq 0) -and ($dpiOut -match 'Success:\s*True')
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --sync-dpi' `
        -Passed $dpiOk -Details "ExitCode=$dpiExit" -DurationMs ([int]$swDpi.ElapsedMilliseconds)
} catch {
    $swDpi.Stop()
    Add-CheckResult -Phase 'Phase 2: Daemon CLI' -Name 'DisplayFixDaemon.exe --sync-dpi' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swDpi.ElapsedMilliseconds)
}

# -------------------------------------------------------------------------
# Phase 3: Live System Telemetry Probe (probe_system.ps1)
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 3] Executing Live System Telemetry Probe (F01)..." -ForegroundColor Yellow
}

$probeScript = Join-Path $projectRoot 'scripts\diagnostics\probe_system.ps1'
$swProbe = [System.Diagnostics.Stopwatch]::StartNew()
$telemetryObj = $null
try {
    $probeRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeScript -Json -NoFile 2>$null | Out-String
    $telemetryObj = $probeRaw | ConvertFrom-Json
    $swProbe.Stop()

    $probeOk = ($null -ne $telemetryObj) -and
               ($telemetryObj.RefreshRateHz -ge 359.0) -and
               ($telemetryObj.DpiScalePercent -eq 125) -and
               (-not $telemetryObj.PhantomDuplicateDetected) -and
               ($telemetryObj.TdrEventCount -eq 0) -and
               ($telemetryObj.DwmCrashCount -eq 0)

    Add-CheckResult -Phase 'Phase 3: Telemetry' -Name 'System Telemetry Invariants (360Hz, 125% DPI, 0 Ghosts, 0 TDRs)' `
        -Passed $probeOk `
        -Details "GPU=$($telemetryObj.ActiveGpu), Mode=$($telemetryObj.DisplayMode), Hz=$($telemetryObj.RefreshRateHz), DPI=$($telemetryObj.DpiScalePercent)%, Ghost=$($telemetryObj.PhantomDuplicateDetected)" `
        -DurationMs ([int]$swProbe.ElapsedMilliseconds)
} catch {
    $swProbe.Stop()
    Add-CheckResult -Phase 'Phase 3: Telemetry' -Name 'System Telemetry Invariants (360Hz, 125% DPI, 0 Ghosts, 0 TDRs)' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swProbe.ElapsedMilliseconds)
}

# -------------------------------------------------------------------------
# Phase 4: DWM Health & Stability Gate (dwm_health.ps1)
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 4] Executing DWM Health & Stability Monitor (F02)..." -ForegroundColor Yellow
}

$dwmScript = Join-Path $projectRoot 'scripts\diagnostics\dwm_health.ps1'
$swDwm = [System.Diagnostics.Stopwatch]::StartNew()
$dwmObj = $null
try {
    $dwmRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $dwmScript -Json 2>$null | Out-String
    $dwmObj = $dwmRaw | ConvertFrom-Json
    $swDwm.Stop()

    $dwmOk = ($null -ne $dwmObj) -and
             ($dwmObj.Status -eq 'Healthy') -and
             ($dwmObj.Process.WorkingSetMB -lt 250.0) -and
             ($dwmObj.Process.HandleCount -lt 2500) -and
             ($dwmObj.StabilityEvents.TdrCount -eq 0) -and
             ($dwmObj.StabilityEvents.DwmCrashCount -eq 0)

    Add-CheckResult -Phase 'Phase 4: DWM Health' -Name 'DWM Stability & Resource Bounds (<250MB WS, <2500 Handles)' `
        -Passed $dwmOk `
        -Details "Status=$($dwmObj.Status), WS=$($dwmObj.Process.WorkingSetMB)MB, Handles=$($dwmObj.Process.HandleCount), CPU=$($dwmObj.Process.CpuPercent)%" `
        -DurationMs ([int]$swDwm.ElapsedMilliseconds)
} catch {
    $swDwm.Stop()
    Add-CheckResult -Phase 'Phase 4: DWM Health' -Name 'DWM Stability & Resource Bounds (<250MB WS, <2500 Handles)' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swDwm.ElapsedMilliseconds)
}

# -------------------------------------------------------------------------
# Phase 5: Display Switching Stress Smoke Test (stress_test.ps1)
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 5] Executing Display Switching Stress Harness (F03)..." -ForegroundColor Yellow
}

$stressScript = Join-Path $projectRoot 'scripts\diagnostics\stress_test.ps1'
$itersToRun = if ($Quick) { 2 } else { $StressIterations }
$settleMs   = if ($Quick) { 100 } else { 200 }
$cooldownMs = if ($Quick) { 100 } else { 200 }

$swStress = [System.Diagnostics.Stopwatch]::StartNew()
$stressObj = $null
try {
    $stressRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $stressScript `
        -Iterations $itersToRun -Mode Simulated -SettleDelayMs $settleMs -CooldownMs $cooldownMs -Json 2>$null | Out-String
    $stressObj = $stressRaw | ConvertFrom-Json
    $swStress.Stop()

    $stressOk = ($null -ne $stressObj) -and ($stressObj.overallVerdict -eq 'PASSED')
    Add-CheckResult -Phase 'Phase 5: Stress Harness' -Name "Stress Harness ($itersToRun Iterations)" `
        -Passed $stressOk `
        -Details "Verdict=$($stressObj.overallVerdict), WSDelta=$($stressObj.leakAnalysis.workingSet.actualDeltaMB)MB, HandleDelta=$($stressObj.leakAnalysis.handles.actualDelta)" `
        -DurationMs ([int]$swStress.ElapsedMilliseconds)
} catch {
    $swStress.Stop()
    Add-CheckResult -Phase 'Phase 5: Stress Harness' -Name "Stress Harness ($itersToRun Iterations)" `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swStress.ElapsedMilliseconds)
}

# -------------------------------------------------------------------------
# Phase 6: Master 29-Suite (136-Test) Opaque-Box E2E Test Suite
# -------------------------------------------------------------------------
if (-not $Json) {
    Write-Host "`n[Phase 6] Executing Complete 29-Suite (136-Test) E2E Test Harness (F16)..." -ForegroundColor Yellow
}

$e2eRunner = Join-Path $projectRoot 'tests\e2e\test_runner.ps1'
$swE2e = [System.Diagnostics.Stopwatch]::StartNew()
$e2eObj = $null
try {
    $e2eRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $e2eRunner -Tier All -Json 2>$null | Out-String
    $e2eObj = $e2eRaw | ConvertFrom-Json
    $swE2e.Stop()

    $e2eOk = ($null -ne $e2eObj) -and
             ($e2eObj.Summary.Success -eq $true) -and
             ($e2eObj.Summary.Failed -eq 0) -and
             ($e2eObj.Summary.TotalSuites -ge 29) -and
             ($e2eObj.Summary.Passed -ge 136)

    Add-CheckResult -Phase 'Phase 6: E2E Test Suite' -Name 'Master E2E Test Suite (All Tiers 1-4)' `
        -Passed $e2eOk `
        -Details "Suites=$($e2eObj.Summary.TotalSuites), Passed=$($e2eObj.Summary.Passed)/$($e2eObj.Summary.TotalTests), Failed=$($e2eObj.Summary.Failed)" `
        -DurationMs ([int]$swE2e.ElapsedMilliseconds)
} catch {
    $swE2e.Stop()
    Add-CheckResult -Phase 'Phase 6: E2E Test Suite' -Name 'Master E2E Test Suite (All Tiers 1-4)' `
        -Passed $false -Details $_.Exception.Message -DurationMs ([int]$swE2e.ElapsedMilliseconds)
}

$overallSw.Stop()
$totalMs = [int]$overallSw.ElapsedMilliseconds
$passedChecks = @($checks | Where-Object { $_.Passed }).Count
$failedChecks = @($checks | Where-Object { -not $_.Passed }).Count
$overallSuccess = ($failedChecks -eq 0)

$report = [PSCustomObject]@{
    Timestamp       = (Get-Date).ToUniversalTime().ToString('o')
    OverallVerdict  = if ($overallSuccess) { 'PASSED' } else { 'FAILED' }
    Success         = $overallSuccess
    IsElevated      = $isElevated
    TotalChecks     = $checks.Count
    PassedChecks    = $passedChecks
    FailedChecks    = $failedChecks
    DurationMs      = $totalMs
    Checks          = $checks
    E2ESummary      = if ($e2eObj) { $e2eObj.Summary } else { $null }
}

if ($OutputFile) {
    try {
        $outDir = Split-Path -Parent $OutputFile
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null
        }
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputFile -Encoding UTF8
    } catch {
        $fallbackFile = Join-Path $env:TEMP 'DisplayFix\logs\verification_report.json'
        try {
            $fbDir = Split-Path -Parent $fallbackFile
            if (-not (Test-Path -LiteralPath $fbDir)) {
                New-Item -ItemType Directory -Path $fbDir -Force | Out-Null
            }
            $report | ConvertTo-Json -Depth 6 | Set-Content -Path $fallbackFile -Encoding UTF8
        } catch { }
    }
}

if ($Json) {
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host " MASTER ACCEPTANCE VERIFICATION SUMMARY" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " Total Verification Gates : $($checks.Count)"
    Write-Host " Gates Passed             : $passedChecks" -ForegroundColor Green
    Write-Host " Gates Failed             : $failedChecks" -ForegroundColor $(if ($failedChecks -eq 0) { 'Gray' } else { 'Red' })
    if ($e2eObj) {
        Write-Host " E2E Test Suite Coverage  : $($e2eObj.Summary.Passed) / $($e2eObj.Summary.TotalTests) Tests Passing ($($e2eObj.Summary.TotalSuites) Suites)" -ForegroundColor Green
    }
    Write-Host " Total Duration           : $([math]::Round($totalMs / 1000.0, 2)) seconds"
    Write-Host " Final Verdict            : $($report.OverallVerdict)" -ForegroundColor $(if ($overallSuccess) { 'Green' } else { 'Red' })
    Write-Host "================================================================================" -ForegroundColor Cyan
}

if ($PassThru) {
    return $report
}

# Ensure resident daemon is restored and running after test execution
try {
    $activeDaemon = Get-Process -Name 'DisplayFixDaemon' -ErrorAction SilentlyContinue
    if (-not $activeDaemon -and (Test-Path -LiteralPath $daemonExe)) {
        [void]([wmiclass]"win32_process").Create("`"$daemonExe`" --run")
    }
} catch { }

if ($overallSuccess) {
    exit 0
} else {
    exit 1
}
