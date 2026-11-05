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

        #region Standard Interface GUIDs

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

        #region P/Invoke Imports

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterDeviceNotification(IntPtr hRecipient, IntPtr NotificationFilter, int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterDeviceNotification(IntPtr Handle);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterPowerSettingNotification(IntPtr Handle);

        #endregion

        #region Fields and Properties

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
                // HWND_MESSAGE parent: receives direct notifications but Windows skips broadcast WM_DISPLAYCHANGE
                cp.Parent = HWND_MESSAGE;
                Logger.Info("EventWindow", "Initializing EventWindow with HWND_MESSAGE parent.");
            }
            else
            {
                // Invisible top-level tool window: receives all broadcast messages (WM_DISPLAYCHANGE)
                // without showing in taskbar or Alt-Tab
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
                        // Ignore parsing errors for custom device broadcast packets
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
                    int dataLength = Marshal.ReadInt32(m.LParam, 16);
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
                        // Screen turned on / resumed from sleep
                        if (previousState == 0 || previousState == 2)
                        {
                            Logger.Info("EventWindow", "Resume from display sleep detected. Triggering RESUME_ENFORCE_360HZ reconfiguration.");
                        }
                        TriggerDebounce("PBT_POWERSETTINGCHANGE_SCREEN_ON");
                    }
                    else if (displayState == 0)
                    {
                        // Screen off: stand down and cancel non-essential pending debounces
                        Logger.Info("EventWindow", "Display is Off. Standing down, canceling pending debounce timer.");
                        CancelPendingDebounce();
                    }
                    else if (displayState == 2)
                    {
                        // Dimmed: stand down
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
                // Reset the timer to fire after the quiet window has elapsed
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
