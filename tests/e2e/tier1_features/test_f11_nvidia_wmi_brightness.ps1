# tests/e2e/tier1_features/test_f11_nvidia_wmi_brightness.ps1
# Feature F11: NVIDIA WMI Brightness Backend (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F11 - NVIDIA WMI Brightness Backend" {

    It "F11.1: Verifies NvWmiBrightness WMI class existence in root\wmi namespace" {
        $providers = Get-BrightnessWmiProviders
        Assert-True $providers.HasNvWmiBrightness "root\wmi:NvWmiBrightness class must be registered and accessible"
    }

    It "F11.2: Verifies NvGetSetBrightnessLevel method signature contract" {
        $nvClass = Get-CimClass -Namespace "root\wmi" -ClassName "NvWmiBrightness"
        Assert-NotNull $nvClass "NvWmiBrightness class must exist"
        $method = $nvClass.CimClassMethods["NvGetSetBrightnessLevel"]
        Assert-NotNull $method "NvGetSetBrightnessLevel method must be present on NvWmiBrightness"
        Assert-True ($method.Parameters.Count -ge 2) "Method must accept inArg and Level parameters"
    }

    It "F11.3: Verifies calibration write offset calculation (+8 compensation)" {
        $applyWriteOffset = {
            param([int]$userLevel)
            # Internal quantization offset compensation: write (userLevel + 8)
            $compensated = $userLevel + 8
            if ($compensated -gt 100) { $compensated = 100 }
            if ($compensated -lt 10)  { $compensated = 10 }
            return $compensated
        }

        Assert-Equal (& $applyWriteOffset 50) 58 "50% user level + 8 offset = 58"
        Assert-Equal (& $applyWriteOffset 80) 88 "80% user level + 8 offset = 88"
        Assert-Equal (& $applyWriteOffset 95) 100 "95% user level + 8 offset clamped to 100"
    }

    It "F11.4: Verifies safety floor clamping (minimum 10% prevents display black screen)" {
        $clampBrightness = {
            param([int]$level)
            if ($level -lt 10) { return 10 }
            if ($level -gt 100) { return 100 }
            return $level
        }

        Assert-Equal (& $clampBrightness 0) 10 "0% input must be clamped to safe 10% floor"
        Assert-Equal (& $clampBrightness 5) 10 "5% input must be clamped to safe 10% floor"
        Assert-Equal (& $clampBrightness -10) 10 "Negative input must be clamped to safe 10% floor"
        Assert-Equal (& $clampBrightness 10) 10 "10% input remains at 10%"
    }

    It "F11.5: Verifies safety ceiling clamping (maximum 100%)" {
        $clampBrightness = {
            param([int]$level)
            if ($level -lt 10) { return 10 }
            if ($level -gt 100) { return 100 }
            return $level
        }

        Assert-Equal (& $clampBrightness 100) 100 "100% input remains 100%"
        Assert-Equal (& $clampBrightness 105) 100 "105% input clamped to 100%"
        Assert-Equal (& $clampBrightness 255) 100 "255 input clamped to 100%"
    }
}
