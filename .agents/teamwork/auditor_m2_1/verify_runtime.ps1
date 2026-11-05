# verify_runtime.ps1
$ErrorActionPreference = 'Stop'

Write-Host "=== TEST 1: Named Mutex and Duplicate Blocking ==="
$proc = Start-Process -FilePath "bin\DisplayFixDaemon.exe" -ArgumentList "--run" -PassThru
Start-Sleep -Milliseconds 600

try {
    $m = $null
    $exists = [System.Threading.Mutex]::TryOpenExisting("Global\DisplayFixDaemon_SingleInstanceMutex", [ref]$m)
    Write-Host "Mutex exists while daemon is running: $exists"
    if ($m) { $m.Close() }

    $proc2 = Start-Process -FilePath "bin\DisplayFixDaemon.exe" -ArgumentList "--run" -Wait -PassThru
    Write-Host "Duplicate instance exit code: $($proc2.ExitCode)"
}
finally {
    if (-not $proc.HasExited) {
        $proc.Kill()
        $proc.WaitForExit()
        Write-Host "Background daemon killed successfully."
    }
}

Start-Sleep -Milliseconds 500
$mAfter = $null
$existsAfter = [System.Threading.Mutex]::TryOpenExisting("Global\DisplayFixDaemon_SingleInstanceMutex", [ref]$mAfter)
Write-Host "Mutex exists after daemon killed: $existsAfter"
if ($mAfter) { $mAfter.Close() }

Write-Host "`n=== TEST 2: SetupAPI & CfgMgr32 Calls via --evict-now ==="
$logFile = "C:\ProgramData\DisplayFix\logs\daemon.log"
$initialLength = 0
if (Test-Path $logFile) {
    $initialLength = (Get-Item $logFile).Length
}

$evictProc = Start-Process -FilePath "bin\DisplayFixDaemon.exe" -ArgumentList "--evict-now" -Wait -PassThru
Write-Host "Evict-now exit code: $($evictProc.ExitCode)"

if (Test-Path $logFile) {
    $newContent = Get-Content $logFile -Tail 10
    Write-Host "Recent daemon.log entries:"
    $newContent | ForEach-Object { Write-Host "  $_" }
}

Write-Host "`n=== TEST 3: Direct In-Process C# Reflection Verification ==="
# Load compiled assembly and invoke GhostEvictionEngine directly
$assemblyPath = Resolve-Path "bin\DisplayFixDaemon.exe"
$bytes = [System.IO.File]::ReadAllBytes($assemblyPath)
$asm = [System.Reflection.Assembly]::Load($bytes)
$engineType = $asm.GetType("DisplayFix.Daemon.GhostEvictionEngine")
$monitors = $engineType.GetMethod("EnumerateMonitors").Invoke($null, @($false))
Write-Host "GhostEvictionEngine.EnumerateMonitors() returned $($monitors.Count) device nodes:"
foreach ($mon in $monitors) {
    Write-Host "  - InstanceId: $($mon.InstanceId)"
    Write-Host "    Present: $($mon.IsPresent), Status: 0x$($mon.DevNodeStatus.ToString('X8')), Parent: $($mon.ParentDeviceId)"
    Write-Host "    IsInternal: $($mon.IsInternalPanel), IsIntelGhost: $($mon.IsIntelGhost), IsNvidiaActive: $($mon.IsNvidiaActive), IsForeign: $($mon.IsForeign)"
}
