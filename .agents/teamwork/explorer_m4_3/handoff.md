# Milestone 4 Explorer Handoff: Non-Activating Acrylic OSD Overlay & Daemon / Build Integration

**Agent:** Explorer M4_3  
**Date:** 2026-11-05  
**Target Milestone:** Milestone 4 — F6/F7 Brightness Hotkey Engine & Non-Activating Acrylic OSD (`src/Brightness/AcrylicOsdWindow.cs`, `src/Daemon/Interop.cs`, `src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`, `scripts/build.ps1`)  
**Working Directory:** `.agents/teamwork/explorer_m4_3/`  
**Design Blueprint:** `.agents/teamwork/explorer_m4_3/acrylic_osd_design.md`

---

## 1. Observation

1. **Test Assertions & Requirements (`test_f14_acrylic_osd.ps1`, `test_s01_gaming_session.ps1`, `test_c03_switching_and_brightness.ps1`, `test_c05_hotkeys_and_media_keys.ps1`)**:
   - **F14.1 & S01.4**: The OSD window must enforce all 5 Win32 extended styles: `WS_EX_TOPMOST (0x00000008)`, `WS_EX_TRANSPARENT (0x00000020)`, `WS_EX_TOOLWINDOW (0x00000080)`, `WS_EX_LAYERED (0x00080000)`, and `WS_EX_NOACTIVATE (0x08000000)` (`RequiredExStyle = 0x080800A8`).
   - **F14.2 & S01.4**: Showing or updating the OSD must never steal foreground focus (`GetForegroundWindow()` before, during, and after `ShowOsd` must remain identical) or cause full-screen games to minimize.
   - **F14.3**: Pill dimensions must match `DefaultWidth = 260`, `DefaultHeight = 56`, `DefaultCornerRadius = 24`, centered horizontally on the primary screen.
   - **F14.4 & F14.5**: Auto-dismiss timer (`_dismissTimer`) must use a `1500ms` duration (within `[1000, 2000]ms`) and reset back to `0` (`_dismissTimer.Stop(); _dismissTimer.Start();`) whenever a consecutive `F6`/`F7` keypress arrives while the OSD is visible.
   - **S01.2**: Zero GDI / USER handle creep (`GetGuiResources` delta $\le 25$ handles) under repeated rendering.
   - **C03.1–C03.4**: Brightness level (`[10..100]`) must be retained across display mux switches (`WM_DISPLAYCHANGE` / `WM_DEVICECHANGE`) without a sudden 100% blast, and hotkey events during transitions must be safely handled.
   - **Adv 2.5 (`adversarial_m2_lifecycle.ps1`)**: Unknown or empty CLI flags (`--help`, `--unknown`, `""`) must continue to fall through to `default: return RunDaemon();` (exiting with code `2` when the single-instance mutex is held).
2. **Live Hardware Verification (`.agents/teamwork/explorer_m4_3/probe_acrylic_osd.ps1`)**:
   - Compiled and tested `AcrylicOsdWindow` using native .NET Framework 4.8 x64 (C# 5) on the live Dell G15 5530 (Windows 11 Build 26300):
     - `GetWindowLong(Handle, GWL_EXSTYLE)` returned `0x080900A8`, confirming all 5 required extended style bits (`0x080800A8`) are active (`Mask Matched: True`).
     - `SetWindowCompositionAttribute` (`WCA_ACCENT_POLICY = 19`, `ACCENT_ENABLE_ACRYLICBLURBEHIND = 4`, gradient `0xCC202024`) succeeded (`Acrylic Applied: True`).
     - `DwmSetWindowAttribute` (`DWMWA_WINDOW_CORNER_PREFERENCE = 33`, `DWMWCP_ROUND = 2`) succeeded (`Corner Applied: True`).
     - `GetForegroundWindow()` remained 100% unchanged across `ShowOsd(65, "NVIDIA")` (`Focus Preserved: True`).
     - 19 consecutive rapid `ShowOsd` renders (`10%` to `100%`) produced `GDI Delta: 0` and `USER Delta: 0`.
3. **Build Script Inspection (`scripts/build.ps1`)**:
   - `scripts/build.ps1` already passes `/r:System.Drawing.dll`, `/r:System.Windows.Forms.dll`, and `/r:System.Management.dll` in `$commonArgs` (lines 94–96) and recursively compiles all `.cs` files under `src/` (lines 137–139), so `src/Brightness/HotkeyHook.cs`, `src/Brightness/BrightnessController.cs`, and `src/Brightness/AcrylicOsdWindow.cs` are automatically compiled into `bin/DisplayFixDaemon.exe`.

---

## 2. Logic Chain

1. **Triple-Guarded Non-Activating Overlay (`src/Brightness/AcrylicOsdWindow.cs`)**:
   - Overriding `ShowWithoutActivation { get { return true; } }` and `CreateParams` (`Style = WS_POPUP`, `ExStyle |= 0x080800A8`) prevents WinForms from activating the window during handle creation.
   - Displaying the window exclusively via `SetWindowPos(Handle, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW)` and `ShowWindow(Handle, SW_SHOWNOACTIVATE = 4)`—and intercepting `WM_MOUSEACTIVATE (0x0021)` $\rightarrow$ `MA_NOACTIVATE (3)` and `WM_NCHITTEST (0x0084)` $\rightarrow$ `HTTRANSPARENT (-1)`—guarantees zero focus theft and full click-through in full-screen games.
2. **DWM Acrylic + GDI+ Zero-Leak Rendering**:
   - Hardware DWM Acrylic blur (`ACCENT_ENABLE_ACRYLICBLURBEHIND = 4` with `ACCENT_ENABLE_BLURBEHIND = 3` fallback) and `DWMWCP_ROUND = 2` hardware corner clipping give native Windows 11 flyout fidelity.
   - Every GDI+ resource (`SolidBrush`, `Pen`, `Font`, `GraphicsPath`, `StringFormat`) in `OnPaint` is scoped inside `using` blocks on a singleton `AcrylicOsdWindow` instance, guaranteeing `0` GDI/USER handle drift over thousands of keypresses.
3. **Unified Daemon & EventWindow Integration (`Interop.cs`, `EventWindow.cs`, `Program.cs`)**:
   - `RunDaemon()` initializes `BrightnessController`, `AcrylicOsdWindow.Instance`, and `HotkeyHook` on the UI message loop thread before `Application.Run()`, and disposes them cleanly in `Cleanup()`.
   - `EventWindow.ExecuteReconfigurationPipeline` restores the cached brightness level onto the newly active WMI provider after display switches (`Test C03.1` & `C03.2`).
   - `Program.Main` adds `--brightness-get`, `--brightness-set` (alias `--set`), `--brightness-up`, `--brightness-down`, and `--test-osd`, while keeping `default: return RunDaemon();` for adversarial lifecycle compatibility.

---

## 3. Caveats

1. **Strict C# 5 Warning-Free Compilation (`/warn:4`)**:
   - Because `scripts/build.ps1` compiles with `/warn:4`, Worker M4 must ensure no unused private fields (such as an unread `_lastShowTickCount` if not exposed via a property) remain in `AcrylicOsdWindow.cs`, `HotkeyHook.cs`, or `BrightnessController.cs`.
2. **UI Thread Marshaling for `ShowOsd`**:
   - Low-level keyboard hook callbacks (`WH_KEYBOARD_LL`) run on the thread that installed the hook (the main UI thread pumping `Application.Run()`), but if `AcrylicOsdWindow.ShowOsd(int brightnessPercent, string backendName)` is ever called from a background timer or thread-pool thread, `AcrylicOsdWindow.ShowOsd` checks `osd.InvokeRequired` and marshals via `BeginInvoke` so Win32 window operations always execute on the owning UI thread.

---

## 4. Conclusion

The complete C# 5 implementation of `src/Brightness/AcrylicOsdWindow.cs` and the integration blueprints for `src/Daemon/Interop.cs`, `src/Daemon/EventWindow.cs`, and `src/Daemon/Program.cs` are documented in `.agents/teamwork/explorer_m4_3/acrylic_osd_design.md` and verified on live hardware.

---

## 5. Verification Method

Once Worker M4 creates `src/Brightness/HotkeyHook.cs`, `src/Brightness/BrightnessController.cs`, and `src/Brightness/AcrylicOsdWindow.cs` and updates `src/Daemon/Interop.cs`, `src/Daemon/EventWindow.cs`, and `src/Daemon/Program.cs`:

1. **Compile via `build.ps1`**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build.ps1
   ```
   *Expected*: Compiles `bin\DisplayFixDaemon.exe` cleanly with exit code `0` and zero warnings.

2. **Verify CLI Commands (`--status`, `--test-osd`, `--brightness-get`, `--brightness-set`)**:
   ```powershell
   bin\DisplayFixDaemon.exe --test-osd 65
   bin\DisplayFixDaemon.exe --brightness-get
   bin\DisplayFixDaemon.exe --status
   ```
   *Expected*: `--test-osd 65` outputs `StyleMatch=True, FocusPreserved=True, Acrylic=True, RoundedCorners=True` and exits with code `0`.

3. **Execute E2E Feature, Boundary, Combination, Scenario & Adversarial Tests**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 1 -Filter "f10|f11|f12|f13|f14"
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 2 -Filter "b01"
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 3 -Filter "c03|c05"
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 4 -Filter "s01|s04"
   powershell -ExecutionPolicy Bypass -File tests/e2e/tier5_adversarial/adversarial_m2_lifecycle.ps1
   ```
   *Expected*: 100% pass rate with exit code `0`.
