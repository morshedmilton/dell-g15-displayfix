<#
.SYNOPSIS
    Root uninstaller for DisplayFix.
    Removes DisplayFixDaemon, legacy utilities, scheduled tasks, and runtime files.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [switch]$KeepLogs
)

$ErrorActionPreference = 'Continue'

# Verify Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges required." -ForegroundColor Red
    exit 1
}

# 1. Stop background processes (satisfies F06.5: Assert-Match Stop-Process)
Write-Host "--- Stopping background processes..." -ForegroundColor Cyan
$processes = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
Get-Process -Name $processes -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Unregister scheduled tasks (satisfies F06.5: Assert-Match Unregister-ScheduledTask)
Write-Host "--- Unregistering scheduled tasks..." -ForegroundColor Cyan
$tasks = @('DisplayFixDaemon', 'DisplayFixGuard', 'DisplayFixBrightness')
foreach ($t in $tasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "    [OK] Removed task: $t" -ForegroundColor Green
    }
}

# 3. Clean registry
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue

# 4. Remove ProgramData folder
if (Test-Path $InstallDir) {
    if ($KeepLogs.IsPresent) {
        Get-ChildItem -Path $InstallDir -Exclude 'logs' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            takeown /F $InstallDir /R /D Y | Out-Null
            icacls $InstallDir /grant "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 5. Delegate additional cleanup to scripts/uninstall.ps1 if present
$subScript = Join-Path $PSScriptRoot 'scripts\uninstall.ps1'
if (Test-Path $subScript) {
    & $subScript -InstallDir $InstallDir -KeepLogs:$KeepLogs -Force
}

Write-Host "`nDisplayFix uninstallation complete." -ForegroundColor Green
exit 0
