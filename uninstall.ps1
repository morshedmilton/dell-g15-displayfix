# Removes both display tools and every trace they leave.
# Run elevated:  powershell -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = 'Continue'

$installDir = 'C:\ProgramData\DisplayFix'
$taskName   = 'DisplayFixGuard'
$runKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) { throw 'Run this script as Administrator.' }

Write-Host '--- stopping processes'
Get-Process PhantomGuard, NvBrightness -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host '--- removing scheduled task'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host '    removed'
}

Write-Host '--- removing startup entry'
Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue

Write-Host '--- removing ProgramData folder'
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $installDir) {
        takeown /F $installDir /R /D Y | Out-Null
        icacls $installDir /grant "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '--- verify'
'task     : ' + [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
'folder   : ' + (Test-Path $installDir)
'processes: ' + @(Get-Process PhantomGuard, NvBrightness -ErrorAction SilentlyContinue).Count
'run entry: ' + [bool]((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).DisplayFixBrightness)

Write-Host ''
Write-Host 'Note: display mode is untouched. Set it in NVIDIA Control Panel.'
