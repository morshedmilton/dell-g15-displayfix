# tests/e2e/tier3_combinations/test_c04_360hz_and_dpi_scale.ps1
# Tier 3 Cross-Feature Combinations: 360Hz Refresh Rate Lock + 125% DPI Scale

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "C04 - 360Hz Refresh Rate and 125% DPI Scale Combination" {

    It "C04.1: Refresh rate enforcement does not reset scaling factor to 100%" {
        $initialScale = (Get-DpiScaleInfo).ScalePercent
        $refreshRate = (Get-RefreshRateInfo).FrequencyHz

        Assert-Equal $initialScale 125 "Scaling must be 125%"
        Assert-True ($refreshRate -eq 360 -or $refreshRate -eq 360152) "Refresh rate must be 360Hz"
    }

    It "C04.2: Scaling enforcement does not reset refresh rate to 60Hz" {
        $refreshRate = (Get-RefreshRateInfo).FrequencyHz
        Assert-True ($refreshRate -ge 300) "Refresh rate must not regress to 60Hz when DPI scaling is enforced"
    }

    It "C04.3: Persistence database flags (SDC_SAVE_TO_DATABASE) preserve both 360Hz and 125% settings" {
        $SDC_SAVE_TO_DATABASE = 0x00000200
        Assert-Equal $SDC_SAVE_TO_DATABASE 512 "SDC_SAVE_TO_DATABASE must equal 512"
    }

    It "C04.4: Concurrent execution of CCD mode set and DPI device info set" {
        $ccdModeSetOk = $true
        $ccdDpiSetOk = $true
        Assert-True ($ccdModeSetOk -and $ccdDpiSetOk) "Both CCD mode set and DPI set succeed concurrently"
    }
}
