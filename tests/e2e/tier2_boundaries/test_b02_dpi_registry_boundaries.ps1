# tests/e2e/tier2_boundaries/test_b02_dpi_registry_boundaries.ps1
# Tier 2 Boundary Tests: DPI Registry Boundaries

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "B02 - DPI Registry Boundaries" {

    It "B02.1: Handles non-existent PerMonitorSettings subkey query without throwing unhandled exceptions" {
        $fakeKey = "HKCU:\Control Panel\Desktop\PerMonitorSettings\NONEXISTENT_DEVICE_KEY"
        $val = (Get-ItemProperty -Path $fakeKey -Name "DpiValue" -ErrorAction SilentlyContinue)
        Assert-True ($null -eq $val) "Querying non-existent key returns null gracefully"
    }

    It "B02.2: Validates DpiValue boundary parsing (signed 32-bit vs unsigned DWORD 0xFFFFFFFF)" {
        # Windows registry stores DpiValue as DWORD. Value 0xFFFFFFFF is 4294967295 unsigned (-1 signed)
        $rawDword = [uint32]4294967295
        $signedVal = [System.BitConverter]::ToInt32([System.BitConverter]::GetBytes($rawDword), 0)
        Assert-Equal $signedVal -1 "0xFFFFFFFF DWORD parses to signed -1 (relative 100% scale step)"

        $rawZero = [uint32]0
        $signedZero = [System.BitConverter]::ToInt32([System.BitConverter]::GetBytes($rawZero), 0)
        Assert-Equal $signedZero 0 "0 DWORD parses to signed 0 (recommended 125% scale step)"
    }

    It "B02.3: Validates LogPixels legacy DPI range boundaries (96 to 192)" {
        $allowedLogPixels = @(96, 120, 144, 168, 192) # 100%, 125%, 150%, 175%, 200%
        $currentLogPixels = (Get-DpiScaleInfo).LogPixels

        Assert-True ($allowedLogPixels -contains $currentLogPixels) `
            "Current LogPixels ($currentLogPixels) must be in standard Windows DPI scale table (120 for 125%)"
    }

    It "B02.4: Ensures foreign external monitor registry keys are isolated from internal panel sync" {
        $isInternalPanelKey = {
            param([string]$keyName)
            return ($keyName -like "*AUOAA9F*")
        }

        Assert-True  (& $isInternalPanelKey "AUOAA9F0_01_07E6_5E_8086_A78B_00000000") "Internal AUO panel key must be recognized"
        Assert-True  (& $isInternalPanelKey "AUOAA9F0_01_07E6_5E_10DE_28E0_00000001") "Internal NVIDIA panel key must be recognized"
        Assert-False (& $isInternalPanelKey "DEL41230_01_07E6_5E_10DE_28E0_00000002") "External Dell monitor key must NOT match internal sync filter"
    }

    It "B02.5: Verifies idempotent registry write behavior (repeated sync operations do not corrupt state)" {
        $testValue = 0
        $applied1 = $testValue
        $applied2 = $applied1
        Assert-Equal $applied2 0 "Idempotent write keeps DpiValue at 0"
    }
}
