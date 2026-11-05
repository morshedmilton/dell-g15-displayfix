# Handoff Report: Challenger M1_2 — Milestone 1 Stress Harness Review

**Agent**: Challenger M1_2  
**Target**: `scripts/diagnostics/stress_test.ps1`  
**Date**: 2026-11-05T11:37:00Z  
**Verdict**: **REJECT**

---

## 1. Observation

Direct empirical observations from executing adversarial tests against `scripts/diagnostics/stress_test.ps1`:

1. **OLS Regression Math Robustness**:
   - `Get-LinearSlope` with empty array `@()` returned `0`.
   - `Get-LinearSlope` with single element `@(120.0)` returned `0`.
   - `Get-LinearSlope` with identical values `@(120.0, 120.0, 120.0, 120.0)` returned `0`.
   - `Get-RSquared` with identical values (where $denY = 0$) returned `0` (protected by line 276: `if ($denX -le 0 -or $denY -le 0) { return 0.0 }`).
   - `Get-LinearSlope` with 1000 identical values returned `0.0`, with `IsNaN = False` and `IsInfinity = False`.

2. **DWM Process Disappearance Unhandled Exception (Critical)**:
   - File path: `scripts/diagnostics/stress_test.ps1`, lines 157-158 and line 360.
   - At line 158:
     ```powershell
     if (-not $proc) { throw "DWM process (dwm.exe) is not running!" }
     ```
   - At line 360:
     ```powershell
     $curDwm = Get-DwmTelemetry -IsElevated $isElevated
     ```
   - When simulated DWM crash/disappearance was introduced at iteration 2:
     Verbatim error output:
     `CAUGHT_TERMINATING_ERROR: DWM process (dwm.exe) is not running!`
     `STATUS: SCRIPT_UNHANDLED_EXCEPTION`
     `JsonReportCount: 0`
     `DidReportGenerate: False`
   - The script terminated immediately. No JSON report or Markdown report was generated.

3. **Low-Iteration Smoke Test False Positives (High)**:
   - File path: `scripts/diagnostics/stress_test.ps1`, line 494:
     ```powershell
     $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
     ```
   - Running `stress_test.ps1 -Iterations 1 -Mode Simulated -Json` produced:
     ```json
     "handles": {
         "initialCount": 1905,
         "finalCount": 1907,
         "actualDelta": 2,
         "maxAllowedDelta": 10,
         "slopePerSwitch": 1,
         "projected100Delta": 100,
         "verdict": "FAIL"
     },
     "overallVerdict": "FAILED"
     ```
   - Exit code was 1. Actual handle delta was 2 (within pro-rated allowance of 10), but projected 100 delta was 100 (exceeding MaxHandleDelta 50).

4. **Silent Report Overwrite under Concurrency (Medium)**:
   - File path: `scripts/diagnostics/stress_test.ps1`, line 504:
     ```powershell
     $timestampStr = $startTimeUtc.ToString("yyyyMMdd_HHmmss")
     $jsonReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.json"
     ```
   - Two concurrent jobs launched in the same second generated only 2 files instead of 4:
     `GeneratedFilesCount: 2`
     `GeneratedFilenames: stress_test_report_20261105_113407.json, stress_test_report_20261105_113407.md`
   - Job 2 silently overwrote Job 1's report without warning or error.

5. **Unhandled DriveNotFoundException on Missing Volume (Medium)**:
   - File path: `scripts/diagnostics/stress_test.ps1`, lines 287-289:
     ```powershell
     if (-not (Test-Path $OutputDir)) {
         New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
     }
     ```
   - Running with `-OutputDir "Z:\NonExistentDrive\logs"` produced:
     `THREW: System.Management.Automation.DriveNotFoundException - Cannot find drive. A drive with the name 'Z' does not exist.`

6. **Parameter Validation Robustness**:
   - Out of 13 boundary/type tests (negative iterations `-5`, zero `0`, excessive `1001`, invalid mode `BogusMode`, SettleDelay `50`/`15000`, Cooldown `50`/`50000`, WorkingSetDelta `0.5`/`600`, HandleDelta `2`/`1500`, type mismatch `abc`), all 13 were rejected with `ParameterBindingValidationException` or `ParameterBindingArgumentTransformationException` prior to script execution.

7. **Circuit Breakers (When Process Running)**:
   - Memory runaway (> 500MB): Aborted at iteration 2, `abortReason = "DWM memory runaway"`.
   - 3 consecutive failures: Aborted at iteration 3, `abortReason = "3 consecutive iteration failures"`.
   - Simulated TDR Event 4101: Aborted at iteration 2, `abortReason = "GPU TDR reset detected"`.
   - Simulated DWM Crash Event 1000: Aborted at iteration 2, `abortReason = "DWM Crash detected"`.
   - DWM PID Change: Aborted at iteration 2, `abortReason = "DWM crashed and restarted"`.

---

## 2. Logic Chain

1. **Step 1 (From Observation 1)**: `Get-LinearSlope` and `Get-RSquared` contain defensive guards (`$count -lt 2` and `$den -eq 0`, `$denX -le 0 -or $denY -le 0`). Empirical tests confirm zero-divide protection works correctly when readings are identical or when count is 0, 1, or large ($N=1000$).
2. **Step 2 (From Observation 2)**: During an actual severe display crash, `dwm.exe` may terminate and not yet be running when the stress harness samples telemetry. Because line 360 invokes `Get-DwmTelemetry` outside any `try/catch` and `$ErrorActionPreference = "Stop"`, the `throw` at line 158 terminates the PowerShell session immediately. This bypasses the circuit breaker at line 382 and the report generation in Section 6. The primary purpose of an automated stress harness—to capture and record crash evidence—is therefore defeated.
3. **Step 3 (From Observation 3)**: In line 494, `projectedHandle100` ($slope \times 100$) is evaluated against `MaxHandleDelta` (50) regardless of the number of iterations. When an operator runs a 1-switch or 2-switch smoke test, normal Windows OS handle fluctuations (+1 or +2 handles) create a slope of $\ge 1.0$, resulting in a projected 100 delta of $\ge 100$. This causes the smoke test to fail with a false positive, even though actual growth (2 handles) was well within the pro-rated threshold (10 handles).
4. **Step 4 (From Observation 4)**: The report filename relies solely on `yyyyMMdd_HHmmss`. Concurrent test runs in CI or automated loops within the same second resolve to identical paths and clobber each other's audit records.
5. **Step 5 (From Observation 5)**: Directory creation at line 288 lacks error handling, causing terminating crashes when an invalid drive letter is passed.
6. **Step 6 (Synthesis)**: While parameter validation and regression math are solid, the harness crashes ungracefully when DWM disappears, produces false-positive failures on smoke tests, and suffers from concurrency file collisions. Therefore, the implementation cannot be approved in its current state.

---

## 3. Caveats

- Tests were executed on the development environment using Windows PowerShell 5.1 / PowerShell 7.
- Actual physical hardware display switching (via Advanced Optimus DDS multiplexer) was not physically triggered during this run because the machine is currently running headlessly via automated agent sessions; testing utilized the `Simulated`, `Passive`, `CcdCycle`, and mocked-telemetry modes provided by the harness.
- No source files in `scripts/diagnostics/stress_test.ps1` were modified, respecting the review-only constraint.

---

## 4. Conclusion

**Verdict: REJECT**

`scripts/diagnostics/stress_test.ps1` requires 4 actionable fixes before Milestone 1 can be considered verified:

1. **Wrap Telemetry Sampling in try/catch**: In `scripts/diagnostics/stress_test.ps1` lines 360-362, catch exceptions from `Get-DwmTelemetry`. If DWM is not running, set `$abortFired = $true`, `$abortReason = "DWM process terminated and not running"`, mark `$iterStatus = "FAIL"`, break out of the loop, and allow Section 6 to write the audit JSON and Markdown reports.
2. **Gate 100-Switch Extrapolation on Sample Size**: In line 493-494, only enforce `($projectedWS100 -le $MaxWorkingSetDeltaMB)` and `($projectedHandle100 -le $MaxHandleDelta)` when `$Iterations -ge 10`. For `$Iterations < 10`, evaluate only actual pro-rated deltas (`$actualWSDelta -le $proRatedMaxWS` and `$actualHandleDelta -le $proRatedMaxHandles`).
3. **Include Process ID in Filename**: Change line 504 to `$timestampStr = "$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"`.
4. **Safeguard OutputDir Creation**: Wrap lines 287-289 in a `try/catch` and fallback to `$env:TEMP\DisplayFix\logs` if directory creation fails.

---

## 5. Verification Method

To independently reproduce the findings:

1. **Verify DWM Termination Crash**:
   Run PowerShell command simulating DWM disappearance on iteration 2:
   ```powershell
   # Reproduce unhandled terminating exception and missing JSON report
   $code = (Get-Content "scripts/diagnostics/stress_test.ps1" -Raw).Replace(
       '$proc = Get-Process -Name dwm -ErrorAction SilentlyContinue',
       'if ($i -eq 2) { $proc = $null } else { $proc = Get-Process -Name dwm -ErrorAction SilentlyContinue }'
   )
   $t = "$env:TEMP\dwm_crash_repro"
   New-Item -Path $t -ItemType Directory -Force | Out-Null
   Set-Content -Path "$t\test.ps1" -Value $code
   & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '$t\test.ps1' -Iterations 5 -OutputDir '$t' }"
   # Invalidation condition: Test fails to generate JSON report in $t.
   ```

2. **Verify Smoke Test False Positive**:
   ```powershell
   & "scripts/diagnostics/stress_test.ps1" -Iterations 1 -Mode Simulated -Json | ConvertFrom-Json
   # Observe: "handles.verdict" is "FAIL" and "overallVerdict" is "FAILED" despite actualDelta <= 10.
   ```

3. **Verify Concurrent Filename Collision**:
   ```powershell
   $s = (Resolve-Path "scripts/diagnostics/stress_test.ps1").Path
   $d = "$env:TEMP\concur_repro"
   New-Item -Path $d -ItemType Directory -Force | Out-Null
   $j1 = Start-Job -ScriptBlock { param($s,$d) & $s -Iterations 2 -OutputDir $d } -ArgumentList $s,$d
   $j2 = Start-Job -ScriptBlock { param($s,$d) & $s -Iterations 2 -OutputDir $d } -ArgumentList $s,$d
   Wait-Job $j1,$j2 | Out-Null
   (Get-ChildItem -Path $d -Filter "*.json").Count
   # Invalidation condition: Count is 1 instead of 2 due to silent overwrite.
   ```
