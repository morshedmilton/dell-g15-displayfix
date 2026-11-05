## 2026-11-05T12:18:23Z
You are Explorer M2_1 investigating and designing the core daemon architecture and Windows message loop for Milestone 2.

Working directory: .agents/teamwork/explorer_m2_1/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\TEST_READY.md
4. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f05_display_change_listener.ps1
5. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f06_daemon_lifecycle.ps1

Objectives:
1. Design `src/Daemon/Program.cs`:
   - Single-instance mutex named `Global\DisplayFixDaemon_SingleInstanceMutex` (verified by test F06.4).
   - CLI flags: `--run` (default resident daemon), `--install` (invoke install script), `--uninstall`, `--status` (check daemon status/telemetry), `--evict-now` (one-shot ghost monitor eviction).
   - Structured logging to `C:\ProgramData\DisplayFix\logs\daemon.log` with timestamp, log level, and component tag.
2. Design `src/Daemon/EventWindow.cs`:
   - Native message-only window (`HWND_MESSAGE` parent) to receive broadcast and window messages without showing taskbar or UI.
   - Register for device notifications via `RegisterDeviceNotification` using `GUID_DEVINTERFACE_MONITOR` (`{E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}`) and `GUID_DEVINTERFACE_DISPLAY_ADAPTER` (`{5B45201D-F2F2-4F3B-85BB-30FF1F953599}`).
   - Register for power setting notifications via `RegisterPowerSettingNotification` using `GUID_CONSOLE_DISPLAY_STATE` (`{6FE69556-704A-47A0-8F24-C28D936FDA47}`).
   - WndProc message handling:
     - `WM_DISPLAYCHANGE` (0x007E): extract width (LOWORD) and height (HIWORD).
     - `WM_DEVICECHANGE` (0x0219): handle `DBT_DEVICEARRIVAL` (0x8000) and `DBT_DEVICEREMOVECOMPLETE` (0x8004).
     - `WM_POWERBROADCAST` (0x0218): decode `PBT_POWERSETTINGCHANGE` (0x8013) and check display state (1 = On -> trigger check, 0 = Off / 2 = Dimmed -> stand down).
   - Event Debouncing: Burst events (e.g. 5 events within 50ms) must coalesce into exactly 1 action after a 200ms quiet window (verified by test F05.4).
3. Provide full, compilable C# source blueprints for `Program.cs` and `EventWindow.cs` targeting .NET Framework 4.8 x64 (no external NuGet packages).

Deliverables:
- Write comprehensive blueprint to `.agents/teamwork/explorer_m2_1/event_window_design.md`
- Write handoff to `.agents/teamwork/explorer_m2_1/handoff.md`
- Send completion message back via send_message.
