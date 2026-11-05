# .agents/teamwork/explorer_m3_2/probe_ccd_dpi.ps1
# Live empirical verification of CCD DPI GET (-3) and SET (-4) structures and calls.

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class CcdDpiProbe
{
    public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE   = -3;
    public const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE   = -4;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public int type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int minScaleRel;
        public int curScaleRel;
        public int maxScaleRel;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int scaleRel;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAYCONFIG_TARGET_DEVICE_NAME
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

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL
    {
        public uint Numerator;
        public uint Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering;
        public int targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO
    {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public byte[] modeInfo;
    }

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(
        uint flags,
        out uint numPathArrayElements,
        out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(
        uint flags,
        ref uint numPathArrayElements,
        [In, Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray,
        ref uint numModeInfoArrayElements,
        [In, Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

    public static void ProbeAll()
    {
        uint numPaths = 0, numModes = 0;
        int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
        Console.WriteLine(string.Format("GetDisplayConfigBufferSizes: rc={0} paths={1} modes={2}", rc, numPaths, numModes));

        DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[numPaths];
        DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[numModes];
        rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
        Console.WriteLine(string.Format("QueryDisplayConfig: rc={0}", rc));

        for (int i = 0; i < numPaths; i++)
        {
            DISPLAYCONFIG_PATH_INFO p = paths[i];

            DISPLAYCONFIG_TARGET_DEVICE_NAME targetName = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            targetName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            targetName.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            targetName.header.adapterId = p.targetInfo.adapterId;
            targetName.header.id = p.targetInfo.id;
            int rcTarget = DisplayConfigGetDeviceInfo(ref targetName);
            Console.WriteLine(string.Format("Path[{0}] TargetName rc={1}: DevicePath='{2}'",
                i, rcTarget, targetName.monitorDevicePath));

            DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getPacket = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
            getPacket.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
            getPacket.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
            getPacket.header.adapterId = p.sourceInfo.adapterId;
            getPacket.header.id = p.sourceInfo.id;
            int rcGet = DisplayConfigGetDeviceInfo(ref getPacket);
            Console.WriteLine(string.Format("Path[{0}] GET_DPI_SCALE (size={1}) rc={2}: minScaleRel={3}, curScaleRel={4}, maxScaleRel={5}",
                i, getPacket.header.size, rcGet, getPacket.minScaleRel, getPacket.curScaleRel, getPacket.maxScaleRel));

            DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setPacket = new DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
            setPacket.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
            setPacket.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET));
            setPacket.header.adapterId = p.sourceInfo.adapterId;
            setPacket.header.id = p.sourceInfo.id;
            setPacket.scaleRel = 0;
            int rcSet = DisplayConfigSetDeviceInfo(ref setPacket);
            Console.WriteLine(string.Format("Path[{0}] SET_DPI_SCALE (size={1}, scaleRel=0) rc={2}",
                i, setPacket.header.size, rcSet));
        }
    }
}
"@

[CcdDpiProbe]::ProbeAll()
