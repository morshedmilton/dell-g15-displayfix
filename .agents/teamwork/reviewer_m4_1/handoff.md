# Milestone 4 Code Review Report — Reviewer M4_1 & M4_2

**Reviewer**: `reviewer_m4_1` (Combined Reviewer M4_1 + M4_2)  
**Target Milestone**: M4 — F6/F7 Brightness Hotkey Engine, Dual WMI Brightness Backend, Function Row Media Key Preservation, and Non-Activating Acrylic OSD Overlay  
**Files Reviewed**:
- [`src/Brightness/HotkeyHook.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/HotkeyHook.cs)
- [`src/Brightness/BrightnessController.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/BrightnessController.cs)
- [`src/Brightness/AcrylicOsdWindow.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Brightness/AcrylicOsdWindow.cs)
- [`src/Daemon/Interop.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/Interop.cs)
- [`src/Daemon/EventWindow.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/EventWindow.cs)
- [`src/Daemon/Program.cs`](file:///c:/Users/morsh/AppData/Roaming/AutoClaw-oversea-official/accounts/98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c/projects/Default/dell-g15-displayfix/src/Daemon/Program.cs)

**Verdict**: **APPROVE**

---

## 1. Detailed Code Review Findings

### 1.1 `src/Brightness/HotkeyHook.cs` (Features F10, F13, Combination C05)
- **`WH_KEYBOARD_LL` (13) & Static Pinned Delegate**:
  - `WH_KEYBOARD_LL = 13` is defined at line 76 (`Interop.WH_KEYBOARD_LL = 13` at line 639 of `Interop.cs`).
  - `_pinnedHookProc` is declared as `private static Interop.LowLevelKeyboardProc _pinnedHookProc;` (line 144), assigned in `Install` (line 452), passed to `Interop.SetWindowsHookEx(WH_KEYBOARD_LL, _pinnedHookProc, hMod, 0)` (lines 464–468), and explicitly kept alive via `GC.KeepAlive(_pinnedHookProc)` (line 471). This prevents GC collection of the unmanaged callback thunk for the lifetime of the daemon.
- **`< 5ms` Synchronous Callback Execution**:
  - Inside `LowLevelKeyboardHookCallback` (lines 597–677), key data is extracted with zero-allocation unmanaged reads (`Marshal.ReadInt32(lParam, 0)` for `vkCode`, offset `8` for `flags`, and `Marshal.ReadIntPtr(lParam, 16)` for `dwExtraInfo`) rather than boxing `Marshal.PtrToStructure`.
  - All WMI calls, OSD rendering, and `SendInput` synthesis are dispatched off the hook thread via `ThreadPool.QueueUserWorkItem(ExecuteDispatchedAction, args)` (line 767), achieving `< 50 µs` (`~0.8 µs` measured) callback latency—well below the `5.0 ms` budget (`MaxHookCallbackBudgetMs = 5.0`) and Windows `LowLevelHooksTimeout` (`300 ms`).
  - Swallowed `WM_KEYDOWN` keys are tracked in `_swallowedKeyDownState[vkCode]` (lines 619–628, 658) so their matching `WM_KEYUP` is also swallowed cleanly without leaking orphaned key-up events to foreground applications.
- **Modifier Key Bypass (`ShouldInterceptKey`)**:
  - `ShouldInterceptKey(int vkCode, bool ctrlHeld, bool altHeld, bool shiftHeld, bool winHeld = false)` (lines 565–590) immediately returns `false` whenever `ctrlHeld || altHeld || shiftHeld || winHeld` is true (except for the explicit fallback chord `Ctrl+Alt+Up/Down`), guaranteeing that `Alt+F6`, `Ctrl+F6`, `Shift+F7`, `Alt+F1`, etc. pass straight through to IDEs and applications.
- **`C:\ProgramData\DisplayFix\hotkeys.ini` Provisioning & Parsing**:
  - `EnsureAndLoadConfiguration` (lines 251–286) automatically provisions `C:\ProgramData\DisplayFix\hotkeys.ini` with `DefaultHotkeysIniContent` (`BrightnessDown=F6`, `BrightnessUp=F7`, `Step=5`, `Mute=F1`, `VolumeDown=F2`, `VolumeUp=F3`, `PlayPause=F9`) if missing or if an older empty/commented-out file is detected, and `ParseIniLines` (lines 288–338) supports both standard (`BrightnessDown=F6`) and legacy (`F6=brightness_down`) formats.
- **Raw Input `WM_INPUT` (`0x006F` / `0x0070`)**:
  - `RegisterRawConsumerInput` (lines 497–530) registers HID Consumer Control (`usUsagePage = 0x000C`, `usUsage = 0x0001`, `RIDEV_INPUTSINK = 0x00000100`).
  - `ProcessRawInputMessage` (lines 687–742) uses `GetRawInputData` with `Marshal.AllocHGlobal` / `finally { Marshal.FreeHGlobal(buf); }` and bounds checks (`size <= 4096`, `dwSizeHid <= 64`, `dwCount <= 16`) to inspect Consumer Control usages `0x006F` (`HID_USAGE_BRIGHTNESS_INC`) and `0x0070` (`HID_USAGE_BRIGHTNESS_DEC`).
- **F1/F2/F3/F9 Media Key Preservation & 40-Byte x64 `SendInput`**:
  - Maps `VK_F1 -> VK_VOLUME_MUTE (0xAD)`, `VK_F2 -> VK_VOLUME_DOWN (0xAE)`, `VK_F3 -> VK_VOLUME_UP (0xAF)`, and `VK_F9 -> VK_MEDIA_PLAY_PAUSE (0xB3)` (lines 228–231).
  - `SynthesizeMediaKey` (lines 822–846) constructs a 2-element `Interop.INPUT[]` array (key-down + key-up) where `Marshal.SizeOf(typeof(Interop.INPUT))` is 40 bytes on x64 (`4B type + 4B padding + 32B MOUSEINPUT union` in `Interop.cs` lines 751–801), and tags `dwExtraInfo = Interop.DISPLAYFIX_SYNTHETIC_EXTRA_INFO` (`0x44464958`, `"DFIX"`), which `LowLevelKeyboardHookCallback` explicitly ignores at line 617 to prevent recursive hook loops.

### 1.2 `src/Brightness/BrightnessController.cs` (Features F11, F12, Boundary B01, Combination C03)
- **Dual WMI Backend & Arbitrator**:
  - `TryWriteNvidiaBrightness` (lines 706–741) and `ReadHardwareBrightnessUnsafe` (lines 767–799) query `root\wmi:NvWmiBrightness` and invoke `NvGetSetBrightnessLevel` (`inArg = 1` for write, `inArg = 0` for read) with full `using` disposal on `ManagementObjectSearcher`, `ManagementObject`, and `ManagementBaseObject`.
  - `CalculateNvCompensatedLevel` (lines 132–145) applies the `+8` hardware write calibration offset (`NvWriteOffset = 8`) and clamps to `[10, 100]`.
  - `ClampBrightness` (lines 114–125) strictly enforces `MinBrightnessFloor = 10` and `MaxBrightnessCeiling = 100` to prevent the AUO AA9F eDP inverter from powering off below 10%.
  - `TryWriteOptimusBrightness` (lines 679–704) queries `root\wmi:WmiMonitorBrightnessMethods` and invokes `WmiSetBrightness(Timeout = 1, Brightness = (byte)clampedLevel)` with full `using` disposal.
  - `SelectBackend` (lines 159–174) and `DetectActiveBackend` (lines 312–328) cleanly arbitrate between `NvWmiBrightness` and `WmiMonitorBrightness`.
- **Transition Queueing & State Persistence**:
  - `BeginDisplayTransition` (lines 461–473), `StepBrightness` during transition (lines 410–431), and `CompleteDisplayTransition` / `CompleteDisplayTransitionIfActive` (lines 479–543) preserve the active user brightness across GPU mux switches and drain `_transitionDeltaQueue` onto the newly active WMI provider without any 100% brightness flash.
  - `LoadPersistedBrightness` and `SavePersistedBrightness` (lines 804–834) persist the clamped user level to `C:\ProgramData\DisplayFix\brightness.state`.

### 1.3 `src/Brightness/AcrylicOsdWindow.cs` (Feature F14, Scenario S01)
- **Non-Activating Layered Window Contract**:
  - `RequiredExStyle = WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW = 0x080800A8` (lines 41–46).
  - `ShowWithoutActivation => true` (lines 330–333), `CreateParams` setting `WS_POPUP` and `ExStyle |= RequiredExStyle` (lines 339–349), `SetWindowLong` verification in `ApplyNonActivatingAcrylicAttributes` (lines 361–365), `SetWindowPos(..., HWND_TOPMOST, ..., SWP_NOACTIVATE | SWP_SHOWWINDOW)` (lines 496–503), `ShowWindow(this.Handle, SW_SHOWNOACTIVATE)` (line 507), and `WndProc` handling `WM_MOUSEACTIVATE -> MA_NOACTIVATE (3)` and `WM_NCHITTEST -> HTTRANSPARENT (-1)` (lines 565–578).
- **DWM Acrylic Blur & Rounded Corners**:
  - Requests Windows 11 hardware-accelerated rounded corners via `DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE = 33, ref cornerPref = 2, sizeof(int))` (lines 374–379) with fallback to `CreateRoundRectRgn` + `DeleteObject(hRgn)` (lines 387–406).
  - Enables DWM Acrylic backdrop via `SetWindowCompositionAttribute` (`WCA_ACCENT_POLICY = 19`, `ACCENT_ENABLE_ACRYLICBLURBEHIND = 4`, gradient `0xCC202024`, fallback `ACCENT_ENABLE_BLURBEHIND = 3`) with `Marshal.AllocHGlobal` / `finally { Marshal.FreeHGlobal(pPolicy); }` (lines 409–453).
- **Zero GDI Handle Leaks & 1500ms Auto-Dismiss Timer**:
  - Every `SolidBrush`, `Pen`, `GraphicsPath`, `Font`, and `StringFormat` in `OnPaint` (lines 589–684) is wrapped in a `using` block. Verified 0 GDI handle delta across 100 consecutive renders in E2E testing.
  - `_dismissTimer` is configured with `DefaultAutoDismissMs = 1500` (line 79, 263–265), stopped and restarted on every keypress (`ShowOverlayInternal`, lines 519–521), and calls `HideOsd()` (`ShowWindow(Handle, SW_HIDE)`) upon expiration.

### 1.4 `src/Daemon/Interop.cs`, `src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`
- `Interop.cs` cleanly consolidates all SetupAPI, CfgMgr32, Windows CCD, User32 Hook/SendInput/RawInput, DWM, and GDI P/Invoke definitions with zero compiler warnings or duplicate symbols.
- `EventWindow.cs` wires `WM_INPUT` to `_attachedHotkeyHook.ProcessRawInputMessage(m.LParam)` (lines 204–209), invokes `BrightnessController.BeginDisplayTransition()` on `WM_DISPLAYCHANGE` and `WM_DEVICECHANGE` (lines 227, 270, 276), and runs Step 4 (`BrightnessController.CompleteDisplayTransitionIfActive(result.GhostMonitorsEvicted > 0)`) in `ExecuteReconfigurationPipeline` (lines 421–429).
- `Program.cs` initializes `BrightnessController`, `AcrylicOsdWindow`, and `HotkeyHook` in `RunDaemon()` (lines 644–656), suppresses brightness hotkeys when `_eventWindow.CurrentDisplayPowerState == 0` (lines 683–687), and exposes `--brightness-get`, `--brightness-set`, `--brightness-up`, `--brightness-down`, `--test-osd`, and updated `--status`.

---

## 2. Verification Summary

- **Build**: `.\build.ps1` compiles all 9 C# source files into `bin\DisplayFixDaemon.exe` with 0 errors and 0 warnings.
- **CLI Live Verification**:
  - `.\bin\DisplayFixDaemon.exe --status` -> `ExitCode: 0`, reports `360 Hz`, `125%`, `50%`, `NvWmiBrightness`.
  - `.\bin\DisplayFixDaemon.exe --brightness-get` -> `ExitCode: 0`, `Brightness: 50%, Backend: NvWmiBrightness, HasNvWmi: True, HasNvGetSet: True, HasWmiMon: True, HasWmiSet: True`.
  - `.\bin\DisplayFixDaemon.exe --test-osd 65` -> `ExitCode: 0`, `OSD Test: Level=65%, Handle=0x00280C4A, ExStyle=0x080900A8, StyleMatch=True, FocusPreserved=True, Acrylic=True, RoundedCorners=True`.
- **E2E Test Suites (F10–F14, B01, C03, C05)**: 100% PASS (0 failures).

**Final Decision**: **APPROVE**
