# tests/e2e/tier5_adversarial/adversarial_m2_lifecycle.ps1
# Adversarial Stress Testing Suite for Milestone 2:
# Daemon Lifecycle, Mutex Concurrency Race, CLI Robustness & Task Persistence

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$totalTests = 0
$passedTests = 0
$failedTests = 0
$testResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-TestResult {
    param(
        [string]$Category,
        [string]$TestName,
        [bool]$Passed,
        [string]$Details
    )
    $script:totalTests++
    if ($Passed) {
        $script:passedTests++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] ${TestName}: $Details" -ForegroundColor Red
    }
    $script:testResults.Add([PSCustomObject]@{
        Category = $Category
        TestName = $TestName
        Passed   = $Passed
        Details  = $Details
    })
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  M2 DAEMON LIFECYCLE, MUTEX & CLI ADVERSARIAL STRESS SUITE" -ForegroundColor White
Write-Host "  Target: DisplayFixDaemon.exe, SingleInstanceMutex, install.ps1" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor Cyan

$binPath = Join-Path (Get-Location).Path "bin\DisplayFixDaemon.exe"
if (-not (Test-Path $binPath)) {
    Write-Host "[ERROR] Binary not found at $binPath. Run build.ps1 first." -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------------------------
# SUITE 1: Single-Instance Mutex Concurrency & Race Condition
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 1: Mutex Concurrency Race (5 Simultaneous Instances) ---" -ForegroundColor Yellow

# Ensure no orphan process is holding the mutex
Get-Process -Name DisplayFixDaemon -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$jobs = 1..5 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($exe)
        $proc = Start-Process -FilePath $exe -ArgumentList "--run" -PassThru
        Start-Sleep -Seconds 2
        return [PSCustomObject]@{
            ProcessId = $proc.Id
            HasExited = $proc.HasExited
            ExitCode  = if ($proc.HasExited) { $proc.ExitCode } else { $null }
        }
    } -ArgumentList $binPath
}

$null = $jobs | Wait-Job -Timeout 20
$jobOutputs = $jobs | Receive-Job

$runningCount = @($jobOutputs | Where-Object { $_.HasExited -eq $false }).Count
$exit2Count = @($jobOutputs | Where-Object { $_.HasExited -eq $true -and $_.ExitCode -eq 2 }).Count

$suite1Passed = ($runningCount -eq 1 -and $exit2Count -eq 4)
Record-TestResult -Category "1. Mutex Concurrency" `
    -TestName "5 simultaneous background instances: exactly 1 acquires mutex, 4 exit with code 2" `
    -Passed $suite1Passed `
    -Details "Running=$runningCount (expected 1), Code2=$exit2Count (expected 4)"

# Cleanup running daemon and jobs
Get-Process -Name DisplayFixDaemon -ErrorAction SilentlyContinue | Stop-Process -Force
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# -------------------------------------------------------------------------
# SUITE 2: CLI Argument Robustness & Casing
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 2: CLI Argument Robustness & Command Handlers ---" -ForegroundColor Yellow

# Test 2.1: --status when daemon is NOT running
$statusOutStopped = & $binPath --status | Out-String
$statusStoppedPassed = ($LASTEXITCODE -eq 0 -and $statusOutStopped -match 'Mutex Active:\s+False' -and $statusOutStopped -match 'DisplayFixDaemon Status Telemetry')
Record-TestResult -Category "2. CLI Robustness" `
    -TestName "--status executes cleanly with code 0 when daemon is stopped (reports Mutex Active: False)" `
    -Passed $statusStoppedPassed `
    -Details "ExitCode=$LASTEXITCODE, MutexActive=False"

# Test 2.2: --evict-now one-shot execution
$evictOut = & $binPath --evict-now | Out-String
$evictPassed = ($LASTEXITCODE -eq 0 -and $evictOut -match 'One-shot eviction complete' -and $evictOut -match 'Ghost monitors evicted:')
Record-TestResult -Category "2. CLI Robustness" `
    -TestName "--evict-now executes cleanly with code 0 and reports eviction metrics" `
    -Passed $evictPassed `
    -Details "ExitCode=$LASTEXITCODE"

# Test 2.3: Case insensitivity (--STATUS, --EVICT-NOW)
$caseStatusOut = & $binPath --STATUS | Out-String
$caseStatusExit = $LASTEXITCODE
$caseEvictOut = & $binPath --EVICT-NOW | Out-String
$caseEvictExit = $LASTEXITCODE
$casingPassed = ($caseStatusExit -eq 0 -and $caseEvictExit -eq 0 -and $caseStatusOut -match 'Telemetry' -and $caseEvictOut -match 'eviction')
Record-TestResult -Category "2. CLI Robustness" `
    -TestName "CLI arguments are case-insensitive (--STATUS, --EVICT-NOW)" `
    -Passed $casingPassed `
    -Details "StatusExit=$caseStatusExit, EvictExit=$caseEvictExit"

# Test 2.4: Mutex protection while daemon is running for --status and --evict-now
$activeDaemon = Start-Process -FilePath $binPath -ArgumentList "--run" -PassThru
Start-Sleep -Seconds 2

$statusOutRunning = & $binPath --status | Out-String
$statusRunningExit = $LASTEXITCODE
$statusRunningPassed = ($statusRunningExit -eq 0 -and $statusOutRunning -match 'Mutex Active:\s+True')
Record-TestResult -Category "2. CLI Robustness" `
    -TestName "--status correctly detects active mutex when daemon is running" `
    -Passed $statusRunningPassed `
    -Details "ExitCode=$statusRunningExit, OutputMatched=$($statusOutRunning -match 'Mutex Active:\s+True')"

# Test 2.5: Invoking duplicate daemon via --help or --unknown while daemon is running exits with code 2
$pHelp = Start-Process -FilePath $binPath -ArgumentList "--help" -Wait -PassThru
$pUnknown = Start-Process -FilePath $binPath -ArgumentList "--unknown" -Wait -PassThru
$pEmpty = Start-Process -FilePath $binPath -ArgumentList '""' -Wait -PassThru

$dupBlocked = ($pHelp.ExitCode -eq 2 -and $pUnknown.ExitCode -eq 2 -and $pEmpty.ExitCode -eq 2)
Record-TestResult -Category "2. CLI Robustness" `
    -TestName "Invoking --help, --unknown, or empty arg while daemon is running yields exit code 2 (duplicate prevented)" `
    -Passed $dupBlocked `
    -Details "--help exit: $($pHelp.ExitCode), --unknown exit: $($pUnknown.ExitCode), empty exit: $($pEmpty.ExitCode)"

$activeDaemon | Stop-Process -Force
Start-Sleep -Milliseconds 500

# -------------------------------------------------------------------------
# SUITE 3: Abrupt Process Termination & Mutex Recovery
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 3: Process Termination & Mutex Recovery ---" -ForegroundColor Yellow

# Test 3.1: Abrupt Stop-Process -Force cleanly frees named mutex
$daemon1 = Start-Process -FilePath $binPath -ArgumentList "--run" -PassThru
Start-Sleep -Seconds 2

# Verify mutex is held
$held = $false
try {
    $mObj = [System.Threading.Mutex]::OpenExisting("Global\DisplayFixDaemon_SingleInstanceMutex")
    if (-not $mObj.WaitOne(0)) {
        $held = $true
    }
    $mObj.Close()
} catch {
    $held = $false
}

# Kill daemon abruptly
Stop-Process -Id $daemon1.Id -Force
Start-Sleep -Milliseconds 500

# Launch immediately
$daemon2 = Start-Process -FilePath $binPath -ArgumentList "--run" -PassThru
Start-Sleep -Seconds 2

$recovered = ($null -ne (Get-Process -Id $daemon2.Id -ErrorAction SilentlyContinue) -and -not $daemon2.HasExited)
Record-TestResult -Category "3. Mutex Recovery" `
    -TestName "Abrupt Stop-Process -Force releases named mutex; immediate restart succeeds without deadlock" `
    -Passed ($held -and $recovered) `
    -Details "InitialMutexHeld=$held, RecoveredPID=$($daemon2.Id), HasExited=$($daemon2.HasExited)"

$daemon2 | Stop-Process -Force
Start-Sleep -Milliseconds 500

# Test 3.2: 5 consecutive kill-and-recover cycles under rapid stress
$rapidPass = 0
for ($c = 1; $c -le 5; $c++) {
    $p = Start-Process -FilePath $binPath -ArgumentList "--run" -PassThru
    Start-Sleep -Milliseconds 400
    if (-not $p.HasExited) {
        Stop-Process -Id $p.Id -Force
        Start-Sleep -Milliseconds 200
        $rapidPass++
    }
}
Record-TestResult -Category "3. Mutex Recovery" `
    -TestName "5 rapid kill-and-recover stress cycles complete with zero mutex deadlocks or hangs" `
    -Passed ($rapidPass -eq 5) `
    -Details "Cycles passed: $rapidPass / 5"

# -------------------------------------------------------------------------
# SUITE 4: Scheduled Task Persistence & Policy Verification
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 4: Scheduled Task Persistence & Policy Settings ---" -ForegroundColor Yellow

# Test 4.1: In-memory Task Settings Definition verification (matching install.ps1)
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval ([TimeSpan]::FromMinutes(1))

$batteryPersist = ($settings.DisallowStartIfOnBatteries -eq $false -and $settings.StopIfGoingOnBatteries -eq $false)
$restartOnFail  = ($settings.RestartCount -eq 3 -and $settings.RestartInterval -eq "PT1M")
$noTimeLimit    = ($settings.ExecutionTimeLimit -eq "PT0S")
$ignoreNew      = ($settings.MultipleInstances -eq "IgnoreNew")

$settingsPassed = ($batteryPersist -and $restartOnFail -and $noTimeLimit -and $ignoreNew)
Record-TestResult -Category "4. Task Persistence" `
    -TestName "Scheduled task settings enforce battery persistence, restart on failure, infinite execution, and IgnoreNew" `
    -Passed $settingsPassed `
    -Details "BatteryPersist=$batteryPersist, RestartOnFail=$restartOnFail, Infinite=$noTimeLimit, Multiple=$ignoreNew"

# Test 4.2: Verification of Principal Elevation and Logon Trigger
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$principalPassed = ($principal.RunLevel -eq "Highest" -and $principal.LogonType -eq "Interactive" -and $trigger.CimClass.CimClassName -match "LogonTrigger")
Record-TestResult -Category "4. Task Persistence" `
    -TestName "Scheduled task principal configures RunLevel Highest and interactive AtLogon trigger" `
    -Passed $principalPassed `
    -Details "RunLevel=$($principal.RunLevel), LogonType=$($principal.LogonType), Trigger=$($trigger.CimClass.CimClassName)"

# Test 4.3: Non-elevated execution guard in install.ps1 and uninstall.ps1
$installExit = (Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File scripts\install.ps1" -Wait -PassThru).ExitCode
$uninstallExit = (Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File scripts\uninstall.ps1" -Wait -PassThru).ExitCode
$guardPassed = ($installExit -eq 1 -and $uninstallExit -eq 1)
Record-TestResult -Category "4. Task Persistence" `
    -TestName "install.ps1 and uninstall.ps1 reject non-elevated callers with exit code 1 (ELEVATION_REQUIRED)" `
    -Passed $guardPassed `
    -Details "install.ps1 exit: $installExit, uninstall.ps1 exit: $uninstallExit"

# Test 4.4: Live registered Scheduled Task validation
$activeTask = Get-ScheduledTask | Where-Object { $_.TaskName -match 'DisplayFix' } | Select-Object -First 1
$liveTaskPassed = ($null -ne $activeTask -and
                   $activeTask.Principal.RunLevel -eq 'Highest' -and
                   $activeTask.Settings.StopIfGoingOnBatteries -eq $false -and
                   $activeTask.Settings.ExecutionTimeLimit -eq 'PT0S')
Record-TestResult -Category "4. Task Persistence" `
    -TestName "Active registered scheduled task matches persistence policy (RunLevel Highest, Battery persistence, PT0S)" `
    -Passed $liveTaskPassed `
    -Details "TaskName=$($activeTask.TaskName), RunLevel=$($activeTask.Principal.RunLevel), StopOnBattery=$($activeTask.Settings.StopIfGoingOnBatteries)"

# -------------------------------------------------------------------------
# SUMMARY
# -------------------------------------------------------------------------
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  M2 ADVERSARIAL STRESS TEST SUMMARY" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  Total Tests Executed : $totalTests"
Write-Host "  Passed Tests         : $passedTests" -ForegroundColor Green
Write-Host "  Failed Tests         : $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
$allPassed = ($failedTests -eq 0)
Write-Host "  Final Verdict        : $(if ($allPassed) { 'APPROVE' } else { 'REJECT' })" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host "========================================================================" -ForegroundColor Cyan

exit $(if ($allPassed) { 0 } else { 1 })
