## 2026-11-05T13:03:17Z
You are Explorer M3_2 investigating and designing the Multi-Topology Registry DPI Sync and Dynamic CCD 125% DPI Enforcement Engine for Milestone 3.

Working directory: .agents/teamwork/explorer_m3_2/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f08_registry_dpi_sync.ps1
4. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f09_ccd_dpi_enforcement.ps1
5. Existing source code in `src/Daemon/`.

Objectives:
1. Design `src/Daemon/ScalingSynchronizer.cs` & required P/Invoke in `Interop.cs`:
   - Feature F08: Multi-Topology Registry DPI Sync:
     - Check and synchronize `HKCU:\Control Panel\Desktop\LogPixels` = 120 (125% scale base).
     - Enumerate all subkeys under `HKCU:\Control Panel\Desktop\PerMonitorSettings` matching `*AUOAA9F*` (including Intel `8086*A78B` and NVIDIA `10DE*28E0`).
     - Set `DpiValue = 0` (DWORD) across all matching topologies, resolving the known defect `DEFECT-F08-DPI-DESYNC` where NVIDIA path had `DpiValue = 4294967295` (-1, 100%).
     - Also set `DpiValue = 0` on `HKCU:\Control Panel\Desktop\PerMonitorSettings` root if applicable.
   - Feature F09: Dynamic CCD 125% DPI Enforcement:
     - CCD API: `DisplayConfigSetDeviceInfo` / `DisplayConfigGetDeviceInfo`.
     - Request codes: `DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3`, `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`.
     - Struct `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET`: Header (20 bytes: type, size, adapterId, id) + scaleRel (4 bytes: int32) = 24 bytes (verified by test F09.3).
     - Relative scale mapping: `scaleRel = 0` corresponds to 125% (native recommended scale, verified by test F09.2).
     - Apply dynamically without logoff or reboot.
2. Ensure strict C# 5 syntax compatibility (no string interpolation) for native `csc.exe` on .NET 4.8 x64.
3. Provide a complete, compilable blueprint for `ScalingSynchronizer.cs` and new P/Invoke definitions for `Interop.cs`.

Deliverables:
- Write design blueprint to `.agents/teamwork/explorer_m3_2/scaling_sync_design.md`
- Write handoff to `.agents/teamwork/explorer_m3_2/handoff.md`
- Send completion message back via send_message.
