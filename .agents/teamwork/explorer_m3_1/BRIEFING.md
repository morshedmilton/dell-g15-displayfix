# BRIEFING — 2026-11-05T13:36:00Z

## Mission
Investigate and design the 360Hz Refresh Rate Lock Engine (`RefreshRateLock.cs` & `Interop.cs` extensions) for Milestone 3.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m3_1
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: Milestone 3 (360Hz Refresh Rate Lock)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in `src/` (provide complete blueprints in our own folder)
- Windows CCD API: QueryDisplayConfig (QDC_ONLY_ACTIVE_PATHS = 0x2) and SetDisplayConfig
- Combined flags: SDC_APPLY (0x80) | SDC_USE_SUPPLIED_DISPLAY_CONFIG (0x20) | SDC_SAVE_TO_DATABASE (0x200) | SDC_ALLOW_CHANGES (0x400) = 0x000006A0 (verified by test F07.3)
- Exact hardware rational frequency for internal panel AUO AA9F: Numerator = 360152, Denominator = 1000 (360.152 Hz, test F07.2)
- Mode detection: Query active display mode. If current frequency < 300Hz, enforce 360Hz. If already 360Hz, stand down.
- Secondary fallback: ChangeDisplaySettingsEx with DEVMODE dmDisplayFrequency = 360 if CCD fails.
- Strict C# 5 syntax compatibility (no string interpolation `$""`, etc.) targeting .NET Framework 4.8 x64 csc.exe.

## Current Parent
- Conversation ID: fe9fc6db-f74f-40c5-a931-72b007a4c96e
- Updated: 2026-11-05T13:36:00Z

## Investigation State
- **Explored paths**: `PROJECT.md`, `ORIGINAL_REQUEST.md`, `test_f07_refresh_rate_360hz.ps1`, `test_c01_switching_and_360hz.ps1`, `test_c04_360hz_and_dpi_scale.ps1`, `src/Daemon/Interop.cs`, `src/Daemon/Program.cs`, `src/Daemon/EventWindow.cs`, `src/Daemon/GhostEvictionEngine.cs`, live CCD and DEVMODEW hardware probes.
- **Key findings**:
  - `DISPLAYCONFIG_PATH_INFO` size = 72 bytes, `DISPLAYCONFIG_MODE_INFO` size = 64 bytes on x64.
  - Internal panel `AUOAA9F` reports `Numerator = 360152`, `Denominator = 1000`, `pixelRate = 839010000`, `hSyncFreq = 839010000 / 2080` at 1920x1080.
  - `ChangeDisplaySettingsExW` requires the specific GDI device name (`viewGdiDeviceName`, e.g. `\\.\DISPLAY5`) and preserving populated `DEVMODEW` fields from `EnumDisplaySettingsW(..., ENUM_CURRENT_SETTINGS, ref dm)` while OR-ing `DM_DISPLAYFREQUENCY` to return `0` (`DISP_CHANGE_SUCCESSFUL`).
- **Unexplored areas**: None (all objectives completed).

## Key Decisions Made
- Designed `RefreshRateLock.cs` with multi-stage resilience: (1) CCD `SetDisplayConfig` with `0x000006A0`, (2) retry with `0x000004A0` if `ERROR_ACCESS_DENIED (5)`, (3) retry with `DISPLAYCONFIG_PATH_MODE_IDX_INVALID` if explicit mode struct rejected, and (4) fallback to `ChangeDisplaySettingsExW(viewGdiDeviceName, ref dm, ...)` with `dmDisplayFrequency = 360`.
- Included DPI scaling CCD structs in `Interop_M3_Extensions.cs` so Worker M3 has a single unified `Interop.cs` extension block.

## Artifact Index
- `DISPATCH.md` — Task assignment
- `progress.md` — Liveness heartbeat
- `BRIEFING.md` — Persistent working memory
- `refresh_rate_design.md` — Full architectural & C# 5 code blueprint
- `RefreshRateLock.cs` — Compilable C# 5 source for `src/Daemon/RefreshRateLock.cs`
- `Interop_M3_Extensions.cs` — Compilable C# 5 P/Invoke additions for `src/Daemon/Interop.cs`
- `handoff.md` — 5-component handoff report
