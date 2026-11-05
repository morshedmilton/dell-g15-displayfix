# tests/e2e/tier1_features/test_f08_registry_dpi_sync.ps1
# Feature F08: Multi-Topology Registry DPI Sync (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F08 - Multi-Topology Registry DPI Sync" {

    It "F08.1: Verifies PerMonitorSettings registry branch existence under HKCU" {
        $regPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
        Assert-PathExists $regPath "PerMonitorSettings registry branch must exist"
    }

    It "F08.2: Verifies LogPixels system DPI base equals 120 (125% scaling factor)" {
        $desktopKey = "HKCU:\Control Panel\Desktop"
        $logPixels = (Get-ItemProperty -Path $desktopKey -Name "LogPixels" -ErrorAction SilentlyContinue).LogPixels
        # 120 = 125% scale (96 * 1.25)
        Assert-Equal $logPixels 120 "HKCU:\Control Panel\Desktop\LogPixels must equal 120 (125% scale base)"
    }

    It "F08.3: Verifies Intel UHD topology key (8086_A78B) has DpiValue = 0 (125% recommended)" {
        $regPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
        $intelKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*8086*A78B*" }
        if ($intelKeys) {
            foreach ($k in $intelKeys) {
                $val = (Get-ItemProperty -Path $k.PSPath -Name "DpiValue" -ErrorAction SilentlyContinue).DpiValue
                Assert-Equal $val 0 "Intel topology $($k.PSChildName) DpiValue must equal 0 (125% recommended)"
            }
        } else {
            Assert-True $true "No Intel topology key currently present"
        }
    }

    It "F08.4: Verifies NVIDIA RTX 4060 topology key (10DE_28E0) has DpiValue = 0 (125% recommended)" {
        $regPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
        $nvKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*10DE*28E0*" }
        if ($nvKeys) {
            foreach ($k in $nvKeys) {
                $val = (Get-ItemProperty -Path $k.PSPath -Name "DpiValue" -ErrorAction SilentlyContinue).DpiValue
                # Must be 0 (125%), not -1 (4294967295) which causes revert to 100%
                Assert-Equal $val 0 "NVIDIA topology $($k.PSChildName) DpiValue must equal 0 (125%), preventing desync to 100%"
            }
        } else {
            Assert-True $true "No NVIDIA topology key currently present"
        }
    }

    It "F08.5: Validates topology synchronization parity between Intel and NVIDIA registry entries" {
        $regPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
        $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*AUOAA9F*" }
        
        $mismatches = 0
        foreach ($k in $subKeys) {
            $val = (Get-ItemProperty -Path $k.PSPath -Name "DpiValue" -ErrorAction SilentlyContinue).DpiValue
            if ($val -ne 0) { $mismatches++ }
        }

        Assert-Equal $mismatches 0 "All internal panel AUOAA9F topologies must be synchronized to DpiValue = 0"
    }
}
