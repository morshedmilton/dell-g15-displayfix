# BRIEFING — 2026-11-05T10:47:00Z

## Mission
Investigate repository structure, language, architecture, existing daemons/services/scripts, system environment telemetry (active GPUs, monitors, drivers, scaling, refresh rate), and identify root causes of DWM/switching/scaling/brightness issues on Dell G15.

## 🔒 My Identity
- Archetype: Explorer
- Roles: Codebase & Telemetry Explorer
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_repo\
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: Exploration & Telemetry Analysis

## 🔒 Key Constraints
- Read-only investigation — do NOT implement or modify source code or system configurations
- Write detailed findings to survey_repo_analysis.md
- Write complete handoff report to handoff.md
- Send completion message to parent upon finishing with summary and artifact paths

## Current Parent
- Conversation ID: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Updated: 2026-11-05T10:47:00Z

## Investigation State
- **Explored paths**: Entire workspace root (`src/`, `bin/`, `docs/`, `build.ps1`, `install.ps1`, `uninstall.ps1`, `README.md`, `CHANGELOG.md`), Git history (`v1.0.0` to `v1.3.0`), system telemetry (WMI/CIM, PnP, Win32 QDC display paths, DPI scaling, scheduled tasks, running processes, Windows Event Logs).
- **Key findings**:
  1. Excessive latency: PhantomGuard polls every 8s and sleeps 11s, causing 27-35s of DWM lag and input stutter.
  2. Destructive adapter reset: `pnputil /disable-device` on Intel GPU causes display blinks, alt-tabs games, and triggers DWM DirectX device removal/leaks.
  3. Refresh rate: 360Hz refresh rate is completely unmanaged and absent from the codebase.
  4. Display scaling: 125% scaling is completely unmanaged; `PerMonitorSettings` desynchronization between Intel and NVIDIA paths causes 100% fallback and blurry text.
  5. Hotkeys: Out-of-the-box F6/F7 brightness keys are completely non-functional due to empty `hotkeys.ini` (v1.2.0 regression).
  6. Reusable assets: NVIDIA WMI `NvGetSetBrightnessLevel` logic with +8 write offset, 10% safety floor, scheduled task elevated token pattern, and zero-dependency `csc.exe` build script.
- **Unexplored areas**: None within the exploration scope.

## Key Decisions Made
- Recommend a clean, unified modern rebuild (`DisplayFixDaemon`) incorporating:
  1. Event-driven `WM_DISPLAYCHANGE` listener ($< 100$ ms reaction time)
  2. Non-disruptive `SetDisplayConfig` path unbinding without PCIe adapter restarts
  3. Automatic 360Hz refresh rate preservation
  4. Automatic 125% DPI scale synchronization across all monitor paths
  5. Active out-of-the-box F6/F7 brightness hotkeys with low-level keyboard hooks, consumer HID handling, and an on-screen display (OSD) overlay.

## Artifact Index
- `DISPATCH.md` — Incoming dispatch log
- `progress.md` — Liveness heartbeat
- `telemetry_probe.ps1` — Win32/WMI live telemetry probe script
- `probe_wmi.ps1` — WMI and NvBrightness provider privilege test script
- `query_paths.ps1` — QDC path and monitor topology probe script
- `survey_repo_analysis.md` — Comprehensive analysis of codebase, telemetry, root causes, and recommendations
- `handoff.md` — Complete 5-component handoff report
