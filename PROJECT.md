# Project: Dell G15 5530 DisplayFix

## Architecture

The solution resolves Dell G15 5530 display switching lag, ghost monitor presentation stalls, 360Hz refresh rate resets, F6/F7 brightness hotkey failures in NVIDIA GPU Only mode, and display scaling desynchronization.

The architecture centers on a high-performance, event-driven Windows resident application (`DisplayFixDaemon.exe`) built in C# targeting .NET Framework 4.8 x64 (using the native `csc.exe` toolchain without external package dependencies), executed with elevated credentials (`RunLevel: HighestAvailable`) via a Windows Task Scheduler logon task.

### Core Architectural Components:
1. **Event Dispatcher & Window Pump**: Listens for `WM_DISPLAYCHANGE` and `RegisterDeviceNotification` (`GUID_DEVINTERFACE_MONITOR` and `GUID_DEVINTERFACE_DISPLAY_ADAPTER`) to react instantaneously (<100ms) to Advanced Optimus / Dynamic Display Switching (DDS) hardware multiplexer events.
2. **Ghost Monitor Eviction Engine**: Detects disconnected Intel eDP monitor nodes (`UID8388688`) when the panel is routed to the RTX 4060 dGPU, recycling the device node via native CfgMgr32 / SetupAPI in <500ms to eliminate DWM 30–50% CPU load and presentation stalls without disruptive child process spawning.
3. **360Hz Refresh Rate Lock Engine**: Queries supported modes for the AU Optronics `AUO AA9F` internal panel and enforces the exact native rational `refreshRateNumerator = 360152`, `refreshRateDenominator = 1000` via Windows CCD `SetDisplayConfig` with `SDC_APPLY | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES`.
4. **Persistent 125% DPI Scaling Engine**: Synchronizes `PerMonitorSettings` registry trees across both GPU topologies (`8086_A78B` and `10DE_28E0`) to `DpiValue = 0` (125%) and dynamically invokes `DisplayConfigSetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE`) to lock 125% scaling synchronously with zero font blur and no logoff/reboot.
5. **Brightness Hotkey & OSD Engine**: In Function Key mode (`Fn + Esc`), captures `VK_F6` (decrease) and `VK_F7` (increase) via low-level keyboard hook (`WH_KEYBOARD_LL`), routes adjustments to `root\wmi:NvWmiBrightness` (with +8 offset and 10% floor) in NVIDIA mode and `WmiMonitorBrightnessMethods` in Optimus mode, renders a smooth non-activating acrylic On-Screen Display (OSD), and preserves standard media key passthrough (F1-F3, F9).
6. **Telemetry & Verification Subsystem**: Automated diagnostic tooling capturing active GPU, display paths, refresh rate, DPI scaling, DWM memory/handle telemetry, and 100-switch stress validation against TDR resets (`Event ID 4101`) or DWM crashes (`Event ID 1000`).

---

## Feature Inventory

Every feature from the Phase 0 Survey is inventoried below and mapped to a specific implementation milestone:

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F01 | Real-time System Telemetry Probe | PowerShell/C# diagnostic prober reporting active GPU, display paths, refresh rate, DPI scaling, and DWM health | M1 | survey_repo / survey_spec |
| F02 | DWM Health & Stability Monitor | Automated monitor tracking GDI/USER objects (`GetGuiResources`), private working set, and Event IDs 1000/4101 | M1 | survey_spec |
| F03 | 100-Switch Stress Test Harness | Automated stress-testing harness simulating or tracking display switches, verifying DWM leak bounds | M1 | survey_spec |
| F04 | Sub-second Ghost Monitor Eviction | Event-driven eviction of unclocked Intel eDP monitor node on DDS switch via CfgMgr32, eliminating DWM 30-50% CPU stall | M2 | survey_repo / survey_spec |
| F05 | Zero-Lag Display Change Listener | Window message pump capturing `WM_DISPLAYCHANGE` and `WM_DEVICECHANGE` (<100ms response vs 16-30s polling) | M2 | survey_repo / survey_spec |
| F06 | Clean Lifecycle & Task Scheduler Setup | Elevated logon scheduled task (`RunLevel HighestAvailable`) and silent daemon execution with logging | M2 | survey_repo |
| F07 | Native 360Hz Refresh Rate Lock | Programmatic enforcement of 360.152Hz (360152/1000) via CCD `SetDisplayConfig` with `SDC_SAVE_TO_DATABASE` | M3 | survey_spec |
| F08 | Multi-Topology Registry DPI Sync | Synchronizing `PerMonitorSettings` registry keys across Intel and NVIDIA AUO AA9F paths to `DpiValue = 0` (125%) | M3 | survey_brightness_scaling |
| F09 | Dynamic CCD 125% DPI Enforcement | Calling `DisplayConfigSetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE`) on switch for crisp, non-blurry 125% scaling | M3 | survey_brightness_scaling |
| F10 | F6/F7 Hotkey Interception | Low-level keyboard hook capturing `VK_F6` (down) and `VK_F7` (up) out-of-the-box without requiring Fn key | M4 | survey_brightness_scaling |
| F11 | NVIDIA WMI Brightness Backend | Elevated `root\wmi:NvWmiBrightness` controller with +8 offset calibration and 10% safety floor | M4 | survey_brightness_scaling |
| F12 | Optimus WMI Brightness Backend | `root\wmi:WmiMonitorBrightnessMethods` fallback controller for Optimus / iGPU mode | M4 | survey_brightness_scaling |
| F13 | Function Row Media Key Preservation | Pass-through / remapping of F1-F3 (Mute/Vol) and F9 (Play/Pause) so standard controls remain functional | M4 | survey_brightness_scaling |
| F14 | Non-Activating Acrylic OSD Overlay | Lightweight layered acrylic OSD window displaying brightness percentage bar without stealing focus | M4 | survey_brightness_scaling |
| F15 | Physical Verification Guide | Clear step-by-step instructions for physical testing of display switching, 360Hz, scaling, and brightness keys | M5 | ORIGINAL_REQUEST §R5 |
| F16 | 100% E2E Test Suite Acceptance | Passing all Tier 1-4 tests published in TEST_READY.md and passing Tier 5 adversarial coverage hardening | M5 | Project Pattern |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Diagnostics, Telemetry & Stress Harness | Implement system telemetry probe (`diagnose.ps1`), DWM health prober (`dwm_health.ps1`), and stress test harness (`stress_test.ps1`) | none | DONE |
| M2 | Core Daemon & Ghost Monitor Eviction Engine | Implement `DisplayFixDaemon` event loop (`WM_DISPLAYCHANGE`), in-process CfgMgr32 ghost eviction (<500ms lag), task scheduler install script | M1 | DONE |
| M3 | 360Hz Refresh Rate Lock & Persistent 125% DPI Scaling | Implement CCD 360Hz enforcement (`SetDisplayConfig` with rational 360152/1000) and DPI synchronizer (`DisplayConfigSetDeviceInfo` + registry sync) | M2 | DONE |
| M4 | F6/F7 Brightness Hotkey Engine & Acrylic OSD | Implement low-level hook for F6/F7, dual WMI brightness backend (NvWmiBrightness + WmiMonitorBrightness), acrylic OSD, media key preservation | M2, M3 | DONE |
| M5 | Final Milestone: 100% E2E Test Suite Pass & Adversarial Hardening | Verify all acceptance criteria, pass 100% of E2E test suite (Tiers 1-4), execute Tier 5 adversarial hardening, deliver verification guide | M1, M2, M3, M4 | DONE |

---

## Interface Contracts

### 1. `DisplayFixDaemon` Event Loop ↔ Ghost Eviction Engine
- **Trigger**: Window Message `WM_DISPLAYCHANGE` (0x007E) or `WM_DEVICECHANGE` (0x0219).
- **Function**: `int EvictGhostMonitors()`
- **Behavior**: Scans PnP devices under class `Monitor`. If `AUOAA9F` is present on both NVIDIA and Intel paths, invokes `CM_Disable_DevNode` then `CM_Enable_DevNode` on Intel device instance `PCI\VEN_8086&DEV_A78B...`.
- **Return**: Number of ghost paths successfully evicted (0 or 1). Latency target: < 500ms.

### 2. `DisplayFixDaemon` ↔ 360Hz Refresh Rate Lock
- **Function**: `bool EnforceRefreshRate360Hz(string targetDevicePath)`
- **CCD API**: `SetDisplayConfig`
  - Flags: `SDC_APPLY | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES | SDC_USE_SUPPLIED_DISPLAY_CONFIG`
  - Rational: `Numerator = 360152`, `Denominator = 1000`
- **Fallback**: `ChangeDisplaySettingsEx` with `DEVMODE` `dmDisplayFrequency = 360`.

### 3. `DisplayFixDaemon` ↔ Persistent 125% Display Scaling
- **Function**: `bool EnforceDisplayScaling125()`
- **Registry Synchronization**:
  - Keys: `HKCU:\Control Panel\Desktop\PerMonitorSettings\<AUOAA9F_*>`
  - Value: `DpiValue = 0` (DWORD) for both `10DE_28E0` and `8086_A78B` branches.
  - Value: `LogPixels = 120` in `HKCU:\Control Panel\Desktop`.
- **CCD API**: `DisplayConfigSetDeviceInfo`
  - Structure: `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE`
  - `scaleRel = 0` (Recommended scale = 125%).

### 4. `DisplayFixDaemon` ↔ Brightness Engine & OSD
- **Input**: Low-level keyboard hook callback `LowLevelKeyboardProc` capturing `VK_F6` (0x75) and `VK_F7` (0x76).
- **Backend Selection**:
  - If `Get-CimInstance root\wmi:NvWmiBrightness` accessible $\rightarrow$ write `NvGetSetBrightnessLevel` with +8 offset and clamp $[10, 100]$.
  - Else fallback $\rightarrow$ write `WmiMonitorBrightnessMethods.WmiSetBrightness(Timeout=1, Brightness=level)`.
- **OSD Interface**: `void ShowOsd(int brightnessPercent)`
  - Window Styles: `WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST`
  - Auto-dismiss after 1500ms.

### 5. Telemetry & Verification Harness ↔ System
- **Diagnostics Output**: `C:\ProgramData\DisplayFix\logs\telemetry.json`
- **Metrics Schema**:
  - `ActiveGpu`: string ("NVIDIA RTX 4060" / "Intel UHD")
  - `DisplayMode`: string ("NVIDIA GPU Only" / "Optimus" / "Automatic")
  - `RefreshRateHz`: double (expected: 360.15)
  - `DpiScalePercent`: int (expected: 125)
  - `DwmWorkingSetMB`: double (< 250MB)
  - `DwmHandleCount`: int (< 2500)
  - `TdrEventCount`: int (expected: 0)
  - `DwmCrashCount`: int (expected: 0)

---

## Code Layout

```
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\
├── src/
│   ├── Daemon/
│   │   ├── Program.cs                  # Main entry point, single-instance mutex, service loop
│   │   ├── EventWindow.cs              # Invisible message-only window (WM_DISPLAYCHANGE, WM_DEVICECHANGE)
│   │   ├── GhostEvictionEngine.cs      # CfgMgr32 / PnP devnode cycling (<500ms)
│   │   ├── RefreshRateLock.cs          # CCD SetDisplayConfig 360.152Hz enforcement
│   │   ├── ScalingSynchronizer.cs      # PerMonitorSettings registry sync & CCD DPI locking
│   │   └── Interop.cs                  # Win32, CCD, CfgMgr32, SetupAPI P/Invoke definitions
│   ├── Brightness/
│   │   ├── HotkeyHook.cs               # WH_KEYBOARD_LL hook for F6/F7 with media pass-through
│   │   ├── BrightnessController.cs     # Dual WMI backend (NvWmiBrightness + WmiMonitorBrightness)
│   │   └── AcrylicOsdWindow.cs         # Non-activating WPF / Win32 layered OSD overlay
│   └── Common/
│       ├── Logger.cs                   # High-performance rotating file logger
│       └── SystemTelemetry.cs          # Runtime state probe
├── scripts/
│   ├── build.ps1                       # csc.exe compiler script (zero dependencies)
│   ├── install.ps1                     # Installs elevated scheduled task at user logon
│   ├── uninstall.ps1                   # Unregisters task and cleans runtime binaries
│   ├── diagnostics/
│   │   ├── probe_system.ps1            # Comprehensive live telemetry report
│   │   ├── dwm_health.ps1              # DWM memory, handles, and Event Log checker
│   │   └── stress_test.ps1             # 100-switch simulation & stability verification
│   └── verify.ps1                      # Master acceptance validation runner
├── tests/
│   ├── e2e/
│   │   ├── test_runner.ps1             # Master E2E test harness
│   │   ├── tier1_features/             # Tier 1: Feature coverage tests (≥5 per feature)
│   │   ├── tier2_boundaries/           # Tier 2: Boundary & corner cases
│   │   ├── tier3_combinations/         # Tier 3: Pairwise cross-feature combinations
│   │   ├── tier4_scenarios/            # Tier 4: Real-world application workloads
│   │   └── tier5_adversarial/          # Tier 5: Adversarial edge cases & coverage hardening
├── docs/
│   ├── verification_guide.md           # Step-by-step physical and automated testing guide
│   └── architecture.md                 # Detailed design & root cause analysis
└── bin/
    └── DisplayFixDaemon.exe            # Compiled standalone executable
```
