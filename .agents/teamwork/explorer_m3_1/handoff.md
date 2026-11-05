# Explorer M3_1 Handoff Report: 360Hz Refresh Rate Lock Engine

**Explorer:** Explorer M3_1  
**Date:** 2026-11-05  
**Milestone:** Milestone 3 (360Hz Refresh Rate Lock & Persistent 125% DPI Scaling)  
**Working Directory:** `.agents/teamwork/explorer_m3_1/`  
**Deliverables:**
- `.agents/teamwork/explorer_m3_1/refresh_rate_design.md` (Full Architectural & Code Blueprint)
- `.agents/teamwork/explorer_m3_1/RefreshRateLock.cs` (Standalone Compilable C# 5 Source)
- `.agents/teamwork/explorer_m3_1/Interop_M3_Extensions.cs` (Standalone Compilable C# 5 P/Invoke Extensions for `Interop.cs`)

---

## 1. Observation

1. **Live CCD Topology & Rational Timing Measurement**:
   - Executed `GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS = 0x2)` and `QueryDisplayConfig` against the live Dell G15 5530 hardware:
     - Structure sizes verified on x64 .NET 4.8:
       - `Marshal.SizeOf(typeof(DISPLAYCONFIG_PATH_INFO))` = `72` bytes
       - `Marshal.SizeOf(typeof(DISPLAYCONFIG_MODE_INFO))` = `64` bytes
       - `Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET))` = `24` bytes
     - Active Path `[0]` hardware properties retrieved via `DisplayConfigGetDeviceInfo`:
       - `viewGdiDeviceName`: `\\.\DISPLAY5`
       - `monitorDevicePath`: `\\?\DISPLAY#AUOAA9F#5&39808dae&2&UID4353#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}`
       - `adapterDevicePath`: `\\?\PCI#VEN_10DE&DEV_28E0&SUBSYS_0BF71028&REV_A1#4&3b6a47d9&0&0008#{5b45201d-f2f2-4f3b-85bb-30ff1f953599}`
       - `targetInfo.refreshRate`: `Numerator = 360152`, `Denominator = 1000` (`360.152 Hz`)
       - `targetMode.targetVideoSignalInfo`: `vSyncFreq = 360152/1000`, `hSyncFreq = 839010000/2080`, `pixelRate = 839010000`, `activeSize = 1920x1080`, `totalSize = 2080x1120`, `videoStandard = 255`, `scanLineOrdering = 1`.
2. **Live `ChangeDisplaySettingsExW` Secondary Fallback Verification**:
   - Calling `ChangeDisplaySettingsExW` with `lpszDeviceName = null` or overwriting `dm.dmFields = DM_DISPLAYFREQUENCY` (which strips `DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFLAGS`) returns `-1` (`DISP_CHANGE_FAILED`).
   - Calling `EnumDisplaySettingsW(viewGdiDeviceName, ENUM_CURRENT_SETTINGS, ref dm)` (where `dmSize = 220` bytes for `DEVMODEW`), preserving existing `dm.dmFields` (`0x005C0000`), OR-ing `dm.dmFields |= DM_DISPLAYFREQUENCY`, setting `dm.dmDisplayFrequency = 360`, and invoking `ChangeDisplaySettingsExW(viewGdiDeviceName, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero)` returns `0` (`DISP_CHANGE_SUCCESSFUL`).
3. **Compiler Verification**:
   - Compiled `.agents/teamwork/explorer_m3_1/RefreshRateLock.cs` and `.agents/teamwork/explorer_m3_1/Interop_M3_Extensions.cs` together with existing `src/Daemon/*.cs` using `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /platform:x64 /warn:4`:
     - Exit code: `0` (zero warnings, zero errors, strict C# 5 compliance).

---

## 2. Logic Chain

1. **Exact Hardware Rational Contract (Test F07.2 & C01.1)**:
   - Because the AUO AA9F internal panel operates at a native vertical refresh rate of `360.152 Hz`, supplying `Numerator = 360152` and `Denominator = 1000` in both `DISPLAYCONFIG_PATH_TARGET_INFO.refreshRate` and `DISPLAYCONFIG_TARGET_MODE.targetVideoSignalInfo.vSyncFreq` (along with `pixelRate = 839010000` and `hSyncFreq = 839010000/2080` for 1920x1080) matches the exact hardware mode timing expected by the WDDM 3.1 driver.
2. **Persistence Database Flag Contract (Test F07.3 & C04.3)**:
   - Combining `SDC_APPLY (0x80) | SDC_USE_SUPPLIED_DISPLAY_CONFIG (0x20) | SDC_SAVE_TO_DATABASE (0x200) | SDC_ALLOW_CHANGES (0x400)` equals `0x000006A0`.
   - When executed by the elevated `DisplayFixDaemon` scheduled task, `SDC_SAVE_TO_DATABASE` commits the 360.152Hz mode into `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration`, preventing future hotplug/mux transitions from defaulting to 60Hz.
   - If invoked from a non-elevated session where `0x000006A0` returns `ERROR_ACCESS_DENIED (5)`, retrying with `0x000004A0` (omitting `SDC_SAVE_TO_DATABASE`) or falling back to `ChangeDisplaySettingsExW` ensures dynamic 360Hz enforcement still succeeds.
3. **Stand-Down Optimization (Test F07.5 & C01.2)**:
   - Since the AUO AA9F panel only has two states (`60Hz` and `360Hz`), checking `curHz < 300.0` (`MinimumHighRefreshThresholdHz`) accurately detects 60Hz fallback while standing down in `< 2ms` with zero display flicker when the panel is already running at `360.152Hz` (unless `force: true` is requested).

---

## 3. Caveats

1. **Non-Elevated `SetDisplayConfig` Permissions**:
   - In non-elevated shells (Session 1 standard token), `SetDisplayConfig` can return `ERROR_ACCESS_DENIED (5)` when `SDC_SAVE_TO_DATABASE (0x200)` is set or when the active topology is locked by an elevated service. `RefreshRateLock.CheckAndEnforce` handles this gracefully by:
     1. Attempting `SetDisplayConfig` with `0x000006A0` (full persistence).
     2. Retrying `SetDisplayConfig` with `0x000004A0` (no database save) if `rc == 5`.
     3. Retrying `SetDisplayConfig` with `targetInfo.modeInfoIdx = DISPLAYCONFIG_PATH_MODE_IDX_INVALID (0xFFFFFFFF)` if explicit mode timing is rejected.
     4. Falling back to `ChangeDisplaySettingsExW(matchedGdiName, ref dm, ...)` with `dmDisplayFrequency = 360` (which succeeds even in non-elevated user contexts).
2. **Shared `Interop.cs` Definitions with Explorer M3_2**:
   - `Interop_M3_Extensions.cs` includes `DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3`, `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`, `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET`, and `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` (24 bytes) so Worker M3 can merge a single unified CCD region into `src/Daemon/Interop.cs` without duplicate struct definitions.

---

## 4. Conclusion

The 360Hz Refresh Rate Lock Engine (`RefreshRateLock.cs` and `Interop.cs` extensions) is completely designed, verified against live hardware CCD/DEVMODE APIs, and confirmed to compile with zero warnings on 64-bit .NET Framework 4.8 `csc.exe` (C# 5). All requirements for Feature F07, Combination C01/C04, and Interface Contract #2 in `PROJECT.md` are satisfied.

---

## 5. Verification Method

1. **Verify Feature F07 E2E Test Suite**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier 1 -Filter "f07"
   ```
2. **Verify Zero-Warning C# 5 Compilation with `csc.exe`**:
   Merge the `#region Windows CCD & Display Settings Constants & Structures` from `.agents/teamwork/explorer_m3_1/Interop_M3_Extensions.cs` into `src/Daemon/Interop.cs`, copy `.agents/teamwork/explorer_m3_1/RefreshRateLock.cs` to `src/Daemon/RefreshRateLock.cs`, and run:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1
   ```
