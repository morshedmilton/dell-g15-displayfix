## 2026-11-05T10:56:48Z

You are the E2E Test Writer leading the E2E Testing Track for the Dell G15 5530 DisplayFix project.
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\test_writer_e2e\

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Also read PROJECT.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md

Your mission:
Design and implement the complete opaque-box E2E test suite according to the Project Pattern specifications:
1. Create `TEST_INFRA.md` at project root (`c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\TEST_INFRA.md`) following the template in Project Pattern rules.
2. Build the master test runner script:
   `tests/e2e/test_runner.ps1`
   Supporting parameters: `-Tier <1|2|3|4|All>`, `-Json`, `-Verbose`, returning exit code 0 when all tests pass, non-zero on failure.
3. Author comprehensive opaque-box test cases covering every feature in `PROJECT.md § Feature Inventory` (F01–F16):
   - `tests/e2e/tier1_features/`: Feature coverage tests verifying each feature in isolation (≥5 tests per feature).
   - `tests/e2e/tier2_boundaries/`: Boundary and corner cases (empty configs, extreme values, rapid sequential events, invalid registry states).
   - `tests/e2e/tier3_combinations/`: Cross-feature combinations (pairwise interactions between switching, 360Hz lock, 125% DPI scale, and brightness hotkeys).
   - `tests/e2e/tier4_scenarios/`: Real-world application scenarios (gaming session, laptop lid/sleep resume, external display connect/disconnect, prolonged video playback).
4. Publish `TEST_READY.md` at project root with full coverage summary and execution instructions once all test scripts are authored and verified.
5. Write your handoff report to `handoff.md` in your working directory and notify the parent via `send_message`.

Scope boundaries:
- You write test infrastructure and test scripts (`TEST_INFRA.md`, `TEST_READY.md`, `tests/e2e/**`). Do NOT modify product implementation code in `src/`.
- Ensure tests are progressive: Tier 1 tests can run and give signals even before full daemon compilation.
