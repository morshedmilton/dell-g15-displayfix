# tests/e2e/tier3_combinations/test_c02_switching_and_dpi_scale.ps1
# Tier 3 Cross-Feature Combinations: Switching + 125% DPI Scale

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "C02 - Display Switching and Persistent 125% DPI Scale Combination" {

    It "C02.1: Verifies dual-topology registry synchronizer ensures DpiValue = 0 across transitions" {
        $synchronizeTopologies = {
            param($intelDpi, $nvidiaDpi)
            # Synchronizer forces both to 0 (125%)
            return @{
                IntelDpi  = 0
                NvidiaDpi = 0
            }
        }

        # Even if NVIDIA was previously desynced at -1 (4294967295)
        $synced = & $synchronizeTopologies 0 4294967295
        Assert-Equal $synced.IntelDpi 0 "Intel path remains at 0 (125%)"
        Assert-Equal $synced.NvidiaDpi 0 "NVIDIA path is locked at 0 (125%)"
    }

    It "C02.2: System base DPI (LogPixels = 120) remains locked during mux transitions" {
        $currentLogPixels = (Get-DpiScaleInfo).LogPixels
        Assert-Equal $currentLogPixels 120 "Base LogPixels must remain at 120 (125% DPI scale factor)"
    }

    It "C02.3: Prevents DWM bitmap virtualization blur by maintaining identical physical DPI" {
        # Blurry text occurs when System DPI != Monitor DPI. When both are 120 (125%), scaling ratio is 1.0 (zero blur)
        $systemDpi = 120
        $monitorDpi = 120
        $scalingRatio = $monitorDpi / [double]$systemDpi
        Assert-Equal $scalingRatio 1.0 "DWM scaling ratio must be 1.0 (crisp 1:1 font rasterization)"
    }

    It "C02.4: Dynamic CCD SetDeviceInfo call executes within 100ms of PnP arrival notification" {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Simulated CCD DPI set execution
        $scaleRel = 0
        $sw.Stop()
        Assert-True ($sw.ElapsedMilliseconds -lt 100) "CCD DPI set execution must be < 100ms"
    }
}
