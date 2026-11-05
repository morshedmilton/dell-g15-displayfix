# BRIEFING — 2026-11-05T12:47:00Z

## Mission
Implement Milestone 2: Core Daemon & Ghost Monitor Eviction Engine, including EventWindow, Interop, GhostEvictionEngine, Program CLI/daemon, build/install/uninstall scripts, and app manifest, verified against all 15 tests in F04, F05, and F06.

## 🔒 My Identity
- Archetype: worker
- Roles: implementer, qa
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\worker_m2
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: M2 (Core Daemon & Ghost Monitor Eviction Engine)

## 🔒 Key Constraints
- Language compatibility: C# 5 (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`). No C# 6+ features (e.g. no string interpolation `$"..."`).
- EventWindow: Hidden unmapped top-level tool window (`WS_POPUP | WS_EX_TOOLWINDOW` positioned off-screen), NOT `HWND_MESSAGE`.
- Debouncing: 200ms quiet-window timer coalescing bursts into single event.
- Single-instance mutex: `Global\DisplayFixDaemon_SingleInstanceMutex`.
- Native ghost eviction: In-process via CfgMgr32 / SetupAPI in < 500ms without spawning child processes. Target internal panel `AUOAA9F` with token `UID8388688` (parent `PCI\VEN_8086&DEV_A78B`). Protect active NVIDIA node `UID4353` and external monitors.
- Install/Uninstall scripts:
  - `install.ps1` & `scripts/install.ps1`: Registers Scheduled Task `DisplayFixDaemon` running `bin/DisplayFixDaemon.exe --run` at user logon with `RunLevel: HighestAvailable`.
  - `uninstall.ps1` & `scripts/uninstall.ps1`: Must explicitly contain `Unregister-ScheduledTask` and `Stop-Process`.
- Integrity: DO NOT CHEAT. Real state and genuine behavior only.

## Current Parent
- Conversation ID: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Updated: 2026-11-05T12:47:00Z

## Task Summary
- **What to build**: Core Daemon (`DisplayFixDaemon.exe`) and build/install scripts.
- **Success criteria**: All 15 tests in F04, F05, F06 pass exit code 0; CLI commands `--status`, `--evict-now` work.
- **Interface contracts**: PROJECT.md, Explorer M2 blueprints.
- **Code layout**: src/Daemon/..., scripts/..., root scripts, bin/...

## Key Decisions Made
- `src/app.manifest`: Configured `asInvoker` with `PerMonitorV2` and Windows 10/11 GUID so CLI commands run directly from non-elevated user shell, while Task Scheduler starts the resident daemon with `RunLevel: Highest`.
- Console attachment: Implemented `EnsureConsoleOutput` using `GetStdHandle` + `AttachConsole` + `CreateFile("CONOUT$")` so `winexe` CLI commands output directly to PowerShell and cmd prompts.
- Debounce window: 200ms quiet-window timer coalescing bursts into single reconfiguration dispatch.
- In-process eviction: In-process SetupAPI and CfgMgr32 cycling completing in ~8.4ms (well under 500ms budget) without child process overhead.

## Artifact Index
- `src/app.manifest` — Application manifest with DPI awareness and OS compatibility
- `src/Daemon/Interop.cs` — P/Invoke interop for Win32, SetupAPI, and CfgMgr32
- `src/Daemon/GhostEvictionEngine.cs` — In-process ghost eviction engine
- `src/Daemon/EventWindow.cs` — Win32 top-level hidden tool window with 200ms debouncing
- `src/Daemon/Program.cs` — Main daemon entry point, CLI, single-instance mutex, rotating Logger
- `scripts/build.ps1` & `build.ps1` — C# 5 compiler scripts
- `scripts/install.ps1` & `install.ps1` — Scheduled task installer
- `scripts/uninstall.ps1` & `uninstall.ps1` — Lifecycle uninstaller
- `bin/DisplayFixDaemon.exe` — Standalone daemon binary

## Change Tracker
- **Files modified**: `src/app.manifest`, `src/Daemon/Interop.cs`, `src/Daemon/GhostEvictionEngine.cs`, `src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`, `scripts/build.ps1`, `scripts/install.ps1`, `scripts/uninstall.ps1`, `build.ps1`, `install.ps1`, `uninstall.ps1`, `bin/DisplayFixDaemon.exe`
- **Build status**: PASS (csc.exe compile in ~140ms)
- **Pending issues**: None

## Quality Status
- **Build/test result**: PASS (15/15 tests in F04, F05, F06; 20/20 in Tier 2; 16/16 in Tier 4)
- **Lint status**: Clean (C# 5 standard syntax, /warn:4 clean)
- **Tests added/modified**: Verified against all test suites
