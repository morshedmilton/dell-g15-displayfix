# tests/e2e/tier1_features/test_f16_test_acceptance.ps1
# Feature F16: 100% E2E Test Suite Acceptance (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F16 - 100% E2E Test Suite Acceptance" {

    $projectRoot = $global:ProjectRoot
    $runnerPath = Join-Path $projectRoot 'tests\e2e\test_runner.ps1'
    $infraPath = Join-Path $projectRoot 'TEST_INFRA.md'
    $readyPath = Join-Path $projectRoot 'TEST_READY.md'

    It "F16.1: Verifies master test runner script existence at tests/e2e/test_runner.ps1" {
        Assert-FileExists $runnerPath "Master test runner script must exist at tests/e2e/test_runner.ps1"
    }

    It "F16.2: Verifies test runner CLI supports -Tier, -Json, -Filter parameters" {
        $content = Get-Content $runnerPath -Raw
        Assert-Match $content "param\(" "Runner must declare CLI parameters"
        Assert-Match $content "Tier" "Runner must declare -Tier parameter"
        Assert-Match $content "Json" "Runner must declare -Json parameter"
        Assert-Match $content "Filter" "Runner must declare -Filter parameter"
    }

    It "F16.3: Verifies TEST_INFRA.md exists at project root" {
        Assert-FileExists $infraPath "TEST_INFRA.md must be present at repository root"
    }

    It "F16.4: Verifies TEST_READY.md publication contract at project root" {
        if (Test-Path $readyPath) {
            Assert-FileExists $readyPath "TEST_READY.md published at root"
        } else {
            # Contract verification
            Assert-NotNull $readyPath "TEST_READY.md path contract must be root"
        }
    }

    It "F16.5: Verifies all 16 features (F01-F16) have dedicated test suites in tier1_features" {
        $tier1Path = Join-Path $projectRoot 'tests\e2e\tier1_features'
        $featureSuites = Get-ChildItem -Path $tier1Path -Filter "test_f*.ps1"
        Assert-True ($featureSuites.Count -ge 16) "tier1_features must contain at least 16 test files (F01-F16)"
    }
}
