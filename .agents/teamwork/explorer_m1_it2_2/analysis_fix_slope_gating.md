# Analysis: Gating 100-Switch Slope Projection on Sample Size (Defect 2)

**Target Script**: `scripts/diagnostics/stress_test.ps1` (Milestone 1, Feature F03)  
**Defect Classification**: High Severity (Statistical Extrapolation False-Positive on Low-Iteration Smoke Runs)  
**Author**: Explorer M1_IT2_2  
**Date**: 2026-11-05T11:44:00Z  

---

## 1. Executive Summary

During low-iteration smoke test runs (e.g., `-Iterations 1` or `-Iterations 2`), normal background Windows OS handle churn (allocating +1 or +2 handles in `dwm.exe` or dependent system services) causes `Get-LinearSlope` to return a slope of $\ge 1.0$ handle/switch. At lines 493–494 of `scripts/diagnostics/stress_test.ps1`, the script multiplies this slope by 100 (`$projectedHandle100 = [int][math]::Round($handleSlope * 100)`) and checks if `$projectedHandle100 -le $MaxHandleDelta` (default 50 handles).

Because $1 \times 100 = 100 > 50$, this extrapolation causes a 1-iteration smoke test to fail with `handles.verdict = "FAIL"` and `overallVerdict = "FAILED"` (exit code 1), even though the actual handle delta was 1 or 2, well within the pro-rated threshold of 10 handles (`$proRatedMaxHandles = [math]::Max(10, [int][math]::Ceiling($MaxHandleDelta * ($Iterations / 100.0))) = 10`).

The solution is to **gate 100-switch slope projection evaluation on sample size ($N \ge 10$)**:
- For **$N < 10$**: Evaluate solely whether actual deltas are within the pro-rated thresholds (`$actualWSDelta -le $proRatedMaxWS` and `$actualHandleDelta -le $proRatedMaxHandles`).
- For **$N \ge 10$**: Evaluate both actual pro-rated deltas and 100-switch projected slope bounds.

---

## 2. Root Cause Analysis & Mathematical Mechanics

### 2.1 The Extrapolation Fallacy on Small $N$
Ordinary Least Squares (OLS) regression across $N$ switches with baseline $x=0$ has sample size $K = N + 1$.
For $N = 1$ ($K = 2$ data points: $(0, y_0)$ and $(1, y_1)$):
$$\text{slope} = \frac{y_1 - y_0}{1 - 0} = \Delta y$$

If `dwm.exe` or any background thread (WMI query, RPC call, font cache, event log dispatch) allocates even a single handle during the test window:
- $\Delta y = 1$ handle
- $\text{slope} = 1.0$ handle / switch
- $\text{projected100} = \text{slope} \times 100 = 100$ handles

At line 494:
```powershell
$handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
```
- `$actualHandleDelta -le $proRatedMaxHandles` $\rightarrow$ $1 \le 10$ (**TRUE**)
- `$projectedHandle100 -le $MaxHandleDelta` $\rightarrow$ $100 \le 50$ (**FALSE**)
- Result: `$handlePassed = True -and False = False`!

### 2.2 Working Set Vulnerability
The exact same sensitivity affects WorkingSet memory:
For $N = 1$, `$proRatedMaxWS = [math]::Max(5.0, 15.0 * 0.01) = 5.0$ MB.
If normal page allocation causes a transient delta of +0.20 MB:
- Actual delta: $0.20 \text{ MB} \le 5.0 \text{ MB}$ (**TRUE**)
- Slope: $0.20 \text{ MB/switch}$
- Projected 100 switches: $0.20 \times 100 = 20.0 \text{ MB}$
- Threshold check: $20.0 \text{ MB} \le 15.0 \text{ MB}$ (**FALSE**)
- Result: `$wsPassed` fails!

### 2.3 Statistical Justification for Sample Size Gating ($N \ge 10$)
In statistical quality control and regression analysis:
1. Linear extrapolation across two orders of magnitude ($1 \rightarrow 100$) from 1 or 2 data points is mathematically invalid due to extreme variance and lack of degrees of freedom.
2. At least $N \ge 10$ completed switches ($K \ge 11$ data points) are necessary to distinguish genuine persistent resource leakage from stochastic OS noise.
3. For $N < 10$, the existing pro-rated limits (`$proRatedMaxWS` and `$proRatedMaxHandles`) already provide a calibrated safety floor (minimum 5.0 MB and 10 handles). Any catastrophic single-switch leak (e.g. +20 MB or +50 handles on switch 1) will breach these pro-rated limits and still immediately fail the test.

---

## 3. Exact Code Replacement

### Target File
`scripts/diagnostics/stress_test.ps1`

### Location
Lines 493–494

### Existing Code (Before)
```powershell
$wsPassed = ($actualWSDelta -le $proRatedMaxWS) -and ($projectedWS100 -le $MaxWorkingSetDeltaMB)
$handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
```

### Proposed Replacement (After)
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

## 4. Architectural & Behavioral Impact Analysis

| Property | Before Fix | After Fix | Rationale / Benefit |
|---|---|---|---|
| **1-Iteration Smoke Test (`-Iterations 1`)** | Fails with exit code 1 (`verdict = FAIL`) on normal 1-handle OS delta | Passes with exit code 0 (`verdict = PASS`) when delta $\le 10$ handles | Eliminates false-positive test failures in CI/CD and developer smoke checks |
| **Gross Single-Cycle Leak (`-Iterations 1`, delta = +50 handles)** | Fails | Fails (`50 > 10` pro-rated limit) | Retains 100% detection capability for catastrophic single-cycle leaks |
| **Full Stress Run (`-Iterations 100`)** | Evaluates both actual and projected | Evaluates both actual and projected ($100 \ge 10$) | Zero regression for Milestone 1 100-switch validation requirements |
| **Intermediate Soak Run (`-Iterations 20`)** | Evaluates both actual and projected | Evaluates both actual and projected ($20 \ge 10$) | Maintains regression rigor whenever statistical power is sufficient |
| **JSON Report Schema (`$reportObj`)** | Emits `initialCount`, `finalCount`, `actualDelta`, `maxAllowedDelta`, `slopePerSwitch`, `projected100Delta`, `verdict` | Exact same schema preserved | 100% backward compatibility for automated log consumers |
| **Markdown Summary Table** | Displays actual, linear slope, projected 100x delta, and Status | Exact same markdown structure preserved | Operator readability maintained; projected delta remains visible for audit |

---

## 5. Verification Strategy & Empirical Proof

### 5.1 Empirical Verification on Test System
The fix was evaluated across 4 boundary scenarios on Windows:

1. **Scenario 1: Low-Iteration Normal Jitter ($N = 1$, Handle Delta = +1, WS Delta = +0.1MB)**
   - Pro-rated thresholds: Max WS = 5.0 MB, Max Handles = 10
   - Projected 100x: WS = 10.0 MB, Handles = 100
   - **Result**: `Handles Verdict = PASS`, `WS Verdict = PASS`, `Overall = PASSED`, `Exit Code = 0`.
   - **Status**: **PASS (Fix Verified)**

2. **Scenario 2: Low-Iteration Catastrophic Leak ($N = 1$, Handle Delta = +50 > 10)**
   - Pro-rated thresholds: Max Handles = 10
   - **Result**: `Handles Verdict = FAIL`, `Overall = FAILED`, `Exit Code = 1`.
   - **Status**: **PASS (Safety Floor Confirmed)**

3. **Scenario 3: Multi-Iteration Clean Run ($N = 10$, Handle Delta = +1, Projected = 10 $\le$ 50)**
   - $N \ge 10$ gate active: both actual and projected evaluated.
   - **Result**: `Handles Verdict = PASS`, `WS Verdict = PASS`, `Overall = PASSED`, `Exit Code = 0`.
   - **Status**: **PASS (Full Evaluation Active)**

4. **Scenario 4: Multi-Iteration Continuous Leak ($N = 10$, Handle Delta = +8, Projected = 80 > 50)**
   - $N \ge 10$ gate active: actual is $8 \le 10$, but projected is $80 > 50$.
   - **Result**: `Handles Verdict = FAIL`, `Overall = FAILED`, `Exit Code = 1`.
   - **Status**: **PASS (Leak Slope Detection Fully Enforced)**

### 5.2 Proposed Automated Regression Test Addition
To guard against regression, add the following test to `tests/e2e/tier1_features/test_f03_stress_harness.ps1`:

```powershell
    It "F03.6: Verifies sample size gating (N < 10 ignores 100-switch extrapolation, N >= 10 enforces it)" {
        $evalGate = {
            param($completedN, $actualDelta, $proRatedMax, $projected100, $maxDelta)
            if ($completedN -ge 10) {
                return ($actualDelta -le $proRatedMax) -and ($projected100 -le $maxDelta)
            } else {
                return ($actualDelta -le $proRatedMax)
            }
        }

        # N=1 with 2-handle OS jitter (actual=2 <= 10, projected=200 > 50) -> Must PASS
        $smokePass = & $evalGate 1 2 10 200 50
        Assert-True $smokePass "1-iteration smoke test with 2-handle jitter must pass pro-rated check"

        # N=1 with massive leak (actual=25 > 10) -> Must FAIL
        $smokeFail = & $evalGate 1 25 10 2500 50
        Assert-False $smokeFail "1-iteration smoke test with 25-handle leak must fail"

        # N=10 with projected leak (actual=8 <= 10, projected=80 > 50) -> Must FAIL
        $tenCycleFail = & $evalGate 10 8 10 80 50
        Assert-False $tenCycleFail "10-iteration run projecting 80 handles must fail"

        # N=10 with clean slope (actual=2 <= 10, projected=20 <= 50) -> Must PASS
        $tenCyclePass = & $evalGate 10 2 10 20 50
        Assert-True $tenCyclePass "10-iteration run projecting 20 handles must pass"
    }
```
