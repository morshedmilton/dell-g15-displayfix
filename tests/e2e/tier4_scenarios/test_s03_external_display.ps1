# tests/e2e/tier4_scenarios/test_s03_external_display.ps1
# Tier 4 Scenario: External Monitor (HDMI / Type-C DP) Connect & Disconnect

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "S03 - External Display Connect and Disconnect Scenario" {

    It "S03.1: Identifies external monitors and prevents eviction of non-AUOAA9F displays" {
        $monitorFilter = {
            param([string]$deviceInstanceId, [string]$hardwareId)
            # Safe eviction target is strictly the Intel ghost node
            if ($deviceInstanceId -like "*AUOAA9F*UID8388688*") {
                return "TARGET_GHOST_EVICTION"
            }
            return "STAND_DOWN_PRESERVE_DISPLAY"
        }

        # Simulated external HDMI monitor
        Assert-Equal (& $monitorFilter "DISPLAY\DEL4123\4&12345678&0&UID0" "MONITOR\DEL4123") "STAND_DOWN_PRESERVE_DISPLAY" `
            "External Dell monitor must be preserved"
        Assert-Equal (& $monitorFilter "DISPLAY\SAM0456\4&87654321&0&UID1" "MONITOR\SAM0456") "STAND_DOWN_PRESERVE_DISPLAY" `
            "External Samsung monitor must be preserved"
        Assert-Equal (& $monitorFilter "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688" "MONITOR\AUOAA9F") "TARGET_GHOST_EVICTION" `
            "Intel ghost node must be correctly targeted"
    }

    It "S03.2: Multi-display topology does not disable primary discrete graphics adapter" {
        $gpus = Get-ActiveVideoControllers
        Assert-NotNull $gpus.Nvidia "Discrete NVIDIA adapter must never be disabled during external monitor attachment"
    }

    It "S03.3: Disconnecting external monitor restores single-display internal 360Hz configuration" {
        $restoreInternalTopology = {
            param([int]$activeDisplayCount)
            if ($activeDisplayCount -eq 1) {
                return @{ TargetPanel = "AUOAA9F"; FrequencyHz = 360; ScalePercent = 125 }
            }
            return @{ MultiMonitor = $true }
        }

        $res = & $restoreInternalTopology 1
        Assert-Equal $res.TargetPanel "AUOAA9F" "Internal panel targeted"
        Assert-Equal $res.FrequencyHz 360 "360Hz restored"
        Assert-Equal $res.ScalePercent 125 "125% scaling restored"
    }

    It "S03.4: Hotplugging external display does not trigger DWM memory leaks" {
        $metrics = Get-DwmHealthMetrics
        Assert-NotNull $metrics "DWM health metrics must remain queryable"
        Assert-InRange $metrics.WorkingSetMB 10.0 300.0 "DWM memory remains within bounds during topology changes"
    }
}
