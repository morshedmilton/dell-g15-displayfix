Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class TestCCD
{
    public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    public const uint QDC_ALL_PATHS         = 0x00000001;

    public const uint SDC_APPLY                       = 0x00000080;
    public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
    public const uint SDC_SAVE_TO_DATABASE            = 0x00000200;
    public const uint SDC_ALLOW_CHANGES               = 0x00000400;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL
    {
        public uint Numerator;
        public uint Denominator;
    }

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

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(
        uint flags,
        out uint numPathArrayElements,
        out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(
        uint flags,
        ref uint numPathArrayElements,
        [In, Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray,
        ref uint numModeInfoArrayElements,
        [In, Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(
        uint numPathArrayElements,
        [In] DISPLAYCONFIG_PATH_INFO[] pathArray,
        uint numModeInfoArrayElements,
        [In] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
        uint flags);
}
"@

$numPaths = [uint32]0
$numModes = [uint32]0
$rc = [TestCCD]::GetDisplayConfigBufferSizes([TestCCD]::QDC_ONLY_ACTIVE_PATHS, [ref]$numPaths, [ref]$numModes)

$paths = New-Object TestCCD+DISPLAYCONFIG_PATH_INFO[] $numPaths
$modes = New-Object TestCCD+DISPLAYCONFIG_MODE_INFO[] $numModes

$rc2 = [TestCCD]::QueryDisplayConfig([TestCCD]::QDC_ONLY_ACTIVE_PATHS, [ref]$numPaths, $paths, [ref]$numModes, $modes, [IntPtr]::Zero)

$flagsNoSave = [TestCCD]::SDC_APPLY -bor [TestCCD]::SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor [TestCCD]::SDC_ALLOW_CHANGES
Write-Host ("Flags without SAVE: 0x{0:X8}" -f $flagsNoSave)
$rcSet2 = [TestCCD]::SetDisplayConfig($numPaths, $paths, $numModes, $modes, $flagsNoSave)
Write-Host "SetDisplayConfig without SAVE: rc=$rcSet2"
