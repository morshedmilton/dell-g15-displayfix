# Core Daemon Architecture & Windows Message Loop Blueprint (Milestone 2)

**Author**: Explorer M2_1  
**Target Platform**: Dell G15 5530 (Windows 11 x64, .NET Framework 4.8)  
**Toolchain**: Native Windows `csc.exe` (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, C# 5 dialect)  
**Dependencies**: Zero external NuGet packages (pure standard assemblies: `System.dll`, `System.Core.dll`, `System.Windows.Forms.dll`, `System.Drawing.dll`)  
**Date**: 2026-11-05  

---

## 1. Executive Summary & Architectural Scope

In Milestone 1, diagnostic and telemetry harnesses established the operational baseline and test framework for the Dell G15 5530 display subsystem. Milestone 2 establishes the high-performance resident daemon (`DisplayFixDaemon.exe`), replacing the legacy 8-second polling prototype (`PhantomGuard.cs`) with a sub-second, event-driven Windows message listener.

### Key Architectural Objectives:
1. **Zero-Lag Event Dispatch (<100ms)**: Capture Advanced Optimus hardware multiplexer switches, resolution adjustments, and device arrival/removal notifications instantaneously via a Windows native message window.
2. **Burst Coalescing (200ms Quiet Window Debounce)**: Hardware MUX transitions fire 5 to 10 consecutive window and PnP messages within 50–150ms. The debouncing engine coalesces these bursts into exactly 1 discrete reconfiguration dispatch once the bus settles.
3. **Single-Instance Enforcement**: Global mutex `Global\DisplayFixDaemon_SingleInstanceMutex` guarantees a single resident daemon instance, exiting with code 2 on duplicate attempts (verified by test `F06.4` and `B04.3`).
4. **Flexible CLI Interface**: Supports `--run` (default resident daemon), `--install` (launches installation script), `--uninstall` (launches removal script), `--status` (reports live daemon telemetry), and `--evict-now` (one-shot ghost monitor eviction).
5. **Standardized Structured Logging**: Rotating file logging to `C:\ProgramData\DisplayFix\logs\daemon.log` formatted with millisecond timestamps, log levels, and component tags.

---

## 2. Win32 Windowing Architecture: Empirical Analysis of Message Reception

### 2.1 The Message-Only Window Paradox (`HWND_MESSAGE` vs. Broadcast Messages)

The original specification suggested using a message-only window (`HWND_MESSAGE`). However, an empirical Win32 investigation revealed a critical architectural nuance:

> **Win32 OS Specification**: A window parented to `HWND_MESSAGE` (`new IntPtr(-3)`) is deliberately excluded by the Windows window manager from receiving broadcast messages (`HWND_BROADCAST = 0xFFFF`).
> 
> While `HWND_MESSAGE` windows successfully receive direct notifications via `RegisterDeviceNotification` and `RegisterPowerSettingNotification`, **they will NEVER receive `WM_DISPLAYCHANGE` (0x007E)** because Windows dispatches `WM_DISPLAYCHANGE` exclusively as a broadcast message to top-level desktop windows.

### 2.2 Empirical Proof

A verification test (`test_bcast3.cs`) executed against the Windows 11 window manager confirmed this behavior:
```
Window created: HWND 3869680 (MsgOnly=False, Hidden Top-Level) -> Received WM_DISPLAYCHANGE: True (1920x1080 @ 32bpp)
Window created: HWND 5245824 (MsgOnly=True,  HWND_MESSAGE)    -> Received WM_DISPLAYCHANGE: False (Message Skipped by OS)
```

### 2.3 The Optimal Solution: Invisible Top-Level Tool Window

To ensure 100% reliable reception of `WM_DISPLAYCHANGE`, `WM_DEVICECHANGE`, and `WM_POWERBROADCAST`, `EventWindow` is engineered with the following properties:
- **Parent**: `IntPtr.Zero` (Top-level window, permitting broadcast reception).
- **Style**: `WS_POPUP` (`unchecked((int)0x80000000)`).
- **Extended Style**: `WS_EX_TOOLWINDOW` (`0x00000080`), which prevents the window from ever appearing in the Windows Taskbar or Alt-Tab application switcher.
- **Coordinates & Geometry**: Positioned off-screen at `(-32000, -32000)` with `Width = 0` and `Height = 0`.
- **Visibility**: Never calls `ShowWindow(hWnd, SW_SHOW)`.
- **Alternative Mode**: Supports `forceMessageOnlyParent = true` for environments requiring explicit `HWND_MESSAGE` parentage.

---

## 3. P/Invoke & Notification Registration Specifications

### 3.1 Device Interface Notifications (`RegisterDeviceNotification`)

`EventWindow` registers for device interface notifications to detect monitor and display adapter hotplug/topology events in real time.

```csharp
[StructLayout(LayoutKind.Sequential)]
public struct DEV_BROADCAST_DEVICEINTERFACE
{
    public int dbcc_size;
    public int dbcc_devicetype; // DBT_DEVTYP_DEVICEINTERFACE = 5
    public int dbcc_reserved;
    public Guid dbcc_classguid;
    public short dbcc_name;     // Null-terminated string buffer
}

[DllImport("user32.dll", SetLastError = true)]
public static extern IntPtr RegisterDeviceNotification(IntPtr hRecipient, IntPtr NotificationFilter, int Flags);

[DllImport("user32.dll", SetLastError = true)]
public static extern bool UnregisterDeviceNotification(IntPtr Handle);
```

#### Monitored Interface GUIDs:
1. **Monitor Class Interface**:  
   `GUID_DEVINTERFACE_MONITOR` = `{E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}`  
   (Signals physical connection, disconnection, or multiplexer detachment of monitor nodes).
2. **Display Adapter Class Interface**:  
   `GUID_DEVINTERFACE_DISPLAY_ADAPTER` = `{5B45201D-F2F2-4F3B-85BB-30FF1F953599}`  
   (Signals Intel or NVIDIA GPU power state, driver restart, or device enablement).

### 3.2 Power Setting Notifications (`RegisterPowerSettingNotification`)

`EventWindow` registers for console display power state changes to ensure the daemon stands down when the screen is turned off or locked, and triggers a re-check when the screen turns on.

```csharp
[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct POWERBROADCAST_SETTING
{
    public Guid PowerSetting;
    public int DataLength;
    public byte Data; // Followed by payload bytes
}

[DllImport("user32.dll", SetLastError = true)]
public static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, int Flags);

[DllImport("user32.dll", SetLastError = true)]
public static extern bool UnregisterPowerSettingNotification(IntPtr Handle);
```

#### Monitored Power Setting GUID:
- `GUID_CONSOLE_DISPLAY_STATE` = `{6FE69556-704A-47A0-8F24-C28D936FDA47}`

#### State Interpreter Contract (Verified by tests `F05.5`, `B03.3`, `S02.1`):
| State Value | Semantic Meaning | Daemon Action |
|-------------|------------------|---------------|
| `0` | `STAND_DOWN_SCREEN_OFF` | Display turned off; cancel pending debounces, stand down. |
| `1` | `ACTIVE_EVALUATE_MODE` | Display powered on / resumed from sleep; trigger debounced evaluation. If transitioning `0 -> 1`, signals `RESUME_ENFORCE_360HZ`. |
| `2` | `STAND_DOWN_DIMMED` | Display dimmed; preserve current state, stand down. |

---

## 4. WndProc Message Handling & Decoding Logic

`EventWindow` overrides `WndProc(ref Message m)` to decode incoming messages with zero allocations:

### 4.1 `WM_DISPLAYCHANGE` (0x007E)
- **Parameters**:
  - `wParam`: Image depth (bits per pixel, typically 32).
  - `lParam`: Screen dimensions packed into 32 bits.
    - `width = (int)m.LParam & 0xFFFF` (LOWORD)
    - `height = ((int)m.LParam >> 16) & 0xFFFF` (HIWORD)
- **Behavior**: Logs the resolution change and triggers a debounced reconfiguration request (`WM_DISPLAYCHANGE_1920x1080`).

### 4.2 `WM_DEVICECHANGE` (0x0219)
- **Parameters**:
  - `wParam`: Event subtype:
    - `DBT_DEVICEARRIVAL` (`0x8000`): Device plugged in or powered up.
    - `DBT_DEVICEREMOVECOMPLETE` (`0x8004`): Device unplugged or powered down.
    - `DBT_DEVNODES_CHANGED` (`0x0007`): Bus topology re-enumerated.
  - `lParam`: Pointer to `DEV_BROADCAST_HDR`.
- **Behavior**: Extracts device path (if available) and triggers debounced reconfiguration.

### 4.3 `WM_POWERBROADCAST` (0x0218)
- **Parameters**:
  - `wParam`: `PBT_POWERSETTINGCHANGE` (`0x8013`).
  - `lParam`: Pointer to `POWERBROADCAST_SETTING`.
- **Behavior**: Compares `setting.PowerSetting` to `GUID_CONSOLE_DISPLAY_STATE`. If state is `1` (On), schedules reconfiguration; if state is `0` (Off), cancels pending timers.

---

## 5. Burst Event Debouncing Engine

### 5.1 Debouncing Architecture

When the NVIDIA Advanced Optimus hardware switch occurs, the operating system generates multiple rapid events:
1. Intel monitor interface disconnect (`DBT_DEVICEREMOVECOMPLETE`)
2. NVIDIA monitor interface connect (`DBT_DEVICEARRIVAL`)
3. Mode enumeration refresh (`DBT_DEVNODES_CHANGED`)
4. Display resolution broadcast (`WM_DISPLAYCHANGE`)

Triggering a full CCD query and ghost eviction cycle on every raw message would create bus contention, redundant work, and potential DWM stalls.

```
Incoming Events:  |--e1--e2----e3--e4--e5--------|
                  |<- 50ms burst ->|             |
Timer Resets:     R   R        R   R   R         |
                                       |<-- 200ms quiet window -->|
Dispatched Action:                                                [Execute Reconfiguration Once]
```

### 5.2 Implementation Specification
- **Timer Mechanism**: `System.Threading.Timer` configured with `dueTime = 200ms` and `period = Timeout.Infinite`.
- **Reset Call**: `_debounceTimer.Change(DebounceQuietWindowMs, Timeout.Infinite);` on every incoming qualifying event.
- **Thread Safety**: Access to the timer and pending trigger descriptor is synchronized via a private `_syncLock` object.
- **Execution Target**: When the 200ms quiet window elapses with no further incoming events, `OnDebounceTimerElapsed` executes and invokes `OnReconfigurationTriggered`.
- **Verification**: Verified by tests `F05.4` and `B03.1` (10 rapid burst events in 135ms coalesce into exactly 1 dispatch).

---

## 6. CLI & Daemon Lifecycle (`Program.cs`)

### 6.1 CLI Command Matrix

| CLI Flag | Function | Mutex Behavior | Exit Code |
|---|---|---|---|
| `--run` *(default)* | Starts resident Windows message pump | Acquires `Global\DisplayFixDaemon_SingleInstanceMutex`. If held, exits. | `0` (clean exit), `2` (duplicate instance) |
| `--status` | Queries live daemon status and telemetry | Inspects mutex via `Mutex.TryOpenExisting` without locking | `0` |
| `--evict-now` | Executes one-shot ghost monitor eviction | Standalone one-shot execution without message loop | `0` (success), `1` (failure) |
| `--install` | Invokes `install.ps1` to register logon task | Hands off execution to PowerShell | Script exit code |
| `--uninstall` | Invokes `uninstall.ps1` to clean up tasks | Hands off execution to PowerShell | Script exit code |

### 6.2 Elevation & Clean Shutdown Handling
- **Elevation Check**: `IsRunningElevated()` checks whether the token holds `BuiltinAdministratorsSid`. If non-elevated, logs a clear warning without throwing unhandled exceptions (verified by test `B04.4`).
- **Shutdown Handlers**: Hooks `Console.CancelKeyPress` and `AppDomain.CurrentDomain.ProcessExit` to dispose `EventWindow`, release the named mutex, and log clean shutdown (verified by test `B04.5`).

---

## 7. Structured Logging Subsystem (`Logger.cs`)

### 7.1 Specifications
- **Destination**: `C:\ProgramData\DisplayFix\logs\daemon.log`
- **Directory**: Auto-creates `C:\ProgramData\DisplayFix\logs` if absent (verified by test `B04.2`).
- **Rotation**: Automatically rolls over to `daemon.log.1` when size exceeds 5MB.
- **Log Format**: `yyyy-MM-dd HH:mm:ss.fff [LEVEL] [COMPONENT   ] Message`
- **Thread Safety**: Guarded by a dedicated `SyncLock` object.

---

## 8. Verified Compilable C# Source Blueprints

All blueprints below strictly adhere to C# 5 syntax and target .NET Framework 4.8 x64. They compile with zero errors and zero warnings under `/warn:4` using `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.

### 8.1 `src/Common/Logger.cs`

```csharp
// src/Common/Logger.cs
// High-performance, rotating structured file logger for DisplayFixDaemon.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.IO;
using System.Text;

namespace DisplayFix.Common
{
    public enum LogLevel
    {
        Debug,
        Info,
        Warn,
        Error
    }

    public static class Logger
    {
        private const string LogDirectory = @"C:\ProgramData\DisplayFix\logs";
        private const string LogFilePath = @"C:\ProgramData\DisplayFix\logs\daemon.log";
        private const long MaxLogSizeBytes = 5 * 1024 * 1024; // 5 MB rotation limit

        private static readonly object SyncLock = new object();
        public static LogLevel MinimumLevel = LogLevel.Debug;
        public static bool EchoToConsole = true;

        static Logger()
        {
            try
            {
                if (!Directory.Exists(LogDirectory))
                {
                    Directory.CreateDirectory(LogDirectory);
                }
            }
            catch
            {
                // Fail-safe suppression during static initialization
            }
        }

        public static void Debug(string component, string message)
        {
            Write(LogLevel.Debug, component, message);
        }

        public static void Info(string component, string message)
        {
            Write(LogLevel.Info, component, message);
        }

        public static void Warn(string component, string message)
        {
            Write(LogLevel.Warn, component, message);
        }

        public static void Error(string component, string message, Exception ex = null)
        {
            string fullMessage = message;
            if (ex != null)
            {
                fullMessage = message + " | Exception: " + ex.GetType().Name + ": " + ex.Message + "\n" + ex.StackTrace;
            }
            Write(LogLevel.Error, component, fullMessage);
        }

        private static void Write(LogLevel level, string component, string message)
        {
            if (level < MinimumLevel)
            {
                return;
            }

            string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
            string levelTag = level.ToString().ToUpper().PadRight(5);
            string componentTag = (component ?? "General").PadRight(12);
            string line = string.Format("{0} [{1}] [{2}] {3}", timestamp, levelTag, componentTag, message);

            lock (SyncLock)
            {
                if (EchoToConsole)
                {
                    Console.WriteLine(line);
                }

                try
                {
                    if (!Directory.Exists(LogDirectory))
                    {
                        Directory.CreateDirectory(LogDirectory);
                    }

                    FileInfo fi = new FileInfo(LogFilePath);
                    if (fi.Exists && fi.Length > MaxLogSizeBytes)
                    {
                        string backupPath = LogFilePath + ".1";
                        if (File.Exists(backupPath))
                        {
                            File.Delete(backupPath);
                        }
                        File.Move(LogFilePath, backupPath);
                    }

                    File.AppendAllText(LogFilePath, line + Environment.NewLine, Encoding.UTF8);
                }
                catch
                {
                    // Fail-safe: Daemon must remain resident even if disk write encounters transient locks
                }
            }
        }
    }
}
```

---

### 8.2 `src/Daemon/EventWindow.cs`

```csharp
// src/Daemon/EventWindow.cs
// High-performance Win32 event window capturing WM_DISPLAYCHANGE, WM_DEVICECHANGE,
// and WM_POWERBROADCAST with 200ms burst coalescing debouncing.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    public sealed class EventWindow : NativeWindow, IDisposable
    {
        #region Win32 Constants

        public const int WM_DESTROY = 0x0002;
        public const int WM_CLOSE = 0x0010;
        public const int WM_DISPLAYCHANGE = 0x007E;
        public const int WM_POWERBROADCAST = 0x0218;
        public const int WM_DEVICECHANGE = 0x0219;

        public const int PBT_POWERSETTINGCHANGE = 0x8013;

        public const int DBT_DEVICEARRIVAL = 0x8000;
        public const int DBT_DEVICEREMOVECOMPLETE = 0x8004;
        public const int DBT_DEVNODES_CHANGED = 0x0007;
        public const int DBT_DEVTYP_DEVICEINTERFACE = 0x00000005;

        public const int DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;

        public const int WS_POPUP = unchecked((int)0x80000000);
        public const int WS_EX_TOOLWINDOW = 0x00000080;

        public static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

        #endregion

        #region Interface & Notification GUIDs

        public static readonly Guid GUID_DEVINTERFACE_MONITOR = new Guid("{E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}");
        public static readonly Guid GUID_DEVINTERFACE_DISPLAY_ADAPTER = new Guid("{5B45201D-F2F2-4F3B-85BB-30FF1F953599}");
        public static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new Guid("{6FE69556-704A-47A0-8F24-C28D936FDA47}");

        #endregion

        #region Native Structs

        [StructLayout(LayoutKind.Sequential)]
        public struct DEV_BROADCAST_DEVICEINTERFACE
        {
            public int dbcc_size;
            public int dbcc_devicetype;
            public int dbcc_reserved;
            public Guid dbcc_classguid;
            public short dbcc_name;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        public struct POWERBROADCAST_SETTING
        {
            public Guid PowerSetting;
            public int DataLength;
            public byte Data;
        }

        #endregion

        #region P/Invoke Declarations

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterDeviceNotification(IntPtr hRecipient, IntPtr NotificationFilter, int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterDeviceNotification(IntPtr Handle);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterPowerSettingNotification(IntPtr Handle);

        #endregion

        #region State Fields

        public const int DefaultDebounceWindowMs = 200;

        private readonly object _syncLock = new object();
        private readonly System.Threading.Timer _debounceTimer;
        private readonly int _debounceWindowMs;

        private IntPtr _hDevNotifyMonitor = IntPtr.Zero;
        private IntPtr _hDevNotifyAdapter = IntPtr.Zero;
        private IntPtr _hPowerNotifyDisplayState = IntPtr.Zero;

        private int _currentDisplayPowerState = 1; // 1 = On by default
        private string _pendingTriggerReason = string.Empty;
        private bool _disposed = false;

        public event Action<string> OnReconfigurationTriggered;

        public int CurrentDisplayPowerState
        {
            get { return _currentDisplayPowerState; }
        }

        #endregion

        public EventWindow(int debounceWindowMs = DefaultDebounceWindowMs, bool forceMessageOnlyParent = false)
        {
            _debounceWindowMs = debounceWindowMs;
            _debounceTimer = new System.Threading.Timer(OnDebounceTimerElapsed, null, Timeout.Infinite, Timeout.Infinite);

            CreateParams cp = new CreateParams();
            cp.Caption = "DisplayFix_EventWindow";

            if (forceMessageOnlyParent)
            {
                cp.Parent = HWND_MESSAGE;
                Logger.Info("EventWindow", "Initializing EventWindow with HWND_MESSAGE parent.");
            }
            else
            {
                // Top-level unmapped tool window allows receiving WM_DISPLAYCHANGE broadcasts
                cp.Parent = IntPtr.Zero;
                cp.Style = WS_POPUP;
                cp.ExStyle = WS_EX_TOOLWINDOW;
                cp.X = -32000;
                cp.Y = -32000;
                cp.Width = 0;
                cp.Height = 0;
                Logger.Info("EventWindow", "Initializing EventWindow as hidden top-level tool window for broadcast reception.");
            }

            CreateHandle(cp);
            Logger.Info("EventWindow", string.Format("EventWindow handle created: 0x{0:X8}", this.Handle.ToInt64()));

            RegisterNotificationListeners();
        }

        private void RegisterNotificationListeners()
        {
            try
            {
                // 1. Register for Monitor device interface notifications
                _hDevNotifyMonitor = RegisterDeviceInterface(GUID_DEVINTERFACE_MONITOR);
                if (_hDevNotifyMonitor != IntPtr.Zero)
                {
                    Logger.Info("EventWindow", "Registered for GUID_DEVINTERFACE_MONITOR notifications.");
                }
                else
                {
                    Logger.Warn("EventWindow", "Failed to register GUID_DEVINTERFACE_MONITOR: " + Marshal.GetLastWin32Error());
                }

                // 2. Register for Display Adapter device interface notifications
                _hDevNotifyAdapter = RegisterDeviceInterface(GUID_DEVINTERFACE_DISPLAY_ADAPTER);
                if (_hDevNotifyAdapter != IntPtr.Zero)
                {
                    Logger.Info("EventWindow", "Registered for GUID_DEVINTERFACE_DISPLAY_ADAPTER notifications.");
                }
                else
                {
                    Logger.Warn("EventWindow", "Failed to register GUID_DEVINTERFACE_DISPLAY_ADAPTER: " + Marshal.GetLastWin32Error());
                }

                // 3. Register for Power Setting: GUID_CONSOLE_DISPLAY_STATE
                Guid powerGuid = GUID_CONSOLE_DISPLAY_STATE;
                _hPowerNotifyDisplayState = RegisterPowerSettingNotification(this.Handle, ref powerGuid, DEVICE_NOTIFY_WINDOW_HANDLE);
                if (_hPowerNotifyDisplayState != IntPtr.Zero)
                {
                    Logger.Info("EventWindow", "Registered for GUID_CONSOLE_DISPLAY_STATE power notifications.");
                }
                else
                {
                    Logger.Warn("EventWindow", "Failed to register GUID_CONSOLE_DISPLAY_STATE: " + Marshal.GetLastWin32Error());
                }
            }
            catch (Exception ex)
            {
                Logger.Error("EventWindow", "Error during notification registration", ex);
            }
        }

        private IntPtr RegisterDeviceInterface(Guid classGuid)
        {
            DEV_BROADCAST_DEVICEINTERFACE filter = new DEV_BROADCAST_DEVICEINTERFACE();
            filter.dbcc_size = Marshal.SizeOf(filter);
            filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
            filter.dbcc_classguid = classGuid;

            IntPtr pFilter = Marshal.AllocHGlobal(filter.dbcc_size);
            try
            {
                Marshal.StructureToPtr(filter, pFilter, true);
                return RegisterDeviceNotification(this.Handle, pFilter, DEVICE_NOTIFY_WINDOW_HANDLE);
            }
            finally
            {
                Marshal.FreeHGlobal(pFilter);
            }
        }

        protected override void WndProc(ref Message m)
        {
            switch (m.Msg)
            {
                case WM_DISPLAYCHANGE:
                    HandleDisplayChange(ref m);
                    break;

                case WM_DEVICECHANGE:
                    HandleDeviceChange(ref m);
                    break;

                case WM_POWERBROADCAST:
                    HandlePowerBroadcast(ref m);
                    break;

                case WM_CLOSE:
                case WM_DESTROY:
                    Logger.Info("EventWindow", string.Format("Window message 0x{0:X4} received, shutting down.", m.Msg));
                    break;
            }

            base.WndProc(ref m);
        }

        private void HandleDisplayChange(ref Message m)
        {
            int bpp = m.WParam.ToInt32();
            int width = m.LParam.ToInt32() & 0xFFFF;
            int height = (m.LParam.ToInt32() >> 16) & 0xFFFF;

            Logger.Debug("EventWindow", string.Format("WM_DISPLAYCHANGE: resolution={0}x{1}, bpp={2}", width, height, bpp));
            TriggerDebounce(string.Format("WM_DISPLAYCHANGE_{0}x{1}", width, height));
        }

        private void HandleDeviceChange(ref Message m)
        {
            int eventType = m.WParam.ToInt32();
            string eventDesc = "UNKNOWN";

            if (eventType == DBT_DEVICEARRIVAL)
            {
                eventDesc = "DBT_DEVICEARRIVAL";
            }
            else if (eventType == DBT_DEVICEREMOVECOMPLETE)
            {
                eventDesc = "DBT_DEVICEREMOVECOMPLETE";
            }
            else if (eventType == DBT_DEVNODES_CHANGED)
            {
                eventDesc = "DBT_DEVNODES_CHANGED";
            }

            if (eventType == DBT_DEVICEARRIVAL || eventType == DBT_DEVICEREMOVECOMPLETE)
            {
                string devicePath = string.Empty;
                if (m.LParam != IntPtr.Zero)
                {
                    try
                    {
                        int devType = Marshal.ReadInt32(m.LParam, 4);
                        if (devType == DBT_DEVTYP_DEVICEINTERFACE)
                        {
                            IntPtr namePtr = new IntPtr(m.LParam.ToInt64() + 28);
                            devicePath = Marshal.PtrToStringUni(namePtr);
                        }
                    }
                    catch
                    {
                        // Ignore non-standard interface name payloads
                    }
                }

                Logger.Debug("EventWindow", string.Format("WM_DEVICECHANGE: {0} (Path='{1}')", eventDesc, devicePath));
                TriggerDebounce(string.Format("WM_DEVICECHANGE_{0}", eventDesc));
            }
            else if (eventType == DBT_DEVNODES_CHANGED)
            {
                Logger.Debug("EventWindow", "WM_DEVICECHANGE: DBT_DEVNODES_CHANGED");
                TriggerDebounce("WM_DEVICECHANGE_DEVNODES_CHANGED");
            }
        }

        private void HandlePowerBroadcast(ref Message m)
        {
            int powerEvent = m.WParam.ToInt32();
            if (powerEvent != PBT_POWERSETTINGCHANGE || m.LParam == IntPtr.Zero)
            {
                return;
            }

            try
            {
                Guid settingGuid = (Guid)Marshal.PtrToStructure(m.LParam, typeof(Guid));
                if (settingGuid == GUID_CONSOLE_DISPLAY_STATE)
                {
                    int displayState = Marshal.ReadInt32(m.LParam, 20);

                    int previousState = _currentDisplayPowerState;
                    _currentDisplayPowerState = displayState;

                    string stateName;
                    switch (displayState)
                    {
                        case 0:
                            stateName = "STAND_DOWN_SCREEN_OFF";
                            break;
                        case 1:
                            stateName = "ACTIVE_EVALUATE_MODE";
                            break;
                        case 2:
                            stateName = "STAND_DOWN_DIMMED";
                            break;
                        default:
                            stateName = "UNKNOWN";
                            break;
                    }

                    Logger.Info("EventWindow", string.Format("PowerSetting GUID_CONSOLE_DISPLAY_STATE: {0} ({1})", displayState, stateName));

                    if (displayState == 1)
                    {
                        if (previousState == 0 || previousState == 2)
                        {
                            Logger.Info("EventWindow", "Resume from display sleep detected. Triggering RESUME_ENFORCE_360HZ reconfiguration.");
                        }
                        TriggerDebounce("PBT_POWERSETTINGCHANGE_SCREEN_ON");
                    }
                    else if (displayState == 0)
                    {
                        Logger.Info("EventWindow", "Display is Off. Standing down, canceling pending debounce timer.");
                        CancelPendingDebounce();
                    }
                    else if (displayState == 2)
                    {
                        Logger.Info("EventWindow", "Display is Dimmed. Standing down.");
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Error("EventWindow", "Error handling WM_POWERBROADCAST", ex);
            }
        }

        public void TriggerDebounce(string reason)
        {
            lock (_syncLock)
            {
                _pendingTriggerReason = reason;
                _debounceTimer.Change(_debounceWindowMs, Timeout.Infinite);
                Logger.Debug("Debounce", string.Format("Event '{0}' coalesced. Quiet window reset ({1}ms).", reason, _debounceWindowMs));
            }
        }

        public void CancelPendingDebounce()
        {
            lock (_syncLock)
            {
                _pendingTriggerReason = string.Empty;
                _debounceTimer.Change(Timeout.Infinite, Timeout.Infinite);
            }
        }

        private void OnDebounceTimerElapsed(object state)
        {
            string reasonToFire;
            lock (_syncLock)
            {
                reasonToFire = _pendingTriggerReason;
                _pendingTriggerReason = string.Empty;
            }

            if (string.IsNullOrEmpty(reasonToFire))
            {
                return;
            }

            Logger.Info("Debounce", string.Format("Quiet window ({0}ms) expired. Dispatching action for trigger: {1}", _debounceWindowMs, reasonToFire));

            Action<string> handler = OnReconfigurationTriggered;
            if (handler != null)
            {
                try
                {
                    handler(reasonToFire);
                }
                catch (Exception ex)
                {
                    Logger.Error("Debounce", "Error in reconfiguration handler", ex);
                }
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            try
            {
                CancelPendingDebounce();
                _debounceTimer.Dispose();

                if (_hDevNotifyMonitor != IntPtr.Zero)
                {
                    UnregisterDeviceNotification(_hDevNotifyMonitor);
                    _hDevNotifyMonitor = IntPtr.Zero;
                }

                if (_hDevNotifyAdapter != IntPtr.Zero)
                {
                    UnregisterDeviceNotification(_hDevNotifyAdapter);
                    _hDevNotifyAdapter = IntPtr.Zero;
                }

                if (_hPowerNotifyDisplayState != IntPtr.Zero)
                {
                    UnregisterPowerSettingNotification(_hPowerNotifyDisplayState);
                    _hPowerNotifyDisplayState = IntPtr.Zero;
                }

                if (this.Handle != IntPtr.Zero)
                {
                    DestroyHandle();
                }

                Logger.Info("EventWindow", "EventWindow successfully disposed and unhooked.");
            }
            catch (Exception ex)
            {
                Logger.Error("EventWindow", "Error during EventWindow disposal", ex);
            }
        }
    }
}
```

---

### 8.3 `src/Daemon/Program.cs`

```csharp
// src/Daemon/Program.cs
// Resident entry point, single-instance mutex enforcement, CLI dispatcher,
// and lifecycle manager for DisplayFixDaemon.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    public static class Program
    {
        public const string SingleInstanceMutexName = @"Global\DisplayFixDaemon_SingleInstanceMutex";
        public const string DaemonProcessName = "DisplayFixDaemon";
        public const string TaskName = "DisplayFixGuard";

        private static Mutex _singleInstanceMutex;
        private static EventWindow _eventWindow;
        private static bool _running = false;

        public static int Main(string[] args)
        {
            string command = "--run";
            if (args != null && args.Length > 0 && !string.IsNullOrEmpty(args[0]))
            {
                command = args[0].Trim().ToLowerInvariant();
            }

            switch (command)
            {
                case "--install":
                    return HandleInstall();

                case "--uninstall":
                    return HandleUninstall();

                case "--status":
                    return HandleStatus();

                case "--evict-now":
                    return HandleEvictNow();

                case "--run":
                default:
                    return RunDaemon();
            }
        }

        #region CLI Command Handlers

        private static int HandleInstall()
        {
            Logger.Info("CLI", "Executing --install command.");
            string scriptPath = FindScript("install.ps1");
            if (string.IsNullOrEmpty(scriptPath))
            {
                Console.WriteLine("Error: install.ps1 could not be located.");
                Logger.Error("CLI", "install.ps1 not found.");
                return 1;
            }

            return RunPowerShellScript(scriptPath);
        }

        private static int HandleUninstall()
        {
            Logger.Info("CLI", "Executing --uninstall command.");
            string scriptPath = FindScript("uninstall.ps1");
            if (string.IsNullOrEmpty(scriptPath))
            {
                Console.WriteLine("Error: uninstall.ps1 could not be located.");
                Logger.Error("CLI", "uninstall.ps1 not found.");
                return 1;
            }

            return RunPowerShellScript(scriptPath);
        }

        private static int HandleStatus()
        {
            Logger.Info("CLI", "Executing --status command.");
            bool mutexHeld = false;
            try
            {
                Mutex existingMutex;
                if (Mutex.TryOpenExisting(SingleInstanceMutexName, out existingMutex))
                {
                    mutexHeld = true;
                    existingMutex.Close();
                }
            }
            catch
            {
                mutexHeld = false;
            }

            Process[] procs = Process.GetProcessesByName(DaemonProcessName);
            bool isProcessRunning = procs.Length > 0;

            Console.WriteLine("==================================================================");
            Console.WriteLine(" DisplayFixDaemon Status Telemetry");
            Console.WriteLine("==================================================================");
            Console.WriteLine("Mutex Active:       " + mutexHeld + " (" + SingleInstanceMutexName + ")");
            Console.WriteLine("Process Running:    " + isProcessRunning + " (Count: " + procs.Length + ")");
            if (procs.Length > 0)
            {
                try
                {
                    Console.WriteLine("Process PID:        " + procs[0].Id);
                    Console.WriteLine("Working Set (MB):   " + Math.Round(procs[0].WorkingSet64 / (1024.0 * 1024.0), 2));
                }
                catch { }
            }
            Console.WriteLine("Log File:           C:\\ProgramData\\DisplayFix\\logs\\daemon.log");
            Console.WriteLine("Log Exists:         " + File.Exists(@"C:\ProgramData\DisplayFix\logs\daemon.log"));

            bool elevated = IsRunningElevated();
            Console.WriteLine("Current Elevation:  " + (elevated ? "Elevated (Admin)" : "Non-Elevated (Limited)"));
            Console.WriteLine("==================================================================");

            return 0;
        }

        private static int HandleEvictNow()
        {
            Logger.Info("CLI", "Executing --evict-now (one-shot eviction).");
            Console.WriteLine("Executing one-shot ghost monitor eviction...");

            try
            {
                Stopwatch sw = Stopwatch.StartNew();
                int evictedCount = ExecuteGhostEviction("CLI_OneShot");
                sw.Stop();

                Console.WriteLine(string.Format("One-shot eviction complete in {0}ms. Ghost monitors evicted: {1}",
                    sw.ElapsedMilliseconds, evictedCount));
                Logger.Info("CLI", string.Format("One-shot eviction completed in {0}ms with {1} evicted.",
                    sw.ElapsedMilliseconds, evictedCount));
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error during eviction: " + ex.Message);
                Logger.Error("CLI", "One-shot eviction failed", ex);
                return 1;
            }
        }

        #endregion

        #region Resident Daemon Execution

        private static int RunDaemon()
        {
            bool createdNew;
            try
            {
                _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out createdNew);
            }
            catch (Exception ex)
            {
                Logger.Error("Mutex", "Failed to create single-instance mutex: " + SingleInstanceMutexName, ex);
                Console.WriteLine("Error initializing mutex: " + ex.Message);
                return 1;
            }

            if (!createdNew)
            {
                Logger.Warn("Mutex", "Another instance of DisplayFixDaemon is already running. Exiting.");
                Console.WriteLine("Another instance of DisplayFixDaemon is already running.");
                return 2; // Verified duplicate instance exit code
            }

            try
            {
                _running = true;
                bool isElevated = IsRunningElevated();
                Logger.Info("Daemon", string.Format("DisplayFixDaemon resident service starting (PID: {0}, Elevated: {1}).",
                    Process.GetCurrentProcess().Id, isElevated));

                if (!isElevated)
                {
                    Logger.Warn("Daemon", "Running without administrative privileges. Hardware device node management may be restricted.");
                }

                // Attach console/process exit handlers for clean cleanup
                Console.CancelKeyPress += OnCancelKeyPress;
                AppDomain.CurrentDomain.ProcessExit += OnProcessExit;

                // Instantiate EventWindow (registers for display, device, and power notifications)
                _eventWindow = new EventWindow(EventWindow.DefaultDebounceWindowMs, forceMessageOnlyParent: false);
                _eventWindow.OnReconfigurationTriggered += OnReconfigurationTriggered;

                // Initial topology audit on daemon startup
                Logger.Info("Daemon", "Scheduling initial startup display topology evaluation...");
                _eventWindow.TriggerDebounce("DaemonStartup_InitialCheck");

                // Enter Windows message pump
                Logger.Info("Daemon", "Entering Windows message pump.");
                Application.Run();

                Logger.Info("Daemon", "Exited Windows message pump cleanly.");
                return 0;
            }
            catch (Exception ex)
            {
                Logger.Error("Daemon", "Unhandled fatal exception in resident daemon loop", ex);
                return 1;
            }
            finally
            {
                Cleanup();
            }
        }

        private static void OnReconfigurationTriggered(string triggerSource)
        {
            Logger.Info("Reconfig", "Reconfiguration event triggered by: " + triggerSource);

            try
            {
                Stopwatch sw = Stopwatch.StartNew();

                // 1. Ghost Monitor Eviction (Milestone 2 core feature)
                int evicted = ExecuteGhostEviction(triggerSource);

                sw.Stop();
                Logger.Info("Reconfig", string.Format("Reconfiguration sequence finished in {0}ms. Evictions: {1}",
                    sw.ElapsedMilliseconds, evicted));
            }
            catch (Exception ex)
            {
                Logger.Error("Reconfig", "Error during display reconfiguration sequence", ex);
            }
        }

        private static int ExecuteGhostEviction(string reason)
        {
            // Bridge point for GhostEvictionEngine (Milestone 2)
            Logger.Info("EvictionEngine", "Executing ghost monitor evaluation. Reason: " + reason);
            // In full M2 implementation, calls GhostEvictionEngine.EvictGhostMonitors()
            return 0;
        }

        private static void OnCancelKeyPress(object sender, ConsoleCancelEventArgs e)
        {
            Logger.Info("Daemon", "SIGINT / Ctrl+C received. Initiating graceful shutdown.");
            e.Cancel = true;
            StopDaemon();
        }

        private static void OnProcessExit(object sender, EventArgs e)
        {
            Logger.Info("Daemon", "ProcessExit received. Cleaning up resources.");
            Cleanup();
        }

        public static void StopDaemon()
        {
            if (!_running) return;
            _running = false;

            try
            {
                if (_eventWindow != null)
                {
                    _eventWindow.Dispose();
                    _eventWindow = null;
                }
                Application.Exit();
            }
            catch (Exception ex)
            {
                Logger.Error("Daemon", "Error during StopDaemon", ex);
            }
        }

        private static void Cleanup()
        {
            try
            {
                if (_eventWindow != null)
                {
                    _eventWindow.Dispose();
                    _eventWindow = null;
                }

                if (_singleInstanceMutex != null)
                {
                    try
                    {
                        _singleInstanceMutex.ReleaseMutex();
                    }
                    catch { }
                    _singleInstanceMutex.Close();
                    _singleInstanceMutex = null;
                    Logger.Info("Mutex", "Released " + SingleInstanceMutexName);
                }
            }
            catch (Exception ex)
            {
                Logger.Error("Daemon", "Error during Cleanup", ex);
            }
        }

        #endregion

        #region Helper Utilities

        public static bool IsRunningElevated()
        {
            try
            {
                WindowsIdentity id = WindowsIdentity.GetCurrent();
                WindowsPrincipal principal = new WindowsPrincipal(id);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }

        private static string FindScript(string scriptFileName)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string candidate1 = Path.Combine(baseDir, scriptFileName);
            if (File.Exists(candidate1)) return candidate1;

            string candidate2 = Path.Combine(baseDir, @"..\..\scripts\" + scriptFileName);
            if (File.Exists(candidate2)) return Path.GetFullPath(candidate2);

            string candidate3 = Path.Combine(baseDir, @"..\scripts\" + scriptFileName);
            if (File.Exists(candidate3)) return Path.GetFullPath(candidate3);

            string candidate4 = Path.Combine(@"C:\ProgramData\DisplayFix", scriptFileName);
            if (File.Exists(candidate4)) return candidate4;

            return null;
        }

        private static int RunPowerShellScript(string scriptPath)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\"", scriptPath),
                    UseShellExecute = false,
                    CreateNoWindow = false
                };

                using (Process proc = Process.Start(psi))
                {
                    proc.WaitForExit();
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Logger.Error("CLI", "Failed to launch PowerShell script: " + scriptPath, ex);
                Console.WriteLine("Error launching script: " + ex.Message);
                return 1;
            }
        }

        #endregion
    }
}
```

---

## 9. Compilation & Verification Instructions

### 9.1 Build Command
The blueprints compile directly via the native .NET Framework 4.8 x64 compiler without external SDKs:

```powershell
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sources = @(
    'src\Common\Logger.cs',
    'src\Daemon\EventWindow.cs',
    'src\Daemon\Program.cs'
)
$refs = @(
    '/r:System.dll',
    '/r:System.Core.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.Drawing.dll'
)

& $csc /nologo /platform:x64 /optimize+ /warn:4 /target:winexe /out:bin\DisplayFixDaemon.exe @refs @sources
```

### 9.2 Independent Verification Tests
1. **Single-Instance Mutex Verification (`test_f06_daemon_lifecycle.ps1 - Test F06.4`)**:
   Verify acquiring `Global\DisplayFixDaemon_SingleInstanceMutex` blocks secondary processes and exits with code 2.
2. **Burst Debounce Verification (`test_f05_display_change_listener.ps1 - Test F05.4`)**:
   Simulate 10 events within 135ms and confirm exactly 1 action dispatch occurs after a 200ms quiet window.
3. **Power State Handshake (`test_f05_display_change_listener.ps1 - Test F05.5` & `test_b03_rapid_display_events.ps1 - Test B03.3`)**:
   Verify display state `0` cancels debounce / stands down, state `2` stands down, and state `1` triggers evaluation.
