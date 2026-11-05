## 2026-11-05T12:31:31Z
You are Worker M2 implementing Milestone 2: Core Daemon & Ghost Monitor Eviction Engine.

Working directory: .agents/teamwork/worker_m2/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. Explorer M2_1 blueprint: .agents/teamwork/explorer_m2_1/event_window_design.md
4. Explorer M2_2 blueprint: .agents/teamwork/explorer_m2_2/ghost_eviction_design.md and .agents/teamwork/explorer_m2_2/GhostEvictionEngine.cs and .agents/teamwork/explorer_m2_2/Interop.cs
5. Explorer M2_3 blueprint: .agents/teamwork/explorer_m2_3/build_lifecycle_design.md
6. Test suites to satisfy:
   - tests/e2e/tier1_features/test_f04_ghost_eviction.ps1
   - tests/e2e/tier1_features/test_f05_display_change_listener.ps1
   - tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive File Ownership:
You own and have exclusive write permission to:
- src/app.manifest
- src/Daemon/Interop.cs
- src/Daemon/GhostEvictionEngine.cs
- src/Daemon/EventWindow.cs
- src/Daemon/Program.cs
- scripts/build.ps1
- scripts/install.ps1
- scripts/uninstall.ps1
- build.ps1
- install.ps1
- uninstall.ps1
- bin/DisplayFixDaemon.exe

Key Implementation Guidelines:
1. Language compatibility: The system compiler is C# 5 (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`). DO NOT use C# 6+ features like string interpolation `$"..."`. Use `string.Format(...)` or string concatenation.
2. EventWindow architecture: Do NOT use `HWND_MESSAGE` because Windows blocks `HWND_BROADCAST` (such as `WM_DISPLAYCHANGE` 0x007E) from reaching message-only windows. Use a hidden unmapped top-level tool window (`WS_POPUP | WS_EX_TOOLWINDOW` positioned off-screen) as designed by Explorer M2_1.
3. Event debouncing: Implement the 200ms quiet-window timer to coalesce rapid bursts into a single reconfiguration event (satisfying test F05.4).
4. Single-instance mutex: Use `Global\DisplayFixDaemon_SingleInstanceMutex` (satisfying test F06.4).
5. Native ghost eviction: Must execute in-process via CfgMgr32 / SetupAPI in < 500ms without spawning child processes (`pnputil.exe` or `powershell.exe`). Target ONLY internal panel `AUOAA9F` with token `UID8388688` (parent `PCI\VEN_8086&DEV_A78B`). Strictly protect active NVIDIA node `UID4353` and external monitors.
6. Install/Uninstall scripts:
   - `install.ps1` & `scripts/install.ps1`: Registers Scheduled Task `DisplayFixDaemon` running `bin/DisplayFixDaemon.exe --run` at user logon with `RunLevel: HighestAvailable`.
   - `uninstall.ps1` & `scripts/uninstall.ps1`: Must explicitly contain `Unregister-ScheduledTask` and `Stop-Process` to satisfy test F06.5.
7. Verification:
   - Run `build.ps1` / `scripts/build.ps1` to compile `bin/DisplayFixDaemon.exe`.
   - Run tests:
     `powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 1 -Filter "f04|f05|f06"`
     All 15 tests must pass with exit code 0.
   - Test CLI:
     `bin/DisplayFixDaemon.exe --status`
     `bin/DisplayFixDaemon.exe --evict-now`

Deliverables:
- Implement all files cleanly.
- Run build and test verification, and record exact commands and console outputs.
- Write handoff report to `.agents/teamwork/worker_m2/handoff.md`.
- Send completion message back via send_message.
