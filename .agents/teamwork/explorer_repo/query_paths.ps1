# Query Display Config Detailed Paths
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class QdcDetails {
    private const int QDC_ALL_PATHS = 1;
    private const int QDC_ONLY_ACTIVE_PATHS = 2;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO {
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
    public struct DISPLAYCONFIG_PATH_INFO {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_2DREGION { public uint cx; public uint cy; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO {
        public ulong pixelRate;
        public DISPLAYCONFIG_RATIONAL hSyncFreq;
        public DISPLAYCONFIG_RATIONAL vSyncFreq;
        public DISPLAYCONFIG_2DREGION activeSize;
        public DISPLAYCONFIG_2DREGION totalSize;
        public uint videoStandard;
        public uint scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_TARGET_MODE { public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo; }

    [StructLayout(LayoutKind.Explicit)]
    public struct DISPLAYCONFIG_MODE_INFO_UNION {
        [FieldOffset(0)] public DISPLAYCONFIG_TARGET_MODE targetMode;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
        public int type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
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
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(
        uint flags,
        ref uint numPathArrayElements,
        [Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray,
        ref uint numModeInfoArrayElements,
        [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME deviceName);

    public static void Run() {
        uint numPaths, numModes;
        int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
        Console.WriteLine("QDC_ONLY_ACTIVE_PATHS: paths=" + numPaths + " modes=" + numModes + " rc=" + rc);

        DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[numPaths];
        DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[numModes];
        rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
        Console.WriteLine("QueryDisplayConfig rc=" + rc);

        for (int i = 0; i < numPaths; i++) {
            var p = paths[i];
            double hz = (p.targetInfo.refreshRateDenominator > 0)
                ? (double)p.targetInfo.refreshRateNumerator / p.targetInfo.refreshRateDenominator
                : 0.0;
            Console.WriteLine(string.Format("Path {0}: Adapter={1}:{2} TargetAdapter={3}:{4} ModeIdx={5} Refresh={6:F2}Hz Flags=0x{7:X}",
                i, p.sourceInfo.adapterId.HighPart, p.sourceInfo.adapterId.LowPart,
                p.targetInfo.adapterId.HighPart, p.targetInfo.adapterId.LowPart,
                p.targetInfo.modeInfoIdx, hz, p.flags));

            DISPLAYCONFIG_TARGET_DEVICE_NAME dev = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            dev.header.type = 2; // DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME
            dev.header.size = (uint)Marshal.SizeOf(dev);
            dev.header.adapterId = p.targetInfo.adapterId;
            dev.header.id = p.targetInfo.id;
            int devRc = DisplayConfigGetDeviceInfo(ref dev);
            if (devRc == 0) {
                Console.WriteLine("  FriendlyName: " + dev.monitorFriendlyDeviceName);
                Console.WriteLine("  DevicePath:   " + dev.monitorDevicePath);
            }
        }

        Console.WriteLine("\n--- QDC_ALL_PATHS ---");
        uint allP, allM;
        rc = GetDisplayConfigBufferSizes(QDC_ALL_PATHS, out allP, out allM);
        Console.WriteLine("QDC_ALL_PATHS: paths=" + allP + " modes=" + allM + " rc=" + rc);
        DISPLAYCONFIG_PATH_INFO[] pathsAll = new DISPLAYCONFIG_PATH_INFO[allP];
        DISPLAYCONFIG_MODE_INFO[] modesAll = new DISPLAYCONFIG_MODE_INFO[allM];
        rc = QueryDisplayConfig(QDC_ALL_PATHS, ref allP, pathsAll, ref allM, modesAll, IntPtr.Zero);
        Console.WriteLine("QueryDisplayConfig QDC_ALL_PATHS rc=" + rc);
        for (int i = 0; i < allP; i++) {
            var p = pathsAll[i];
            double hz = (p.targetInfo.refreshRateDenominator > 0)
                ? (double)p.targetInfo.refreshRateNumerator / p.targetInfo.refreshRateDenominator
                : 0.0;
            Console.WriteLine(string.Format("All Path {0}: Adapter={1}:{2} TargetAdapter={3}:{4} ModeIdx={5} Refresh={6:F2}Hz Flags=0x{7:X} TargetAvailable={8}",
                i, p.sourceInfo.adapterId.HighPart, p.sourceInfo.adapterId.LowPart,
                p.targetInfo.adapterId.HighPart, p.targetInfo.adapterId.LowPart,
                p.targetInfo.modeInfoIdx, hz, p.flags, p.targetInfo.targetAvailable));

            DISPLAYCONFIG_TARGET_DEVICE_NAME dev = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            dev.header.type = 2;
            dev.header.size = (uint)Marshal.SizeOf(dev);
            dev.header.adapterId = p.targetInfo.adapterId;
            dev.header.id = p.targetInfo.id;
            int devRc = DisplayConfigGetDeviceInfo(ref dev);
            if (devRc == 0) {
                Console.WriteLine("  FriendlyName: " + dev.monitorFriendlyDeviceName);
                Console.WriteLine("  DevicePath:   " + dev.monitorDevicePath);
            }
        }
    }
}
'@
[QdcDetails]::Run()
