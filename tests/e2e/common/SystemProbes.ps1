# tests/e2e/common/SystemProbes.ps1
# Low-level system telemetry and diagnostic probes for Dell G15 DisplayFix E2E tests

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32GuiProbes
{
    public const int GR_GDIOBJECTS = 0;
    public const int GR_USEROBJECTS = 1;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
}

public static class Win32DisplayProbes
{
    public const int ENUM_CURRENT_SETTINGS = -1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
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

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettingsA(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);
}
"@ -ErrorAction SilentlyContinue

function Get-ActiveVideoControllers {
    $controllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $result = @{
        Intel = $null
        Nvidia = $null
        Raw = $controllers
    }
    foreach ($c in $controllers) {
        if ($c.PNPDeviceID -match "VEN_8086" -or $c.Name -match "Intel") {
            $result.Intel = $c
        }
        elseif ($c.PNPDeviceID -match "VEN_10DE" -or $c.Name -match "NVIDIA") {
            $result.Nvidia = $c
        }
    }
    return $result
}

function Get-DisplayTopologyState {
    $monitors = Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue
    $intelGhost = $monitors | Where-Object { $_.InstanceId -like "*AUOAA9F*UID8388688*" }
    $nvidiaActive = $monitors | Where-Object { $_.InstanceId -like "*AUOAA9F*UID4353*" }

    $allPresent = $monitors | Where-Object { $_.Present -eq $true }

    return [PSCustomObject]@{
        TotalMonitors     = $monitors.Count
        PresentMonitors   = $allPresent.Count
        HasIntelGhost     = ($null -ne $intelGhost -and $intelGhost.Present -eq $true)
        IntelGhostDevice  = $intelGhost
        NvidiaActiveNode  = $nvidiaActive
        AllMonitors       = $monitors
    }
}

function Get-RefreshRateInfo {
    $dm = New-Object Win32DisplayProbes+DEVMODE
    $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
    $ret = [Win32DisplayProbes]::EnumDisplaySettingsA($null, [Win32DisplayProbes]::ENUM_CURRENT_SETTINGS, [ref]$dm)

    $videoController = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1

    $freq = 0
    $width = 0
    $height = 0
    $bpp = 32

    if ($ret -and $dm.dmPelsWidth -gt 0) {
        $width = $dm.dmPelsWidth
        $height = $dm.dmPelsHeight
        $freq = $dm.dmDisplayFrequency
        $bpp = $dm.dmBitsPerPel
    }

    if ($videoController) {
        if ($width -eq 0 -and $videoController.CurrentHorizontalResolution) {
            $width = $videoController.CurrentHorizontalResolution
        }
        if ($height -eq 0 -and $videoController.CurrentVerticalResolution) {
            $height = $videoController.CurrentVerticalResolution
        }
        if ($freq -eq 0 -and $videoController.CurrentRefreshRate) {
            $freq = $videoController.CurrentRefreshRate
        }
    }

    return [PSCustomObject]@{
        Success        = $ret
        FrequencyHz    = $freq
        PelsWidth      = $width
        PelsHeight     = $height
        BitsPerPixel   = $bpp
    }
}

function Get-DpiScaleInfo {
    $perMonitorRoot = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
    $desktopKey = "HKCU:\Control Panel\Desktop"

    $logPixels = (Get-ItemProperty -Path $desktopKey -Name "LogPixels" -ErrorAction SilentlyContinue).LogPixels
    if ($null -eq $logPixels) { $logPixels = 96 } # default fallback

    $topologies = @()
    if (Test-Path $perMonitorRoot) {
        $subKeys = Get-ChildItem -Path $perMonitorRoot -ErrorAction SilentlyContinue
        foreach ($k in $subKeys) {
            $dpiVal = (Get-ItemProperty -Path $k.PSPath -Name "DpiValue" -ErrorAction SilentlyContinue).DpiValue
            $topologies += [PSCustomObject]@{
                KeyName  = $k.PSChildName
                DpiValue = $dpiVal
            }
        }
    }

    return [PSCustomObject]@{
        LogPixels  = $logPixels
        ScalePercent = [int](($logPixels / 96.0) * 100)
        Topologies = $topologies
    }
}

function Get-DwmHealthMetrics {
    $dwmProc = Get-Process -Name dwm -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dwmProc) {
        return $null
    }

    $gdi = 0
    $user = 0
    try {
        $gdi = [Win32GuiProbes]::GetGuiResources($dwmProc.Handle, [Win32GuiProbes]::GR_GDIOBJECTS)
        $user = [Win32GuiProbes]::GetGuiResources($dwmProc.Handle, [Win32GuiProbes]::GR_USEROBJECTS)
    } catch {}

    return [PSCustomObject]@{
        ProcessId       = $dwmProc.Id
        WorkingSetMB    = [math]::Round($dwmProc.WorkingSet64 / 1MB, 2)
        PagedMemoryMB   = [math]::Round($dwmProc.PagedMemorySize64 / 1MB, 2)
        HandleCount     = $dwmProc.Handles
        ThreadCount     = $dwmProc.Threads.Count
        GdiObjects      = $gdi
        UserObjects     = $user
    }
}

function Get-SystemEventLogAlerts {
    param([int]$Hours = 1)
    $since = (Get-Date).AddHours(-$Hours)

    $tdrEvents = @()
    try {
        $tdrEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 4101
            StartTime = $since
        } -ErrorAction SilentlyContinue
    } catch {}

    $dwmCrashes = @()
    try {
        $dwmCrashes = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            Id        = 1000
            StartTime = $since
        } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match "dwm\.exe" }
    } catch {}

    return [PSCustomObject]@{
        TdrCount     = ($tdrEvents | Measure-Object).Count
        TdrEvents    = $tdrEvents
        DwmCrashes   = ($dwmCrashes | Measure-Object).Count
        CrashEvents  = $dwmCrashes
    }
}

function Get-BrightnessWmiProviders {
    $hasNvWmi = $false
    $hasIntelWmi = $false

    try {
        $nv = Get-CimClass -Namespace root\wmi -ClassName NvWmiBrightness -ErrorAction Stop
        if ($nv) { $hasNvWmi = $true }
    } catch {}

    try {
        $wmiMon = Get-CimClass -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop
        if ($wmiMon) { $hasIntelWmi = $true }
    } catch {}

    return [PSCustomObject]@{
        HasNvWmiBrightness          = $hasNvWmi
        HasWmiMonitorBrightnessMethods = $hasIntelWmi
    }
}
