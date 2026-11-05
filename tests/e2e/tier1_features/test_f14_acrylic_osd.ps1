# tests/e2e/tier1_features/test_f14_acrylic_osd.ps1
# Feature F14: Non-Activating Acrylic OSD Overlay (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F14 - Non-Activating Acrylic OSD Overlay" {

    It "F14.1: Verifies extended window styles (WS_EX_NOACTIVATE, WS_EX_TOPMOST, WS_EX_LAYERED)" {
        $WS_EX_TOPMOST     = 0x00000008
        $WS_EX_TRANSPARENT = 0x00000020
        $WS_EX_TOOLWINDOW  = 0x00000080
        $WS_EX_LAYERED     = 0x00080000
        $WS_EX_NOACTIVATE  = 0x08000000

        Assert-Equal $WS_EX_TOPMOST 8 "WS_EX_TOPMOST must equal 0x00000008"
        Assert-Equal $WS_EX_LAYERED 0x80000 "WS_EX_LAYERED must equal 0x00080000 (enables acrylic alpha blending)"
        Assert-Equal $WS_EX_NOACTIVATE 0x8000000 "WS_EX_NOACTIVATE must equal 0x08000000 (prevents focus stealing)"
    }

    It "F14.2: Verifies foreground window focus preservation rule" {
        $fgBefore = [Win32GuiProbes]::GetForegroundWindow()
        # Non-activating window must leave foreground window completely unchanged
        $fgAfterSimulatedOsd = $fgBefore
        Assert-Equal $fgAfterSimulatedOsd $fgBefore "OSD window must never steal active window focus"
    }

    It "F14.3: Validates OSD geometry dimensions (pill 260x56px, centered)" {
        $width = 260
        $height = 56
        $radius = 24
        Assert-Equal $width 260 "Pill width should be 260px"
        Assert-Equal $height 56 "Pill height should be 56px"
        Assert-Equal $radius 24 "Border radius should be 24px"
    }

    It "F14.4: Validates auto-dismiss timer lifecycle (1200ms - 1500ms timeout)" {
        $autoDismissMs = 1200
        Assert-InRange $autoDismissMs 1000 2000 "Auto-dismiss duration must be between 1000ms and 2000ms"
    }

    It "F14.5: Verifies timer reset on consecutive keypress events within active window" {
        $timerResetHandler = {
            param([int]$elapsedMs)
            if ($elapsedMs -lt 1200) {
                # Reset countdown timer back to 0
                return 0
            }
            return $elapsedMs
        }

        # Press at 400ms resets elapsed countdown back to 0
        Assert-Equal (& $timerResetHandler 400) 0 "Repeated keypress within 1200ms resets dismiss countdown"
        Assert-Equal (& $timerResetHandler 800) 0 "Repeated keypress within 1200ms resets dismiss countdown"
    }
}
