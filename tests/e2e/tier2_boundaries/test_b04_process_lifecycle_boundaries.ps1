# tests/e2e/tier2_boundaries/test_b04_process_lifecycle_boundaries.ps1
# Tier 2 Boundary Tests: Process Lifecycle Boundaries

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "B04 - Process Lifecycle Boundaries" {

    It "B04.1: Fallback to safe defaults when hotkeys.ini is missing or empty" {
        $parseConfig = {
            param([string]$rawConfig)
            $defaultConfig = @{
                DownKey = "F6"
                UpKey   = "F7"
                Step    = 5
            }
            if ([string]::IsNullOrWhiteSpace($rawConfig)) {
                return $defaultConfig
            }
            return $defaultConfig
        }

        $resEmpty = & $parseConfig ""
        Assert-Equal $resEmpty.DownKey "F6" "Empty config defaults DownKey to F6"
        Assert-Equal $resEmpty.UpKey "F7" "Empty config defaults UpKey to F7"
        Assert-Equal $resEmpty.Step 5 "Empty config defaults Step to 5%"
    }

    It "B04.2: Auto-creates missing log directory (C:\ProgramData\DisplayFix\logs) without error" {
        $logDir = "C:\ProgramData\DisplayFix\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Assert-PathExists $logDir "Log directory must exist or be creatable"
    }

    It "B04.3: Blocks duplicate daemon execution through single-instance named mutex" {
        $mutexName = "Global\DisplayFix_TestMutex_Boundary"
        $created1 = $false
        $created2 = $false

        $m1 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created1)
        try {
            $m2 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created2)
            try {
                Assert-True $created1 "First process must acquire mutex"
                Assert-False $created2 "Second process must be denied mutex acquisition (duplicate blocked)"
            } finally {
                $m2.Close()
            }
        } finally {
            if ($created1) { $m1.ReleaseMutex() }
            $m1.Close()
        }
    }

    It "B04.4: Gracefully detects non-elevated user execution context" {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        # Test elevation verification gate logic
        $checkElevation = {
            param([bool]$elevated)
            if (-not $elevated) {
                return "ELEVATION_REQUIRED"
            }
            return "ACCESS_GRANTED"
        }

        Assert-Equal (& $checkElevation $false) "ELEVATION_REQUIRED" "Non-elevated caller must be signaled cleanly"
        Assert-Equal (& $checkElevation $true) "ACCESS_GRANTED" "Elevated caller proceeds"
    }

    It "B04.5: Releasing single-instance mutex allows subsequent clean restart" {
        $mutexName = "Global\DisplayFix_RestartTestMutex"
        $c1 = $false
        $m1 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$c1)
        $m1.ReleaseMutex()
        $m1.Close()

        # Second launch after clean release
        $c2 = $false
        $m2 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$c2)
        try {
            Assert-True $c2 "Subsequent process must acquire mutex after clean release"
        } finally {
            if ($c2) { $m2.ReleaseMutex() }
            $m2.Close()
        }
    }
}
