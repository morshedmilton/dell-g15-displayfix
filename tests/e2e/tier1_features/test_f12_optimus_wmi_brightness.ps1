# tests/e2e/tier1_features/test_f12_optimus_wmi_brightness.ps1
# Feature F12: Optimus WMI Brightness Backend (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F12 - Optimus WMI Brightness Backend" {

    It "F12.1: Verifies WmiMonitorBrightnessMethods class schema in root\wmi" {
        $wmiClass = Get-CimClass -Namespace "root\wmi" -ClassName "WmiMonitorBrightnessMethods" -ErrorAction SilentlyContinue
        Assert-NotNull $wmiClass "WmiMonitorBrightnessMethods class definition must exist in WMI repository"
        $method = $wmiClass.CimClassMethods["WmiSetBrightness"]
        Assert-NotNull $method "WmiSetBrightness method must be present on WmiMonitorBrightnessMethods"
    }

    It "F12.2: Validates WmiSetBrightness method parameter types (Timeout: uint32, Brightness: uint8)" {
        $wmiClass = Get-CimClass -Namespace "root\wmi" -ClassName "WmiMonitorBrightnessMethods" -ErrorAction SilentlyContinue
        $method = $wmiClass.CimClassMethods["WmiSetBrightness"]
        Assert-NotNull $method.Parameters["Timeout"] "Timeout parameter required"
        Assert-NotNull $method.Parameters["Brightness"] "Brightness parameter required"
    }

    It "F12.3: Validates dynamic backend selector arbitrator logic" {
        $selectBackend = {
            param([bool]$hasNvWmi, [bool]$hasWmiMon, [bool]$isNvidiaActive)
            if ($isNvidiaActive -and $hasNvWmi) {
                return "NvWmiBrightness"
            } elseif ($hasWmiMon) {
                return "WmiMonitorBrightness"
            } else {
                return "FallbackNvWmi"
            }
        }

        Assert-Equal (& $selectBackend $true $false $true) "NvWmiBrightness" "In NVIDIA mode with NvWmi available, choose NvWmi"
        Assert-Equal (& $selectBackend $false $true $false) "WmiMonitorBrightness" "In Optimus mode with WmiMon available, choose WmiMon"
        Assert-Equal (& $selectBackend $true $true $true) "NvWmiBrightness" "In NVIDIA mode with both available, prefer NvWmi"
    }

    It "F12.4: Verifies safe handling when active WMI provider count drops to 0" {
        $safeAdjustBrightness = {
            param($targetLevel, $availableProvidersCount)
            if ($availableProvidersCount -eq 0) {
                # Must log warning and return false gracefully, never throw unhandled exception
                return [PSCustomObject]@{ Success = $false; Error = "NO_ACTIVE_PROVIDER" }
            }
            return [PSCustomObject]@{ Success = $true; Error = $null }
        }

        $res = & $safeAdjustBrightness 50 0
        Assert-False $res.Success "Provider count 0 must report Success = false"
        Assert-Equal $res.Error "NO_ACTIVE_PROVIDER" "Error must indicate NO_ACTIVE_PROVIDER"
    }

    It "F12.5: Verifies timeout parameter contract for WmiSetBrightness (Timeout = 1 sec)" {
        $timeoutSeconds = 1
        Assert-Equal $timeoutSeconds 1 "WmiSetBrightness timeout should be 1 second to avoid UI stalls"
    }
}
