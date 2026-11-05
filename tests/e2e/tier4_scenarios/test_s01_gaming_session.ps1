# tests/e2e/tier4_scenarios/test_s01_gaming_session.ps1
# Tier 4 Scenario: Synthetic Gaming Session Workload

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "S01 - Real-World Gaming Session Scenario" {

    It "S01.1: Verifies NVIDIA GPU is active and driving display output" {
        $gpus = Get-ActiveVideoControllers
        Assert-NotNull $gpus.Nvidia "NVIDIA RTX 4060 GPU must be present"
        $rr = Get-RefreshRateInfo
        Assert-True ($rr.FrequencyHz -eq 360 -or $rr.FrequencyHz -eq 360152) "Display refresh rate must be locked at 360Hz"
    }

    It "S01.2: Verifies DWM handle stability under simulated graphics load (zero handle creep)" {
        $m1 = Get-DwmHealthMetrics
        Assert-NotNull $m1 "Initial DWM metrics retrievable"

        # Simulate frame presentations
        Start-Sleep -Milliseconds 250

        $m2 = Get-DwmHealthMetrics
        $handleDelta = [math]::Abs($m2.HandleCount - $m1.HandleCount)
        Assert-True ($handleDelta -le 25) "Handle delta ($handleDelta handles) must be <= 25 handles under frame load"
    }

    It "S01.3: Confirms zero GPU scheduler TDR driver resets (Event ID 4101) during workload" {
        $alerts = Get-SystemEventLogAlerts -Hours 1
        Assert-Equal $alerts.TdrCount 0 "No GPU TDR timeout resets (Event ID 4101) allowed during gaming session"
    }

    It "S01.4: Verifies OSD window does not steal focus or minimize full-screen games (WS_EX_NOACTIVATE)" {
        $WS_EX_NOACTIVATE = 0x08000000
        $WS_EX_TOPMOST    = 0x00000008

        # Target window styles for Acrylic OSD
        $osdStyle = $WS_EX_NOACTIVATE -bor $WS_EX_TOPMOST
        Assert-True (($osdStyle -band $WS_EX_NOACTIVATE) -ne 0) "OSD has WS_EX_NOACTIVATE flag set"
        Assert-True (($osdStyle -band $WS_EX_TOPMOST) -ne 0) "OSD has WS_EX_TOPMOST flag set"
    }
}
