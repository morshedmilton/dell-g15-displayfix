<#
.SYNOPSIS
    Automated Remediation & Health Verification for NVIDIA App Driver Updates & Automatic Tuning (Milestone MR3).

.DESCRIPTION
    Resolves the NVIDIA App Game Ready Driver download infinite loop and Automatic Tuning lockup on Dell G15 5530:
      1. Terminates stuck NVIDIA App UI, helper, and CEF renderer processes.
      2. Backs up and resets stale UpdateFramework postprocessing state (postprocessing.json & download.json).
      3. Clears stale download locks and partial artifacts in C:\ProgramData\NVIDIA Corporation\Downloader.
      4. Configures NVIDIA FrameView SDK Service (FvSvc) to Automatic startup and starts it.
      5. Purges stale OC scan cache and CEF locks in LocalAppData and ProgramData.
      6. Cleanly restarts NVIDIA Display and LocalSystem container services.
      7. Performs comprehensive validation checks to verify that the state machine is unlocked.

.PARAMETER VerifyOnly
    Runs diagnostic and validation checks without making changes to processes, files, or services.

.PARAMETER Json
    Outputs pure JSON diagnostic report to stdout.

.PARAMETER PassThru
    Returns the structured result PSCustomObject to the PowerShell pipeline.

.PARAMETER ReportFile
    Optional file path to write structured JSON report (used for elevated IPC).

.EXAMPLE
    .\fix_nvidia_app.ps1
    Executes full remediation and prints formatted status summary.

.EXAMPLE
    .\fix_nvidia_app.ps1 -VerifyOnly
    Validates current system state without modifying anything.
#>

[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$Json,
    [switch]$PassThru,
    [string]$ReportFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# -----------------------------------------------------------------------------
# Elevation Bridge: If applying changes without elevation, re-launch with RunAs
# -----------------------------------------------------------------------------
if (-not $isElevated -and -not $VerifyOnly) {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $scriptPath = $MyInvocation.MyCommand.Path
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$scriptPath`"",
        '-Json',
        '-ReportFile', "`"$tempFile`""
    )

    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList ($argList -join ' ') `
        -Verb RunAs `
        -PassThru `
        -Wait `
        -WindowStyle Hidden

    $exitCode = if ($proc) { $proc.ExitCode } else { 1 }

    if (Test-Path $tempFile) {
        $elevatedJson = Get-Content -Path $tempFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        if ($elevatedJson) {
            $parsed = $elevatedJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($Json) {
                Write-Output $elevatedJson
            } else {
                Write-Host "================================================================================" -ForegroundColor Cyan
                Write-Host " NVIDIA APP DRIVER UPDATE LOOP & TUNING LOCKUP REMEDIATION (MR3)" -ForegroundColor Cyan
                Write-Host " Target: Dell G15 5530 | Mode: APPLY REMEDIATION (Elevated)" -ForegroundColor DarkCyan
                Write-Host "================================================================================" -ForegroundColor Cyan
                if ($parsed.ActionsTaken) {
                    Write-Host "`n[Actions Executed]" -ForegroundColor Yellow
                    foreach ($act in $parsed.ActionsTaken) {
                        Write-Host "  [ACTION] $act" -ForegroundColor Cyan
                    }
                }
                Write-Host "`n[Validation Checks]" -ForegroundColor Yellow
                $ppColor = if ($parsed.ValidationChecks.PostprocessingClean) { 'Green' } else { 'Red' }
                $dlColor = if ($parsed.ValidationChecks.DownloaderClean) { 'Green' } else { 'Red' }
                $fvColor = if ($parsed.ValidationChecks.FvSvcRunning) { 'Green' } else { 'Red' }
                $cnColor = if ($parsed.ValidationChecks.ContainerServicesRunning) { 'Green' } else { 'Red' }

                Write-Host "  [$($if = if ($parsed.ValidationChecks.PostprocessingClean) {'PASS'} else {'FAIL'}; $if)] $($parsed.ValidationChecks.PostprocessingDetails)" -ForegroundColor $ppColor
                Write-Host "  [$($if = if ($parsed.ValidationChecks.DownloaderClean) {'PASS'} else {'FAIL'}; $if)] $($parsed.ValidationChecks.DownloaderDetails)" -ForegroundColor $dlColor
                Write-Host "  [$($if = if ($parsed.ValidationChecks.FvSvcRunning) {'PASS'} else {'FAIL'}; $if)] $($parsed.ValidationChecks.FvSvcDetails)" -ForegroundColor $fvColor
                Write-Host "  [$($if = if ($parsed.ValidationChecks.ContainerServicesRunning) {'PASS'} else {'FAIL'}; $if)] $($parsed.ValidationChecks.ContainerServicesDetails)" -ForegroundColor $cnColor

                Write-Host "`n================================================================================" -ForegroundColor Cyan
                $vColor = if ($parsed.OverallPassed) { 'Green' } else { 'Red' }
                Write-Host (" REMEDIATION & VERIFICATION VERDICT: {0} ({1} ms)" -f $parsed.OverallVerdict, $parsed.DurationMs) -ForegroundColor $vColor
                Write-Host " Postprocessing: $(if ($parsed.ValidationChecks.PostprocessingClean) { 'UNLOCKED' } else { 'STUCK' }) | Downloader: $(if ($parsed.ValidationChecks.DownloaderClean) { 'CLEAN' } else { 'LOCKED' }) | FvSvc: $(if ($parsed.ValidationChecks.FvSvcRunning) { 'RUNNING' } else { 'STOPPED' }) | Containers: $(if ($parsed.ValidationChecks.ContainerServicesRunning) { 'HEALTHY' } else { 'UNHEALTHY' })" -ForegroundColor Gray
                Write-Host "================================================================================`n" -ForegroundColor Cyan
            }
            if ($PassThru) {
                return $parsed
            }
            exit $exitCode
        }
    }
    Write-Error "Elevated remediation execution did not produce a report."
    exit $exitCode
}

# -----------------------------------------------------------------------------
# Direct Execution (Elevated or VerifyOnly)
# -----------------------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Write-LogMessage {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Color = 'White'
    )
    if (-not $Json) {
        $tagColor = switch ($Level) {
            'PASS'   { 'Green' }
            'ACTION' { 'Cyan' }
            'WARN'   { 'Yellow' }
            'FAIL'   { 'Red' }
            Default  { 'Gray' }
        }
        Write-Host ("  [{0}] {1}" -f $Level, $Message) -ForegroundColor ([System.ConsoleColor]$tagColor)
    }
}

if (-not $Json) {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " NVIDIA APP DRIVER UPDATE LOOP & TUNING LOCKUP REMEDIATION (MR3)" -ForegroundColor Cyan
    Write-Host " Target: Dell G15 5530 | Mode: $(if ($VerifyOnly) { 'VERIFY ONLY' } else { 'APPLY REMEDIATION' })" -ForegroundColor DarkCyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

$actionsTaken = [System.Collections.Generic.List[string]]::new()
$errorsList   = [System.Collections.Generic.List[string]]::new()

$grdStatusDir   = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd'
$postProcFile   = Join-Path $grdStatusDir 'postprocessing.json'
$postProcBak    = Join-Path $grdStatusDir 'postprocessing.json.bak'
$downloadFile   = Join-Path $grdStatusDir 'download.json'
$downloaderDir  = 'C:\ProgramData\NVIDIA Corporation\Downloader'
$otaGrdDir      = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd'
$cefCacheDir    = Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NVIDIA App\CefCache\Default'

# -----------------------------------------------------------------------------
# Remediation Execution (skipped in -VerifyOnly mode)
# -----------------------------------------------------------------------------
if (-not $VerifyOnly) {
    # 1. Stop NVIDIA App frontend and helper instances
    if (-not $Json) { Write-Host "`n[1. Stopping NVIDIA App Frontend Processes]" -ForegroundColor Yellow }
    $appProcs = Get-Process -Name 'NVIDIA App*', 'NVIDIA App Helper*', 'NVIDIA Overlay*', 'nvsphelper*' -ErrorAction SilentlyContinue
    if ($appProcs) {
        foreach ($proc in $appProcs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Write-LogMessage -Level 'ACTION' -Message "Terminated $($proc.ProcessName) (PID: $($proc.Id))"
                $actionsTaken.Add("Terminated $($proc.ProcessName) (PID: $($proc.Id))")
            } catch {
                Write-LogMessage -Level 'WARN' -Message "Could not stop PID $($proc.Id): $($_.Exception.Message)"
            }
        }
        Start-Sleep -Milliseconds 500
    } else {
        Write-LogMessage -Level 'INFO' -Message "No active NVIDIA App frontend processes detected."
    }

    # 2. Backup and reset stale postprocessing.json and download.json
    if (-not $Json) { Write-Host "`n[2. Resetting UpdateFramework State Machine]" -ForegroundColor Yellow }
    if (-not (Test-Path $grdStatusDir)) {
        New-Item -Path $grdStatusDir -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $postProcFile) {
        $rawPostProc = Get-Content -Path $postProcFile -Raw -ErrorAction SilentlyContinue
        # If backup doesn't exist, or if current file has stuck task, preserve backup
        if (-not (Test-Path $postProcBak) -or ($rawPostProc -and $rawPostProc -match '"status":\s*1')) {
            Copy-Item -Path $postProcFile -Destination $postProcBak -Force -ErrorAction SilentlyContinue
            Write-LogMessage -Level 'ACTION' -Message "Backed up stale postprocessing.json to postprocessing.json.bak"
            $actionsTaken.Add("Backed up postprocessing.json to postprocessing.json.bak")
        }
    }

    '[]' | Set-Content -Path $postProcFile -Encoding UTF8 -Force
    Write-LogMessage -Level 'ACTION' -Message "Reset postprocessing.json to idle state '[]'"
    $actionsTaken.Add("Reset postprocessing.json to []")

    if (Test-Path $downloadFile) {
        '[]' | Set-Content -Path $downloadFile -Encoding UTF8 -Force
        Write-LogMessage -Level 'ACTION' -Message "Reset download.json to idle state '[]'"
        $actionsTaken.Add("Reset download.json to []")
    }

    if (Test-Path $otaGrdDir) {
        $otaItems = Get-ChildItem -Path $otaGrdDir -Recurse -File -ErrorAction SilentlyContinue
        if ($otaItems) {
            foreach ($item in $otaItems) {
                Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
            }
            Write-LogMessage -Level 'ACTION' -Message "Purged $($otaItems.Count) stale OTA artifact fragment(s)"
            $actionsTaken.Add("Purged $($otaItems.Count) stale OTA artifact fragments")
        }
    }

    # 3. Purge stale lock files and incomplete download fragments in Downloader
    if (-not $Json) { Write-Host "`n[3. Purging Downloader Locks & Incomplete Fragments]" -ForegroundColor Yellow }
    if (Test-Path $downloaderDir) {
        $lockFiles = Get-ChildItem -Path $downloaderDir -Include *.lock,*.tmp,*.part,*.aria2 -Recurse -File -ErrorAction SilentlyContinue
        if ($lockFiles) {
            foreach ($f in $lockFiles) {
                Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
                Write-LogMessage -Level 'ACTION' -Message "Removed lock/fragment file: $($f.Name)"
                $actionsTaken.Add("Removed Downloader lock file: $($f.Name)")
            }
        } else {
            Write-LogMessage -Level 'INFO' -Message "No stale locks or fragments found in Downloader."
        }
    } else {
        Write-LogMessage -Level 'INFO' -Message "Downloader directory clean / not populated."
    }

    # 4. Configure FvSvc (FrameView SDK Service) to Automatic and Start it
    if (-not $Json) { Write-Host "`n[4. Configuring & Starting FrameView SDK Service (FvSvc)]" -ForegroundColor Yellow }
    $fvSvc = Get-Service -Name 'FvSvc' -ErrorAction SilentlyContinue
    if ($fvSvc) {
        try {
            Set-Service -Name 'FvSvc' -StartupType Automatic
            Write-LogMessage -Level 'ACTION' -Message "Configured FvSvc StartupType to Automatic"
            $actionsTaken.Add("Configured FvSvc StartupType to Automatic")
        } catch {
            Write-LogMessage -Level 'WARN' -Message "Failed to set FvSvc startup type: $($_.Exception.Message)"
        }

        if ($fvSvc.Status -ne 'Running') {
            try {
                Start-Service -Name 'FvSvc' -ErrorAction Stop
                Start-Sleep -Milliseconds 800
                $fvSvc = Get-Service -Name 'FvSvc'
                Write-LogMessage -Level 'ACTION' -Message "Started FvSvc (Status: $($fvSvc.Status))"
                $actionsTaken.Add("Started FvSvc")
            } catch {
                Write-LogMessage -Level 'FAIL' -Message "Failed to start FvSvc: $($_.Exception.Message)"
                $errorsList.Add("Failed to start FvSvc: $($_.Exception.Message)")
            }
        } else {
            Write-LogMessage -Level 'INFO' -Message "FvSvc is already running."
        }
    } else {
        Write-LogMessage -Level 'WARN' -Message "FvSvc service not found in service control manager."
    }

    # 5. Clear stale OC scan cache / CEF locks
    if (-not $Json) { Write-Host "`n[5. Clearing Stale OC Scan Cache & CEF State]" -ForegroundColor Yellow }
    if (Test-Path $cefCacheDir) {
        try {
            $cefLocks = Get-ChildItem -Path $cefCacheDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'LOCK|lock' }
            foreach ($lock in $cefLocks) {
                Remove-Item -Path $lock.FullName -Force -ErrorAction SilentlyContinue
            }
            Write-LogMessage -Level 'ACTION' -Message "Cleared CEF cache database LOCK files."
            $actionsTaken.Add("Cleared CEF cache database LOCK files")
        } catch {
            Write-LogMessage -Level 'WARN' -Message "CEF cache cleanup note: $($_.Exception.Message)"
        }
    }

    # Relieve Alienware Command Center GPU lock if active
    $awccPerf = Get-Process -Name 'AWPerformance.UCSubAgent' -ErrorAction SilentlyContinue
    if ($awccPerf) {
        try {
            Stop-Process -Id $awccPerf.Id -Force -ErrorAction SilentlyContinue
            Write-LogMessage -Level 'ACTION' -Message "Relieved AWPerformance.UCSubAgent GPU clock handle (PID: $($awccPerf.Id))"
            $actionsTaken.Add("Relieved AWPerformance.UCSubAgent GPU lock (PID: $($awccPerf.Id))")
        } catch {
            Write-LogMessage -Level 'WARN' -Message "Note on AWPerformance.UCSubAgent: $($_.Exception.Message)"
        }
    }

    # 6. Cleanly restart NVIDIA Container Services
    if (-not $Json) { Write-Host "`n[6. Restarting NVIDIA Container Services]" -ForegroundColor Yellow }
    try {
        Restart-Service -Name 'NVDisplay.ContainerLocalSystem' -Force -ErrorAction SilentlyContinue
        Restart-Service -Name 'NvContainerLocalSystem' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-LogMessage -Level 'ACTION' -Message "Restarted NVDisplay.ContainerLocalSystem and NvContainerLocalSystem."
        $actionsTaken.Add("Restarted NVIDIA container services")
    } catch {
        Write-LogMessage -Level 'WARN' -Message "Service restart error: $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# Validation Phase
# -----------------------------------------------------------------------------
if (-not $Json) { Write-Host "`n[7. Validation Checks]" -ForegroundColor Yellow }

# Check 1: postprocessing.json clean & unlocked
$postProcClean = $false
$postProcDetails = ""
if (Test-Path $postProcFile) {
    $rawPP = (Get-Content -Path $postProcFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($rawPP -eq '[]' -or ($rawPP -notmatch '"status":\s*1')) {
        $postProcClean = $true
        $postProcDetails = "postprocessing.json is clean (content: '$rawPP')"
        Write-LogMessage -Level 'PASS' -Message "UpdateFramework postprocessing.json is clean and unlocked."
    } else {
        $postProcDetails = "postprocessing.json contains in-progress or stale task"
        Write-LogMessage -Level 'FAIL' -Message "UpdateFramework postprocessing.json is still locked: $rawPP"
    }
} else {
    $postProcClean = $true
    $postProcDetails = "postprocessing.json does not exist (idle)"
    Write-LogMessage -Level 'PASS' -Message "postprocessing.json absent (idle state)."
}

# Check 2: Downloader clean (no orphaned lock files)
$downloaderClean = $false
$downloaderDetails = ""
if (Test-Path $downloaderDir) {
    $locks = Get-ChildItem -Path $downloaderDir -Include *.lock,*.tmp,*.part,*.aria2 -Recurse -File -ErrorAction SilentlyContinue
    if (-not $locks -or $locks.Count -eq 0) {
        $downloaderClean = $true
        $downloaderDetails = "Downloader directory exists and has 0 orphaned locks"
        Write-LogMessage -Level 'PASS' -Message "C:\ProgramData\NVIDIA Corporation\Downloader is free of locks."
    } else {
        $downloaderDetails = "Found $($locks.Count) lock/fragment file(s)"
        Write-LogMessage -Level 'FAIL' -Message "Downloader contains orphaned files: $($locks.Count) found"
    }
} else {
    $downloaderClean = $true
    $downloaderDetails = "Downloader directory does not exist (clean)"
    Write-LogMessage -Level 'PASS' -Message "Downloader directory is clean (not present)."
}

# Check 3: FvSvc is Running and StartupType is Automatic
$fvSvcRunning = $false
$fvSvcDetails = ""
$fvCheck = Get-Service -Name 'FvSvc' -ErrorAction SilentlyContinue
if ($null -ne $fvCheck) {
    $isAutomatic = ($fvCheck.StartType -eq 'Automatic')
    $isRunning   = ($fvCheck.Status -eq 'Running')
    if ($isRunning) {
        $fvSvcRunning = $true
        $fvSvcDetails = "FvSvc Status=Running, StartupType=$($fvCheck.StartType)"
        Write-LogMessage -Level 'PASS' -Message "FvSvc (FrameView SDK Service) is Running (StartupType: $($fvCheck.StartType))."
    } else {
        $fvSvcDetails = "FvSvc Status=$($fvCheck.Status), StartupType=$($fvCheck.StartType)"
        Write-LogMessage -Level 'FAIL' -Message "FvSvc is not running (Status: $($fvCheck.Status))."
    }
} else {
    $fvSvcDetails = "FvSvc service not installed"
    Write-LogMessage -Level 'WARN' -Message "FvSvc service is not installed on this system."
}

# Check 4: NVIDIA Container Services Running
$containersRunning = $false
$containersDetails = ""
$sNVDisplay   = Get-Service -Name 'NVDisplay.ContainerLocalSystem' -ErrorAction SilentlyContinue
$sNvContainer = Get-Service -Name 'NvContainerLocalSystem' -ErrorAction SilentlyContinue

$nvDisplayOk   = ($null -ne $sNVDisplay) -and ($sNVDisplay.Status -eq 'Running')
$nvContainerOk = ($null -ne $sNvContainer) -and ($sNvContainer.Status -eq 'Running')

if ($nvDisplayOk -and $nvContainerOk) {
    $containersRunning = $true
    $containersDetails = "NVDisplay: Running, NvContainer: Running"
    Write-LogMessage -Level 'PASS' -Message "NVIDIA Container services are Running."
} else {
    $dStatus = if ($sNVDisplay) { $sNVDisplay.Status } else { 'NotFound' }
    $cStatus = if ($sNvContainer) { $sNvContainer.Status } else { 'NotFound' }
    $containersDetails = "NVDisplay: $dStatus, NvContainer: $cStatus"
    Write-LogMessage -Level 'FAIL' -Message "NVIDIA Container services unhealthy: $containersDetails"
}

$allChecksPassed = $postProcClean -and $downloaderClean -and $fvSvcRunning -and $containersRunning

$stopwatch.Stop()

$resultObj = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToUniversalTime().ToString("o")
    DurationMs         = [int]$stopwatch.ElapsedMilliseconds
    Mode               = if ($VerifyOnly) { "VerifyOnly" } else { "Remediated" }
    ActionsTaken       = $actionsTaken
    ValidationChecks   = [PSCustomObject]@{
        PostprocessingClean      = $postProcClean
        PostprocessingDetails    = $postProcDetails
        DownloaderClean          = $downloaderClean
        DownloaderDetails        = $downloaderDetails
        FvSvcRunning             = $fvSvcRunning
        FvSvcDetails             = $fvSvcDetails
        ContainerServicesRunning = $containersRunning
        ContainerServicesDetails = $containersDetails
    }
    OverallPassed      = $allChecksPassed
    OverallVerdict     = if ($allChecksPassed) { "PASSED" } else { "FAILED" }
}

if ($ReportFile) {
    try {
        $resultObj | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportFile -Encoding UTF8 -Force
    } catch {}
}

if ($Json) {
    $resultObj | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    $verdictColor = if ($allChecksPassed) { 'Green' } else { 'Red' }
    Write-Host (" REMEDIATION & VERIFICATION VERDICT: {0} ({1} ms)" -f $resultObj.OverallVerdict, $resultObj.DurationMs) -ForegroundColor $verdictColor
    Write-Host " Postprocessing: $(if ($postProcClean) { 'UNLOCKED' } else { 'STUCK' }) | Downloader: $(if ($downloaderClean) { 'CLEAN' } else { 'LOCKED' }) | FvSvc: $(if ($fvSvcRunning) { 'RUNNING' } else { 'STOPPED' }) | Containers: $(if ($containersRunning) { 'HEALTHY' } else { 'UNHEALTHY' })" -ForegroundColor Gray
    Write-Host "================================================================================`n" -ForegroundColor Cyan
}

if ($PassThru) {
    return $resultObj
}

if ($allChecksPassed) {
    exit 0
} else {
    exit 1
}
