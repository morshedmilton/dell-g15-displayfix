# Handoff Report: Codebase & Telemetry Exploration

**Agent:** Explorer 1 (Codebase & Telemetry Explorer)  
**Parent:** `1fa2c640-1687-4d63-a802-a810e6d0f6c0`  
**Working Directory:** `c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_repo\`  
**Target Artifact:** `survey_repo_analysis.md`

---

## 1. Observation

1. **Repository Layout and Toolchain:**
   - Workspace root contains: `src/PhantomGuard.cs` (468 lines), `src/NvBrightness.cs` (834 lines), `bin/PhantomGuard.exe` (12.8 KB), `bin/NvBrightness.exe` (22.5 KB), `build.ps1`, `install.ps1`, `uninstall.ps1`, `docs/problem.md`, `README.md`, `CHANGELOG.md`.
   - Toolchain uses Windows built-in `csc.exe` (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`) targeting .NET Framework 4.8 x64 (`build.ps1:9-32`).
   - Git commit history traces versions from `v1.0.0` (commit `5a70116`) to `v1.3.0` (commit `ef30fe0`).

2. **System Environment & Live Telemetry:**
   - Machine: Dell G15 5530, BIOS 1.36.0 (2026-08-26), Windows 11 Pro 64-bit Build 26300.
   - Active GPUs:
     - Intel(R) UHD Graphics (`PCI\VEN_8086&DEV_A78B...`, Driver `32.0.101.7088`).
     - NVIDIA GeForce RTX 4060 Laptop GPU (`PCI\VEN_10DE&DEV_28E0...`, Driver `32.0.16.2101`).
   - Active Display: Currently attached to `\\.\DISPLAY5` (RTX 4060 dGPU), mode: `1920x1080 @ 360.15 Hz`, 32 bpp, device path `\\?\DISPLAY#AUOAA9F#5&39808dae&2&UID4353#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}`.
   - PnP Monitor instances: `DISPLAY\AUOAA9F\5&39808DAE&2&UID4353` is `OK`; `DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688` is `Unknown` / `CM_PROB_PHANTOM`.
   - DWM Process (PID 2332): Handles: 1936, WorkingSet: ~126 MB, PrivateMemory: ~287 MB.

3. **Display Scaling Telemetry:**
   - `HKCU:\Control Panel\Desktop\LogPixels` is `120` (125%).
   - `HKCU:\Control Panel\Desktop\WindowMetrics\AppliedDPI` is `120`.
   - In `HKCU:\Control Panel\Desktop\PerMonitorSettings`:
     - `AUOAA9F0..._10DE_28E0...`: `DpiValue = 4294967295` (-1 / Unset).
     - `AUOAA9F0..._8086_A78B...`: `DpiValue = 0` (100%).
   - Win32 API `GetDpiForSystem()` reports `96 (100%)`.

4. **Brightness & Hotkeys State:**
   - `root\wmi:NvWmiBrightness` exists, but access is denied to unelevated tokens (HRESULT `0x80041003`). When called elevated via task `DisplayFixBrightness`, `NvGetSetBrightnessLevel` succeeds with `apply -> True backend=NVIDIA` (`C:\ProgramData\DisplayFix\logs\app.log`).
   - `C:\ProgramData\DisplayFix\hotkeys.ini` lines 1-13 are completely commented out by default (commit `80b091e`).
   - `src/NvBrightness.cs:33-34` defines `HotkeyF6` and `HotkeyF7` but never registers them; keys are only registered if defined in `hotkeys.ini`. Because `hotkeys.ini` is empty, plain F6/F7 hotkeys do not function out-of-the-box.
   - When configured, `RegisterHotKey(Handle, id, 0, vk)` claims `VK_F6` and `VK_F7` globally with no application passthrough (`src/NvBrightness.cs:648-651`).

5. **Detection & Repair Mechanics in PhantomGuard:**
   - `PollMs = 8000`, `Confirmations = 2` (`src/PhantomGuard.cs:38-39`). Total latency before repair: 16–24 seconds.
   - `Repair()` calls `pnputil.exe /disable-device` on the Intel adapter, sleeps 4000 ms, calls `pnputil.exe /enable-device`, sleeps 7000 ms (`src/PhantomGuard.cs:272-286`). Total repair duration: 11+ seconds. Total episode latency: 27–35 seconds.

---

## 2. Logic Chain

1. From Observation 5 (`PhantomGuard.cs` 8s poll, 2 confirmations, 11s sleep) $\rightarrow$ Any display mux switch leaves DWM rendering two surfaces for 16 to 24 seconds before `Repair()` begins. During this window, DWM CPU sits at 30%–50% with 1-second input stalls, as measured in `docs/problem.md`.
2. From Observation 5 (`pnputil /disable-device` on Intel PCIe display adapter) $\rightarrow$ Disabling the GPU adapter triggers an abrupt `DXGI_ERROR_DEVICE_REMOVED` across all active DWM DirectX swapchains, causing display blinking and focus loss in fullscreen 3D applications. Under repeated switching stress (up to 100 switches), DWM's device recovery loop leaks GDI and DirectX handles, escalating into DWM crashes or driver TDR resets.
3. From Observation 1 & 2 $\rightarrow$ There is zero code in the repository that reads or enforces refresh rate. When switching to Optimus or when the Intel adapter re-enumerates, the Intel driver is susceptible to falling back to default 60Hz.
4. From Observation 3 (registry conflict between `LogPixels = 120` and `PerMonitorSettings DpiValue = 0` / `-1`) $\rightarrow$ When Windows transitions between Intel (`8086_A78B`) and NVIDIA (`10DE_28E0`) display paths, Windows reads the per-monitor DPI setting for that path. Because they are not synchronized, Windows falls back to 100% or switches scaling dynamically, producing blurry text in non-Per-Monitor-v2 applications.
5. From Observation 4 (`hotkeys.ini` empty, `DefaultHotkeys` commented out, `RegisterHotKey` global swallow) $\rightarrow$ Plain F6 and F7 brightness controls are dead out-of-the-box in NVIDIA GPU Only mode. When manually added to `hotkeys.ini`, they swallow F6/F7 system-wide, breaking native game controls and function keys.
6. From Observation 4 (`root\wmi:NvWmiBrightness` working when elevated with +8 write offset and 10% floor) $\rightarrow$ The core NVIDIA WMI write logic and scheduled task elevated token pattern are valid and verified.

---

## 3. Caveats

- Investigation was strictly read-only; no code was modified, no drivers were toggled, and no display switches were forced during this phase.
- Active display mode was investigated while currently muxed to the NVIDIA dGPU (Advanced Optimus / NVIDIA GPU Only). Behavior under pure Optimus was inferred from code, commit history, and recorded logs in `docs/problem.md` and `guard.log`.
- Internal Dell EC firmware communication (Fn-lock toggling via Fn+Esc) happens at the hardware/ACPI level; user-mode software receives plain `VK_F6`/`VK_F7` keystrokes when Fn-lock is enabled, and ACPI/HID consumer control signals when Fn-lock is in media mode.

---

## 4. Conclusion

The existing `dell-g15-displayfix` codebase proved the feasibility of fixing the Dell G15 5530 defect, but its current implementation is a slow, disruptive workaround that fails the user's requirements:
- **Display Switching & DWM Stability:** Fails due to 16–30s detection latency and destructive `pnputil` adapter resets that induce DWM device loss and handle leaks.
- **360Hz Refresh Rate:** Completely unmanaged.
- **Persistent 125% Scaling:** Completely unmanaged; registry desync causes 100% fallback and blurry text.
- **F6/F7 Hotkeys:** Inactive out-of-the-box due to empty `hotkeys.ini` and prone to swallowing keys system-wide.

**Recommendation:** A clean, unified architectural rebuild (`DisplayFixDaemon`) is necessary.
- **Event-Driven:** Replace 8s polling with instant `WM_DISPLAYCHANGE` / `WM_DEVICECHANGE` listeners ($< 100$ ms response).
- **Non-Disruptive Path Removal:** Use `SetDisplayConfig` to cleanly deactivate the stale Intel path without restarting the PCIe GPU adapter.
- **Refresh Rate Watcher:** Enforce 360Hz automatically after every display change.
- **DPI Synchronizer:** Synchronize `PerMonitorSettings` and call `DisplayConfigSetDeviceInfo` to enforce 125% DPI scale across both GPU paths.
- **Modern Hotkey Engine:** Provide out-of-the-box F6/F7 brightness control with low-level keyboard hooks, consumer HID listener, and an on-screen display (OSD) feedback overlay.

---

## 5. Verification Method

1. **Verify Codebase & Commit State:**
   ```powershell
   git status
   git log -n 5 --oneline
   ```
2. **Verify Telemetry & Running Tasks:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .agents\teamwork\explorer_repo\telemetry_probe.ps1
   ```
   Confirm active GPU, 360Hz refresh rate, active path ID, and running status of `DisplayFixGuard` and `DisplayFixBrightness`.
3. **Verify WMI Brightness Provider Privileges:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .agents\teamwork\explorer_repo\probe_wmi.ps1
   ```
   Confirm unelevated query returns Access Denied (`0x80041003`) while elevated task logs (`C:\ProgramData\DisplayFix\logs\app.log`) confirm successful writes.
4. **Inspect Detailed Analysis:**
   Inspect `c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_repo\survey_repo_analysis.md`.
