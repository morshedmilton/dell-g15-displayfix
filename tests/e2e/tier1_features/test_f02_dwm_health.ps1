# tests/e2e/tier1_features/test_f02_dwm_health.ps1
# Feature F02: DWM Health & Stability Monitor (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F02 - DWM Health & Stability Monitor" {

    It "F02.1: Discovers dwm.exe process and captures memory and thread counts" {
        $metrics = Get-DwmHealthMetrics
        Assert-NotNull $metrics "DWM metrics must be retrievable"
        Assert-True ($metrics.ProcessId -gt 0) "DWM ProcessId must be valid (> 0)"
        Assert-True ($metrics.WorkingSetMB -gt 10.0) "DWM WorkingSet should be > 10MB"
        Assert-True ($metrics.ThreadCount -gt 0) "DWM ThreadCount must be > 0"
    }

    It "F02.2: Queries Win32 GDI and USER handle resources via GetGuiResources" {
        $metrics = Get-DwmHealthMetrics
        Assert-NotNull $metrics "DWM metrics must be retrievable"
        # Baseline healthy bounds: GDI < 250, USER < 500
        Assert-InRange $metrics.GdiObjects 0 250 "GDI objects must be within normal threshold (< 250)"
        Assert-InRange $metrics.UserObjects 0 500 "USER objects must be within normal threshold (< 500)"
    }

    It "F02.3: Validates DWM memory working set is within safe bounds (< 250 MB)" {
        $metrics = Get-DwmHealthMetrics
        Assert-NotNull $metrics "DWM metrics must be retrievable"
        Assert-InRange $metrics.WorkingSetMB 10.0 250.0 "DWM WorkingSet must be within healthy bounds (< 250 MB)"
        Assert-InRange $metrics.HandleCount 100 2500 "DWM Handle count must be within healthy bounds (< 2500)"
    }

    It "F02.4: Verifies absence of driver TDR resets (Event ID 4101) in System Event Log" {
        $alerts = Get-SystemEventLogAlerts -Hours 1
        Assert-NotNull $alerts "Event log alerts must be queryable"
        # Healthy system should have 0 TDR resets
        Assert-Equal $alerts.TdrCount 0 "No display driver TDR resets (Event ID 4101) should have occurred"
    }

    It "F02.5: Verifies absence of DWM application crashes (Event ID 1000) in Application Log" {
        $alerts = Get-SystemEventLogAlerts -Hours 1
        Assert-NotNull $alerts "Event log alerts must be queryable"
        Assert-Equal $alerts.DwmCrashes 0 "No DWM crashes (Event ID 1000) should have occurred"
    }
}
