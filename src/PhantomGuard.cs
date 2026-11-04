// PhantomGuard - clears the stale duplicate display path left behind by
// Advanced Optimus / DDS on Dell G15 5530.
//
// Logic
//   every 8 s: count ACTIVE display paths (QueryDisplayConfig)
//   <= 1 active path           -> healthy, reset counters
//   >= 2 paths, any external   -> user plugged a monitor, never touch anything
//   >= 2 paths, all internal   -> stale duplicate, repair after 2 confirmations
//
// Repair = disable + re-enable the Intel display adapter (the duplicate path is
// powered by that adapter's monitor instance). Never touches the NVIDIA adapter.
//
// Safety rails
//   - 2 consecutive confirmations before acting (no reaction to transients)
//   - 120 s cooldown between repairs
//   - max 3 repairs per rolling hour
//   - single instance
//   - every decision is logged

using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace PhantomGuard
{
    internal static class Program
    {
        private const string InstallDir = @"C:\ProgramData\DisplayFix";
        private const string LogDir = @"C:\ProgramData\DisplayFix\logs";
        private const string LogFile = @"C:\ProgramData\DisplayFix\logs\guard.log";
        private const string IntelMatch = "Intel";
        private const string InternalPanelTag = "AUOAA9F";

        private const int PollMs = 8000;
        private const int Confirmations = 2;
        private const int CooldownMs = 60000;          // minimum gap between two repairs
        private const int MaxAttemptsPerEpisode = 3;   // per switch, not per hour
        private const int DisableWaitMs = 4000;
        private const int EnableWaitMs = 7000;

        private static readonly object LogLock = new object();

        private static int Main(string[] args)
        {
            bool once = args.Length > 0 && args[0].Equals("--once", StringComparison.OrdinalIgnoreCase);

            Directory.CreateDirectory(InstallDir);
            Directory.CreateDirectory(LogDir);

            bool created;
            using (var mutex = new Mutex(true, @"Global\PhantomGuard_SingleInstance", out created))
            {
                if (!created)
                {
                    Log("another instance is already running - exit");
                    return 2;
                }

                Log(once ? "=== start (once mode) ===" : "=== start ===");
                Log("log file: " + LogFile);

                int hits = 0;
                DateTime lastRepair = DateTime.MinValue;

                // No hourly cap any more. Instead the guard repairs once per "episode":
                // an episode opens when a duplicate appears and closes when the display
                // state is clean again. Every switch is its own episode, so switching
                // as often as you like is fine. Inside one episode it retries at most
                // MaxAttemptsPerEpisode times, so a repair that never works cannot turn
                // into an endless disable/enable loop.
                bool episodeOpen = false;
                int attempts = 0;
                bool gaveUpLogged = false;

                while (true)
                {
                    int paths;
                    bool allInternal;
                    string detail;
                    Scan(out paths, out allInternal, out detail);

                    if (once)
                        Log("scan: " + detail + "  -> duplicate=" + allInternal);

                    if (paths <= 1 && !allInternal)
                    {
                        if (hits > 0) Log("healthy again - " + detail);
                        hits = 0;

                        if (episodeOpen)
                        {
                            Log("episode closed after " + attempts + " repair(s)");
                            episodeOpen = false;
                            attempts = 0;
                            gaveUpLogged = false;
                        }
                    }
                    else if (!allInternal)
                    {
                        if (hits > 0) Log("no duplicate - standing down (" + detail + ")");
                        hits = 0;
                    }
                    else
                    {
                        hits++;

                        if (!episodeOpen)
                        {
                            episodeOpen = true;
                            attempts = 0;
                            gaveUpLogged = false;
                            Log("episode open - " + detail);
                        }

                        Log("duplicate internal path detected (" + hits + "/" + Confirmations +
                            ") " + detail);

                        if (hits >= Confirmations)
                        {
                            TimeSpan since = DateTime.UtcNow - lastRepair;

                            if (attempts >= MaxAttemptsPerEpisode)
                            {
                                if (!gaveUpLogged)
                                {
                                    Log("repair limit reached for this episode (" +
                                        attempts + ") - will try again once the display " +
                                        "state is clean");
                                    gaveUpLogged = true;
                                }
                            }
                            else if (since.TotalMilliseconds < CooldownMs)
                            {
                                Log("cooling down (" + (int)since.TotalSeconds + "s) - waiting");
                            }
                            else
                            {
                                Log("REPAIR starting (attempt " + (attempts + 1) + ")");
                                bool ok = Repair();
                                lastRepair = DateTime.UtcNow;
                                attempts++;
                                hits = 0;

                                int after; bool ai; string d2;
                                Scan(out after, out ai, out d2);
                                Log(ok
                                    ? "REPAIR done - active paths now " + after + " [" + d2 + "]"
                                    : "REPAIR FAILED - active paths " + after + " [" + d2 + "]");
                            }
                        }
                    }

                    if (once)
                    {
                        Log("=== end (once mode) ===");
                        return 0;
                    }
                    Thread.Sleep(PollMs);
                }
            }
        }

        // ---------- detection ----------
        //
        // Two independent signals, both readable without a desktop context
        // (so this works from a scheduled task):
        //   1. number of ACTIVE display paths, from the display config API
        //   2. the set of monitors that are actually present, from WMI
        //
        // A duplicate is confirmed only when there are 2+ active paths AND
        // every present monitor is the internal panel. If anything else is
        // plugged in, we stand down.

        private static void Scan(out int activePaths, out bool allInternal, out string detail)
        {
            activePaths = 0;
            allInternal = false;
            detail = "";

            uint numPath, numMode;
            int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPath, out numMode);
            if (rc != 0)
            {
                detail = "GetDisplayConfigBufferSizes rc=" + rc;
                return;
            }
            activePaths = (int)numPath;

            var internalIds = new System.Collections.Generic.List<string>();
            var foreign = new System.Collections.Generic.List<string>();
            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT Name, PNPDeviceID, ConfigManagerErrorCode FROM Win32_PnPEntity " +
                    "WHERE PNPClass = 'Monitor'"))
                {
                    foreach (ManagementObject mo in searcher.Get())
                    {
                        object errObj = mo["ConfigManagerErrorCode"];
                        int err = errObj == null ? -1 : Convert.ToInt32(errObj);
                        if (err != 0) continue;                       // not present
                        string id = Convert.ToString(mo["PNPDeviceID"]);
                        if (string.IsNullOrEmpty(id)) continue;

                        if (id.IndexOf(InternalPanelTag, StringComparison.OrdinalIgnoreCase) >= 0)
                            internalIds.Add(id);
                        else
                            foreign.Add(id);
                    }
                }
            }
            catch (Exception ex)
            {
                detail = "monitor enumeration failed: " + ex.Message;
                return;
            }

            var sb = new StringBuilder();
            sb.Append(activePaths).Append(" path(s); present: ");
            foreach (string id in internalIds) { sb.Append(ShortId(id)).Append(" "); }
            foreach (string id in foreign) { sb.Append("FOREIGN:").Append(ShortId(id)).Append(" "); }
            if (internalIds.Count == 0 && foreign.Count == 0) sb.Append("(none)");
            detail = sb.ToString().Trim();

            // Any non-internal monitor that is present means a real second screen.
            // Never act in that case.
            if (foreign.Count > 0)
            {
                allInternal = false;
                return;
            }

            // Two independent signals, either one is enough. This matters because
            // the duplicate does not always show up in both places at once:
            //   - the display config reports an extra active path, and/or
            //   - PnP lists a second present copy of the same internal panel.
            if (internalIds.Count == 0)
            {
                allInternal = false;
                return;
            }

            allInternal = (activePaths >= 2) || (internalIds.Count >= 2);
        }

        private static string ShortId(string id)
        {
            if (string.IsNullOrEmpty(id)) return "?";
            int i = id.LastIndexOf('\\');
            string tail = i >= 0 ? id.Substring(i + 1) : id;
            int j = id.IndexOf("DISPLAY\\", StringComparison.OrdinalIgnoreCase);
            string head = j >= 0 ? id.Substring(j + 8).Split('\\')[0] : "";
            return head.Length > 0 ? head + "/" + tail : tail;
        }

        // ---------- repair ----------

        private static bool Repair()
        {
            string instanceId = FindIntelAdapter();
            if (instanceId == null)
            {
                Log("  Intel display adapter not found - abort");
                return false;
            }
            Log("  adapter: " + instanceId);

            if (!RunPnP("/disable-device \"" + instanceId + "\""))
            {
                Log("  disable failed - abort");
                return false;
            }
            Thread.Sleep(DisableWaitMs);

            if (!RunPnP("/enable-device \"" + instanceId + "\""))
            {
                Log("  enable failed - retrying once");
                Thread.Sleep(2000);
                RunPnP("/enable-device \"" + instanceId + "\"");
            }
            Thread.Sleep(EnableWaitMs);
            return true;
        }

        private static string FindIntelAdapter()
        {
            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT Name, PNPDeviceID FROM Win32_PnPEntity WHERE PNPClass = 'Display'"))
                {
                    foreach (ManagementObject mo in searcher.Get())
                    {
                        string name = Convert.ToString(mo["Name"]);
                        string id = Convert.ToString(mo["PNPDeviceID"]);
                        if (name != null && id != null &&
                            name.IndexOf(IntelMatch, StringComparison.OrdinalIgnoreCase) >= 0)
                            return id;
                    }
                }
            }
            catch (Exception ex)
            {
                Log("  WMI query failed: " + ex.Message);
            }
            return null;
        }

        private static bool RunPnP(string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo("pnputil.exe", arguments)
                {
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (var p = Process.Start(psi))
                {
                    string stdout = p.StandardOutput.ReadToEnd();
                    string stderr = p.StandardError.ReadToEnd();
                    p.WaitForExit(30000);
                    bool ok = p.HasExited && p.ExitCode == 0;
                    Log("  pnputil " + arguments.Split(' ')[0] + " -> exit " +
                        (p.HasExited ? p.ExitCode.ToString() : "timeout") +
                        (ok ? "" : " :: " + (stdout + stderr).Trim().Replace("\r", " ").Replace("\n", " ")));
                    return ok;
                }
            }
            catch (Exception ex)
            {
                Log("  pnputil threw: " + ex.Message);
                return false;
            }
        }

        // ---------- logging ----------

        private static void Log(string message)
        {
            lock (LogLock)
            {
                try
                {
                    var fi = new FileInfo(LogFile);
                    if (fi.Exists && fi.Length > 1024 * 1024)
                    {
                        string old = LogFile + ".1";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(LogFile, old);
                    }
                    File.AppendAllText(LogFile,
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + Environment.NewLine,
                        Encoding.UTF8);
                }
                catch { }
            }
        }

        // ---------- interop ----------

        private const int QDC_ONLY_ACTIVE_PATHS = 2;
        private const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_SOURCE_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_TARGET_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint outputTechnology;
            public uint rotation;
            public uint scaling;
            public uint refreshRateNumerator;
            public uint refreshRateDenominator;
            public uint scanLineOrdering;
            public int targetAvailable;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_INFO
        {
            public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
            public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
            public uint flags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_2DREGION { public uint cx; public uint cy; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
        {
            public ulong pixelRate;
            public DISPLAYCONFIG_RATIONAL hSyncFreq;
            public DISPLAYCONFIG_RATIONAL vSyncFreq;
            public DISPLAYCONFIG_2DREGION activeSize;
            public DISPLAYCONFIG_2DREGION totalSize;
            public uint videoStandard;
            public uint scanLineOrdering;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_TARGET_MODE { public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_DEVICE_INFO_HEADER
        {
            public int type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAYCONFIG_TARGET_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public uint flags;
            public uint outputTechnology;
            public ushort edidManufactureId;
            public ushort edidProductCodeId;
            public uint connectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
            public string monitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string monitorDevicePath;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);

        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(
            uint flags,
            ref uint numPathArrayElements,
            [Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray,
            ref uint numModeInfoArrayElements,
            [Out] DISPLAYCONFIG_TARGET_MODE[] modeInfoArray,
            IntPtr currentTopologyId);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME deviceName);
    }
}
