using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

class Benchmark
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
        string Enumerator,
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

    static void Main()
    {
        Guid monitorGuid = new Guid("4d36e96e-e325-11ce-bfc1-08002be10318");
        Stopwatch sw = Stopwatch.StartNew();

        // 1. Enumerate present monitors via SetupAPI
        IntPtr h = SetupDiGetClassDevsW(ref monitorGuid, null, IntPtr.Zero, DIGCF_PRESENT);
        int presentCount = 0;
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
                presentCount++;
                idx++;
            }
            SetupDiDestroyDeviceInfoList(h);
        }
        sw.Stop();
        Console.WriteLine("SetupAPI DIGCF_PRESENT enumeration took: " + sw.Elapsed.TotalMilliseconds + " ms (count=" + presentCount + ")");

        // 2. Locate node directly via CM_Locate_DevNodeW
        sw.Restart();
        uint devInst;
        int cr = CM_Locate_DevNodeW(out devInst, @"DISPLAY\AUOAA9F\5&39808DAE&2&UID4353", 0);
        sw.Stop();
        Console.WriteLine("CM_Locate_DevNodeW took: " + sw.Elapsed.TotalMilliseconds + " ms (cr=" + cr + ", devInst=" + devInst + ")");
    }
}
