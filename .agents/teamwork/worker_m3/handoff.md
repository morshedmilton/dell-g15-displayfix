# Worker M3 Handoff Report: 360Hz Refresh Rate Lock & Persistent 125% DPI Scaling

**Agent:** Worker M3  
**Date:** 2026-11-05  
**Milestone:** Milestone 3 (360Hz Refresh Rate Lock & Persistent 125% DPI Scaling)  
**Working Directory:** `.agents/teamwork/worker_m3/`  
**Status:** COMPLETED  

---

## 1. Summary of Changes Implemented

1. **Unified Windows CCD & DPI Interop (`src/Daemon/Interop.cs`)**:
   - Merged all Windows CCD (`GetDisplayConfigBufferSizes`, `QueryDisplayConfig`, `SetDisplayConfig`, `DisplayConfigGetDeviceInfo`, `DisplayConfigSetDeviceInfo`) and User32 display mode (`EnumDisplaySettingsW`, `ChangeDisplaySettingsExW`, `GetDpiForSystem`) constants, structures, and P/Invoke signatures cleanly into `src/Daemon/Interop.cs` with zero duplicate symbols.
   - Verified structure sizes and layouts on 64-bit .NET Framework 4.8:
     - `DISPLAYCONFIG_PATH_INFO` = 72 bytes
     - `DISPLAYCONFIG_MODE_INFO` = 64 bytes
     - `DISPLAYCONFIG_DEVICE_INFO_HEADER` = 20 bytes
     - `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET` (`type = -3`) = 32 bytes
     - `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` (`type = -4`) = 24 bytes
     - `DEVMODEW` = 220 bytes

2. **360Hz Refresh Rate Lock Engine (`src/Daemon/RefreshRateLock.cs` — Feature F07)**:
   - Implemented `EnforceRefreshRate360Hz(string targetDevicePath = null)`, `Enforce360Hz(bool force = false)`, `CheckAndEnforce(...)`, `QueryActiveDisplayPaths()`, `ShouldRestore360Hz(double)`, `GetCurrentRefreshRateHz()`, and `EnforceViaDevModeFallback(...)`.
   - Enforces exact hardware rational `360152 / 1000` (`360.152 Hz`) with native pixel clock (`839010000`) and horizontal sync (`839010000 / 2080`) on internal panel `AUOAA9F` via `SetDisplayConfig` with `SDC_ENFORCE_FLAGS = 0x000006A0` (`SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES`), multi-tier retry (`0x000004A0` and path-level mode resolution), and `ChangeDisplaySettingsExW` (`dmDisplayFrequency = 360`) fallback.
   - Stands down cleanly in `< 1ms` when the internal panel is already locked at `>= 300.0 Hz` (`360.152 Hz`).

3. **Multi-Topology Registry DPI Sync & Dynamic CCD 125% DPI Enforcement (`src/Daemon/ScalingSynchronizer.cs` — Features F08 & F09)**:
   - Implemented `EnforceDisplayScaling125()`, `Enforce125(bool forceCcdSet = false)`, `CheckAndEnforce(bool forceCcdSet = false)`, `SynchronizeRegistryTopologies(...)`, `EnforceCcdDpiScale125(...)`, `IsInternalPanelTopologyKey(string)`, `ParseRegistryDwordToSignedInt32(...)`, `MapRelativeStepToPercent(...)`, and `GetCurrentScalingPercent()` / `GetActiveScalePercent()`.
   - Synchronizes `HKCU\Control Panel\Desktop\LogPixels = 120` (125% system base) and all `PerMonitorSettings\*AUOAA9F*` topology subkeys (`8086_A78B`, `10DE_28E0`, and fallback `MSNILAUOAA9F0`) to `DpiValue = 0` (`RegistryValueKind.DWord`) across `HKCU` and loaded `HKEY_USERS` `S-1-5-21-*` hives while isolating external displays.
   - Dynamically enforces `scaleRel = 0` (125% Recommended) on active internal panel CCD paths via `DisplayConfigSetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`) followed by a post-CCD registry verification pass.

4. **M2 Reviewer Edge-Case Mitigations (`src/Daemon/GhostEvictionEngine.cs`)**:
   - Added `m.IsInternalPanel` guard to the NVIDIA parent fallback check (`m.IsNvidiaActive || (m.IsInternalPanel && m.ParentDeviceId != null && ...)`), preventing false eviction of the internal Intel panel if an external monitor is connected to the NVIDIA dGPU in Optimus mode (`Reviewer M2_1 Finding 1`).
   - Added dynamic `EnumerateMonitors(presentOnly: false)` fallback before literal `DefaultIntelGhostInstanceId` lookup (`Reviewer M2_2 Caveat 3`).
   - Verified `CM_Enable_DevNode` return value `crEnable == Interop.CR_SUCCESS` with a 25ms single retry before reporting `EvictedCount = 1` (`Reviewer M2_1 Finding 2`).

5. **Unified 3-Stage Reconfiguration Pipeline (`src/Daemon/EventWindow.cs`)**:
   - Implemented `EventWindow.ExecuteReconfigurationPipeline(string triggerReason)` executing:
     - **Step 1**: `GhostEvictionEngine.CheckAndEvict()`
     - **Step 2**: `RefreshRateLock.Enforce360Hz()`
     - **Step 3**: `ScalingSynchronizer.Enforce125()`
   - Each stage is isolated in its own `try/catch` block and timed with `Stopwatch`. Total steady-state execution time measured at `~2.07ms` (well within the `< 100ms` budget).
   - Preserves `OnReconfigurationTriggered` event dispatch for M2 adversarial test compatibility without duplicate execution.

6. **CLI & Lifecycle Enhancements (`src/Daemon/Program.cs`)**:
   - Added `--lock-360hz` and `--sync-dpi` CLI commands.
   - Updated `--status` to filter out the current CLI process PID (`Reviewer M2_1 Finding 4` & `Reviewer M2_2 Caveat 1`) and report `Refresh Rate (Hz): 360 Hz` and `Display Scaling (%): 125%`.

---

## 2. Live Remediation & Verification Results

1. **Zero-Warning Native Compilation (`.\build.ps1`)**:
   - Compiled all 6 source files in `src/Daemon/` using 64-bit `csc.exe` (`/nologo /platform:x64 /warn:4 /optimize+`) in `136ms` with exit code `0`, zero errors, and zero warnings (`bin\DisplayFixDaemon.exe`, 72 KB).

2. **Live `DEFECT-F08-DPI-DESYNC` Remediation (`--sync-dpi`, `--lock-360hz`, `--status`)**:
   - Running `.\bin\DisplayFixDaemon.exe --sync-dpi` detected and remediated the live registry desync on both `AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101^...` and `MSNILAUOAA9F0_01_07E6_5E_1414_008D_FFFFFFFF_FFFFFFFF_0^...` from `-1 (0xFFFFFFFF)` to `0 (125% recommended)` and enforced `scaleRel = 0` via CCD `DisplayConfigSetDeviceInfo` (`rc = 0`, exit code `0`).
   - Running `.\bin\DisplayFixDaemon.exe --lock-360hz` verified `360152/1000 (360.152Hz)` on `\\.\DISPLAY5` in `3.96ms` (exit code `0`).
   - Running `.\bin\DisplayFixDaemon.exe --status` reported `Refresh Rate (Hz): 360 Hz`, `Display Scaling (%): 125%`, and `Process Running: False (Count: 0)` (exit code `0`).

3. **E2E & Adversarial Test Suite Results**:
   - `tests/e2e/test_runner.ps1 -Filter "f04|f05|f06|f07|f08|f09|b02|b03|b04|c01|c02|c04"`: **57 / 57 tests PASSED** across 12 suites (`0` failed, `0` skipped).
   - `tests/e2e/tier5_adversarial/adversarial_m2_eviction_event_test.ps1`: **16 / 16 tests PASSED** (`Final Gate Verdict: APPROVE`).
   - `tests/e2e/tier5_adversarial/adversarial_m2_lifecycle.ps1`: **12 / 12 tests PASSED** (`Final Verdict: APPROVE`).
