// .agents/teamwork/explorer_m3_1/RefreshRateLock.cs
// Reference Compilable Blueprint for src/Daemon/RefreshRateLock.cs
// High-performance in-process 360Hz (360.152Hz) Refresh Rate Lock Engine for Dell G15 5530.
// Enforces exact native rational 360152/1000 via Windows CCD SetDisplayConfig with DEVMODEW fallback.
// Zero child processes, zero external dependencies. Targets .NET Framework 4.8 x64 (C# 5 compatible).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    /// <summary>
    /// Telemetry details for an active CCD display path.
    /// </summary>
    public class DisplayPathRateInfo
    {
        public int PathIndex { get; set; }
        public uint SourceId { get; set; }
        public uint TargetId { get; set; }
        public uint AdapterLowPart { get; set; }
        public int AdapterHighPart { get; set; }
        public string GdiDeviceName { get; set; }
        public string MonitorDevicePath { get; set; }
        public string MonitorFriendlyName { get; set; }
        public string AdapterDevicePath { get; set; }
        public bool IsInternalPanel { get; set; }
        public uint Numerator { get; set; }
        public uint Denominator { get; set; }
        public double FrequencyHz { get; set; }

        public override string ToString()
        {
            return string.Format("Path[{0}]: GDI='{1}', Internal={2}, Rate={3}/{4} ({5:F3}Hz), Monitor='{6}'",
                PathIndex, GdiDeviceName, IsInternalPanel, Numerator, Denominator, FrequencyHz, MonitorDevicePath);
        }
    }

    /// <summary>
    /// Execution telemetry result returned from a 360Hz refresh rate check / enforcement pass.
    /// </summary>
    public class RefreshRateLockResult
    {
        public bool InternalPanelFound { get; set; }
        public string TargetDevicePath { get; set; }
        public string GdiDeviceName { get; set; }
        public uint InitialNumerator { get; set; }
        public uint InitialDenominator { get; set; }
        public double InitialFrequencyHz { get; set; }
        public uint FinalNumerator { get; set; }
        public uint FinalDenominator { get; set; }
        public double FinalFrequencyHz { get; set; }
        public bool WasAlready360Hz { get; set; }
        public bool EnforcementAttempted { get; set; }
        public bool EnforcementSucceeded { get; set; }
        public bool UsedDevModeFallback { get; set; }
        public int CcdReturnCode { get; set; }
        public int FallbackReturnCode { get; set; }
        public double ElapsedMilliseconds { get; set; }
        public string Message { get; set; }
    }

    /// <summary>
    /// Native Windows CCD and User32 DEVMODE 360Hz Refresh Rate Lock Engine (Milestone 3 / Feature F07).
    /// </summary>
    public static class RefreshRateLock
    {
        #region Constants & Hardware Signatures

        public const string InternalPanelModel = "AUOAA9F";

        /// <summary>
        /// Exact hardware rational timing for AU Optronics AUO AA9F 360Hz eDP panel (360.152 Hz).
        /// Verified by Test F07.2 & C01.1.
        /// </summary>
        public const uint TargetNumerator   = 360152;
        public const uint TargetDenominator = 1000;
        public const int TargetNominalHz    = 360;
        public const int FallbackHz         = 60;

        /// <summary>
        /// Threshold frequency (300 Hz) below which the panel is in fallback 60Hz mode and requires restoration.
        /// Verified by Test F07.5 & C01.2.
        /// </summary>
        public const double MinimumHighRefreshThresholdHz = 300.0;

        /// <summary>
        /// Native pixel clock and sync parameters for AUO AA9F 1920x1080 @ 360.152Hz.
        /// </summary>
        public const ulong NativePixelRate360Hz  = 839010000UL;
        public const uint NativeHSyncNumerator   = 839010000U;
        public const uint NativeHSyncDenominator = 2080U;

        /// <summary>
        /// Combined Windows CCD SetDisplayConfig flags verified by Test F07.3:
        /// SDC_APPLY (0x80) | SDC_USE_SUPPLIED_DISPLAY_CONFIG (0x20) | SDC_SAVE_TO_DATABASE (0x200) | SDC_ALLOW_CHANGES (0x400) = 0x000006A0
        /// </summary>
        public const uint CcdEnforceFlags = Interop.SDC_ENFORCE_FLAGS;

        /// <summary>
        /// Secondary CCD flags without SDC_SAVE_TO_DATABASE (0x000004A0) if database write returns ERROR_ACCESS_DENIED.
        /// </summary>
        public const uint CcdEnforceFlagsNoSave = Interop.SDC_ENFORCE_FLAGS_NO_SAVE;

        #endregion

        #region Public Contract API

        /// <summary>
        /// Master interface contract specified by PROJECT.md (§ Interface Contracts #2).
        /// Queries active display configuration for the internal AUO AA9F panel and enforces 360.152Hz (360152/1000).
        /// </summary>
        /// <param name="targetDevicePath">Optional monitor device path filter (null or empty matches any internal AUOAA9F panel).</param>
        /// <returns>True if the panel is confirmed at 360Hz or successfully switched to 360Hz; false otherwise.</returns>
        public static bool EnforceRefreshRate360Hz(string targetDevicePath = null)
        {
            RefreshRateLockResult result = CheckAndEnforce(targetDevicePath, force: false);
            return result.EnforcementSucceeded || result.WasAlready360Hz;
        }

        /// <summary>
        /// Evaluates whether a given frequency requires restoration to 360Hz (< 300Hz threshold per F07.5 / C01.2).
        /// </summary>
        public static bool ShouldRestore360Hz(double currentFrequencyHz)
        {
            return currentFrequencyHz > 0.0 && currentFrequencyHz < MinimumHighRefreshThresholdHz;
        }

        /// <summary>
        /// Queries all active CCD display paths and populates hardware identity and rational refresh rate metadata.
        /// </summary>
        public static List<DisplayPathRateInfo> QueryActiveDisplayPaths()
        {
            List<DisplayPathRateInfo> list = new List<DisplayPathRateInfo>();

            uint numPaths;
            uint numModes;
            int rc = Interop.GetDisplayConfigBufferSizes(Interop.QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
            if (rc != Interop.ERROR_SUCCESS || numPaths == 0)
            {
                return list;
            }

            Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
            Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];

            rc = Interop.QueryDisplayConfig(Interop.QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
            if (rc != Interop.ERROR_SUCCESS)
            {
                return list;
            }

            for (int i = 0; i < (int)numPaths; i++)
            {
                Interop.DISPLAYCONFIG_PATH_INFO p = paths[i];
                DisplayPathRateInfo info = new DisplayPathRateInfo();
                info.PathIndex = i;
                info.SourceId = p.sourceInfo.id;
                info.TargetId = p.targetInfo.id;
                info.AdapterLowPart = p.targetInfo.adapterId.LowPart;
                info.AdapterHighPart = p.targetInfo.adapterId.HighPart;

                uint num = p.targetInfo.refreshRate.Numerator;
                uint den = p.targetInfo.refreshRate.Denominator;

                uint targetModeIdx = p.targetInfo.modeInfoIdx;
                if ((num == 0 || den == 0) && targetModeIdx < numModes)
                {
                    if (modes[targetModeIdx].infoType == Interop.DISPLAYCONFIG_MODE_INFO_TYPE_TARGET)
                    {
                        num = modes[targetModeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Numerator;
                        den = modes[targetModeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Denominator;
                    }
                }

                info.Numerator = num;
                info.Denominator = den;
                info.FrequencyHz = (den > 0) ? ((double)num / (double)den) : 0.0;

                // Resolve Target Monitor Device Name
                Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME targetName = new Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME();
                targetName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
                targetName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME));
                targetName.header.adapterId = p.targetInfo.adapterId;
                targetName.header.id = p.targetInfo.id;
                if (Interop.DisplayConfigGetDeviceInfo(ref targetName) == Interop.ERROR_SUCCESS)
                {
                    info.MonitorDevicePath = targetName.monitorDevicePath ?? string.Empty;
                    info.MonitorFriendlyName = targetName.monitorFriendlyDeviceName ?? string.Empty;
                }
                else
                {
                    info.MonitorDevicePath = string.Empty;
                    info.MonitorFriendlyName = string.Empty;
                }

                // Resolve Source GDI Device Name (e.g. \\.\DISPLAY1)
                Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME sourceName = new Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME();
                sourceName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
                sourceName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME));
                sourceName.header.adapterId = p.sourceInfo.adapterId;
                sourceName.header.id = p.sourceInfo.id;
                if (Interop.DisplayConfigGetDeviceInfo(ref sourceName) == Interop.ERROR_SUCCESS)
                {
                    info.GdiDeviceName = sourceName.viewGdiDeviceName ?? string.Empty;
                }
                else
                {
                    info.GdiDeviceName = string.Empty;
                }

                // Resolve Adapter Device Path
                Interop.DISPLAYCONFIG_ADAPTER_NAME adapterName = new Interop.DISPLAYCONFIG_ADAPTER_NAME();
                adapterName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME;
                adapterName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_ADAPTER_NAME));
                adapterName.header.adapterId = p.targetInfo.adapterId;
                adapterName.header.id = 0;
                if (Interop.DisplayConfigGetDeviceInfo(ref adapterName) == Interop.ERROR_SUCCESS)
                {
                    info.AdapterDevicePath = adapterName.adapterDevicePath ?? string.Empty;
                }
                else
                {
                    info.AdapterDevicePath = string.Empty;
                }

                info.IsInternalPanel = info.MonitorDevicePath.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0;
                list.Add(info);
            }

            return list;
        }

        #endregion

        #region Core Enforcement Pipeline

        /// <summary>
        /// Inspects active display configuration for the AUO AA9F internal panel.
        /// If refresh rate is below 300Hz (e.g. 60Hz fallback) or if force is true, enforces 360.152Hz (360152/1000)
        /// via Windows CCD SetDisplayConfig (0x000006A0), with automatic fallback to ChangeDisplaySettingsExW.
        /// </summary>
        /// <param name="targetDevicePath">Optional monitor device path filter.</param>
        /// <param name="force">If true, applies SetDisplayConfig even if already reporting >= 300Hz.</param>
        /// <returns>Structured telemetry result.</returns>
        public static RefreshRateLockResult CheckAndEnforce(string targetDevicePath = null, bool force = false)
        {
            Stopwatch sw = Stopwatch.StartNew();
            RefreshRateLockResult result = new RefreshRateLockResult();
            result.TargetDevicePath = targetDevicePath ?? InternalPanelModel;

            uint numPaths;
            uint numModes;
            int rcSizes = Interop.GetDisplayConfigBufferSizes(Interop.QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
            if (rcSizes != Interop.ERROR_SUCCESS || numPaths == 0)
            {
                Logger.Warn("RefreshLock", string.Format("GetDisplayConfigBufferSizes failed (rc={0}, paths={1}). Attempting DEVMODE fallback.", rcSizes, numPaths));
                bool fbOk = EnforceViaDevModeFallback(null, out result);
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                return result;
            }

            Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
            Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];

            int rcQuery = Interop.QueryDisplayConfig(Interop.QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
            if (rcQuery != Interop.ERROR_SUCCESS)
            {
                Logger.Warn("RefreshLock", string.Format("QueryDisplayConfig failed (rc={0}). Attempting DEVMODE fallback.", rcQuery));
                bool fbOk = EnforceViaDevModeFallback(null, out result);
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                return result;
            }

            int targetPathIdx = -1;
            string matchedMonitorPath = string.Empty;
            string matchedGdiName = string.Empty;

            for (int i = 0; i < (int)numPaths; i++)
            {
                Interop.DISPLAYCONFIG_PATH_INFO p = paths[i];

                Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME tName = new Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME();
                tName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
                tName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME));
                tName.header.adapterId = p.targetInfo.adapterId;
                tName.header.id = p.targetInfo.id;

                string monPath = string.Empty;
                if (Interop.DisplayConfigGetDeviceInfo(ref tName) == Interop.ERROR_SUCCESS && tName.monitorDevicePath != null)
                {
                    monPath = tName.monitorDevicePath;
                }

                bool isMatch = false;
                if (!string.IsNullOrEmpty(targetDevicePath))
                {
                    isMatch = monPath.IndexOf(targetDevicePath, StringComparison.OrdinalIgnoreCase) >= 0;
                }
                else
                {
                    isMatch = monPath.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0;
                }

                if (isMatch)
                {
                    targetPathIdx = i;
                    matchedMonitorPath = monPath;

                    Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME sName = new Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME();
                    sName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
                    sName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME));
                    sName.header.adapterId = p.sourceInfo.adapterId;
                    sName.header.id = p.sourceInfo.id;
                    if (Interop.DisplayConfigGetDeviceInfo(ref sName) == Interop.ERROR_SUCCESS && sName.viewGdiDeviceName != null)
                    {
                        matchedGdiName = sName.viewGdiDeviceName;
                    }
                    break;
                }
            }

            // If no explicit AUOAA9F path matched but there is only 1 active display path on the system, use path 0
            if (targetPathIdx < 0 && numPaths == 1 && string.IsNullOrEmpty(targetDevicePath))
            {
                targetPathIdx = 0;
                Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME sName = new Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME();
                sName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
                sName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DEVICE_NAME));
                sName.header.adapterId = paths[0].sourceInfo.adapterId;
                sName.header.id = paths[0].sourceInfo.id;
                if (Interop.DisplayConfigGetDeviceInfo(ref sName) == Interop.ERROR_SUCCESS && sName.viewGdiDeviceName != null)
                {
                    matchedGdiName = sName.viewGdiDeviceName;
                }
            }

            if (targetPathIdx < 0)
            {
                sw.Stop();
                result.InternalPanelFound = false;
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Stand down: Internal panel AUOAA9F not found among active CCD display paths.";
                Logger.Debug("RefreshLock", result.Message);
                return result;
            }

            result.InternalPanelFound = true;
            result.TargetDevicePath = matchedMonitorPath;
            result.GdiDeviceName = matchedGdiName;

            uint curNum = paths[targetPathIdx].targetInfo.refreshRate.Numerator;
            uint curDen = paths[targetPathIdx].targetInfo.refreshRate.Denominator;
            uint modeIdx = paths[targetPathIdx].targetInfo.modeInfoIdx;

            if ((curNum == 0 || curDen == 0) && modeIdx < numModes)
            {
                if (modes[modeIdx].infoType == Interop.DISPLAYCONFIG_MODE_INFO_TYPE_TARGET)
                {
                    curNum = modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Numerator;
                    curDen = modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Denominator;
                }
            }

            double curHz = (curDen > 0) ? ((double)curNum / (double)curDen) : 0.0;
            result.InitialNumerator = curNum;
            result.InitialDenominator = curDen;
            result.InitialFrequencyHz = curHz;

            // Mode detection rule (Objective 1 & Test F07.5):
            // If current frequency >= 300Hz (already 360Hz) and not forced, stand down cleanly.
            if (!ShouldRestore360Hz(curHz) && curHz >= MinimumHighRefreshThresholdHz && !force)
            {
                sw.Stop();
                result.WasAlready360Hz = true;
                result.EnforcementAttempted = false;
                result.EnforcementSucceeded = true;
                result.FinalNumerator = curNum;
                result.FinalDenominator = curDen;
                result.FinalFrequencyHz = curHz;
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = string.Format("Clean: Internal panel already locked at {0}/{1} ({2:F3}Hz) on '{3}'.",
                    curNum, curDen, curHz, matchedGdiName);
                Logger.Debug("RefreshLock", result.Message);
                return result;
            }

            // Enforce 360.152Hz (360152 / 1000) via Windows CCD SetDisplayConfig
            result.EnforcementAttempted = true;
            Logger.Info("RefreshLock", string.Format("Enforcing 360.152Hz ({0}/{1}) on path {2} ('{3}', initial={4:F3}Hz, force={5})...",
                TargetNumerator, TargetDenominator, targetPathIdx, matchedGdiName, curHz, force));

            paths[targetPathIdx].targetInfo.refreshRate.Numerator = TargetNumerator;
            paths[targetPathIdx].targetInfo.refreshRate.Denominator = TargetDenominator;

            if (modeIdx < numModes && modes[modeIdx].infoType == Interop.DISPLAYCONFIG_MODE_INFO_TYPE_TARGET)
            {
                modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Numerator = TargetNumerator;
                modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.vSyncFreq.Denominator = TargetDenominator;

                // Ensure pixelRate and hSyncFreq match native 360Hz timing when transitioning from 60Hz
                if (modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.activeSize.cx == 1920 &&
                    modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.activeSize.cy == 1080)
                {
                    modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.pixelRate = NativePixelRate360Hz;
                    modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.hSyncFreq.Numerator = NativeHSyncNumerator;
                    modes[modeIdx].modeInfo.targetMode.targetVideoSignalInfo.hSyncFreq.Denominator = NativeHSyncDenominator;
                }
            }

            // Primary CCD call with SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES (0x000006A0)
            int rcSet = Interop.SetDisplayConfig(numPaths, paths, numModes, modes, CcdEnforceFlags);
            result.CcdReturnCode = rcSet;

            // If ERROR_ACCESS_DENIED (5) due to non-elevated context writing SDC_SAVE_TO_DATABASE, retry with 0x000004A0
            if (rcSet == Interop.ERROR_ACCESS_DENIED)
            {
                Logger.Warn("RefreshLock", "SetDisplayConfig(0x000006A0) returned ERROR_ACCESS_DENIED (5). Retrying without SDC_SAVE_TO_DATABASE (0x000004A0)...");
                rcSet = Interop.SetDisplayConfig(numPaths, paths, numModes, modes, CcdEnforceFlagsNoSave);
                result.CcdReturnCode = rcSet;
            }

            // If supplying modified mode timing struct was rejected by driver (ERROR_INVALID_PARAMETER = 87),
            // let CCD compute the target mode from the path refreshRate rational by invalidating target modeInfoIdx.
            if (rcSet != Interop.ERROR_SUCCESS)
            {
                Logger.Warn("RefreshLock", string.Format("SetDisplayConfig with explicit targetMode returned {0}. Retrying with path-level rational resolution...", rcSet));
                paths[targetPathIdx].targetInfo.modeInfoIdx = Interop.DISPLAYCONFIG_PATH_MODE_IDX_INVALID;
                rcSet = Interop.SetDisplayConfig(numPaths, paths, numModes, modes, CcdEnforceFlags);
                if (rcSet == Interop.ERROR_ACCESS_DENIED)
                {
                    rcSet = Interop.SetDisplayConfig(numPaths, paths, numModes, modes, CcdEnforceFlagsNoSave);
                }
                result.CcdReturnCode = rcSet;
            }

            if (rcSet == Interop.ERROR_SUCCESS)
            {
                sw.Stop();
                result.EnforcementSucceeded = true;
                result.UsedDevModeFallback = false;
                result.FinalNumerator = TargetNumerator;
                result.FinalDenominator = TargetDenominator;
                result.FinalFrequencyHz = (double)TargetNumerator / (double)TargetDenominator;
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = string.Format("CCD SetDisplayConfig locked 360.152Hz ({0}/{1}) on '{2}' in {3:F2}ms (rc=0).",
                    TargetNumerator, TargetDenominator, matchedGdiName, result.ElapsedMilliseconds);
                Logger.Info("RefreshLock", result.Message);
                return result;
            }

            // Secondary Fallback: ChangeDisplaySettingsExW with DEVMODEW dmDisplayFrequency = 360
            Logger.Warn("RefreshLock", string.Format("CCD SetDisplayConfig failed with rc={0}. Invoking secondary fallback ChangeDisplaySettingsExW(360Hz) on '{1}'...",
                rcSet, matchedGdiName));

            RefreshRateLockResult fbResult;
            bool fallbackSuccess = EnforceViaDevModeFallback(matchedGdiName, out fbResult);

            sw.Stop();
            result.UsedDevModeFallback = true;
            result.FallbackReturnCode = fbResult.FallbackReturnCode;
            result.EnforcementSucceeded = fallbackSuccess;
            result.FinalNumerator = fallbackSuccess ? TargetNumerator : curNum;
            result.FinalDenominator = fallbackSuccess ? TargetDenominator : curDen;
            result.FinalFrequencyHz = fallbackSuccess ? 360.0 : curHz;
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
            result.Message = fbResult.Message;

            if (fallbackSuccess)
            {
                Logger.Info("RefreshLock", result.Message);
            }
            else
            {
                Logger.Error("RefreshLock", result.Message);
            }

            return result;
        }

        /// <summary>
        /// Secondary fallback mechanism using Win32 ChangeDisplaySettingsExW with DEVMODEW.dmDisplayFrequency = 360.
        /// Preserves existing resolution, color depth, and dmFields to avoid DISP_CHANGE_FAILED (-1).
        /// </summary>
        public static bool EnforceViaDevModeFallback(string gdiDeviceName, out RefreshRateLockResult result)
        {
            result = new RefreshRateLockResult();
            result.UsedDevModeFallback = true;
            result.EnforcementAttempted = true;
            result.GdiDeviceName = gdiDeviceName ?? string.Empty;

            string targetGdi = string.IsNullOrEmpty(gdiDeviceName) ? null : gdiDeviceName;

            Interop.DEVMODEW dm = new Interop.DEVMODEW();
            dm.dmSize = (short)Marshal.SizeOf(typeof(Interop.DEVMODEW));

            if (!Interop.EnumDisplaySettingsW(targetGdi, Interop.ENUM_CURRENT_SETTINGS, ref dm))
            {
                int err = Marshal.GetLastWin32Error();
                result.FallbackReturnCode = Interop.DISP_CHANGE_FAILED;
                result.EnforcementSucceeded = false;
                result.Message = string.Format("EnumDisplaySettingsW failed for device '{0}' (Win32Error={1}).", targetGdi ?? "PRIMARY", err);
                return false;
            }

            result.InitialFrequencyHz = dm.dmDisplayFrequency;
            result.InitialNumerator = (uint)(dm.dmDisplayFrequency * 1000);
            result.InitialDenominator = 1000;

            dm.dmDisplayFrequency = TargetNominalHz;
            dm.dmFields |= Interop.DM_DISPLAYFREQUENCY;

            // Attempt persistent registry + live dynamic update first
            int dispRet = Interop.ChangeDisplaySettingsExW(
                targetGdi,
                ref dm,
                IntPtr.Zero,
                Interop.CDS_UPDATEREGISTRY,
                IntPtr.Zero);

            // If CDS_UPDATEREGISTRY fails due to permissions, retry with dynamic-only flags (0)
            if (dispRet != Interop.DISP_CHANGE_SUCCESSFUL)
            {
                dispRet = Interop.ChangeDisplaySettingsExW(
                    targetGdi,
                    ref dm,
                    IntPtr.Zero,
                    0,
                    IntPtr.Zero);
            }

            result.FallbackReturnCode = dispRet;
            if (dispRet == Interop.DISP_CHANGE_SUCCESSFUL)
            {
                result.EnforcementSucceeded = true;
                result.FinalNumerator = TargetNumerator;
                result.FinalDenominator = TargetDenominator;
                result.FinalFrequencyHz = TargetNominalHz;
                result.Message = string.Format("Fallback ChangeDisplaySettingsExW successfully enforced {0}Hz on '{1}' (ret={2}).",
                    TargetNominalHz, targetGdi ?? "PRIMARY", dispRet);
                return true;
            }

            result.EnforcementSucceeded = false;
            result.FinalFrequencyHz = result.InitialFrequencyHz;
            result.Message = string.Format("Fallback ChangeDisplaySettingsExW failed on '{0}' with DISP_CHANGE code {1}.",
                targetGdi ?? "PRIMARY", dispRet);
            return false;
        }

        #endregion
    }
}
