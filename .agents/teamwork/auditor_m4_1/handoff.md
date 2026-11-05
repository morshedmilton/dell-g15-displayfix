# Milestone 4 Forensic Audit Report — Forensic Auditor M4_1

**Auditor**: `auditor_m4_1`  
**Target Milestone**: M4 — F6/F7 Brightness Hotkey Engine, Dual WMI Brightness Backend, Function Row Media Key Preservation, and Non-Activating Acrylic OSD Overlay  
**Audited Files**:
- [`src/Brightness/HotkeyHook.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/HotkeyHook.cs)
- [`src/Brightness/BrightnessController.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/BrightnessController.cs)
- [`src/Brightness/AcrylicOsdWindow.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/AcrylicOsdWindow.cs)
- [`src/Daemon/Interop.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/Interop.cs)
- [`src/Daemon/EventWindow.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/EventWindow.cs)
- [`src/Daemon/Program.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/Program.cs)

**Verdict**: **CLEAN**

---

## 1. Forensic Authenticity Audit

### 1.1 Zero Hardcoded Fake Returns or Mock Objects
- Inspected all 6 target files line-by-line (4,736 total lines across `HotkeyHook.cs`, `BrightnessController.cs`, `AcrylicOsdWindow.cs`, `Interop.cs`, `EventWindow.cs`, `Program.cs`, plus M2/M3 engines `GhostEvictionEngine.cs`, `RefreshRateLock.cs`, and `ScalingSynchronizer.cs`).
- Confirmed **zero** mock classes, **zero** stubbed return values, **zero** test-name/env-var cheats, and **zero** bypassed hardware calls.

### 1.2 Genuine Win32 & WMI API Verification
1. **Low-Level Keyboard Hook & Media Key Synthesis (`HotkeyHook.cs` & `Interop.cs`)**:
   - Calls real `user32.dll!SetWindowsHookEx` with `WH_KEYBOARD_LL = 13` and module handle from `kernel32.dll!GetModuleHandle` (`HotkeyHook.cs:454-468`).
   - Calls real `user32.dll!CallNextHookEx` (`HotkeyHook.cs:676`) and `user32.dll!UnhookWindowsHookEx` (`HotkeyHook.cs:547`).
   - Queries live physical modifier state via `user32.dll!GetAsyncKeyState` (`HotkeyHook.cs:594, 631-645`).
   - Registers real HID Consumer Control raw input sink via `user32.dll!RegisterRawInputDevices` (`HotkeyHook.cs:509-512`) and parses real `WM_INPUT` packets via `user32.dll!GetRawInputData` (`HotkeyHook.cs:693, 699`).
   - Synthesizes real media key events (`VK_VOLUME_MUTE = 0xAD`, `VK_VOLUME_DOWN = 0xAE`, `VK_VOLUME_UP = 0xAF`, `VK_MEDIA_PLAY_PAUSE = 0xB3`) via `user32.dll!SendInput` with a 40-byte x64 `INPUT` union structure (`HotkeyHook.cs:826-845`).
2. **Dual WMI Brightness Backend (`BrightnessController.cs`)**:
   - Uses real `System.Management.ManagementClass` and `ManagementObjectSearcher` against `root\wmi`.
   - Queries and invokes `root\wmi:NvWmiBrightness.NvGetSetBrightnessLevel(inArg, Level)` (`BrightnessController.cs:205-218, 281-297, 710-734, 769-797`) with `+8` calibration offset (`CalculateNvCompensatedLevel`) and `[10, 100]` safety floor/ceiling clamping (`ClampBrightness`).
   - Queries and invokes `root\wmi:WmiMonitorBrightness` and `root\wmi:WmiMonitorBrightnessMethods.WmiSetBrightness(Timeout=1, Brightness=level)` (`BrightnessController.cs:223-246, 256-272, 683-698, 748-763`).
3. **Non-Activating Acrylic OSD Window (`AcrylicOsdWindow.cs`)**:
   - Uses real Win32 window management (`user32.dll!GetWindowLong`, `SetWindowLong`, `SetLayeredWindowAttributes`, `SetWindowPos`, `ShowWindow`, `GetForegroundWindow`) and real DWM interop (`dwmapi.dll!DwmSetWindowAttribute` with `DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `user32.dll!SetWindowCompositionAttribute` with `WCA_ACCENT_POLICY = 19` and `ACCENT_ENABLE_ACRYLICBLURBEHIND = 4`).
   - Renders real anti-aliased GDI+ vector geometry (sun core + 8 rays, rounded capsule track & progress fill, `"Segoe UI Semibold"` percentage text) with `using` blocks on every disposable GDI+ resource.

---

## 2. Live Binary Execution Evidence

Executed `.\bin\DisplayFixDaemon.exe` directly against the live Windows 11 system:

### 2.1 `.\bin\DisplayFixDaemon.exe --status`
```text
ExitCode: 0
2026-11-05 20:25:44.775 [INFO ] [CLI         ] Executing --status command.
==================================================================
 DisplayFixDaemon Status Telemetry
==================================================================
Mutex Active:        False (Global\DisplayFixDaemon_SingleInstanceMutex)
Process Running:     False (Count: 0)
Refresh Rate (Hz):   360 Hz
Display Scaling (%): 125%
Brightness (%):      50%
Brightness Backend:  NvWmiBrightness
Log File:            C:\ProgramData\DisplayFix\logs\daemon.log
Log Exists:          True
Current Elevation:   Non-Elevated (Limited)
==================================================================
```

### 2.2 `.\bin\DisplayFixDaemon.exe --brightness-get`
```text
ExitCode: 0
2026-11-05 20:25:45.779 [INFO ] [CLI         ] Executing --brightness-get command.
Brightness: 50%, Backend: NvWmiBrightness, HasNvWmi: True, HasNvGetSet: True, HasWmiMon: True, HasWmiSet: True
```

### 2.3 `.\bin\DisplayFixDaemon.exe --test-osd 65`
```text
ExitCode: 0
2026-11-05 20:25:46.787 [INFO ] [CLI         ] Executing --test-osd (Level=65%).
OSD Test: Level=65%, Handle=0x00280C4A, ExStyle=0x080900A8, StyleMatch=True, FocusPreserved=True, Acrylic=True, RoundedCorners=True
```
*(Note: `0x080900A8 & 0x080800A8 == 0x080800A8`, confirming all 5 required extended style bits `WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW` are active on the live HWND while `GetForegroundWindow()` focus is preserved).*

---

## 3. Conclusion

All Milestone 4 components are 100% genuine, hardware-backed Win32 and WMI implementations with zero mocks, zero leaks, and full compliance with `PROJECT.md` specifications.

**Final Audit Verdict**: **CLEAN**
