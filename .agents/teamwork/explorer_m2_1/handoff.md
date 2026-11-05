# Explorer M2_1 Handoff Report: Core Daemon Architecture & Event Window Design

**Agent**: Explorer M2_1  
**Milestone**: Milestone 2 (Core Daemon & Ghost Monitor Eviction Engine)  
**Deliverable**: `.agents/teamwork/explorer_m2_1/event_window_design.md`  
**Date**: 2026-11-05T12:35:00Z  
**Status**: Complete (Hard Handoff)  

---

## 1. Observation

1. **Compiler Dialect and Constraints (`build.ps1` lines 9, 14–24)**:
   - Toolchain executable: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.
   - Compiler version banner: `Microsoft (R) Visual C# Compiler version 14.8.10001.0 for C# 5`.
   - When compiling C# 6+ features (e.g., string interpolation `$"..."`), the compiler failed with:
     ```
     error CS1056: Unexpected character '$'
     ```
   - Standard reference flags in `build.ps1`: `/r:System.dll`, `/r:System.Core.dll`, `/r:System.Management.dll`, `/r:System.Windows.Forms.dll`, `/r:System.Drawing.dll`. Zero external NuGet packages are permitted.

2. **Win32 Broadcast Exclusion on `HWND_MESSAGE` (`test_bcast3.cs`)**:
   - Compiling and executing a test window parented to `HWND_MESSAGE` (`new IntPtr(-3)`) vs a top-level unmapped tool window (`WS_POPUP | WS_EX_TOOLWINDOW`):
     ```
     Window created: 3869680 (MsgOnly=False, Hidden Top-Level) -> Received WM_DISPLAYCHANGE: 1920x1080 @ 32bpp (True)
     Window created: 5245824 (MsgOnly=True,  HWND_MESSAGE)    -> Received WM_DISPLAYCHANGE: False
     ```
   - The Windows window manager explicitly excludes message-only windows (`HWND_MESSAGE`) from receiving broadcast messages (`HWND_BROADCAST = 0xFFFF`). Because `WM_DISPLAYCHANGE` (0x007E) is exclusively dispatched as a broadcast, an `HWND_MESSAGE` window cannot receive it.
   - Both window types successfully register for `RegisterDeviceNotification` (`GUID_DEVINTERFACE_MONITOR` and `GUID_DEVINTERFACE_DISPLAY_ADAPTER`) and `RegisterPowerSettingNotification` (`GUID_CONSOLE_DISPLAY_STATE`).

3. **Single-Instance Mutex Contract (`test_f06_daemon_lifecycle.ps1` lines 44–62)**:
   - Mutex name contract: `Global\DisplayFixDaemon_SingleInstanceMutex`.
   - Test `F06.4` and `B04.3` enforce that a secondary launch while the mutex is held must report `createdNew = false`.
   - Verbatim execution test with prototype `DisplayFixDaemon.exe`:
     ```
     2026-11-05 18:27:36.073 [WARN ] [Mutex       ] Another instance of DisplayFixDaemon is already running. Exiting.
     Another instance of DisplayFixDaemon is already running.
     ExitCode: 2
     ```

4. **Burst Coalescing Debounce Contract (`test_f05_display_change_listener.ps1` lines 46–61 & `test_b03_rapid_display_events.ps1` lines 10–23)**:
   - Requires that a burst of 10 rapid events within 135ms must coalesce into exactly 1 discrete action dispatch after a 200ms quiet window.
   - Verbatim unit test output using `System.Threading.Timer.Change(200, Timeout.Infinite)`:
     ```
     Debounced action fired at 12:24:27.286
     Total executions: 1
     SUCCESS: Exactly 1 execution fired after burst.
     ```

5. **Power Notification State Machine (`test_f05_display_change_listener.ps1` lines 63–77 & `test_b03_rapid_display_events.ps1` lines 43–57)**:
   - Monitored power setting: `GUID_CONSOLE_DISPLAY_STATE` (`{6FE69556-704A-47A0-8F24-C28D936FDA47}`).
   - States: `0` = Off (`STAND_DOWN_SCREEN_OFF`), `1` = On (`ACTIVE_EVALUATE_MODE`), `2` = Dimmed (`STAND_DOWN_DIMMED`).
   - Sleep-wake resume transition (`0 -> 1`) triggers `RESUME_ENFORCE_360HZ` (verified by `test_s02_lid_sleep_resume.ps1` line 21).

---

## 2. Logic Chain

1. **From Observation 1**: Because the build environment relies on Windows-bundled `csc.exe` (v14.8 / C# 5) without external build tools, all source code for `Program.cs`, `EventWindow.cs`, and `Logger.cs` must strictly use C# 5 syntax (`string.Format`, explicit getters, standard null checks) and standard BCL references.
2. **From Observation 2**: Because `WM_DISPLAYCHANGE` is a broadcast message and `HWND_MESSAGE` windows never receive broadcasts, configuring `EventWindow` purely as `HWND_MESSAGE` would cause the daemon to fail to detect display resolution and topology changes. By utilizing an unmapped top-level tool window (`Parent = IntPtr.Zero`, `WS_POPUP`, `WS_EX_TOOLWINDOW`, off-screen coordinates `(-32000, -32000)`), the window receives all broadcast and device messages while remaining 100% invisible with zero Taskbar or Alt-Tab presence.
3. **From Observation 3**: The daemon entry point in `Program.cs` must initialize `Mutex(true, @"Global\DisplayFixDaemon_SingleInstanceMutex", out createdNew)`. If `!createdNew`, it must log the warning, print to console, and immediately terminate with exit code 2.
4. **From Observation 4**: Rapid MUX switching generates interleaved PnP and display change messages. By using an atomic `_syncLock` and resetting `_debounceTimer.Change(200, Timeout.Infinite)` on each message arrival, multiple events are coalesced until a continuous 200ms quiet window elapses, firing exactly one reconfiguration sequence.
5. **From Observation 5**: In `WndProc`, decoding `WM_POWERBROADCAST` with `PBT_POWERSETTINGCHANGE` against `GUID_CONSOLE_DISPLAY_STATE` allows the daemon to actively stand down and cancel pending timers when the screen turns off (state 0), preventing useless wakeups or ghost eviction during sleep, while triggering immediate re-evaluation upon wake (state 1).

---

## 3. Caveats

1. **Direct DevNode Cycling Integration**: This blueprint covers the daemon host (`Program.cs`) and message window pump (`EventWindow.cs`). The internal implementation of `GhostEvictionEngine.cs` (CfgMgr32 / SetupAPI in-process devnode cycling) is interfaced via `ExecuteGhostEviction()` delegate and is assigned to the companion Milestone 2 worker.
2. **Elevated Execution Requirement**: The daemon requires administrative credentials (`RunLevel Highest`) to cycle PnP device nodes and interact with `NvWmiBrightness`. While `Program.cs` safely detects non-elevated contexts without crashing (logging a clear warning), full hardware eviction requires elevated execution via the Task Scheduler logon task.
3. **External Display Attachment**: When an external monitor (HDMI/Type-C) is connected, eviction of non-internal monitors must stand down, as verified by feature test `F04.5` and scenario `S03.1`. The reconfiguration handler correctly delegates this topology check to the eviction engine.

---

## 4. Conclusion

The architecture and compilable source code for `src/Daemon/Program.cs`, `src/Daemon/EventWindow.cs`, and `src/Common/Logger.cs` are fully designed, prototyped, and validated:
- Fully compliant with .NET Framework 4.8 x64 and C# 5 `csc.exe` compiler constraints.
- Employs an invisible top-level tool window ensuring 100% reliable reception of `WM_DISPLAYCHANGE`, `WM_DEVICECHANGE`, and `WM_POWERBROADCAST`.
- Enforces single-instance mutex `Global\DisplayFixDaemon_SingleInstanceMutex` with exit code 2 on collisions.
- Coalesces rapid burst events into a single action via a 200ms quiet-window debounce timer.
- Implements CLI dispatcher for `--run`, `--install`, `--uninstall`, `--status`, and `--evict-now`.
- Implements thread-safe structured logging to `C:\ProgramData\DisplayFix\logs\daemon.log` with 5MB rotation.

The complete blueprint is delivered in `.agents/teamwork/explorer_m2_1/event_window_design.md`.

---

## 5. Verification Method

### 5.1 Compilation Verification
Compile the prototype source files using the exact project toolchain:
```powershell
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sources = @(
    '.agents\teamwork\explorer_m2_1\test_daemon\Logger.cs',
    '.agents\teamwork\explorer_m2_1\test_daemon\EventWindow.cs',
    '.agents\teamwork\explorer_m2_1\test_daemon\Program.cs'
)
& $csc /nologo /platform:x64 /optimize+ /warn:4 /r:System.dll /r:System.Core.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:.agents\teamwork\explorer_m2_1\test_daemon\DisplayFixDaemon.exe @sources
```
**Expected Result**: Compiles cleanly with exit code 0, 0 errors, and 0 warnings.

### 5.2 Functional CLI Verification
1. **Status Query**:
   ```powershell
   .agents\teamwork\explorer_m2_1\test_daemon\DisplayFixDaemon.exe --status
   ```
   **Expected Result**: Outputs structured status report, detects mutex status, exits with code 0.
2. **One-Shot Eviction**:
   ```powershell
   .agents\teamwork\explorer_m2_1\test_daemon\DisplayFixDaemon.exe --evict-now
   ```
   **Expected Result**: Executes eviction bridge, writes structured log entry to `C:\ProgramData\DisplayFix\logs\daemon.log`, exits with code 0.
3. **Single-Instance Mutex Collision**:
   ```powershell
   $m = New-Object System.Threading.Mutex($true, 'Global\DisplayFixDaemon_SingleInstanceMutex', [ref]$false)
   try {
       .agents\teamwork\explorer_m2_1\test_daemon\DisplayFixDaemon.exe --run
       Write-Host "ExitCode: $LASTEXITCODE"
   } finally {
       $m.ReleaseMutex()
       $m.Close()
   }
   ```
   **Expected Result**: Logs collision warning and exits with code 2.

### 5.3 Test Suite Acceptance
Execute the existing E2E feature tests:
```powershell
powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Filter "f05"
powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Filter "f06"
```
**Expected Result**: 100% pass rate across all test cases in `test_f05_display_change_listener.ps1` and `test_f06_daemon_lifecycle.ps1`.
