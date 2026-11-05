# tests/e2e/challenger_media_passthrough_test.ps1
# Challenger 2 Verification Harness: Media Key Coexistence & Passthrough
# Tests F6/F7 non-interference with function keys (F1-F3, F4-F5, F8, F9 G-Key, F10-F12),
# modifier bypass, keyup symmetry, anti-recursion, and G-Key passthrough configuration.

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

$assembly = [System.Reflection.Assembly]::LoadFrom($daemonExePath)
[DisplayFix.Common.Logger]::EchoToConsole = $false

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
Write-Host "  CHALLENGER 2: MEDIA KEY COEXISTENCE & PASSTHROUGH VERIFICATION" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan

$tempIniDir = Join-Path ([System.IO.Path]::GetTempPath()) ("DisplayFix_ChalMedia_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempIniDir -Force | Out-Null
$tempIniPath = Join-Path $tempIniDir "hotkeys.ini"

try {
    # 1. Instantiate test HotkeyHook instance
    $hook = New-Object DisplayFix.Brightness.HotkeyHook($tempIniPath)
    $activeInstField = [DisplayFix.Brightness.HotkeyHook].GetField('_activeInstance', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
    $activeInstField.SetValue($null, $hook)

    $cbMethod = [DisplayFix.Brightness.HotkeyHook].GetMethod(
        'LowLevelKeyboardHookCallback',
        [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
    )

    $pKbd = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(24)

    # Helper function to invoke hook callback
    function Invoke-Hook {
        param([int]$vk, [int]$msg, [int]$flags = 0, [IntPtr]$extraInfo = [IntPtr]::Zero)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 0, $vk)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 4, 0)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 8, $flags)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 12, 0)
        [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pKbd, 16, $extraInfo)
        $res = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]$msg, $pKbd))
        return $res.ToInt64()
    }

    # -------------------------------------------------------------------------
    # SUITE 1: Unclaimed Function Keys Pure Passthrough
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 1: Non-Brightness & Unclaimed Function Keys Passthrough ---" -ForegroundColor Yellow

    # Function keys that MUST pass through untouched: F4 (0x73), F5 (0x74), F8 (0x77), F10 (0x79), F11 (0x7A), F12 (0x7B)
    $unclaimedKeys = @(
        @{ Name = "F4";  Vk = 0x73 },
        @{ Name = "F5";  Vk = 0x74 },
        @{ Name = "F8";  Vk = 0x77 },
        @{ Name = "F10"; Vk = 0x79 },
        @{ Name = "F11"; Vk = 0x7A },
        @{ Name = "F12"; Vk = 0x7B }
    )

    $allUnclaimedPassed = $true
    $unclaimedDetails = @()

    foreach ($k in $unclaimedKeys) {
        $downRes = Invoke-Hook -vk $k.Vk -msg 0x0100 # WM_KEYDOWN
        $upRes   = Invoke-Hook -vk $k.Vk -msg 0x0101 # WM_KEYUP
        $pred    = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $false, $false, $false, $false)

        if ($downRes -ne 0 -or $upRes -ne 0 -or $pred -ne $false) {
            $allUnclaimedPassed = $false
        }
        $unclaimedDetails += "$($k.Name)(Down=$downRes,Up=$upRes,Pred=$pred)"
    }

    Assert-Test `
        -Name "1.1: Unclaimed function keys (F4, F5, F8, F10, F11, F12) pass through untouched (Hook=0, Pred=False)" `
        -Condition $allUnclaimedPassed `
        -Details ($unclaimedDetails -join ", ")

    # -------------------------------------------------------------------------
    # SUITE 2: Modifier Key Bypass for Brightness and Media Keys
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 2: Modifier Combinations Passthrough (Ctrl, Alt, Shift, Win) ---" -ForegroundColor Yellow

    # When Ctrl, Alt, Shift, or Win are held down, F6, F7, F1, F2, F3, F9 must NOT be swallowed!
    $claimedKeys = @(
        @{ Name = "F6 (BrightnessDown)"; Vk = 0x75 },
        @{ Name = "F7 (BrightnessUp)";   Vk = 0x76 },
        @{ Name = "F1 (Mute)";           Vk = 0x70 },
        @{ Name = "F2 (VolDown)";        Vk = 0x71 },
        @{ Name = "F3 (VolUp)";          Vk = 0x72 },
        @{ Name = "F9 (PlayPause/G-Key)";Vk = 0x78 }
    )

    $allModifiersPassed = $true
    $modDetails = @()

    foreach ($k in $claimedKeys) {
        # Test Alt held via LLKHF_ALTDOWN (0x20)
        $altDownRes = Invoke-Hook -vk $k.Vk -msg 0x0104 -flags 0x20 # WM_SYSKEYDOWN with LLKHF_ALTDOWN
        $altUpRes   = Invoke-Hook -vk $k.Vk -msg 0x0105 -flags 0x20 # WM_SYSKEYUP with LLKHF_ALTDOWN

        # Test ShouldInterceptKey with all modifier variations
        $ctrlPred  = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $true,  $false, $false, $false)
        $altPred   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $false, $true,  $false, $false)
        $shiftPred = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $false, $false, $true,  $false)
        $winPred   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $false, $false, $false, $true)
        $multiPred = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey($k.Vk, $true,  $false, $true,  $false)

        if ($altDownRes -ne 0 -or $altUpRes -ne 0 -or
            $ctrlPred -ne $false -or $altPred -ne $false -or
            $shiftPred -ne $false -or $winPred -ne $false -or $multiPred -ne $false) {
            $allModifiersPassed = $false
        }
        $modDetails += "$($k.Name)(AltHook=$altDownRes,CtrlPred=$ctrlPred,ShiftPred=$shiftPred,WinPred=$winPred)"
    }

    Assert-Test `
        -Name "2.1: Modifiers (Ctrl, Alt, Shift, Win) guarantee 100% passthrough for F6, F7, F1, F2, F3, F9" `
        -Condition $allModifiersPassed `
        -Details ($modDetails -join "; ")

    # -------------------------------------------------------------------------
    # SUITE 3: Media Key Synthesis & Keyup Symmetry
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 3: Media Key Synthesis Accuracy & Swallow Symmetry ---" -ForegroundColor Yellow

    # Check TotalMediaEvents before and after
    $totalMediaBefore = $hook.TotalMediaEvents

    # Test F1 -> 0xAD (VK_VOLUME_MUTE)
    $f1Down = Invoke-Hook -vk 0x70 -msg 0x0100
    $f1Up   = Invoke-Hook -vk 0x70 -msg 0x0101

    # Test F2 -> 0xAE (VK_VOLUME_DOWN)
    $f2Down = Invoke-Hook -vk 0x71 -msg 0x0100
    $f2Up   = Invoke-Hook -vk 0x71 -msg 0x0101

    # Test F3 -> 0xAF (VK_VOLUME_UP)
    $f3Down = Invoke-Hook -vk 0x72 -msg 0x0100
    $f3Up   = Invoke-Hook -vk 0x72 -msg 0x0101

    # Test F9 -> 0xB3 (VK_MEDIA_PLAY_PAUSE)
    $f9Down = Invoke-Hook -vk 0x78 -msg 0x0100
    $f9Up   = Invoke-Hook -vk 0x78 -msg 0x0101

    # Allow async ThreadPool synthesis to complete
    Start-Sleep -Milliseconds 250
    $totalMediaAfter = $hook.TotalMediaEvents
    $totalMediaDispatched = $totalMediaAfter - $totalMediaBefore

    $swallowSymmetryOk = (
        $f1Down -eq 1 -and $f1Up -eq 1 -and
        $f2Down -eq 1 -and $f2Up -eq 1 -and
        $f3Down -eq 1 -and $f3Up -eq 1 -and
        $f9Down -eq 1 -and $f9Up -eq 1
    )

    $allMediaDispatched = ($totalMediaDispatched -eq 4)
    $f1ActionVk = [DisplayFix.Brightness.HotkeyHook]::ActionToMediaVk([DisplayFix.Brightness.HotkeyActionType]::VolumeMute)
    $f2ActionVk = [DisplayFix.Brightness.HotkeyHook]::ActionToMediaVk([DisplayFix.Brightness.HotkeyActionType]::VolumeDown)
    $f3ActionVk = [DisplayFix.Brightness.HotkeyHook]::ActionToMediaVk([DisplayFix.Brightness.HotkeyActionType]::VolumeUp)
    $f9ActionVk = [DisplayFix.Brightness.HotkeyHook]::ActionToMediaVk([DisplayFix.Brightness.HotkeyActionType]::MediaPlayPause)

    $mediaCodesOk = (
        $f1ActionVk -eq 0xAD -and
        $f2ActionVk -eq 0xAE -and
        $f3ActionVk -eq 0xAF -and
        $f9ActionVk -eq 0xB3 -and
        $allMediaDispatched
    )

    Assert-Test `
        -Name "3.1: F1, F2, F3, F9 keydown and keyup are symmetrically swallowed (Hook=1)" `
        -Condition $swallowSymmetryOk `
        -Details "F1($f1Down,$f1Up), F2($f2Down,$f2Up), F3($f3Down,$f3Up), F9($f9Down,$f9Up)"

    Assert-Test `
        -Name "3.2: Asynchronous SendInput media synthesis emits correct VK codes (0xAD, 0xAE, 0xAF, 0xB3) across 4 events" `
        -Condition $mediaCodesOk `
        -Details "TotalMediaDispatched=$totalMediaDispatched, F1=0x$($f1ActionVk.ToString('X2')), F2=0x$($f2ActionVk.ToString('X2')), F3=0x$($f3ActionVk.ToString('X2')), F9=0x$($f9ActionVk.ToString('X2'))"

    # -------------------------------------------------------------------------
    # SUITE 4: F9 Dell G-Key Passthrough Coexistence & Unbinding
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 4: F9 Dell G-Key Configuration Dynamics ---" -ForegroundColor Yellow

    # Investigation: How does unbinding F9 affect passthrough?
    # When _vkDispatchTable[0x78] is cleared (ClearActionBinding):
    $clearMethod = [DisplayFix.Brightness.HotkeyHook].GetMethod(
        'ClearActionBinding',
        [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance
    )
    $clearMethod.Invoke($hook, @([DisplayFix.Brightness.HotkeyActionType]::MediaPlayPause))

    $f9UnboundPred = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x78, $false, $false, $false, $false)
    $f9UnboundDown = Invoke-Hook -vk 0x78 -msg 0x0100
    $f9UnboundUp   = Invoke-Hook -vk 0x78 -msg 0x0101

    # Brightness hotkeys F6/F7 and media keys F1-F3 must still remain fully active!
    $f6StillActive = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x75, $false, $false, $false, $false)
    $f7StillActive = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x76, $false, $false, $false, $false)
    $f1StillActive = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x70, $false, $false, $false, $false)

    $gKeyPassthroughOk = (
        $f9UnboundPred -eq $false -and
        $f9UnboundDown -eq 0 -and
        $f9UnboundUp -eq 0 -and
        $f6StillActive -eq $true -and
        $f7StillActive -eq $true -and
        $f1StillActive -eq $true
    )

    Assert-Test `
        -Name "4.1: When MediaPlayPause is unbound, raw F9 (Dell G-Key) passes through untouched (Hook=0, Pred=False)" `
        -Condition $gKeyPassthroughOk `
        -Details "F9(Pred=$f9UnboundPred,Down=$f9UnboundDown,Up=$f9UnboundUp), F6Active=$f6StillActive, F7Active=$f7StillActive, F1Active=$f1StillActive"

    # Restore default table
    $hook.InitializeDefaultDispatchTable()

    # -------------------------------------------------------------------------
    # SUITE 5: Anti-Recursion on Synthetic Events (DISPLAYFIX_SYNTHETIC_EXTRA_INFO)
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 5: Synthetic Anti-Recursion Guard ---" -ForegroundColor Yellow

    $synthExtra = [DisplayFix.Daemon.Interop]::DISPLAYFIX_SYNTHETIC_EXTRA_INFO
    $synthDown = Invoke-Hook -vk 0x75 -msg 0x0100 -extraInfo $synthExtra
    $synthUp   = Invoke-Hook -vk 0x75 -msg 0x0101 -extraInfo $synthExtra

    $antiRecursionOk = ($synthDown -eq 0 -and $synthUp -eq 0)
    Assert-Test `
        -Name "5.1: Keystrokes with DISPLAYFIX_SYNTHETIC_EXTRA_INFO (0x44464958) are ignored by hook (Hook=0)" `
        -Condition $antiRecursionOk `
        -Details "SynthDown=$synthDown, SynthUp=$synthUp, ExtraInfo=0x$($synthExtra.ToInt64().ToString('X8'))"

    # -------------------------------------------------------------------------
    # SUITE 6: Hook Callback Execution Latency Benchmark
    # -------------------------------------------------------------------------
    Write-Host "`n--- SUITE 6: Hook Callback Execution Latency Benchmark ---" -ForegroundColor Yellow

    $latencies = [System.Collections.Generic.List[double]]::new(200)
    for ($i = 0; $i -lt 200; $i++) {
        # Alternate between swallowed F6 and passed-through F4
        $vk = if (($i % 2) -eq 0) { 0x75 } else { 0x73 }
        $t0 = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $ret = Invoke-Hook -vk $vk -msg 0x0100
        $t1 = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $null = Invoke-Hook -vk $vk -msg 0x0101

        $us = (($t1 - $t0) * 1000000.0) / [System.Diagnostics.Stopwatch]::Frequency
        $latencies.Add($us)
    }

    $sorted = [System.Collections.Generic.List[double]]::new($latencies)
    $sorted.Sort()
    $p50 = $sorted[[int][math]::Floor($sorted.Count * 0.50)]
    $p95 = $sorted[[int][math]::Floor($sorted.Count * 0.95)]
    $p99 = $sorted[[int][math]::Floor($sorted.Count * 0.99)]
    $maxUs = $sorted[$sorted.Count - 1]

    # Hook budget is 5000 us (5 ms). We expect well under 500 us in practice.
    $latencyPass = ($p95 -lt 1000.0 -and $maxUs -lt 5000.0)
    Assert-Test `
        -Name "6.1: 200 hook callbacks latency < 5.0ms budget (P50: $([math]::Round($p50, 1))us, P95: $([math]::Round($p95, 1))us, Max: $([math]::Round($maxUs, 1))us)" `
        -Condition $latencyPass `
        -Details "P50=$([math]::Round($p50, 1))us, P95=$([math]::Round($p95, 1))us, P99=$([math]::Round($p99, 1))us, Max=$([math]::Round($maxUs, 1))us"

    $hook.Dispose()
}
finally {
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pKbd)
    if (Test-Path $tempIniDir) {
        Remove-Item -Path $tempIniDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY: Total Tests: $totalTests | Passed: $passedTests | Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
