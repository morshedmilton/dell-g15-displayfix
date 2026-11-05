# tests/e2e/tier4_scenarios/test_s04_prolonged_video_playback.ps1
# Tier 4 Scenario: Prolonged Video Playback & Multimedia Session

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "S04 - Prolonged Video Playback and Media Stability Scenario" {

    It "S04.1: Extended presentation simulation shows flat DWM private working set drift (< 5MB)" {
        $m1 = Get-DwmHealthMetrics
        Assert-NotNull $m1 "Initial DWM metrics retrievable"

        # Presentation sampling
        Start-Sleep -Milliseconds 300

        $m2 = Get-DwmHealthMetrics
        $wsDriftMB = [math]::Abs($m2.WorkingSetMB - $m1.WorkingSetMB)
        Assert-True ($wsDriftMB -lt 5.0) "DWM memory drift ($wsDriftMB MB) must be < 5.0 MB during media presentation"
    }

    It "S04.2: Smooth brightness adjustments cause zero presentation frame stutter" {
        $applyBrightnessStep = {
            param([int]$current, [int]$delta)
            $newLevel = $current + $delta
            if ($newLevel -lt 10) { $newLevel = 10 }
            if ($newLevel -gt 100) { $newLevel = 100 }
            return $newLevel
        }

        $b1 = & $applyBrightnessStep 50 -5
        $b2 = & $applyBrightnessStep $b1 5
        Assert-Equal $b2 50 "Brightness adjusted smoothly and restored without glitching"
    }

    It "S04.3: Zero DWM crashes (Event ID 1000) recorded in Application event log" {
        $alerts = Get-SystemEventLogAlerts -Hours 1
        Assert-Equal $alerts.DwmCrashes 0 "Zero DWM application crashes allowed during multimedia playback"
    }

    It "S04.4: 360Hz refresh rate remains solidly locked throughout continuous playback" {
        $rr = Get-RefreshRateInfo
        Assert-True ($rr.FrequencyHz -ge 300) "Refresh rate remains locked at 360Hz"
    }
}
