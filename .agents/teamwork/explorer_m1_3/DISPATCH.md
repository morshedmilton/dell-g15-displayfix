## 2026-11-05T10:56:26Z
You are Explorer M1_3 for Milestone 1 (Diagnostics, Telemetry & Stress Harness).
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m1_3\

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Also read PROJECT.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
and read previous survey reports at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\spec_miner_display\survey_display_spec.md

Your mission:
Design the implementation strategy and technical architecture for `scripts/diagnostics/stress_test.ps1` (Feature F03).
Requirements:
1. Support repeated display switching stress testing up to 100 iterations (parameter `-Iterations 100`, default 10 for quick smoke test, 100 for soak validation).
2. Measure baseline DWM metrics (WorkingSet, PagedMemorySize, GDI/USER handles, Event IDs 1000/4101).
3. Execute stress iterations safely:
   - Either trigger display topology changes (via CCD `SetDisplayConfig` cycling between clone/extend/internal modes, or device cycling) or monitor external switches.
   - Wait for post-switch stabilization (settle delay e.g. 500-1000ms).
   - Verify active refresh rate remains at 360Hz and scaling remains at 125% after each iteration.
4. Calculate memory and handle leak slopes:
   - Handle leak delta: $(Handles_{final} - Handles_{initial}) \le 50$ handles over 100 switches.
   - WorkingSet leak delta: $(WS_{final} - WS_{initial}) \le 30$ MB over 100 switches.
   - Crash/TDR detection: exactly 0 new Event ID 1000 or Event ID 4101 events.
5. Generate a comprehensive stress test report in JSON and Markdown with timestamped iteration logs.

Scope boundaries:
- You are strictly READ-ONLY. Recommend implementation details, script structure, parameters, leak calculation math, and thresholds. Do NOT modify source code or system settings.
- Write your report to `analysis_stress_test.md` and complete handoff to `handoff.md` in your working directory.
- Send a completion message to parent upon finishing.
