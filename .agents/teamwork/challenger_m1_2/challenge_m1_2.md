# Adversarial Challenge Report: Display Switching Stress Test Harness (`stress_test.ps1`)

**Agent**: Challenger M1_2  
**Target Component**: `scripts/diagnostics/stress_test.ps1` (Milestone 1, Feature F03)  
**Date**: 2026-11-05T11:36:00Z  
**Verdict**: **REJECT** (Critical and High-severity defects empirically reproduced)

---

## Challenge Summary

**Overall Risk Assessment**: **CRITICAL**

While `scripts/diagnostics/stress_test.ps1` demonstrates strong mathematical divide-by-zero protection in its OLS regression functions and comprehensive PowerShell parameter binding constraints, adversarial stress-testing identified two breaking defects and two edge-case vulnerabilities:

1. **[CRITICAL] Unhandled Terminating Exception on DWM Process Crash**: If DWM terminates/crashes during display switching and is not actively running at the moment of telemetry polling (line 360), `Get-DwmTelemetry` throws an uncaught exception (`throw "DWM process (dwm.exe) is not running!"`) under `$ErrorActionPreference = "Stop"`. This crashes PowerShell immediately, bypassing the circuit breaker logic and post-run analysis. **Zero JSON and Markdown audit reports are generated**, leaving zero telemetry records of the crash.
2. **[HIGH] False-Positive Leak Slope Failures on Short Smoke Tests**: For small iteration counts (e.g., `-Iterations 1` or `2`), line 494 evaluates `($projectedHandle100 -le $MaxHandleDelta)`. A normal background Windows OS allocation of even 1 handle yields a linear slope of 1.0 handle/switch, which extrapolates to 100 handles across 100 switches. Because $100 > 50$, **the 1-iteration smoke test consistently fails with `verdict = FAIL`**, even when actual handle growth is well within the pro-rated allowance (2 handles vs 10 allowed).
3. **[MEDIUM] Silent Audit Report Overwrite under Concurrent Execution**: Report filenames are generated with 1-second timestamp resolution (`stress_test_report_yyyyMMdd_HHmmss.json`) without PID or UUID. Concurrent or rapid invocations in the same second silently overwrite the audit report on disk with no warning.
4. **[MEDIUM] Unhandled DriveNotFoundException on Invalid Output Directory**: If `$OutputDir` specifies a non-existent drive letter, `New-Item` (line 288) throws an uncaught terminating exception under `$ErrorActionPreference = "Stop"`.

---

## Challenges & Empirical Reproductions

### [Critical] Challenge 1: Unhandled Exception and Audit Loss on DWM Process Disappearance

- **Assumption Challenged**: The test harness assumes that when DWM crashes during display switching, it will either already have restarted with a new PID, or that the process object will remain accessible to detect the crash.
- **Attack Scenario**: Severe display adapter reset or crash where `dwm.exe` terminates and has not yet completed restarting when line 360 executes:
  ```powershell
  # Line 360 of scripts/diagnostics/stress_test.ps1
  $curDwm = Get-DwmTelemetry -IsElevated $isElevated
  ```
  Inside `Get-DwmTelemetry` (lines 157-158):
  ```powershell
  $proc = Get-Process -Name dwm -ErrorAction SilentlyContinue
  if (-not $proc) { throw "DWM process (dwm.exe) is not running!" }
  ```
  Because `$ErrorActionPreference = "Stop"` is configured at line 84, this `throw` is an uncaught terminating error.
- **Empirical Reproduction**:
  Simulated DWM process absence on iteration 2:
  ```
  [Iteration 1/5] Executing switch (Simulated)... OK (WS: 119.95MB, Handles: 1907, Freq: 360Hz)
  [Iteration 2/5] Executing switch (Simulated)... CAUGHT_TERMINATING_ERROR: DWM process (dwm.exe) is not running!
  STATUS: SCRIPT_UNHANDLED_EXCEPTION
  JsonReportCount: 0
  DidReportGenerate: False
  ```
- **Blast Radius**: Script crashes immediately. Circuit breaker at line 382 (`if ($curDwm.ProcessId -ne $initialDwm.ProcessId)`) never executes. Post-run regression analysis and report generation (lines 503-600) never run. Zero audit artifacts are saved to disk, masking the exact crash event from the CI/CD pipeline.
- **Mitigation**:
  Wrap the telemetry polling in a `try/catch` block. If `dwm.exe` is absent, catch the exception, set `$curDwm = $null`, trip the circuit breaker (`$abortFired = $true`, `$abortReason = "DWM process terminated and not running"`), mark iteration status as `FAIL`, break the loop cleanly, and proceed to generate the JSON/Markdown audit report.

---

### [High] Challenge 2: Statistical Extrapolation Defect on Low-Iteration Smoke Tests (False Positive Failure)

- **Assumption Challenged**: The harness assumes that multiplying the linear slope by 100 (`$projectedWS100 = $wsSlope * 100`, `$projectedHandle100 = $handleSlope * 100`) is a valid compliance gate regardless of iteration count.
- **Attack Scenario**: An operator runs a standard 1-iteration smoke test:
  ```powershell
  .\stress_test.ps1 -Iterations 1 -Mode Simulated -Json
  ```
  At iteration 1, baseline handle count is 1905; 100ms later, handle count is 1907 (a 2-handle delta from normal OS background activity).
  - Pro-rated actual handle allowance: `[math]::Max(10, [math]::Ceiling(50 * (1 / 100.0))) = 10 handles`.
  - Actual handle delta: 2 handles (Well within 10-handle allowance).
  - Slope calculation: $(1907 - 1905) / 1 = 1.0$ handle/switch.
  - Projected 100 switches: $1.0 \times 100 = 100$ handles.
  - Compliance check (line 494): `($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)`
  - $2 \le 10$ is TRUE, but $100 \le 50$ is FALSE!
- **Empirical Reproduction**:
  Executed `stress_test.ps1 -Iterations 1 -Mode Simulated -Json`:
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
  Exit code: `1`.
- **Blast Radius**: Every short smoke test (`Iterations < 5`) is practically guaranteed to report false positive failures whenever normal Windows background noise shifts handle or memory counts slightly.
- **Mitigation**:
  Only evaluate the 100-switch extrapolation check (`projected100Delta`) when `$Iterations -ge 10` (or require minimum statistical confidence $R^2 \ge 0.70$ and sample size $N \ge 10$). For small iterations ($N < 10$), gate solely on the pro-rated actual delta thresholds.

---

### [Medium] Challenge 3: Silent Audit Report Clobbering under Concurrency

- **Assumption Challenged**: The harness assumes test executions will never occur concurrently within the same second.
- **Attack Scenario**: Two automated test runners or background validation jobs execute `stress_test.ps1` concurrently or within the same clock second to `$OutputDir`:
  ```powershell
  # Lines 504-506 of scripts/diagnostics/stress_test.ps1
  $timestampStr = $startTimeUtc.ToString("yyyyMMdd_HHmmss")
  $jsonReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.json"
  $mdReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.md"
  ```
  Both processes resolve the identical filename.
- **Empirical Reproduction**:
  Two concurrent jobs launched simultaneously to `$env:TEMP\displayfix_test_concurrent`:
  - Generated files: `stress_test_report_20261105_113407.json`, `stress_test_report_20261105_113407.md` (Total 2 files instead of 4).
  - Inspection of JSON showed Job 2 completely overwrote Job 1's audit data silently.
- **Blast Radius**: Loss of compliance and test audit trail in multi-agent or concurrent CI environments.
- **Mitigation**:
  Include process ID or GUID in filename: `"stress_test_report_${timestampStr}_$($PID).json"`.

---

### [Medium] Challenge 4: Unhandled DriveNotFoundException on Missing Volume

- **Assumption Challenged**: The harness assumes `$OutputDir` will always reside on a valid filesystem drive.
- **Attack Scenario**: Invocation with an invalid drive path:
  ```powershell
  .\stress_test.ps1 -OutputDir 'Z:\NonExistentDrive\logs'
  ```
  Lines 287-289:
  ```powershell
  if (-not (Test-Path $OutputDir)) {
      New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
  }
  ```
- **Empirical Reproduction**:
  `THREW: System.Management.Automation.DriveNotFoundException - Cannot find drive. A drive with the name 'Z' does not exist.`
- **Blast Radius**: Immediate crash before running baseline or tests.
- **Mitigation**:
  Wrap directory initialization in a `try/catch` with fallback to `$env:TEMP\DisplayFix\logs`.

---

## Stress Test Results Matrix

| # | Empirical Scenario | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|
| **M01** | `Get-LinearSlope` with empty array `@()` | Return `0.0`, no divide-by-zero | Returned `0.0` | **PASS** |
| **M02** | `Get-LinearSlope` with single element `@(120.0)` | Return `0.0`, no divide-by-zero | Returned `0.0` | **PASS** |
| **M03** | `Get-LinearSlope` with 4 identical values `@(120, 120, 120, 120)` | Return `0.0`, no divide-by-zero | Returned `0.0` | **PASS** |
| **M04** | `Get-RSquared` with 4 identical values ($denY = 0$) | Return `0.0`, no divide-by-zero | Returned `0.0` | **PASS** |
| **M05** | `Get-LinearSlope` with known positive slope ($y=2x+10$) | Return `2.0`, $R^2 = 1.0$ | Returned `2.0`, $R^2 = 1.0$ | **PASS** |
| **M06** | `Get-LinearSlope` with known negative slope ($y=-0.5x+100$) | Return `-0.5`, $R^2 = 1.0$ | Returned `-0.5`, $R^2 = 1.0$ | **PASS** |
| **M07** | `Get-LinearSlope` with 1000 identical readings | Return `0.0`, no NaN/Infinity | Returned `0.0`, IsNaN=False | **PASS** |
| **C01** | WorkingSet Memory Runaway (> 500MB) | Abort immediately, status FAIL, report written | Aborted at iteration 2, `abortReason = "DWM memory runaway"`, reports written | **PASS** |
| **C02** | 3 Consecutive Iteration Failures (e.g. Refresh 144Hz) | Abort at 3rd failure, status FAIL, report written | Aborted at iteration 3, `abortReason = "3 consecutive iteration failures"`, reports written | **PASS** |
| **C03** | Simulated TDR Event (Event ID 4101) | Abort immediately, status FAIL, report written | Aborted at iteration 2, `abortReason = "GPU TDR reset detected"`, reports written | **PASS** |
| **C04** | Simulated DWM Crash Event (Event ID 1000) | Abort immediately, status FAIL, report written | Aborted at iteration 2, `abortReason = "DWM Crash detected"`, reports written | **PASS** |
| **C05** | DWM PID Change (DWM restarted) | Abort immediately, status FAIL, report written | Aborted at iteration 2, `abortReason = "DWM crashed and restarted"`, reports written | **PASS** |
| **C06** | DWM Process Terminates During Telemetry Polling | Catch crash, abort with FAIL, write audit report | **Unhandled terminating exception thrown; script crashed; 0 reports generated** | **FAIL (CRITICAL)** |
| **P01** | Negative Iterations (`-Iterations -5`) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P02** | Zero Iterations (`-Iterations 0`) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P03** | Excessive Iterations (`-Iterations 1001`) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P04** | Invalid Mode (`-Mode BogusMode`) | Reject at parameter binding | Threw `ParameterBindingValidationException` (ValidateSet) | **PASS** |
| **P05** | Out-of-bounds `SettleDelayMs` (50ms, 15000ms) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P06** | Out-of-bounds `CooldownMs` (50ms, 50000ms) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P07** | Out-of-bounds `MaxWorkingSetDeltaMB` (0.5MB, 600MB) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P08** | Out-of-bounds `MaxHandleDelta` (2, 1500) | Reject at parameter binding | Threw `ParameterBindingValidationException` | **PASS** |
| **P09** | Type mismatch (`-Iterations abc`) | Reject at parameter binding | Threw `ParameterBindingArgumentTransformationException` | **PASS** |
| **D01** | Smoke Test (-Iterations 1) under normal 2-handle jitter | Pass if within pro-rated delta (2 <= 10) | **Failed: Extrapolated slope (100 > 50) failed the test** | **FAIL (HIGH)** |
| **D02** | Concurrent executions in same second | Separate reports per execution | **Silent collision: Report overwritten without warning** | **FAIL (MEDIUM)** |
| **D03** | Invalid drive in OutputDir (`Z:\...`) | Graceful fallback or handled error | **Unhandled DriveNotFoundException terminating script** | **FAIL (MEDIUM)** |
| **D04** | Read-Only target file collision | Catch exception, warn operator | Caught in try/catch, printed Warning | **PASS** |

---

## Final Recommendation & Verdict

**Verdict**: **REJECT**

`scripts/diagnostics/stress_test.ps1` must be remediated by the implementer before deployment into automated soak validation:

1. **Fix DWM Polling Exception Handling**: Wrap lines 360-361 in a `try/catch`. When `dwm.exe` is absent, do not terminate; trip the circuit breaker, mark iteration status as `FAIL`, and let Section 6 write the failure audit JSON/Markdown.
2. **Fix Low-Iteration False Positives**: Condition the 100-switch extrapolation check (`projectedWS100` and `projectedHandle100`) on `$Iterations -ge 10`. For `$Iterations < 10`, evaluate only `$actualWSDelta -le $proRatedMaxWS` and `$actualHandleDelta -le $proRatedMaxHandles`.
3. **Include Process ID in Report Filenames**: Update line 504 to `$timestampStr = "$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"` to prevent silent report overwrites under concurrent runs.
4. **Wrap OutputDir Creation**: Add error handling around `New-Item -Path $OutputDir` to fall back to `$env:TEMP\DisplayFix\logs` if the target drive is inaccessible.
