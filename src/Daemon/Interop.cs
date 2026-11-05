// src/Daemon/Interop.cs
// High-performance Win32, SetupAPI, CfgMgr32, and Windows CCD P/Invoke interop layer for DisplayFixDaemon.
// Zero external NuGet packages. Targets .NET Framework 4.8 x64 (C# 5 compatible).

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace DisplayFix.Daemon
{
    public static class Interop
    {
        #region GUID Definitions

        /// <summary>
        /// Device setup class GUID for Monitor devices: {4d36e96e-e325-11ce-bfc1-08002be10318}
        /// </summary>
        public static readonly Guid GUID_DEVCLASS_MONITOR = new Guid("4d36e96e-e325-11ce-bfc1-08002be10318");

        /// <summary>
        /// Device interface class GUID for Monitor devices: {E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}
        /// </summary>
        public static readonly Guid GUID_DEVINTERFACE_MONITOR = new Guid("E6F07B5F-EE97-4A90-B076-33F57BF4EAA7");

        /// <summary>
        /// Device interface class GUID for Display Adapters: {5B45201D-F2F2-4F3B-85BB-30FF1F953599}
        /// </summary>
        public static readonly Guid GUID_DEVINTERFACE_DISPLAY_ADAPTER = new Guid("5B45201D-F2F2-4F3B-85BB-30FF1F953599");

        /// <summary>
        /// Power setting notification GUID for console display state: {6FE69556-704A-47A0-8F24-C28D936FDA47}
        /// </summary>
        public static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47");

        #endregion

        #region SetupAPI Constants & Structures

        public const uint DIGCF_DEFAULT         = 0x00000001;
        public const uint DIGCF_PRESENT         = 0x00000002;
        public const uint DIGCF_ALLCLASSES      = 0x00000004;
        public const uint DIGCF_PROFILE         = 0x00000008;
        public const uint DIGCF_DEVICEINTERFACE = 0x00000010;

        public static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        public const uint SPDRP_DEVICEDESC                  = 0x00000000;
        public const uint SPDRP_HARDWAREID                  = 0x00000001;
        public const uint SPDRP_COMPATIBLEIDS               = 0x00000002;
        public const uint SPDRP_CLASS                       = 0x00000007;
        public const uint SPDRP_CLASSGUID                   = 0x00000008;
        public const uint SPDRP_DRIVER                      = 0x00000009;
        public const uint SPDRP_CONFIGFLAGS                 = 0x0000000A;
        public const uint SPDRP_MFG                         = 0x0000000B;
        public const uint SPDRP_FRIENDLYNAME                = 0x0000000C;

        [StructLayout(LayoutKind.Sequential)]
        public struct SP_DEVINFO_DATA
        {
            public uint cbSize;
            public Guid ClassGuid;
            public uint DevInst;
            public IntPtr Reserved;
        }

        #endregion

        #region SetupAPI Functions

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

        [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SetupDiGetDeviceRegistryPropertyW(
            IntPtr DeviceInfoSet,
            ref SP_DEVINFO_DATA DeviceInfoData,
            uint Property,
            out uint PropertyRegDataType,
            [Out] byte[] PropertyBuffer,
            uint PropertyBufferSize,
            out uint RequiredSize);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

        #endregion

        #region CfgMgr32 Constants & Status Codes

        public const int CR_SUCCESS                 = 0x00000000;
        public const int CR_DEFAULT                 = 0x00000001;
        public const int CR_OUT_OF_MEMORY           = 0x00000002;
        public const int CR_INVALID_POINTER         = 0x00000003;
        public const int CR_INVALID_FLAG            = 0x00000004;
        public const int CR_INVALID_DEVNODE         = 0x0000000D;
        public const int CR_INVALID_DEVINST         = CR_INVALID_DEVNODE;
        public const int CR_NO_SUCH_DEVNODE         = 0x0000000E;
        public const int CR_NO_SUCH_DEVINST         = CR_NO_SUCH_DEVNODE;
        public const int CR_ALREADY_SUCH_DEVNODE    = 0x00000010;
        public const int CR_INVALID_DEVICE_ID       = 0x00000011;
        public const int CR_NOT_DISABLEABLE         = 0x00000021;
        public const int CR_ACCESS_DENIED           = 0x00000033;

        public const uint CM_LOCATE_DEVNODE_NORMAL       = 0x00000000;
        public const uint CM_LOCATE_DEVNODE_PHANTOM      = 0x00000001;
        public const uint CM_LOCATE_DEVNODE_CANCELREMOVE = 0x00000002;
        public const uint CM_LOCATE_DEVNODE_NOVALIDATION = 0x00000004;

        public const uint CM_DISABLE_POLITE     = 0x00000000;
        public const uint CM_DISABLE_ABSOLUTE   = 0x00000001;
        public const uint CM_DISABLE_HARDWARE   = 0x00000002;
        public const uint CM_DISABLE_UI_NOT_OK  = 0x00000004;

        public const uint CM_REENUMERATE_NORMAL             = 0x00000000;
        public const uint CM_REENUMERATE_SYNCHRONOUS        = 0x00000001;
        public const uint CM_REENUMERATE_RETRY_INSTALLATION = 0x00000002;
        public const uint CM_REENUMERATE_ASYNCHRONOUS       = 0x00000004;

        public const uint DN_ROOT_ENUMERATED    = 0x00000001;
        public const uint DN_DRIVER_LOADED      = 0x00000002;
        public const uint DN_ENUM_LOADED        = 0x00000004;
        public const uint DN_STARTED            = 0x00000008;
        public const uint DN_MANUAL             = 0x00000010;
        public const uint DN_NEED_TO_ENUM       = 0x00000020;
        public const uint DN_HAS_PROBLEM        = 0x00000400;
        public const uint DN_DISABLEABLE        = 0x00002000;
        public const uint DN_REMOVABLE          = 0x00004000;
        public const uint DN_WILL_BE_REMOVED    = 0x00040000;
        public const uint DN_NEEDS_LOCKING      = 0x02000000;

        public const uint CM_PROB_NOT_CONFIGURED    = 1;
        public const uint CM_PROB_OUT_OF_MEMORY     = 3;
        public const uint CM_PROB_DISABLED          = 22; // 0x16
        public const uint CM_PROB_HARDWARE_DISABLED = 29;

        #endregion

        #region CfgMgr32 Functions

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

        [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern int CM_Query_And_Remove_SubTreeW(
            uint dnDevInst,
            out uint pVetoType,
            [Out] StringBuilder pszVetoName,
            uint ulNameLength,
            uint ulFlags);

        #endregion

        #region User32 Window Message & Notification Constants & Functions

        public const int WM_DESTROY         = 0x0002;
        public const int WM_CLOSE           = 0x0010;
        public const int WM_DISPLAYCHANGE   = 0x007E;
        public const int WM_POWERBROADCAST  = 0x0218;
        public const int WM_DEVICECHANGE    = 0x0219;

        public const int DBT_DEVICEARRIVAL          = 0x8000;
        public const int DBT_DEVICEREMOVECOMPLETE   = 0x8004;
        public const int DBT_DEVNODES_CHANGED       = 0x0007;
        public const int DBT_DEVTYP_DEVICEINTERFACE = 0x0005;

        public const int PBT_POWERSETTINGCHANGE = 0x8013;

        public const int DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;

        public const int WS_POPUP = unchecked((int)0x80000000);
        public const int WS_EX_TOOLWINDOW = 0x00000080;

        public static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

        [StructLayout(LayoutKind.Sequential)]
        public struct DEV_BROADCAST_HDR
        {
            public uint dbch_size;
            public uint dbch_devicetype;
            public uint dbch_reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DEV_BROADCAST_DEVICEINTERFACE
        {
            public int dbcc_size;
            public int dbcc_devicetype;
            public int dbcc_reserved;
            public Guid dbcc_classguid;
            public short dbcc_name;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        public struct POWERBROADCAST_SETTING
        {
            public Guid PowerSetting;
            public int DataLength;
            public byte Data;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterDeviceNotification(
            IntPtr hRecipient,
            IntPtr NotificationFilter,
            int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterDeviceNotification(IntPtr Handle);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterPowerSettingNotification(
            IntPtr hRecipient,
            ref Guid PowerSettingGuid,
            int Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterPowerSettingNotification(IntPtr Handle);

        #endregion

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

        public const uint SDC_TOPOLOGY_INTERNAL           = 0x00000001;
        public const uint SDC_TOPOLOGY_CLONE              = 0x00000002;
        public const uint SDC_TOPOLOGY_EXTEND             = 0x00000004;
        public const uint SDC_TOPOLOGY_EXTERNAL           = 0x00000008;
        public const uint SDC_TOPOLOGY_SUPPLIED           = 0x00000010;
        public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
        public const uint SDC_VALIDATE                    = 0x00000040;
        public const uint SDC_APPLY                       = 0x00000080;
        public const uint SDC_NO_OPTIMIZATION             = 0x00000100;
        public const uint SDC_SAVE_TO_DATABASE            = 0x00000200;
        public const uint SDC_ALLOW_CHANGES               = 0x00000400;
        public const uint SDC_PATH_PERSIST_IF_REQUIRED    = 0x00000800;
        public const uint SDC_FORCE_MODE_ENUMERATION      = 0x00001000;
        public const uint SDC_ALLOW_PATH_ORDER_CHANGES    = 0x00002000;

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

        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME                = 1;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME                = 2;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_PREFERRED_MODE      = 3;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME               = 4;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_TARGET_PERSISTENCE         = 5;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_BASE_TYPE           = 6;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SUPPORT_VIRTUAL_RESOLUTION = 7;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_SUPPORT_VIRTUAL_RESOLUTION = 8;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO        = 9;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE       = 10;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL            = 11;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE                  = -3;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE                  = -4;

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
            public uint LowPart;
            public int HighPart;

            public override string ToString()
            {
                return string.Format("0x{0:X8}:0x{1:X8}", HighPart, LowPart);
            }
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

        /// <summary>
        /// 20-byte header for DisplayConfigGetDeviceInfo / DisplayConfigSetDeviceInfo packets.
        /// Layout: type (4B) + size (4B) + adapterId (8B) + id (4B) = 20 bytes.
        /// </summary>
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

        /// <summary>
        /// 32-byte packet for DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE (-3).
        /// Layout: header (20B) + minScaleRel (4B) + curScaleRel (4B) + maxScaleRel (4B) = 32 bytes.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int minScaleRel;
            public int curScaleRel;
            public int maxScaleRel;
        }

        /// <summary>
        /// 24-byte packet for DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE (-4).
        /// Layout: header (20B) + scaleRel (4B) = 24 bytes (verified by Test F09.3).
        /// </summary>
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

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
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

        [DllImport("user32.dll")]
        public static extern uint GetDpiForSystem();

        #endregion

        #region Milestone 4: Low-Level Keyboard Hook (WH_KEYBOARD_LL), SendInput, Raw Input & Acrylic OSD Interop

        public const int WH_KEYBOARD_LL = 13;

        public const int WM_KEYDOWN    = 0x0100;
        public const int WM_KEYUP      = 0x0101;
        public const int WM_SYSKEYDOWN = 0x0104;
        public const int WM_SYSKEYUP   = 0x0105;
        public const int WM_HOTKEY     = 0x0312;
        public const int WM_INPUT      = 0x00FF;

        // Virtual Key Codes for Function Row & Media Keys (Verified by Tests F10.1, F13.1-F13.4)
        public const int VK_F1  = 0x70; // 112 - Mute (VK_VOLUME_MUTE)
        public const int VK_F2  = 0x71; // 113 - Volume Down (VK_VOLUME_DOWN)
        public const int VK_F3  = 0x72; // 114 - Volume Up (VK_VOLUME_UP)
        public const int VK_F4  = 0x73; // 115
        public const int VK_F5  = 0x74; // 116
        public const int VK_F6  = 0x75; // 117 - Brightness Down
        public const int VK_F7  = 0x76; // 118 - Brightness Up
        public const int VK_F8  = 0x77; // 119
        public const int VK_F9  = 0x78; // 120 - Play/Pause (VK_MEDIA_PLAY_PAUSE)
        public const int VK_F10 = 0x79;
        public const int VK_F11 = 0x7A;
        public const int VK_F12 = 0x7B;

        public const ushort VK_VOLUME_MUTE      = 0xAD; // 173
        public const ushort VK_VOLUME_DOWN      = 0xAE; // 174
        public const ushort VK_VOLUME_UP        = 0xAF; // 175
        public const ushort VK_MEDIA_NEXT_TRACK = 0xB0; // 176
        public const ushort VK_MEDIA_PREV_TRACK = 0xB1; // 177
        public const ushort VK_MEDIA_STOP       = 0xB2; // 178
        public const ushort VK_MEDIA_PLAY_PAUSE = 0xB3; // 179

        // Modifier Virtual Key Codes for Bypass Verification (Test F10.3)
        public const int VK_SHIFT    = 0x10;
        public const int VK_CONTROL  = 0x11;
        public const int VK_MENU     = 0x12; // Alt
        public const int VK_LWIN     = 0x5B;
        public const int VK_RWIN     = 0x5C;
        public const int VK_LSHIFT   = 0xA0;
        public const int VK_RSHIFT   = 0xA1;
        public const int VK_LCONTROL = 0xA2;
        public const int VK_RCONTROL = 0xA3;
        public const int VK_LMENU    = 0xA4;
        public const int VK_RMENU    = 0xA5;

        public const int VK_UP   = 0x26;
        public const int VK_DOWN = 0x28;

        // KBDLLHOOKSTRUCT flags
        public const uint LLKHF_EXTENDED          = 0x00000001;
        public const uint LLKHF_LOWER_IL_INJECTED = 0x00000002;
        public const uint LLKHF_INJECTED          = 0x00000010;
        public const uint LLKHF_ALTDOWN           = 0x00000020;
        public const uint LLKHF_UP                = 0x00000080;

        /// <summary>
        /// Custom signature placed in dwExtraInfo when DisplayFixDaemon synthesizes media keys via SendInput
        /// to prevent recursive re-interception in WH_KEYBOARD_LL.
        /// </summary>
        public static readonly IntPtr DISPLAYFIX_SYNTHETIC_EXTRA_INFO = new IntPtr(0x44464958); // "DFIX"

        /// <summary>
        /// Low-level keyboard hook callback delegate. Must be pinned in a static field to prevent GC collection.
        /// </summary>
        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        /// <summary>
        /// 24-byte (on x64) low-level keyboard input event structure passed via lParam in WH_KEYBOARD_LL.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(
            int idHook,
            LowLevelKeyboardProc lpfn,
            IntPtr hMod,
            uint dwThreadId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr CallNextHookEx(
            IntPtr hhk,
            int nCode,
            IntPtr wParam,
            IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        // SendInput & Key Synthesis Structures (x64-Safe 40-Byte INPUT)
        public const uint INPUT_MOUSE    = 0;
        public const uint INPUT_KEYBOARD = 1;
        public const uint INPUT_HARDWARE = 2;

        public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        public const uint KEYEVENTF_KEYUP       = 0x0002;
        public const uint KEYEVENTF_UNICODE     = 0x0004;
        public const uint KEYEVENTF_SCANCODE    = 0x0008;

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION
        {
            [FieldOffset(0)]
            public MOUSEINPUT mi;

            [FieldOffset(0)]
            public KEYBDINPUT ki;

            [FieldOffset(0)]
            public HARDWAREINPUT hi;
        }

        /// <summary>
        /// 40-byte structure on 64-bit Windows (4-byte type + 4-byte alignment padding + 32-byte MOUSEINPUT union).
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public INPUTUNION u;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(
            uint nInputs,
            [In] INPUT[] pInputs,
            int cbSize);

        // Raw Input HID Consumer Control (UsagePage 0x0C, Usage 0x01)
        public const ushort HID_USAGE_PAGE_CONSUMER    = 0x000C;
        public const ushort HID_USAGE_CONSUMER_CONTROL = 0x0001;

        /// <summary>
        /// HID Consumer Control Brightness Increment (0x006F = 111) and Decrement (0x0070 = 112).
        /// Verified by Test F10.5.
        /// </summary>
        public const ushort HID_USAGE_BRIGHTNESS_INC = 0x006F; // 111
        public const ushort HID_USAGE_BRIGHTNESS_DEC = 0x0070; // 112

        public const uint RID_INPUT       = 0x10000003;
        public const uint RIM_TYPEHID     = 2;
        public const uint RIDEV_REMOVE    = 0x00000001;
        public const uint RIDEV_INPUTSINK = 0x00000100;

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTDEVICE
        {
            public ushort usUsagePage;
            public ushort usUsage;
            public uint dwFlags;
            public IntPtr hwndTarget;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTHEADER
        {
            public uint dwType;
            public uint dwSize;
            public IntPtr hDevice;
            public IntPtr wParam;
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterRawInputDevices(
            [In] RAWINPUTDEVICE[] pRawInputDevices,
            uint uiNumDevices,
            uint cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetRawInputData(
            IntPtr hRawInput,
            uint uiCommand,
            IntPtr pData,
            ref uint pcbSize,
            uint cbSizeHeader);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterHotKey(
            IntPtr hWnd,
            int id,
            uint fsModifiers,
            uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnregisterHotKey(
            IntPtr hWnd,
            int id);

        public const uint MOD_ALT      = 0x0001;
        public const uint MOD_CONTROL  = 0x0002;
        public const uint MOD_SHIFT    = 0x0004;
        public const uint MOD_WIN      = 0x0008;
        public const uint MOD_NOREPEAT = 0x4000;

        // Acrylic OSD Extended Window Styles (F14.1, S01.4)
        public const int WS_EX_TOPMOST     = 0x00000008;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_LAYERED     = 0x00080000;
        public const int WS_EX_NOACTIVATE  = 0x08000000;
        public const int SW_HIDE           = 0;
        public const int SW_SHOWNOACTIVATE = 4;
        public const uint SWP_NOACTIVATE   = 0x0010;
        public const uint SWP_SHOWWINDOW   = 0x0040;

        #endregion
    }
}
