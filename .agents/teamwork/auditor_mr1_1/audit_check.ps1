# Forensic Audit Inspection Script
$ErrorActionPreference = 'Stop'

Write-Host "=== 1. Task Scheduler & Process Elevation ===" -ForegroundColor Cyan
$task = Get-ScheduledTask -TaskName 'DisplayFixDaemon' -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Task Found: $($task.TaskName)"
    Write-Host "Task State: $($task.State)"
    Write-Host "RunLevel:   $($task.Principal.RunLevel)"
    Write-Host "User:       $($task.Principal.UserId)"
    Write-Host "Action:     $($task.Actions.Execute) $($task.Actions.Arguments)"
} else {
    Write-Host "CRITICAL: Scheduled task DisplayFixDaemon NOT FOUND!" -ForegroundColor Red
}

$proc = Get-Process -Name 'DisplayFixDaemon' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "`nProcess Found: Id=$($proc.Id), Name=$($proc.ProcessName), Path=$($proc.Path)"
    # Check process token elevation
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    Write-Host "Current Auditor Identity: $($identity.Name)"
    
    $exePath = 'C:\ProgramData\DisplayFix\DisplayFixDaemon.exe'
    $w32Proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)"
    Write-Host "Win32_Process ExecutablePath: $($w32Proc.ExecutablePath)"
    Write-Host "Win32_Process CommandLine:    $($w32Proc.CommandLine)"
    
    # Query elevation status from daemon via --status CLI
    $statusOut = & $exePath --status
    Write-Host "`nDaemon --status output:"
    $statusOut | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "CRITICAL: Process DisplayFixDaemon NOT RUNNING!" -ForegroundColor Red
}

Write-Host "`n=== 2. Assembly Comparison (bin/ vs ProgramData) ===" -ForegroundColor Cyan
$p1 = Resolve-Path 'bin\DisplayFixDaemon.exe'
$p2 = 'C:\ProgramData\DisplayFix\DisplayFixDaemon.exe'
$bytes1 = [System.IO.File]::ReadAllBytes($p1)
$bytes2 = [System.IO.File]::ReadAllBytes($p2)
Write-Host "bin/ size:         $($bytes1.Length) bytes"
Write-Host "ProgramData size:  $($bytes2.Length) bytes"

$a1 = [System.Reflection.Assembly]::Load($bytes1)
$a2 = [System.Reflection.Assembly]::Load($bytes2)
Write-Host "bin/ Types:        $($a1.GetTypes().Count)"
Write-Host "ProgramData Types: $($a2.GetTypes().Count)"
Write-Host "bin/ EntryPoint:   $($a1.EntryPoint)"
Write-Host "ProgramData Entry: $($a2.EntryPoint)"
$types1 = $a1.GetTypes() | Select-Object -ExpandProperty FullName | Sort-Object
$types2 = $a2.GetTypes() | Select-Object -ExpandProperty FullName | Sort-Object
$diff = Compare-Object $types1 $types2
if ($diff) {
    Write-Host "Types Difference: $($diff | Out-String)" -ForegroundColor Red
} else {
    Write-Host "Type signatures match exactly 100%!" -ForegroundColor Green
    $types1 | ForEach-Object { Write-Host "  + $_" -ForegroundColor DarkGray }
}

Write-Host "`n=== 3. HKCU Run Registry Cleanliness ===" -ForegroundColor Cyan
$hkcuRun = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).DisplayFixDaemon
if ($null -eq $hkcuRun) {
    Write-Host "HKCU Run Clean: Verified ($null)" -ForegroundColor Green
} else {
    Write-Host "VIOLATION: HKCU Run contains DisplayFixDaemon: $hkcuRun" -ForegroundColor Red
}

Write-Host "`n=== 4. Hotkeys.ini Configuration Inspection ===" -ForegroundColor Cyan
$hotkeysPath = 'C:\ProgramData\DisplayFix\hotkeys.ini'
if (Test-Path $hotkeysPath) {
    $iniContent = Get-Content $hotkeysPath -Raw
    Write-Host "Hotkeys.ini content:"
    Write-Host $iniContent -ForegroundColor Yellow
} else {
    Write-Host "CRITICAL: hotkeys.ini missing at $hotkeysPath" -ForegroundColor Red
}

Write-Host "`n=== 5. Direct NvWmiBrightness WMI Subsystem Test ===" -ForegroundColor Cyan
try {
    $wmiInst = Get-CimInstance -Namespace 'root\wmi' -ClassName 'NvWmiBrightness' -ErrorAction Stop
    Write-Host "NvWmiBrightness instance retrieved: Active=$($wmiInst.Active), InstanceName=$($wmiInst.InstanceName)"
    
    # Test readback (inArg = 0)
    $readRes = Invoke-CimMethod -InputObject $wmiInst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = 0; Level = 0 }
    Write-Host "NvGetSetBrightnessLevel (READ): Result=$($readRes.Result)"
    
    # Test write (inArg = 1, Level = current)
    $currentVal = $readRes.Result
    $writeRes = Invoke-CimMethod -InputObject $wmiInst -MethodName 'NvGetSetBrightnessLevel' -Arguments @{ inArg = 1; Level = [uint32]$currentVal }
    Write-Host "NvGetSetBrightnessLevel (WRITE back $currentVal): Result=$($writeRes.Result)"
} catch {
    Write-Host "WMI Execution Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== 6. Recent Windows Event Logs Check ===" -ForegroundColor Cyan
$recentEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like '*DisplayFix*' -or $_.Message -like '*NvWmi*' -or $_.ProviderName -like '*DisplayFix*' }
if ($recentEvents) {
    Write-Host "Found matching application events:"
    $recentEvents | Format-Table TimeCreated, ProviderName, LevelDisplayName, Message -AutoSize
} else {
    Write-Host "No crash, error, or warning events recorded for DisplayFix in Application log." -ForegroundColor Green
}
