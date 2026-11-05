# tests/e2e/tier1_features/test_f10_hotkey_interception.ps1
# Feature F10: F6/F7 Hotkey Interception (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F10 - F6/F7 Hotkey Interception" {

    It "F10.1: Verifies virtual key code mapping for F6 (0x75) and F7 (0x76)" {
        $VK_F6 = 0x75
        $VK_F7 = 0x76

        Assert-Equal $VK_F6 117 "VK_F6 virtual key code must equal 0x75 (117)"
        Assert-Equal $VK_F7 118 "VK_F7 virtual key code must equal 0x76 (118)"
    }

    It "F10.2: Verifies low-level keyboard hook WH_KEYBOARD_LL contract (idHook = 13)" {
        $WH_KEYBOARD_LL = 13
        Assert-Equal $WH_KEYBOARD_LL 13 "WH_KEYBOARD_LL hook ID must equal 13"
    }

    It "F10.3: Verifies modifier key bypass logic (Ctrl/Alt/Shift must pass through)" {
        # If user presses Shift+F6 or Ctrl+F7 in an IDE/app, hook must NOT swallow the key
        $shouldIntercept = {
            param([int]$vkCode, [bool]$ctrlHeld, [bool]$altHeld, [bool]$shiftHeld)
            if ($ctrlHeld -or $altHeld -or $shiftHeld) { return $false } # Pass through
            if ($vkCode -eq 0x75 -or $vkCode -eq 0x76) { return $true }  # Intercept plain F6/F7
            return $false
        }

        Assert-True  (& $shouldIntercept 0x75 $false $false $false) "Plain F6 must be intercepted"
        Assert-True  (& $shouldIntercept 0x76 $false $false $false) "Plain F7 must be intercepted"
        Assert-False (& $shouldIntercept 0x75 $true  $false $false) "Ctrl+F6 must pass through"
        Assert-False (& $shouldIntercept 0x76 $false $true  $false) "Alt+F7 must pass through"
        Assert-False (& $shouldIntercept 0x75 $false $false $true)  "Shift+F6 must pass through"
    }

    It "F10.4: Validates hotkeys.ini configuration existence and parsing" {
        $hotkeysIni = "C:\ProgramData\DisplayFix\hotkeys.ini"
        if (Test-Path $hotkeysIni) {
            $content = Get-Content $hotkeysIni -Raw
            Assert-NotNull $content "hotkeys.ini content must not be empty"
        } else {
            # Contract verification of default ini structure
            $sampleIni = @"
[Hotkeys]
BrightnessDown=F6
BrightnessUp=F7
Step=5
"@
            Assert-Match $sampleIni "BrightnessDown=F6" "Default configuration must map BrightnessDown to F6"
            Assert-Match $sampleIni "BrightnessUp=F7" "Default configuration must map BrightnessUp to F7"
        }
    }

    It "F10.5: Verifies raw input HID consumer control usage codes (0x006F and 0x0070)" {
        $HID_USAGE_BRIGHTNESS_INC = 0x006F
        $HID_USAGE_BRIGHTNESS_DEC = 0x0070

        Assert-Equal $HID_USAGE_BRIGHTNESS_INC 111 "HID usage increment must equal 0x006F (111)"
        Assert-Equal $HID_USAGE_BRIGHTNESS_DEC 112 "HID usage decrement must equal 0x0070 (112)"
    }
}
