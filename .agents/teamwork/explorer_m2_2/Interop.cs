// Interop.cs
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace DisplayFix.Daemon
{
    public static class Interop
    {
        public static readonly Guid GUID_DEVCLASS_MONITOR = new Guid("4d36e96e-e325-11ce-bfc1-08002be10318");
        public static readonly Guid GUID_DEVINTERFACE_MONITOR = new Guid("E6F07B5F-EE97-4A90-B076-33F57BF4EAA7");
        public static readonly Guid GUID_DEVINTERFACE_DISPLAY_ADAPTER = new Guid("5B45201D-F2F2-4F3B-85BB-30FF1F953599");
        public static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47");

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
        public const uint CM_PROB_DISABLED          = 22;
        public const uint CM_PROB_HARDWARE_DISABLED = 29;

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

        public const int WM_DISPLAYCHANGE   = 0x007E;
        public const int WM_POWERBROADCAST  = 0x0218;
        public const int WM_DEVICECHANGE    = 0x0219;
        public const int WM_DESTROY         = 0x0002;

        public const int DBT_DEVICEARRIVAL          = 0x8000;
        public const int DBT_DEVICEREMOVECOMPLETE   = 0x8004;
        public const int DBT_DEVTYP_DEVICEINTERFACE = 0x0005;

        public const int PBT_POWERSETTINGCHANGE = 0x8013;

        public static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);
        public const int DEVICE_NOTIFY_WINDOW_HANDLE = 0x00000000;

        [StructLayout(LayoutKind.Sequential)]
        public struct DEV_BROADCAST_HDR
        {
            public uint dbch_size;
            public uint dbch_devicetype;
            public uint dbch_reserved;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEV_BROADCAST_DEVICEINTERFACE
        {
            public uint dbcc_size;
            public uint dbcc_devicetype;
            public uint dbcc_reserved;
            public Guid dbcc_classguid;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string dbcc_name;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POWERBROADCAST_SETTING
        {
            public Guid PowerSetting;
            public uint DataLength;
            public byte Data;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterDeviceNotificationW(
            IntPtr hRecipient,
            IntPtr NotificationFilter,
            uint Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterDeviceNotification(IntPtr Handle);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr RegisterPowerSettingNotification(
            IntPtr hRecipient,
            ref Guid PowerSettingGuid,
            uint Flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterPowerSettingNotification(IntPtr Handle);
    }
}
