// .agents/teamwork/explorer_m3_1/Interop_M3_Extensions.cs
// Reference Compilable Blueprint for CCD & Display Settings P/Invoke additions to src/Daemon/Interop.cs
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Runtime.InteropServices;

namespace DisplayFix.Daemon
{
    public static partial class InteropCcdExtensions
    {
        #region Windows CCD & Display Settings Constants & Structures

        public const int ERROR_SUCCESS             = 0;
        public const int ERROR_ACCESS_DENIED       = 5;
        public const int ERROR_GEN_FAILURE         = 31;
        public const int ERROR_NOT_SUPPORTED       = 50;
        public const int ERROR_INVALID_PARAMETER   = 87;
        public const int ERROR_INSUFFICIENT_BUFFER = 122;

        public const uint QDC_ALL_PATHS         = 0x00000001;
        public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        public const uint QDC_DATABASE_CURRENT  = 0x00000004;

        public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
        public const uint SDC_VALIDATE                    = 0x00000040;
        public const uint SDC_APPLY                       = 0x00000080;
        public const uint SDC_NO_OPTIMIZATION             = 0x00000100;
        public const uint SDC_SAVE_TO_DATABASE            = 0x00000200;
        public const uint SDC_ALLOW_CHANGES               = 0x00000400;

        /// <summary>
        /// Combined CCD enforcement flags verified by Test F07.3:
        /// SDC_APPLY (0x80) | SDC_USE_SUPPLIED_DISPLAY_CONFIG (0x20) | SDC_SAVE_TO_DATABASE (0x200) | SDC_ALLOW_CHANGES (0x400) = 0x000006A0
        /// </summary>
        public const uint SDC_ENFORCE_FLAGS = SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES;

        /// <summary>
        /// Fallback CCD enforcement flags without database save (0x000004A0) when running without HKLM write elevation.
        /// </summary>
        public const uint SDC_ENFORCE_FLAGS_NO_SAVE = SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES;

        public const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE        = 1;
        public const uint DISPLAYCONFIG_MODE_INFO_TYPE_TARGET        = 2;
        public const uint DISPLAYCONFIG_MODE_INFO_TYPE_DESKTOP_IMAGE = 3;
        public const uint DISPLAYCONFIG_PATH_MODE_IDX_INVALID        = 0xFFFFFFFF;

        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME           = 1;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME           = 2;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_PREFERRED_MODE = 3;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME          = 4;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_TARGET_PERSISTENCE    = 5;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_BASE_TYPE      = 6;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE             = -3;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE             = -4;

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_RATIONAL
        {
            public uint Numerator;
            public uint Denominator;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_2DREGION
        {
            public uint cx;
            public uint cy;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
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
        public struct DISPLAYCONFIG_SOURCE_MODE
        {
            public uint width;
            public uint height;
            public uint pixelFormat;
            public int positionX;
            public int positionY;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_TARGET_MODE
        {
            public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct DISPLAYCONFIG_MODE_INFO_UNION
        {
            [FieldOffset(0)]
            public DISPLAYCONFIG_TARGET_MODE targetMode;

            [FieldOffset(0)]
            public DISPLAYCONFIG_SOURCE_MODE sourceMode;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_MODE_INFO
        {
            public uint infoType;
            public uint id;
            public LUID adapterId;
            public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
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
        public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
        {
            public int type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string viewGdiDeviceName;
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

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_ADAPTER_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string adapterDevicePath;
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

        public const int ENUM_CURRENT_SETTINGS  = -1;
        public const int ENUM_REGISTRY_SETTINGS = -2;

        public const int DM_BITSPERPEL       = 0x00040000;
        public const int DM_PELSWIDTH        = 0x00080000;
        public const int DM_PELSHEIGHT       = 0x00100000;
        public const int DM_DISPLAYFLAGS     = 0x00200000;
        public const int DM_DISPLAYFREQUENCY = 0x00400000;

        public const uint CDS_UPDATEREGISTRY = 0x00000001;
        public const uint CDS_TEST           = 0x00000002;
        public const uint CDS_GLOBAL         = 0x00000008;
        public const uint CDS_RESET          = 0x40000000;

        public const int DISP_CHANGE_SUCCESSFUL  = 0;
        public const int DISP_CHANGE_RESTART     = 1;
        public const int DISP_CHANGE_FAILED      = -1;
        public const int DISP_CHANGE_BADMODE     = -2;
        public const int DISP_CHANGE_NOTUPDATED  = -3;
        public const int DISP_CHANGE_BADFLAGS    = -4;
        public const int DISP_CHANGE_BADPARAM    = -5;
        public const int DISP_CHANGE_BADDUALVIEW = -6;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODEW
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
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
        public static extern int SetDisplayConfig(
            uint numPathArrayElements,
            [In] DISPLAYCONFIG_PATH_INFO[] pathArray,
            uint numModeInfoArrayElements,
            [In] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
            uint flags);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_ADAPTER_NAME requestPacket);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigSetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setPacket);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool EnumDisplaySettingsW(
            string lpszDeviceName,
            int iModeNum,
            ref DEVMODEW lpDevMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int ChangeDisplaySettingsExW(
            string lpszDeviceName,
            ref DEVMODEW lpDevMode,
            IntPtr hwnd,
            uint dwflags,
            IntPtr lParam);

        #endregion
    }
}
