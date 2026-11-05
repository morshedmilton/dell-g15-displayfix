Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class TestSetupApi2
{
    public const uint DIGCF_DEFAULT = 0x00000001;
    public const uint DIGCF_PRESENT = 0x00000002;
    public const uint DIGCF_ALLCLASSES = 0x00000004;
    public const uint DIGCF_DEVICEINTERFACE = 0x00000010;

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVINFO_DATA
    {
        public uint cbSize;
        public Guid ClassGuid;
        public uint DevInst;
        public IntPtr Reserved;
    }

    [DllImport("setupapi.dll", SetLastError = true)]
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
}
"@

$monitorGuid = [Guid]::Parse("{4d36e96e-e325-11ce-bfc1-08002be10318}")
$guidPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
[System.Runtime.InteropServices.Marshal]::StructureToPtr($monitorGuid, $guidPtr, $false)

$hDevInfo = [TestSetupApi2]::SetupDiGetClassDevsW($guidPtr, $null, [IntPtr]::Zero, [TestSetupApi2]::DIGCF_PRESENT)
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "hDevInfo=$hDevInfo, err=$err"

if ($hDevInfo -ne [IntPtr]-1) {
    $devData = New-Object TestSetupApi2+SP_DEVINFO_DATA
    $devData.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devData)
    $idx = [uint32]0
    while ([TestSetupApi2]::SetupDiEnumDeviceInfo($hDevInfo, $idx, [ref]$devData)) {
        $sb = New-Object System.Text.StringBuilder 512
        $req = [uint32]0
        [TestSetupApi2]::SetupDiGetDeviceInstanceIdW($hDevInfo, [ref]$devData, $sb, $sb.Capacity, [ref]$req) | Out-Null
        Write-Host "Device: $($sb.ToString())"
        $idx++
    }
    $enumErr = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "Enum completed: count=$idx, lastErr=$enumErr"
    [TestSetupApi2]::SetupDiDestroyDeviceInfoList($hDevInfo) | Out-Null
}
[System.Runtime.InteropServices.Marshal]::FreeHGlobal($guidPtr)
