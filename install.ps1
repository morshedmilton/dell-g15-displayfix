# Installs the two display tools for this machine.
#   PhantomGuard.exe -> scheduled task at logon, highest privileges (needs admin)
#   NvBrightness.exe -> HKCU Run entry (normal user session)
#
# Run elevated:  powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'

$installDir = 'C:\ProgramData\DisplayFix'
$logDir     = Join-Path $installDir 'logs'
$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir     = Join-Path $here 'bin'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) { throw 'Run this script as Administrator.' }

foreach ($exe in 'PhantomGuard.exe', 'NvBrightness.exe') {
    if (-not (Test-Path (Join-Path $binDir $exe))) { throw "missing $exe - run build.ps1 first" }
}

Write-Host '--- stopping anything already running'
Get-Process PhantomGuard, NvBrightness -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "--- copying to $installDir"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir     -Force | Out-Null
Copy-Item (Join-Path $binDir 'PhantomGuard.exe') $installDir -Force
Copy-Item (Join-Path $binDir 'NvBrightness.exe') $installDir -Force

Write-Host '--- scheduled task: DisplayFixGuard'
$taskName = 'DisplayFixGuard'
$user     = [Security.Principal.WindowsIdentity]::GetCurrent().Name

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action    = New-ScheduledTaskAction -Execute (Join-Path $installDir 'PhantomGuard.exe')
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(2))

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Description 'Clears the stale duplicate display path left by Advanced Optimus / DDS.' | Out-Null

Write-Host '--- scheduled task: DisplayFixBrightness'
# The NVIDIA brightness WMI provider (root\wmi:NvWmiBrightness) refuses access to a
# non-elevated caller once the panel has muxed to the dGPU, so the tray app has to run
# elevated. A scheduled task gives that without a UAC prompt at every logon.
$brightTask = 'DisplayFixBrightness'

Unregister-ScheduledTask -TaskName $brightTask -Confirm:$false -ErrorAction SilentlyContinue

$bAction    = New-ScheduledTaskAction -Execute (Join-Path $installDir 'NvBrightness.exe')
$bTrigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$bPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$bSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $brightTask -Action $bAction -Trigger $bTrigger `
    -Principal $bPrincipal -Settings $bSettings -Description 'Tray brightness control that works on both GPUs.' | Out-Null

Write-Host '--- removing the old per-user Run entry (it could not write brightness)'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue

Write-Host '--- starting both now'
Start-ScheduledTask -TaskName $taskName
Start-ScheduledTask -TaskName $brightTask
Start-Sleep -Seconds 5

Write-Host ''
Write-Host '--- status'
Get-ScheduledTask -TaskName $taskName, $brightTask -ErrorAction SilentlyContinue |
    Select-Object TaskName, State | Format-Table -AutoSize
Get-Process PhantomGuard, NvBrightness -ErrorAction SilentlyContinue |
    Select-Object ProcessName, Id | Format-Table -AutoSize
'run entry present: ' + [bool]((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).DisplayFixBrightness)
