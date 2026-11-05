# Handoff Report: Explorer M1_IT2_2 — Defect 2 Slope Gating Fix Formulation

**Agent**: Explorer M1_IT2_2  
**Target File**: `scripts/diagnostics/stress_test.ps1`  
**Milestone**: Milestone 1 (Diagnostics, Telemetry & Stress Harness) - Iteration 2  
**Date**: 2026-11-05T11:45:00Z  
**Status**: Ready for Implementation  

---

## 1. Observation

1. **Direct Empirical Reproduction of 1-Iteration Smoke Test Failure**:
   Command executed:
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\diagnostics\stress_test.ps1' -Iterations 1 -Mode Simulated -Json"
   ```
   Verbatim output received:
   ```json
   "leakAnalysis":  {
       "workingSet":  {
           "initialMB":  120.16,
           "finalMB":  120.26,
           "actualDeltaMB":  0.1,
           "maxAllowedDeltaMB":  5,
           "slopeMBPerSwitch":  0.07,
           "projected100DeltaMB":  7,
           "rSquared":  1,
           "verdict":  "PASS"
       },
       "handles":  {
           "initialCount":  1906,
           "finalCount":  1907,
           "actualDelta":  1,
           "maxAllowedDelta":  10,
           "slopePerSwitch":  1,
           "projected100Delta":  100,
           "rSquared":  1,
           "verdict":  "FAIL"
       }
   },
   "overallVerdict":  "FAILED"
   ```
   Exit code: `1`.

2. **Source Code Inspection at Exact Lines**:
   In `scripts/diagnostics/stress_test.ps1`, lines 493–494:
   ```powershell
   493: $wsPassed = ($actualWSDelta -le $proRatedMaxWS) -and ($projectedWS100 -le $MaxWorkingSetDeltaMB)
   494: $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
   ```
   In lines 295–296:
   ```powershell
   295: $proRatedMaxWS = [math]::Max(5.0, [math]::Round($MaxWorkingSetDeltaMB * ($Iterations / 100.0), 2))
   296: $proRatedMaxHandles = [math]::Max(10, [int][math]::Ceiling($MaxHandleDelta * ($Iterations / 100.0)))
   ```
   In lines 476–479:
   ```powershell
   476: $handleSlope = Get-LinearSlope -YValues $handleHistory.ToArray()
   477: $handleRSquared = Get-RSquared -YValues $handleHistory.ToArray()
   478: $projectedHandle100 = [int][math]::Round($handleSlope * 100)
   479: $actualHandleDelta = $finalDwm.HandleCount - $initialDwm.HandleCount
   ```

3. **Challenger M1_2 Report Findings**:
   In `.agents/teamwork/challenger_m1_2/challenge_m1_2.md` lines 54–86 (Defect 2):
   Challenger verified that normal background OS handle allocation of 1 or 2 handles yields a slope of 1.0 handle/switch, extrapolating to 100 handles across 100 switches. Because $100 > 50$, the smoke test consistently fails with `verdict = FAIL`.

4. **Empirical Verification of Proposed Slope Gating**:
   Evaluated the proposed gating replacement against simulated scenarios in temp execution:
   - $N = 1$ with 1-handle jitter: `Handles Verdict = PASS`, `Overall = PASSED`, `Exit Code = 0`.
   - $N = 1$ with 50-handle catastrophic leak: `Handles Verdict = FAIL`, `Overall = FAILED`, `Exit Code = 1`.
   - $N = 10$ with clean slope: `Handles Verdict = PASS`, `Overall = PASSED`, `Exit Code = 0`.
   - $N = 10$ with projected 80-handle leak: `Handles Verdict = FAIL`, `Overall = FAILED`, `Exit Code = 1`.

---

## 2. Logic Chain

1. **Step 1 (From Observation 1 & 2)**: At line 494, `$handlePassed` unconditionally evaluates `($projectedHandle100 -le $MaxHandleDelta)`. For $N = 1$, only two data points exist ($x=0$ and $x=1$). The slope is identical to the single-cycle delta ($y_1 - y_0$). Multiplying this single delta by 100 inflates a 1-handle background fluctuation to 100 handles, directly violating the threshold of 50 handles.
2. **Step 2 (From Observation 2)**: The harness already computes pro-rated actual thresholds (`$proRatedMaxWS` and `$proRatedMaxHandles`) designed specifically to scale with iteration count, providing a minimum threshold of 5.0 MB working set and 10 handles for low-iteration runs. The actual handle delta of 1 was well within this pro-rated threshold (1 <= 10).
3. **Step 3 (From Observation 3 & 4)**: Linear extrapolation by a factor of 100x from a sample size of $N < 10$ is statistically invalid and dominated by transient noise. Imposing a minimum sample size requirement ($N \ge 10$) allows OLS regression to operate on sufficient data points ($K \ge 11$) while gating low-iteration runs ($N < 10$) strictly on their pro-rated actual deltas.
4. **Step 4 (From Observation 4)**: Gating the projection check preserves full leak-detection power:
   - Normal low-iteration smoke runs pass cleanly without false positives.
   - Gross single-cycle leaks still fail because actual delta breaches `$proRatedMaxHandles` (10) or `$proRatedMaxWS` (5.0 MB).
   - Runs with $N \ge 10$ (such as full 100-switch validation runs) evaluate both actual and projected deltas, fully enforcing the original regression leak criteria.

---

## 3. Caveats

- This investigation was strictly read-only; no modifications were made to `scripts/diagnostics/stress_test.ps1`.
- The fix addresses Defect 2 (slope projection gating). Other defects identified by Challenger M1_2 (such as Defect 1: DWM process disappearance try/catch, Defect 3: filename PID collision, and Defect 4: drive creation fallback) are separate issues that can be composed seamlessly alongside this fix.
- Gating threshold is set to sample size $N \ge 10$ based on `$iterationRecords.Count` (representing completed iteration switches). If fewer than 10 iterations completed (e.g. 1 or 2 iteration smoke runs), slope projection is bypassed.

---

## 4. Conclusion

The exact code change required in `scripts/diagnostics/stress_test.ps1` is localized to lines 493–494.

### Proposed Code Replacement
**Target File**: `scripts/diagnostics/stress_test.ps1`  
**Lines**: 493–494  

**Replace**:
```powershell
$wsPassed = ($actualWSDelta -le $proRatedMaxWS) -and ($projectedWS100 -le $MaxWorkingSetDeltaMB)
$handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
```

**With**:
```powershell
# Gate 100-switch slope projection on sample size (N >= 10).
# For low-iteration smoke runs (N < 10), evaluate only pro-rated actual deltas to avoid false positives from background OS jitter.
# For N >= 10, evaluate both actual and projected deltas.
if ($iterationRecords.Count -ge 10) {
    $wsPassed = ($actualWSDelta -le $proRatedMaxWS) -and ($projectedWS100 -le $MaxWorkingSetDeltaMB)
    $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
} else {
    $wsPassed = ($actualWSDelta -le $proRatedMaxWS)
    $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles)
}
```

---

## 5. Verification Method

Once implemented, the fix can be independently verified using the following concrete steps:

1. **Verify 1-Iteration Smoke Test Passes (Fix Invalidation Condition)**:
   ```powershell
   $res = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\diagnostics\stress_test.ps1' -Iterations 1 -Mode Simulated -Json" | ConvertFrom-Json
   # Invalidation Condition: If $res.leakAnalysis.handles.verdict is "FAIL" or $res.overallVerdict is "FAILED", the fix is invalid.
   # Expected: $res.leakAnalysis.handles.verdict -eq "PASS" and $res.overallVerdict -eq "PASSED" and exit code 0.
   ```

2. **Verify 2-Iteration Smoke Test Passes**:
   ```powershell
   $res = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\diagnostics\stress_test.ps1' -Iterations 2 -Mode Simulated -Json" | ConvertFrom-Json
   # Expected: $res.leakAnalysis.handles.verdict -eq "PASS" and $res.overallVerdict -eq "PASSED" and exit code 0.
   ```

3. **Verify Existing E2E Test Suite Passes**:
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier 1 -Filter f03
   # Expected: All 5 F03 tests PASS.
   ```

4. **Verify Boundary Gating Logic with Unit Tests**:
   Execute the 4-case verification harness documented in `analysis_fix_slope_gating.md` Section 5.1.
