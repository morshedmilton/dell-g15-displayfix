// src/Daemon/ScalingSynchronizer.cs
// Multi-Topology Registry DPI Synchronizer (F08) and Dynamic CCD 125% DPI Enforcement Engine (F09).
// Ensures persistent 125% (120 DPI) scaling across Optimus, Automatic, and NVIDIA GPU Only modes
// with zero font blur and zero session logoff/reboot requirements.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    /// <summary>
    /// Execution telemetry result returned from a DPI synchronization and CCD enforcement pass.
    /// </summary>
    public class ScalingSyncResult
    {
        public bool Success { get; set; }
        public bool RegistrySynced { get; set; }
        public int TopologiesChecked { get; set; }
        public int TopologiesUpdated { get; set; }
        public int LogPixels { get; set; }
        public bool LogPixelsUpdated { get; set; }
        public bool CcdEnforced { get; set; }
        public bool CcdModified { get; set; }
        public int ActivePathsChecked { get; set; }
        public int CurrentScaleRel { get; set; }
        public int MinScaleRel { get; set; }
        public int MaxScaleRel { get; set; }
        public int ScalePercent { get; set; }
        public int LastWin32Error { get; set; }
        public double ElapsedMilliseconds { get; set; }
        public string Message { get; set; }
    }

    /// <summary>
    /// Synchronizes PerMonitorSettings registry trees across Intel (8086_A78B) and NVIDIA (10DE_28E0)
    /// topologies and enforces 125% scaling dynamically via Windows CCD APIs.
    /// </summary>
    public static class ScalingSynchronizer
    {
        #region Constants

        public const string DesktopRegistrySubKey = @"Control Panel\Desktop";
        public const string PerMonitorSettingsSubKey = @"Control Panel\Desktop\PerMonitorSettings";
        public const string InternalPanelToken = "AUOAA9F";
        public const string IntelTopologyToken = "8086";
        public const string NvidiaTopologyToken = "10DE";

        public const string LogPixelsValueName = "LogPixels";
        public const string DpiValueName = "DpiValue";

        /// <summary>
        /// 120 DPI = 125% scaling factor (96 DPI * 1.25). Verified by Test F08.2.
        /// </summary>
        public const int TargetLogPixels125 = 120;

        /// <summary>
        /// Relative step 0 corresponds to 125% (Recommended scale on AUOAA9F 1080p panel).
        /// Verified by Test F08.3, F08.4, F09.2.
        /// </summary>
        public const int TargetDpiValueZero = 0;

        /// <summary>
        /// Standard Windows DPI scaling percentage steps indexed by offset from minimum (100%).
        /// </summary>
        private static readonly int[] StandardScalePercentages = new int[]
        {
            100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500
        };

        #endregion

        #region Public Entry Points & Interface Contracts

        /// <summary>
        /// Master interface contract specified by PROJECT.md §3.
        /// Synchronizes registry topologies and enforces 125% scaling via CCD.
        /// </summary>
        /// <returns>True if both registry sync and CCD enforcement succeeded.</returns>
        public static bool EnforceDisplayScaling125()
        {
            ScalingSyncResult result = CheckAndEnforce(forceCcdSet: false);
            return result.Success;
        }

        /// <summary>
        /// Entry point for EventWindow and CLI orchestration pipeline.
        /// </summary>
        /// <param name="forceCcdSet">If true, invokes DisplayConfigSetDeviceInfo even when curScaleRel == 0.</param>
        /// <returns>True if both registry sync and CCD enforcement succeeded.</returns>
        public static bool Enforce125(bool forceCcdSet = false)
        {
            ScalingSyncResult result = CheckAndEnforce(forceCcdSet: forceCcdSet);
            return result.Success;
        }

        /// <summary>
        /// Executes the complete 3-stage DPI synchronization and dynamic CCD enforcement pipeline:
        /// 1. Multi-Topology Registry DPI Sync (F08)
        /// 2. Dynamic CCD 125% DPI Enforcement (F09)
        /// 3. Post-CCD Registry Verification Pass
        /// </summary>
        /// <param name="forceCcdSet">If true, invokes DisplayConfigSetDeviceInfo even when curScaleRel == 0.</param>
        /// <returns>Structured telemetry result.</returns>
        public static ScalingSyncResult CheckAndEnforce(bool forceCcdSet = false)
        {
            Stopwatch sw = Stopwatch.StartNew();
            ScalingSyncResult result = new ScalingSyncResult();
            result.LogPixels = TargetLogPixels125;
            result.ScalePercent = 125;

            try
            {
                // Stage 1: Synchronize Registry Topologies (Pre-CCD)
                bool logPixelsUpdated1;
                int checkedCount1;
                int updatedCount1 = SynchronizeRegistryTopologies(out logPixelsUpdated1, out checkedCount1);

                result.RegistrySynced = true;
                result.LogPixelsUpdated = logPixelsUpdated1;
                result.TopologiesChecked = checkedCount1;
                result.TopologiesUpdated = updatedCount1;

                // Stage 2: Enforce 125% Scaling dynamically via CCD DisplayConfigSetDeviceInfo
                int activePaths;
                int curScaleRel;
                int minScaleRel;
                int maxScaleRel;
                bool ccdModified;
                int lastCcdErr;

                bool ccdOk = EnforceCcdDpiScale125(
                    forceCcdSet,
                    out activePaths,
                    out curScaleRel,
                    out minScaleRel,
                    out maxScaleRel,
                    out ccdModified,
                    out lastCcdErr);

                result.CcdEnforced = ccdOk;
                result.CcdModified = ccdModified;
                result.ActivePathsChecked = activePaths;
                result.CurrentScaleRel = curScaleRel;
                result.MinScaleRel = minScaleRel;
                result.MaxScaleRel = maxScaleRel;
                result.LastWin32Error = lastCcdErr;

                // Stage 3: Post-CCD Registry Verification Pass
                // Ensures any registry writes performed internally by Windows during DisplayConfigSetDeviceInfo
                // leave all AUOAA9F topologies pinned to DpiValue = 0.
                bool logPixelsUpdated2;
                int checkedCount2;
                int updatedCount2 = SynchronizeRegistryTopologies(out logPixelsUpdated2, out checkedCount2);

                result.LogPixelsUpdated = result.LogPixelsUpdated || logPixelsUpdated2;
                if (checkedCount2 > result.TopologiesChecked)
                {
                    result.TopologiesChecked = checkedCount2;
                }
                result.TopologiesUpdated += updatedCount2;

                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Success = result.RegistrySynced && result.CcdEnforced;

                result.Message = string.Format(
                    "ScalingSync complete in {0:F2}ms: Registry(Checked={1}, Updated={2}, LogPixels=120) | CCD(Enforced={3}, Modified={4}, Paths={5}, ScaleRel={6}, Err={7})",
                    result.ElapsedMilliseconds,
                    result.TopologiesChecked,
                    result.TopologiesUpdated,
                    result.CcdEnforced,
                    result.CcdModified,
                    result.ActivePathsChecked,
                    result.CurrentScaleRel,
                    result.LastWin32Error);

                if (result.TopologiesUpdated > 0 || result.CcdModified || result.LogPixelsUpdated)
                {
                    Logger.Info("ScalingSync", result.Message);
                }
                else
                {
                    Logger.Debug("ScalingSync", result.Message);
                }
            }
            catch (Exception ex)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Success = false;
                result.Message = "Exception during ScalingSynchronizer.CheckAndEnforce: " + ex.Message;
                Logger.Error("ScalingSync", result.Message, ex);
            }

            return result;
        }

        #endregion

        #region Feature F08: Multi-Topology Registry DPI Synchronization

        /// <summary>
        /// Determines whether a PerMonitorSettings subkey belongs to the internal AUOAA9F panel.
        /// Isolates foreign external displays per Test B02.4.
        /// </summary>
        public static bool IsInternalPanelTopologyKey(string keyName)
        {
            if (string.IsNullOrEmpty(keyName))
            {
                return false;
            }
            return keyName.IndexOf(InternalPanelToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>
        /// Safely parses a registry DWORD value (which may be boxed as int, uint, or long)
        /// into a signed 32-bit integer (e.g. 4294967295 / 0xFFFFFFFF -> -1, 0 -> 0).
        /// Verified by Test B02.2.
        /// </summary>
        public static int ParseRegistryDwordToSignedInt32(object rawValue, int defaultValue)
        {
            if (rawValue == null)
            {
                return defaultValue;
            }

            try
            {
                if (rawValue is int)
                {
                    return (int)rawValue;
                }
                if (rawValue is uint)
                {
                    return unchecked((int)(uint)rawValue);
                }
                if (rawValue is long)
                {
                    return unchecked((int)(long)rawValue);
                }
                uint parsedUnsigned = Convert.ToUInt32(rawValue);
                return BitConverter.ToInt32(BitConverter.GetBytes(parsedUnsigned), 0);
            }
            catch
            {
                return defaultValue;
            }
        }

        /// <summary>
        /// Synchronizes HKCU:\Control Panel\Desktop\LogPixels = 120 and sets DpiValue = 0
        /// across all PerMonitorSettings subkeys matching *AUOAA9F* (Intel, NVIDIA, and fallback topologies).
        /// Also synchronizes loaded interactive user hives under HKEY_USERS if running in an elevated context.
        /// </summary>
        public static int SynchronizeRegistryTopologies(out bool logPixelsUpdated, out int topologiesChecked)
        {
            logPixelsUpdated = false;
            topologiesChecked = 0;
            int totalUpdated = 0;

            // 1. Synchronize primary Registry.CurrentUser hive
            bool hkcuLogUpdated;
            int hkcuChecked;
            totalUpdated += SynchronizeHive(Registry.CurrentUser, out hkcuLogUpdated, out hkcuChecked);
            logPixelsUpdated = hkcuLogUpdated;
            topologiesChecked = hkcuChecked;

            // 2. Defensively synchronize loaded interactive user hives in Registry.Users (S-1-5-21-*)
            try
            {
                string[] sidNames = Registry.Users.GetSubKeyNames();
                for (int i = 0; i < sidNames.Length; i++)
                {
                    string sid = sidNames[i];
                    if (sid.StartsWith("S-1-5-21-", StringComparison.OrdinalIgnoreCase) &&
                        !sid.EndsWith("_Classes", StringComparison.OrdinalIgnoreCase))
                    {
                        using (RegistryKey userHive = Registry.Users.OpenSubKey(sid, writable: true))
                        {
                            if (userHive != null)
                            {
                                bool sidLogUpdated;
                                int sidChecked;
                                int sidUpdated = SynchronizeHive(userHive, out sidLogUpdated, out sidChecked);
                                if (sidChecked > topologiesChecked)
                                {
                                    topologiesChecked = sidChecked;
                                }
                                totalUpdated += sidUpdated;
                                logPixelsUpdated = logPixelsUpdated || sidLogUpdated;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Debug("ScalingSync", "Note: HKEY_USERS supplementary scan skipped: " + ex.Message);
            }

            return totalUpdated;
        }

        private static int SynchronizeHive(RegistryKey rootHive, out bool logPixelsUpdated, out int topologiesChecked)
        {
            logPixelsUpdated = false;
            topologiesChecked = 0;
            int topologiesUpdated = 0;

            if (rootHive == null)
            {
                return 0;
            }

            // A. Ensure Control Panel\Desktop\LogPixels == 120 (125% system DPI base, Test F08.2)
            try
            {
                using (RegistryKey desktopKey = rootHive.CreateSubKey(DesktopRegistrySubKey))
                {
                    if (desktopKey != null)
                    {
                        object rawLogPixels = desktopKey.GetValue(LogPixelsValueName);
                        int currentLogPixels = ParseRegistryDwordToSignedInt32(rawLogPixels, -1);
                        if (rawLogPixels == null || currentLogPixels != TargetLogPixels125)
                        {
                            desktopKey.SetValue(LogPixelsValueName, TargetLogPixels125, RegistryValueKind.DWord);
                            logPixelsUpdated = true;
                            Logger.Info("ScalingSync", string.Format(
                                "Updated {0}\\LogPixels from {1} to {2} (125% system base).",
                                DesktopRegistrySubKey, currentLogPixels, TargetLogPixels125));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("ScalingSync", "Failed to synchronize Control Panel\\Desktop\\LogPixels: " + ex.Message);
            }

            // B. Ensure Control Panel\Desktop\PerMonitorSettings exists and sync all *AUOAA9F* subkeys to DpiValue = 0
            try
            {
                using (RegistryKey pmRootKey = rootHive.CreateSubKey(PerMonitorSettingsSubKey))
                {
                    if (pmRootKey != null)
                    {
                        // Also ensure DpiValue = 0 on PerMonitorSettings root key if applicable
                        object rootDpiObj = pmRootKey.GetValue(DpiValueName);
                        if (rootDpiObj != null)
                        {
                            int rootDpiVal = ParseRegistryDwordToSignedInt32(rootDpiObj, -999);
                            if (rootDpiVal != TargetDpiValueZero)
                            {
                                pmRootKey.SetValue(DpiValueName, TargetDpiValueZero, RegistryValueKind.DWord);
                            }
                        }

                        string[] subKeyNames = pmRootKey.GetSubKeyNames();
                        for (int i = 0; i < subKeyNames.Length; i++)
                        {
                            string subName = subKeyNames[i];

                            // Isolate external monitors: only touch internal panel AUOAA9F topologies (Test B02.4)
                            if (!IsInternalPanelTopologyKey(subName))
                            {
                                continue;
                            }

                            topologiesChecked++;

                            using (RegistryKey topoKey = pmRootKey.OpenSubKey(subName, writable: true))
                            {
                                if (topoKey == null)
                                {
                                    continue;
                                }

                                object rawDpi = topoKey.GetValue(DpiValueName);
                                int signedDpi = ParseRegistryDwordToSignedInt32(rawDpi, -999);

                                if (rawDpi == null || signedDpi != TargetDpiValueZero)
                                {
                                    topoKey.SetValue(DpiValueName, TargetDpiValueZero, RegistryValueKind.DWord);
                                    topologiesUpdated++;
                                    Logger.Info("ScalingSync", string.Format(
                                        "Synchronized topology '{0}' DpiValue from {1} (0x{2:X8}) to 0 (125% recommended).",
                                        subName, signedDpi, unchecked((uint)signedDpi)));
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("ScalingSync", "Failed to synchronize PerMonitorSettings subkeys: " + ex.Message);
            }

            return topologiesUpdated;
        }

        #endregion

        #region Feature F09: Dynamic CCD 125% DPI Enforcement

        /// <summary>
        /// Converts a relative CCD DPI step into a percentage scale factor.
        /// Relative step 0 maps to 125% (native recommended scale on AUOAA9F).
        /// </summary>
        public static int MapRelativeStepToPercent(int scaleRel, int minScaleRel)
        {
            if (scaleRel == 0) return 125;
            if (scaleRel == -1) return 100;
            if (scaleRel == 1) return 150;
            if (scaleRel == 2) return 175;
            if (scaleRel == 3) return 200;

            int indexFromMin = scaleRel - minScaleRel;
            if (indexFromMin >= 0 && indexFromMin < StandardScalePercentages.Length)
            {
                return StandardScalePercentages[indexFromMin];
            }

            return 125;
        }

        /// <summary>
        /// Enforces 125% scaling (scaleRel = 0) dynamically across active internal panel CCD paths
        /// via DisplayConfigGetDeviceInfo (-3) and DisplayConfigSetDeviceInfo (-4).
        /// Requires zero user logoff or reboot (Test F09.5).
        /// </summary>
        public static bool EnforceCcdDpiScale125(
            bool forceSet,
            out int activePathsChecked,
            out int currentScaleRel,
            out int minScaleRel,
            out int maxScaleRel,
            out bool modified,
            out int lastWin32Error)
        {
            activePathsChecked = 0;
            currentScaleRel = 0;
            minScaleRel = -1;
            maxScaleRel = 3;
            modified = false;
            lastWin32Error = Interop.ERROR_SUCCESS;

            uint numPaths = 0;
            uint numModes = 0;

            int rcSizes = Interop.GetDisplayConfigBufferSizes(
                Interop.QDC_ONLY_ACTIVE_PATHS,
                out numPaths,
                out numModes);

            if (rcSizes != Interop.ERROR_SUCCESS || numPaths == 0)
            {
                lastWin32Error = rcSizes;
                Logger.Warn("ScalingSync", string.Format(
                    "GetDisplayConfigBufferSizes failed or returned 0 active paths (rc={0}, paths={1}).",
                    rcSizes, numPaths));
                return false;
            }

            Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
            Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];

            int rcQuery = Interop.QueryDisplayConfig(
                Interop.QDC_ONLY_ACTIVE_PATHS,
                ref numPaths,
                paths,
                ref numModes,
                modes,
                IntPtr.Zero);

            if (rcQuery != Interop.ERROR_SUCCESS)
            {
                lastWin32Error = rcQuery;
                Logger.Warn("ScalingSync", string.Format("QueryDisplayConfig failed with Win32 error {0}.", rcQuery));
                return false;
            }

            bool allInternalSucceeded = true;

            for (int i = 0; i < (int)numPaths; i++)
            {
                Interop.DISPLAYCONFIG_PATH_INFO path = paths[i];

                // Identify target monitor path to ensure we only enforce 125% on internal AUOAA9F panel
                Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME targetName = new Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME();
                targetName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
                targetName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME));
                targetName.header.adapterId = path.targetInfo.adapterId;
                targetName.header.id = path.targetInfo.id;

                int rcTarget = Interop.DisplayConfigGetDeviceInfo(ref targetName);
                string devPath = (rcTarget == Interop.ERROR_SUCCESS && targetName.monitorDevicePath != null)
                    ? targetName.monitorDevicePath
                    : string.Empty;

                // If multiple monitors are connected and this path is explicitly a foreign monitor, skip it
                if (!string.IsNullOrEmpty(devPath) &&
                    devPath.IndexOf(InternalPanelToken, StringComparison.OrdinalIgnoreCase) < 0)
                {
                    Logger.Debug("ScalingSync", string.Format(
                        "Skipping CCD DPI enforcement for external monitor path [{0}]: '{1}'", i, devPath));
                    continue;
                }

                activePathsChecked++;

                // 1. Query current relative DPI scale via DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE (-3)
                Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
                getReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
                getReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
                getReq.header.adapterId = path.sourceInfo.adapterId;
                getReq.header.id = path.sourceInfo.id;

                int rcGet = Interop.DisplayConfigGetDeviceInfo(ref getReq);
                if (rcGet == Interop.ERROR_SUCCESS)
                {
                    minScaleRel = getReq.minScaleRel;
                    currentScaleRel = getReq.curScaleRel;
                    maxScaleRel = getReq.maxScaleRel;
                }
                else
                {
                    lastWin32Error = rcGet;
                    Logger.Warn("ScalingSync", string.Format(
                        "DisplayConfigGetDeviceInfo(GET_DPI_SCALE) on SourceId={0} returned rc={1}. Proceeding with SET_DPI_SCALE.",
                        path.sourceInfo.id, rcGet));
                }

                // 2. If curScaleRel != 0 (not 125%) or forceSet requested, enforce scaleRel = 0
                if (rcGet != Interop.ERROR_SUCCESS || getReq.curScaleRel != TargetDpiValueZero || forceSet)
                {
                    Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
                    setReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
                    setReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET)); // 24 bytes
                    setReq.header.adapterId = path.sourceInfo.adapterId;
                    setReq.header.id = path.sourceInfo.id;
                    setReq.scaleRel = TargetDpiValueZero; // 0 = 125% Recommended

                    int rcSet = Interop.DisplayConfigSetDeviceInfo(ref setReq);
                    if (rcSet == Interop.ERROR_SUCCESS)
                    {
                        modified = true;
                        currentScaleRel = TargetDpiValueZero;
                        Logger.Info("ScalingSync", string.Format(
                            "Enforced 125% DPI scaling (scaleRel=0) via CCD on Adapter={0}, SourceId={1} (prevScaleRel={2}).",
                            path.sourceInfo.adapterId, path.sourceInfo.id, getReq.curScaleRel));
                    }
                    else
                    {
                        lastWin32Error = rcSet;
                        allInternalSucceeded = false;
                        Logger.Warn("ScalingSync", string.Format(
                            "DisplayConfigSetDeviceInfo(SET_DPI_SCALE, scaleRel=0) failed with Win32 error {0}.", rcSet));
                    }
                }
                else
                {
                    Logger.Debug("ScalingSync", string.Format(
                        "Active path [{0}] (SourceId={1}) is already locked at 125% (curScaleRel=0, min={2}, max={3}).",
                        i, path.sourceInfo.id, getReq.minScaleRel, getReq.maxScaleRel));
                }
            }

            return allInternalSucceeded;
        }

        /// <summary>
        /// Queries the current active DPI scaling percentage for telemetry and CLI --status reporting.
        /// </summary>
        public static int GetCurrentScalingPercent()
        {
            return GetActiveScalePercent();
        }

        /// <summary>
        /// Queries the current active DPI scaling percentage for telemetry and CLI --status reporting.
        /// </summary>
        public static int GetActiveScalePercent()
        {
            try
            {
                uint numPaths = 0;
                uint numModes = 0;
                if (Interop.GetDisplayConfigBufferSizes(Interop.QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes) == Interop.ERROR_SUCCESS && numPaths > 0)
                {
                    Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
                    Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];
                    if (Interop.QueryDisplayConfig(Interop.QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero) == Interop.ERROR_SUCCESS)
                    {
                        Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
                        getReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
                        getReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
                        getReq.header.adapterId = paths[0].sourceInfo.adapterId;
                        getReq.header.id = paths[0].sourceInfo.id;

                        if (Interop.DisplayConfigGetDeviceInfo(ref getReq) == Interop.ERROR_SUCCESS)
                        {
                            return MapRelativeStepToPercent(getReq.curScaleRel, getReq.minScaleRel);
                        }
                    }
                }
            }
            catch { }

            try
            {
                using (RegistryKey desktopKey = Registry.CurrentUser.OpenSubKey(DesktopRegistrySubKey, writable: false))
                {
                    if (desktopKey != null)
                    {
                        int logPixels = ParseRegistryDwordToSignedInt32(desktopKey.GetValue(LogPixelsValueName), 120);
                        if (logPixels > 0)
                        {
                            return (int)Math.Round((logPixels / 96.0) * 100.0);
                        }
                    }
                }
            }
            catch { }

            return 125;
        }

        #endregion
    }
}
