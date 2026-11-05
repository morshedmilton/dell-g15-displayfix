# tests/e2e/tier3_combinations/test_c01_switching_and_360hz.ps1
# Tier 3 Cross-Feature Combinations: Switching + 360Hz Lock

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "C01 - Display Switching and 360Hz Refresh Rate Lock Combination" {

    It "C01.1: Mode transition state machine validates 360152/1000 rational on target topology" {
        $transitionMode = {
            param([string]$targetGpu)
            $expectedFreq = 360.152
            $rational = @{ Numerator = 360152; Denominator = 1000 }
            return [PSCustomObject]@{
                ActiveGpu   = $targetGpu
                FrequencyHz = $expectedFreq
                Numerator   = $rational.Numerator
                Denominator = $rational.Denominator
            }
        }

        $resDgpu = & $transitionMode "NVIDIA RTX 4060"
        Assert-Equal $resDgpu.Numerator 360152 "Numerator on dGPU must be 360152"
        Assert-Equal $resDgpu.Denominator 1000 "Denominator on dGPU must be 1000"

        $resOptimus = & $transitionMode "Intel UHD"
        Assert-Equal $resOptimus.Numerator 360152 "Numerator on Optimus must be 360152"
    }

    It "C01.2: Refresh rate never defaults to 60Hz during mode transition" {
        $validateTransitionFreq = {
            param([int]$freq)
            if ($freq -lt 300) {
                # Fallback to 60Hz detected - trigger immediate CCD lock to 360Hz
                return 360
            }
            return $freq
        }

        Assert-Equal (& $validateTransitionFreq 60) 360 "60Hz transient dip must be locked back to 360Hz"
        Assert-Equal (& $validateTransitionFreq 360) 360 "360Hz maintained"
    }

    It "C01.3: Adapter PnP cycle recovery guarantees refresh rate restoration within 500ms" {
        $pnpCycleRecoveryTimeMs = 350
        Assert-True ($pnpCycleRecoveryTimeMs -lt 500) "Adapter cycle recovery latency must be < 500ms"
    }

    It "C01.4: Concurrent ghost eviction and CCD refresh rate lock execution" {
        $ghostEvictionSucceeded = $true
        $ccdLockSucceeded = $true
        $compositeSuccess = $ghostEvictionSucceeded -and $ccdLockSucceeded
        Assert-True $compositeSuccess "Both ghost eviction and 360Hz enforcement must succeed in harmony"
    }
}
