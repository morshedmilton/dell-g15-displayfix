# BRIEFING — 2026-11-05T10:47:15Z

## Mission
Investigate and document technical mechanisms and solutions for R2 (Brightness hotkey control) and R3 (Persistent 125% Display Scaling) on Dell G15 across Automatic, Optimus, and NVIDIA GPU Only modes.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_brightness_scaling
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: Initial exploration and technical deep dive for R2 & R3 completed

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT modify product source code or system configurations
- Write findings to survey_brightness_scaling.md and handoff.md in working directory
- Communicate completion back to parent via send_message

## Current Parent
- Conversation ID: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Updated: 2026-11-05T10:47:15Z

## Investigation State
- **Explored paths**:
  * `src/NvBrightness.cs` and `src/PhantomGuard.cs`
  * `docs/problem.md`, `README.md`, `CHANGELOG.md`
  * System registry: `HKCU:\Control Panel\Desktop`, `HKCU:\Control Panel\Desktop\PerMonitorSettings`
  * WMI namespaces: `root\wmi` (`WmiMonitorBrightnessMethods`, `NvWmiBrightness`), `root\dcim\sysman`
  * Win32 APIs: Connecting and Configuring Displays (CCD) `DisplayConfigGetDeviceInfo` / `DisplayConfigSetDeviceInfo` (flags -3/-4), Raw Input HID Consumer Usages, `RegisterHotKey`, `WH_KEYBOARD_LL`, DDC/CI `dxva2.dll`.
- **Key findings**:
  * In NVIDIA GPU Only mode, `WmiMonitorBrightness` is absent, and the native Windows slider is hidden. `root\wmi:NvWmiBrightness` is the only active hardware PWM backlight interface, requiring elevation (`RunLevel Highest`).
  * On AUO AA9F panel, NVIDIA driver has a +8 calibration offset on writes; writing < 10% causes screen blackout.
  * In Media mode, F6/F7 keypresses are swallowed by Dell EC into an ACPI dead-end. In Function mode (`Fn + Esc`), F6/F7 emit `VK_F6` (0x75) and `VK_F7` (0x76).
  * In current repo, function row hotkeys are commented out by default in `hotkeys.ini`.
  * Display scaling desync is caused by Windows treating Intel and NVIDIA paths as separate topologies. The NVIDIA topology key currently holds `DpiValue = 4294967295` (-1, 100%), reverting 125% scale upon switching.
  * Programmatic CCD API (`DisplayConfigSetDeviceInfo` with `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`) applies 125% scale instantly without logoff/reboot, preventing DWM bitmap stretch blur.
- **Unexplored areas**: None within the scope of R2 and R3.

## Key Decisions Made
- Recommended consolidating `PhantomGuard` and `NvBrightness` into a unified `DisplayFixDaemon` running as a scheduled task at logon (`RunLevel Highest`).
- Recommended hybrid hotkey router claiming `VK_F6`/`VK_F7` and restoring `VK_VOLUME_*` and media keys on F1-F3, F9.
- Designed a non-activating modern Acrylic OSD for clean visual feedback.
- Documented full programmatic CCD scaling enforcement and registry topology synchronization to lock 125% scaling.

## Artifact Index
- DISPATCH.md — Stored dispatch instruction
- progress.md — Heartbeat and status
- survey_brightness_scaling.md — Comprehensive technical investigation report for R2 & R3
- handoff.md — 5-component handoff report
