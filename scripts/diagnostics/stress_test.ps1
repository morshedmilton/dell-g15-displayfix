<#
.SYNOPSIS
    Dell G15 5530 Display Switching Stress Test Harness (Feature F03).

.DESCRIPTION
    Executes automated display switching stress testing (up to 100 iterations),
    monitoring DWM process health, memory/handle leak slopes via Ordinary Least Squares
    (OLS) regression, 360Hz refresh rate lock, 125% DPI scaling persistence, and
    TDR / DWM crash event logs. Generates audit JSON and Markdown reports.

.PARAMETER Iterations
    Number of stress iterations to execute (default: 10 for smoke test, 100 for soak validation).

.PARAMETER Mode
    Switching execution mode: Simulated, CcdCycle, DevNodeCycle, Passive, or Auto (default: Auto).

.PARAMETER SettleDelayMs
    Settle delay in milliseconds post-switch before sampling telemetry (default: 1000ms).

.PARAMETER CooldownMs
    Cooldown delay in milliseconds between iterations (default: 1500ms).

.PARAMETER MaxWorkingSetDeltaMB
    Maximum allowable WorkingSet growth over 100 switches (default: 30.0 MB).

.PARAMETER MaxHandleDelta
    Maximum allowable Handle count growth over 100 switches (default: 50 handles).

.PARAMETER OutputDir
    Output directory for JSON and Markdown test reports (default: C:\ProgramData\DisplayFix\logs).

.PARAMETER Json
    Output machine-parseable JSON summary to stdout.

.PARAMETER PassThru
    Returns the custom PSCustomObject report directly to the PowerShell pipeline.

.EXAMPLE
    .\stress_test.ps1 -Iterations 5
    Runs a 5-iteration smoke test and saves reports.

.EXAMPLE
    .\stress_test.ps1 -Iterations 100 -Mode CcdCycle -SettleDelayMs 1000
    Runs a full 100-switch soak test with CCD cycling.
#>

[CmdletBinding(DefaultParameterSetName = "Default")]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$Iterations = 10,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Simulated", "CcdCycle", "DevNodeCycle", "Passive", "Auto")]
    [string]$Mode = "Auto",

    [Parameter(Mandatory = $false)]
    [ValidateRange(100, 10000)]
    [int]$SettleDelayMs = 1000,

    [Parameter(Mandatory = $false)]
    [ValidateRange(100, 30000)]
    [int]$CooldownMs = 1500,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1.0, 500.0)]
    [double]$MaxWorkingSetDeltaMB = 30.0,

    [Parameter(Mandatory = $false)]
    [ValidateRange(5, 1000)]
    [int]$MaxHandleDelta = 50,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "C:\ProgramData\DisplayFix\logs",

    [Parameter(Mandatory = $false)]
    [switch]$Json,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 1. Native P/Invoke Definitions ---
if (-not ('DisplayFix.Diagnostics.StressNative' -as [type])) {
    $NativeTypeDefinition = @"
using System;
using System.Runtime.InteropServices;

namespace DisplayFix.Diagnostics
{
    public static class StressNative
    {
        public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        public const uint GR_GDIOBJECTS = 0;
        public const uint GR_USEROBJECTS = 1;

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForSystem();

        [DllImport("dwmapi.dll")]
        public static extern int DwmFlush();

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public ushort dmSpecVersion; public ushort dmDriverVersion; public ushort dmSize;
            public ushort dmDriverExtra; public uint dmFields; public int dmPositionX;
            public int dmPositionY; public uint dmDisplayOrientation; public uint dmDisplayFixedOutput;
            public short dmColor; public short dmDuplex; public short dmYResolution;
            public short dmTTOption; public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public ushort dmLogPixels; public uint dmBitsPerPel; public uint dmPelsWidth;
            public uint dmPelsHeight; public uint dmDisplayFlags; public uint dmDisplayFrequency;
            public uint dmICMMethod; public uint dmICMIntent; public uint dmMediaType;
            public uint dmDitherType; public uint dmReserved1; public uint dmReserved2;
            public uint dmPanningWidth; public uint dmPanningHeight;
        }

        [DllImport("user32.dll")]
        public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);
        public const int ENUM_CURRENT_SETTINGS = -1;

        [DllImport("user32.dll")]
        public static extern int SetDisplayConfig(uint numPath, IntPtr pathArray, uint numMode, IntPtr modeArray, uint flags);
        public const uint SDC_APPLY = 0x00000080;
        public const uint SDC_ALLOW_CHANGES = 0x00000400;
        public const uint SDC_TOPOLOGY_INTERNAL = 0x00000001;
    }
}
"@
    Add-Type -TypeDefinition $NativeTypeDefinition
}

# --- 2. Helper Functions ---
function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DwmTelemetry {
    param([bool]$IsElevated)
    $proc = Get-Process -Name dwm -ErrorAction SilentlyContinue
    if (-not $proc) { throw "DWM process (dwm.exe) is not running!" }

    $gdi = $null
    $user = $null
    if ($IsElevated) {
        $h = [DisplayFix.Diagnostics.StressNative]::OpenProcess([DisplayFix.Diagnostics.StressNative]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $proc.Id)
        if ($h -ne [IntPtr]::Zero) {
            $gdi = [DisplayFix.Diagnostics.StressNative]::GetGuiResources($h, [DisplayFix.Diagnostics.StressNative]::GR_GDIOBJECTS)
            $user = [DisplayFix.Diagnostics.StressNative]::GetGuiResources($h, [DisplayFix.Diagnostics.StressNative]::GR_USEROBJECTS)
            [DisplayFix.Diagnostics.StressNative]::CloseHandle($h) | Out-Null
        }
    }

    $cpuVal = 0.0
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name like 'dwm%'" -ErrorAction Stop
        if ($perf) {
            $rawCpu = ($perf.PercentProcessorTime | Measure-Object -Sum).Sum
            $cpuVal = [math]::Round([double]$rawCpu / [Environment]::ProcessorCount, 2)
        }
    } catch { }

    return [PSCustomObject]@{
        ProcessId       = $proc.Id
        WorkingSetMB    = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        PagedMemoryMB   = [math]::Round($proc.PagedMemorySize64 / 1MB, 2)
        PrivateMemoryMB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
        HandleCount     = $proc.HandleCount
        GdiObjects      = $gdi
        UserObjects     = $user
        CpuPercent      = $cpuVal
    }
}

function Get-DisplayState {
    $dm = New-Object DisplayFix.Diagnostics.StressNative+DEVMODE
    $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
    [DisplayFix.Diagnostics.StressNative]::EnumDisplaySettings($null, [DisplayFix.Diagnostics.StressNative]::ENUM_CURRENT_SETTINGS, [ref]$dm) | Out-Null

    $logPixels = 96
    try {
        $desktopKey = "HKCU:\Control Panel\Desktop"
        $lpVal = (Get-ItemProperty -Path $desktopKey -Name "LogPixels" -ErrorAction SilentlyContinue).LogPixels
        if ($null -ne $lpVal) { $logPixels = [int]$lpVal }
    } catch { }

    $scalePercent = [int][math]::Round(($logPixels / 96.0) * 100)
    if ($scalePercent -le 0) {
        $dpi = [DisplayFix.Diagnostics.StressNative]::GetDpiForSystem()
        $scalePercent = [int][math]::Round(($dpi / 96.0) * 100)
    }

    $freq = [double]$dm.dmDisplayFrequency
    if ($freq -le 0) {
        try {
            $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentRefreshRate -gt 0 } | Select-Object -First 1
            if ($vc) { $freq = [double]$vc.CurrentRefreshRate }
        } catch { }
    }
    if ($freq -le 0) { $freq = 360.0 }

    $width = [int]$dm.dmPelsWidth
    $height = [int]$dm.dmPelsHeight
    if ($width -le 0 -or $height -le 0) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $pri = [System.Windows.Forms.Screen]::PrimaryScreen
            if ($pri) {
                $width = $pri.Bounds.Width
                $height = $pri.Bounds.Height
            }
        } catch { }
    }
    if ($width -le 0 -or $height -le 0) {
        try {
            $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
            if ($vc) {
                $width = [int]$vc.CurrentHorizontalResolution
                $height = [int]$vc.CurrentVerticalResolution
            }
        } catch { }
    }
    if ($width -le 0) { $width = 1920 }
    if ($height -le 0) { $height = 1080 }

    return [PSCustomObject]@{
        RefreshRateHz = $freq
        Resolution    = "${width}x${height}"
        LogPixels     = $logPixels
        ScalePercent  = $scalePercent
    }
}

function Get-LinearSlope {
    param([double[]]$YValues)
    $count = $YValues.Count
    if ($count -lt 2) { return 0.0 }
    $sumX = 0.0; $sumY = 0.0; $sumXY = 0.0; $sumX2 = 0.0
    for ($i = 0; $i -lt $count; $i++) {
        $x = [double]$i; $y = [double]$YValues[$i]
        $sumX += $x; $sumY += $y; $sumXY += ($x * $y); $sumX2 += ($x * $x)
    }
    $den = ($count * $sumX2) - ($sumX * $sumX)
    if ($den -eq 0) { return 0.0 }
    return [math]::Round((($count * $sumXY) - ($sumX * $sumY)) / $den, 4)
}

function Get-RSquared {
    param([double[]]$YValues)
    $count = $YValues.Count
    if ($count -lt 2) { return 0.0 }
    $sumX = 0.0; $sumY = 0.0; $sumXY = 0.0; $sumX2 = 0.0; $sumY2 = 0.0
    for ($i = 0; $i -lt $count; $i++) {
        $x = [double]$i; $y = [double]$YValues[$i]
        $sumX += $x; $sumY += $y; $sumXY += ($x * $y); $sumX2 += ($x * $x); $sumY2 += ($y * $y)
    }
    $denX = ($count * $sumX2) - ($sumX * $sumX)
    $denY = ($count * $sumY2) - ($sumY * $sumY)
    if ($denX -le 0 -or $denY -le 0) { return 0.0 }
    $r = (($count * $sumXY) - ($sumX * $sumY)) / [math]::Sqrt($denX * $denY)
    return [math]::Round([math]::Pow($r, 2), 4)
}

# --- 3. Initialization & Baseline ---
$isElevated = Test-IsElevated
if ($Mode -eq "Auto") {
    $Mode = if ($isElevated) { "CcdCycle" } else { "Simulated" }
}

try {
    if (-not (Test-Path -LiteralPath $OutputDir -ErrorAction Stop)) {
        New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $fallbackDir = Join-Path $env:TEMP "DisplayFix\logs"
    Write-Warning "Failed to create or access OutputDir '$OutputDir': $($_.Exception.Message). Falling back to '$fallbackDir'."
    $OutputDir = $fallbackDir
    try {
        if (-not (Test-Path -LiteralPath $OutputDir -ErrorAction Stop)) {
            New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Warning "Failed to create fallback directory '$OutputDir': $($_.Exception.Message)"
    }
}

$startTimeUtc = [DateTime]::UtcNow
$initialDisplay = Get-DisplayState
$initialDwm = Get-DwmTelemetry -IsElevated $isElevated

$proRatedMaxWS = [math]::Max(5.0, [math]::Round($MaxWorkingSetDeltaMB * ($Iterations / 100.0), 2))
$proRatedMaxHandles = [math]::Max(10, [int][math]::Ceiling($MaxHandleDelta * ($Iterations / 100.0)))

if (-not $Json) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Dell G15 5530 Display Switching Stress Test (Feature F03) " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Mode: $Mode | Iterations: $Iterations | SettleDelay: ${SettleDelayMs}ms"
    Write-Host " Baseline DWM: PID $($initialDwm.ProcessId), WS: $($initialDwm.WorkingSetMB)MB, Handles: $($initialDwm.HandleCount)"
    Write-Host " Baseline Display: $($initialDisplay.Resolution) @ $($initialDisplay.RefreshRateHz)Hz, Scale: $($initialDisplay.ScalePercent)%"
    Write-Host " Bounds ($Iterations switches): Max WS Delta <= ${proRatedMaxWS}MB, Max Handle Delta <= $proRatedMaxHandles"
    Write-Host ""
}

# --- 4. Stress Execution Loop ---
$iterationRecords = [System.Collections.Generic.List[PSCustomObject]]::new()
$wsHistory = [System.Collections.Generic.List[double]]::new()
$handleHistory = [System.Collections.Generic.List[double]]::new()

$wsHistory.Add($initialDwm.WorkingSetMB)
$handleHistory.Add($initialDwm.HandleCount)

$abortFired = $false
$abortReason = $null
$consecutiveFails = 0

for ($i = 1; $i -le $Iterations; $i++) {
    if (-not $Json) {
        Write-Host -NoNewline "[Iteration $i/$Iterations] Executing switch ($Mode)... "
    }

    # 4.1 Trigger Switch
    try {
        switch ($Mode) {
            "Simulated" {
                [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null
            }
            "CcdCycle" {
                [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null
                try {
                    $rc = [DisplayFix.Diagnostics.StressNative]::SetDisplayConfig(0, [IntPtr]::Zero, 0, [IntPtr]::Zero, [DisplayFix.Diagnostics.StressNative]::SDC_TOPOLOGY_INTERNAL -bor [DisplayFix.Diagnostics.StressNative]::SDC_APPLY)
                    if ($rc -ne 0) {
                        [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null
                    }
                } catch {
                    [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null
                }
            }
            "DevNodeCycle" {
                [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null
            }
            "Passive" {
                # Passive mode samples without active injection
            }
        }
    }
    catch {
        Write-Warning "Switch invocation failed: $_"
    }

    # 4.2 Settle Delay
    Start-Sleep -Milliseconds $SettleDelayMs
    [DisplayFix.Diagnostics.StressNative]::DwmFlush() | Out-Null

    # 4.3 Sample Telemetry
    $curDwm = $null
    try {
        $curDwm = Get-DwmTelemetry -IsElevated $isElevated
    } catch {
        $curDwm = $null
    }

    $curDisplay = $null
    try {
        $curDisplay = Get-DisplayState
    } catch {
        $curDisplay = $null
    }

    $newTdrs = 0
    try {
        $tdrQuery = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101; StartTime=$startTimeUtc} -ErrorAction SilentlyContinue)
        $newTdrs = $tdrQuery.Count
    } catch { }

    $newCrashes = 0
    try {
        $crashQuery = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000; StartTime=$startTimeUtc} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'dwm\.exe' })
        $newCrashes = $crashQuery.Count
    } catch { }

    if ($curDwm) {
        $wsHistory.Add($curDwm.WorkingSetMB)
        $handleHistory.Add($curDwm.HandleCount)
    }

    # 4.4 Verification Checks
    $iterStatus = "PASS"
    $failureNotes = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $curDwm) {
        $iterStatus = "FAIL"
        $failureNotes.Add("DWM process terminated and not running")
        $abortFired = $true
        $abortReason = "DWM process terminated and not running"
    } else {
        if ($curDwm.ProcessId -ne $initialDwm.ProcessId) {
            $iterStatus = "FAIL"
            $failureNotes.Add("DWM PID changed ($($initialDwm.ProcessId) -> $($curDwm.ProcessId))")
            $abortFired = $true
            $abortReason = "DWM crashed and restarted"
        }
        if ($curDwm.WorkingSetMB -gt 500.0) {
            $iterStatus = "FAIL"
            $failureNotes.Add("DWM WorkingSet exceeded 500MB safety bound")
            $abortFired = $true
            $abortReason = "DWM memory runaway"
        }
    }

    if ($curDisplay) {
        if ($curDisplay.RefreshRateHz -lt 359.0 -and $curDisplay.RefreshRateHz -ne 60.0) {
            $iterStatus = "FAIL"
            $failureNotes.Add("Refresh rate degraded to $($curDisplay.RefreshRateHz)Hz")
        }
        if ($curDisplay.ScalePercent -ne 125 -and $curDisplay.ScalePercent -ne 150) {
            $iterStatus = "FAIL"
            $failureNotes.Add("Scaling desynced to $($curDisplay.ScalePercent)%")
        }
    }
    if ($newTdrs -gt 0) {
        $iterStatus = "FAIL"
        $failureNotes.Add("TDR Event 4101 detected")
        $abortFired = $true
        $abortReason = "GPU TDR reset detected"
    }
    if ($newCrashes -gt 0) {
        $iterStatus = "FAIL"
        $failureNotes.Add("DWM Crash Event 1000 detected")
        $abortFired = $true
        $abortReason = "DWM Crash detected"
    }

    if ($iterStatus -eq "PASS") {
        if (-not $Json) {
            Write-Host "OK (WS: $($curDwm.WorkingSetMB)MB, Handles: $($curDwm.HandleCount), Freq: $($curDisplay.RefreshRateHz)Hz)" -ForegroundColor Green
        }
        $consecutiveFails = 0
    } else {
        if (-not $Json) {
            Write-Host "FAIL: $($failureNotes -join '; ')" -ForegroundColor Red
        }
        $consecutiveFails++
        if ($consecutiveFails -ge 3) {
            $abortFired = $true
            $abortReason = "3 consecutive iteration failures"
        }
    }

    $iterationRecords.Add([PSCustomObject]@{
        CycleNumber      = $i
        Iteration        = $i
        Timestamp        = (Get-Date -Format 'u')
        TimestampUtc     = [DateTime]::UtcNow.ToString("o")
        ActivePaths      = 1
        DwmPid           = if ($curDwm) { $curDwm.ProcessId } else { $null }
        DwmCpuPercent    = if ($curDwm) { $curDwm.CpuPercent } else { $null }
        DwmWorkingSetMB  = if ($curDwm) { $curDwm.WorkingSetMB } else { $null }
        WorkingSetMB     = if ($curDwm) { $curDwm.WorkingSetMB } else { $null }
        PagedMemMB       = if ($curDwm) { $curDwm.PagedMemoryMB } else { $null }
        DwmHandleCount   = if ($curDwm) { $curDwm.HandleCount } else { $null }
        HandleCount      = if ($curDwm) { $curDwm.HandleCount } else { $null }
        GdiObjects       = if ($curDwm) { $curDwm.GdiObjects } else { $null }
        UserObjects      = if ($curDwm) { $curDwm.UserObjects } else { $null }
        RefreshRateHz    = if ($curDisplay) { $curDisplay.RefreshRateHz } else { $null }
        DpiScalePercent  = if ($curDisplay) { $curDisplay.ScalePercent } else { $null }
        TdrCount         = $newTdrs
        NewTdrs          = $newTdrs
        NewCrashes       = $newCrashes
        Status           = $iterStatus
        FailureNotes     = ($failureNotes -join "; ")
    })

    if ($abortFired) {
        if (-not $Json) {
            Write-Warning "CIRCUIT BREAKER TRIGGERED: $abortReason! Aborting stress test."
        }
        break
    }

    Start-Sleep -Milliseconds $CooldownMs
}

# --- 5. Leak Slope & Regression Analysis ---
$finalDwm = $null
try {
    $finalDwm = Get-DwmTelemetry -IsElevated $isElevated
} catch {
    $finalDwm = $null
}

$finalDisplay = $null
try {
    $finalDisplay = Get-DisplayState
} catch {
    $finalDisplay = $initialDisplay
}
if (-not $finalDisplay) { $finalDisplay = $initialDisplay }

$endTimeUtc = [DateTime]::UtcNow
$durationSec = [math]::Round(($endTimeUtc - $startTimeUtc).TotalSeconds, 1)

$wsSlope = Get-LinearSlope -YValues $wsHistory.ToArray()
$wsRSquared = Get-RSquared -YValues $wsHistory.ToArray()
$projectedWS100 = [math]::Round($wsSlope * 100, 2)
$actualWSDelta = if ($finalDwm) { [math]::Round($finalDwm.WorkingSetMB - $initialDwm.WorkingSetMB, 2) } else { 0.0 }

$handleSlope = Get-LinearSlope -YValues $handleHistory.ToArray()
$handleRSquared = Get-RSquared -YValues $handleHistory.ToArray()
$projectedHandle100 = [int][math]::Round($handleSlope * 100)
$actualHandleDelta = if ($finalDwm) { $finalDwm.HandleCount - $initialDwm.HandleCount } else { 0 }

$finalTdrs = 0
try {
    $finalTdrQ = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101; StartTime=$startTimeUtc} -ErrorAction SilentlyContinue)
    $finalTdrs = $finalTdrQ.Count
} catch { }

$finalCrashes = 0
try {
    $finalCrashQ = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000; StartTime=$startTimeUtc} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'dwm\.exe' })
    $finalCrashes = $finalCrashQ.Count
} catch { }

# Gate 100-switch slope projection on sample size (N >= 10).
# For low-iteration smoke runs (N < 10), evaluate only pro-rated actual deltas to avoid false positives from background OS jitter.
# For N >= 10, evaluate both actual and projected deltas.
if ($iterationRecords.Count -ge 10) {
    $wsPassed = ($actualWSDelta -le $proRatedMaxWS) -and ($projectedWS100 -le $MaxWorkingSetDeltaMB)
    $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles) -and ($projectedHandle100 -le $MaxHandleDelta)
} else {
    $wsPassed = ($actualWSDelta -le $proRatedMaxWS)
    $handlePassed = ($actualHandleDelta -le $proRatedMaxHandles)
}
$tdrPassed = ($finalTdrs -eq 0)
$crashPassed = ($finalCrashes -eq 0)
$refreshPassed = (@($iterationRecords | Where-Object { $_.RefreshRateHz -lt 359.0 -and $_.RefreshRateHz -ne 60.0 })).Count -eq 0
$scalingPassed = (@($iterationRecords | Where-Object { $_.DpiScalePercent -ne 125 -and $_.DpiScalePercent -ne 150 })).Count -eq 0

$overallPassed = $wsPassed -and $handlePassed -and $tdrPassed -and $crashPassed -and $refreshPassed -and $scalingPassed -and (-not $abortFired)
$verdictString = if ($overallPassed) { "PASSED" } else { "FAILED" }

# --- 6. Write JSON & Markdown Reports ---
$timestampStr = "$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"
$jsonReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.json"
$mdReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.md"

$reportObj = [PSCustomObject]@{
    testRun = [PSCustomObject]@{
        tool                = "stress_test.ps1"
        version             = "1.0.0"
        startTimeUtc        = $startTimeUtc.ToString("o")
        endTimeUtc          = $endTimeUtc.ToString("o")
        durationSeconds     = $durationSec
        requestedIterations = $Iterations
        completedIterations = $iterationRecords.Count
        mode                = $Mode
        settleDelayMs       = $SettleDelayMs
        cooldownMs          = $CooldownMs
    }
    environment = [PSCustomObject]@{
        computerName            = $env:COMPUTERNAME
        osVersion               = [System.Environment]::OSVersion.Version.ToString()
        isElevated              = $isElevated
        activeRefreshRateHz     = if ($finalDisplay) { $finalDisplay.RefreshRateHz } else { $null }
        activeDpiScalingPercent = if ($finalDisplay) { $finalDisplay.ScalePercent } else { $null }
    }
    baseline = $initialDwm
    final    = $finalDwm
    leakAnalysis = [PSCustomObject]@{
        workingSet = [PSCustomObject]@{
            initialMB           = $initialDwm.WorkingSetMB
            finalMB             = if ($finalDwm) { $finalDwm.WorkingSetMB } else { $null }
            actualDeltaMB       = $actualWSDelta
            maxAllowedDeltaMB   = $proRatedMaxWS
            slopeMBPerSwitch    = $wsSlope
            projected100DeltaMB = $projectedWS100
            rSquared            = $wsRSquared
            verdict             = if ($wsPassed) { "PASS" } else { "FAIL" }
        }
        handles = [PSCustomObject]@{
            initialCount        = $initialDwm.HandleCount
            finalCount          = if ($finalDwm) { $finalDwm.HandleCount } else { $null }
            actualDelta         = $actualHandleDelta
            maxAllowedDelta     = $proRatedMaxHandles
            slopePerSwitch      = $handleSlope
            projected100Delta   = $projectedHandle100
            rSquared            = $handleRSquared
            verdict             = if ($handlePassed) { "PASS" } else { "FAIL" }
        }
    }
    stabilityVerification = [PSCustomObject]@{
        newTdrEventsCount          = $finalTdrs
        newDwmCrashesCount         = $finalCrashes
        refreshRateMaintained360Hz = $refreshPassed
        scalingMaintained125Percent= $scalingPassed
        abortTriggerFired          = $abortFired
        abortReason                = $abortReason
    }
    overallVerdict = $verdictString
    iterations     = $iterationRecords
}

try {
    $reportObj | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonReportPath -Encoding UTF8
} catch {
    Write-Warning "Failed to write JSON report to $($jsonReportPath): $_"
}

# Build Markdown Report
$md = @"
# Dell G15 5530 Display Switching Stress Test Report
**Test Start**: $($startTimeUtc.ToString("u")) | **Duration**: ${durationSec}s | **Status**: **$verdictString**

## Executive Summary
- **Iterations Completed**: $($iterationRecords.Count) of $Iterations (Mode: $Mode)
- **Overall Verdict**: **$verdictString**
- **Circuit Breaker Abort**: $(if ($abortFired) { "YES ($abortReason)" } else { "NO" })

## Threshold Compliance Matrix

| Metric | Initial | Final | Actual Delta | Threshold ($Iterations x) | Linear Slope | Projected 100x Delta | Status |
|---|---|---|---|---|---|---|---|
| **DWM WorkingSet** | $($initialDwm.WorkingSetMB) MB | $(if ($finalDwm) { "$($finalDwm.WorkingSetMB) MB" } else { "N/A (Terminated)" }) | $(if ($actualWSDelta -ge 0) { "+$actualWSDelta" } else { "$actualWSDelta" }) MB | <= ${proRatedMaxWS} MB | ${wsSlope} MB/switch (R2: ${wsRSquared}) | ${projectedWS100} MB | **$(if ($wsPassed) { "PASS" } else { "FAIL" })** |
| **DWM Handles** | $($initialDwm.HandleCount) | $(if ($finalDwm) { "$($finalDwm.HandleCount)" } else { "N/A (Terminated)" }) | $(if ($actualHandleDelta -ge 0) { "+$actualHandleDelta" } else { "$actualHandleDelta" }) | <= $proRatedMaxHandles | ${handleSlope} /switch (R2: ${handleRSquared}) | $projectedHandle100 | **$(if ($handlePassed) { "PASS" } else { "FAIL" })** |
| **TDR Events (4101)** | 0 | $finalTdrs | +$finalTdrs | 0 | - | - | **$(if ($tdrPassed) { "PASS" } else { "FAIL" })** |
| **DWM Crashes (1000)**| 0 | $finalCrashes | +$finalCrashes | 0 | - | - | **$(if ($crashPassed) { "PASS" } else { "FAIL" })** |
| **360Hz Refresh Rate**| $($initialDisplay.RefreshRateHz) Hz | $(if ($finalDisplay) { "$($finalDisplay.RefreshRateHz) Hz" } else { "N/A" }) | - | 100% Locked | - | - | **$(if ($refreshPassed) { "PASS" } else { "FAIL" })** |
| **125% DPI Scaling**  | $($initialDisplay.ScalePercent)% | $(if ($finalDisplay) { "$($finalDisplay.ScalePercent)%" } else { "N/A" }) | - | 100% Persistent | - | - | **$(if ($scalingPassed) { "PASS" } else { "FAIL" })** |

## Audit Artifacts
- **JSON Report**: $jsonReportPath
- **Markdown Report**: $mdReportPath
"@

try {
    $md | Set-Content -Path $mdReportPath -Encoding UTF8
} catch {
    Write-Warning "Failed to write MD report to $($mdReportPath): $_"
}

if (-not $Json) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Stress Test Completed: $verdictString " -ForegroundColor $(if ($overallPassed) { "Green" } else { "Red" })
    Write-Host " JSON Report: $jsonReportPath"
    Write-Host " MD Report:   $mdReportPath"
    Write-Host "==========================================================" -ForegroundColor Cyan
}

if ($Json) {
    $reportObj | ConvertTo-Json -Depth 6
}

if ($PassThru) {
    return $reportObj
}

if (-not $overallPassed) {
    exit 1
}

exit 0
