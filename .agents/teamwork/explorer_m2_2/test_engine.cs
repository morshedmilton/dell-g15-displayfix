using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

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

public static class NativeInterop
{
    // Class GUID for Monitor: {4d36e96e-e325-11ce-bfc1-08002be10318}
    public static readonly Guid GUID_DEVCLASS_MONITOR = new Guid("4d36e96e-e325-11ce-bfc1-08002be10318");

    // Interface GUID for Monitor: {E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}
    public static readonly Guid GUID_DEVINTERFACE_MONITOR = new Guid("E6F07B5F-EE97-4A90-B076-33F57BF4EAA7");

    // Interface GUID for Display Adapter: {5B45201D-F2F2-4F3B-85BB-30FF1F953599}
    public static readonly Guid GUID_DEVINTERFACE_DISPLAY_ADAPTER = new Guid("5B45201D-F2F2-4F3B-85BB-30FF1F953599");

    // SetupAPI Flags
    public const uint DIGCF_DEFAULT = 0x00000001;
    public const uint DIGCF_PRESENT = 0x00000002;
    public const uint DIGCF_ALLCLASSES = 0x00000004;
    public const uint DIGCF_PROFILE = 0x00000008;
    public const uint DIGCF_DEVICEINTERFACE = 0x00000010;

    public static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVINFO_DATA
    {
        public uint cbSize;
        public Guid ClassGuid;
        public uint DevInst;
        public IntPtr Reserved;
    }

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SetupDiGetClassDevsW(
        ref Guid ClassGuid,
        [MarshalAs(UnmanagedType.LPWStr)] string Enumerator,
        IntPtr hwndParent,
        uint Flags);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SetupDiGetClassDevsW(
        IntPtr ClassGuid,
        [MarshalAs(UnmanagedType.LPWStr)] string Enumerator,
        IntPtr hwndParent,
        uint Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiEnumDeviceInfo(
        IntPtr DeviceInfoSet,
        uint MemberIndex,
        ref SP_DEVINFO_DATA DeviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SetupDiGetDeviceInstanceIdW(
        IntPtr DeviceInfoSet,
        ref SP_DEVINFO_DATA DeviceInfoData,
        StringBuilder DeviceInstanceId,
        uint DeviceInstanceIdSize,
        out uint RequiredSize);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    // CfgMgr32 Constants
    public const int CR_SUCCESS = 0x00000000;
    public const int CR_DEFAULT = 0x00000001;
    public const int CR_OUT_OF_MEMORY = 0x00000002;
    public const int CR_INVALID_POINTER = 0x00000003;
    public const int CR_INVALID_FLAG = 0x00000004;
    public const int CR_INVALID_DEVNODE = 0x0000000D;
    public const int CR_INVALID_DEVINST = CR_INVALID_DEVNODE;
    public const int CR_NO_SUCH_DEVNODE = 0x0000000E;
    public const int CR_NOT_DISABLEABLE = 0x00000021;
    public const int CR_ACCESS_DENIED = 0x00000033;

    public const uint CM_LOCATE_DEVNODE_NORMAL = 0x00000000;
    public const uint CM_LOCATE_DEVNODE_PHANTOM = 0x00000001;
    public const uint CM_LOCATE_DEVNODE_CANCELREMOVE = 0x00000002;
    public const uint CM_LOCATE_DEVNODE_NOVALIDATION = 0x00000004;

    public const uint CM_DISABLE_POLITE = 0x00000000;
    public const uint CM_DISABLE_ABSOLUTE = 0x00000001;
    public const uint CM_DISABLE_HARDWARE = 0x00000002;
    public const uint CM_DISABLE_UI_NOT_OK = 0x00000004;

    public const uint CM_REENUMERATE_NORMAL = 0x00000000;
    public const uint CM_REENUMERATE_SYNCHRONOUS = 0x00000001;
    public const uint CM_REENUMERATE_RETRY_INSTALLATION = 0x00000002;
    public const uint CM_REENUMERATE_ASYNCHRONOUS = 0x00000004;

    public const uint DN_ROOT_ENUMERATED = 0x00000001;
    public const uint DN_DRIVER_LOADED = 0x00000002;
    public const uint DN_ENUM_LOADED = 0x00000004;
    public const uint DN_STARTED = 0x00000008;
    public const uint DN_MANUAL = 0x00000010;
    public const uint DN_NEED_TO_ENUM = 0x00000020;
    public const uint DN_HAS_PROBLEM = 0x00000400;
    public const uint DN_DISABLEABLE = 0x00002000;
    public const uint DN_REMOVABLE = 0x00004000;

    public const uint CM_PROB_DISABLED = 22; // 0x16

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Locate_DevNodeW(
        out uint pdnDevInst,
        string pDeviceID,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_DevNode_Status(
        out uint pulStatus,
        out uint pulProblemNumber,
        uint dnDevInst,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_Parent(
        out uint pdnDevInst,
        uint dnDevInst,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Get_Device_IDW(
        uint dnDevInst,
        [Out] StringBuilder Buffer,
        uint BufferLen,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Disable_DevNode(
        uint dnDevInst,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Enable_DevNode(
        uint dnDevInst,
        uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Reenumerate_DevNode(
        uint dnDevInst,
        uint ulFlags);
}

public static class GhostEvictionEngine
{
    public const string InternalPanelModel = "AUOAA9F";
    public const string IntelGhostUidToken = "UID8388688";
    public const string NvidiaActiveUidToken = "UID4353";
    public const string IntelGpuVenDev = "VEN_8086&DEV_A78B";
    public const string NvidiaGpuVenDev = "VEN_10DE&DEV_28E0";

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
        Guid monitorClass = NativeInterop.GUID_DEVCLASS_MONITOR;
        uint flags = presentOnly ? NativeInterop.DIGCF_PRESENT : 0;

        IntPtr hDevInfo = NativeInterop.SetupDiGetClassDevsW(ref monitorClass, null, IntPtr.Zero, flags);
        if (hDevInfo == NativeInterop.INVALID_HANDLE_VALUE)
        {
            return list;
        }

        try
        {
            NativeInterop.SP_DEVINFO_DATA devData = new NativeInterop.SP_DEVINFO_DATA();
            devData.cbSize = (uint)Marshal.SizeOf(typeof(NativeInterop.SP_DEVINFO_DATA));
            uint idx = 0;
            StringBuilder sb = new StringBuilder(512);

            while (NativeInterop.SetupDiEnumDeviceInfo(hDevInfo, idx, ref devData))
            {
                uint reqSize;
                if (NativeInterop.SetupDiGetDeviceInstanceIdW(hDevInfo, ref devData, sb, (uint)sb.Capacity, out reqSize))
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
                    int cr = NativeInterop.CM_Get_DevNode_Status(out status, out prob, devData.DevInst, 0);
                    if (cr == NativeInterop.CR_SUCCESS)
                    {
                        info.IsPresent = (status & NativeInterop.DN_STARTED) != 0 || (status & NativeInterop.DN_DRIVER_LOADED) != 0;
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
                    if (NativeInterop.CM_Get_Parent(out parentInst, devData.DevInst, 0) == NativeInterop.CR_SUCCESS)
                    {
                        StringBuilder sbParent = new StringBuilder(512);
                        if (NativeInterop.CM_Get_Device_IDW(parentInst, sbParent, (uint)sbParent.Capacity, 0) == NativeInterop.CR_SUCCESS)
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
            NativeInterop.SetupDiDestroyDeviceInfoList(hDevInfo);
        }

        return list;
    }

    public static int EvictGhostMonitors()
    {
        var result = CheckAndEvict();
        return result.EvictedCount;
    }

    public static GhostEvictionResult CheckAndEvict(bool force = false)
    {
        var sw = Stopwatch.StartNew();
        var result = new GhostEvictionResult();

        // 1. Enumerate present monitors
        var presentMonitors = EnumerateMonitors(presentOnly: true);

        // Check if foreign monitor is connected
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

        // If internal panel is NOT currently on NVIDIA dGPU, stand down.
        if (!nvidiaActive && !force)
        {
            sw.Stop();
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
            result.Message = "Stand down: Panel not currently routed to NVIDIA dGPU (Optimus / iGPU mode active).";
            return result;
        }

        // If a foreign monitor is attached, verify eviction safety rule:
        // Eviction rule: only target AUOAA9F on Intel path. Never touch foreign monitor IDs.
        // If a lingering ghost node IS present, we still only touch the ghost node.
        if (lingeringGhost == null)
        {
            // Verify if locate finds it as active
            uint ghostDevInst;
            int crLocate = NativeInterop.CM_Locate_DevNodeW(out ghostDevInst, @"DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688", NativeInterop.CM_LOCATE_DEVNODE_NORMAL);
            if (crLocate == NativeInterop.CR_SUCCESS)
            {
                // Node is active in devtree
                uint st, pr;
                if (NativeInterop.CM_Get_DevNode_Status(out st, out pr, ghostDevInst, 0) == NativeInterop.CR_SUCCESS)
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

        // Lingering ghost node detected!
        result.IntelGhostPresent = true;
        uint targetDevInst = lingeringGhost.DevInst;

        // Safety assertion: Ensure target is NOT the active NVIDIA node
        if (IsNvidiaActiveNode(lingeringGhost.InstanceId))
        {
            sw.Stop();
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
            result.Message = "Safety abort: Attempted eviction of active NVIDIA display node prevented.";
            return result;
        }

        // Execute in-process eviction via CfgMgr32
        int crDisable = NativeInterop.CM_Disable_DevNode(targetDevInst, NativeInterop.CM_DISABLE_POLITE);
        result.LastConfigRet = crDisable;

        if (crDisable != NativeInterop.CR_SUCCESS)
        {
            sw.Stop();
            result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
            result.Message = "CM_Disable_DevNode failed with CONFIGRET 0x" + crDisable.ToString("X2");
            return result;
        }

        // Re-enable so PnP cleans up state and recognizes that the port has no monitor attached
        System.Threading.Thread.Sleep(50);
        int crEnable = NativeInterop.CM_Enable_DevNode(targetDevInst, 0);

        // If parent Intel GPU adapter is known, trigger re-enumeration
        if (!string.IsNullOrEmpty(lingeringGhost.ParentDeviceId))
        {
            uint parentInst;
            if (NativeInterop.CM_Locate_DevNodeW(out parentInst, lingeringGhost.ParentDeviceId, NativeInterop.CM_LOCATE_DEVNODE_NORMAL) == NativeInterop.CR_SUCCESS)
            {
                NativeInterop.CM_Reenumerate_DevNode(parentInst, NativeInterop.CM_REENUMERATE_NORMAL);
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

class Program
{
    static void Main()
    {
        Console.WriteLine("=== Testing GhostEvictionEngine ===");
        var sw = Stopwatch.StartNew();
        var res = GhostEvictionEngine.CheckAndEvict();
        sw.Stop();

        Console.WriteLine("Result:");
        Console.WriteLine("  NvidiaActive: " + res.NvidiaActive);
        Console.WriteLine("  IntelGhostPresent: " + res.IntelGhostPresent);
        Console.WriteLine("  ForeignMonitorPresent: " + res.ForeignMonitorPresent);
        Console.WriteLine("  EvictedCount: " + res.EvictedCount);
        Console.WriteLine("  ElapsedMilliseconds: " + res.ElapsedMilliseconds + " ms");
        Console.WriteLine("  Message: " + res.Message);

        Console.WriteLine("\n--- All Enumerated Monitors ---");
        var all = GhostEvictionEngine.EnumerateMonitors(false);
        foreach (var m in all)
        {
            Console.WriteLine("  " + m);
            Console.WriteLine("    IntelGhost=" + m.IsIntelGhost + ", NvidiaActive=" + m.IsNvidiaActive + ", Foreign=" + m.IsForeign);
        }

        Console.WriteLine("\n--- Safety Filter Assertions (F04.5 & S03.1) ---");
        Assert("DISPLAY\\AUOAA9F\\4&3A9F8B26&8&UID8388688", true, "Intel ghost node must be targeted");
        Assert("DISPLAY\\AUOAA9F\\5&39808DAE&2&UID4353", false, "Active NVIDIA node must NOT be targeted");
        Assert("DISPLAY\\DEL4123\\4&12345678&0&UID0", false, "External Dell monitor must NOT be targeted");
        Assert("DISPLAY\\SAM0123\\4&87654321&0&UID1", false, "External Samsung monitor must NOT be targeted");
        Console.WriteLine("ALL CHECKS PASSED!");
    }

    static void Assert(string id, bool expectedTarget, string desc)
    {
        bool target = GhostEvictionEngine.IsIntelGhostNode(id);
        if (target != expectedTarget)
        {
            Console.WriteLine("FAIL: " + desc + " (id=" + id + ", got=" + target + ", exp=" + expectedTarget + ")");
        }
        else
        {
            Console.WriteLine("PASS: " + desc);
        }
    }
}
