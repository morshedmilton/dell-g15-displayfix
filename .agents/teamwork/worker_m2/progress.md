# Progress Log — Worker M2

Last visited: 2026-11-05T12:47:00Z

## Status
Completed Milestone 2: Core Daemon & Ghost Monitor Eviction Engine implementation and verification.

### Actions Completed
1. Created `src/app.manifest` with `asInvoker` execution level, `PerMonitorV2` DPI awareness, Windows 10/11 compatibility GUID `{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}`, and `longPathAware`.
2. Created `src/Daemon/Interop.cs` containing SetupAPI, CfgMgr32, and User32 P/Invoke declarations, structs, and GUIDs.
3. Created `src/Daemon/GhostEvictionEngine.cs` implementing in-process CfgMgr32 / SetupAPI monitor enumeration, strict targeting of Intel ghost node `AUOAA9F` with token `UID8388688`, active protection of NVIDIA node `UID4353`, and exclusion of foreign displays.
4. Created `src/Daemon/EventWindow.cs` implementing hidden unmapped top-level tool window (`WS_POPUP | WS_EX_TOOLWINDOW` at `-32000, -32000`) for broadcast reception of `WM_DISPLAYCHANGE` (0x007E), `WM_DEVICECHANGE` (0x0219), and `WM_POWERBROADCAST` (0x0218), coupled with a 200ms quiet-window debouncing timer.
5. Created `src/Daemon/Program.cs` implementing the resident daemon entry point, single-instance mutex `Global\DisplayFixDaemon_SingleInstanceMutex` (duplicate exit code 2), CLI handlers (`--run`, `--status`, `--evict-now`, `--install`, `--uninstall`), and embedded `Logger`.
6. Created `scripts/build.ps1` and root `build.ps1` compiling `bin/DisplayFixDaemon.exe` with `csc.exe` in ~140ms.
7. Created `scripts/install.ps1` and root `install.ps1` managing elevated Scheduled Task `DisplayFixDaemon` at user logon with `RunLevel: HighestAvailable`.
8. Created `scripts/uninstall.ps1` and root `uninstall.ps1` containing `Stop-Process` and `Unregister-ScheduledTask`.
9. Verified with all 15 tests in F04, F05, F06 passing 100% (exit code 0).
10. Verified CLI commands `bin/DisplayFixDaemon.exe --status` and `bin/DisplayFixDaemon.exe --evict-now` (completing in ~8.4ms).
