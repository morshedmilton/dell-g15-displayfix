// src/Daemon/EventWindow.cs
// High-performance Win32 event window capturing WM_DISPLAYCHANGE, WM_DEVICECHANGE,
// and WM_POWERBROADCAST with 200ms burst coalescing debouncing and unified 3-stage
// Milestone 3 reconfiguration pipeline (<100ms total latency budget).
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using DisplayFix.Brightness;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    /// <summary>
    /// Telemetry record for a single execution of the unified 3-stage display reconfiguration pipeline.
    /// </summary>
    public sealed class ReconfigurationPipelineResult
    {
        public string TriggerReason { get; set; }
        public int GhostMonitorsEvicted { get; set; }
        public string EvictionMessage { get; set; }
        public double Step1EvictionMs { get; set; }

        public bool RefreshRateEnforced { get; set; }
        public double Step2RefreshRateMs { get; set; }

        public bool DpiScalingSynchronized { get; set; }
        public double Step3DpiSyncMs { get; set; }

        public double TotalElapsedMs { get; set; }

        public override string ToString()
        {
            return string.Format(
                "Trigger='{0}', Total={1:F2}ms [Step1_Evict={2} ({3:F2}ms), Step2_360Hz={4} ({5:F2}ms), Step3_125Dpi={6} ({7:F2}ms)]",
                TriggerReason,
                TotalElapsedMs,
                GhostMonitorsEvicted,
                Step1EvictionMs,
                RefreshRateEnforced,
                Step2RefreshRateMs,
                DpiScalingSynchronized,
                Step3DpiSyncMs);
        }
    }

    public sealed class EventWindow : NativeWindow, IDisposable
    {
        #region State Fields

        public const int DefaultDebounceWindowMs = 200;
        public const double PipelineLatencyBudgetMs = 100.0;

        private static readonly object _pipelineExecutionLock = new object();

        private readonly object _syncLock = new object();
        private readonly System.Threading.Timer _debounceTimer;
        private readonly int _debounceWindowMs;

        private IntPtr _hDevNotifyMonitor = IntPtr.Zero;
        private IntPtr _hDevNotifyAdapter = IntPtr.Zero;
        private IntPtr _hPowerNotifyDisplayState = IntPtr.Zero;

        private int _currentDisplayPowerState = 1; // 1 = On by default
        private string _pendingTriggerReason = string.Empty;
        private bool _disposed = false;
        private ReconfigurationPipelineResult _lastPipelineResult;
        private HotkeyHook _attachedHotkeyHook;

        public event Action<string> OnReconfigurationTriggered;

        public HotkeyHook AttachedHotkeyHook
        {
            get { return _attachedHotkeyHook; }
            set { _attachedHotkeyHook = value; }
        }

        public int CurrentDisplayPowerState
        {
            get { return _currentDisplayPowerState; }
        }

        public ReconfigurationPipelineResult LastPipelineResult
        {
            get { return _lastPipelineResult; }
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
                cp.Parent = Interop.HWND_MESSAGE;
                Logger.Info("EventWindow", "Initializing EventWindow with HWND_MESSAGE parent.");
            }
            else
            {
                // Top-level unmapped tool window allows receiving WM_DISPLAYCHANGE broadcasts
                cp.Parent = IntPtr.Zero;
                cp.Style = Interop.WS_POPUP;
                cp.ExStyle = Interop.WS_EX_TOOLWINDOW;
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
                _hDevNotifyMonitor = RegisterDeviceInterface(Interop.GUID_DEVINTERFACE_MONITOR);
                if (_hDevNotifyMonitor != IntPtr.Zero)
                {
                    Logger.Info("EventWindow", "Registered for GUID_DEVINTERFACE_MONITOR notifications.");
                }
                else
                {
                    Logger.Warn("EventWindow", "Failed to register GUID_DEVINTERFACE_MONITOR: " + Marshal.GetLastWin32Error());
                }

                // 2. Register for Display Adapter device interface notifications
                _hDevNotifyAdapter = RegisterDeviceInterface(Interop.GUID_DEVINTERFACE_DISPLAY_ADAPTER);
                if (_hDevNotifyAdapter != IntPtr.Zero)
                {
                    Logger.Info("EventWindow", "Registered for GUID_DEVINTERFACE_DISPLAY_ADAPTER notifications.");
                }
                else
                {
                    Logger.Warn("EventWindow", "Failed to register GUID_DEVINTERFACE_DISPLAY_ADAPTER: " + Marshal.GetLastWin32Error());
                }

                // 3. Register for Power Setting: GUID_CONSOLE_DISPLAY_STATE
                Guid powerGuid = Interop.GUID_CONSOLE_DISPLAY_STATE;
                _hPowerNotifyDisplayState = Interop.RegisterPowerSettingNotification(this.Handle, ref powerGuid, Interop.DEVICE_NOTIFY_WINDOW_HANDLE);
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
            Interop.DEV_BROADCAST_DEVICEINTERFACE filter = new Interop.DEV_BROADCAST_DEVICEINTERFACE();
            filter.dbcc_size = Marshal.SizeOf(filter);
            filter.dbcc_devicetype = Interop.DBT_DEVTYP_DEVICEINTERFACE;
            filter.dbcc_classguid = classGuid;

            IntPtr pFilter = Marshal.AllocHGlobal(filter.dbcc_size);
            try
            {
                Marshal.StructureToPtr(filter, pFilter, true);
                return Interop.RegisterDeviceNotification(this.Handle, pFilter, Interop.DEVICE_NOTIFY_WINDOW_HANDLE);
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
                case Interop.WM_DISPLAYCHANGE:
                    HandleDisplayChange(ref m);
                    break;

                case Interop.WM_DEVICECHANGE:
                    HandleDeviceChange(ref m);
                    break;

                case Interop.WM_POWERBROADCAST:
                    HandlePowerBroadcast(ref m);
                    break;

                case Interop.WM_INPUT:
                    if (_attachedHotkeyHook != null)
                    {
                        _attachedHotkeyHook.ProcessRawInputMessage(m.LParam);
                    }
                    break;

                case Interop.WM_CLOSE:
                case Interop.WM_DESTROY:
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
            BrightnessController.BeginDisplayTransition();
            TriggerDebounce(string.Format("WM_DISPLAYCHANGE_{0}x{1}", width, height));
        }

        private void HandleDeviceChange(ref Message m)
        {
            int eventType = m.WParam.ToInt32();
            string eventDesc = "UNKNOWN";

            if (eventType == Interop.DBT_DEVICEARRIVAL)
            {
                eventDesc = "DBT_DEVICEARRIVAL";
            }
            else if (eventType == Interop.DBT_DEVICEREMOVECOMPLETE)
            {
                eventDesc = "DBT_DEVICEREMOVECOMPLETE";
            }
            else if (eventType == Interop.DBT_DEVNODES_CHANGED)
            {
                eventDesc = "DBT_DEVNODES_CHANGED";
            }

            if (eventType == Interop.DBT_DEVICEARRIVAL || eventType == Interop.DBT_DEVICEREMOVECOMPLETE)
            {
                string devicePath = string.Empty;
                if (m.LParam != IntPtr.Zero)
                {
                    try
                    {
                        int devType = Marshal.ReadInt32(m.LParam, 4);
                        if (devType == Interop.DBT_DEVTYP_DEVICEINTERFACE)
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
                BrightnessController.BeginDisplayTransition();
                TriggerDebounce(string.Format("WM_DEVICECHANGE_{0}", eventDesc));
            }
            else if (eventType == Interop.DBT_DEVNODES_CHANGED)
            {
                Logger.Debug("EventWindow", "WM_DEVICECHANGE: DBT_DEVNODES_CHANGED");
                BrightnessController.BeginDisplayTransition();
                TriggerDebounce("WM_DEVICECHANGE_DEVNODES_CHANGED");
            }
        }

        private void HandlePowerBroadcast(ref Message m)
        {
            int powerEvent = m.WParam.ToInt32();
            if (powerEvent != Interop.PBT_POWERSETTINGCHANGE || m.LParam == IntPtr.Zero)
            {
                return;
            }

            try
            {
                Guid settingGuid = (Guid)Marshal.PtrToStructure(m.LParam, typeof(Guid));
                if (settingGuid == Interop.GUID_CONSOLE_DISPLAY_STATE)
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

        /// <summary>
        /// Executes the unified 3-stage Milestone 3 Display Reconfiguration Pipeline:
        ///   Step 1: In-process ghost monitor eviction (GhostEvictionEngine.CheckAndEvict())
        ///   Step 2: 360Hz refresh rate lock enforcement (RefreshRateLock.Enforce360Hz())
        ///   Step 3: 125% DPI scaling synchronization (ScalingSynchronizer.Enforce125())
        /// Total latency budget: &lt; 100ms.
        /// </summary>
        public static ReconfigurationPipelineResult ExecuteReconfigurationPipeline(string triggerReason)
        {
            lock (_pipelineExecutionLock)
            {
                Stopwatch swTotal = Stopwatch.StartNew();
                ReconfigurationPipelineResult result = new ReconfigurationPipelineResult();
                result.TriggerReason = triggerReason ?? "Manual";

                // Step 1: In-process ghost monitor eviction
                Stopwatch swStep1 = Stopwatch.StartNew();
                try
                {
                    GhostEvictionResult evictRes = GhostEvictionEngine.CheckAndEvict();
                    result.GhostMonitorsEvicted = evictRes.EvictedCount;
                    result.EvictionMessage = evictRes.Message;
                }
                catch (Exception ex1)
                {
                    result.EvictionMessage = "Exception: " + ex1.Message;
                    Logger.Error("Pipeline", "Step 1 (GhostEvictionEngine.CheckAndEvict) failed", ex1);
                }
                swStep1.Stop();
                result.Step1EvictionMs = swStep1.Elapsed.TotalMilliseconds;

                // Step 2: 360Hz refresh rate lock enforcement
                Stopwatch swStep2 = Stopwatch.StartNew();
                try
                {
                    result.RefreshRateEnforced = RefreshRateLock.Enforce360Hz();
                }
                catch (Exception ex2)
                {
                    result.RefreshRateEnforced = false;
                    Logger.Error("Pipeline", "Step 2 (RefreshRateLock.Enforce360Hz) failed", ex2);
                }
                swStep2.Stop();
                result.Step2RefreshRateMs = swStep2.Elapsed.TotalMilliseconds;

                // Step 3: 125% DPI scaling synchronization (Registry + CCD)
                Stopwatch swStep3 = Stopwatch.StartNew();
                try
                {
                    result.DpiScalingSynchronized = ScalingSynchronizer.Enforce125();
                }
                catch (Exception ex3)
                {
                    result.DpiScalingSynchronized = false;
                    Logger.Error("Pipeline", "Step 3 (ScalingSynchronizer.Enforce125) failed", ex3);
                }
                swStep3.Stop();
                result.Step3DpiSyncMs = swStep3.Elapsed.TotalMilliseconds;

                // Step 4: Brightness transition synchronization (C03)
                try
                {
                    BrightnessController.CompleteDisplayTransitionIfActive(result.GhostMonitorsEvicted > 0);
                }
                catch (Exception ex4)
                {
                    Logger.Error("Pipeline", "Step 4 (BrightnessController.CompleteDisplayTransitionIfActive) failed", ex4);
                }

                swTotal.Stop();
                result.TotalElapsedMs = swTotal.Elapsed.TotalMilliseconds;

                if (result.TotalElapsedMs <= PipelineLatencyBudgetMs)
                {
                    Logger.Info("Pipeline", string.Format("Unified pipeline completed within budget ({0:F2}ms <= {1:F0}ms): {2}",
                        result.TotalElapsedMs, PipelineLatencyBudgetMs, result.ToString()));
                }
                else
                {
                    Logger.Warn("Pipeline", string.Format("Unified pipeline exceeded {0:F0}ms budget ({1:F2}ms): {2}",
                        PipelineLatencyBudgetMs, result.TotalElapsedMs, result.ToString()));
                }

                return result;
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

            if (_currentDisplayPowerState == 0)
            {
                Logger.Info("Debounce", string.Format("Skipping reconfiguration for '{0}' because display is currently OFF.", reasonToFire));
                return;
            }

            Logger.Info("Debounce", string.Format("Quiet window ({0}ms) expired. Dispatching unified pipeline for trigger: {1}", _debounceWindowMs, reasonToFire));

            // Execute the unified 3-stage pipeline (Step 1: Evict, Step 2: 360Hz, Step 3: 125% DPI)
            _lastPipelineResult = ExecuteReconfigurationPipeline(reasonToFire);

            // Notify registered listeners (e.g., Program.cs or E2E test collectors)
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
                    Interop.UnregisterDeviceNotification(_hDevNotifyMonitor);
                    _hDevNotifyMonitor = IntPtr.Zero;
                }

                if (_hDevNotifyAdapter != IntPtr.Zero)
                {
                    Interop.UnregisterDeviceNotification(_hDevNotifyAdapter);
                    _hDevNotifyAdapter = IntPtr.Zero;
                }

                if (_hPowerNotifyDisplayState != IntPtr.Zero)
                {
                    Interop.UnregisterPowerSettingNotification(_hPowerNotifyDisplayState);
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
