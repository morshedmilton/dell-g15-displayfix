# Handoff Report: Explorer M3_2 — Multi-Topology Registry DPI Sync & Dynamic CCD 125% DPI Enforcement

## Status: COMPLETED

## Deliverables Produced
1. **Design Blueprint:** `.agents/teamwork/explorer_m3_2/scaling_sync_design.md`
2. **Empirical CCD DPI Verification Script:** `.agents/teamwork/explorer_m3_2/probe_ccd_dpi.ps1`
3. **Handoff Summary:** `.agents/teamwork/explorer_m3_2/handoff.md`
4. **Progress Log:** `.agents/teamwork/explorer_m3_2/progress.md`

---

## Key Empirical Findings

### 1. Root Cause of `DEFECT-F08-DPI-DESYNC` Confirmed in Live Registry
Direct query of `HKCU:\Control Panel\Desktop\PerMonitorSettings` on the target Dell G15 5530 revealed 4 internal panel subkeys matching `*AUOAA9F*`:
- `AUOAA9F0_01_07E6_5E^6ABFF6B3F25020EA5A6C25291E1D582D` $\rightarrow$ `DpiValue = 0` (125%)
- `AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050^...` (Intel UHD) $\rightarrow$ `DpiValue = 0` (125%)
- `AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101^...` (NVIDIA RTX 4060) $\rightarrow$ `DpiValue = 4294967295` (`-1`, 100%)
- `MSNILAUOAA9F0_01_07E6_5E_1414_008D_FFFFFFFF_FFFFFFFF_0^...` (Basic Display) $\rightarrow$ `DpiValue = 4294967295` (`-1`, 100%)

Because both `10DE_28E0` and `MSNILAUOAA9F0` store `4294967295` (`0xFFFFFFFF` / `-1`), Test F08.4 and Test F08.5 currently fail until `ScalingSynchronizer.SynchronizeRegistryTopologies` overwrites all `*AUOAA9F*` subkeys with `DpiValue = 0` (`RegistryValueKind.DWord`).

### 2. Live CCD DPI Scaling API Verification (`DisplayConfigGetDeviceInfo` / `DisplayConfigSetDeviceInfo`)
- Verified in C# against `user32.dll` (`probe_ccd_dpi.ps1`):
  - `DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3` (`DISPLAYCONFIG_SOURCE_DPI_SCALE_GET`, `size = 32` bytes) returns `rc = 0`, `minScaleRel = -2`, `curScaleRel = 0`, `maxScaleRel = 1`.
  - `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4` (`DISPLAYCONFIG_SOURCE_DPI_SCALE_SET`, `size = 24` bytes, `scaleRel = 0`) returns `rc = 0` (`ERROR_SUCCESS`).
  - `DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2` (`DISPLAYCONFIG_TARGET_DEVICE_NAME`, `size = 420` bytes) resolves `\\?\DISPLAY#AUOAA9F#5&39808dae&2&UID4353#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}` to isolate the internal panel from external displays.
- **Crucial Pitfall Identified:** Calling `DisplayConfigSetDeviceInfo` only modifies the *currently active* CCD display path in DWM and does not overwrite inactive topology keys in `PerMonitorSettings`. Thus, `ScalingSynchronizer.CheckAndEnforce` executes a 3-stage pipeline:
  1. Pre-CCD multi-topology registry sync (`LogPixels = 120` + all `*AUOAA9F*` subkeys `DpiValue = 0` + root `PerMonitorSettings` `DpiValue = 0` if present, across `HKCU` and loaded `HKEY_USERS` `S-1-5-21-*` hives).
  2. Dynamic CCD enforcement (`DisplayConfigGetDeviceInfo(-3)` + `DisplayConfigSetDeviceInfo(-4, scaleRel = 0)`).
  3. Post-CCD registry verification pass to ensure any OS registry updates leave all `*AUOAA9F*` keys at `DpiValue = 0`.

---

## Implementation Guidance for Milestone 3 Worker
1. **Add CCD & DPI P/Invoke definitions to `src/Daemon/Interop.cs`** from Section 3 of `scaling_sync_design.md`.
2. **Create `src/Daemon/ScalingSynchronizer.cs`** using the full C# 5 compatible source code in Section 4 of `scaling_sync_design.md`.
3. **Wire into `Program.cs` & `EventWindow.cs`:**
   - Call `ScalingSynchronizer.CheckAndEnforce(forceCcdSet: false)` in the `OnReconfigurationTriggered` pipeline (after `GhostEvictionEngine.CheckAndEvict()` and `RefreshRateLock.Enforce360Hz()`).
   - Add `--sync-dpi` CLI handler in `Program.cs` calling `ScalingSynchronizer.CheckAndEnforce(forceCcdSet: true)`.
   - Include `ScalingSynchronizer.GetActiveScalePercent()` in `--status` telemetry output.
