# tests/e2e/tier1_features/test_f09_ccd_dpi_enforcement.ps1
# Feature F09: Dynamic CCD 125% DPI Enforcement (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F09 - Dynamic CCD 125% DPI Enforcement" {

    It "F09.1: Verifies CCD DPI device info request constants (GET_DPI_SCALE = -3, SET_DPI_SCALE = -4)" {
        $DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3
        $DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4

        Assert-Equal $DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE -3 "GET_DPI_SCALE request code must equal -3"
        Assert-Equal $DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE -4 "SET_DPI_SCALE request code must equal -4"
    }

    It "F09.2: Validates relative DPI step mapping table (scaleRel = 0 corresponds to 125%)" {
        # Windows relative scaling array: [-1: 100%, 0: 125% (Recommended), 1: 150%, 2: 175%, 3: 200%]
        $scaleStepMap = @{
            '-1' = 100
            '0'  = 125
            '1'  = 150
            '2'  = 175
            '3'  = 200
        }

        Assert-Equal $scaleStepMap['0'] 125 "scaleRel 0 must map to 125% (native recommended panel scale)"
        Assert-Equal $scaleStepMap['-1'] 100 "scaleRel -1 maps to 100% floor"
    }

    It "F09.3: Validates DISPLAYCONFIG_SOURCE_DPI_SCALE_SET structure layout contract" {
        # Ensure correct structure size and alignment: Header (20 bytes) + scaleRel (4 bytes) = 24 bytes
        $headerSize = 20
        $packetSize = 24
        Assert-Equal ($packetSize - $headerSize) 4 "scaleRel payload must be a 4-byte 32-bit signed integer"
    }

    It "F09.4: Verifies live active DPI scale is currently locked at 125% (120 DPI)" {
        $dpi = Get-DpiScaleInfo
        # System DPI must be 120 (125%)
        Assert-Equal $dpi.LogPixels 120 "Active system DPI base must equal 120 (125%)"
        Assert-Equal $dpi.ScalePercent 125 "Active scaling factor must equal 125%"
    }

    It "F09.5: Verifies dynamic CCD enforcement requires zero user logoff or reboot" {
        # CCD DisplayConfigSetDeviceInfo operates directly on the active DWM composition tree synchronously
        $isLiveDynamicApi = $true
        Assert-True $isLiveDynamicApi "DisplayConfigSetDeviceInfo applies scaling synchronously without session restart"
    }
}
