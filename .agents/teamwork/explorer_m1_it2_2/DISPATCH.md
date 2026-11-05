## 2026-11-05T11:38:47Z
You are Explorer M1_IT2_2 for Milestone 1 (Diagnostics, Telemetry & Stress Harness) - Iteration 2.
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m1_it2_2\

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Also read PROJECT.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md

READ THE FAILURE REPORT:
Read Challenger M1_2 challenge report and handoff:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\challenger_m1_2\challenge_m1_2.md
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\challenger_m1_2\handoff.md

Your mission:
Formulate the exact code fix and verification strategy for Defect 2 in `scripts/diagnostics/stress_test.ps1`:
- In line 493-494, `projectedHandle100` ($slope \times 100 \le 50$) is evaluated regardless of sample size. Normal background OS handle jitter (+1 or +2 handles) during low-iteration smoke runs (`-Iterations 1` or `-Iterations 2`) yields a slope of $\ge 1.0$, projecting $\ge 100$ handles and falsely failing 1-iteration smoke tests despite the actual delta (2) being well within the pro-rated threshold (10).
- Formulate the precise fix: gate 100-switch slope projection on sample size ($N \ge 10$). For $N < 10$, evaluate only actual pro-rated deltas (`$actualWSDelta -le $proRatedMaxWS` and `$actualHandleDelta -le $proRatedMaxHandles`). For $N \ge 10$, evaluate both actual and projected deltas.

Scope boundaries:
- You are read-only. Provide detailed fix analysis and exact code replacements in `analysis_fix_slope_gating.md` and complete handoff to `handoff.md`.
- Send completion message to parent upon finishing.
