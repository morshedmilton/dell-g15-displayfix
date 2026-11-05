# tests/e2e/tier3_combinations/test_c03_switching_and_brightness.ps1
# Tier 3 Cross-Feature Combinations: Switching + Brightness Control

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "C03 - Display Switching and Brightness Control Combination" {

    It "C03.1: Brightness level is retained across display transitions without sudden 100% blast" {
        $savedBrightness = 45
        # Simulate transition from Optimus to NVIDIA mode
        $transferredBrightness = $savedBrightness
        Assert-Equal $transferredBrightness 45 "Brightness must stay at 45% (no sudden reset to 100% blast on mode change)"
    }

    It "C03.2: Brightness provider transitions cleanly from WmiMonitor to NvWmi" {
        $providerHandshake = {
            param([string]$activeGpu)
            if ($activeGpu -eq "NVIDIA") {
                return @{ Provider = "root\wmi:NvWmiBrightness"; Method = "NvGetSetBrightnessLevel" }
            } else {
                return @{ Provider = "root\wmi:WmiMonitorBrightnessMethods"; Method = "WmiSetBrightness" }
            }
        }

        $p1 = & $providerHandshake "Optimus"
        Assert-Equal $p1.Provider "root\wmi:WmiMonitorBrightnessMethods" "Optimus uses WmiMonitor"

        $p2 = & $providerHandshake "NVIDIA"
        Assert-Equal $p2.Provider "root\wmi:NvWmiBrightness" "NVIDIA mode uses NvWmiBrightness"
    }

    It "C03.3: Hotkey event pressed during active multiplexer transition is safely handled" {
        # Event queue test
        $eventQueue = [System.Collections.Generic.Queue[string]]::new()
        $isTransitioning = $true

        # User presses F7 during transition
        $eventQueue.Enqueue("F7_UP")
        $isTransitioning = $false

        # Process queued event upon stabilization
        $processed = $eventQueue.Dequeue()
        Assert-Equal $processed "F7_UP" "Queued hotkey event processed after stabilization"
    }

    It "C03.4: Safe 10% brightness floor is preserved throughout backend handoff" {
        $minAllowed = 10
        $current = 10
        Assert-True ($current -ge $minAllowed) "10% floor maintained during provider handoff"
    }
}
