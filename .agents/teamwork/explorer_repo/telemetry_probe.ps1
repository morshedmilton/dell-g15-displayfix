# Telemetry Probe for Dell G15 Display & System Environment
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=== 1. VIDEO CONTROLLERS ==="
Get-CimInstance Win32_VideoController | Select-Object Name, DeviceID, DriverVersion, DriverDate, Status, AdapterRAM, CurrentRefreshRate, VideoModeDescription | Format-Table -AutoSize

Write-Host "=== 2. PNP DISPLAY & MONITOR DEVICES ==="
Get-PnpDevice -Class Display, Monitor | Select-Object Class, FriendlyName, InstanceId, Status, Problem | Format-Table -AutoSize

Write-Host "=== 3. SYSTEM & MONITOR DISPLAY SETTINGS (Win32) ==="
$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class Win32Display {
    [DllImport("user32.dll")]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll")]
    public static extern int GetDpiForSystem();

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE {
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
    }

    public static void PrintDisplays() {
        Console.WriteLine("System DPI: " + GetDpiForSystem() + " (" + (GetDpiForSystem() * 100 / 96) + "%)");
        uint paths, modes;
        int rc = GetDisplayConfigBufferSizes(2, out paths, out modes);
        Console.WriteLine("QDC_ONLY_ACTIVE_PATHS: paths=" + paths + ", modes=" + modes + " (rc=" + rc + ")");

        DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
        dd.cb = Marshal.SizeOf(dd);
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++) {
            Console.WriteLine("\nAdapter " + i + ": " + dd.DeviceName + " [" + dd.DeviceString + "]");
            Console.WriteLine("  Flags: 0x" + dd.StateFlags.ToString("X") + " DeviceID: " + dd.DeviceID);

            DEVMODE dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(dm);
            if (EnumDisplaySettings(dd.DeviceName, -1, ref dm)) {
                Console.WriteLine("  Current Mode: " + dm.dmPelsWidth + "x" + dm.dmPelsHeight + " @ " + dm.dmDisplayFrequency + " Hz, " + dm.dmBitsPerPel + " bpp");
            }

            DISPLAY_DEVICE mon = new DISPLAY_DEVICE();
            mon.cb = Marshal.SizeOf(mon);
            for (uint j = 0; EnumDisplayDevices(dd.DeviceName, j, ref mon, 0); j++) {
                Console.WriteLine("    Monitor " + j + ": " + mon.DeviceName + " [" + mon.DeviceString + "] ID: " + mon.DeviceID + " Flags: 0x" + mon.StateFlags.ToString("X"));
            }
        }
    }
}
'@
Add-Type -TypeDefinition $csharp
[Win32Display]::PrintDisplays()

Write-Host "`n=== 4. DPI & SCALING REGISTRY SETTINGS ==="
Get-ItemProperty 'HKCU:\Control Panel\Desktop' | Select-Object LogPixels, Win8DpiScaling, DpiScalingVer | Format-List
Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' | Select-Object AppliedDPI | Format-List
Get-ChildItem 'HKCU:\Control Panel\Desktop\PerMonitorSettings' | ForEach-Object {
    $p = $_.PSPath
    [PSCustomObject]@{
        Key = $_.PSChildName
        DpiValue = (Get-ItemProperty $p).DpiValue
    }
} | Format-Table -AutoSize

Write-Host "=== 5. BRIGHTNESS INTERFACES (WMI) ==="
$intelBright = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue
$intelLevel = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue
$nvBright = Get-CimInstance -Namespace root\wmi -ClassName NvWmiBrightness -ErrorAction SilentlyContinue

Write-Host ("Intel WmiMonitorBrightnessMethods: " + ($intelBright -ne $null))
Write-Host ("Intel WmiMonitorBrightness CurrentBrightness: " + $intelLevel.CurrentBrightness)
Write-Host ("NVIDIA NvWmiBrightness available: " + ($nvBright -ne $null))
if ($nvBright) {
    Write-Host ("NVIDIA NvWmiBrightness Active: " + $nvBright.Active)
}

Write-Host "`n=== 6. DWM & DISPLAYFIX PROCESS METRICS ==="
Get-Process dwm, PhantomGuard, NvBrightness -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, CPU, Handles, WorkingSet64, PrivateMemorySize64 | Format-Table -AutoSize

Write-Host "=== 7. SCHEDULED TASKS & STARTUP ENTRIES ==="
Get-ScheduledTask -TaskName 'DisplayFixGuard', 'DisplayFixBrightness' -ErrorAction SilentlyContinue | Select-Object TaskName, State, @{n='Execute';e={$_.Actions.Execute}} | Format-Table -AutoSize
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Select-Object DisplayFixBrightness | Format-List

Write-Host "=== 8. RECENT DWM OR DISPLAY DRIVER ERRORS (EVENT LOG) ==="
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display','nvlddmkm','Desktop Window Manager'; Level=1,2,3} -MaxEvents 10 -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, Message | Format-List
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error','Desktop Window Manager'; Level=1,2} -MaxEvents 10 -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, Message | Format-List
