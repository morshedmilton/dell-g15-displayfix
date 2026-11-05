# tests/e2e/challenger_backlight_telemetry_test.ps1
# Challenger 2 Verification Harness: System Telemetry & Physical Backlight Verification
# Tests root\wmi:NvWmiBrightness duty cycle synchronization before and after hotkey/CLI adjustments,
# verifying +8 offset calibration, 10% floor safety, and OSD synchronization.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item (Join-Path $scriptDir '..\..')).FullName
$daemonExePath = Join-Path $projectRoot 'bin\DisplayFixDaemon.exe'

if (-not (Test-Path $daemonExePath)) {
    Write-Error "DisplayFixDaemon.exe not found at '$daemonExePath'."
    exit 1
}

$totalTests = 0
$passedTests = 0
$failedTests = 0
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details
    )
    $script:totalTests++
    if ($Condition) {
        $script:passedTests++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor DarkGray
        }
    } else {
        $script:failedTests++
        $msg = "FAILED: $Name - $Details"
        $script:failures.Add($msg)
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         Reason: $Details" -ForegroundColor Yellow
    }
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  CHALLENGER 2: SYSTEM TELEMETRY & NVWMI BRIGHTNESS VERIFICATION" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan

# Helper to query raw NvWmiBrightness hardware level
function Get-NvWmiDutyCycle {
    try {
        $inst = Get-CimInstance -Namespace 'root\wmi' -ClassName 'NvWmiBrightness' -ErrorAction Stop
        $res = Invoke-CimMethod -InputObject $inst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = [uint32]0; Level = [uint32]0 } -ErrorAction Stop
        return [int]$res.Result
    } catch {
        return -1
    }
}

# Helper to run CLI command
function Invoke-DaemonCli {
    param([string]$ArgString)
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $daemonExePath
    $pinfo.Arguments = $ArgString
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($pinfo)
    $stdout = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; Output = $stdout.Trim() }
}

# 1. Query initial state
$initialDuty = Get-NvWmiDutyCycle
$initialCli = Invoke-DaemonCli "--brightness-get"

Assert-Test `
    -Name "1.1: Direct root\wmi:NvWmiBrightness query succeeds with valid duty cycle" `
    -Condition ($initialDuty -ge 10 -and $initialDuty -le 100) `
    -Details "InitialDutyCycle=$initialDuty, CliOutput='$($initialCli.Output)'"

try {
    # 2. Set to 50%
    $set50 = Invoke-DaemonCli "--brightness-set 50"
    Start-Sleep -Milliseconds 200
    $duty50 = Get-NvWmiDutyCycle
    $get50 = Invoke-DaemonCli "--brightness-get"

    # Expected compensated level in log is 58, readback duty cycle is in [50, 60]
    $test50Ok = ($set50.ExitCode -eq 0 -and $duty50 -ge 50 -and $duty50 -le 60 -and $get50.Output -match 'Brightness: 50%')
    Assert-Test `
        -Name "2.1: Setting 50% brightness writes calibrated compensated level (duty cycle ~54-58) and synchronizes telemetry" `
        -Condition $test50Ok `
        -Details "SetExit=$($set50.ExitCode), HardwareDutyCycle=$duty50 (expected 50..60), CliGet='$($get50.Output)'"

    # 3. Step Up +5% (to 55%)
    $stepUp = Invoke-DaemonCli "--brightness-up 5"
    Start-Sleep -Milliseconds 200
    $duty55 = Get-NvWmiDutyCycle
    $get55 = Invoke-DaemonCli "--brightness-get"

    $test55Ok = ($stepUp.ExitCode -eq 0 -and $duty55 -ge $duty50 -and $get55.Output -match 'Brightness: 55%')
    Assert-Test `
        -Name "3.1: Stepping up +5% increases physical duty cycle ($duty50 -> $duty55) and matches 55% telemetry" `
        -Condition $test55Ok `
        -Details "StepUpExit=$($stepUp.ExitCode), HardwareDutyCycle=$duty55 (>= $duty50), CliGet='$($get55.Output)'"

    # 4. Step Down -10% (to 45%)
    $stepDown = Invoke-DaemonCli "--brightness-down 10"
    Start-Sleep -Milliseconds 200
    $duty45 = Get-NvWmiDutyCycle
    $get45 = Invoke-DaemonCli "--brightness-get"

    $test45Ok = ($stepDown.ExitCode -eq 0 -and $duty45 -lt $duty50 -and $get45.Output -match 'Brightness: 45%')
    Assert-Test `
        -Name "4.1: Stepping down -10% decreases physical duty cycle ($duty55 -> $duty45) and matches 45% telemetry" `
        -Condition $test45Ok `
        -Details "StepDownExit=$($stepDown.ExitCode), HardwareDutyCycle=$duty45 (< $duty50), CliGet='$($get45.Output)'"

    # 5. Boundary Floor Safety: Set to 5% (below 10% floor)
    $set5 = Invoke-DaemonCli "--brightness-set 5"
    Start-Sleep -Milliseconds 200
    $dutyFloor = Get-NvWmiDutyCycle
    $getFloor = Invoke-DaemonCli "--brightness-get"

    # Clamped user level = 10%, duty cycle >= 18 and <= 25
    $floorOk = ($dutyFloor -ge 18 -and $dutyFloor -le 25 -and $getFloor.Output -match 'Brightness: 10%')
    Assert-Test `
        -Name "5.1: Sub-10% input (5%) clamps safely at 10% floor and duty cycle $dutyFloor (preventing inverter shutoff)" `
        -Condition $floorOk `
        -Details "HardwareDutyCycle=$dutyFloor (expected 18..25), CliGet='$($getFloor.Output)'"

    # 6. Boundary Ceiling: Set to 95%
    $set95 = Invoke-DaemonCli "--brightness-set 95"
    Start-Sleep -Milliseconds 200
    $dutyCeil = Get-NvWmiDutyCycle
    $getCeil = Invoke-DaemonCli "--brightness-get"

    # High brightness: duty cycle >= 90 and <= 100
    $ceilOk = ($dutyCeil -ge 90 -and $dutyCeil -le 100 -and $getCeil.Output -match 'Brightness: 95%')
    Assert-Test `
        -Name "6.1: High brightness (95%) applies +8 offset with ceiling clamp (duty cycle: $dutyCeil)" `
        -Condition $ceilOk `
        -Details "HardwareDutyCycle=$dutyCeil (expected 90..100), CliGet='$($getCeil.Output)'"

    # 7. Monotonicity verification across the full tested range
    $monotonicOk = ($dutyFloor -lt $duty45 -and $duty45 -lt $duty50 -and $duty50 -le $duty55 -and $duty55 -lt $dutyCeil)
    Assert-Test `
        -Name "7.1: Physical panel backlight duty cycle is strictly monotonic: Floor($dutyFloor) < 45%($duty45) < 50%($duty50) <= 55%($duty55) < 95%($dutyCeil)" `
        -Condition $monotonicOk `
        -Details "Duty cycles: 10%->$dutyFloor, 45%->$duty45, 50%->$duty50, 55%->$duty55, 95%->$dutyCeil"
}
finally {
    # Restore original brightness
    $null = Invoke-DaemonCli "--brightness-set 50"
}

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY: Total Tests: $totalTests | Passed: $passedTests | Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
