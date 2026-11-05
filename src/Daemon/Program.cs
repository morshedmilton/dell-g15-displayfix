// src/Daemon/Program.cs
// Resident entry point, single-instance mutex enforcement, CLI dispatcher,
// and lifecycle manager for DisplayFixDaemon.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using DisplayFix.Brightness;
using DisplayFix.Common;

namespace DisplayFix.Common
{
    public enum LogLevel
    {
        Debug,
        Info,
        Warn,
        Error
    }

    /// <summary>
    /// High-performance rotating structured file logger for DisplayFixDaemon.
    /// Writes to C:\ProgramData\DisplayFix\logs\daemon.log with 5MB rotation.
    /// </summary>
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

namespace DisplayFix.Daemon
{
    public static class Program
    {
        public const string SingleInstanceMutexName = @"Global\DisplayFixDaemon_SingleInstanceMutex";
        public const string DaemonProcessName = "DisplayFixDaemon";

        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(uint dwProcessId);
        private const uint ATTACH_PARENT_PROCESS = unchecked((uint)-1);

        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        private static extern IntPtr CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);
        private const int STD_OUTPUT_HANDLE = -11;

        private static Mutex _singleInstanceMutex;
        private static EventWindow _eventWindow;
        private static HotkeyHook _hotkeyHook;
        private static AcrylicOsdWindow _osdWindow;
        private static bool _running = false;

        private static void EnsureConsoleOutput()
        {
            try
            {
                IntPtr stdOutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
                if (stdOutHandle == IntPtr.Zero || stdOutHandle.ToInt64() == -1)
                {
                    if (AttachConsole(ATTACH_PARENT_PROCESS))
                    {
                        IntPtr stdOut = CreateFile("CONOUT$", 0x40000000, 2, IntPtr.Zero, 3, 0, IntPtr.Zero);
                        if (stdOut != IntPtr.Zero && stdOut.ToInt64() != -1)
                        {
                            Microsoft.Win32.SafeHandles.SafeFileHandle safeHandle = new Microsoft.Win32.SafeHandles.SafeFileHandle(stdOut, true);
                            FileStream fs = new FileStream(safeHandle, FileAccess.Write);
                            StreamWriter writer = new StreamWriter(fs, Encoding.Default);
                            writer.AutoFlush = true;
                            Console.SetOut(writer);
                            Console.SetError(writer);
                        }
                    }
                }
            }
            catch { }
        }

        public static int Main(string[] args)
        {
            EnsureConsoleOutput();

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

                case "--lock-360hz":
                    return HandleLock360Hz();

                case "--sync-dpi":
                    return HandleSyncDpi();

                case "--brightness-get":
                case "--get-brightness":
                    return HandleBrightnessGet();

                case "--brightness-set":
                case "--set-brightness":
                case "--set":
                    return HandleBrightnessSet(args);

                case "--brightness-up":
                    return HandleBrightnessStep(args, +BrightnessController.DefaultStepPercent);

                case "--brightness-down":
                    return HandleBrightnessStep(args, -BrightnessController.DefaultStepPercent);

                case "--test-osd":
                    return HandleTestOsd(args);

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

            // Reviewer M2_1 & M2_2 Mitigation: Filter out current CLI process PID from running daemon count
            int currentPid = Process.GetCurrentProcess().Id;
            Process[] allProcs = Process.GetProcessesByName(DaemonProcessName);
            List<Process> daemonProcs = new List<Process>();
            for (int i = 0; i < allProcs.Length; i++)
            {
                if (allProcs[i].Id != currentPid)
                {
                    daemonProcs.Add(allProcs[i]);
                }
            }

            bool isProcessRunning = daemonProcs.Count > 0;

            int currentRefreshHz = 0;
            try
            {
                currentRefreshHz = RefreshRateLock.GetCurrentRefreshRateHz();
            }
            catch { }

            int currentScalingPercent = 0;
            try
            {
                currentScalingPercent = ScalingSynchronizer.GetCurrentScalingPercent();
            }
            catch { }

            int currentBrightness = -1;
            string brightnessBackend = "None";
            try
            {
                currentBrightness = BrightnessController.GetBrightness();
                brightnessBackend = BrightnessController.GetActiveBackendName();
            }
            catch { }

            Console.WriteLine("==================================================================");
            Console.WriteLine(" DisplayFixDaemon Status Telemetry");
            Console.WriteLine("==================================================================");
            Console.WriteLine("Mutex Active:        " + mutexHeld + " (" + SingleInstanceMutexName + ")");
            Console.WriteLine("Process Running:     " + isProcessRunning + " (Count: " + daemonProcs.Count + ")");
            if (daemonProcs.Count > 0)
            {
                try
                {
                    Console.WriteLine("Process PID:         " + daemonProcs[0].Id);
                    Console.WriteLine("Working Set (MB):    " + Math.Round(daemonProcs[0].WorkingSet64 / (1024.0 * 1024.0), 2));
                }
                catch { }
            }
            Console.WriteLine("Refresh Rate (Hz):   " + currentRefreshHz + " Hz");
            Console.WriteLine("Display Scaling (%): " + currentScalingPercent + "%");
            Console.WriteLine("Brightness (%):      " + (currentBrightness >= 0 ? (currentBrightness + "%") : "N/A"));
            Console.WriteLine("Brightness Backend:  " + brightnessBackend);
            Console.WriteLine("Log File:            C:\\ProgramData\\DisplayFix\\logs\\daemon.log");
            Console.WriteLine("Log Exists:          " + File.Exists(@"C:\ProgramData\DisplayFix\logs\daemon.log"));

            bool elevated = IsRunningElevated();
            Console.WriteLine("Current Elevation:   " + (elevated ? "Elevated (Admin)" : "Non-Elevated (Limited)"));
            Console.WriteLine("==================================================================");
            try { Console.Out.Flush(); } catch { }

            return 0;
        }

        private static int HandleEvictNow()
        {
            Logger.Info("CLI", "Executing --evict-now (one-shot eviction).");
            Console.WriteLine("Executing one-shot ghost monitor eviction...");

            try
            {
                Stopwatch sw = Stopwatch.StartNew();
                GhostEvictionResult result = GhostEvictionEngine.CheckAndEvict(force: false);
                sw.Stop();

                Console.WriteLine(string.Format("One-shot eviction complete in {0:F2}ms. Ghost monitors evicted: {1}",
                    sw.Elapsed.TotalMilliseconds, result.EvictedCount));
                Console.WriteLine("Details: " + result.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Info("CLI", string.Format("One-shot eviction completed in {0:F2}ms with {1} evicted. Details: {2}",
                    sw.Elapsed.TotalMilliseconds, result.EvictedCount, result.Message));
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error during eviction: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "One-shot eviction failed", ex);
                return 1;
            }
        }

        private static int HandleLock360Hz()
        {
            Logger.Info("CLI", "Executing --lock-360hz (one-shot 360Hz refresh rate enforcement).");
            Console.WriteLine("Executing one-shot 360Hz refresh rate lock...");

            try
            {
                int beforeHz = RefreshRateLock.GetCurrentRefreshRateHz();
                Stopwatch sw = Stopwatch.StartNew();
                RefreshRateLockResult lockResult = RefreshRateLock.CheckAndEnforce(null, force: false);
                sw.Stop();
                bool ok = lockResult.EnforcementSucceeded || lockResult.WasAlready360Hz;
                int afterHz = RefreshRateLock.GetCurrentRefreshRateHz();

                Console.WriteLine(string.Format("One-shot 360Hz lock complete in {0:F2}ms. Success: {1} (Before: {2}Hz -> After: {3}Hz)",
                    sw.Elapsed.TotalMilliseconds, ok, beforeHz, afterHz));
                Console.WriteLine("Details: " + lockResult.Message);
                try { Console.Out.Flush(); } catch { }

                Logger.Info("CLI", string.Format("One-shot 360Hz lock finished in {0:F2}ms. Success={1}, Before={2}Hz, After={3}Hz, Details={4}",
                    sw.Elapsed.TotalMilliseconds, ok, beforeHz, afterHz, lockResult.Message));
                return ok ? 0 : 1;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error during 360Hz refresh rate enforcement: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "One-shot 360Hz lock failed", ex);
                return 1;
            }
        }

        private static int HandleSyncDpi()
        {
            Logger.Info("CLI", "Executing --sync-dpi (one-shot 125% DPI registry & CCD synchronization).");
            Console.WriteLine("Executing one-shot 125% DPI scaling synchronization...");

            try
            {
                int beforeScale = ScalingSynchronizer.GetCurrentScalingPercent();
                Stopwatch sw = Stopwatch.StartNew();
                ScalingSyncResult syncResult = ScalingSynchronizer.CheckAndEnforce(forceCcdSet: true);
                sw.Stop();
                bool ok = syncResult.Success;
                int afterScale = ScalingSynchronizer.GetCurrentScalingPercent();

                Console.WriteLine(string.Format("One-shot 125% DPI sync complete in {0:F2}ms. Success: {1} (Before: {2}% -> After: {3}%)",
                    sw.Elapsed.TotalMilliseconds, ok, beforeScale, afterScale));
                Console.WriteLine("Details: " + syncResult.Message);
                try { Console.Out.Flush(); } catch { }

                Logger.Info("CLI", string.Format("One-shot 125% DPI sync finished in {0:F2}ms. Success={1}, Before={2}%, After={3}%, Details={4}",
                    sw.Elapsed.TotalMilliseconds, ok, beforeScale, afterScale, syncResult.Message));
                return ok ? 0 : 1;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error during 125% DPI scaling synchronization: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "One-shot 125% DPI sync failed", ex);
                return 1;
            }
        }

        private static int HandleBrightnessGet()
        {
            Logger.Info("CLI", "Executing --brightness-get command.");
            try
            {
                int current = BrightnessController.GetBrightness();
                string backend = BrightnessController.GetActiveBackendName();
                BrightnessSchemaStatus schema = BrightnessController.ProbeSchema();

                Console.WriteLine(string.Format(
                    "Brightness: {0}%, Backend: {1}, HasNvWmi: {2}, HasNvGetSet: {3}, HasWmiMon: {4}, HasWmiSet: {5}",
                    current,
                    backend,
                    schema.HasNvWmiBrightness,
                    schema.HasNvGetSetBrightnessLevel,
                    schema.HasWmiMonitorBrightness,
                    schema.HasWmiSetBrightness));
                try { Console.Out.Flush(); } catch { }
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error querying brightness: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "--brightness-get failed", ex);
                return 1;
            }
        }

        private static int HandleBrightnessSet(string[] args)
        {
            int targetLevel = BrightnessController.DefaultInitialBrightness;
            if (args != null && args.Length > 1 && !string.IsNullOrEmpty(args[1]))
            {
                int parsed;
                if (int.TryParse(args[1].Trim(), out parsed))
                {
                    targetLevel = parsed;
                }
            }

            Logger.Info("CLI", string.Format("Executing --brightness-set (Target={0}%).", targetLevel));
            try
            {
                BrightnessOperationResult res = BrightnessController.SetBrightness(targetLevel);
                Console.WriteLine(string.Format(
                    "Brightness Set: Requested={0}%, Clamped={1}%, HardwareLevel={2}, Backend={3}, Provider={4}, Success={5}, Error={6}, Elapsed={7:F2}ms",
                    res.RequestedLevel,
                    res.ClampedUserLevel,
                    res.HardwareWrittenLevel,
                    res.BackendName ?? "None",
                    res.Provider ?? "None",
                    res.Success,
                    res.Error ?? "None",
                    res.ElapsedMs));
                try { Console.Out.Flush(); } catch { }
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error setting brightness: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "--brightness-set failed", ex);
                return 1;
            }
        }

        private static int HandleBrightnessStep(string[] args, int defaultDelta)
        {
            int delta = defaultDelta;
            if (args != null && args.Length > 1 && !string.IsNullOrEmpty(args[1]))
            {
                int parsedStep;
                if (int.TryParse(args[1].Trim(), out parsedStep) && parsedStep != 0)
                {
                    delta = (defaultDelta >= 0) ? Math.Abs(parsedStep) : -Math.Abs(parsedStep);
                }
            }

            Logger.Info("CLI", string.Format("Executing brightness step (Delta={0:+#;-#;0}%).", delta));
            try
            {
                BrightnessOperationResult res = BrightnessController.StepBrightness(delta);
                Console.WriteLine(string.Format(
                    "Brightness Step ({0:+#;-#;0}%): Clamped={1}%, HardwareLevel={2}, Backend={3}, Success={4}, Error={5}, Elapsed={6:F2}ms",
                    delta,
                    res.ClampedUserLevel,
                    res.HardwareWrittenLevel,
                    res.BackendName ?? "None",
                    res.Success,
                    res.Error ?? "None",
                    res.ElapsedMs));
                try { Console.Out.Flush(); } catch { }
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error stepping brightness: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
                Logger.Error("CLI", "Brightness step failed", ex);
                return 1;
            }
        }

        private static int HandleTestOsd(string[] args)
        {
            int testLevel = 65;
            if (args != null && args.Length > 1 && !string.IsNullOrEmpty(args[1]))
            {
                int parsed;
                if (int.TryParse(args[1].Trim(), out parsed))
                {
                    testLevel = parsed;
                }
            }

            Logger.Info("CLI", string.Format("Executing --test-osd (Level={0}%).", testLevel));
            try
            {
                IntPtr fgBefore = AcrylicOsdWindow.GetForegroundWindow();
                using (AcrylicOsdWindow osd = new AcrylicOsdWindow())
                {
                    osd.ShowOverlayInternal(testLevel, "TEST");
                    Application.DoEvents();

                    IntPtr fgDuring = AcrylicOsdWindow.GetForegroundWindow();
                    int exStyle = AcrylicOsdWindow.GetWindowLong(osd.Handle, AcrylicOsdWindow.GWL_EXSTYLE);
                    int reqMask = AcrylicOsdWindow.RequiredExStyle;
                    bool styleOk = (exStyle & reqMask) == reqMask;
                    bool focusOk = (fgBefore == fgDuring);

                    Console.WriteLine(string.Format(
                        "OSD Test: Level={0}%, Handle=0x{1:X8}, ExStyle=0x{2:X8}, StyleMatch={3}, FocusPreserved={4}, Acrylic={5}, RoundedCorners={6}",
                        osd.CurrentBrightnessPercent,
                        osd.Handle.ToInt64(),
                        exStyle,
                        styleOk,
                        focusOk,
                        osd.AcrylicApplied,
                        osd.RoundedCornersApplied));
                    try { Console.Out.Flush(); } catch { }

                    Thread.Sleep(250);
                    Application.DoEvents();
                    osd.HideOsd();
                    return (styleOk && focusOk) ? 0 : 1;
                }
            }
            catch (Exception ex)
            {
                Logger.Error("CLI", "Error executing --test-osd", ex);
                Console.WriteLine("Error executing --test-osd: " + ex.Message);
                try { Console.Out.Flush(); } catch { }
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

                // Initialize Milestone 4 Brightness Controller & Non-Activating Acrylic OSD Window on UI thread
                BrightnessController.Initialize();
                _osdWindow = AcrylicOsdWindow.Instance;

                // Instantiate EventWindow (registers for display, device, and power notifications)
                _eventWindow = new EventWindow(EventWindow.DefaultDebounceWindowMs, forceMessageOnlyParent: false);
                _eventWindow.OnReconfigurationTriggered += OnReconfigurationTriggered;

                // Instantiate & install WH_KEYBOARD_LL HotkeyHook (F6/F7 brightness + F1-F3/F9 media keys + Raw Input 0x006F/0x0070)
                _hotkeyHook = new HotkeyHook();
                _hotkeyHook.OnBrightnessStepRequested += OnBrightnessStepRequested;
                _eventWindow.AttachedHotkeyHook = _hotkeyHook;
                _hotkeyHook.Install(_eventWindow.Handle);

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

        private static void OnBrightnessStepRequested(int deltaPercent)
        {
            try
            {
                if (_eventWindow != null && _eventWindow.CurrentDisplayPowerState == 0)
                {
                    Logger.Debug("Brightness", "Ignoring brightness hotkey while display power state is OFF.");
                    return;
                }

                BrightnessOperationResult res = BrightnessController.StepBrightness(deltaPercent);
                if (res != null)
                {
                    AcrylicOsdWindow.ShowOsd(res.ClampedUserLevel, res.BackendName);
                }
            }
            catch (Exception ex)
            {
                Logger.Error("Brightness", "Error handling brightness step hotkey", ex);
            }
        }

        private static void OnReconfigurationTriggered(string triggerSource)
        {
            try
            {
                ReconfigurationPipelineResult result = (_eventWindow != null) ? _eventWindow.LastPipelineResult : null;
                if (result == null)
                {
                    result = EventWindow.ExecuteReconfigurationPipeline(triggerSource);
                }

                Logger.Info("Reconfig", string.Format(
                    "Reconfiguration sequence completed for '{0}' in {1:F2}ms (Evicted={2}, 360HzLocked={3}, 125DpiSynced={4}).",
                    triggerSource,
                    result.TotalElapsedMs,
                    result.GhostMonitorsEvicted,
                    result.RefreshRateEnforced,
                    result.DpiScalingSynchronized));
            }
            catch (Exception ex)
            {
                Logger.Error("Reconfig", "Error logging display reconfiguration sequence", ex);
            }
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
                if (_hotkeyHook != null)
                {
                    try { _hotkeyHook.Dispose(); } catch { }
                    _hotkeyHook = null;
                }

                if (_osdWindow != null)
                {
                    try { _osdWindow.Dispose(); } catch { }
                    _osdWindow = null;
                }

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
                if (_hotkeyHook != null)
                {
                    try { _hotkeyHook.Dispose(); } catch { }
                    _hotkeyHook = null;
                }

                if (_osdWindow != null)
                {
                    try { _osdWindow.Dispose(); } catch { }
                    _osdWindow = null;
                }

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
