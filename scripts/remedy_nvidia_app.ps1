# scripts/remedy_nvidia_app.ps1
# Fixes NVIDIA App Game Ready Driver infinite download loop and Automatic Tuning lockup
# MR3 - Full remediation of UpdateFramework stale state

[CmdletBinding()]
param(
    [switch]$Verify  # Run in verify-only mode (no changes)
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " FIXING NVIDIA APP DRIVER DOWNLOAD LOOP AND AUTOMATIC TUNING LOCKUP" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$ErrorCount  = 0
$StatusPath  = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status'
$OtaPath     = 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts'
$grdStatusDir = Join-Path $StatusPath 'grd'

# ---------------------------------------------------------------------------
# Step 1 - Stop NVIDIA App UI processes
# ---------------------------------------------------------------------------
Write-Host "`n[Step 1] Stopping NVIDIA App UI processes..." -ForegroundColor Yellow
$nvUIProcs = Get-Process | Where-Object { $_.ProcessName -match 'NVIDIA App|nvsphelper|NVIDIA Overlay' }
foreach ($p in $nvUIProcs) {
    try {
        Write-Host "  Stopping $($p.ProcessName) (PID: $($p.Id))..."
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    } catch {}
}
Start-Sleep -Seconds 2
Write-Host "  Done" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2 - Clear stuck ota-artifacts
# ---------------------------------------------------------------------------
Write-Host "`n[Step 2] Clearing stuck UpdateFramework ota-artifacts cache..." -ForegroundColor Yellow
if (Test-Path $OtaPath) {
    $before = (Get-ChildItem $OtaPath -Recurse -ErrorAction SilentlyContinue).Count
    Write-Host "  Items before clear: $before"
    if (-not $Verify) {
        Get-ChildItem -Path $OtaPath -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    $after = (Get-ChildItem $OtaPath -Recurse -ErrorAction SilentlyContinue).Count
    Write-Host "  Items after clear: $after" -ForegroundColor Green
} else {
    Write-Host "  ota-artifacts path not found (already clean)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 3 - Reset GRD status files
# ---------------------------------------------------------------------------
Write-Host "`n[Step 3] Resetting stuck GRD status files to idle state..." -ForegroundColor Yellow
if (Test-Path $grdStatusDir) {
    $dlFile = Join-Path $grdStatusDir 'download.json'
    $ppFile = Join-Path $grdStatusDir 'postprocessing.json'
    if (-not $Verify) {
        '[]' | Set-Content -Path $dlFile -Encoding UTF8 -Force -ErrorAction SilentlyContinue
        '[]' | Set-Content -Path $ppFile -Encoding UTF8 -Force -ErrorAction SilentlyContinue
        Write-Host "  download.json -> []" -ForegroundColor Green
        Write-Host "  postprocessing.json -> []" -ForegroundColor Green
    } else {
        $dlContent = Get-Content $dlFile -Raw -ErrorAction SilentlyContinue
        $ppContent = Get-Content $ppFile -Raw -ErrorAction SilentlyContinue
        Write-Host "  [VERIFY] download.json = $dlContent"
        Write-Host "  [VERIFY] postprocessing.json = $ppContent"
    }
} else {
    Write-Host "  GRD status dir not found, creating empty structure..." -ForegroundColor Yellow
    if (-not $Verify) {
        New-Item -Path $grdStatusDir -ItemType Directory -Force | Out-Null
        '[]' | Set-Content -Path (Join-Path $grdStatusDir 'download.json') -Encoding UTF8 -Force
        '[]' | Set-Content -Path (Join-Path $grdStatusDir 'postprocessing.json') -Encoding UTF8 -Force
    }
    Write-Host "  Created clean GRD status dir" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 4 - Reset nvapp autoupdate.json to idle
# ---------------------------------------------------------------------------
Write-Host "`n[Step 4] Resetting nvapp autoupdate.json to idle state..." -ForegroundColor Yellow
$nvAppStatusDir = Join-Path $StatusPath 'nvapp'
$autoUpdateFile = Join-Path $nvAppStatusDir 'autoupdate.json'
$idleJson = '[{"componentName":"nvapp","installedVersion":"","backupPath":"","updateVersion":"","taskId":"","ufApiCallSessionId":"","updateState":0,"currentPhase":0}]'
if (Test-Path $autoUpdateFile) {
    $raw = Get-Content $autoUpdateFile -Raw -ErrorAction SilentlyContinue
    $needsReset = $false
    if ($raw) {
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch {}
        if ($obj -ne $null) {
            $us = if ($obj -is [array]) { $obj[0].updateState } else { $obj.updateState }
            $cp = if ($obj -is [array]) { $obj[0].currentPhase } else { $obj.currentPhase }
            Write-Host "  Current updateState: $us  currentPhase: $cp"
            if ($us -ne 0 -or $cp -ne 0) { $needsReset = $true }
        } else {
            Write-Host "  Could not parse autoupdate.json - will reset" -ForegroundColor DarkYellow
            $needsReset = $true
        }
    } else {
        $needsReset = $true
    }
    if ($needsReset) {
        if (-not $Verify) {
            $idleJson | Set-Content -Path $autoUpdateFile -Encoding UTF8 -Force
            Write-Host "  Reset to idle (updateState:0, currentPhase:0)" -ForegroundColor Green
        }
    } else {
        Write-Host "  Already idle - no change needed" -ForegroundColor Green
    }
} else {
    Write-Host "  autoupdate.json not found - no action needed" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 5 - Clear CEF/webview cache
# ---------------------------------------------------------------------------
Write-Host "`n[Step 5] Clearing NVIDIA App CEF cache..." -ForegroundColor Yellow
$cefPaths = @(
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA app\CEF",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NvNode\cache"
)
foreach ($cefPath in $cefPaths) {
    if (Test-Path $cefPath) {
        $sizeMB = [math]::Round((Get-ChildItem $cefPath -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)
        Write-Host "  Found: $cefPath ($sizeMB MB)"
        if (-not $Verify) {
            Get-ChildItem $cefPath -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    Cleared." -ForegroundColor Green
        }
    } else {
        Write-Host "  Not found (already clean): $cefPath" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Step 6 - Ensure NVIDIA Container services are Running
# ---------------------------------------------------------------------------
Write-Host "`n[Step 6] Verifying NVIDIA Container services..." -ForegroundColor Yellow
$requiredServices = @('NVDisplay.ContainerLocalSystem', 'NvContainerLocalSystem')
foreach ($svc in $requiredServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.Status -ne 'Running' -and -not $Verify) {
            Write-Host "  Starting $svc..." -ForegroundColor Yellow
            Start-Service $svc -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        }
        $st = if ($s) { $s.Status } else { 'Unknown' }
        $col = if ($st -eq 'Running') { 'Green' } else { 'Red' }
        if ($st -ne 'Running') { $ErrorCount++ }
        Write-Host "  $svc : $st" -ForegroundColor $col
    } else {
        Write-Host "  $svc : NOT FOUND (may be named differently)" -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# Step 7 - Start FrameView SDK service if stopped
# ---------------------------------------------------------------------------
Write-Host "`n[Step 7] FrameView SDK service state..." -ForegroundColor Yellow
$fv = Get-Service -DisplayName 'NVIDIA FrameView SDK service' -ErrorAction SilentlyContinue
if ($fv) {
    Write-Host "  NVFrameViewSDK Status: $($fv.Status)"
    if ($fv.Status -ne 'Running' -and -not $Verify) {
        try {
            Start-Service $fv.Name -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $fv = Get-Service -Name $fv.Name -ErrorAction SilentlyContinue
            Write-Host "  After start: $($fv.Status)" -ForegroundColor Green
        } catch {
            Write-Host "  Could not start FrameView SDK (non-critical): $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
} else {
    Write-Host "  FrameView SDK service not found (non-critical)" -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# Verification Summary
# ---------------------------------------------------------------------------
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host " POST-REMEDIATION VERIFICATION" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ota-artifacts
$otaCount = (Get-ChildItem $OtaPath -Recurse -ErrorAction SilentlyContinue).Count
$otaOk    = ($otaCount -eq 0)
$otaLabel = if ($otaOk) { '[PASS]' } else { '[FAIL]' }
$otaColor = if ($otaOk) { 'Green' } else { 'Red' }
Write-Host "ota-artifacts count : $otaCount $otaLabel" -ForegroundColor $otaColor
if (-not $otaOk) { $ErrorCount++ }

# GRD download.json
$dlContent = (Get-Content (Join-Path $grdStatusDir 'download.json') -Raw -ErrorAction SilentlyContinue).Trim()
$dlOk      = ($dlContent -eq '[]')
$dlLabel   = if ($dlOk) { '[PASS]' } else { '[FAIL]' }
$dlColor   = if ($dlOk) { 'Green' } else { 'Red' }
Write-Host "grd/download.json   : $dlContent $dlLabel" -ForegroundColor $dlColor
if (-not $dlOk) { $ErrorCount++ }

# GRD postprocessing.json
$ppContent = (Get-Content (Join-Path $grdStatusDir 'postprocessing.json') -Raw -ErrorAction SilentlyContinue).Trim()
$ppOk      = ($ppContent -eq '[]')
$ppLabel   = if ($ppOk) { '[PASS]' } else { '[FAIL]' }
$ppColor   = if ($ppOk) { 'Green' } else { 'Red' }
Write-Host "grd/postproc.json   : $ppContent $ppLabel" -ForegroundColor $ppColor
if (-not $ppOk) { $ErrorCount++ }

# Container services
$svc1   = Get-Service 'NVDisplay.ContainerLocalSystem' -ErrorAction SilentlyContinue
$svc2   = Get-Service 'NvContainerLocalSystem' -ErrorAction SilentlyContinue
$c1     = if ($svc1) { $svc1.Status.ToString() } else { 'NotFound' }
$c2     = if ($svc2) { $svc2.Status.ToString() } else { 'NotFound' }
$svcOk  = ($c1 -eq 'Running') -and ($c2 -eq 'Running')
$svcLabel = if ($svcOk) { '[PASS]' } else { '[FAIL]' }
$svcColor = if ($svcOk) { 'Green' } else { 'Red' }
Write-Host "Container services  : NVDisplay=$c1 NvContainer=$c2 $svcLabel" -ForegroundColor $svcColor
if (-not $svcOk) { $ErrorCount++ }

Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
if ($ErrorCount -eq 0) {
    Write-Host " ALL CHECKS PASSED - NVIDIA App should now download drivers without looping." -ForegroundColor Green
    Write-Host " Restart NVIDIA App and attempt a fresh driver download." -ForegroundColor Green
} else {
    Write-Host " $ErrorCount CHECK(S) FAILED - see above for details." -ForegroundColor Red
}
Write-Host "================================================================================" -ForegroundColor Cyan
exit $ErrorCount
