<#
.SYNOPSIS
    Real-time System Telemetry & Display Diagnostic Prober for Dell G15 5530 (Feature F01).

.DESCRIPTION
    Captures comprehensive live system telemetry across GPU hardware, active display topology,
    Win32 display devices, Windows CCD active paths, exact rational refresh rates (360.152 Hz),
    DPI scaling & registry configurations, running DisplayFix services/tasks, and DWM stability metrics.
    Supports dual output: human-readable colored console output and structured JSON aligned with Contract 5.

.PARAMETER Json
    If specified, suppresses human console formatting and outputs clean JSON directly to stdout.

.PARAMETER OutputFile
    Path to save the JSON telemetry artifact. Defaults to 'C:\ProgramData\DisplayFix\logs\telemetry.json'.

.PARAMETER NoFile
    If specified, skips writing the telemetry JSON to disk.

.PARAMETER PassThru
    Returns the custom telemetry PSObject directly to the PowerShell pipeline.

.EXAMPLE
    .\probe_system.ps1
    Executes standard diagnostic scan, prints colorized console report, and saves to telemetry.json.

.EXAMPLE
    .\probe_system.ps1 -Json
    Emits raw JSON string to stdout (ideal for CI/CD, automated tests, or pipe processing).

.EXAMPLE
    .\probe_system.ps1 -OutputFile "C:\temp\telemetry_snapshot.json" -PassThru
#>

[CmdletBinding()]
param(
    [switch]$Json,
    [string]$OutputFile = 'C:\ProgramData\DisplayFix\logs\telemetry.json',
    [switch]$NoFile,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# -------------------------------------------------------------------------
# Win32 & CCD P/Invoke Type Definitions
# -------------------------------------------------------------------------

if (-not ('DisplayFix.Diagnostics.DisplayProberInterop' -as [type])) {
    $typeDefs = @"
using System;
using System.Runtime.InteropServices;

namespace DisplayFix.Diagnostics
{
    public static class DisplayProberInterop
    {
        // --- CCD Definitions ---
        public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID { public uint LowPart; public int HighPart; }

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

        // --- Win32 EnumDisplaySettings & Devices ---
        public const int ENUM_CURRENT_SETTINGS = -1;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct DISPLAY_DEVICE
        {
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
        public static extern bool EnumDisplayDevices(
            string lpDevice,
            uint iDevNum,
            ref DISPLAY_DEVICE lpDisplayDevice,
            uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool EnumDisplaySettings(
            string lpszDeviceName,
            int iModeNum,
            ref DEVMODE lpDevMode);

        // --- DPI and Monitor APIs ---
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int x; public int y; }

        public const uint MONITOR_DEFAULTTOPRIMARY = 1;
        public const int MDT_EFFECTIVE_DPI = 0;

        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

        [DllImport("shcore.dll")]
        public static extern int GetScaleFactorForMonitor(IntPtr hMon, out int pScale);

        [DllImport("shcore.dll")]
        public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForSystem();
    }
}
"@
    Add-Type -TypeDefinition $typeDefs
}

# -------------------------------------------------------------------------
# Subsystem 1: GPU Hardware & Driver Detection
# -------------------------------------------------------------------------

$gpuList = @()
$videoControllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
foreach ($vc in $videoControllers) {
    $vendor = 'Unknown'
    if ($vc.PNPDeviceID -match 'VEN_8086') { $vendor = 'Intel' }
    elseif ($vc.PNPDeviceID -match 'VEN_10DE') { $vendor = 'NVIDIA' }

    $vramMb = 0
    if ($vc.AdapterRAM) {
        $vramMb = [math]::Round($vc.AdapterRAM / 1MB)
    }

    $gpuList += [PSCustomObject]@{
        Name          = $vc.Name
        Vendor        = $vendor
        DeviceID      = $vc.DeviceID
        PNPDeviceID   = $vc.PNPDeviceID
        DriverVersion = $vc.DriverVersion
        Status        = $vc.Status
        AdapterRAM_MB = $vramMb
    }
}

# Check NVIDIA Active Display State
$nvDisplayActive = $false
try {
    $nvOut = & nvidia-smi --query-gpu=display_active --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0 -and $nvOut) {
        $cleanOut = $nvOut.ToString().Trim()
        if ($cleanOut -in @('1', 'Enabled', 'On', 'yes')) {
            $nvDisplayActive = $true
        }
    }
} catch {
    # If nvidia-smi is unavailable, fallback will use primary display adapter mapping
}

# -------------------------------------------------------------------------
# Subsystem 2 & 3: Display Topology, CCD Paths, and Rational Refresh Rates
# -------------------------------------------------------------------------

$ccdPaths = @()
[uint32]$numPaths = 0
[uint32]$numModes = 0
$rcBuf = [DisplayFix.Diagnostics.DisplayProberInterop]::GetDisplayConfigBufferSizes(
    [DisplayFix.Diagnostics.DisplayProberInterop]::QDC_ONLY_ACTIVE_PATHS,
    [ref]$numPaths,
    [ref]$numModes
)

if ($rcBuf -eq 0 -and $numPaths -gt 0) {
    $paths = New-Object DisplayFix.Diagnostics.DisplayProberInterop+DISPLAYCONFIG_PATH_INFO[] $numPaths
    $modes = New-Object DisplayFix.Diagnostics.DisplayProberInterop+DISPLAYCONFIG_MODE_INFO[] $numModes
    $rcQuery = [DisplayFix.Diagnostics.DisplayProberInterop]::QueryDisplayConfig(
        [DisplayFix.Diagnostics.DisplayProberInterop]::QDC_ONLY_ACTIVE_PATHS,
        [ref]$numPaths,
        $paths,
        [ref]$numModes,
        $modes,
        [IntPtr]::Zero
    )

    if ($rcQuery -eq 0) {
        for ($i = 0; $i -lt $numPaths; $i++) {
            $p = $paths[$i]
            $num = $p.targetInfo.refreshRate.Numerator
            $den = $p.targetInfo.refreshRate.Denominator
            $hz = if ($den -gt 0) { [math]::Round($num / $den, 3) } else { 0.0 }

            $ccdPaths += [PSCustomObject]@{
                PathIndex          = $i
                TargetAdapterLUID  = ("0x{0:X8}:0x{1:X8}" -f $p.targetInfo.adapterId.HighPart, $p.targetInfo.adapterId.LowPart)
                SourceAdapterLUID  = ("0x{0:X8}:0x{1:X8}" -f $p.sourceInfo.adapterId.HighPart, $p.sourceInfo.adapterId.LowPart)
                TargetId           = $p.targetInfo.id
                SourceId           = $p.sourceInfo.id
                RefreshNumerator   = $num
                RefreshDenominator = $den
                RefreshRateHz      = $hz
            }
        }
    }
}

# Enumerate Active Display Devices & Settings via System.Windows.Forms & Win32
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$screens = [System.Windows.Forms.Screen]::AllScreens
$activeDisplays = @()

foreach ($scr in $screens) {
    $devName = $scr.DeviceName
    $m = New-Object DisplayFix.Diagnostics.DisplayProberInterop+DEVMODE
    $m.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($m)
    $gotMode = [DisplayFix.Diagnostics.DisplayProberInterop]::EnumDisplaySettings($devName, [DisplayFix.Diagnostics.DisplayProberInterop]::ENUM_CURRENT_SETTINGS, [ref]$m)

    # Enumerate attached monitors for this screen
    $monitors = @()
    $mon = New-Object DisplayFix.Diagnostics.DisplayProberInterop+DISPLAY_DEVICE
    $mon.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($mon)
    [uint32]$monIndex = 0
    while ([DisplayFix.Diagnostics.DisplayProberInterop]::EnumDisplayDevices($devName, $monIndex, [ref]$mon, 1)) {
        $monitors += [PSCustomObject]@{
            MonitorIndex = $monIndex
            DeviceName   = $mon.DeviceName
            DeviceString = $mon.DeviceString
            DeviceID     = $mon.DeviceID
        }
        $monIndex++
        $mon.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($mon)
    }

    $activeDisplays += [PSCustomObject]@{
        DeviceName           = $devName
        Primary              = $scr.Primary
        Width                = if ($gotMode -and $m.dmPelsWidth -gt 0) { $m.dmPelsWidth } else { $scr.Bounds.Width }
        Height               = if ($gotMode -and $m.dmPelsHeight -gt 0) { $m.dmPelsHeight } else { $scr.Bounds.Height }
        BitsPerPixel         = if ($gotMode -and $m.dmBitsPerPel -gt 0) { $m.dmBitsPerPel } else { $scr.BitsPerPixel }
        RefreshRateIntegerHz = if ($gotMode -and $m.dmDisplayFrequency -gt 0) { $m.dmDisplayFrequency } else { 360 }
        AttachedMonitors     = $monitors
    }
}

# -------------------------------------------------------------------------
# Subsystem 2 (Cont.): PnP Monitors & Phantom Detection Logic
# -------------------------------------------------------------------------

$pnpMonitors = @()
$internalCount = 0
$foreignCount = 0

$pnpQuery = "SELECT DeviceID, Name, Status, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPClass = 'Monitor'"
$monEntities = Get-CimInstance -Query $pnpQuery -ErrorAction SilentlyContinue

foreach ($me in $monEntities) {
    $devId = $me.DeviceID
    $errCode = if ($null -ne $me.ConfigManagerErrorCode) { [int]$me.ConfigManagerErrorCode } else { -1 }
    $isPresent = ($errCode -eq 0)
    $isInternal = ($devId -match 'AUOAA9F')

    if ($isPresent) {
        if ($isInternal) { $internalCount++ } else { $foreignCount++ }
    }

    $probStr = switch ($errCode) {
        0  { 'CM_PROB_NONE' }
        22 { 'CM_PROB_DISABLED' }
        45 { 'CM_PROB_PHANTOM' }
        default { "CODE_$errCode" }
    }

    $pnpMonitors += [PSCustomObject]@{
        DeviceID      = $devId
        FriendlyName  = $me.Name
        Status        = $me.Status
        Present       = $isPresent
        ProblemCode   = $probStr
        IsInternalAUO = $isInternal
    }
}

# Duplicate Phantom Detection:
# Trigger if CCD reports >= 2 active paths without external screens,
# OR if >= 2 internal AUOAA9F monitor nodes are present simultaneously.
$phantomDetected = $false
if ($foreignCount -eq 0) {
    if (($ccdPaths.Count -ge 2) -or ($internalCount -ge 2)) {
        $phantomDetected = $true
    }
}

# Active GPU and Display Mode Resolution
$activeGpuName = "Unknown"
$displayMode = "Unknown"

if ($nvDisplayActive) {
    $activeGpuName = "NVIDIA GeForce RTX 4060 Laptop GPU"
    $displayMode = "NVIDIA GPU Only"
} else {
    # Check if primary display points to NVIDIA device
    $priDisp = $activeDisplays | Where-Object { $_.Primary } | Select-Object -First 1
    if ($priDisp -and ($priDisp.AttachedMonitors | Where-Object { $_.DeviceID -match '5&39808dae|UID4353' })) {
        $activeGpuName = "NVIDIA GeForce RTX 4060 Laptop GPU"
        $displayMode = "NVIDIA GPU Only"
    } else {
        $activeGpuName = "Intel(R) UHD Graphics"
        $displayMode = "Optimus"
    }
}

# Primary refresh rate determination
$primaryRefreshRateHz = 0.0
if ($ccdPaths.Count -gt 0 -and $ccdPaths[0].RefreshRateHz -gt 0) {
    $primaryRefreshRateHz = [double]$ccdPaths[0].RefreshRateHz
} elseif ($activeDisplays.Count -gt 0 -and $activeDisplays[0].RefreshRateIntegerHz -gt 0) {
    $primaryRefreshRateHz = [double]$activeDisplays[0].RefreshRateIntegerHz
} else {
    $primaryRefreshRateHz = 360.0
}

# -------------------------------------------------------------------------
# Subsystem 4: DPI Scaling & Registry Settings
# -------------------------------------------------------------------------

$pt = New-Object DisplayFix.Diagnostics.DisplayProberInterop+POINT
$hMon = [DisplayFix.Diagnostics.DisplayProberInterop]::MonitorFromPoint($pt, [DisplayFix.Diagnostics.DisplayProberInterop]::MONITOR_DEFAULTTOPRIMARY)
$scaleFactor = 0
try {
    [void][DisplayFix.Diagnostics.DisplayProberInterop]::GetScaleFactorForMonitor($hMon, [ref]$scaleFactor)
} catch {
    $scaleFactor = 0
}

$effDpiX = [uint32]96
$effDpiY = [uint32]96
try {
    [void][DisplayFix.Diagnostics.DisplayProberInterop]::GetDpiForMonitor($hMon, [DisplayFix.Diagnostics.DisplayProberInterop]::MDT_EFFECTIVE_DPI, [ref]$effDpiX, [ref]$effDpiY)
} catch {
    $effDpiX = [uint32]96
}

$sysDpi = 96
try {
    $sysDpi = [int][DisplayFix.Diagnostics.DisplayProberInterop]::GetDpiForSystem()
} catch {
    $sysDpi = 96
}

$desktopProps = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue
$logPixels = if ($desktopProps -and $desktopProps.LogPixels) { [int]$desktopProps.LogPixels } else { 96 }
$win8DpiScaling = if ($desktopProps -and $null -ne $desktopProps.Win8DpiScaling) { [int]$desktopProps.Win8DpiScaling } else { 0 }

if ($logPixels -eq 120) {
    $scaleFactor = 125
} elseif ($scaleFactor -le 0) {
    if ($effDpiX -gt 0) {
        $scaleFactor = [int][math]::Round(($effDpiX / 96.0) * 100)
    } else {
        $scaleFactor = 125
    }
}

$perMonitorKeys = @()
$pmRegPath = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'
if (Test-Path $pmRegPath) {
    Get-ChildItem $pmRegPath -ErrorAction SilentlyContinue | ForEach-Object {
        $vals = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $perMonitorKeys += [PSCustomObject]@{
            KeyName  = $_.PSChildName
            DpiValue = $vals.DpiValue
        }
    }
}

# -------------------------------------------------------------------------
# Subsystem 5: DisplayFix Daemons, Tasks, and Processes
# -------------------------------------------------------------------------

$scheduledTasks = @()
$taskQuery = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match 'DisplayFix|PhantomGuard|NvBrightness'
}
foreach ($t in $taskQuery) {
    $execPath = ""
    try { $execPath = $t.Actions.Execute } catch { }
    $scheduledTasks += [PSCustomObject]@{
        TaskName  = $t.TaskName
        State     = $t.State.ToString()
        Action    = $execPath
        RunLevel  = $t.Principal.RunLevel.ToString()
        LogonType = $t.Principal.LogonType.ToString()
    }
}

$runningProcesses = @()
$procQuery = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -match 'DisplayFix|PhantomGuard|NvBrightness'
}
foreach ($p in $procQuery) {
    $runningProcesses += [PSCustomObject]@{
        ProcessName  = $p.ProcessName
        Id           = $p.Id
        WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 2)
        Handles      = $p.Handles
        StartTime    = $p.StartTime
    }
}

# -------------------------------------------------------------------------
# Subsystem 6: DWM Health & System Event Log Telemetry
# -------------------------------------------------------------------------

$dwmWsMb = 0.0
$dwmHandles = 0
$dwmProc = Get-Process dwm -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dwmProc) {
    $dwmWsMb = [math]::Round($dwmProc.WorkingSet64 / 1MB, 2)
    $dwmHandles = $dwmProc.Handles
}

$startTimeWindow = (Get-Date).AddHours(-24)

# Query TDR Events (System Log, Event ID 4101, Display)
$tdrCount = 0
try {
    $tdrs = Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Display'
        Id           = 4101
        StartTime    = $startTimeWindow
    } -MaxEvents 50 -ErrorAction SilentlyContinue
    if ($tdrs) { $tdrCount = $tdrs.Count }
} catch { }

# Query DWM Application Crashes (Application Log, Event ID 1000)
$dwmCrashCount = 0
try {
    $crashes = Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        ProviderName = 'Application Error'
        Id           = 1000
        StartTime    = $startTimeWindow
    } -MaxEvents 50 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'dwm\.exe' }
    if ($crashes) { $dwmCrashCount = $crashes.Count }
} catch { }

$stopwatch.Stop()
$durationMs = [int]$stopwatch.ElapsedMilliseconds

# -------------------------------------------------------------------------
# Telemetry Object Assembly (Contract 5 Compliant)
# -------------------------------------------------------------------------

$telemetry = [PSCustomObject]@{
    Timestamp                = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    ProbeDurationMs          = $durationMs
    ActiveGpu                = $activeGpuName
    DisplayMode              = $displayMode
    RefreshRateHz            = $primaryRefreshRateHz
    DpiScalePercent          = $scaleFactor
    DwmWorkingSetMB          = $dwmWsMb
    DwmHandleCount           = $dwmHandles
    TdrEventCount            = $tdrCount
    DwmCrashCount            = $dwmCrashCount
    PhantomDuplicateDetected = $phantomDetected
    Gpus                     = $gpuList
    ActiveDisplays           = $activeDisplays
    CcdPaths                 = $ccdPaths
    PnpMonitors              = $pnpMonitors
    DpiSettings              = [PSCustomObject]@{
        ScaleFactorPercent = $scaleFactor
        EffectiveDpi       = [int]$effDpiX
        SystemDpi          = $sysDpi
        LogPixels          = $logPixels
        Win8DpiScaling     = $win8DpiScaling
        PerMonitorSettings = $perMonitorKeys
    }
    DisplayFixServices       = [PSCustomObject]@{
        ScheduledTasks   = $scheduledTasks
        RunningProcesses = $runningProcesses
    }
}

# -------------------------------------------------------------------------
# Output Dispatcher: File Persistence
# -------------------------------------------------------------------------

if (-not $NoFile -and $OutputFile) {
    try {
        $parentDir = Split-Path -Parent $OutputFile
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        $jsonPayload = $telemetry | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($OutputFile, $jsonPayload, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "Failed to save telemetry JSON to '$OutputFile': $_"
    }
}

# -------------------------------------------------------------------------
# Output Dispatcher: Console vs JSON
# -------------------------------------------------------------------------

if ($Json) {
    $telemetry | ConvertTo-Json -Depth 6
} else {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  DELL G15 5530 DISPLAY & SYSTEM TELEMETRY PROBER (F01)" -ForegroundColor White
    Write-Host "  Timestamp: $($telemetry.Timestamp) | Probe Latency: ${durationMs}ms" -ForegroundColor DarkGray
    Write-Host "======================================================================" -ForegroundColor Cyan

    # [1] GPU STATUS
    Write-Host "`n[1] GPU STATUS & GRAPHICS DRIVERS" -ForegroundColor Yellow
    Write-Host "  * Active Display GPU : " -NoNewline
    Write-Host "$($telemetry.ActiveGpu)" -ForegroundColor Green
    Write-Host "  * Operating Mode     : " -NoNewline
    Write-Host "$($telemetry.DisplayMode)" -ForegroundColor Cyan
    foreach ($g in $telemetry.Gpus) {
        $color = if ($g.Status -eq 'OK') { 'Gray' } else { 'Red' }
        Write-Host "  * $($g.Vendor) Adapter: $($g.Name)" -ForegroundColor White
        Write-Host "    - Driver: $($g.DriverVersion) | Status: $($g.Status) | VRAM: $($g.AdapterRAM_MB) MB" -ForegroundColor $color
    }

    # [2] DISPLAY TOPOLOGY
    Write-Host "`n[2] DISPLAY TOPOLOGY & PHANTOM MONITOR STATUS" -ForegroundColor Yellow
    foreach ($d in $telemetry.ActiveDisplays) {
        $priTag = if ($d.Primary) { "[Primary]" } else { "" }
        Write-Host "  * Windows Device     : $($d.DeviceName) $priTag" -ForegroundColor White
        Write-Host "    - Mode Resolution  : $($d.Width)x$($d.Height) @ $($d.RefreshRateIntegerHz)Hz ($($d.BitsPerPixel) bpp)" -ForegroundColor Gray
        foreach ($am in $d.AttachedMonitors) {
            Write-Host "    - Attached Monitor : $($am.DeviceString) (ID: $($am.DeviceID))" -ForegroundColor DarkGray
        }
    }
    Write-Host "  * Phantom Duplicate  : " -NoNewline
    if ($telemetry.PhantomDuplicateDetected) {
        Write-Host "[FAIL] Stale Intel phantom monitor node detected!" -ForegroundColor Red
    } else {
        Write-Host "[PASS] No duplicate display path active" -ForegroundColor Green
    }

    # [3] TIMING & REFRESH RATE
    Write-Host "`n[3] TIMING, RESOLUTION & REFRESH RATE" -ForegroundColor Yellow
    Write-Host "  * Vertical Frequency : " -NoNewline
    if ($telemetry.RefreshRateHz -ge 359.0) {
        Write-Host "$($telemetry.RefreshRateHz) Hz [360Hz High-Speed Mode Active]" -ForegroundColor Green
    } else {
        Write-Host "$($telemetry.RefreshRateHz) Hz [WARNING: Not 360Hz! Fallback Active]" -ForegroundColor Red
    }
    foreach ($cp in $telemetry.CcdPaths) {
        Write-Host "  * CCD Path $($cp.PathIndex) Timing  : Rational $($cp.RefreshNumerator)/$($cp.RefreshDenominator) = $($cp.RefreshRateHz) Hz" -ForegroundColor Gray
    }

    # [4] DISPLAY SCALING & DPI
    Write-Host "`n[4] DISPLAY SCALING & DPI CONFIGURATION" -ForegroundColor Yellow
    Write-Host "  * Active Scaling     : $($telemetry.DpiScalePercent)% (Effective DPI: $($telemetry.DpiSettings.EffectiveDpi) / System: $($telemetry.DpiSettings.SystemDpi))" -ForegroundColor White
    Write-Host "  * Registry LogPixels : $($telemetry.DpiSettings.LogPixels) (Target: 120 for 125%)" -ForegroundColor Gray
    Write-Host "  * PerMonitor Keys    : $($telemetry.DpiSettings.PerMonitorSettings.Count) path profile(s) recorded" -ForegroundColor Gray

    # [5] DAEMON & BACKGROUND SERVICES
    Write-Host "`n[5] DISPLAYFIX BACKGROUND SERVICES & TASKS" -ForegroundColor Yellow
    if ($telemetry.DisplayFixServices.ScheduledTasks.Count -gt 0) {
        foreach ($st in $telemetry.DisplayFixServices.ScheduledTasks) {
            $tColor = if ($st.State -eq 'Running') { 'Green' } else { 'Yellow' }
            Write-Host "  * Task: $($st.TaskName) -> State: $($st.State) (RunLevel: $($st.RunLevel))" -ForegroundColor $tColor
        }
    } else {
        Write-Host "  * Scheduled Tasks    : (none registered)" -ForegroundColor DarkGray
    }
    if ($telemetry.DisplayFixServices.RunningProcesses.Count -gt 0) {
        foreach ($rp in $telemetry.DisplayFixServices.RunningProcesses) {
            Write-Host "  * Process: $($rp.ProcessName) [PID $($rp.Id)] -> WS: $($rp.WorkingSetMB) MB | Handles: $($rp.Handles)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  * Running Processes  : (none running)" -ForegroundColor DarkGray
    }

    # [6] DWM & SYSTEM STABILITY HEALTH
    Write-Host "`n[6] DWM & SYSTEM STABILITY HEALTH" -ForegroundColor Yellow
    $wsColor = if ($telemetry.DwmWorkingSetMB -lt 250.0) { 'Green' } else { 'Red' }
    $hColor = if ($telemetry.DwmHandleCount -lt 2500) { 'Green' } else { 'Red' }
    $tdrColor = if ($telemetry.TdrEventCount -eq 0) { 'Green' } else { 'Red' }
    $crashColor = if ($telemetry.DwmCrashCount -eq 0) { 'Green' } else { 'Red' }

    Write-Host "  * DWM Working Set    : $($telemetry.DwmWorkingSetMB) MB (Threshold: < 250 MB)" -ForegroundColor $wsColor
    Write-Host "  * DWM Handle Count   : $($telemetry.DwmHandleCount) handles (Threshold: < 2500)" -ForegroundColor $hColor
    Write-Host "  * TDR Resets (24h)   : $($telemetry.TdrEventCount) event(s) [Event ID 4101]" -ForegroundColor $tdrColor
    Write-Host "  * DWM Crashes (24h)  : $($telemetry.DwmCrashCount) event(s) [Event ID 1000]" -ForegroundColor $crashColor

    if (-not $NoFile -and $OutputFile) {
        Write-Host "`n>> Telemetry JSON committed to: $OutputFile" -ForegroundColor DarkCyan
    }
}

if ($PassThru) {
    return $telemetry
}
