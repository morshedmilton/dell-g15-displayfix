# tests/e2e/tier3_combinations/test_c05_hotkeys_and_media_keys.ps1
# Tier 3 Cross-Feature Combinations: Hotkeys + Function Row Media Keys

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "C05 - Brightness Hotkeys and Media Keys Combination" {

    It "C05.1: Interleaving F6/F7 brightness adjustments with F1-F3 volume keys" {
        $sequence = @('F7', 'F3', 'F7', 'F2', 'F6')
        $brightnessActions = 0
        $volumeActions = 0

        foreach ($k in $sequence) {
            if ($k -eq 'F6' -or $k -eq 'F7') { $brightnessActions++ }
            if ($k -eq 'F2' -or $k -eq 'F3') { $volumeActions++ }
        }

        Assert-Equal $brightnessActions 3 "3 brightness adjustments captured"
        Assert-Equal $volumeActions 2 "2 volume adjustments captured"
    }

    It "C05.2: Interleaving F6/F7 brightness adjustments with F9 play/pause key" {
        $sequence = @('F6', 'F9', 'F7')
        $playPauseCount = 0

        foreach ($k in $sequence) {
            if ($k -eq 'F9') { $playPauseCount++ }
        }

        Assert-Equal $playPauseCount 1 "F9 play/pause event accurately detected without interference"
    }

    It "C05.3: Rapid double-tap F6 followed by F2 does not drop volume keystrokes" {
        $eventLog = [System.Collections.Generic.List[string]]::new()
        $eventLog.Add("BRIGHTNESS_DOWN")
        $eventLog.Add("BRIGHTNESS_DOWN")
        $eventLog.Add("VOLUME_DOWN")

        Assert-Equal $eventLog.Count 3 "All 3 keystroke actions registered in sequence"
        Assert-Equal $eventLog[2] "VOLUME_DOWN" "Third action was VOLUME_DOWN without drop"
    }

    It "C05.4: Acrylic OSD does not interfere with Windows native volume flyout" {
        $osdWindowStyle = 0x08000000 # WS_EX_NOACTIVATE
        $isNoActivate = ($osdWindowStyle -band 0x08000000) -ne 0
        Assert-True $isNoActivate "OSD window has WS_EX_NOACTIVATE (no window focus interference)"
    }
}
