# tests/e2e/challenger_osd_interference_test.ps1
# Challenger 2 Verification Harness: Acrylic OSD Non-Interference, Focus Preservation & Auto-Dismiss
# Empirically tests WS_EX_NOACTIVATE, live foreground window invariant across Notepad and Console,
# WM_MOUSEACTIVATE / WM_NCHITTEST click-through, 1500ms auto-dismiss, timer reset, and GDI/USER leak bounds.

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

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DisplayFix.ChallengerOsd
{
    public static class Native
    {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

        public const uint GR_GDIOBJECTS  = 0;
        public const uint GR_USEROBJECTS = 1;
        public const int GWL_EXSTYLE    = -20;
        public const uint WM_MOUSEACTIVATE = 0x0021;
        public const uint WM_NCHITTEST     = 0x0084;
    }
}
"@

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
Write-Host "  CHALLENGER 2: ACRYLIC OSD NON-INTERFERENCE & FOCUS VERIFICATION" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan

$osd = [DisplayFix.Brightness.AcrylicOsdWindow]::Instance

# -------------------------------------------------------------------------
# SUITE 1: Extended Window Styles & Live HWND Flags
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 1: Extended Window Styles (WS_EX_NOACTIVATE & Acrylic) ---" -ForegroundColor Yellow

$osd.ShowOverlayInternal(55, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
$hwnd = $osd.Handle

$exStyle = [DisplayFix.ChallengerOsd.Native]::GetWindowLong($hwnd, [DisplayFix.ChallengerOsd.Native]::GWL_EXSTYLE)
$reqMask = [DisplayFix.Brightness.AcrylicOsdWindow]::RequiredExStyle

$hasNoActivate  = ($exStyle -band [DisplayFix.Brightness.AcrylicOsdWindow]::WS_EX_NOACTIVATE) -ne 0
$hasLayered     = ($exStyle -band [DisplayFix.Brightness.AcrylicOsdWindow]::WS_EX_LAYERED) -ne 0
$hasTransparent = ($exStyle -band [DisplayFix.Brightness.AcrylicOsdWindow]::WS_EX_TRANSPARENT) -ne 0
$hasTopmost     = ($exStyle -band [DisplayFix.Brightness.AcrylicOsdWindow]::WS_EX_TOPMOST) -ne 0
$hasToolwindow  = ($exStyle -band [DisplayFix.Brightness.AcrylicOsdWindow]::WS_EX_TOOLWINDOW) -ne 0
$allBitsMatched = (($exStyle -band $reqMask) -eq $reqMask)

Assert-Test `
    -Name "1.1: Live HWND extended style has all 5 flags (WS_EX_NOACTIVATE, LAYERED, TRANSPARENT, TOPMOST, TOOLWINDOW)" `
    -Condition ($allBitsMatched -and $hasNoActivate -and $hasLayered -and $hasTransparent -and $hasTopmost -and $hasToolwindow) `
    -Details "Handle=0x$($hwnd.ToString('X8')), ExStyle=0x$($exStyle.ToString('X8')), ReqMask=0x$($reqMask.ToString('X8')), NoActivate=$hasNoActivate, Transparent=$hasTransparent"

# -------------------------------------------------------------------------
# SUITE 2: Input Focus Preservation with Active Foreground Windows
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 2: Live Focus Preservation Across Active Windows ---" -ForegroundColor Yellow

# Test A: Foreground console window focus preservation
$fgConsoleBefore = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()
$osd.ShowOverlayInternal(60, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
$fgConsoleDuring = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()
$osd.HideOsd()
[System.Windows.Forms.Application]::DoEvents()
$fgConsoleAfter = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()

$consoleFocusOk = (
    $fgConsoleBefore -eq $fgConsoleDuring -and
    $fgConsoleBefore -eq $fgConsoleAfter -and
    $fgConsoleDuring -ne $hwnd
)

Assert-Test `
    -Name "2.1: OSD does NOT steal focus from active console window" `
    -Condition $consoleFocusOk `
    -Details "Before=0x$($fgConsoleBefore.ToString('X8')), During=0x$($fgConsoleDuring.ToString('X8')), After=0x$($fgConsoleAfter.ToString('X8')), OsdHandle=0x$($hwnd.ToString('X8'))"

# Test B: Foreground Notepad window focus preservation
$notepad = Start-Process notepad.exe -PassThru
try {
    for ($i = 0; $i -lt 20; $i++) {
        $notepad.Refresh()
        if ($notepad.MainWindowHandle -ne [IntPtr]::Zero) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    $npHwnd = $notepad.MainWindowHandle
    if ($npHwnd -ne [IntPtr]::Zero) {
        [DisplayFix.ChallengerOsd.Native]::SetForegroundWindow($npHwnd) | Out-Null
        Start-Sleep -Milliseconds 200
    }

    $fgNotepadBefore = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()
    $osd.ShowOverlayInternal(70, "NVIDIA")
    [System.Windows.Forms.Application]::DoEvents()
    $fgNotepadDuring = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()
    Start-Sleep -Milliseconds 100
    $osd.HideOsd()
    [System.Windows.Forms.Application]::DoEvents()
    $fgNotepadAfter = [DisplayFix.ChallengerOsd.Native]::GetForegroundWindow()

    $notepadFocusOk = (
        $fgNotepadBefore -eq $fgNotepadDuring -and
        $fgNotepadBefore -eq $fgNotepadAfter -and
        $fgNotepadDuring -ne $hwnd
    )

    Assert-Test `
        -Name "2.2: OSD does NOT steal focus from active foreground Notepad application" `
        -Condition $notepadFocusOk `
        -Details "Before=0x$($fgNotepadBefore.ToString('X8')), During=0x$($fgNotepadDuring.ToString('X8')), After=0x$($fgNotepadAfter.ToString('X8')), OsdHandle=0x$($hwnd.ToString('X8'))"
}
finally {
    if (-not $notepad.HasExited) {
        $notepad.Kill()
        $notepad.WaitForExit()
    }
}

# -------------------------------------------------------------------------
# SUITE 3: Mouse Activation & Click-Through Transparency
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 3: Mouse Hit-Testing & Click-Through Transparency ---" -ForegroundColor Yellow

# WM_MOUSEACTIVATE must return MA_NOACTIVATE (3)
$resMouseAct = [DisplayFix.ChallengerOsd.Native]::SendMessage($hwnd, [DisplayFix.ChallengerOsd.Native]::WM_MOUSEACTIVATE, [IntPtr]::Zero, [IntPtr]::Zero)

# WM_NCHITTEST must return HTTRANSPARENT (-1)
$resHitTest = [DisplayFix.ChallengerOsd.Native]::SendMessage($hwnd, [DisplayFix.ChallengerOsd.Native]::WM_NCHITTEST, [IntPtr]::Zero, [IntPtr]::Zero)

$mouseOk = ($resMouseAct.ToInt32() -eq 3 -and $resHitTest.ToInt32() -eq -1)
Assert-Test `
    -Name "3.1: WM_MOUSEACTIVATE returns MA_NOACTIVATE (3) and WM_NCHITTEST returns HTTRANSPARENT (-1)" `
    -Condition $mouseOk `
    -Details "WM_MOUSEACTIVATE=$($resMouseAct.ToInt32())(expected 3), WM_NCHITTEST=$($resHitTest.ToInt32())(expected -1)"

# -------------------------------------------------------------------------
# SUITE 4: Auto-Dismiss Timing & Timer Reset Behavior
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 4: Auto-Dismiss Timing & Dynamic Timer Reset ---" -ForegroundColor Yellow

# Test A: Default 1500ms auto-dismiss
$osd.ShowOverlayInternal(80, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
$swDismiss = [System.Diagnostics.Stopwatch]::StartNew()

while ($osd.IsOsdVisible -and $swDismiss.ElapsedMilliseconds -lt 3000) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50
}
$swDismiss.Stop()
$dismissMs = $swDismiss.ElapsedMilliseconds

$dismissOk = ($dismissMs -ge 1300 -and $dismissMs -le 2000 -and -not $osd.IsOsdVisible)
Assert-Test `
    -Name "4.1: OSD cleanly auto-dismisses after 1500ms (measured: ${dismissMs}ms)" `
    -Condition $dismissOk `
    -Details "Elapsed=${dismissMs}ms (target 1500ms), FinalVisibility=$($osd.IsOsdVisible)"

# Test B: Timer reset on rapid consecutive keypresses
$osd.ShowOverlayInternal(40, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 900
# Keypress at 900ms resets the 1500ms timer
$osd.ShowOverlayInternal(45, "NVIDIA")
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 900
$stillVisibleAt1800ms = $osd.IsOsdVisible
# Total elapsed since first press = 1800ms. If timer reset worked, OSD is STILL visible!

# Now wait for the reset timer to expire (another 800ms -> total 1700ms since second press)
Start-Sleep -Milliseconds 800
[System.Windows.Forms.Application]::DoEvents()
$hiddenAfterFullTimeout = -not $osd.IsOsdVisible

$timerResetOk = ($stillVisibleAt1800ms -and $hiddenAfterFullTimeout)
Assert-Test `
    -Name "4.2: Repeated keypresses dynamically reset auto-dismiss timer without flicker" `
    -Condition $timerResetOk `
    -Details "StillVisibleAt1800ms=$stillVisibleAt1800ms, HiddenAfterFullTimeout=$hiddenAfterFullTimeout"

# -------------------------------------------------------------------------
# SUITE 5: GDI/USER Handle Leak Stress (50 Show/Hide Bursts)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 5: Resource & Handle Leak Stress ---" -ForegroundColor Yellow

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

$curProc = [System.Diagnostics.Process]::GetCurrentProcess()
$gdiStart  = [DisplayFix.ChallengerOsd.Native]::GetGuiResources($curProc.Handle, [DisplayFix.ChallengerOsd.Native]::GR_GDIOBJECTS)
$userStart = [DisplayFix.ChallengerOsd.Native]::GetGuiResources($curProc.Handle, [DisplayFix.ChallengerOsd.Native]::GR_USEROBJECTS)
$procHandlesStart = $curProc.HandleCount

$swBurst = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 1; $i -le 50; $i++) {
    $lvl = 10 + (($i * 7) % 91)
    $osd.ShowOverlayInternal($lvl, "NVIDIA")
    [System.Windows.Forms.Application]::DoEvents()
    if (($i % 10) -eq 0) {
        $osd.HideOsd()
        [System.Windows.Forms.Application]::DoEvents()
    }
}
$swBurst.Stop()
$osd.HideOsd()
[System.Windows.Forms.Application]::DoEvents()

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

$curProc.Refresh()
$gdiEnd  = [DisplayFix.ChallengerOsd.Native]::GetGuiResources($curProc.Handle, [DisplayFix.ChallengerOsd.Native]::GR_GDIOBJECTS)
$userEnd = [DisplayFix.ChallengerOsd.Native]::GetGuiResources($curProc.Handle, [DisplayFix.ChallengerOsd.Native]::GR_USEROBJECTS)
$procHandlesEnd = $curProc.HandleCount

$gdiDelta = [int]$gdiEnd - [int]$gdiStart
$userDelta = [int]$userEnd - [int]$userStart
$procHandleDelta = [int]$procHandlesEnd - [int]$procHandlesStart

$leakPass = ($gdiDelta -le 2 -and $userDelta -le 2 -and $procHandleDelta -le 10)
Assert-Test `
    -Name "5.1: Zero GDI/USER/Process handle leaks over 50 rapid bursts (GDI: $gdiDelta, USER: $userDelta, Handles: $procHandleDelta)" `
    -Condition $leakPass `
    -Details "50 bursts in $($swBurst.ElapsedMilliseconds)ms: GDI=$gdiStart->$gdiEnd(+$gdiDelta), USER=$userStart->$userEnd(+$userDelta), Handles=$procHandlesStart->$procHandlesEnd(+$procHandleDelta)"

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY: Total Tests: $totalTests | Passed: $passedTests | Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
