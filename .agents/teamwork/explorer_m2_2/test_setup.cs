using System;
using System.Runtime.InteropServices;
using System.Text;

class Test
{
    public const uint DIGCF_PRESENT = 0x00000002;

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

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_DevNode_Status(out uint pulStatus, out uint pulProblemNumber, uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_Parent(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Get_Device_IDW(uint dnDevInst, StringBuilder Buffer, uint BufferLen, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Disable_DevNode(uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Enable_DevNode(uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Reenumerate_DevNode(uint dnDevInst, uint ulFlags);

    public const int CR_SUCCESS = 0x00000000;
    public const int CR_INVALID_DEVNODE = 0x0000000D;
    public const int CR_NO_SUCH_DEVNODE = 0x0000000E;

    static void Main()
    {
        Guid monitorGuid = new Guid("4d36e96e-e325-11ce-bfc1-08002be10318");

        Console.WriteLine("--- Enumerating All Monitors and Parents ---");
        IntPtr h = SetupDiGetClassDevsW(ref monitorGuid, null, IntPtr.Zero, 0);
        if (h != (IntPtr)(-1))
        {
            SP_DEVINFO_DATA data = new SP_DEVINFO_DATA();
            data.cbSize = (uint)Marshal.SizeOf(data);
            uint idx = 0;
            StringBuilder sb = new StringBuilder(512);
            while (SetupDiEnumDeviceInfo(h, idx, ref data))
            {
                uint req;
                SetupDiGetDeviceInstanceIdW(h, ref data, sb, (uint)sb.Capacity, out req);
                string instanceId = sb.ToString();

                uint status = 0, prob = 0;
                int crStatus = CM_Get_DevNode_Status(out status, out prob, data.DevInst, 0);

                string parentId = "";
                uint parentInst = 0;
                int crParent = CM_Get_Parent(out parentInst, data.DevInst, 0);
                if (crParent == CR_SUCCESS)
                {
                    StringBuilder sbParent = new StringBuilder(512);
                    CM_Get_Device_IDW(parentInst, sbParent, (uint)sbParent.Capacity, 0);
                    parentId = sbParent.ToString();
                }

                Console.WriteLine("Idx {0}: ID={1}", idx, instanceId);
                Console.WriteLine("   DevInst={0}, CM_Get_DevNode_Status: cr={1}, status=0x{2:X8}, prob={3}", 
                    data.DevInst, crStatus, status, prob);
                Console.WriteLine("   Parent: cr={0}, parentInst={1}, ParentID={2}",
                    crParent, parentInst, parentId);

                idx++;
            }
            SetupDiDestroyDeviceInfoList(h);
        }
    }
}
