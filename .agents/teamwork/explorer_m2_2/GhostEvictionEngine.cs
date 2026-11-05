// GhostEvictionEngine.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace DisplayFix.Daemon
{
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

    public static class GhostEvictionEngine
    {
        public const string InternalPanelModel = "AUOAA9F";
        public const string IntelGhostUidToken  = "UID8388688";
        public const string NvidiaActiveUidToken = "UID4353";
        public const string IntelGpuVenDev      = "VEN_8086&DEV_A78B";
        public const string NvidiaGpuVenDev     = "VEN_10DE&DEV_28E0";

        private const int ReenableDelayMs = 50;

        public static bool IsIntelGhostNode(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0 &&
                   instanceId.IndexOf(IntelGhostUidToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        public static bool IsNvidiaActiveNode(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0 &&
                   instanceId.IndexOf(NvidiaActiveUidToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        public static bool IsForeignMonitor(string instanceId)
        {
            if (string.IsNullOrEmpty(instanceId)) return false;
            return instanceId.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) < 0;
        }

        public static List<MonitorDeviceInfo> EnumerateMonitors(bool presentOnly = false)
        {
            var list = new List<MonitorDeviceInfo>();
            Guid monitorClass = Interop.GUID_DEVCLASS_MONITOR;
            uint flags = presentOnly ? Interop.DIGCF_PRESENT : 0;

            IntPtr hDevInfo = Interop.SetupDiGetClassDevsW(ref monitorClass, null, IntPtr.Zero, flags);
            if (hDevInfo == Interop.INVALID_HANDLE_VALUE)
            {
                return list;
            }

            try
            {
                var devData = new Interop.SP_DEVINFO_DATA();
                devData.cbSize = (uint)Marshal.SizeOf(typeof(Interop.SP_DEVINFO_DATA));
                uint idx = 0;
                StringBuilder sb = new StringBuilder(512);

                while (Interop.SetupDiEnumDeviceInfo(hDevInfo, idx, ref devData))
                {
                    uint reqSize;
                    if (Interop.SetupDiGetDeviceInstanceIdW(hDevInfo, ref devData, sb, (uint)sb.Capacity, out reqSize))
                    {
                        string id = sb.ToString();
                        var info = new MonitorDeviceInfo
                        {
                            InstanceId = id,
                            DevInst = devData.DevInst,
                            IsInternalPanel = id.IndexOf(InternalPanelModel, StringComparison.OrdinalIgnoreCase) >= 0,
                            IsIntelGhost = IsIntelGhostNode(id),
                            IsNvidiaActive = IsNvidiaActiveNode(id),
                            IsForeign = IsForeignMonitor(id)
                        };

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

        public static int EvictGhostMonitors()
        {
            GhostEvictionResult result = CheckAndEvict();
            return result.EvictedCount;
        }

        public static GhostEvictionResult CheckAndEvict(bool force = false)
        {
            var sw = Stopwatch.StartNew();
            var result = new GhostEvictionResult();

            var presentMonitors = EnumerateMonitors(presentOnly: true);

            bool foreignPresent = false;
            bool nvidiaActive = false;
            MonitorDeviceInfo lingeringGhost = null;

            foreach (var m in presentMonitors)
            {
                if (m.IsForeign)
                {
                    foreignPresent = true;
                }
                if (m.IsNvidiaActive || (m.ParentDeviceId != null && m.ParentDeviceId.IndexOf(NvidiaGpuVenDev, StringComparison.OrdinalIgnoreCase) >= 0))
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

            if (!nvidiaActive && !force)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Stand down: Internal panel AUOAA9F not routed to NVIDIA dGPU (Optimus/iGPU mode active).";
                return result;
            }

            if (lingeringGhost == null)
            {
                uint ghostDevInst;
                int crLocate = Interop.CM_Locate_DevNodeW(out ghostDevInst, @"DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688", Interop.CM_LOCATE_DEVNODE_NORMAL);
                if (crLocate == Interop.CR_SUCCESS)
                {
                    uint status, prob;
                    if (Interop.CM_Get_DevNode_Status(out status, out prob, ghostDevInst, 0) == Interop.CR_SUCCESS)
                    {
                        lingeringGhost = new MonitorDeviceInfo
                        {
                            InstanceId = @"DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688",
                            DevInst = ghostDevInst,
                            IsPresent = true,
                            IsIntelGhost = true
                        };
                    }
                }
            }

            if (lingeringGhost == null)
            {
                sw.Stop();
                result.IntelGhostPresent = false;
                result.EvictedCount = 0;
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Clean: Intel ghost node UID8388688 is already evicted (non-present).";
                return result;
            }

            result.IntelGhostPresent = true;
            uint targetDevInst = lingeringGhost.DevInst;

            if (IsNvidiaActiveNode(lingeringGhost.InstanceId))
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = "Safety abort: Attempted eviction of active NVIDIA display node prevented.";
                return result;
            }

            int crDisable = Interop.CM_Disable_DevNode(targetDevInst, Interop.CM_DISABLE_POLITE);
            result.LastConfigRet = crDisable;

            if (crDisable != Interop.CR_SUCCESS)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Message = string.Format("CM_Disable_DevNode failed with CONFIGRET 0x{0:X2}.", crDisable);
                return result;
            }

            Thread.Sleep(ReenableDelayMs);

            int crEnable = Interop.CM_Enable_DevNode(targetDevInst, 0);

            if (!string.IsNullOrEmpty(lingeringGhost.ParentDeviceId))
            {
                uint parentInst;
                if (Interop.CM_Locate_DevNodeW(out parentInst, lingeringGhost.ParentDeviceId, Interop.CM_LOCATE_DEVNODE_NORMAL) == Interop.CR_SUCCESS)
                {
                    Interop.CM_Reenumerate_DevNode(parentInst, Interop.CM_REENUMERATE_NORMAL);
                }
            }

            sw.Stop();
            result.EvictedCount = 1;
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
            result.Message = string.Format("Ghost monitor '{0}' successfully evicted in {1:F2}ms (crDisable=0x{2:X2}, crEnable=0x{3:X2}).",
                lingeringGhost.InstanceId, result.ElapsedMilliseconds, crDisable, crEnable);

            return result;
        }
    }
}
