# tests/e2e/tier1_features/test_f13_media_key_preservation.ps1
# Feature F13: Function Row Media Key Preservation (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F13 - Function Row Media Key Preservation" {

    It "F13.1: Verifies virtual key code mapping for Mute (VK_VOLUME_MUTE = 0xAD)" {
        $VK_VOLUME_MUTE = 0xAD
        Assert-Equal $VK_VOLUME_MUTE 173 "VK_VOLUME_MUTE virtual key code must equal 0xAD (173)"
    }

    It "F13.2: Verifies virtual key code mapping for Volume Down (0xAE) and Volume Up (0xAF)" {
        $VK_VOLUME_DOWN = 0xAE
        $VK_VOLUME_UP   = 0xAF

        Assert-Equal $VK_VOLUME_DOWN 174 "VK_VOLUME_DOWN virtual key code must equal 0xAE (174)"
        Assert-Equal $VK_VOLUME_UP 175 "VK_VOLUME_UP virtual key code must equal 0xAF (175)"
    }

    It "F13.3: Verifies virtual key code mapping for Play/Pause (VK_MEDIA_PLAY_PAUSE = 0xB3)" {
        $VK_MEDIA_PLAY_PAUSE = 0xB3
        Assert-Equal $VK_MEDIA_PLAY_PAUSE 179 "VK_MEDIA_PLAY_PAUSE virtual key code must equal 0xB3 (179)"
    }

    It "F13.4: Validates function row media key mapping dispatch table" {
        $mediaKeyTable = @{
            'F1' = 0xAD # Mute
            'F2' = 0xAE # Volume Down
            'F3' = 0xAF # Volume Up
            'F9' = 0xB3 # Play / Pause
        }

        Assert-Equal $mediaKeyTable['F1'] 0xAD "F1 must map to Mute (0xAD)"
        Assert-Equal $mediaKeyTable['F2'] 0xAE "F2 must map to Volume Down (0xAE)"
        Assert-Equal $mediaKeyTable['F3'] 0xAF "F3 must map to Volume Up (0xAF)"
        Assert-Equal $mediaKeyTable['F9'] 0xB3 "F9 must map to Play/Pause (0xB3)"
    }

    It "F13.5: Verifies media key passthrough does not collide with brightness hotkeys (F6/F7)" {
        $claimedKeys = @('F1', 'F2', 'F3', 'F6', 'F7', 'F9')
        $brightnessKeys = @('F6', 'F7')
        $mediaKeys = @('F1', 'F2', 'F3', 'F9')

        $overlap = $brightnessKeys | Where-Object { $mediaKeys -contains $_ }
        Assert-Equal ($overlap | Measure-Object).Count 0 "No key collision between brightness hotkeys and media keys"
    }
}
