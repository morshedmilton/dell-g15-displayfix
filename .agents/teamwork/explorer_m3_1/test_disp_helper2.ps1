Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DisplaySettingsHelper2
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_TEST = 0x00000002;
    public const int DM_PELSWIDTH = 0x00080000;
    public const int DM_PELSHEIGHT = 0x00100000;
    public const int DM_BITSPERPEL = 0x00040000;
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

$dm = New-Object DisplaySettingsHelper2+DEVMODE
$dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
$ret = [DisplaySettingsHelper2]::EnumDisplaySettings($primary, [DisplaySettingsHelper2]::ENUM_CURRENT_SETTINGS, [ref]$dm)

$dm.dmFields = [DisplaySettingsHelper2]::DM_PELSWIDTH -bor [DisplaySettingsHelper2]::DM_PELSHEIGHT -bor [DisplaySettingsHelper2]::DM_BITSPERPEL -bor [DisplaySettingsHelper2]::DM_DISPLAYFREQUENCY
$dm.dmDisplayFrequency = 360
$rcTest = [DisplaySettingsHelper2]::ChangeDisplaySettingsEx($primary, [ref]$dm, [IntPtr]::Zero, [DisplaySettingsHelper2]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsEx (CDS_TEST) with standard fields: ret=$rcTest"

# Also try without deviceName ($null)
$rcTestNull = [DisplaySettingsHelper2]::ChangeDisplaySettingsEx($null, [ref]$dm, [IntPtr]::Zero, [DisplaySettingsHelper2]::CDS_TEST, [IntPtr]::Zero)
Write-Host "ChangeDisplaySettingsEx (CDS_TEST) with null device: ret=$rcTestNull"
