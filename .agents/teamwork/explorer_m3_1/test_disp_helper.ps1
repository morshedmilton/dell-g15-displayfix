Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DisplaySettingsHelper
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_TEST = 0x00000002;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct DEVMODE
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

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);
}
"@

Add-Type -AssemblyName System.Windows.Forms
$primary = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName
Write-Host "Primary screen: $primary"

$dm = New-Object DisplaySettingsHelper+DEVMODE
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$ret = [DisplaySettingsHelper]::EnumDisplaySettings($primary, [DisplaySettingsHelper]::ENUM_CURRENT_SETTINGS, [ref]$dm)
Write-Host "EnumDisplaySettings: ret=$ret, dmSize=$($dm.dmSize), freq=$($dm.dmDisplayFrequency), fields=0x$($dm.dmFields.ToString('X8'))"

# Test 1: with dmSize returned by EnumDisplaySettings (188)
$rcTest1 = [DisplaySettingsHelper]::ChangeDisplaySettingsEx($primary, [ref]$dm, [IntPtr]::Zero, [DisplaySettingsHelper]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsEx (CDS_TEST) with dmSize=$($dm.dmSize): ret=$rcTest1"

# Test 2: with dmSize = 220
$dm.dmSize = 220
$rcTest2 = [DisplaySettingsHelper]::ChangeDisplaySettingsEx($primary, [ref]$dm, [IntPtr]::Zero, [DisplaySettingsHelper]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsEx (CDS_TEST) with dmSize=220: ret=$rcTest2"
