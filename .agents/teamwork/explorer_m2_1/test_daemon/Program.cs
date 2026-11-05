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

            // Check elevation
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

        #region Daemon Execution Loop

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
            // Placeholder / bridge for GhostEvictionEngine (Milestone 2)
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
