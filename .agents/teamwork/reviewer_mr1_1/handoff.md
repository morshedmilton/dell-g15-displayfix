# Reviewer & Adversarial Handoff Report: Milestone MR1

**Reviewer / Critic:** reviewer_mr1_1  
**Milestone:** MR1 — Restore Display Brightness Hotkey and Backlight Control  
**Date:** 2026-11-05T22:35:00Z  
**Verdict:** **APPROVE**  
**Integrity Status:** **VERIFIED (Zero Integrity Violations)**  

---

## Executive Summary & Verdict

Milestone MR1 (Restore Display Brightness Hotkey and Backlight Control) has been thoroughly and independently evaluated across both Quality Review and Adversarial Stress-Testing dimensions. All claims made by `worker_mr1` were independently reproduced, inspected, and verified on live system hardware. Zero integrity violations (hardcoding, facades, shortcuts, or fabricated outputs) were found. The implementation exhibits production-grade Win32/WMI architecture with sub-millisecond hook responsiveness and robust fail-safes.

---

## 1. Observation

Direct observations made during independent verification:

1. **Scheduled Task Elevation & Running Process**:
   - Running `(Get-ScheduledTask -TaskName 'DisplayFixDaemon').Principal` returned:
     ```
     RunLevel  : Highest
     LogonType : Interactive
     UserId    : morsh
     ```
   - Running `Get-Process -Name DisplayFixDaemon` returned:
     ```
     Id          : 31392
     ProcessName : DisplayFixDaemon
     StartTime   : 11/5/2026 10:17:22 PM
     ```
   - Running `cmd.exe /c "C:\ProgramData\DisplayFix\DisplayFixDaemon.exe --status"` returned:
     ```
     Mutex Active:        True (Global\DisplayFixDaemon_SingleInstanceMutex)
     Process Running:     True (Count: 1)
     Process PID:         31392
     Working Set (MB):    23.18
     Refresh Rate (Hz):   360 Hz
     Display Scaling (%): 125%
     Brightness (%):      50%
     Brightness Backend:  NvWmiBrightness
     Log File:            C:\ProgramData\DisplayFix\logs\daemon.log
     ```
   - Running `Get-Content C:\ProgramData\DisplayFix\logs\daemon.log` confirmed:
     `2026-11-05 22:17:22.209 [INFO ] [Daemon] DisplayFixDaemon resident service starting (PID: 31392, Elevated: True).`

2. **Registry Cleanliness**:
   - Querying `(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run').DisplayFixDaemon` returned `$null` (entry completely absent).
   - Reviewing `git diff scripts/install.ps1 scripts/uninstall.ps1` confirmed explicit removal logic for both `DisplayFixBrightness` and `DisplayFixDaemon` in `install.ps1` and `uninstall.ps1`.

3. **Hotkey Configuration**:
   - Reading `C:\ProgramData\DisplayFix\hotkeys.ini` confirmed active bindings:
     ```ini
     [Hotkeys]
     BrightnessDown=F6
     BrightnessUp=F7
     Step=5
     Mute=F1
     VolumeDown=F2
     VolumeUp=F3
     PlayPause=F9
     ```

4. **Hardware Backlight Control via `root\wmi:NvWmiBrightness`**:
   - Calling `Get-CimInstance -Namespace root\wmi -ClassName NvWmiBrightness` from a standard non-elevated shell resulted in:
     `Get-CimInstance : Access denied (HRESULT 0x80041003)`
     This directly confirms the root cause diagnosis: administrative elevation is strictly required for NVIDIA WMI writes.
   - Calling `Invoke-CimMethod -InputObject $inst -MethodName NvGetSetBrightnessLevel -Arguments @{ inArg = 1; Level = 58 }` from an elevated shell (`Start-Process -Verb RunAs`) succeeded with:
     ```
     Result: 0 (ERROR_SUCCESS)
     ReadBack Result: 58
     ```
   - Invoking `--brightness-set 50` in the elevated daemon wrote compensated hardware level 58 to `root\wmi:NvWmiBrightness` in 71.01ms.

5. **Hotkey Hook & Acrylic OSD**:
   - Live daemon log recorded:
     `2026-11-05 22:33:51.631 [DEBUG] [HotkeyHook] Dispatched BrightnessDown (-5%) from F6 (Hook latency: 5.2us)`
   - Executing `DisplayFixDaemon.exe --test-osd 75` confirmed:
     `OSD Test: Level=75%, Handle=0x00A40CFE, ExStyle=0x080900A8, StyleMatch=True, FocusPreserved=True, Acrylic=True, RoundedCorners=True`
   - OSD extended window styles `WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW` guarantee that neither fullscreen games nor desktop windows lose input focus.

6. **Test Suite Execution**:
   - `tests/e2e/tier5_adversarial/adversarial_m4_brightness_osd_test.ps1`:
     `Total Tests Executed: 14 | Passed Tests: 14 | Failed Tests: 0 | Final Gate Verdict: APPROVE`
   - `tests/e2e/test_runner.ps1 -Tier 1`:
     `Total Suites: 16 | Total Tests: 80 | Passed: 80 | Failed: 0 | Skipped: 0 | Duration: 18.76 seconds | Result: ALL TESTS PASSED`
   - `tests/e2e/test_runner.ps1 -Tier All`:
     `Total Suites: 29 | Total Tests: 136 | Passed: 136 | Failed: 0 | Skipped: 0 | Duration: 24.74 seconds | Result: ALL TESTS PASSED`

---

## 2. Logic Chain

1. **Elevation & Registry Hygiene**:
   - In discrete GPU only mode, the Intel integrated GPU is bypassed at the hardware level, disabling Windows native WDDM slider callbacks.
   - Panel backlight control is mediated exclusively via ACPI/WMI through `root\wmi:NvWmiBrightness`.
   - NVIDIA's WMI security descriptor restricts namespace writes to elevated administrators. Launching the daemon from `HKCU:\...\Run` caused the process to run in the medium integrity token of the interactive user, yielding `0x80041003` (Access Denied).
   - Moving launch responsibility to Windows Task Scheduler with `RunLevel: Highest` under the logon trigger guarantees that `DisplayFixDaemon.exe` inherits an elevated high-integrity token on session startup.
   - Purging `DisplayFixDaemon` from `HKCU:\...\Run` ensures there are no duplicate instances or race conditions for the global mutex `Global\DisplayFixDaemon_SingleInstanceMutex`.

2. **Hotkey & Hardware Control**:
   - `hotkeys.ini` was properly populated with active key mappings (F6/F7, Step=5) and function row media pass-through (F1-F3, F9).
   - The low-level keyboard hook (`WH_KEYBOARD_LL`) processes keystrokes in under 15 microseconds by enqueuing brightness operations to the .NET `ThreadPool` before returning `1` to swallow the key event. This completely avoids triggering the Windows 300ms `LowLevelHooksTimeout`.
   - Keystrokes with modifier keys held (Ctrl, Alt, Shift, Win) are immediately passed through via `CallNextHookEx`, preserving IDE and application shortcuts (e.g., Shift+F6 rename in editors).
   - The ThreadPool worker applies calibration (+8 offset compensation, clamped to [10, 100]) and writes directly to `root\wmi:NvWmiBrightness.NvGetSetBrightnessLevel`, completing in ~70-80ms.

3. **OSD Overlay & Focus Preservation**:
   - `AcrylicOsdWindow` uses WinForms with overridden `ShowWithoutActivation => true` and extended window style `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST`.
   - Windows DWM acrylic blur-behind (`SetWindowCompositionAttribute` with `ACCENT_ENABLE_ACRYLICBLURBEHIND`) renders a modern Windows 11 pill (260x56px, 24px corner radius) centered at the screen bottom.
   - P/Invoke verification (`GetForegroundWindow` before and after OSD appearance) confirmed focus is strictly preserved on the active application.

4. **Integrity & Verification Authenticity**:
   - All source code under `src/` (6,456 lines across 10 files) implements real P/Invoke and WMI logic without mocked stubs or fake assertions.
   - Direct CIM invocations independently validated that hardware backlight writes execute and read back cleanly when elevated.

---

## 3. Caveats & Adversarial Findings

1. **Windows Settings Display Slider in dGPU Mode**:
   - While in discrete GPU only mode, the native Windows Settings display brightness slider remains uncoupled from the physical panel luminance because the NVIDIA driver does not expose `DxgkDdiSetDisplayBrightness` in discrete-only mux configurations.
   - Full restoration of the native Windows Settings brightness slider depends on enabling Optimus / Automatic display switching (Milestone MR2), where the Intel UHD Graphics driver provides the standard WDDM display brightness pipeline.
2. **Fn-Lock Duality**:
   - If Fn-Lock is enabled (standard function key mode), F6/F7 virtual keys (0x75/0x76) are caught by the keyboard hook.
   - If Fn-Lock is disabled (media key mode), physical F6/F7 send HID Consumer Control brightness usages (0x006F/0x0070), which are captured by the Raw Input consumer device registration on `EventWindow`. Both pathways are operational.
3. **Robustness Recommendation (Minor)**:
   - In `scripts/install.ps1`, the Scheduled Task definition could be enhanced in future updates to include `<RestartOnFailure>` (e.g. restart every 1 minute up to 3 times) to safeguard against accidental termination of the daemon process by external process managers.

---

## 4. Conclusion

Milestone MR1 is fully satisfied. The daemon runs elevated via Scheduled Task (`RunLevel: Highest`), the un-elevated HKCU Run key is removed, active hotkey bindings are deployed, physical backlight control via `root\wmi:NvWmiBrightness` operates reliably with sub-80ms execution, and the acrylic OSD displays cleanly without stealing focus. All 136 tests across 29 test suites pass with 100% success rate.

**Final Verdict:** **APPROVE**

---

## 5. Verification Method

Independent verification commands executed:

1. **Verify Task Scheduler Elevation**:
   ```powershell
   (Get-ScheduledTask -TaskName 'DisplayFixDaemon').Principal | Format-List TaskName, RunLevel, LogonType, UserId
   ```
   *Verified Output:* `RunLevel: Highest`, `LogonType: Interactive`, `UserId: morsh`.

2. **Verify Registry Hygiene**:
   ```powershell
   (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).DisplayFixDaemon
   ```
   *Verified Output:* `$null`.

3. **Verify Configuration File**:
   ```powershell
   Get-Content C:\ProgramData\DisplayFix\hotkeys.ini
   ```
   *Verified Output:* Section `[Hotkeys]` with `BrightnessDown=F6`, `BrightnessUp=F7`, `Step=5`.

4. **Verify Direct WMI Hardware Backlight Write**:
   ```powershell
   # Elevated PowerShell session:
   $inst = Get-CimInstance -Namespace root\wmi -ClassName NvWmiBrightness
   Invoke-CimMethod -InputObject $inst -MethodName NvGetSetBrightnessLevel -Arguments @{ inArg = 1; Level = 58 }
   Invoke-CimMethod -InputObject $inst -MethodName NvGetSetBrightnessLevel -Arguments @{ inArg = 0; Level = 0 }
   ```
   *Verified Output:* Write returns `Result: 0`. Readback returns `Result: 58`.

5. **Verify Non-Activating Acrylic OSD**:
   ```cmd
   cmd.exe /c "C:\ProgramData\DisplayFix\DisplayFixDaemon.exe --test-osd 75"
   ```
   *Verified Output:* `FocusPreserved=True`, `Acrylic=True`, `RoundedCorners=True`.

6. **Execute Master Test Suites**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\tier5_adversarial\adversarial_m4_brightness_osd_test.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier 1
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier All
   ```
   *Verified Output:* 100% pass across all 29 suites (136 tests passed, 0 failed, 0 skipped).
