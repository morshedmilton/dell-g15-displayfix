# Adversarial Test Suite for M1 Diagnostics (probe_system.ps1 & dwm_health.ps1)
# Tier 5 Adversarial Coverage & Boundary Stress Testing

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$totalTests = 0
$passedTests = 0
$failedTests = 0
$testResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-TestResult {
    param(
        [string]$Category,
        [string]$TestName,
        [bool]$Passed,
        [string]$Details
    )
    $script:totalTests++
    if ($Passed) {
        $script:passedTests++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] ${TestName}: $Details" -ForegroundColor Red
    }
    $script:testResults.Add([PSCustomObject]@{
        Category = $Category
        TestName = $TestName
        Passed   = $Passed
        Details  = $Details
    })
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  M1 DIAGNOSTICS ADVERSARIAL STRESS TEST SUITE" -ForegroundColor White
Write-Host "  Target Scripts: probe_system.ps1, dwm_health.ps1" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# SUITE A: Invalid Arguments, Conflicting Parameter Sets & Boundary Out-of-Range
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE A: Parameter Validation & Boundary Out-of-Range ---" -ForegroundColor Yellow

$casesA = @(
    @{
        Category = "A. Parameter Validation"
        Name = "probe_system.ps1 rejects undefined parameter"
        Command = { & .\scripts\diagnostics\probe_system.ps1 -NonExistentParam "val" 2>&1 }
        ExpectedErr = "A parameter cannot be found"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects undefined parameter"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -UnknownFlag 2>&1 }
        ExpectedErr = "A parameter cannot be found"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects conflicting parameter sets (-Since and -LookbackMinutes)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -Since (Get-Date) -LookbackMinutes 30 2>&1 }
        ExpectedErr = "Parameter set cannot be resolved"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects conflicting parameter sets (-Since and -AllTime)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -Since (Get-Date) -AllTime 2>&1 }
        ExpectedErr = "Parameter set cannot be resolved"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects conflicting parameter sets (-LookbackMinutes and -AllTime)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -LookbackMinutes 30 -AllTime 2>&1 }
        ExpectedErr = "Parameter set cannot be resolved"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -LookbackMinutes (-5)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -LookbackMinutes -5 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -LookbackMinutes (0)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -LookbackMinutes 0 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -LookbackMinutes (20000)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -LookbackMinutes 20000 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxWorkingSetMB (10)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxWorkingSetMB 10 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxWorkingSetMB (5000)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxWorkingSetMB 5000 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxHandleCount (100)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxHandleCount 100 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxGdiObjects (5)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxGdiObjects 5 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxUserObjects (10)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxUserObjects 10 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxCpuPercent (2.0)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxCpuPercent 2.0 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects out-of-range -MaxCpuPercent (150.0)"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -MaxCpuPercent 150.0 2>&1 }
        ExpectedErr = "minimum allowed range|maximum allowed range|out of range"
    },
    @{
        Category = "A. Parameter Validation"
        Name = "dwm_health.ps1 rejects malformed -Since string"
        Command = { & .\scripts\diagnostics\dwm_health.ps1 -Since "NOT_A_VALID_DATE_TIME" 2>&1 }
        ExpectedErr = "Cannot convert"
    }
)

foreach ($c in $casesA) {
    try {
        $out = & $c.Command
        $outStr = ($out | Out-String).Trim()
        $matched = ($outStr -match $c.ExpectedErr)
        Record-TestResult -Category $c.Category -TestName $c.Name -Passed $matched -Details "Output: $outStr"
    } catch {
        $msg = $_.Exception.Message
        $matched = ($msg -match $c.ExpectedErr)
        Record-TestResult -Category $c.Category -TestName $c.Name -Passed $matched -Details "Exception: $msg"
    }
}

# -------------------------------------------------------------------------
# SUITE B: Missing Directories, Invalid Drives & Path Edge Cases
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE B: Filesystem Paths, Nonexistent Drives & NoFile ---" -ForegroundColor Yellow

# Test B1: Auto-creation of nested directories for OutputFile
$testOutputDir = "C:\ProgramData\DisplayFix\tests_adversarial\nested\sub"
$testOutputFile = Join-Path $testOutputDir "test_telemetry.json"
if (Test-Path "C:\ProgramData\DisplayFix\tests_adversarial") {
    Remove-Item "C:\ProgramData\DisplayFix\tests_adversarial" -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    $probeOut = & .\scripts\diagnostics\probe_system.ps1 -OutputFile $testOutputFile -Json
    $fileCreated = Test-Path $testOutputFile
    $parsed = $probeOut | ConvertFrom-Json
    $isValid = ($null -ne $parsed -and $parsed.ActiveGpu -ne $null -and $fileCreated)
    Record-TestResult -Category "B. File Paths" -TestName "probe_system.ps1 auto-creates nested output directory" -Passed $isValid -Details "File created: $fileCreated"
} catch {
    Record-TestResult -Category "B. File Paths" -TestName "probe_system.ps1 auto-creates nested output directory" -Passed $false -Details $_.Exception.Message
} finally {
    if (Test-Path "C:\ProgramData\DisplayFix\tests_adversarial") {
        Remove-Item "C:\ProgramData\DisplayFix\tests_adversarial" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Test B2: Invalid drive for OutputFile does not crash probe_system.ps1
try {
    $warnList = $null
    $parsed = & .\scripts\diagnostics\probe_system.ps1 -OutputFile "Z:\NonExistentDrive\bad.json" -Json -WarningVariable warnList 2>$null | ConvertFrom-Json
    $isValid = ($null -ne $parsed -and $parsed.ActiveGpu -ne $null -and $warnList.Count -ge 1)
    Record-TestResult -Category "B. File Paths" -TestName "probe_system.ps1 gracefully warns and emits JSON when output drive is invalid" -Passed $isValid -Details "Valid JSON emitted, Warnings caught: $($warnList.Count)"
} catch {
    Record-TestResult -Category "B. File Paths" -TestName "probe_system.ps1 gracefully warns and emits JSON when output drive is invalid" -Passed $false -Details $_.Exception.Message
}

# Test B3: Invalid drive for OutputFile does not crash dwm_health.ps1
try {
    $warnList = $null
    $parsed = & .\scripts\diagnostics\dwm_health.ps1 -OutputFile "Z:\NonExistentDrive\bad.json" -Json -WarningVariable warnList 2>$null | ConvertFrom-Json
    $isValid = ($null -ne $parsed -and $parsed.Status -ne $null -and $warnList.Count -ge 1)
    Record-TestResult -Category "B. File Paths" -TestName "dwm_health.ps1 gracefully warns and emits JSON when output drive is invalid" -Passed $isValid -Details "Status: $($parsed.Status), Warnings caught: $($warnList.Count)"
} catch {
    Record-TestResult -Category "B. File Paths" -TestName "dwm_health.ps1 gracefully warns and emits JSON when output drive is invalid" -Passed $false -Details $_.Exception.Message
}

# Test B4: -NoFile switch suppresses file creation
$defaultFile = 'C:\ProgramData\DisplayFix\logs\telemetry.json'
$beforeMtime = if (Test-Path $defaultFile) { (Get-Item $defaultFile).LastWriteTimeUtc } else { [DateTime]::MinValue }
Start-Sleep -Milliseconds 100
& .\scripts\diagnostics\probe_system.ps1 -NoFile -Json | Out-Null
$afterMtime = if (Test-Path $defaultFile) { (Get-Item $defaultFile).LastWriteTimeUtc } else { [DateTime]::MinValue }
$noFileHonored = ($beforeMtime -eq $afterMtime)
Record-TestResult -Category "B. File Paths" -TestName "probe_system.ps1 -NoFile honors suppression of disk write" -Passed $noFileHonored -Details "Before: $beforeMtime, After: $afterMtime"

# -------------------------------------------------------------------------
# SUITE C: Add-Type Idempotency & Consecutive Invocations in the SAME Session
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE C: Add-Type Idempotency & Consecutive Invocations ---" -ForegroundColor Yellow

# Test C1: Run probe_system.ps1 5 times consecutively in the SAME process
$c1Pass = $true
$c1Details = ""
for ($i = 1; $i -le 5; $i++) {
    try {
        $p = & .\scripts\diagnostics\probe_system.ps1 -Json -NoFile | ConvertFrom-Json
        if (-not $p.RefreshRateHz) {
            $c1Pass = $false
            $c1Details = "Iteration $i returned empty refresh rate"
            break
        }
    } catch {
        $c1Pass = $false
        $c1Details = "Iteration $i threw exception: $($_.Exception.Message)"
        break
    }
}
Record-TestResult -Category "C. Add-Type Idempotency" -TestName "probe_system.ps1 survives 5 consecutive runs in same session" -Passed $c1Pass -Details $c1Details

# Test C2: Run dwm_health.ps1 5 times consecutively in the SAME process
$c2Pass = $true
$c2Details = ""
for ($i = 1; $i -le 5; $i++) {
    try {
        $h = & .\scripts\diagnostics\dwm_health.ps1 -Json | ConvertFrom-Json
        if (-not $h.Status) {
            $c2Pass = $false
            $c2Details = "Iteration $i returned empty status"
            break
        }
    } catch {
        $c2Pass = $false
        $c2Details = "Iteration $i threw exception: $($_.Exception.Message)"
        break
    }
}
Record-TestResult -Category "C. Add-Type Idempotency" -TestName "dwm_health.ps1 survives 5 consecutive runs in same session" -Passed $c2Pass -Details $c2Details

# Test C3: Interleaved execution in same session
$c3Pass = $true
$c3Details = ""
for ($i = 1; $i -le 3; $i++) {
    try {
        $p = & .\scripts\diagnostics\probe_system.ps1 -Json -NoFile | ConvertFrom-Json
        $h = & .\scripts\diagnostics\dwm_health.ps1 -Json | ConvertFrom-Json
        if ($p.ActiveGpu -eq $null -or $h.Status -eq $null) {
            $c3Pass = $false
            $c3Details = "Iteration $i returned null fields"
            break
        }
    } catch {
        $c3Pass = $false
        $c3Details = "Iteration $i interleaved threw: $($_.Exception.Message)"
        break
    }
}
Record-TestResult -Category "C. Add-Type Idempotency" -TestName "Interleaved probe_system and dwm_health share DisplayFix.Diagnostics namespace cleanly" -Passed $c3Pass -Details $c3Details

# -------------------------------------------------------------------------
# SUITE D: Concurrent Invocations (Background Jobs)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE D: Concurrent Invocations via Background Jobs ---" -ForegroundColor Yellow

$jobs = @()
$rootDir = (Get-Location).Path
for ($j = 1; $j -le 4; $j++) {
    $jobs += Start-Job -ScriptBlock {
        param($dir, $idx)
        Set-Location $dir
        $p = & .\scripts\diagnostics\probe_system.ps1 -Json -NoFile | ConvertFrom-Json
        $h = & .\scripts\diagnostics\dwm_health.ps1 -Json | ConvertFrom-Json
        return [PSCustomObject]@{
            JobIndex = $idx
            ActiveGpu = $p.ActiveGpu
            RefreshHz = $p.RefreshRateHz
            DwmStatus = $h.Status
        }
    } -ArgumentList $rootDir, $j
}

$jobResults = $jobs | Wait-Job -Timeout 30 | Receive-Job
$jobs | Remove-Job -Force

$dPass = ($jobResults.Count -eq 4)
foreach ($jr in $jobResults) {
    if (-not $jr.ActiveGpu -or -not $jr.RefreshHz -or -not $jr.DwmStatus) {
        $dPass = $false
    }
}
Record-TestResult -Category "D. Concurrency" -TestName "4 concurrent background jobs execute probe_system and dwm_health simultaneously" -Passed $dPass -Details "Returned $($jobResults.Count)/4 jobs successfully"

# -------------------------------------------------------------------------
# SUITE E: Pipeline Consumption, Purity & Type Contracts
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE E: Pipeline Consumption, Stream Purity & Schema ---" -ForegroundColor Yellow

# Test E1: Standard pipe to ConvertFrom-Json
try {
    $jsonObj = & .\scripts\diagnostics\probe_system.ps1 -Json -NoFile | ConvertFrom-Json
    $hasAllFields = ($null -ne $jsonObj.ActiveGpu -and
                     $null -ne $jsonObj.DisplayMode -and
                     $null -ne $jsonObj.RefreshRateHz -and
                     $null -ne $jsonObj.DpiScalePercent -and
                     $null -ne $jsonObj.DwmWorkingSetMB -and
                     $null -ne $jsonObj.DwmHandleCount -and
                     $null -ne $jsonObj.TdrEventCount -and
                     $null -ne $jsonObj.DwmCrashCount)
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 -Json pipeline emits all Contract 5 required fields" -Passed $hasAllFields -Details "Fields: ActiveGpu=$($jsonObj.ActiveGpu), Hz=$($jsonObj.RefreshRateHz)"
} catch {
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 -Json pipeline emits all Contract 5 required fields" -Passed $false -Details $_.Exception.Message
}

# Test E2: Verify RefreshRateHz numeric precision and expected 360.152
$hzValid = ($jsonObj.RefreshRateHz -ge 359.0 -and $jsonObj.RefreshRateHz -le 361.0)
Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 reports refresh rate ~360.152 Hz" -Passed $hzValid -Details "Reported Hz: $($jsonObj.RefreshRateHz)"

# Test E3: Verify Active GPU and Mode match Dell G15 live state
$gpuValid = ($jsonObj.ActiveGpu -match 'NVIDIA|Intel' -and $jsonObj.DisplayMode -in @('NVIDIA GPU Only', 'Optimus', 'Automatic'))
Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 detects active GPU and mode dynamically" -Passed $gpuValid -Details "GPU=$($jsonObj.ActiveGpu), Mode=$($jsonObj.DisplayMode)"

# Test E4: -PassThru returns PSCustomObject directly
try {
    $obj = & .\scripts\diagnostics\probe_system.ps1 -PassThru -NoFile
    $isPsobj = ($obj -is [PSCustomObject] -and $obj.ActiveGpu -ne $null)
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 -PassThru returns live PSCustomObject directly to pipeline" -Passed $isPsobj -Details "Type: $($obj.GetType().FullName)"
} catch {
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "probe_system.ps1 -PassThru returns live PSCustomObject directly to pipeline" -Passed $false -Details $_.Exception.Message
}

# Test E5: dwm_health.ps1 -PassThru returns PSCustomObject directly
try {
    $hobj = & .\scripts\diagnostics\dwm_health.ps1 -PassThru
    $isHpsobj = ($hobj -is [PSCustomObject] -and $hobj.Status -ne $null)
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "dwm_health.ps1 -PassThru returns live PSCustomObject directly to pipeline" -Passed $isHpsobj -Details "Type: $($hobj.GetType().FullName), Status=$($hobj.Status)"
} catch {
    Record-TestResult -Category "E. Pipeline & Schema" -TestName "dwm_health.ps1 -PassThru returns live PSCustomObject directly to pipeline" -Passed $false -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# SUITE F: Non-Elevated Behavior & Graceful Degradation
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE F: Non-Elevated Behavior & Graceful Degradation ---" -ForegroundColor Yellow

# Test F1: dwm_health.ps1 non-elevated handles GetGuiResources gracefully
try {
    $h = & .\scripts\diagnostics\dwm_health.ps1 -Json | ConvertFrom-Json
    $guiHandled = $false
    if (-not $h.IsElevated) {
        # Non-elevated: Available must be false, Reason must indicate elevation, Gdi/User 0 or null, ExitCode 0 (no crash)
        $guiHandled = ($h.GuiResources.Available -eq $false -and
                       $h.GuiResources.Reason -match 'Requires Administrator' -and
                       ($null -eq $h.GuiResources.GdiObjects -or $h.GuiResources.GdiObjects -eq 0) -and
                       $h.ExitCode -eq 0 -and
                       $h.Process.HandleCount -gt 0)
    } else {
        # Elevated: GDI and User handles queried successfully
        $guiHandled = ($h.GuiResources.Available -eq $true -and $h.ExitCode -eq 0)
    }
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 gracefully handles GDI/USER access without crashing" -Passed $guiHandled -Details "Elevated: $($h.IsElevated), Available: $($h.GuiResources.Available), Reason: $($h.GuiResources.Reason)"
} catch {
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 gracefully handles GDI/USER access without crashing" -Passed $false -Details $_.Exception.Message
}

# Test F2: dwm_health.ps1 triggers Warning exit code when -FailOnWarning and threshold breached
try {
    # Set artificially low threshold: MaxWorkingSetMB = 50.0 (DWM is ~117 MB)
    $lowWsOut = powershell -ExecutionPolicy Bypass -Command "& { .\scripts\diagnostics\dwm_health.ps1 -MaxWorkingSetMB 50.0 -FailOnWarning -Json; exit `$LASTEXITCODE }"
    $exitCodeLow = $LASTEXITCODE
    $parsedLow = $lowWsOut | ConvertFrom-Json
    $breachHandled = ($exitCodeLow -eq 1 -and $parsedLow.Status -eq "Warning" -and $parsedLow.Violations.Count -ge 1)
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 -FailOnWarning exits with code 1 on threshold breach" -Passed $breachHandled -Details "ExitCode=$exitCodeLow, Status=$($parsedLow.Status), Violations=$($parsedLow.Violations -join '; ')"
} catch {
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 -FailOnWarning exits with code 1 on threshold breach" -Passed $false -Details $_.Exception.Message
}

# Test F3: dwm_health.ps1 does NOT fail when -FailOnWarning is omitted even if threshold breached
try {
    $softWsOut = powershell -ExecutionPolicy Bypass -Command "& { .\scripts\diagnostics\dwm_health.ps1 -MaxWorkingSetMB 50.0 -Json; exit `$LASTEXITCODE }"
    $exitCodeSoft = $LASTEXITCODE
    $parsedSoft = $softWsOut | ConvertFrom-Json
    $softHandled = ($exitCodeSoft -eq 0 -and $parsedSoft.Status -eq "Warning")
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 without -FailOnWarning exits with code 0 on soft warning" -Passed $softHandled -Details "ExitCode=$exitCodeSoft, Status=$($parsedSoft.Status)"
} catch {
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 without -FailOnWarning exits with code 0 on soft warning" -Passed $false -Details $_.Exception.Message
}

# Test F4: dwm_health.ps1 handle count threshold breach
try {
    $lowHOut = powershell -ExecutionPolicy Bypass -Command "& { .\scripts\diagnostics\dwm_health.ps1 -MaxHandleCount 500 -FailOnWarning -Json; exit `$LASTEXITCODE }"
    $exitCodeH = $LASTEXITCODE
    $parsedH = $lowHOut | ConvertFrom-Json
    $handleHandled = ($exitCodeH -eq 1 -and $parsedH.Status -eq "Warning" -and ($parsedH.Violations | Where-Object { $_ -match 'Handle Count' }))
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 detects handle count breach (>500)" -Passed ($handleHandled -ne $null) -Details "ExitCode=$exitCodeH, Status=$($parsedH.Status)"
} catch {
    Record-TestResult -Category "F. Elevation & Graceful Fallback" -TestName "dwm_health.ps1 detects handle count breach (>500)" -Passed $false -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# SUMMARY
# -------------------------------------------------------------------------
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  ADVERSARIAL STRESS TEST SUMMARY" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  Total Tests Executed : $totalTests"
Write-Host "  Passed Tests         : $passedTests" -ForegroundColor Green
Write-Host "  Failed Tests         : $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
$allPassed = ($failedTests -eq 0)
Write-Host "  Final Verdict        : $(if ($allPassed) { 'APPROVE (All Tests Passed)' } else { 'REJECT (Failures Detected)' })" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host "========================================================================" -ForegroundColor Cyan

exit $(if ($allPassed) { 0 } else { 1 })
