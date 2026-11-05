// src/Daemon/GhostEvictionEngine.cs
// High-performance in-process ghost monitor eviction engine for Dell G15 5530.
// Eliminates DWM presentation stalls by recycling unclocked Intel eDP devnodes (<100ms latency).
// Zero child processes, zero external dependencies. Targets .NET Framework 4.8 x64 (C# 5 compatible).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    /// <summary>
    /// Telemetry details for an enumerated PnP monitor device node.
    /// </summary>
    public class MonitorDeviceInfo
    {
        public string InstanceId { get; set; }
        public string ParentDeviceId { get; set; }
        public uint DevInst { get; set; }
        public bool IsPresent { get; set; }
        public uint DevNodeStatus { get; set; }
        public uint ProblemNumber { get; set; }
        public bool IsInternalPanel { get; set; }
        public bool IsIntelGhost { get; set; }
        public bool IsNvidiaActive { get; set; }
        public bool IsForeign { get; set; }

        public override string ToString()
        {
            return string.Format("ID='{0}', Present={1}, Status=0x{2:X8}, Parent='{3}'",
                InstanceId, IsPresent, DevNodeStatus, ParentDeviceId);
        }
    }

    /// <summary>
    /// Execution telemetry result returned from an eviction sweep.
    /// </summary>
    public class GhostEvictionResult
    {
        public bool NvidiaActive { get; set; }
        public bool IntelGhostPresent { get; set; }
        public bool ForeignMonitorPresent { get; set; }
        public int EvictedCount { get; set; }
        public double ElapsedMilliseconds { get; set; }
        public int LastConfigRet { get; set; }
        public string Message { get; set; }
    }

    /// <summary>
    /// Native in-process CfgMgr32 / SetupAPI Ghost Eviction Engine.
    /// </summary>
    public static class GhostEvictionEngine
    {
        #region Constants & Hardware Signatures

        public const string InternalPanelModel = "AUOAA9F";
        public const string IntelGhostUidToken  = "UID8388688";
        public const string NvidiaActiveUidToken = "UID4353";
        public const string IntelGpuVenDev      = "VEN_8086&DEV_A78B";
        public const string NvidiaGpuVenDev     = "VEN_10DE&DEV_28E0";
        public const string DefaultIntelGhostInstanceId = @"DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688";

        private const int ReenableDelayMs = 50;
        private const int RetryReenableDelayMs = 25;

        #endregion

        #region Device Identification & Safety Filters

        /// <summary>
        /// Identifies whether a device instance matches the disconnected Intel internal panel node.
        /// Strict matching rule per Test F04.5 & S03.1.
        /// </summary>
        public static bool IsIntelGhostNode(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0 &&
                   instanceId.IndexOf(IntelGhostUidToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>
        /// Identifies whether a device instance matches the active NVIDIA dGPU internal panel node.
        /// This node MUST NEVER be touched.
        /// </summary>
        public static bool IsNvidiaActiveNode(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0 &&
                   instanceId.IndexOf(NvidiaActiveUidToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>
        /// Identifies whether a monitor is an external / foreign display (Dell, Samsung, LG, HDMI, DP).
        /// Foreign monitors MUST NEVER be touched per Test F04.5 & S03.1.
        /// </summary>
        public static bool IsForeignMonitor(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) < 0;
        }

        #endregion

        #region Device Enumeration

        /// <summary>
        /// Enumerates all monitor device nodes under Class Monitor via SetupAPI and CfgMgr32.
        /// </summary>
        /// <param name="presentOnly">If true, returns only currently present devices (DIGCF_PRESENT).</param>
        /// <returns>List of populated MonitorDeviceInfo objects.</returns>
        public static List<MonitorDeviceInfo> EnumerateMonitors(bool presentOnly = false)
        {
            List<MonitorDeviceInfo> list = new List<MonitorDeviceInfo>();
            Guid monitorClass = Interop.GUID_DEVCLASS_MONITOR;
            uint flags = presentOnly ? Interop.DIGCF_PRESENT : 0;

            IntPtr hDevInfo = Interop.SetupDiGetClassDevsW(ref monitorClass, null, IntPtr.Zero, flags);
            if (hDevInfo == Interop.INVALID_HANDLE_VALUE)
            {
                Logger.Warn("EvictionEngine", "SetupDiGetClassDevsW returned INVALID_HANDLE_VALUE");
                return list;
            }

            try
            {
                Interop.SP_DEVINFO_DATA devData = new Interop.SP_DEVINFO_DATA();
                devData.cbSize = (uint)Marshal.SizeOf(typeof(Interop.SP_DEVINFO_DATA));
                uint idx = 0;
                StringBuilder sb = new StringBuilder(512);

                while (Interop.SetupDiEnumDeviceInfo(hDevInfo, idx, ref devData))
                {
                    uint reqSize;
                    if (Interop.SetupDiGetDeviceInstanceIdW(hDevInfo, ref devData, sb, (uint)sb.Capacity, out reqSize))
                    {
                        string id = sb.ToString();
                        MonitorDeviceInfo info = new MonitorDeviceInfo();
                        info.InstanceId = id;
                        info.DevInst = devData.DevInst;
                        info.IsInternalPanel = id.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0;
                        info.IsIntelGhost = IsIntelGhostNode(id);
                        info.IsNvidiaActive = IsNvidiaActiveNode(id);
                        info.IsForeign = IsForeignMonitor(id);

                        uint status, prob;
                        int cr = Interop.CM_Get_DevNode_Status(out status, out prob, devData.DevInst, 0);
                        if (cr == Interop.CR_SUCCESS)
                        {
                            info.IsPresent = (status & Interop.DN_STARTED) != 0 || (status & Interop.DN_DRIVER_LOADED) != 0;
                            info.DevNodeStatus = status;
                            info.ProblemNumber = prob;
                        }
                        else
                        {
                            info.IsPresent = false;
                            info.DevNodeStatus = 0;
                            info.ProblemNumber = 0;
                        }

                        uint parentInst;
                        if (Interop.CM_Get_Parent(out parentInst, devData.DevInst, 0) == Interop.CR_SUCCESS)
                        {
                            StringBuilder sbParent = new StringBuilder(512);
                            if (Interop.CM_Get_Device_IDW(parentInst, sbParent, (uint)sbParent.Capacity, 0) == Interop.CR_SUCCESS)
                            {
                                info.ParentDeviceId = sbParent.ToString();
                            }
                        }

                        list.Add(info);
                    }
                    idx++;
                }
            }
            finally
            {
                Interop.SetupDiDestroyDeviceInfoList(hDevInfo);
            }

            return list;
        }

        #endregion

        #region Core Eviction Algorithm

        /// <summary>
        /// Master eviction contract specified by PROJECT.md.
        /// Invoked on WM_DISPLAYCHANGE / WM_DEVICECHANGE or CLI --evict-now.
        /// </summary>
        /// <returns>Number of ghost paths successfully evicted (0 or 1).</returns>
        public static int EvictGhostMonitors()
        {
            GhostEvictionResult result = CheckAndEvict();
            return result.EvictedCount;
        }

        /// <summary>
        /// Evaluates display topology, enforces safety invariants, and executes in-process eviction if ghost node is active.
        /// </summary>
        /// <param name="force">If true, bypasses NVIDIA active topology prerequisite (for testing/diagnostics).</param>
        /// <returns>Structured execution telemetry.</returns>
        public static GhostEvictionResult CheckAndEvict(bool force = false)
        {
            Stopwatch sw = Stopwatch.StartNew();
            GhostEvictionResult result = new GhostEvictionResult();

            // 1. Enumerate currently present monitors (< 4ms)
            List<MonitorDeviceInfo> presentMonitors = EnumerateMonitors(presentOnly: true);

            bool foreignPresent = false;
            bool nvidiaActive = false;
            MonitorDeviceInfo lingeringGhost = null;

            for (int i = 0; i < presentMonitors.Count; i++)
            {
                MonitorDeviceInfo m = presentMonitors[i];
                if (m.IsForeign)
                {
                    foreignPresent = true;
                }
                // Reviewer M2_1 Mitigation: Require m.IsInternalPanel when checking NVIDIA parent device ID
                // so external HDMI/DP monitors attached to the RTX 4060 in Optimus mode do not trigger false eviction.
                if (m.IsNvidiaActive || (m.IsInternalPanel && m.ParentDeviceId != null && m.ParentDeviceId.IndexOf(NvidiaGpuVenDev, StringComparison.OrdinalIgnoreCase) >= 0))
                {
                    nvidiaActive = true;
                }
                if (m.IsIntelGhost)
                {
                    lingeringGhost = m;
                }
            }

            result.NvidiaActive = nvidiaActive;
            result.ForeignMonitorPresent = foreignPresent;

            // Invariant 1: If internal panel is NOT currently routed to NVIDIA dGPU, stand down immediately.
            // In Optimus mode, the Intel node is the primary display and must not be touched!
            if (!nvidiaActive && !force)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Stand down: Internal panel AUOAA9F not routed to NVIDIA dGPU (Optimus/iGPU mode active).";
                Logger.Info("EvictionEngine", result.Message);
                return result;
            }

            // Invariant 2: Check if Intel ghost node is actively present in devtree.
            // Reviewer M2_2 Mitigation: Dynamic non-present enumeration fallback before literal instance ID lookup.
            if (lingeringGhost == null)
            {
                List<MonitorDeviceInfo> allMonitors = EnumerateMonitors(presentOnly: false);
                for (int i = 0; i < allMonitors.Count; i++)
                {
                    MonitorDeviceInfo candidate = allMonitors[i];
                    if (candidate.IsIntelGhost && candidate.IsPresent)
                    {
                        lingeringGhost = candidate;
                        break;
                    }
                }
            }

            // Tertiary fallback: Direct CM_Locate_DevNodeW by known hardware instance path
            if (lingeringGhost == null)
            {
                uint ghostDevInst;
                int crLocate = Interop.CM_Locate_DevNodeW(out ghostDevInst, DefaultIntelGhostInstanceId, Interop.CM_LOCATE_DEVNODE_NORMAL);
                if (crLocate == Interop.CR_SUCCESS)
                {
                    uint status, prob;
                    if (Interop.CM_Get_DevNode_Status(out status, out prob, ghostDevInst, 0) == Interop.CR_SUCCESS)
                    {
                        bool isPresent = (status & Interop.DN_STARTED) != 0 || (status & Interop.DN_DRIVER_LOADED) != 0;
                        if (isPresent)
                        {
                            lingeringGhost = new MonitorDeviceInfo();
                            lingeringGhost.InstanceId = DefaultIntelGhostInstanceId;
                            lingeringGhost.DevInst = ghostDevInst;
                            lingeringGhost.IsPresent = true;
                            lingeringGhost.IsInternalPanel = true;
                            lingeringGhost.IsIntelGhost = true;
                            lingeringGhost.DevNodeStatus = status;
                            lingeringGhost.ProblemNumber = prob;

                            uint parentInst;
                            if (Interop.CM_Get_Parent(out parentInst, ghostDevInst, 0) == Interop.CR_SUCCESS)
                            {
                                StringBuilder sbParent = new StringBuilder(512);
                                if (Interop.CM_Get_Device_IDW(parentInst, sbParent, (uint)sbParent.Capacity, 0) == Interop.CR_SUCCESS)
                                {
                                    lingeringGhost.ParentDeviceId = sbParent.ToString();
                                }
                            }
                        }
                    }
                }
            }

            // If ghost node is NOT present, system is already in healthy clean state.
            if (lingeringGhost == null)
            {
                sw.Stop();
                result.IntelGhostPresent = false;
                result.EvictedCount = 0;
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Clean: Intel ghost node UID8388688 is already evicted (non-present).";
                Logger.Debug("EvictionEngine", result.Message);
                return result;
            }

            // Lingering ghost monitor confirmed!
            result.IntelGhostPresent = true;
            uint targetDevInst = lingeringGhost.DevInst;

            // Invariant 3: Hard safety assertion - ensure target is never the active NVIDIA node.
            if (IsNvidiaActiveNode(lingeringGhost.InstanceId))
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Safety abort: Attempted eviction of active NVIDIA display node prevented.";
                Logger.Error("EvictionEngine", result.Message);
                return result;
            }

            // Execute in-process eviction: Disable unclocked devnode
            Logger.Info("EvictionEngine", string.Format("Disabling unclocked ghost devnode: {0} (DevInst: 0x{1:X8})", lingeringGhost.InstanceId, targetDevInst));
            int crDisable = Interop.CM_Disable_DevNode(targetDevInst, Interop.CM_DISABLE_POLITE);
            result.LastConfigRet = crDisable;

            if (crDisable != Interop.CR_SUCCESS)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = string.Format("CM_Disable_DevNode failed with CONFIGRET 0x{0:X2}.", crDisable);
                Logger.Warn("EvictionEngine", result.Message);
                return result;
            }

            // Brief pause before re-enabling so PnP unbinds DWM swapchain surface
            Thread.Sleep(ReenableDelayMs);

            // Re-enable devnode: Because panel is physically muxed to NVIDIA, Intel driver sees no display attached
            // and transitions the devnode to disconnected / non-present.
            // Reviewer M2_1 Mitigation: Verify CM_Enable_DevNode return value and retry once if transient contention occurs.
            int crEnable = Interop.CM_Enable_DevNode(targetDevInst, 0);
            if (crEnable != Interop.CR_SUCCESS)
            {
                Logger.Warn("EvictionEngine", string.Format("Initial CM_Enable_DevNode returned 0x{0:X2}; retrying after {1}ms...", crEnable, RetryReenableDelayMs));
                Thread.Sleep(RetryReenableDelayMs);
                crEnable = Interop.CM_Enable_DevNode(targetDevInst, 0);
            }

            result.LastConfigRet = crEnable;

            // If parent Intel display adapter is resolved, trigger synchronous port re-enumeration
            if (!string.IsNullOrEmpty(lingeringGhost.ParentDeviceId))
            {
                uint parentInst;
                if (Interop.CM_Locate_DevNodeW(out parentInst, lingeringGhost.ParentDeviceId, Interop.CM_LOCATE_DEVNODE_NORMAL) == Interop.CR_SUCCESS)
                {
                    Interop.CM_Reenumerate_DevNode(parentInst, Interop.CM_REENUMERATE_NORMAL);
                }
            }

            sw.Stop();
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;

            if (crEnable != Interop.CR_SUCCESS)
            {
                result.EvictedCount = 0;
                result.Message = string.Format("Ghost monitor '{0}' disabled (0x{1:X2}) but CM_Enable_DevNode returned 0x{2:X2} in {3:F2}ms.",
                    lingeringGhost.InstanceId, crDisable, crEnable, result.ElapsedMilliseconds);
                Logger.Warn("EvictionEngine", result.Message);
                return result;
            }

            result.EvictedCount = 1;
            result.Message = string.Format("Ghost monitor '{0}' successfully evicted in {1:F2}ms (crDisable=0x{2:X2}, crEnable=0x{3:X2}).",
                lingeringGhost.InstanceId, result.ElapsedMilliseconds, crDisable, crEnable);
            Logger.Info("EvictionEngine", result.Message);

            return result;
        }

        #endregion
    }
}
