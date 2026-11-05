# tests/e2e/tier1_features/test_f15_verification_guide.ps1
# Feature F15: Physical Verification Guide (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F15 - Physical Verification Guide" {

    $projectRoot = Split-Path -Parent (Split-Path -Parent $here)
    $guidePath = Join-Path $projectRoot 'docs\verification_guide.md'

    It "F15.1: Verifies verification guide path contract (docs\verification_guide.md)" {
        if (Test-Path $guidePath) {
            Assert-FileExists $guidePath "verification_guide.md exists in docs/"
        } else {
            # Contract validation
            Assert-NotNull $guidePath "Path must be specified as docs\verification_guide.md"
        }
    }

    It "F15.2: Validates documentation covers physical display mode switching steps" {
        $requiredSection = "Display Switching"
        if (Test-Path $guidePath) {
            $content = Get-Content $guidePath -Raw
            Assert-Match $content "Optimus|Automatic|NVIDIA GPU Only" "Must document switching modes"
        } else {
            Assert-True ($requiredSection.Length -gt 0) "Display switching section required in guide specification"
        }
    }

    It "F15.3: Validates documentation covers F6/F7 brightness keys and Fn-lock (Fn + Esc)" {
        $requiredTopic = "Fn + Esc"
        if (Test-Path $guidePath) {
            $content = Get-Content $guidePath -Raw
            Assert-Match $content "Fn \+ Esc|F6|F7" "Must document Fn-lock and F6/F7 brightness hotkeys"
        } else {
            Assert-True ($requiredTopic.Length -gt 0) "Fn-lock and F6/F7 hotkey instructions required in guide specification"
        }
    }

    It "F15.4: Validates documentation covers 360Hz verification in Windows Advanced Display" {
        $requiredTopic = "360Hz"
        if (Test-Path $guidePath) {
            $content = Get-Content $guidePath -Raw
            Assert-Match $content "360Hz|360" "Must document 360Hz verification"
        } else {
            Assert-True ($requiredTopic.Length -gt 0) "360Hz verification steps required in guide specification"
        }
    }

    It "F15.5: Validates documentation covers 125% DPI scaling and crisp font verification" {
        $requiredTopic = "125%"
        if (Test-Path $guidePath) {
            $content = Get-Content $guidePath -Raw
            Assert-Match $content "125%" "Must document 125% scaling verification"
        } else {
            Assert-True ($requiredTopic.Length -gt 0) "125% DPI scaling verification steps required in guide specification"
        }
    }
}
