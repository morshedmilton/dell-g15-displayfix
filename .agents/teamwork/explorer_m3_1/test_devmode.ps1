Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class TestDevModeW
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_TEST = 0x00000002;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;
    public const int DM_PELSWIDTH = 0x00080000;
    public const int DM_PELSHEIGHT = 0x00100000;

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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODEW lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsExW(string lpszDeviceName, ref DEVMODEW lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);
}
"@

$dm = New-Object TestDevModeW+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
Write-Host "DEVMODEW size: $($dm.dmSize)"
$retEnum = [TestDevModeW]::EnumDisplaySettingsW($null, [TestDevModeW]::ENUM_CURRENT_SETTINGS, [ref]$dm)
Write-Host "EnumDisplaySettingsW ret=$retEnum, freq=$($dm.dmDisplayFrequency), width=$($dm.dmPelsWidth), height=$($dm.dmPelsHeight)"

$retTest = [TestDevModeW]::ChangeDisplaySettingsExW($null, [ref]$dm, [IntPtr]::Zero, [TestDevModeW]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsExW (CDS_TEST): ret=$retTest (0 = DISP_CHANGE_SUCCESSFUL)"
