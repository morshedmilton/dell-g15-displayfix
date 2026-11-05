# tests/e2e/tier5_adversarial/adversarial_m4_brightness_osd_test.ps1
# Tier 5 Adversarial Stress & Invariant Test Suite for Milestone 4
# F6/F7 Hotkey Interception (F10), NVIDIA WMI Brightness Backend (F11),
# Optimus WMI Brightness Backend (F12), Function Row Media Key Preservation (F13),
# Non-Activating Acrylic OSD Overlay (F14), Boundary B01, Combinations C03/C05, Scenario S01.

[CmdletBinding()]
param(
    [switch]$DetailedOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item (Join-Path $scriptDir '..\..\..')).FullName
$daemonExePath = Join-Path $projectRoot 'bin\DisplayFixDaemon.exe'

if (-not (Test-Path $daemonExePath)) {
    Write-Error "DisplayFixDaemon.exe not found at '$daemonExePath'. Run build.ps1 first."
    exit 1
}

# Load the compiled assembly for in-process reflection, struct layout, and API testing
$assembly = [System.Reflection.Assembly]::LoadFrom($daemonExePath)
[DisplayFix.Common.Logger]::EchoToConsole = $false

# Helper Win32 P/Invoke for GDI/USER object leak tracking (GetGuiResources)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DisplayFix.AdversarialM4
{
    public static class GuiResourceTracker
    {
        public const uint GR_GDIOBJECTS  = 0;
        public const uint GR_USEROBJECTS = 1;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
    }
}
"@

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
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor DarkGray
        }
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] ${TestName}" -ForegroundColor Red
        Write-Host "         Reason: $Details" -ForegroundColor Yellow
    }
    $script:testResults.Add([PSCustomObject]@{
        Category = $Category
        TestName = $TestName
        Passed   = $Passed
        Details  = $Details
    })
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  MILESTONE 4: ADVERSARIAL BRIGHTNESS, HOTKEY & ACRYLIC OSD TEST SUITE" -ForegroundColor White
Write-Host "  Target: HotkeyHook, BrightnessController, AcrylicOsdWindow, Interop" -ForegroundColor DarkGray
Write-Host "  Timestamp: $(Get-Date -Format 'u')" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# SUITE 1: x64 Struct Marshaling Byte Sizes & Field Offsets
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 1: x64 Struct Marshaling Byte Sizes & Field Offsets ---" -ForegroundColor Yellow

$interopType = $assembly.GetType('DisplayFix.Daemon.Interop')
$osdType     = $assembly.GetType('DisplayFix.Brightness.AcrylicOsdWindow')

function Get-StructSize {
    param([Type]$Type)
    return [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Type)
}

function Get-FieldOffset {
    param([Type]$Type, [string]$FieldName)
    return [System.Runtime.InteropServices.Marshal]::OffsetOf([Type]$Type, [string]$FieldName).ToInt32()
}

$tInput         = $interopType.GetNestedType('INPUT')
$tMouseInput    = $interopType.GetNestedType('MOUSEINPUT')
$tKeybdInput    = $interopType.GetNestedType('KEYBDINPUT')
$tHardwareInput = $interopType.GetNestedType('HARDWAREINPUT')
$tKbdLlHook     = $interopType.GetNestedType('KBDLLHOOKSTRUCT')
$tRawInputDev   = $interopType.GetNestedType('RAWINPUTDEVICE')
$tRawInputHdr   = $interopType.GetNestedType('RAWINPUTHEADER')
$tAccentPolicy  = $osdType.GetNestedType('ACCENT_POLICY')
$tWinCompData   = $osdType.GetNestedType('WINDOWCOMPOSITIONATTRIBDATA')

$szInput         = Get-StructSize $tInput
$szMouseInput    = Get-StructSize $tMouseInput
$szKeybdInput    = Get-StructSize $tKeybdInput
$szHardwareInput = Get-StructSize $tHardwareInput
$szKbdLlHook     = Get-StructSize $tKbdLlHook
$szRawInputDev   = Get-StructSize $tRawInputDev
$szRawInputHdr   = Get-StructSize $tRawInputHdr
$szAccentPolicy  = Get-StructSize $tAccentPolicy
$szWinCompData   = Get-StructSize $tWinCompData

$offInputType    = Get-FieldOffset $tInput 'type'
$offInputUnion   = Get-FieldOffset $tInput 'u'

# Test 1.1: Interop.INPUT x64 struct size == 40 bytes and union offset == 8
$inputAbiPass = (
    $szInput -eq 40 -and
    $szMouseInput -eq 32 -and
    $szKeybdInput -eq 24 -and
    $szHardwareInput -eq 8 -and
    $offInputType -eq 0 -and
    $offInputUnion -eq 8
)
Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.1: Interop.INPUT size is exactly 40 bytes on x64 (type@0, union@8, MOUSEINPUT=32B, KEYBDINPUT=24B)" `
    -Passed $inputAbiPass `
    -Details "INPUT=$szInput(40), type@$offInputType(0), u@$offInputUnion(8), MOUSEINPUT=$szMouseInput(32), KEYBDINPUT=$szKeybdInput(24), HARDWAREINPUT=$szHardwareInput(8)"

# Test 1.2: KBDLLHOOKSTRUCT, RAWINPUTDEVICE, RAWINPUTHEADER, ACCENT_POLICY, WINDOWCOMPOSITIONATTRIBDATA sizes & offsets
$offKbdVk     = Get-FieldOffset $tKbdLlHook 'vkCode'
$offKbdScan   = Get-FieldOffset $tKbdLlHook 'scanCode'
$offKbdFlags  = Get-FieldOffset $tKbdLlHook 'flags'
$offKbdTime   = Get-FieldOffset $tKbdLlHook 'time'
$offKbdExtra  = Get-FieldOffset $tKbdLlHook 'dwExtraInfo'

$offRidPage   = Get-FieldOffset $tRawInputDev 'usUsagePage'
$offRidUsage  = Get-FieldOffset $tRawInputDev 'usUsage'
$offRidFlags  = Get-FieldOffset $tRawInputDev 'dwFlags'
$offRidHwnd   = Get-FieldOffset $tRawInputDev 'hwndTarget'

$offAccState  = Get-FieldOffset $tAccentPolicy 'AccentState'
$offAccFlags  = Get-FieldOffset $tAccentPolicy 'AccentFlags'
$offAccGrad   = Get-FieldOffset $tAccentPolicy 'GradientColor'
$offAccAnim   = Get-FieldOffset $tAccentPolicy 'AnimationId'

$hookAndOsdStructsPass = (
    $szKbdLlHook -eq 24 -and
    $offKbdVk -eq 0 -and $offKbdScan -eq 4 -and $offKbdFlags -eq 8 -and $offKbdTime -eq 12 -and $offKbdExtra -eq 16 -and
    $szRawInputDev -eq 16 -and
    $offRidPage -eq 0 -and $offRidUsage -eq 2 -and $offRidFlags -eq 4 -and $offRidHwnd -eq 8 -and
    $szRawInputHdr -eq 24 -and
    $szAccentPolicy -eq 16 -and
    $offAccState -eq 0 -and $offAccFlags -eq 4 -and $offAccGrad -eq 8 -and $offAccAnim -eq 12 -and
    $szWinCompData -eq 24
)
Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.2: KBDLLHOOKSTRUCT (24B), RAWINPUTDEVICE (16B), RAWINPUTHEADER (24B), ACCENT_POLICY (16B), WINDOWCOMPOSITIONATTRIBDATA (24B) match Win32 x64 ABI" `
    -Passed $hookAndOsdStructsPass `
    -Details "KBDLLHOOKSTRUCT=$szKbdLlHook(0,4,8,12,16), RAWINPUTDEVICE=$szRawInputDev(0,2,4,8), RAWINPUTHEADER=$szRawInputHdr, ACCENT_POLICY=$szAccentPolicy(0,4,8,12), WINCOMPDATA=$szWinCompData"

# -------------------------------------------------------------------------
# SUITE 2: HotkeyHook Modifier Bypass, Anti-Recursion, Config & Latency
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 2: HotkeyHook Adversarial Verification ---" -ForegroundColor Yellow

$tempIniDir = Join-Path ([System.IO.Path]::GetTempPath()) ("DisplayFix_Adversarial_M4_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempIniDir -Force | Out-Null
$tempIniPath = Join-Path $tempIniDir "hotkeys.ini"

try {
    $hook = New-Object DisplayFix.Brightness.HotkeyHook($tempIniPath)

    # Set _activeInstance via reflection so static callback/ShouldInterceptKey uses our test instance
    $activeInstField = [DisplayFix.Brightness.HotkeyHook].GetField('_activeInstance', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
    $activeInstField.SetValue($null, $hook)

    # Test 2.1: ShouldInterceptKey exhaustive modifier bypass combinations
    $plainF6   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x75, $false, $false, $false, $false)
    $plainF7   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x76, $false, $false, $false, $false)
    $plainF1   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x70, $false, $false, $false, $false)
    $plainF2   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x71, $false, $false, $false, $false)
    $plainF3   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x72, $false, $false, $false, $false)
    $plainF9   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x78, $false, $false, $false, $false)

    $ctrlF6    = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x75, $true,  $false, $false, $false)
    $altF7     = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x76, $false, $true,  $false, $false)
    $shiftF6   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x75, $false, $false, $true,  $false)
    $winF7     = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x76, $false, $false, $false, $true)
    $ctrlAltF6 = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x75, $true,  $true,  $false, $false)
    $shiftF1   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x70, $false, $false, $true,  $false)
    $altF9     = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x78, $false, $true,  $false, $false)

    # Fallback chord Ctrl+Alt+Up (0x26) / Down (0x28)
    $chordUp   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x26, $true,  $true,  $false, $false)
    $chordDown = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x28, $true,  $true,  $false, $false)
    $plainUp   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x26, $false, $false, $false, $false)

    # Unclaimed keys (F4=0x73, F5=0x74, F8=0x77, F10=0x79, F12=0x7B, OOB=-1, 300)
    $plainF4   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x73, $false, $false, $false, $false)
    $plainF5   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x74, $false, $false, $false, $false)
    $plainF8   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x77, $false, $false, $false, $false)
    $plainF12  = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(0x7B, $false, $false, $false, $false)
    $oobNeg    = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(-1,   $false, $false, $false, $false)
    $oobHigh   = [DisplayFix.Brightness.HotkeyHook]::ShouldInterceptKey(300,  $false, $false, $false, $false)

    $modBypassPass = (
        $plainF6 -eq $true -and $plainF7 -eq $true -and
        $plainF1 -eq $true -and $plainF2 -eq $true -and $plainF3 -eq $true -and $plainF9 -eq $true -and
        $ctrlF6 -eq $false -and $altF7 -eq $false -and $shiftF6 -eq $false -and $winF7 -eq $false -and
        $ctrlAltF6 -eq $false -and $shiftF1 -eq $false -and $altF9 -eq $false -and
        $chordUp -eq $true -and $chordDown -eq $true -and $plainUp -eq $false -and
        $plainF4 -eq $false -and $plainF5 -eq $false -and $plainF8 -eq $false -and $plainF12 -eq $false -and
        $oobNeg -eq $false -and $oobHigh -eq $false
    )
    Record-TestResult `
        -Category "Suite 2: HotkeyHook" `
        -TestName "2.1: ShouldInterceptKey intercepts plain F6/F7/F1-F3/F9, bypasses all Ctrl/Alt/Shift/Win modifiers, and rejects unclaimed/OOB keys" `
        -Passed $modBypassPass `
        -Details "Plain(F6=$plainF6,F7=$plainF7,F1=$plainF1,F2=$plainF2,F3=$plainF3,F9=$plainF9), Mod(Ctrl+F6=$ctrlF6,Alt+F7=$altF7,Shift+F6=$shiftF6,Win+F7=$winF7), Unclaimed(F4=$plainF4,F8=$plainF8,OOB=$oobNeg/$oobHigh)"

    # Test 2.2: DISPLAYFIX_SYNTHETIC_EXTRA_INFO (0x44464958) anti-recursion guard & key-up swallowing symmetry
    $cbMethod = [DisplayFix.Brightness.HotkeyHook].GetMethod(
        'LowLevelKeyboardHookCallback',
        [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
    )

    $pKbd = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(24)
    try {
        $beforeBrEvents = $hook.TotalBrightnessEvents
        $beforeMdEvents = $hook.TotalMediaEvents

        # 1) Synthetic F6 keydown with DISPLAYFIX_SYNTHETIC_EXTRA_INFO (0x44464958) -> MUST NOT intercept (returns 0)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 0, 0x75) # vkCode = VK_F6
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 4, 0)    # scanCode
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 8, 0)    # flags
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 12, 0)   # time
        [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pKbd, 16, [DisplayFix.Daemon.Interop]::DISPLAYFIX_SYNTHETIC_EXTRA_INFO)

        $resSynthF6 = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0100, $pKbd))

        # 2) Synthetic F1 keydown with DISPLAYFIX_SYNTHETIC_EXTRA_INFO -> MUST NOT intercept (returns 0)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 0, 0x70) # vkCode = VK_F1
        $resSynthF1 = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0100, $pKbd))

        Start-Sleep -Milliseconds 30
        $afterSynthBr = $hook.TotalBrightnessEvents
        $afterSynthMd = $hook.TotalMediaEvents

        # 3) Real hardware F6 keydown (dwExtraInfo = 0) -> MUST intercept (returns 1) and swallow matching WM_KEYUP (returns 1)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 0, 0x75) # VK_F6
        [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pKbd, 16, [IntPtr]::Zero)
        $resRealDown = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0100, $pKbd))
        $resRealUp   = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0101, $pKbd))
        # Second WM_KEYUP without prior keydown -> MUST NOT swallow (returns 0)
        $resOrphanUp = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0101, $pKbd))

        $antiRecursionPass = (
            $resSynthF6.ToInt64() -eq 0 -and
            $resSynthF1.ToInt64() -eq 0 -and
            $afterSynthBr -eq $beforeBrEvents -and
            $afterSynthMd -eq $beforeMdEvents -and
            $resRealDown.ToInt64() -eq 1 -and
            $resRealUp.ToInt64() -eq 1 -and
            $resOrphanUp.ToInt64() -eq 0
        )
        Record-TestResult `
            -Category "Suite 2: HotkeyHook" `
            -TestName "2.2: DISPLAYFIX_SYNTHETIC_EXTRA_INFO (0x44464958) prevents recursive hook loops and preserves keydown/keyup swallow symmetry" `
            -Passed $antiRecursionPass `
            -Details "SynthF6Ret=$($resSynthF6.ToInt64())(0), SynthF1Ret=$($resSynthF1.ToInt64())(0), RealKeyDownRet=$($resRealDown.ToInt64())(1), RealKeyUpRet=$($resRealUp.ToInt64())(1), OrphanKeyUpRet=$($resOrphanUp.ToInt64())(0)"

        # Test 2.3: 100 rapid simulated LowLevelKeyboardHookCallback invocations (< 5.0ms budget)
        $latenciesMs = [System.Collections.Generic.List[double]]::new(100)
        for ($i = 0; $i -lt 100; $i++) {
            $vk = if (($i % 2) -eq 0) { 0x75 } else { 0x76 }
            [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 0, $vk)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($pKbd, 8, 0)
            [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pKbd, 16, [IntPtr]::Zero)

            $t0 = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $retDown = [IntPtr]$cbMethod.Invoke($null, @([int]0, [IntPtr]0x0100, $pKbd))
            $t1 = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $null = $cbMethod.Invoke($null, @([int]0, [IntPtr]0x0101, $pKbd))

            $elMs = (($t1 - $t0) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency
            $latenciesMs.Add($elMs)
        }

        $sortedLat = [System.Collections.Generic.List[double]]::new($latenciesMs)
        $sortedLat.Sort()
        $maxLatMs = $sortedLat[$sortedLat.Count - 1]
        $p95LatMs = $sortedLat[[int][math]::Floor($sortedLat.Count * 0.95)]
        $sumLat = 0.0
        foreach ($l in $sortedLat) { $sumLat += $l }
        $avgLatMs = $sumLat / $sortedLat.Count

        $hookLatencyPass = ($maxLatMs -lt 5.0 -and $avgLatMs -lt 1.0 -and $hook.LastCallbackLatencyMicroseconds -lt 5000.0)
        Record-TestResult `
            -Category "Suite 2: HotkeyHook" `
            -TestName "2.3: 100 rapid simulated hook callbacks execute in < 5.0ms (Avg: $([math]::Round($avgLatMs * 1000.0, 1))us, P95: $([math]::Round($p95LatMs * 1000.0, 1))us, Max: $([math]::Round($maxLatMs, 3))ms)" `
            -Passed $hookLatencyPass `
            -Details "100 callbacks: Avg=$([math]::Round($avgLatMs, 4))ms, P95=$([math]::Round($p95LatMs, 4))ms, Max=$([math]::Round($maxLatMs, 4))ms, InternalLastUs=$([math]::Round($hook.LastCallbackLatencyMicroseconds, 1))us"
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pKbd)
    }

    # Test 2.4: hotkeys.ini corruption, empty file, and legacy comment auto-repair
    # Case A: Empty / whitespace file -> auto-repaired with DefaultHotkeysIniContent
    Set-Content -Path $tempIniPath -Value "   `r`n  " -Encoding UTF8
    $hook.EnsureAndLoadConfiguration($tempIniPath)
    $repairedEmptyContent = Get-Content -Path $tempIniPath -Raw

    # Case B: Legacy placeholder file ("Intentionally empty") -> auto-upgraded
    Set-Content -Path $tempIniPath -Value "# Intentionally empty - none by default" -Encoding UTF8
    $hook.EnsureAndLoadConfiguration($tempIniPath)
    $repairedLegacyContent = Get-Content -Path $tempIniPath -Raw

    # Case C: Malformed lines & out-of-bounds Step values (-10, 0, 999, garbage)
    $malformedLines = @(
        "[Hotkeys]",
        "===MALFORMED_LINE===",
        "Step=-10",
        "Step=0",
        "Step=999",
        "Step=NOT_AN_INT",
        "UnknownAction=F6",
        "BrightnessDown=INVALID_KEY_F99",
        "Step=10"
    )
    $hook.ParseIniLines($malformedLines)
    $stepAfterValid = $hook.BrightnessStep
    $hook.ParseIniLines(@("Step=500", "Step=-5"))
    $stepAfterOob = $hook.BrightnessStep
    # Restore default 5% step
    $hook.BrightnessStep = 5

    $iniRepairPass = (
        $repairedEmptyContent -match 'BrightnessDown=F6' -and
        $repairedEmptyContent -match 'BrightnessUp=F7' -and
        $repairedLegacyContent -match 'PlayPause=F9' -and
        $stepAfterValid -eq 10 -and
        $stepAfterOob -eq 10 -and
        $hook.BrightnessStep -eq 5
    )
    Record-TestResult `
        -Category "Suite 2: HotkeyHook" `
        -TestName "2.4: hotkeys.ini empty/legacy files auto-repair and malformed/OOB Step values are safely rejected" `
        -Passed $iniRepairPass `
        -Details "EmptyRepaired=$($repairedEmptyContent -match 'BrightnessDown=F6'), LegacyUpgraded=$($repairedLegacyContent -match 'PlayPause=F9'), StepValid=$stepAfterValid, StepOobIgnored=$($stepAfterOob -eq 10)"

    $hook.Dispose()
}
finally {
    if (Test-Path $tempIniDir) {
        Remove-Item -Path $tempIniDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------------------
# SUITE 3: BrightnessController Clamping, +8 Offset, Arbitration & Transition Queue
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 3: BrightnessController Adversarial Verification ---" -ForegroundColor Yellow

$origBrightness = [DisplayFix.Brightness.BrightnessController]::GetBrightness()
$stateFilePath = [DisplayFix.Brightness.BrightnessController]::StateFilePath
$origStateFileContent = $null
if (Test-Path $stateFilePath) {
    $origStateFileContent = Get-Content -Path $stateFilePath -Raw -ErrorAction SilentlyContinue
}

try {
    # Test 3.1: [10, 100] boundary clamping across extreme inputs (-50, 0, 9, 10, 50, 100, 150, int.MinValue, int.MaxValue)
    $cNeg50  = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(-50)
    $c0      = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(0)
    $c9      = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(9)
    $c10     = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(10)
    $c50     = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(50)
    $c100    = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(100)
    $c150    = [DisplayFix.Brightness.BrightnessController]::ClampBrightness(150)
    $cIntMin = [DisplayFix.Brightness.BrightnessController]::ClampBrightness([int]::MinValue)
    $cIntMax = [DisplayFix.Brightness.BrightnessController]::ClampBrightness([int]::MaxValue)

    $clampPass = (
        $cNeg50 -eq 10 -and $c0 -eq 10 -and $c9 -eq 10 -and $c10 -eq 10 -and
        $c50 -eq 50 -and $c100 -eq 100 -and $c150 -eq 100 -and
        $cIntMin -eq 10 -and $cIntMax -eq 100
    )
    Record-TestResult `
        -Category "Suite 3: BrightnessController" `
        -TestName "3.1: ClampBrightness strictly enforces [10, 100] across (-50, 0, 9, 10, 50, 100, 150, int.MinValue, int.MaxValue)" `
        -Passed $clampPass `
        -Details "-50->$cNeg50, 0->$c0, 9->$c9, 10->$c10, 50->$c50, 100->$c100, 150->$c150, IntMin->$cIntMin, IntMax->$cIntMax"

    # Test 3.2: +8 NVIDIA hardware offset (CalculateNvCompensatedLevel) across boundaries and extremes
    $nvNeg50  = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(-50)
    $nv0      = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(0)
    $nv10     = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(10)
    $nv50     = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(50)
    $nv92     = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(92)
    $nv93     = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(93)
    $nv100    = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(100)
    $nv150    = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel(150)
    $nvIntMin = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel([int]::MinValue)
    $nvIntMax = [DisplayFix.Brightness.BrightnessController]::CalculateNvCompensatedLevel([int]::MaxValue)

    $nvOffsetPass = (
        $nvNeg50 -eq 18 -and $nv0 -eq 18 -and $nv10 -eq 18 -and
        $nv50 -eq 58 -and $nv92 -eq 100 -and $nv93 -eq 100 -and
        $nv100 -eq 100 -and $nv150 -eq 100 -and
        $nvIntMin -eq 18 -and $nvIntMax -eq 100
    )
    Record-TestResult `
        -Category "Suite 3: BrightnessController" `
        -TestName "3.2: CalculateNvCompensatedLevel applies +8 hardware offset and clamps ceiling at 100 without overflow" `
        -Passed $nvOffsetPass `
        -Details "-50->$nvNeg50(18), 0->$nv0(18), 10->$nv10(18), 50->$nv50(58), 92->$nv92(100), 93->$nv93(100), 100->$nv100(100), IntMin->$nvIntMin(18), IntMax->$nvIntMax(100)"

    # Test 3.3: SelectBackend truth-table arbitration & SafeAdjustBrightness zero-provider guard
    $sbNvOnly   = [DisplayFix.Brightness.BrightnessController]::SelectBackend($true,  $false, $true)
    $sbBothNv   = [DisplayFix.Brightness.BrightnessController]::SelectBackend($true,  $true,  $true)
    $sbBothOpt  = [DisplayFix.Brightness.BrightnessController]::SelectBackend($true,  $true,  $false)
    $sbOptOnly  = [DisplayFix.Brightness.BrightnessController]::SelectBackend($false, $true,  $false)
    $sbNvFall   = [DisplayFix.Brightness.BrightnessController]::SelectBackend($true,  $false, $false)
    $sbNone1    = [DisplayFix.Brightness.BrightnessController]::SelectBackend($false, $false, $false)
    $sbNone2    = [DisplayFix.Brightness.BrightnessController]::SelectBackend($false, $false, $true)
    $safeNoProv = [DisplayFix.Brightness.BrightnessController]::SafeAdjustBrightness(50, 0)

    $selectPass = (
        $sbNvOnly  -eq 'NvWmiBrightness' -and
        $sbBothNv  -eq 'NvWmiBrightness' -and
        $sbBothOpt -eq 'WmiMonitorBrightness' -and
        $sbOptOnly -eq 'WmiMonitorBrightness' -and
        $sbNvFall  -eq 'NvWmiBrightness' -and
        $sbNone1   -eq 'NO_ACTIVE_PROVIDER' -and
        $sbNone2   -eq 'NO_ACTIVE_PROVIDER' -and
        $safeNoProv.Success -eq $false -and
        $safeNoProv.Error -eq 'NO_ACTIVE_PROVIDER'
    )
    Record-TestResult `
        -Category "Suite 3: BrightnessController" `
        -TestName "3.3: SelectBackend truth-table arbitration and SafeAdjustBrightness(providers=0) guard behave deterministically" `
        -Passed $selectPass `
        -Details "NV(T,F,T)->$sbNvOnly, BothNV(T,T,T)->$sbBothNv, BothOpt(T,T,F)->$sbBothOpt, Opt(F,T,F)->$sbOptOnly, None->$sbNone1, SafeAdjust(0)->Error=$($safeNoProv.Error)"

    # Test 3.4: Transition queueing (BeginDisplayTransition -> rapid step adjustments -> CompleteDisplayTransition)
    $null = [DisplayFix.Brightness.BrightnessController]::SetBrightness(50)
    [DisplayFix.Brightness.BrightnessController]::BeginDisplayTransition()
    $inTransDuring = [DisplayFix.Brightness.BrightnessController]::IsTransitioning

    # Queue 6 rapid step adjustments while multiplexer transition is active: +5, +5, +10, -5, +5, +5 (net +25 -> 75%)
    $q1 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(5)
    $q2 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(5)
    $q3 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(10)
    $q4 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(-5)
    $q5 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(5)
    $q6 = [DisplayFix.Brightness.BrightnessController]::StepBrightness(5)
    $queuedCountMid = [DisplayFix.Brightness.BrightnessController]::QueuedTransitionStepCount

    $transCompleteRes = [DisplayFix.Brightness.BrightnessController]::CompleteDisplayTransition()
    $inTransAfter = [DisplayFix.Brightness.BrightnessController]::IsTransitioning
    $queuedCountAfter = [DisplayFix.Brightness.BrightnessController]::QueuedTransitionStepCount
    $levelAfterTrans = [DisplayFix.Brightness.BrightnessController]::GetBrightness()

    # Also test transition floor protection: start at 15%, queue -5, -5, -5, -5, -5 -> must clamp at 10% floor
    $null = [DisplayFix.Brightness.BrightnessController]::SetBrightness(15)
    [DisplayFix.Brightness.BrightnessController]::BeginDisplayTransition()
    for ($i = 0; $i -lt 5; $i++) {
        $null = [DisplayFix.Brightness.BrightnessController]::StepBrightness(-5)
    }
    $floorTransRes = [DisplayFix.Brightness.BrightnessController]::CompleteDisplayTransition()

    # Also test StepBrightness with int.MinValue and int.MaxValue (no integer overflow)
    $stepMinRes = [DisplayFix.Brightness.BrightnessController]::StepBrightness([int]::MinValue)
    $stepMaxRes = [DisplayFix.Brightness.BrightnessController]::StepBrightness([int]::MaxValue)

    $transitionPass = (
        $inTransDuring -eq $true -and
        $q1.QueuedDuringTransition -eq $true -and
        $queuedCountMid -eq 6 -and
        $inTransAfter -eq $false -and
        $queuedCountAfter -eq 0 -and
        $transCompleteRes.ClampedUserLevel -eq 75 -and
        $levelAfterTrans -eq 75 -and
        $floorTransRes.ClampedUserLevel -eq 10 -and
        $stepMinRes.ClampedUserLevel -eq 10 -and
        $stepMaxRes.ClampedUserLevel -eq 100
    )
    Record-TestResult `
        -Category "Suite 3: BrightnessController" `
        -TestName "3.4: Transition queueing (BeginDisplayTransition -> rapid steps -> CompleteDisplayTransition) preserves steps, 10% floor, and overflow safety" `
        -Passed $transitionPass `
        -Details "InTrans=$inTransDuring->$inTransAfter, QueuedSteps=$queuedCountMid->$queuedCountAfter, TargetAfter6Steps=$($transCompleteRes.ClampedUserLevel)%(75%), FloorClampAfter5Downs=$($floorTransRes.ClampedUserLevel)%(10%), Step(IntMin/IntMax)=$($stepMinRes.ClampedUserLevel)%/$($stepMaxRes.ClampedUserLevel)%"

    # Test 3.5: brightness.state corruption recovery & persistence round-trip
    $curLevelField = [DisplayFix.Brightness.BrightnessController].GetField('_currentLevel', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)

    # Case A: Sub-floor persisted value (-99) -> clamped to 10%
    Set-Content -Path $stateFilePath -Value "-99" -Encoding UTF8
    $curLevelField.SetValue($null, -1)
    $recSubFloor = [DisplayFix.Brightness.BrightnessController]::GetBrightness()

    # Case B: Super-ceiling persisted value (999) -> clamped to 100%
    Set-Content -Path $stateFilePath -Value "999" -Encoding UTF8
    $curLevelField.SetValue($null, -1)
    $recSuperCeil = [DisplayFix.Brightness.BrightnessController]::GetBrightness()

    # Case C: Corrupted non-numeric garbage -> falls back to hardware or DefaultInitialBrightness [10, 100]
    Set-Content -Path $stateFilePath -Value "CORRUPTED_STATE_DATA_###" -Encoding UTF8
    $curLevelField.SetValue($null, -1)
    $recGarbage = [DisplayFix.Brightness.BrightnessController]::GetBrightness()

    # Case D: Valid SetBrightness(65) persists "65" to disk
    $null = [DisplayFix.Brightness.BrightnessController]::SetBrightness(65)
    $diskVal65 = (Get-Content -Path $stateFilePath -Raw).Trim()

    $persistPass = (
        $recSubFloor -eq 10 -and
        $recSuperCeil -eq 100 -and
        $recGarbage -ge 10 -and $recGarbage -le 100 -and
        $diskVal65 -eq "65"
    )
    Record-TestResult `
        -Category "Suite 3: BrightnessController" `
        -TestName "3.5: brightness.state corruption (-99, 999, garbage) recovers safely into [10, 100] and persists valid levels" `
        -Passed $persistPass `
        -Details "Persisted(-99)->${recSubFloor}%, Persisted(999)->${recSuperCeil}%, Persisted(GARBAGE)->${recGarbage}%, Set(65)->Disk='$diskVal65'"
}
finally {
    # Always restore original brightness and state file
    $null = [DisplayFix.Brightness.BrightnessController]::SetBrightness($origBrightness)
    if ($null -ne $origStateFileContent) {
        Set-Content -Path $stateFilePath -Value $origStateFileContent.Trim() -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------------------
# SUITE 4: AcrylicOsdWindow Extended Styles, Zero Focus Theft & Leak Stress
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 4: AcrylicOsdWindow Adversarial Verification ---" -ForegroundColor Yellow

# Test 4.1: RequiredExStyle == 0x080800A8 and live HWND GetWindowLong(GWL_EXSTYLE) verification
$reqStyle = [DisplayFix.Brightness.AcrylicOsdWindow]::RequiredExStyle
$osd = [DisplayFix.Brightness.AcrylicOsdWindow]::Instance
$osd.ShowOverlayInternal(60, "NVIDIA")
$hwnd = $osd.Handle
$liveExStyle = [DisplayFix.Brightness.AcrylicOsdWindow]::GetWindowLong($hwnd, [DisplayFix.Brightness.AcrylicOsdWindow]::GWL_EXSTYLE)
$styleBitsMatched = (($liveExStyle -band $reqStyle) -eq $reqStyle)

$stylePass = (
    $reqStyle -eq 0x080800A8 -and
    $hwnd -ne [IntPtr]::Zero -and
    $styleBitsMatched -eq $true -and
    $osd.AcrylicApplied -eq $true -and
    $osd.RoundedCornersApplied -eq $true -and
    $osd.PillWidth -eq 260 -and
    $osd.PillHeight -eq 56 -and
    $osd.AutoDismissMs -eq 1500
)
Record-TestResult `
    -Category "Suite 4: AcrylicOsdWindow" `
    -TestName "4.1: AcrylicOsdWindow RequiredExStyle == 0x080800A8 and live HWND GetWindowLong(GWL_EXSTYLE) verifies all 5 non-activating/acrylic flags" `
    -Passed $stylePass `
    -Details "RequiredExStyle=0x$($reqStyle.ToString('X8')), LiveExStyle=0x$($liveExStyle.ToString('X8')), Handle=0x$($hwnd.ToString('X8')), StyleMatch=$styleBitsMatched, Acrylic=$($osd.AcrylicApplied), Rounded=$($osd.RoundedCornersApplied)"

# Test 4.2: Zero focus theft (GetForegroundWindow() invariant across ShowOsd & CLI --test-osd)
$fgBeforeInProc = [DisplayFix.Brightness.AcrylicOsdWindow]::GetForegroundWindow()
[DisplayFix.Brightness.AcrylicOsdWindow]::ShowOsd(75, "NVIDIA")
$fgAfterInProc  = [DisplayFix.Brightness.AcrylicOsdWindow]::GetForegroundWindow()
$inProcFocusPreserved = ($fgBeforeInProc -eq $fgAfterInProc -and $fgAfterInProc -ne $osd.Handle)

$cliOsdOut = & $daemonExePath --test-osd 70 | Out-String
$cliOsdExit = $LASTEXITCODE

$focusPass = (
    $inProcFocusPreserved -eq $true -and
    $cliOsdExit -eq 0 -and
    $cliOsdOut -match 'StyleMatch=True' -and
    $cliOsdOut -match 'FocusPreserved=True'
)
Record-TestResult `
    -Category "Suite 4: AcrylicOsdWindow" `
    -TestName "4.2: Zero focus theft verified across in-process ShowOsd() and CLI --test-osd (GetForegroundWindow invariant)" `
    -Passed $focusPass `
    -Details "InProcFocusPreserved=$inProcFocusPreserved (FG=0x$($fgBeforeInProc.ToString('X8')) -> 0x$($fgAfterInProc.ToString('X8'))), CLI='$($cliOsdOut.Trim())'"

# Test 4.3: Zero GDI/USER handle leaks across 25 rapid ShowOsd bursts
# Warm up first render and GC
$osd.ShowOverlayInternal(50, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

$curProc = [System.Diagnostics.Process]::GetCurrentProcess()
$gdiBefore  = [DisplayFix.AdversarialM4.GuiResourceTracker]::GetGuiResources($curProc.Handle, 0)
$userBefore = [DisplayFix.AdversarialM4.GuiResourceTracker]::GetGuiResources($curProc.Handle, 1)

$swOsdBurst = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 1; $i -le 25; $i++) {
    $lvl = 10 + (($i * 3) % 91)
    $modeName = if (($i % 2) -eq 0) { "NVIDIA" } else { "Optimus" }
    $osd.ShowOverlayInternal($lvl, $modeName)
    [System.Windows.Forms.Application]::DoEvents()
}
$swOsdBurst.Stop()

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

$gdiAfter  = [DisplayFix.AdversarialM4.GuiResourceTracker]::GetGuiResources($curProc.Handle, 0)
$userAfter = [DisplayFix.AdversarialM4.GuiResourceTracker]::GetGuiResources($curProc.Handle, 1)
$osd.HideOsd()

$gdiDelta  = [int]$gdiAfter - [int]$gdiBefore
$userDelta = [int]$userAfter - [int]$userBefore

$osdLeakPass = ($gdiDelta -le 2 -and $userDelta -le 2)
Record-TestResult `
    -Category "Suite 4: AcrylicOsdWindow" `
    -TestName "4.3: Zero GDI/USER handle leaks across 25 rapid ShowOsd bursts (GDI Delta: $gdiDelta, USER Delta: $userDelta)" `
    -Passed $osdLeakPass `
    -Details "25 bursts in $([math]::Round($swOsdBurst.Elapsed.TotalMilliseconds, 2))ms: GDI=$gdiBefore->$gdiAfter (Delta=$gdiDelta), USER=$userBefore->$userAfter (Delta=$userDelta)"

# -------------------------------------------------------------------------
# SUMMARY & FINAL VERDICT
# -------------------------------------------------------------------------
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  MILESTONE 4 ADVERSARIAL TEST SUMMARY" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  Total Tests Executed : $totalTests" -ForegroundColor White
Write-Host "  Passed Tests         : $passedTests" -ForegroundColor Green
Write-Host "  Failed Tests         : $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })

$verdict = if ($failedTests -eq 0) { "APPROVE" } else { "REJECT" }
$verdictColor = if ($failedTests -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Final Gate Verdict   : $verdict" -ForegroundColor $verdictColor
Write-Host "========================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
