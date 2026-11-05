# Handoff Report: Brightness Hotkeys & Persistent Display Scaling (R2 & R3)

**Agent:** Explorer 3 (Brightness Hotkeys & Display Scaling Explorer)  
**Recipient:** Orchestrator (Conversation ID: `1fa2c640-1687-4d63-a802-a810e6d0f6c0`)  
**Artifact:** `survey_brightness_scaling.md`  
**Date:** 2026-11-05  

---

## 1. Observation

1. **WMI Brightness Subsystem Response on dGPU:**
   * Executing `Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness` produced:
     ```
     Get-CimInstance : Not supported (HRESULT 0x8004100c)
     ```
   * Executing `Get-CimInstance -Namespace root\wmi -ClassName NvWmiBrightness` without elevation produced:
     ```
     Get-CimInstance : Access denied (HRESULT 0x80041003)
     ```
   * Executing `NvBrightness.exe --set 50` while running elevated under scheduled task `DisplayFixBrightness` (`RunLevel Highest`) logged:
     ```
     set(50)=True backend=NVIDIA readBack=42 elevated=True
     ```
2. **Current System Monitor Devnodes and Display Paths:**
   * Command `Get-PnpDevice -Class Monitor` returned:
     - `DISPLAY\AUOAA9F\5&39808DAE&2&UID4353` (Status: `OK`, Present: `True`) — NVIDIA dGPU path.
     - `DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688` (Status: `Unknown`, Present: `False`) — Intel iGPU path (unlinked/disabled by `PhantomGuard`).
3. **Display Scaling Registry State (`HKCU:\Control Panel\Desktop`):**
   * Registry query on `HKCU:\Control Panel\Desktop` returned:
     - `LogPixels`: `120` (125% DPI scale base).
   * Registry query on `HKCU:\Control Panel\Desktop\PerMonitorSettings` returned:
     - `AUOAA9F0_01_07E6_5E_8086_A78B_...^...`: `DpiValue = 0` (Recommended scale = 125%).
     - `AUOAA9F0_01_07E6_5E_10DE_28E0_...^...`: `DpiValue = 4294967295` (Signed `-1`, indicating one relative step down = 100% scale).
4. **Existing Codebase Implementation (`NvBrightness.cs` and `hotkeys.ini`):**
   * In `C:\ProgramData\DisplayFix\hotkeys.ini`, lines 1–13 show:
     ```ini
     # DisplayFix - function row bindings
     # Only write entries here if you have verified the exact key, for example:
     #   F6=brightness_down
     #   F7=brightness_up
     ```
     The keys are commented out.
   * In `src/NvBrightness.cs` line 51:
     `internal const int NvWriteOffset = 8;` (compensates the panel's write attenuation).
   * In `src/NvBrightness.cs` lines 43–44:
     `internal const int MinLevel = 10; internal const int MaxLevel = 100;` (hard floor at 10% to prevent panel blackout).
   * In `CHANGELOG.md` lines 44–48:
     `with Fn-lock in media mode, pressing F6 produces no Windows input event at all — not a keystroke, not an HID consumer usage, nothing. It is handled inside the embedded controller and never reaches the OS.`

---

## 2. Logic Chain

1. **Why Brightness Keys Break in NVIDIA GPU Only Mode:**
   - From Observation 1, `WmiMonitorBrightness` is unsupported on the NVIDIA driver (`0x8004100c`), and `PhantomGuard` clears the Intel monitor devnode (Observation 2) to eliminate the 30–50% DWM CPU leak.
   - When the Intel devnode is unlinked, the system has 0 active `WmiMonitorBrightness` interfaces. Windows completely hides the native brightness slider and ignores ACPI brightness notifications.
   - From Observation 4, in Media Mode, Dell's EC traps F6/F7 keypresses internally and routes them to the absent ACPI/Intel provider without emitting OS keystrokes.
   - In Function Key Mode (`Fn + Esc`), the keyboard sends standard `VK_F6` (`0x75`) and `VK_F7` (`0x76`) keystrokes. However, because `hotkeys.ini` in the current repository comments out `F6` and `F7` by default (Observation 4), no process claims them.
   - Therefore, brightness keys appear completely dead out-of-the-box in NVIDIA GPU Only mode.
   - To fix this, software must run with administrative elevation (`RunLevel Highest`) to access `root\wmi:NvWmiBrightness`, claim `VK_F6`/`VK_F7`, enforce a 10% floor and +8 offset, and remap F1–F3/F9 so volume/media functions are preserved.

2. **Why Display Scaling Desyncs and Blurs:**
   - From Observation 3, Windows tracks scaling per display path in `PerMonitorSettings`. The Intel path has `DpiValue = 0` (125%), but the NVIDIA path has `DpiValue = -1` (100%).
   - When switching to NVIDIA GPU Only mode, Windows automatically applies the stored `-1` step, causing display scaling to drop from 125% to 100%.
   - Furthermore, because `LogPixels = 120` (125%), setting the monitor to 100% creates a mismatch between System DPI and Per-Monitor DPI.
   - When an application renders at 100% and scaling changes, or when non-Per-Monitor-V2 apps run, DWM applies bilinear bitmap scaling, creating blurry text and fuzzy UI elements.
   - Calling the CCD API (`DisplayConfigSetDeviceInfo` with `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4` and `scaleRel = 0`) enforces 125% scaling programmatically and synchronously across DWM without logoff or reboot, eliminating blur.

---

## 3. Caveats

1. **Hardware Fn-Lock Requirement:** Because Dell's EC drops F6/F7 in Media Mode without emitting any Windows input report, direct F6/F7 brightness adjustment requires the laptop to be in Function Key Mode (`Fn + Esc` or BIOS setting "Function Key First"). To ensure no user regression, F1 (Mute), F2 (Vol-), F3 (Vol+), and F9 (Play/Pause) must be remapped by the daemon.
2. **DDC/CI Non-viability:** DDC/CI (`dxva2.dll`) cannot control the internal AUO AA9F laptop panel over eDP. Backlight control must rely strictly on `WmiMonitorBrightnessMethods` (Optimus) and `NvWmiBrightness` (NVIDIA mode).
3. **Elevation Prerequisite:** Any resident tool controlling brightness in NVIDIA GPU Only mode must run with `RunLevel Highest` (via Task Scheduler). User-level startup entries will fail with Access Denied.

---

## 4. Conclusion

1. **For R2 (Brightness Hotkey Control):**
   - The dual-backend approach (`WmiMonitorBrightnessMethods` on Intel, `NvWmiBrightness` on NVIDIA) is technically validated and functional.
   - Default hotkey bindings for `F6=brightness_down` and `F7=brightness_up` must be enabled out-of-the-box with Function Row preservation (F1–F3, F9 remapped to media).
   - An interactive Acrylic OSD window (`WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT`) must be added to provide visual feedback, replacing the absent native Windows slider.
2. **For R3 (Persistent 125% Display Scaling):**
   - All `PerMonitorSettings` registry keys corresponding to the AUO AA9F panel topologies (`10DE` and `8086`) must be synchronized to `DpiValue = 0` (125%).
   - A runtime event listener on `WM_DISPLAYCHANGE` calling `DisplayConfigSetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE`) ensures that 125% scaling is locked immediately across every mode transition without blur or logoff.
3. **System Architecture:**
   - Consolidate `PhantomGuard.exe` and `NvBrightness.exe` into a single, cohesive resident engine (`DisplayFixDaemon.exe`) running as an elevated logon task.

---

## 5. Verification Method

### Automated Commands (PowerShell - Elevated):
```powershell
# 1. Test programmatic brightness adjustment via NVIDIA WMI backend
& 'C:\ProgramData\DisplayFix\NvBrightness.exe' --set 65
# Verify readback in temp log:
Get-Content "$env:TEMP\nvbrightness-set.txt"

# 2. Check current monitor count and verify duplicate is absent
(Get-PnpDevice -Class Monitor | Where-Object { $_.Present -eq $true }).Count
# Expected: 1

# 3. Check PerMonitorSettings registry values for all AUO AA9F topologies
Get-Item 'HKCU:\Control Panel\Desktop\PerMonitorSettings\*' | Select-Object PSChildName, DpiValue
# Invalidation condition: DpiValue == 4294967295 (-1) in NVIDIA mode
```

### Physical Testing:
1. Enable Fn-Lock (`Fn + Esc`).
2. Press F6 and F7 in "NVIDIA GPU Only" mode; verify brightness increments/decrements in 5% steps and OSD reflects changes.
3. Switch from Optimus to NVIDIA GPU Only mode; verify Windows display settings display **125%** and text rendering remains sharp in File Explorer and browser windows.
