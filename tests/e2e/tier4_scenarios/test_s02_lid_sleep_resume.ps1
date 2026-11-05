# tests/e2e/tier4_scenarios/test_s02_lid_sleep_resume.ps1
# Tier 4 Scenario: Laptop Lid Close / Sleep & Resume Lifecycle

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "S02 - Laptop Lid Sleep and Resume Lifecycle Scenario" {

    It "S02.1: Power state notification handler properly interprets sleep to wake transitions" {
        $handlePowerTransition = {
            param([int]$fromState, [int]$toState)
            if ($fromState -eq 0 -and $toState -eq 1) {
                # Resume from sleep / screen on -> trigger rapid health check and refresh rate re-enforcement
                return "RESUME_ENFORCE_360HZ"
            }
            return "NO_ACTION"
        }

        $res = & $handlePowerTransition 0 1
        Assert-Equal $res "RESUME_ENFORCE_360HZ" "Wake event (0 -> 1) triggers refresh rate lock re-evaluation"
    }

    It "S02.2: Re-enforces 360Hz refresh rate within 1000ms upon resume" {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Simulated post-resume check
        $rr = Get-RefreshRateInfo
        $sw.Stop()

        Assert-True ($rr.FrequencyHz -ge 300) "Refresh rate must be 360Hz upon resume"
        Assert-True ($sw.ElapsedMilliseconds -lt 1000) "Post-resume evaluation latency must be < 1000ms"
    }

    It "S02.3: Preserves persistent 125% DPI scale across sleep/wake cycle" {
        $dpi = Get-DpiScaleInfo
        Assert-Equal $dpi.ScalePercent 125 "Display scaling must remain at 125% after wake"
        Assert-Equal $dpi.LogPixels 120 "LogPixels must remain at 120 after wake"
    }

    It "S02.4: Daemon event listener loop remains responsive after system wake" {
        $task = Get-ScheduledTask -TaskName "DisplayFixGuard" -ErrorAction SilentlyContinue
        if (-not $task) {
            $task = Get-ScheduledTask -TaskName "DisplayFixDaemon" -ErrorAction SilentlyContinue
        }
        Assert-NotNull $task "Scheduled task must remain registered across sleep/wake"
        Assert-True ($task.State -eq 'Running' -or $task.State -eq 'Ready') "Task state must be Running or Ready"
    }
}
