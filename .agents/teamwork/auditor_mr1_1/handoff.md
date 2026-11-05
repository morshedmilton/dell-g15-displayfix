# Forensic Integrity Audit Report: Milestone MR1

**Auditor:** Forensic Auditor 1 (`auditor_mr1_1`)  
**Target:** Milestone MR1 (Restore Display Brightness Hotkey and Backlight Control)  
**Date:** 2026-11-05T22:34:00Z  
**Project Root:** `c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix`  
**Working Directory:** `.agents/teamwork/auditor_mr1_1`  
**Integrity Mode:** Development (per `ORIGINAL_REQUEST.md`)  

---

## Audit Verdict: CLEAN

No facades, mock bypasses, dummy returns, hardcoded test outcomes, or unauthentic runtime artifacts were detected. The hotkey interception, elevation architecture, and WMI backlight control are genuine, robust, and verified empirically against live hardware interfaces and comprehensive test suites.

---

## Forensic Evidence & Phase Results

| Check / Phase | Result | Evidence / Tool Output |
|---|---|---|
| **Phase 1: Static Code Analysis** | **PASS** | Complete inspection of `src/Brightness/BrightnessController.cs`, `src/Brightness/HotkeyHook.cs`, `scripts/install.ps1`, `scripts/uninstall.ps1`, and `src/Daemon/Program.cs`. Zero mocks, fake return constants, or test shims found. |
| **Phase 1: Pre-populated Artifacts** | **PASS** | Repository scan for stale pre-existing test results returned 0 spurious files. All runtime log files in `C:\ProgramData\DisplayFix\logs\` accurately reflect execution timestamps from active runs. |
| **Phase 2: Source Compilation** | **PASS** | `scripts/build.ps1` compiles all 9 modular C# source files using `csc.exe` (.NET 4.8 x64) cleanly in 164ms. Type signatures and entry points between built and deployed binaries match 100%. |
| **Phase 2: Scheduled Task Integrity** | **PASS** | `Get-ScheduledTask -TaskName 'DisplayFixDaemon'` confirms Task State = `Running`, Principal `UserId: morsh`, `LogonType: Interactive`, and `RunLevel: Highest`. |
| **Phase 2: Elevated Process Tracing** | **PASS** | Daemon PID 31392 verified running from `C:\ProgramData\DisplayFix\DisplayFixDaemon.exe`. Verbatim log telemetry confirms: `DisplayFixDaemon resident service starting (PID: 31392, Elevated: True)`. |
| **Phase 2: Registry Cleanliness** | **PASS** | Querying `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` confirms `DisplayFixDaemon` entry is `$null` (no un-elevated auto-start). |
| **Phase 2: WMI Subsystem Authenticity** | **PASS** | Class `root\wmi:NvWmiBrightness` exists with method `NvGetSetBrightnessLevel`. Non-elevated execution produces genuine `HRESULT 0x80041003 (Access denied)`, while elevated daemon executes hardware writes successfully in < 80ms (`Result: 0`). |
| **Phase 2: Event Log Audit** | **PASS** | Querying Windows Application and System event logs for DisplayFix/NvWmi over the past hour showed 0 crashes (Event ID 1000) and 0 TDR driver resets (Event ID 4101). |
| **Phase 2: Test Suite Execution** | **PASS** | Tier 1 (80/80 passed), Tier 5 Adversarial (14/14 passed, Gate: APPROVE), and Tier All (136/136 passed across 29 suites). 100% pass rate. |

---

## Static Analysis Results

1. **`src/Brightness/BrightnessController.cs`**:
   - Implements genuine WMI COM interaction via `ManagementObjectSearcher` and `InvokeMethod` against `root\wmi:NvWmiBrightness.NvGetSetBrightnessLevel` (lines 709-742) and `root\wmi:WmiMonitorBrightnessMethods.WmiSetBrightness` (lines 680-705).
   - Readback executes real hardware probe with `inArg = 0` (lines 767-800).
   - Offset +8 calibration and safety clamping `[10, 100]` are strictly applied mathematically without fixed mock constants.
   - When no provider responds, errors are handled gracefully with `NO_ACTIVE_PROVIDER` rather than dummy success returns.

2. **`src/Brightness/HotkeyHook.cs`**:
   - Installs native Windows Win32 API low-level hook `SetWindowsHookEx(WH_KEYBOARD_LL = 13)` with pinned static callback `LowLevelKeyboardHookCallback` to prevent GC collection (lines 450-483).
   - Registers Raw Input HID Consumer Control (`0x0C / 0x01`) via `RegisterRawInputDevices` for hardware Fn-lock media key handling (lines 497-530).
   - Synthesizes media keys cleanly using `SendInput` tagged with `DISPLAYFIX_SYNTHETIC_EXTRA_INFO (0x44464958)` to avoid recursive loops (lines 822-846).
   - Hook callback offloads all WMI and OSD execution to `ThreadPool.QueueUserWorkItem`, maintaining hook latency well under the 5ms budget (average 18.3 µs in stress testing).

3. **`scripts/install.ps1` & `scripts/uninstall.ps1`**:
   - Installer validates elevation gate (`IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`).
   - Generates active `C:\ProgramData\DisplayFix\hotkeys.ini` with `BrightnessDown=F6`, `BrightnessUp=F7`, `Step=5`, `Mute=F1`, `VolumeDown=F2`, `VolumeUp=F3`, `PlayPause=F9`.
   - Cleans legacy scheduled tasks (`DisplayFixGuard`, `DisplayFixBrightness`) and removes `DisplayFixDaemon` from `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`.
   - Registers unified scheduled task `DisplayFixDaemon` with `RunLevel Highest` and trigger `AtLogon`.
   - Uninstaller cleanly tears down tasks, processes, and registry entries.

---

## Runtime Tracing Results

1. **Task Scheduler Verification**:
   ```powershell
   (Get-ScheduledTask -TaskName 'DisplayFixDaemon').Principal
   ```
   Direct output:
   ```
   RunLevel              : Highest
   LogonType             : Interactive
   ProcessTokenSidType   : Default
   UserId                : morsh
   ```

2. **Daemon Telemetry & Process Elevation**:
   Querying `C:\ProgramData\DisplayFix\logs\daemon.log` confirmed resident execution under PID 31392:
   ```
   2026-11-05 22:17:22.209 [INFO ] [Daemon      ] DisplayFixDaemon resident service starting (PID: 31392, Elevated: True).
   2026-11-05 22:17:22.248 [INFO ] [HotkeyHook  ] Installed WH_KEYBOARD_LL (idHook=13) handle=0x01300E27 (Step=5%, F6=0x75, F7=0x76, Media=F1-F3/F9).
   2026-11-05 22:17:22.249 [INFO ] [HotkeyHook  ] Raw Input HID Consumer Control (0x0C/0x01) registered.
   ```

3. **WMI Hardware Write Verification**:
   When elevated daemon set brightness to 50%:
   ```
   2026-11-05 22:20:32.032 [INFO ] [Brightness  ] Set brightness to 50% (NV compensated=58) via root\wmi:NvWmiBrightness in 79.65ms.
   ```
   When non-elevated caller attempted write:
   ```
   2026-11-05 22:31:49.042 [DEBUG] [Brightness  ] NVIDIA NvGetSetBrightnessLevel write unavailable: Access denied
   ```
   This confirms that the WMI call directly addresses the security descriptor of the NVIDIA kernel-mode WMI provider rather than a fake user-mode mock.

4. **Registry Cleanliness**:
   ```powershell
   (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).DisplayFixDaemon
   ```
   Returned `$null`.

---

## 1. Observation

1. **Source Code & Binary Integrity**:
   - Compiling source with `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1` succeeded in 164ms, producing `bin\DisplayFixDaemon.exe` (119,808 bytes).
   - Reflection analysis of `bin\DisplayFixDaemon.exe` and `C:\ProgramData\DisplayFix\DisplayFixDaemon.exe` demonstrated identical type count (58 types), identical entry point (`Int32 Main(System.String[])`), and identical internal class structures.

2. **Scheduled Task State**:
   - `Get-ScheduledTask -TaskName 'DisplayFixDaemon'` returned State = `Running`, `RunLevel: Highest`, `UserId: morsh`, Action = `C:\ProgramData\DisplayFix\DisplayFixDaemon.exe --run`.

3. **Daemon Status Telemetry**:
   - Executing `DisplayFixDaemon.exe --status` returned:
     ```
     Mutex Active:        True (Global\DisplayFixDaemon_SingleInstanceMutex)
     Process Running:     True (Count: 1)
     Process PID:         31392
     Working Set (MB):    22.19
     Refresh Rate (Hz):   360 Hz
     Display Scaling (%): 125%
     Brightness (%):      50%
     Brightness Backend:  NvWmiBrightness
     Log Exists:          True
     ```

4. **Event Log State**:
   - `Get-WinEvent` for LogName `Application` and `System` covering the past hour showed 0 errors matching `DisplayFix*`, `NvWmi*`, or `dwm.exe`.

5. **Test Executions**:
   - `tests/e2e/test_runner.ps1 -Tier 1`: 16 suites, 80 tests, 80 passed, 0 failed.
   - `tests/e2e/tier5_adversarial/adversarial_m4_brightness_osd_test.ps1`: 14 tests executed, 14 passed, 0 failed. Gate verdict: `APPROVE`.
   - `tests/e2e/test_runner.ps1 -Tier All`: 29 suites, 136 tests, 136 passed, 0 failed. Duration: 25.27s.

---

## 2. Logic Chain

1. **Static Analysis & Absence of Facades**:
   - Codebase review across `BrightnessController.cs`, `HotkeyHook.cs`, `install.ps1`, and `Program.cs` verified that all interfaces make real system calls (`SetWindowsHookEx`, `RegisterRawInputDevices`, `ManagementObjectSearcher`, `InvokeMethod`).
   - There are no hardcoded conditional responses (e.g., returning fixed PASS values during tests), confirming absence of mock facades.

2. **Runtime Verification of Elevation & Service Integrity**:
   - The scheduled task configuration confirms `RunLevel: Highest` under interactive logon for user `morsh`.
   - The resident background process PID 31392 was spawned by this scheduled task. Its log entries explicitly record `Elevated: True`.
   - Un-elevated CLI processes fail with `Access denied` when contacting `root\wmi:NvWmiBrightness`, proving that hardware brightness write privileges require the elevated token possessed by PID 31392.
   - Deletion of the `HKCU Run` entry ensures that future sessions do not spawn un-elevated instances.

3. **Behavioral Correctness & Test Validation**:
   - Both unit/feature tests (Tier 1), boundary/combination/scenario tests (Tiers 2-4), and hostile adversarial tests (Tier 5) execute against the actual running system and pass 100%.
   - The absence of Application/System log errors and driver TDR events confirms system stability.

---

## 3. Caveats

- In discrete GPU only mode (current active state), the Windows Settings GUI brightness slider is not attached to the physical panel by Windows WDDM. This is an expected architectural trait of discrete GPU mobile systems. Physical brightness adjustment is fully restored via hardware hotkeys (F6/F7 and HID Consumer Control). Re-attaching the native Windows Settings slider requires Optimus / Automatic display switching mode (Milestone MR2).
- No other caveats.

---

## 4. Conclusion

The implementation of Milestone MR1 is **GENUINE, AUTHENTIC, AND FULLY COMPLIANT** with all requirements in `ORIGINAL_REQUEST.md`. There are no integrity violations, mock shims, or bypasses.

**Final Integrity Audit Verdict: CLEAN**

---

## 5. Verification Method

To independently reproduce the forensic audit:

1. **Verify Binary Build from Source**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1
   ```
   *Expected:* Compiles with `csc.exe` in < 500ms and generates 64-bit `bin\DisplayFixDaemon.exe`.

2. **Verify Scheduled Task & Elevation State**:
   ```powershell
   (Get-ScheduledTask -TaskName 'DisplayFixDaemon').Principal | Select-Object RunLevel, UserId, LogonType
   Get-Process -Name DisplayFixDaemon
   Get-Content C:\ProgramData\DisplayFix\logs\daemon.log | Select-String "Elevated: True"
   ```
   *Expected:* `RunLevel: Highest`, `UserId: morsh`, process running, `Elevated: True` logged.

3. **Verify Registry Cleanliness**:
   ```powershell
   (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).DisplayFixDaemon
   ```
   *Expected:* `$null`.

4. **Verify Hotkey Configuration**:
   ```powershell
   Get-Content C:\ProgramData\DisplayFix\hotkeys.ini
   ```
   *Expected:* Contains `BrightnessDown=F6`, `BrightnessUp=F7`, `Step=5`.

5. **Run Master Test Suites**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier 1
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\tier5_adversarial\adversarial_m4_brightness_osd_test.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e\test_runner.ps1 -Tier All
   ```
   *Expected:* All tests pass with 0 failures.
