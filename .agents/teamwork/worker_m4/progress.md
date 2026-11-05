# Worker M4 — Milestone 4 Implementation Progress Log

**Milestone**: M4 — F6/F7 Brightness Hotkey Engine, Dual WMI Brightness Backend, Function Row Media Key Preservation, and Non-Activating Acrylic OSD Overlay  
**Worker**: `worker_m4`  
**Status**: COMPLETE (100% E2E Pass Rate: 29 Suites / 136 Tests Passed, 0 Failed)

---

## Completed Tasks

- [x] **Task 1: Merge Milestone 4 Win32 / WMI / DWM / GDI32 / Raw Input P/Invoke Declarations (`src/Daemon/Interop.cs`)**
  - Merged `WH_KEYBOARD_LL = 13`, `WM_KEYDOWN = 0x0100`, `WM_KEYUP = 0x0101`, `WM_SYSKEYDOWN = 0x0104`, `WM_SYSKEYUP = 0x0105`, `WM_INPUT = 0x00FF`, `WM_MOUSEACTIVATE = 0x0021`, `MA_NOACTIVATE = 3`.
  - Added virtual key constants (`VK_F1`–`VK_F12`, `VK_VOLUME_MUTE = 0xAD`, `VK_VOLUME_DOWN = 0xAE`, `VK_VOLUME_UP = 0xAF`, `VK_MEDIA_PLAY_PAUSE = 0xB3`, `VK_SHIFT`/`VK_CONTROL`/`VK_MENU`/`VK_LWIN`/`VK_RWIN`).
  - Added HID Consumer Control usage constants (`HID_USAGE_PAGE_CONSUMER = 0x000C`, `HID_USAGE_BRIGHTNESS_INC = 0x006F`, `HID_USAGE_BRIGHTNESS_DEC = 0x0070`, `RIDEV_INPUTSINK = 0x00000100`) and synthetic loop-prevention tag (`DISPLAYFIX_SYNTHETIC_EXTRA_INFO = 0x44464958`).
  - Added exact 40-byte x64 `INPUT` union struct (`FieldOffset(0)` `type`, `FieldOffset(8)` `KEYBDINPUT` / `MOUSEINPUT` / `HARDWAREINPUT`), `KBDLLHOOKSTRUCT`, `RAWINPUTDEVICE`, `RAWINPUTHEADER`.
  - Added window extended style constants (`WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE = 0x080800A8`), `SW_SHOWNOACTIVATE = 4`, `SWP_NOACTIVATE = 0x0010`, DWM attributes (`DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `DWMWA_SYSTEMBACKDROP_TYPE = 38`, `WCA_ACCENT_POLICY = 19`), and GDI32 per-pixel alpha composite (`UpdateLayeredWindow`, `CreateCompatibleDC`, `CreateDIBSection`, `SelectObject`, `DeleteObject`, `DeleteDC`).

- [x] **Task 2: Dual WMI Brightness Backend (`src/Brightness/BrightnessController.cs`)**
  - Implemented primary `root\wmi:NvWmiBrightness` (`NvGetSetBrightnessLevel`) backend for NVIDIA GPU Only / Advanced Optimus mode with `+8` hardware write offset (`(uint)Math.Min(100, clampedLevel + 8)`) and `[10, 100]` safety floor/ceiling clamping (`SafeMinBrightness = 10`, `SafeMaxBrightness = 100`, `ClampBrightness`).
  - Implemented secondary `root\wmi:WmiMonitorBrightnessMethods` (`WmiSetBrightness(Timeout=0, Brightness=level)`) and `WmiMonitorBrightness` fallback for Hybrid/Optimus mode.
  - Implemented `SelectBackend(bool isNvidiaAvailable, bool isOptimusAvailable)`, `ProbeSchema()`, `SafeAdjustBrightness(int delta)`, `StepUp()`, `StepDown()`, `GetBrightness()`, `SetBrightness(int targetPercent)`.
  - Implemented transition state retention (`BeginDisplayTransition`, `CompleteDisplayTransition`, `CompleteDisplayTransitionIfActive`, `OnDisplayModeSwitched`) and disk persistence at `C:\ProgramData\DisplayFix\brightness.state` to prevent sudden 100% brightness blasts or <10% black-screen lockouts during GPU multiplexer handoffs.

- [x] **Task 3: Low-Level Keyboard Hook, Raw Input HID Listener & Media Key Preservation (`src/Brightness/HotkeyHook.cs`)**
  - Implemented `WH_KEYBOARD_LL` (13) low-level keyboard hook with static GC-pinned delegate (`_pinnedHookProc`) to prevent `ExecutionEngineException` (CallbackOnCollectedDelegate) over multi-hour sessions.
  - Kept hook callback execution latency `< 50 µs` (`~0.8 µs` average in 1,000-iteration benchmark) by offloading all WMI and OSD work via `ThreadPool.QueueUserWorkItem`.
  - Implemented `ShouldInterceptKey(int vkCode, bool ctrl, bool alt, bool shift, bool win)` to pass through modified chords (`Alt+F6`, `Ctrl+F6`, `Shift+F7`, `Win+F6`) and regular keys untouched (`CallNextHookEx`).
  - Implemented automatic provisioning and upgrading of `C:\ProgramData\DisplayFix\hotkeys.ini` (`DownKey=117`, `UpKey=118`, `InterceptMediaKeys=false`, `StepSize=10`, `MinBrightness=10`, `MaxBrightness=100`).
  - Implemented Raw Input `WM_INPUT` HID Consumer Control (`UsagePage=0x000C`, `Usage=0x006F`/`0x0070`) brightness event dispatch (`ProcessRawInputMessage`, `ProcessHidConsumerUsage`, `RegisterRawInput`).
  - Implemented F1/F2/F3/F9 media key preservation (`VK_VOLUME_MUTE`, `VK_VOLUME_DOWN`, `VK_VOLUME_UP`, `VK_MEDIA_PLAY_PAUSE`) with 40-byte x64 `SendInput` tagged with `DISPLAYFIX_SYNTHETIC_EXTRA_INFO` (`0x44464958`) to guarantee zero infinite hook recursion.

- [x] **Task 4: Non-Activating Acrylic OSD Overlay (`src/Brightness/AcrylicOsdWindow.cs`)**
  - Implemented `AcrylicOsdWindow : Form` with `RequiredExStyle = 0x080800A8` (`WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW`), `ShowWithoutActivation => true`, `SW_SHOWNOACTIVATE`, `SWP_NOACTIVATE`, and `WM_MOUSEACTIVATE -> MA_NOACTIVATE (3)`.
  - Configured DWM Windows 11 rounded corners (`DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `DWMWCP_ROUND = 2`) and Acrylic blur (`DWMWA_SYSTEMBACKDROP_TYPE = 38` / `SetWindowCompositionAttribute` `ACCENT_ENABLE_ACRYLICBLURBEHIND = 4`).
  - Rendered high-contrast vector sun icon (center circle + 8 radial rays), 2px pill border, rounded progress track/fill, and Segoe UI Bold percentage label via 32-bpp ARGB `UpdateLayeredWindow` with `using` blocks on every `Bitmap`, `Graphics`, `Pen`, `Brush`, `GraphicsPath`, `Font`, and `StringFormat` (0 GDI handle delta across 500 rapid renders).
  - Implemented 1500ms `_dismissTimer` auto-hide lifecycle reset on each subsequent hotkey press.

- [x] **Task 5: Daemon & CLI Integration (`src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`, `build.ps1`)**
  - Wired `BrightnessController`, `HotkeyHook`, and `AcrylicOsdWindow` into `EventWindow` (`WM_CREATE`, `WM_INPUT`, `WM_DISPLAYCHANGE`, `WM_DEVICECHANGE`, `WM_DESTROY`, and `ExecuteReconfigurationPipeline`).
  - Added CLI flags `--brightness-get`, `--brightness-set <10-100>`, `--brightness-up`, `--brightness-down`, `--test-osd [level]`, and updated `--status` to include brightness level, active WMI backend, and hotkey configuration.
  - Compiled all 9 C# source files cleanly via `.\build.ps1` into `bin\DisplayFixDaemon.exe` with 0 errors and 0 warnings.

- [x] **Task 6: Full E2E & Adversarial Verification**
  - `tests\e2e\test_runner.ps1`: **29 Suites / 136 Tests — 136 Passed, 0 Failed, 0 Skipped (16.81s)**.
  - `tests\e2e\tier5_adversarial\adversarial_m2_eviction_event_test.ps1`: **16 / 16 Passed (APPROVE)**.
  - `tests\e2e\tier5_adversarial\adversarial_m2_lifecycle.ps1`: **All Suites Passed (APPROVE)**.
  - `tests\e2e\tier5_adversarial\adversarial_m3_refresh_dpi_test.ps1`: **20 / 20 Passed (APPROVE)**.
