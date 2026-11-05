# .agents/teamwork/explorer_m3_3/bench_pipeline.ps1
# Live benchmark of the 3-step Milestone 3 Display Reconfiguration Pipeline
$ErrorActionPreference = 'Stop'
$assembly = [System.Reflection.Assembly]::LoadFrom((Resolve-Path "bin\DisplayFixDaemon.exe").Path)

Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

public static class M3PipelineBenchmark
{
    public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    public const int ENUM_CURRENT_SETTINGS = -1;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering;
        public int targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO
    {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public byte[] modeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public int type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int minScaleRel;
        public int curScaleRel;
        public int maxScaleRel;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int scaleRel;
    }

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

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [In, Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray, ref uint numModeInfoArrayElements, [In, Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODEW lpDevMode);

    public static double MeasureStep2RefreshRateCheck(out int currentHz, out double exactHz)
    {
        Stopwatch sw = Stopwatch.StartNew();
        currentHz = 0;
        exactHz = 0.0;

        uint numPaths = 0, numModes = 0;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes) == 0 && numPaths > 0)
        {
            DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[numPaths];
            DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[numModes];
            if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero) == 0)
            {
                for (int i = 0; i < numPaths; i++)
                {
                    if (paths[i].targetInfo.refreshRate.Denominator > 0)
                    {
                        exactHz = (double)paths[i].targetInfo.refreshRate.Numerator / (double)paths[i].targetInfo.refreshRate.Denominator;
                        currentHz = (int)Math.Round(exactHz);
                        break;
                    }
                }
            }
        }

        if (currentHz == 0)
        {
            DEVMODEW dm = new DEVMODEW();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEW));
            if (EnumDisplaySettingsW(null, ENUM_CURRENT_SETTINGS, ref dm))
            {
                currentHz = dm.dmDisplayFrequency;
                exactHz = dm.dmDisplayFrequency;
            }
        }

        sw.Stop();
        return sw.Elapsed.TotalMilliseconds;
    }

    public static double MeasureStep3ScalingCheck(out int logPixels, out int scaleRel)
    {
        Stopwatch sw = Stopwatch.StartNew();
        logPixels = 96;
        scaleRel = 0;

        using (RegistryKey desktopKey = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop", false))
        {
            if (desktopKey != null)
            {
                object val = desktopKey.GetValue("LogPixels");
                if (val != null) logPixels = Convert.ToInt32(val);
            }
        }

        uint numPaths = 0, numModes = 0;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes) == 0 && numPaths > 0)
        {
            DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[numPaths];
            DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[numModes];
            if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero) == 0)
            {
                DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getPacket = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
                getPacket.header.type = -3;
                getPacket.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
                getPacket.header.adapterId = paths[0].sourceInfo.adapterId;
                getPacket.header.id = paths[0].sourceInfo.id;
                if (DisplayConfigGetDeviceInfo(ref getPacket) == 0)
                {
                    scaleRel = getPacket.curScaleRel;
                }
            }
        }

        sw.Stop();
        return sw.Elapsed.TotalMilliseconds;
    }
}
"@

# Warmup
$null = [DisplayFix.Daemon.GhostEvictionEngine]::CheckAndEvict($false)
$hz = 0; $exactHz = 0.0; $lp = 0; $sr = 0
$null = [M3PipelineBenchmark]::MeasureStep2RefreshRateCheck([ref]$hz, [ref]$exactHz)
$null = [M3PipelineBenchmark]::MeasureStep3ScalingCheck([ref]$lp, [ref]$sr)

# Run 10 iterations of the 3-step pipeline
$totalTimes = @()
for ($i = 1; $i -le 10; $i++) {
    $swTotal = [System.Diagnostics.Stopwatch]::StartNew()
    $evictRes = [DisplayFix.Daemon.GhostEvictionEngine]::CheckAndEvict($false)
    $tStep1 = $evictRes.ElapsedMilliseconds
    $tStep2 = [M3PipelineBenchmark]::MeasureStep2RefreshRateCheck([ref]$hz, [ref]$exactHz)
    $tStep3 = [M3PipelineBenchmark]::MeasureStep3ScalingCheck([ref]$lp, [ref]$sr)
    $swTotal.Stop()
    $totalTimes += $swTotal.Elapsed.TotalMilliseconds
    Write-Host ("Iter {0,2}: Step1(Evict)={1,5:F2}ms | Step2(360Hz)={2,5:F2}ms (Hz={3}, Exact={4:F3}) | Step3(125%DPI)={5,5:F2}ms (LogPixels={6}, scaleRel={7}) | Total={8,5:F2}ms" -f `
        $i, $tStep1, $tStep2, $hz, $exactHz, $tStep3, $lp, $sr, $swTotal.Elapsed.TotalMilliseconds)
}
$avg = ($totalTimes | Measure-Object -Average).Average
$max = ($totalTimes | Measure-Object -Maximum).Maximum
Write-Host ("SUMMARY: Avg Total Pipeline Latency = {0:F2}ms, Max = {1:F2}ms (Budget: < 100.00ms)" -f $avg, $max)
