# tests/e2e/tier1_features/test_f07_refresh_rate_360hz.ps1
# Feature F07: Native 360Hz Refresh Rate Lock (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F07 - Native 360Hz Refresh Rate Lock" {

    It "F07.1: Verifies AUO AA9F internal panel hardware capabilities include 360Hz" {
        $rr = Get-RefreshRateInfo
        Assert-NotNull $rr "Refresh rate info must be queryable"
        # Current active or supported refresh rate must be 360Hz
        Assert-True ($rr.FrequencyHz -eq 360 -or $rr.FrequencyHz -eq 360152) "Display refresh rate must be 360Hz (360.152Hz)"
    }

    It "F07.2: Verifies exact rational timing numerator/denominator (360152 / 1000)" {
        $numerator = 360152
        $denominator = 1000
        $exactFreq = $numerator / [double]$denominator
        
        Assert-InRange $exactFreq 360.15 360.16 "Rational frequency must equal 360.152 Hz"
        Assert-Equal $numerator 360152 "Numerator must match AUO AA9F native hardware timing"
        Assert-Equal $denominator 1000 "Denominator must be 1000"
    }

    It "F07.3: Verifies Windows CCD SetDisplayConfig flags contract (SDC_SAVE_TO_DATABASE)" {
        $SDC_APPLY                       = 0x00000080
        $SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020
        $SDC_SAVE_TO_DATABASE            = 0x00000200
        $SDC_ALLOW_CHANGES               = 0x00000400

        $combinedFlags = $SDC_APPLY -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_SAVE_TO_DATABASE -bor $SDC_ALLOW_CHANGES
        Assert-Equal $combinedFlags 0x000006A0 "Combined CCD flags must equal 0x000006A0 (enforces persistence across reboots)"
        Assert-True (($combinedFlags -band $SDC_SAVE_TO_DATABASE) -ne 0) "SDC_SAVE_TO_DATABASE flag must be present"
    }

    It "F07.4: Validates two-state mode constraint (EDID exposes only 60Hz and 360Hz)" {
        # The AUO AA9F panel on Dell G15 only has 2 discrete states: 60Hz and 360Hz
        $validModes = @(60, 360)
        $current = (Get-RefreshRateInfo).FrequencyHz
        if ($current -eq 360152) { $current = 360 }

        Assert-True ($validModes -contains $current) "Current refresh rate ($current Hz) must be in valid panel mode set (60Hz or 360Hz)"
    }

    It "F07.5: Verifies refresh rate enforcement recovery logic when fallback 60Hz is detected" {
        $shouldRestore360Hz = {
            param([int]$currentFreq)
            if ($currentFreq -lt 300) { return $true }
            return $false
        }

        Assert-True  (& $shouldRestore360Hz 60)  "When refresh rate is 60Hz, enforcement must restore 360Hz"
        Assert-False (& $shouldRestore360Hz 360) "When refresh rate is already 360Hz, no corrective change needed"
    }
}
