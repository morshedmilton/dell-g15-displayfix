Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class TestSetupApi
{
    public const uint DIGCF_DEFAULT = 0x00000001;
    public const uint DIGCF_PRESENT = 0x00000002;
    public const uint DIGCF_ALLCLASSES = 0x00000004;

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

    [DllImport("cfgmgr32.dll", SetLastError = true)]
    public static extern int CM_Get_Parent(out uint pdnDevInst, uint dnDevInst, uint ulFlags);

    [DllImport("cfgmgr32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern int CM_Get_Device_IDW(uint dnDevInst, StringBuilder Buffer, uint BufferLen, uint ulFlags);
}
"@

$monitorGuid = [Guid]::Parse("{4d36e96e-e325-11ce-bfc1-08002be10318}")
Write-Host "--- SetupAPI Enumeration: PRESENT ONLY (DIGCF_PRESENT) ---"
$hDevInfo = [TestSetupApi]::SetupDiGetClassDevsW([ref]$monitorGuid, $null, [IntPtr]::Zero, [TestSetupApi]::DIGCF_PRESENT)
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "hDevInfo=$hDevInfo, err=$err"

if ($hDevInfo -ne [IntPtr]-1) {
    $devData = New-Object TestSetupApi+SP_DEVINFO_DATA
    $devData.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devData)
    $idx = [uint32]0
    while ([TestSetupApi]::SetupDiEnumDeviceInfo($hDevInfo, $idx, [ref]$devData)) {
        $sb = New-Object System.Text.StringBuilder 512
        $req = [uint32]0
        [TestSetupApi]::SetupDiGetDeviceInstanceIdW($hDevInfo, [ref]$devData, $sb, $sb.Capacity, [ref]$req) | Out-Null
        
        $parentId = ""
        $parentInst = [uint32]0
        if ([TestSetupApi]::CM_Get_Parent([ref]$parentInst, $devData.DevInst, 0) -eq 0) {
            $sbParent = New-Object System.Text.StringBuilder 512
            [TestSetupApi]::CM_Get_Device_IDW($parentInst, $sbParent, $sbParent.Capacity, 0) | Out-Null
            $parentId = $sbParent.ToString()
        }

        Write-Host ("Index {0}: DevInst={1}, ID={2}, Parent={3}" -f $idx, $devData.DevInst, $sb.ToString(), $parentId)
        $idx++
    }
    [TestSetupApi]::SetupDiDestroyDeviceInfoList($hDevInfo) | Out-Null
}

Write-Host "--- SetupAPI Enumeration: ALL MONITORS (PRESENT + NON-PRESENT) ---"
$hDevInfoAll = [TestSetupApi]::SetupDiGetClassDevsW([ref]$monitorGuid, $null, [IntPtr]::Zero, 0)
if ($hDevInfoAll -ne [IntPtr]-1) {
    $devData = New-Object TestSetupApi+SP_DEVINFO_DATA
    $devData.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devData)
    $idx = [uint32]0
    while ([TestSetupApi]::SetupDiEnumDeviceInfo($hDevInfoAll, $idx, [ref]$devData)) {
        $sb = New-Object System.Text.StringBuilder 512
        $req = [uint32]0
        [TestSetupApi]::SetupDiGetDeviceInstanceIdW($hDevInfoAll, [ref]$devData, $sb, $sb.Capacity, [ref]$req) | Out-Null
        Write-Host ("All Index {0}: DevInst={1}, ID={2}" -f $idx, $devData.DevInst, $sb.ToString())
        $idx++
    }
    [TestSetupApi]::SetupDiDestroyDeviceInfoList($hDevInfoAll) | Out-Null
}
