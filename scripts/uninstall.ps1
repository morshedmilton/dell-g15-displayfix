<#
.SYNOPSIS
    Uninstalls DisplayFixDaemon, unregisters scheduled tasks, and cleans runtime files.
.DESCRIPTION
    Stops all background DisplayFix processes, unregisters all scheduled tasks,
    cleans legacy registry entries, and removes C:\ProgramData\DisplayFix.
.PARAMETER InstallDir
    Target destination folder to remove (default: 'C:\ProgramData\DisplayFix').
.PARAMETER KeepLogs
    If specified, retains C:\ProgramData\DisplayFix\logs while removing binaries.
.PARAMETER Force
    Suppresses confirmation prompts.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [string[]]$TaskNames = @('DisplayFixDaemon', 'DisplayFixGuard', 'DisplayFixBrightness'),
    [switch]$KeepLogs,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# 1. Elevation Verification Gate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges are required to uninstall DisplayFix." -ForegroundColor Red
    Write-Host "Please re-run this script in an elevated PowerShell session (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " DELL G15 5530 DISPLAYFIX -- LIFECYCLE UNINSTALLER" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 2. Terminate running background processes
Write-Host "`n--- Stopping Background Processes ---" -ForegroundColor Cyan
$processes = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
foreach ($p in $processes) {
    $running = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Terminating active process: $p (PID: $($running.Id -join ', '))" -ForegroundColor Yellow
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 2

# 3. Unregister Windows Scheduled Tasks
Write-Host "`n--- Unregistering Scheduled Tasks ---" -ForegroundColor Cyan
foreach ($t in $TaskNames) {
    $existingTask = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Unregistered scheduled task: $t" -ForegroundColor Green
    } else {
        Write-Host "  [--] Task not present: $t" -ForegroundColor Gray
    }
}

# 4. Clean legacy Run registry entries
Write-Host "`n--- Cleaning Registry ---" -ForegroundColor Cyan
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runEntries = @('DisplayFixBrightness', 'DisplayFixDaemon')
foreach ($entry in $runEntries) {
    if ((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).$entry) {
        Remove-ItemProperty -Path $runKey -Name $entry -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed HKCU Run entry: $entry" -ForegroundColor Green
    } else {
        Write-Host "  [--] HKCU Run entry not present: $entry" -ForegroundColor Gray
    }
}

# 5. Clean ProgramData Filesystem
Write-Host "`n--- Cleaning Filesystem ($InstallDir) ---" -ForegroundColor Cyan
if (Test-Path $InstallDir) {
    if ($KeepLogs.IsPresent) {
        Write-Host "Preserving logs directory: $InstallDir\logs" -ForegroundColor Yellow
        Get-ChildItem -Path $InstallDir -Exclude 'logs' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            # Reset ownership and ACLs if permissions block removal
            takeown /F $InstallDir /R /D Y | Out-Null
            icacls $InstallDir /grant "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if (-not (Test-Path $InstallDir)) {
        Write-Host "  [OK] Successfully removed $InstallDir" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Some files in $InstallDir could not be deleted (may be open in another viewer)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [--] Installation directory not found: $InstallDir" -ForegroundColor Gray
}

# 6. Verification and Status Report
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host " UNINSTALLATION VERIFICATION" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$remainingTasks = @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue).Count
$remainingProcs = @(Get-Process -Name $processes -ErrorAction SilentlyContinue).Count
$folderExists   = Test-Path $InstallDir

Write-Host "Remaining Tasks:     $remainingTasks (expected: 0)" -ForegroundColor $(if ($remainingTasks -eq 0) { 'Green' } else { 'Red' })
Write-Host "Remaining Processes: $remainingProcs (expected: 0)" -ForegroundColor $(if ($remainingProcs -eq 0) { 'Green' } else { 'Red' })
Write-Host "Install Directory:   $folderExists (expected: False)" -ForegroundColor $(if (-not $folderExists) { 'Green' } else { 'Yellow' })
Write-Host "================================================================================" -ForegroundColor Cyan

exit 0
