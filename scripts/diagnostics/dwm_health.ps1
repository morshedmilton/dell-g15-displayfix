<#
.SYNOPSIS
    DWM Health & Stability Monitor for Dell G15 5530 (Feature F02).

.DESCRIPTION
    Probes Desktop Window Manager (dwm.exe) memory footprint, CPU utilization,
    process handle counts, Win32 GUI handles (GetGuiResources), and checks Windows
    Event Logs for TDR driver resets (Event 4101) and DWM crash events (Event 1000/1001).
    Evaluates metrics against Contract 5 thresholds and outputs formatted console report
    or structured JSON.

.PARAMETER Since
    Check event log entries occurring at or after this DateTime. Defaults to system boot time.

.PARAMETER LookbackMinutes
    Check event log entries occurring in the last N minutes.

.PARAMETER AllTime
    Scan all available event logs without time filtering.

.PARAMETER MaxWorkingSetMB
    Warning threshold for Working Set memory in megabytes (default: 250.0 MB).

.PARAMETER MaxHandleCount
    Warning threshold for process handle count (default: 2500).

.PARAMETER MaxGdiObjects
    Warning threshold for Win32 GDI objects (default: 200).

.PARAMETER MaxUserObjects
    Warning threshold for Win32 USER objects (default: 400).

.PARAMETER MaxCpuPercent
    Warning threshold for DWM CPU percentage (default: 20.0%).

.PARAMETER FailOnWarning
    Exit with code 1 if soft warning thresholds are exceeded.

.PARAMETER Json
    Emit structured JSON to stdout.

.PARAMETER OutputFile
    Optional file path to write JSON report to disk.

.PARAMETER PassThru
    Returns the custom PSCustomObject report to the PowerShell pipeline.
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Default')]
    [DateTime]$Since,

    [Parameter(ParameterSetName = 'Lookback')]
    [ValidateRange(1, 10080)]
    [int]$LookbackMinutes,

    [Parameter(ParameterSetName = 'AllTime')]
    [switch]$AllTime,

    [ValidateRange(50, 2048)]
    [double]$MaxWorkingSetMB = 250.0,

    [ValidateRange(500, 10000)]
    [int]$MaxHandleCount = 2500,

    [ValidateRange(10, 1000)]
    [int]$MaxGdiObjects = 200,

    [ValidateRange(50, 2000)]
    [int]$MaxUserObjects = 400,

    [ValidateRange(5.0, 100.0)]
    [double]$MaxCpuPercent = 20.0,

    [switch]$FailOnWarning,

    [switch]$Json,

    [string]$OutputFile,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------
# 1. Type Registration & P/Invoke Definitions (Idempotent)
# ---------------------------------------------------------
if (-not ('DisplayFix.Diagnostics.DwmNative' -as [type])) {
    $csharp = @"
using System;
using System.Runtime.InteropServices;

namespace DisplayFix.Diagnostics
{
    public static class DwmNative
    {
        public const uint PROCESS_QUERY_INFORMATION = 0x0400;
        public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        public const uint GR_GDIOBJECTS = 0;
        public const uint GR_USEROBJECTS = 1;

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetCurrentProcess();

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }

        private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        private const uint TOKEN_QUERY = 0x0008;
        private const uint SE_PRIVILEGE_ENABLED = 0x00000002;

        public static bool EnablePrivilege(string privilegeName)
        {
            IntPtr hToken;
            if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hToken))
                return false;
            try
            {
                LUID luid;
                if (!LookupPrivilegeValue(null, privilegeName, out luid)) return false;
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Privileges.Luid = luid;
                tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;
                return AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            }
            finally { CloseHandle(hToken); }
        }

        public static int QueryGuiResources(int pid, out uint gdi, out uint user, out string status)
        {
            gdi = 0;
            user = 0;
            EnablePrivilege("SeDebugPrivilege");

            IntPtr hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
            if (hProc == IntPtr.Zero)
            {
                hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            }
            if (hProc == IntPtr.Zero)
            {
                int err = Marshal.GetLastWin32Error();
                status = "OpenProcess error " + err;
                return err;
            }
            try
            {
                gdi = GetGuiResources(hProc, GR_GDIOBJECTS);
                user = GetGuiResources(hProc, GR_USEROBJECTS);
                status = "OK";
                return 0;
            }
            finally
            {
                CloseHandle(hProc);
            }
        }
    }
}
"@
    Add-Type -TypeDefinition $csharp
}

# ---------------------------------------------------------
# 2. Elevation & Environment Assessment
# ---------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------
# 3. Time Window Selection for Event Queries
# ---------------------------------------------------------
$bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
if (-not $bootTime) { $bootTime = (Get-Date).AddHours(-24) }
$timeDesc = ""

if ($AllTime) {
    $queryStartTime = [DateTime]::MinValue
    $timeDesc = "All Available History"
} elseif ($PSBoundParameters.ContainsKey('LookbackMinutes')) {
    $queryStartTime = (Get-Date).AddMinutes(-$LookbackMinutes)
    $timeDesc = "Last $LookbackMinutes Minutes"
} elseif ($PSBoundParameters.ContainsKey('Since')) {
    $queryStartTime = $Since
    $timeDesc = "Since $($Since.ToString('yyyy-MM-dd HH:mm:ss'))"
} else {
    $queryStartTime = $bootTime
    $timeDesc = "Since System Boot ($($bootTime.ToString('yyyy-MM-dd HH:mm:ss')))"
}

# ---------------------------------------------------------
# 4. Probe DWM Process
# ---------------------------------------------------------
$dwm = Get-Process -Name dwm -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $dwm) {
    $failureReport = [PSCustomObject]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Status    = "Critical"
        ExitCode  = 2
        Error     = "dwm.exe process is not currently running"
    }
    if ($Json) { $failureReport | ConvertTo-Json -Depth 4 }
    else { Write-Error "CRITICAL: Desktop Window Manager (dwm.exe) is not running!" }
    exit 2
}

# CPU Sampling via WMI / PerfFormattedData or Get-Counter
$cpuPercent = 0.0
try {
    $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name like 'dwm%'" -ErrorAction Stop
    if ($perf) {
        $rawCpu = ($perf.PercentProcessorTime | Measure-Object -Sum).Sum
        $cpuPercent = [math]::Round([double]$rawCpu / [Environment]::ProcessorCount, 2)
    }
} catch {
    try {
        $counter = (Get-Counter "\Process(dwm*)\% Processor Time" -ErrorAction Stop).CounterSamples |
                   Measure-Object -Property CookedValue -Sum
        $cpuPercent = [math]::Round($counter.Sum / [Environment]::ProcessorCount, 2)
    } catch {
        $cpuPercent = 0.0
    }
}

$workingSetMB = [math]::Round($dwm.WorkingSet64 / 1MB, 2)
$pagedMemoryMB = [math]::Round($dwm.PagedMemorySize64 / 1MB, 2)
$privateMemoryMB = [math]::Round($dwm.PrivateMemorySize64 / 1MB, 2)
$peakWorkingSetMB = [math]::Round($dwm.PeakWorkingSet64 / 1MB, 2)
$handleCount = $dwm.HandleCount
$threadCount = $dwm.Threads.Count

# ---------------------------------------------------------
# 5. Probe Win32 GUI Handles (GDI & USER Objects)
# ---------------------------------------------------------
[uint32]$gdiObjects = 0
[uint32]$userObjects = 0
[string]$guiStatus = ""
$guiAvailable = $false

$rc = [DisplayFix.Diagnostics.DwmNative]::QueryGuiResources($dwm.Id, [ref]$gdiObjects, [ref]$userObjects, [ref]$guiStatus)
if ($rc -eq 0) {
    $guiAvailable = $true
} else {
    $guiAvailable = $false
    $gdiObjects = $null
    $userObjects = $null
}

# ---------------------------------------------------------
# 6. Check Windows Event Logs for Stability Violations
# ---------------------------------------------------------
# System Log: Event ID 4101 (TDR Resets)
$tdrFilter = @{
    LogName = 'System'
    Id      = 4101
}
if ($queryStartTime -ne [DateTime]::MinValue) {
    $tdrFilter['StartTime'] = $queryStartTime
}

try {
    $rawTdrEvents = @(Get-WinEvent -FilterHashtable $tdrFilter -ErrorAction Stop)
    $tdrEvents = @($rawTdrEvents | Select-Object -Property TimeCreated, Id, ProviderName, Message)
} catch {
    $tdrEvents = @()
}

# Application Log: Event ID 1000 / 1001 (DWM Crashes)
$appFilter = @{
    LogName = 'Application'
    Id      = @(1000, 1001)
}
if ($queryStartTime -ne [DateTime]::MinValue) {
    $appFilter['StartTime'] = $queryStartTime
}

try {
    $rawAppEvents = @(Get-WinEvent -FilterHashtable $appFilter -ErrorAction Stop)
    $dwmCrashEvents = @($rawAppEvents | Where-Object {
        $_.Message -like '*dwm.exe*' -or $_.Message -like '*dgit.dll*' -or $_.Message -like '*dwmcore.dll*'
    } | Select-Object -Property TimeCreated, Id, ProviderName, Message)
} catch {
    $dwmCrashEvents = @()
}

# ---------------------------------------------------------
# 7. Evaluate Health Thresholds & Violations
# ---------------------------------------------------------
$violations = [System.Collections.Generic.List[string]]::new()
$hasCritical = $false
$hasWarning = $false

# Critical: Any TDR Event
if ($tdrEvents.Count -gt 0) {
    $violations.Add("CRITICAL: $($tdrEvents.Count) TDR driver reset event(s) (Event ID 4101) detected.")
    $hasCritical = $true
}

# Critical: Any DWM Crash
if ($dwmCrashEvents.Count -gt 0) {
    $violations.Add("CRITICAL: $($dwmCrashEvents.Count) DWM crash event(s) (Event ID 1000/1001) detected.")
    $hasCritical = $true
}

# Critical: Memory Leak Exceeding 500 MB
if ($workingSetMB -gt 500.0) {
    $violations.Add("CRITICAL: DWM Working Set is critically high: ${workingSetMB} MB (limit: 500.0 MB).")
    $hasCritical = $true
}

# Critical: Severe CPU Starvation (> 30%)
if ($cpuPercent -gt 30.0) {
    $violations.Add("CRITICAL: DWM CPU usage indicates active V-Sync starvation: ${cpuPercent}% (limit: 30.0%).")
    $hasCritical = $true
}

# Warning: Working Set between MaxWorkingSetMB and 500 MB
if ($workingSetMB -gt $MaxWorkingSetMB -and $workingSetMB -le 500.0) {
    $violations.Add("WARNING: DWM Working Set (${workingSetMB} MB) exceeds threshold (${MaxWorkingSetMB} MB).")
    $hasWarning = $true
}

# Warning: Handle Count
if ($handleCount -gt $MaxHandleCount) {
    $violations.Add("WARNING: DWM Handle Count ($handleCount) exceeds threshold ($MaxHandleCount).")
    $hasWarning = $true
}

# Warning: GDI Objects (if available)
if ($guiAvailable -and $null -ne $gdiObjects -and $gdiObjects -gt $MaxGdiObjects) {
    $violations.Add("WARNING: DWM GDI Objects ($gdiObjects) exceeds threshold ($MaxGdiObjects).")
    $hasWarning = $true
}

# Warning: USER Objects (if available)
if ($guiAvailable -and $null -ne $userObjects -and $userObjects -gt $MaxUserObjects) {
    $violations.Add("WARNING: DWM USER Objects ($userObjects) exceeds threshold ($MaxUserObjects).")
    $hasWarning = $true
}

# Warning: CPU between MaxCpuPercent and 30%
if ($cpuPercent -gt $MaxCpuPercent -and $cpuPercent -le 30.0) {
    $violations.Add("WARNING: DWM CPU utilization (${cpuPercent}%) exceeds threshold (${MaxCpuPercent}%).")
    $hasWarning = $true
}

# Determine Overall Status & Exit Code
$exitCode = 0
$status = "Healthy"

if ($hasCritical) {
    $status = "Critical"
    $exitCode = 2
} elseif ($hasWarning) {
    $status = "Warning"
    $exitCode = if ($FailOnWarning) { 1 } else { 0 }
}

# ---------------------------------------------------------
# 8. Assemble Structured Report
# ---------------------------------------------------------
$report = [PSCustomObject]@{
    Timestamp       = (Get-Date).ToUniversalTime().ToString("o")
    Status          = $status
    ExitCode        = $exitCode
    IsElevated      = $isElevated
    Process         = [PSCustomObject]@{
        Id               = $dwm.Id
        ProcessName      = $dwm.ProcessName
        CpuPercent       = $cpuPercent
        WorkingSetMB     = $workingSetMB
        PagedMemoryMB    = $pagedMemoryMB
        PrivateMemoryMB  = $privateMemoryMB
        PeakWorkingSetMB = $peakWorkingSetMB
        HandleCount      = $handleCount
        ThreadCount      = $threadCount
    }
    GuiResources    = [PSCustomObject]@{
        Available   = $guiAvailable
        GdiObjects  = $gdiObjects
        UserObjects = $userObjects
        Reason      = if (-not $guiAvailable) { "Access Denied (Requires Administrator Elevation)" } else { "Success" }
    }
    StabilityEvents = [PSCustomObject]@{
        QuerySince            = if ($queryStartTime -ne [DateTime]::MinValue) { $queryStartTime.ToUniversalTime().ToString("o") } else { "AllTime" }
        TimeWindowDescription = $timeDesc
        TdrCount              = $tdrEvents.Count
        TdrEvents             = $tdrEvents
        DwmCrashCount         = $dwmCrashEvents.Count
        DwmCrashEvents        = $dwmCrashEvents
    }
    Thresholds      = [PSCustomObject]@{
        MaxWorkingSetMB = $MaxWorkingSetMB
        MaxHandleCount  = $MaxHandleCount
        MaxGdiObjects   = $MaxGdiObjects
        MaxUserObjects  = $MaxUserObjects
        MaxCpuPercent   = $MaxCpuPercent
        MaxTdrEvents    = 0
        MaxDwmCrashes   = 0
    }
    Violations      = @($violations)
}

# ---------------------------------------------------------
# 9. Output Delivery
# ---------------------------------------------------------
$jsonOutput = $report | ConvertTo-Json -Depth 5

if ($OutputFile) {
    try {
        $outDir = Split-Path -Parent $OutputFile
        if ($outDir -and -not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        Set-Content -Path $OutputFile -Value $jsonOutput -Encoding UTF8
    } catch {
        Write-Warning "Failed to save output file: $_"
    }
}

if ($Json) {
    Write-Output $jsonOutput
} else {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  Dell G15 5530 -- DWM Health & Stability Monitor (F02)" -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "[+] DWM Process Status    : RUNNING (PID: $($dwm.Id))" -ForegroundColor Green
    $elevDesc = if ($isElevated) { 'Elevated (Administrator)' } else { 'Standard User (Run as Admin for GDI/USER)' }
    Write-Host "[+] Elevation Level       : $elevDesc"
    $cpuColor = if ($cpuPercent -gt $MaxCpuPercent) { 'Yellow' } else { 'Green' }
    Write-Host "[+] CPU Utilization       : ${cpuPercent}% (Threshold: < ${MaxCpuPercent}%)" -ForegroundColor $cpuColor
    $wsColor = if ($workingSetMB -gt $MaxWorkingSetMB) { 'Yellow' } else { 'Green' }
    Write-Host "[+] Working Set Memory    : ${workingSetMB} MB (Threshold: < ${MaxWorkingSetMB} MB)" -ForegroundColor $wsColor
    Write-Host "[+] Private Committed     : ${privateMemoryMB} MB (Peak WS: ${peakWorkingSetMB} MB)"
    $hColor = if ($handleCount -gt $MaxHandleCount) { 'Yellow' } else { 'Green' }
    Write-Host "[+] Process Handle Count  : $handleCount (Threshold: < $MaxHandleCount)" -ForegroundColor $hColor
    Write-Host "[+] Thread Count          : $threadCount threads"
    if ($guiAvailable) {
        $gdiColor = if ($gdiObjects -gt $MaxGdiObjects) { 'Yellow' } else { 'Green' }
        Write-Host "[+] Win32 GDI Objects     : $gdiObjects (Threshold: < $MaxGdiObjects)" -ForegroundColor $gdiColor
        $userColor = if ($userObjects -gt $MaxUserObjects) { 'Yellow' } else { 'Green' }
        Write-Host "[+] Win32 USER Objects    : $userObjects (Threshold: < $MaxUserObjects)" -ForegroundColor $userColor
    } else {
        Write-Host "[*] Win32 GUI Resources   : [N/A] (Requires Administrator elevation)" -ForegroundColor Gray
    }
    $tdrColor = if ($tdrEvents.Count -gt 0) { 'Red' } else { 'Green' }
    Write-Host "[+] TDR Resets (ID 4101)  : $($tdrEvents.Count) events ($timeDesc)" -ForegroundColor $tdrColor
    $crashColor = if ($dwmCrashEvents.Count -gt 0) { 'Red' } else { 'Green' }
    Write-Host "[+] DWM Crashes (ID 1000) : $($dwmCrashEvents.Count) events ($timeDesc)" -ForegroundColor $crashColor

    if ($violations.Count -gt 0) {
        Write-Host "----------------------------------------------------------------------" -ForegroundColor Red
        Write-Host "VIOLATIONS DETECTED:" -ForegroundColor Red
        foreach ($v in $violations) {
            $vColor = if ($v -like 'CRITICAL*') { 'Red' } else { 'Yellow' }
            Write-Host "  - $v" -ForegroundColor $vColor
        }
    }
    Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
    $statusColor = if ($exitCode -eq 0) { 'Green' } elseif ($exitCode -eq 1) { 'Yellow' } else { 'Red' }
    Write-Host "OVERALL HEALTH ASSESSMENT : $status (Exit Code: $exitCode)" -ForegroundColor $statusColor
    Write-Host "======================================================================" -ForegroundColor Cyan
}

if ($PassThru) {
    return $report
}

exit $exitCode
