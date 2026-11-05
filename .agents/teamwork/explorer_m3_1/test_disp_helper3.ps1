Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DisplaySettingsHelper3
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_TEST = 0x00000002;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;

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

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODEW lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int ChangeDisplaySettingsExW(string lpszDeviceName, ref DEVMODEW lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);
}
"@

Add-Type -AssemblyName System.Windows.Forms
$primary = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName

$dm = New-Object DisplaySettingsHelper3+DEVMODEW
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$ret = [DisplaySettingsHelper3]::EnumDisplaySettingsW($primary, [DisplaySettingsHelper3]::ENUM_CURRENT_SETTINGS, [ref]$dm)

Write-Host "Enum ret=$ret, dmSize=$($dm.dmSize), freq=$($dm.dmDisplayFrequency)"

$rcTest = [DisplaySettingsHelper3]::ChangeDisplaySettingsExW($primary, [ref]$dm, [IntPtr]::Zero, [DisplaySettingsHelper3]::CDS_TEST, [IntPtr]::Zero)
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "ChangeDisplaySettingsExW ret=$rcTest, Win32Error=$err"
