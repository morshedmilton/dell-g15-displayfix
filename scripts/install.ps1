<#
.SYNOPSIS
    Installs DisplayFixDaemon as an elevated Windows Scheduled Task at user logon.
.DESCRIPTION
    Deploys DisplayFixDaemon.exe to C:\ProgramData\DisplayFix, configures logging directories,
    unregisters legacy utilities (DisplayFixGuard, DisplayFixBrightness), and creates a
    high-priority logon scheduled task (RunLevel: Highest).
.PARAMETER InstallDir
    Target destination folder (default: 'C:\ProgramData\DisplayFix').
.PARAMETER TaskName
    Scheduled task name (default: 'DisplayFixDaemon').
.PARAMETER InPlace
    If specified, configures the scheduled task to execute directly from repository bin/
    without copying files to ProgramData (useful for local development).
.PARAMETER NoStart
    If specified, registers the task without starting it immediately.
.PARAMETER BuildIfMissing
    Automatically runs build.ps1 if DisplayFixDaemon.exe is not found in bin/.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [string]$TaskName = 'DisplayFixDaemon',
    [switch]$InPlace,
    [switch]$NoStart,
    [switch]$BuildIfMissing = $true
)

$ErrorActionPreference = 'Stop'

# 1. Elevation Verification Gate
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges are required to install DisplayFixDaemon." -ForegroundColor Red
    Write-Host "Please re-run this script in an elevated PowerShell session (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " DELL G15 5530 DISPLAYFIX -- LIFECYCLE INSTALLER" -ForegroundColor Cyan
Write-Host " User: $($identity.Name) | Elevation: HighestAvailable" -ForegroundColor DarkCyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 2. Determine paths
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$binDir      = Join-Path $projectRoot 'bin'
$buildScript = Join-Path $scriptDir 'build.ps1'
$sourceExe   = Join-Path $binDir 'DisplayFixDaemon.exe'

# Fallback check for building if binary is missing
if (-not (Test-Path $sourceExe)) {
    if ($BuildIfMissing) {
        Write-Host "`n[BUILD] DisplayFixDaemon.exe not found in bin/. Launching build script..." -ForegroundColor Yellow
        if (Test-Path $buildScript) {
            & $buildScript
        } else {
            & (Join-Path $projectRoot 'build.ps1')
        }
    }
}

if (-not (Test-Path $sourceExe)) {
    Write-Error "DisplayFixDaemon.exe not found at $sourceExe. Run scripts/build.ps1 first."
    exit 1
}

# 3. Terminate active background processes
Write-Host "`n--- Stopping Active Processes ---" -ForegroundColor Cyan
$processesToStop = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
$stoppedAny = $false
foreach ($pName in $processesToStop) {
    $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping process: $pName (PID: $($procs.Id -join ', '))" -ForegroundColor Yellow
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        $stoppedAny = $true
    }
}
if ($stoppedAny) {
    Start-Sleep -Seconds 2
} else {
    Write-Host "No active DisplayFix processes found running." -ForegroundColor Gray
}

# 4. Prepare deployment directories
$logDir = Join-Path $InstallDir 'logs'
Write-Host "`n--- Preparing Filesystem ---" -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created installation directory: $InstallDir" -ForegroundColor Green
}
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Host "Created log directory: $logDir" -ForegroundColor Green
}

# Determine target execution path
$targetExe = ''
$targetWorkDir = ''

if ($InPlace) {
    Write-Host "Configuring in-place execution from: $sourceExe" -ForegroundColor Yellow
    $targetExe     = $sourceExe
    $targetWorkDir = $binDir
} else {
    $destExe = Join-Path $InstallDir (Split-Path -Leaf $sourceExe)
    Write-Host "Deploying binary: $sourceExe -> $destExe" -ForegroundColor White
    Copy-Item -Path $sourceExe -Destination $destExe -Force
    
    # Copy configuration or manifest if present
    $sourceConfig = "$sourceExe.config"
    if (Test-Path $sourceConfig) {
        Copy-Item -Path $sourceConfig -Destination (Join-Path $InstallDir (Split-Path -Leaf $sourceConfig)) -Force
    }

    # Provision hotkeys.ini if missing or placeholder
    $hotkeysIniPath = Join-Path $InstallDir 'hotkeys.ini'
    $needsConfig = $true
    if (Test-Path $hotkeysIniPath) {
        $existingConfig = Get-Content $hotkeysIniPath -Raw -ErrorAction SilentlyContinue
        if ($existingConfig -and $existingConfig -notmatch 'Intentionally empty' -and $existingConfig -match 'BrightnessDown') {
            $needsConfig = $false
        }
    }
    if ($needsConfig) {
        $defaultConfig = @"
[Hotkeys]
BrightnessDown=F6
BrightnessUp=F7
Step=5
Mute=F1
VolumeDown=F2
VolumeUp=F3
PlayPause=F9
"@
        Set-Content -Path $hotkeysIniPath -Value $defaultConfig -Encoding UTF8
        Write-Host "Provisioned active hotkey configuration: $hotkeysIniPath" -ForegroundColor Green
    }

    $targetExe     = $destExe
    $targetWorkDir = $InstallDir
}

# 5. Unregister legacy scheduled tasks and existing daemon task
Write-Host "`n--- Configuring Windows Scheduled Tasks ---" -ForegroundColor Cyan
$legacyTasks = @('DisplayFixGuard', 'DisplayFixBrightness', $TaskName)
foreach ($t in $legacyTasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Write-Host "Unregistering task: $t" -ForegroundColor Gray
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Remove non-elevated HKCU Run entries if present
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runEntries = @('DisplayFixBrightness', 'DisplayFixDaemon')
foreach ($entry in $runEntries) {
    if ((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).$entry) {
        Write-Host "Removing non-elevated Run key: $entry" -ForegroundColor Gray
        Remove-ItemProperty -Path $runKey -Name $entry -ErrorAction SilentlyContinue
    }
}

# 6. Register unified Scheduled Task
$user = $identity.Name

$action = New-ScheduledTaskAction `
    -Execute $targetExe `
    -Argument '--run' `
    -WorkingDirectory $targetWorkDir

$trigger = New-ScheduledTaskTrigger `
    -AtLogOn `
    -User $user

$principalObj = New-ScheduledTaskPrincipal `
    -UserId $user `
    -LogonType Interactive `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval ([TimeSpan]::FromMinutes(1))

$description = 'Dell G15 5530 DisplayFix Daemon: Enforces 360Hz refresh rate, 125% DPI scaling, F6/F7 brightness control, and sub-second ghost monitor eviction.'

$regTask = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principalObj `
    -Settings $settings `
    -Description $description

Write-Host "Successfully registered scheduled task: $TaskName" -ForegroundColor Green
Write-Host "  Trigger:   AtLogon ($user)" -ForegroundColor Gray
Write-Host "  Principal: $user (RunLevel: Highest)" -ForegroundColor Gray
Write-Host "  Execute:   $targetExe --run" -ForegroundColor Gray
Write-Host "  WorkDir:   $targetWorkDir" -ForegroundColor Gray

# 7. Start task immediately
if (-not $NoStart) {
    Write-Host "`n--- Starting Task ---" -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
}

# 8. Report Status
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host " INSTALLATION STATUS" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$finalTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$finalProc = Get-Process -Name (([System.IO.Path]::GetFileNameWithoutExtension($targetExe))) -ErrorAction SilentlyContinue

Write-Host "Task Name:   $($finalTask.TaskName)"
Write-Host "Task State:  $($finalTask.State)" -ForegroundColor $(if ($finalTask.State -eq 'Running' -or $finalTask.State -eq 'Ready') { 'Green' } else { 'Yellow' })
Write-Host "RunLevel:    $($finalTask.Principal.RunLevel)"
Write-Host "Process ID:  $(if ($finalProc) { $finalProc.Id } else { 'Pending background start' })"
Write-Host "Log File:    $logDir\daemon.log"
Write-Host "================================================================================" -ForegroundColor Cyan

exit 0
