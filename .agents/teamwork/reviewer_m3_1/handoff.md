# Milestone 3 Code Review Report (`reviewer_m3_1` + `reviewer_m3_2`)

**Reviewer:** Reviewer M3_1 + M3_2  
**Date:** 2026-11-05  
**Milestone:** M3 — 360Hz Refresh Rate Lock & Persistent 125% DPI Scaling  
**Files Reviewed:**
- `src/Daemon/Interop.cs` (637 lines)
- `src/Daemon/RefreshRateLock.cs` (646 lines)
- `src/Daemon/ScalingSynchronizer.cs` (636 lines)
- `src/Daemon/GhostEvictionEngine.cs` (392 lines)
- `src/Daemon/EventWindow.cs` (502 lines)
- `src/Daemon/Program.cs` (629 lines)

**Final Verdict:** **APPROVE**

---

## 1. Executive Summary

The Milestone 3 implementation of `RefreshRateLock.cs` (Feature F07), `ScalingSynchronizer.cs` (Features F08 & F09), the unified Windows CCD/User32 interop layer (`Interop.cs`), the 3-stage reconfiguration pipeline (`EventWindow.cs`), and the M2 reviewer edge-case mitigations (`GhostEvictionEngine.cs`, `Program.cs`) is architecturally sound, memory-safe, thread-safe, and 100% compliant with `PROJECT.md` contracts and hardware specifications for the Dell G15 5530 (`AUOAA9F` 360.152Hz internal eDP panel).

---

## 2. Detailed Technical Review

### 2.1 Unmanaged Struct Layouts & P/Invoke Signatures (`src/Daemon/Interop.cs`)
All Windows CCD (`user32.dll`), User32 display settings, SetupAPI, and CfgMgr32 P/Invoke declarations and unmanaged struct layouts were verified via both static layout analysis and runtime `Marshal.SizeOf` reflection on x64 .NET Framework 4.8:

| Structure | Expected Size | Verified Runtime Size | Layout & Alignment Notes |
|-----------|---------------|-----------------------|--------------------------|
| `DISPLAYCONFIG_PATH_INFO` | 72 bytes | **72 bytes** | `sourceInfo` (20B) + `targetInfo` (48B) + `flags` (4B) = 72B (`Sequential`) |
| `DISPLAYCONFIG_MODE_INFO` | 64 bytes | **64 bytes** | `infoType` (4B) + `id` (4B) + `adapterId` (8B) + `modeInfo` union (48B, 8B aligned via `ulong pixelRate`) = 64B |
| `DISPLAYCONFIG_DEVICE_INFO_HEADER` | 20 bytes | **20 bytes** | `type` (4B) + `size` (4B) + `adapterId` (8B) + `id` (4B) = 20B |
| `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET` | 32 bytes | **32 bytes** | `header` (20B) + `minScaleRel` (4B) + `curScaleRel` (4B) + `maxScaleRel` (4B) = 32B (`type = -3`) |
| `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` | 24 bytes | **24 bytes** | `header` (20B) + `scaleRel` (4B) = 24B (`type = -4`) |
| `DEVMODEW` | 220 bytes | **220 bytes** | `CharSet.Unicode`, `ByValTStr` (`SizeConst = 32`) for `dmDeviceName` and `dmFormName`, exact 220B layout |

- Zero duplicate P/Invoke symbols exist across the 6 compilation units.
- Overloaded `DisplayConfigGetDeviceInfo` signatures cleanly type-specialize `DISPLAYCONFIG_SOURCE_DEVICE_NAME`, `DISPLAYCONFIG_TARGET_DEVICE_NAME`, `DISPLAYCONFIG_ADAPTER_NAME`, and `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET`.

### 2.2 360Hz Refresh Rate Lock Engine (`src/Daemon/RefreshRateLock.cs` — Feature F07)
- **Exact Hardware Rational & Signal Timing**: Enforces `TargetNumerator = 360152`, `TargetDenominator = 1000` (`360.152 Hz`) and populates `targetVideoSignalInfo.pixelRate = 839010000UL` and `hSyncFreq = 839010000 / 2080` when transitioning from 60Hz on 1920x1080 (`RefreshRateLock.cs:472-485`).
- **CCD Enforcement Flags & Multi-Tier Retry**:
  - Primary call uses `CcdEnforceFlags = 0x000006A0` (`SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES`, `Interop.cs:316`, `RefreshRateLock.cs:488`).
  - If running in a non-elevated context where `SDC_SAVE_TO_DATABASE` returns `ERROR_ACCESS_DENIED (5)`, retries automatically with `CcdEnforceFlagsNoSave = 0x000004A0` (`RefreshRateLock.cs:492-497`).
  - If the driver rejects explicit target mode signal modification (`rc != 0`), invalidates `targetInfo.modeInfoIdx = DISPLAYCONFIG_PATH_MODE_IDX_INVALID (0xFFFFFFFF)` so Windows CCD resolves the mode from the path-level rational (`RefreshRateLock.cs:501-511`).
- **Threshold Detection (`< 300Hz`)**: `ShouldRestore360Hz(double)` (`RefreshRateLock.cs:198-201`) accurately identifies fallback rates (`> 0.0 && < 300.0 Hz`) while standing down in `< 4ms` when the internal panel is already locked at `360.152 Hz` (`RefreshRateLock.cs:448-462`).
- **Secondary Fallback (`ChangeDisplaySettingsExW`)**: `EnforceViaDevModeFallback` (`RefreshRateLock.cs:578-642`) calls `EnumDisplaySettingsW(targetGdi, ENUM_CURRENT_SETTINGS, ref dm)` first to preserve resolution (`1920x1080`), bit depth, and flags, sets `dm.dmDisplayFrequency = 360` and `dm.dmFields |= DM_DISPLAYFREQUENCY`, and invokes `ChangeDisplaySettingsExW` with `CDS_UPDATEREGISTRY` (and `0` fallback).

### 2.3 Multi-Topology Registry DPI Sync & Dynamic CCD DPI Enforcement (`src/Daemon/ScalingSynchronizer.cs` — Features F08 & F09)
- **System Base DPI**: Sets `HKCU\Control Panel\Desktop\LogPixels = 120` (`RegistryValueKind.DWord`, 125% base scale) (`ScalingSynchronizer.cs:320-338`).
- **Multi-Topology `PerMonitorSettings` Synchronization**: Iterates all subkeys under `Control Panel\Desktop\PerMonitorSettings` across `Registry.CurrentUser` and loaded interactive user hives (`S-1-5-21-*` under `Registry.Users`), matching `*AUOAA9F*` (`8086_A78B`, `10DE_28E0`, base `AUOAA9F0`, and `MSNILAUOAA9F0`) and writing `DpiValue = 0` (`RegistryValueKind.DWord`) (`ScalingSynchronizer.cs:260-405`).
- **Signed/Unsigned DWORD Conversion**: `ParseRegistryDwordToSignedInt32` (`ScalingSynchronizer.cs:225-253`) safely converts `0xFFFFFFFF` (`4294967295`) to `-1` via `unchecked` / `BitConverter`, ensuring desynchronized `-1` (100%) topology entries are reliably detected and repaired to `0` (125%).
- **Foreign Monitor Isolation**: Both `IsInternalPanelTopologyKey` (`ScalingSynchronizer.cs:211-218`) in the registry pass and the `monitorDevicePath` check (`ScalingSynchronizer.cs:507-513`) in the CCD pass strictly skip non-`AUOAA9F` external monitors.
- **Dynamic CCD DPI Enforcement**: Queries `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET` (`type = -3`, `size = 32`) and enforces `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` (`type = -4`, `size = 24`, `scaleRel = 0`) on the active `AUOAA9F` source (`ScalingSynchronizer.cs:518-565`), followed by a post-CCD registry verification pass (`ScalingSynchronizer.cs:153-165`).

### 2.4 Unified 3-Stage Pipeline & M2 Reviewer Fixes (`EventWindow.cs`, `GhostEvictionEngine.cs`, `Program.cs`)
- **Unified Pipeline (`EventWindow.cs:351-419`)**: `ExecuteReconfigurationPipeline(string triggerReason)` is synchronized via `_pipelineExecutionLock` and executes:
  1. `GhostEvictionEngine.CheckAndEvict()`
  2. `RefreshRateLock.Enforce360Hz()`
  3. `ScalingSynchronizer.Enforce125()`
  Each stage has independent `Stopwatch` telemetry and `try/catch` isolation so an error in one stage never blocks subsequent stages. Total steady-state latency is `~24ms` (well below the `100ms` budget).
- **M2 Reviewer Mitigations Verified**:
  - `GhostEvictionEngine.cs:228`: Added `m.IsInternalPanel` guard to the `ParentDeviceId` NVIDIA fallback check so an external monitor attached to the RTX 4060 in Optimus mode never triggers false eviction of the internal Intel panel.
  - `GhostEvictionEngine.cs:254-266`: Added dynamic `EnumerateMonitors(presentOnly: false)` fallback before literal `DefaultIntelGhostInstanceId` lookup.
  - `GhostEvictionEngine.cs:350-380`: Verifies `crEnable == Interop.CR_SUCCESS` with a 25ms retry before setting `EvictedCount = 1`.
  - `Program.cs:267-278`: Filters out `Process.GetCurrentProcess().Id` in `HandleStatus()` so `--status` never counts its own short-lived CLI process as a running daemon instance.

---

## 3. Minor Observations (Non-Blocking)
- In `ScalingSynchronizer.GetActiveScalePercent()` (`ScalingSynchronizer.cs:600-609`), the quick status helper queries `paths[0]`. In a multi-monitor setup where an external display is path 0, filtering for `AUOAA9F` (as done in `EnforceCcdDpiScale125`) would be even more defensive, though on the laptop panel it works as expected.

## 4. Verdict
**APPROVE** — All Milestone 3 requirements, interface contracts, struct layouts, and M2 reviewer remediations are complete and verified.
