## 2026-11-05T13:02:57Z
You are Explorer M3_1 investigating and designing the 360Hz Refresh Rate Lock Engine for Milestone 3.

Working directory: .agents/teamwork/explorer_m3_1/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f07_refresh_rate_360hz.ps1
4. Existing source code in `src/Daemon/` (`Interop.cs`, `Program.cs`, `EventWindow.cs`).

Objectives:
1. Design `src/Daemon/RefreshRateLock.cs` & required P/Invoke in `Interop.cs`:
   - Windows CCD API: `QueryDisplayConfig` (`QDC_ONLY_ACTIVE_PATHS` = 0x00000002) and `SetDisplayConfig`.
   - Combined flags: `SDC_APPLY (0x80) | SDC_USE_SUPPLIED_DISPLAY_CONFIG (0x20) | SDC_SAVE_TO_DATABASE (0x200) | SDC_ALLOW_CHANGES (0x400)` = `0x000006A0` (verified by test F07.3).
   - Exact hardware rational frequency for internal panel AUO AA9F: Numerator = `360152`, Denominator = `1000` (rational 360.152 Hz, verified by test F07.2).
   - Mode detection: Query active display mode. If current frequency < 300Hz (e.g. 60Hz fallback), enforce 360Hz. If already 360Hz, stand down.
   - Secondary fallback: `ChangeDisplaySettingsEx` with `DEVMODE` `dmDisplayFrequency = 360` if CCD call fails.
2. Ensure strict C# 5 syntax compatibility (no string interpolation) for native `csc.exe` on .NET 4.8 x64.
3. Provide a complete, compilable blueprint for `RefreshRateLock.cs` and new P/Invoke definitions for `Interop.cs`.

Deliverables:
- Write design blueprint to `.agents/teamwork/explorer_m3_1/refresh_rate_design.md`
- Write handoff to `.agents/teamwork/explorer_m3_1/handoff.md`
- Send completion message back via send_message.
