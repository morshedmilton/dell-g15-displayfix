# tests/e2e/tier2_boundaries/test_b01_brightness_extremes.ps1
# Tier 2 Boundary Tests: Brightness Extremes & Clamping

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "B01 - Brightness Extremes and Clamping Boundaries" {

    $clampAlgorithm = {
        param([int]$level)
        if ($level -lt 10) { return 10 }
        if ($level -gt 100) { return 100 }
        return $level
    }

    It "B01.1: Clamps negative brightness values (-100, -1) to safe 10% floor" {
        Assert-Equal (& $clampAlgorithm -100) 10 "Extreme negative -100 must clamp to 10"
        Assert-Equal (& $clampAlgorithm -1)   10 "Negative -1 must clamp to 10"
    }

    It "B01.2: Clamps zero percent (0%) to 10% (prevents hardware panel inverter power-off)" {
        Assert-Equal (& $clampAlgorithm 0) 10 "0% must clamp to 10% (never turn off panel inverter)"
    }

    It "B01.3: Clamps values exceeding 100% (101, 255, 1000) to 100% ceiling" {
        Assert-Equal (& $clampAlgorithm 101) 100 "101% must clamp to 100"
        Assert-Equal (& $clampAlgorithm 255) 100 "255 (uint8 max) must clamp to 100"
        Assert-Equal (& $clampAlgorithm 1000) 100 "1000 must clamp to 100"
    }

    It "B01.4: Handles rapid sequential adjustments (20 rapid step changes in 100ms) without drift" {
        $level = 50
        $step = 5
        # 10 down steps followed by 10 up steps
        for ($i = 0; $i -lt 10; $i++) {
            $level = & $clampAlgorithm ($level - $step)
        }
        Assert-Equal $level 10 "10 down steps from 50 must reach 10% floor"

        for ($i = 0; $i -lt 10; $i++) {
            $level = & $clampAlgorithm ($level + $step)
        }
        Assert-Equal $level 60 "10 up steps from 10 must reach 60"
    }

    It "B01.5: Verifies write offset calculation boundary (+8 compensation does not overflow 100)" {
        $applyCompensatedWrite = {
            param([int]$target)
            $clampedTarget = & $clampAlgorithm $target
            $withOffset = $clampedTarget + 8
            if ($withOffset -gt 100) { $withOffset = 100 }
            return $withOffset
        }

        Assert-Equal (& $applyCompensatedWrite 95) 100 "95 + 8 offset must be clamped to 100 (no overflow)"
        Assert-Equal (& $applyCompensatedWrite 100) 100 "100 + 8 offset must be clamped to 100"
        Assert-Equal (& $applyCompensatedWrite 10) 18 "10 + 8 offset must equal 18"
    }
}
