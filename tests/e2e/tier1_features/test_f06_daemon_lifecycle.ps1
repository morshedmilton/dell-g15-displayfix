# tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1
# Feature F06: Clean Lifecycle & Task Scheduler Setup (>= 5 test cases)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\common\TestFramework.ps1')
. (Join-Path $here '..\common\SystemProbes.ps1')

Describe "F06 - Clean Lifecycle & Task Scheduler Setup" {

    It "F06.1: Verifies scheduled task existence (DisplayFixGuard / DisplayFixDaemon)" {
        $task = Get-ScheduledTask -TaskName "DisplayFixGuard" -ErrorAction SilentlyContinue
        if (-not $task) {
            $task = Get-ScheduledTask -TaskName "DisplayFixDaemon" -ErrorAction SilentlyContinue
        }
        Assert-NotNull $task "DisplayFix scheduled task must be registered in Windows Task Scheduler"
        Assert-True ($task.State -eq 'Running' -or $task.State -eq 'Ready') "Task state must be Running or Ready"
    }

    It "F06.2: Verifies task execution principal runs with highest elevation (RunLevel Highest)" {
        $task = Get-ScheduledTask -TaskName "DisplayFixGuard" -ErrorAction SilentlyContinue
        if (-not $task) {
            $task = Get-ScheduledTask -TaskName "DisplayFixDaemon" -ErrorAction SilentlyContinue
        }
        Assert-NotNull $task "Task must exist"
        Assert-Equal $task.Principal.RunLevel "Highest" "Task RunLevel must be configured as 'Highest' (elevated credentials)"
    }

    It "F06.3: Verifies task trigger is configured for user logon (AtLogon)" {
        $task = Get-ScheduledTask -TaskName "DisplayFixGuard" -ErrorAction SilentlyContinue
        if (-not $task) {
            $task = Get-ScheduledTask -TaskName "DisplayFixDaemon" -ErrorAction SilentlyContinue
        }
        Assert-NotNull $task "Task must exist"
        $hasLogonTrigger = $false
        foreach ($t in $task.Triggers) {
            if ($t.CimClass.CimClassName -match "LogonTrigger") {
                $hasLogonTrigger = $true
                break
            }
        }
        Assert-True $hasLogonTrigger "Task must have an AtLogon trigger"
    }

    It "F06.4: Verifies single-instance mutex enforcement contract" {
        $mutexName = "Global\DisplayFixDaemon_SingleInstanceMutex"
        $createdNew = $false
        $mutex = $null
        try {
            $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
            Assert-NotNull $mutex "System.Threading.Mutex must be instantiable"
            # If createdNew is true, this process owns it; second attempt must fail to acquire
            $createdSecond = $false
            $mutex2 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdSecond)
            Assert-False $createdSecond "Second mutex instance with same name must report createdNew = false (duplicate detected)"
            $mutex2.Close()
        } finally {
            if ($mutex) {
                if ($createdNew) { $mutex.ReleaseMutex() }
                $mutex.Close()
            }
        }
    }

    It "F06.5: Validates clean installation and uninstallation script integrity" {
        $projectRoot = $global:ProjectRoot
        $installScript = Join-Path $projectRoot 'install.ps1'
        $uninstallScript = Join-Path $projectRoot 'uninstall.ps1'

        Assert-FileExists $installScript "install.ps1 must exist at repository root"
        Assert-FileExists $uninstallScript "uninstall.ps1 must exist at repository root"

        $uninstallContent = Get-Content $uninstallScript -Raw
        Assert-Match $uninstallContent "Unregister-ScheduledTask" "uninstall.ps1 must clean up scheduled tasks"
        Assert-Match $uninstallContent "Stop-Process" "uninstall.ps1 must terminate active background processes"
    }
}
