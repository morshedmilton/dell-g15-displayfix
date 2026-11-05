## 2026-11-05T11:52:37Z
You are Worker M1 (Iteration 2) for Milestone 1 (Diagnostics, Telemetry & Stress Harness).
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\worker_m1_it2\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Also read PROJECT.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md

READ THE EXPLORER BLUEPRINTS:
1. Explorer M1_IT2_1 on Defect 1 (DWM Crash Handling):
   c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m1_it2_1\analysis_fix_dwm_crash.md
2. Explorer M1_IT2_2 on Defect 2 (Slope Gating on Small N):
   c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m1_it2_2\analysis_fix_slope_gating.md
3. Explorer M1_IT2_3 on Defects 3 & 4 (Concurrency PID Filename & OutputDir Missing Drive Fallback):
   c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m1_it2_3\analysis_fix_concurrency_io.md

YOUR FILE OWNERSHIP (Exclusive):
- `scripts/diagnostics/stress_test.ps1`

Tasks:
1. Apply the 4 formulated code fixes to `scripts/diagnostics/stress_test.ps1`:
   - Defect 1: Wrap `Get-DwmTelemetry` in `try/catch` at lines 359-362 and line 466, handle null process safely, fire circuit breaker (`$abortFired = $true`, `$abortReason = "DWM process terminated and not running"`), mark iteration status as `FAIL`, break loop cleanly, and ensure Section 5 & 6 generate the complete JSON and Markdown audit reports.
   - Defect 2: In lines 493-494, gate 100-switch slope projection on sample size ($N \ge 10$). For $N < 10$, evaluate only actual pro-rated deltas (`$actualWSDelta -le $proRatedMaxWS` and `$actualHandleDelta -le $proRatedMaxHandles`). For $N \ge 10$, evaluate both actual and projected deltas.
   - Defect 3: In line 504, include `$PID` in the report timestamp filename (`$timestampStr = "$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"`).
   - Defect 4: In lines 287-289, wrap `OutputDir` creation in `try/catch` and fallback to `$env:TEMP\DisplayFix\logs` if directory creation fails on invalid drives.
2. Verify all fixes on the live system:
   - Run `stress_test.ps1 -Iterations 1 -Mode Simulated -Json` and verify it passes (no false positive).
   - Run `stress_test.ps1 -Iterations 5 -Mode Simulated -Json` and verify it passes and report filename contains PID.
   - Run E2E test runner: `tests/e2e/test_runner.ps1 -Tier 1 -Filter "f01|f02|f03"` and verify all 15 tests pass.
   - Run Tier 5 adversarial diagnostics test: `tests/e2e/tier5_adversarial/adversarial_diagnostics_test.ps1` and verify all tests pass.
3. Document all execution commands and outputs in `handoff.md`.
4. Send a completion message to the parent orchestrator.
