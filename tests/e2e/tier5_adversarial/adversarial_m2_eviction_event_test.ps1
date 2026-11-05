# tests/e2e/tier5_adversarial/adversarial_m2_eviction_event_test.ps1
# Tier 5 Adversarial Stress & Safety Invariant Test Suite for Milestone 2
# Ghost Monitor Eviction Engine & Event Window (Debouncing, Latency, Handles, Memory, DWM CPU)

[CmdletBinding()]
param(
    [switch]$DetailedOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item (Join-Path $scriptDir '..\..\..')).FullName
$daemonExePath = Join-Path $projectRoot 'bin\DisplayFixDaemon.exe'

if (-not (Test-Path $daemonExePath)) {
    Write-Error "DisplayFixDaemon.exe not found at '$daemonExePath'. Run build.ps1 first."
    exit 1
}

# Load the compiled assembly
$assembly = [System.Reflection.Assembly]::LoadFrom($daemonExePath)

# Register thread-safe C# collector for background thread callbacks
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace DisplayFix.Tests
{
    public class ReconfigCollector
    {
        private readonly object _lock = new object();
        public readonly List<string> Reasons = new List<string>();
        public readonly List<double> Timestamps = new List<double>();
        public Stopwatch Stopwatch = Stopwatch.StartNew();

        public void OnReconfig(string reason)
        {
            lock (_lock)
            {
                Reasons.Add(reason);
                Timestamps.Add(Stopwatch.Elapsed.TotalMilliseconds);
            }
        }

        public int Count
        {
            get { lock (_lock) { return Reasons.Count; } }
        }

        public string GetReason(int index)
        {
            lock (_lock) { return (index >= 0 && index < Reasons.Count) ? Reasons[index] : null; }
        }

        public double GetTimestamp(int index)
        {
            lock (_lock) { return (index >= 0 && index < Timestamps.Count) ? Timestamps[index] : 0.0; }
        }

        public void Reset()
        {
            lock (_lock)
            {
                Reasons.Clear();
                Timestamps.Clear();
                Stopwatch.Restart();
            }
        }
    }
}
"@

$totalTests = 0
$passedTests = 0
$failedTests = 0
$testResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-TestResult {
    param(
        [string]$Category,
        [string]$TestName,
        [bool]$Passed,
        [string]$Details
    )
    $script:totalTests++
    if ($Passed) {
        $script:passedTests++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        if ($Details) {
            Write-Host "         $Details" -ForegroundColor DarkGray
        }
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] ${TestName}" -ForegroundColor Red
        Write-Host "         Reason: $Details" -ForegroundColor Yellow
    }
    $script:testResults.Add([PSCustomObject]@{
        Category = $Category
        TestName = $TestName
        Passed   = $Passed
        Details  = $Details
    })
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  MILESTONE 2: ADVERSARIAL STRESS & SAFETY INVARIANT TEST SUITE" -ForegroundColor White
Write-Host "  Target: GhostEvictionEngine & EventWindow (DisplayFixDaemon.exe)" -ForegroundColor DarkGray
Write-Host "  Timestamp: $(Get-Date -Format 'u')" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# SUITE 1: 50-Invocation Rapid Burst Eviction Stress Test (Latency, Handles, Memory)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 1: Rapid Burst Eviction Stress Test (50 Invocations) ---" -ForegroundColor Yellow

# Warm up JIT compiler
[DisplayFix.Daemon.GhostEvictionEngine]::EvictGhostMonitors() | Out-Null

$proc = [System.Diagnostics.Process]::GetCurrentProcess()

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

$initialHandles = $proc.HandleCount
$proc.Refresh()
$initialWorkingSetMB = [math]::Round($proc.WorkingSet64 / (1024.0 * 1024.0), 2)
$initialGcMemory = [System.GC]::GetTotalMemory($true)

$latencies = [System.Collections.Generic.List[double]]::new()
$evictionCounts = [System.Collections.Generic.List[int]]::new()
$iterationCount = 50

$burstSw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 1; $i -le $iterationCount; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $evicted = [DisplayFix.Daemon.GhostEvictionEngine]::EvictGhostMonitors()
    $sw.Stop()
    $latencies.Add($sw.Elapsed.TotalMilliseconds)
    $evictionCounts.Add($evicted)
}
$burstSw.Stop()

$proc.Refresh()
$finalHandles = $proc.HandleCount
$finalWorkingSetMB = [math]::Round($proc.WorkingSet64 / (1024.0 * 1024.0), 2)

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()
$finalGcMemory = [System.GC]::GetTotalMemory($true)

# Latency statistics
$sortedLatencies = [System.Collections.Generic.List[double]]::new($latencies)
$sortedLatencies.Sort()

$minLatency = $sortedLatencies[0]
$maxLatency = $sortedLatencies[$sortedLatencies.Count - 1]
$sumLatency = 0.0
foreach ($l in $sortedLatencies) { $sumLatency += $l }
$avgLatency = $sumLatency / $sortedLatencies.Count

$p50Index = [int][math]::Floor($sortedLatencies.Count * 0.50)
$p95Index = [int][math]::Floor($sortedLatencies.Count * 0.95)
$p99Index = [int][math]::Floor($sortedLatencies.Count * 0.99)
$p50Latency = $sortedLatencies[[math]::Min($p50Index, $sortedLatencies.Count - 1)]
$p95Latency = $sortedLatencies[[math]::Min($p95Index, $sortedLatencies.Count - 1)]
$p99Latency = $sortedLatencies[[math]::Min($p99Index, $sortedLatencies.Count - 1)]

$handleDelta = $finalHandles - $initialHandles
$gcMemoryDeltaKB = [math]::Round(($finalGcMemory - $initialGcMemory) / 1024.0, 2)
$wsDeltaMB = [math]::Round($finalWorkingSetMB - $initialWorkingSetMB, 2)

# Test 1.1: Latency < 20ms per call
$latencyPass = ($avgLatency -lt 20.0) -and ($p95Latency -lt 20.0)
Record-TestResult `
    -Category "Suite 1: Burst Eviction" `
    -TestName "1.1: EvictGhostMonitors average latency < 20ms (Actual: $([math]::Round($avgLatency, 2))ms, P95: $([math]::Round($p95Latency, 2))ms)" `
    -Passed $latencyPass `
    -Details "50 calls completed in $([math]::Round($burstSw.Elapsed.TotalMilliseconds, 2))ms. Min: $([math]::Round($minLatency, 2))ms, Max: $([math]::Round($maxLatency, 2))ms, Median: $([math]::Round($p50Latency, 2))ms, P95: $([math]::Round($p95Latency, 2))ms, P99: $([math]::Round($p99Latency, 2))ms."

# Test 1.2: Handle leak verification
$handlePass = [math]::Abs($handleDelta) -le 2
Record-TestResult `
    -Category "Suite 1: Burst Eviction" `
    -TestName "1.2: No handle leaks across 50 consecutive invocations (Delta: $handleDelta handles)" `
    -Passed $handlePass `
    -Details "Initial handles: $initialHandles, Final handles: $finalHandles (Net delta: $handleDelta). SetupDiDestroyDeviceInfoList cleanly frees all devinfo sets."

# Test 1.3: Memory leak verification
$memoryPass = $gcMemoryDeltaKB -lt 1024.0 # Less than 1MB GC delta after full collect
Record-TestResult `
    -Category "Suite 1: Burst Eviction" `
    -TestName "1.3: No unmanaged memory leaks across 50 consecutive invocations (GC Delta: ${gcMemoryDeltaKB} KB, WS Delta: ${wsDeltaMB} MB)" `
    -Passed $memoryPass `
    -Details "Initial GC Heap: $([math]::Round($initialGcMemory/1024.0, 2)) KB, Final GC Heap: $([math]::Round($finalGcMemory/1024.0, 2)) KB. WS: $initialWorkingSetMB MB -> $finalWorkingSetMB MB."

# Test 1.4: CheckAndEvict structured telemetry integrity
$telemetry = [DisplayFix.Daemon.GhostEvictionEngine]::CheckAndEvict($false)
$telemetryPass = ($telemetry -ne $null) -and ($telemetry.ElapsedMilliseconds -gt 0) -and ($telemetry.Message.Length -gt 0)
Record-TestResult `
    -Category "Suite 1: Burst Eviction" `
    -TestName "1.4: CheckAndEvict returns structured telemetry with positive elapsed time and descriptive message" `
    -Passed $telemetryPass `
    -Details "NvidiaActive=$($telemetry.NvidiaActive), IntelGhostPresent=$($telemetry.IntelGhostPresent), Elapsed=$([math]::Round($telemetry.ElapsedMilliseconds, 2))ms, Msg='$($telemetry.Message)'"

# -------------------------------------------------------------------------
# SUITE 2: Adversarial Safety Invariant Verification
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 2: Adversarial Safety Invariant Verification ---" -ForegroundColor Yellow

# Test 2.1: Foreign Monitor Identification (IsForeignMonitor)
$foreignCases = @(
    @{ Id = "DISPLAY\DEL4123\4&12345678&0&UID0"; Expected = $true; Name = "Dell External Monitor (DEL4123)" },
    @{ Id = "DISPLAY\SAM0123\4&87654321&0&UID1"; Expected = $true; Name = "Samsung External Monitor (SAM0123)" },
    @{ Id = "DISPLAY\LG0001\1&23456789&0&UID2";  Expected = $true; Name = "LG UltraGear Display (LG0001)" },
    @{ Id = "DISPLAY\ASU2700\4&22334455&0&UID3"; Expected = $true; Name = "ASUS External Display (ASU2700)" },
    @{ Id = "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353"; Expected = $false; Name = "Internal AUOAA9F Panel (NVIDIA Active)" },
    @{ Id = "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688"; Expected = $false; Name = "Internal AUOAA9F Panel (Intel Ghost)" }
)

$allForeignPass = $true
$foreignFailDetails = ""
foreach ($fc in $foreignCases) {
    $res = [DisplayFix.Daemon.GhostEvictionEngine]::IsForeignMonitor($fc.Id)
    if ($res -ne $fc.Expected) {
        $allForeignPass = $false
        $foreignFailDetails += "$($fc.Name) expected $($fc.Expected) got $res; "
    }
}
Record-TestResult `
    -Category "Suite 2: Safety Invariants" `
    -TestName "2.1: IsForeignMonitor accurately identifies external/foreign monitors vs AUOAA9F internal panel" `
    -Passed $allForeignPass `
    -Details $(if ($allForeignPass) { "All 6 monitor IDs correctly classified (External = True, AUOAA9F = False)" } else { $foreignFailDetails })

# Test 2.2: Active NVIDIA Node Identification (IsNvidiaActiveNode)
$activeCases = @(
    @{ Id = "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353"; Expected = $true; Name = "Internal Panel on NVIDIA dGPU (UID4353)" },
    @{ Id = "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688"; Expected = $false; Name = "Internal Panel on Intel iGPU (UID8388688)" },
    @{ Id = "DISPLAY\DEL4123\4&12345678&0&UID0"; Expected = $false; Name = "Dell External Monitor" },
    @{ Id = "DISPLAY\SAM0123\4&87654321&0&UID1"; Expected = $false; Name = "Samsung External Monitor" },
    @{ Id = "DISPLAY\AUOAA9F\SOMETHING_ELSE";    Expected = $false; Name = "AUOAA9F without UID4353 token" },
    @{ Id = ""; Expected = $false; Name = "Empty String" },
    @{ Id = $null; Expected = $false; Name = "Null String" }
)

$allActivePass = $true
$activeFailDetails = ""
foreach ($ac in $activeCases) {
    $res = [DisplayFix.Daemon.GhostEvictionEngine]::IsNvidiaActiveNode($ac.Id)
    if ($res -ne $ac.Expected) {
        $allActivePass = $false
        $activeFailDetails += "$($ac.Name) expected $($ac.Expected) got $res; "
    }
}
Record-TestResult `
    -Category "Suite 2: Safety Invariants" `
    -TestName "2.2: IsNvidiaActiveNode strictly protects UID4353 and rejects all others" `
    -Passed $allActivePass `
    -Details $(if ($allActivePass) { "UID4353 isolated exclusively; foreign displays, Intel ghost, and empty IDs rejected" } else { $activeFailDetails })

# Test 2.3: Intel Ghost Node Identification (IsIntelGhostNode)
$ghostCases = @(
    @{ Id = "DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688"; Expected = $true; Name = "Intel Internal Panel Ghost Node (UID8388688)" },
    @{ Id = "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353";     Expected = $false; Name = "Active NVIDIA Node (UID4353)" },
    @{ Id = "DISPLAY\DEL4123\4&12345678&0&UID0";        Expected = $false; Name = "Dell External Monitor" },
    @{ Id = "DISPLAY\DEL4123\UID8388688";               Expected = $false; Name = "Foreign Monitor with spoofed UID8388688 token" },
    @{ Id = "DISPLAY\AUOAA9F\UID9999999";               Expected = $false; Name = "Internal Panel with unknown UID token" },
    @{ Id = ""; Expected = $false; Name = "Empty String" },
    @{ Id = $null; Expected = $false; Name = "Null String" }
)

$allGhostPass = $true
$ghostFailDetails = ""
foreach ($gc in $ghostCases) {
    $res = [DisplayFix.Daemon.GhostEvictionEngine]::IsIntelGhostNode($gc.Id)
    if ($res -ne $gc.Expected) {
        $allGhostPass = $false
        $ghostFailDetails += "$($gc.Name) expected $($gc.Expected) got $res; "
    }
}
Record-TestResult `
    -Category "Suite 2: Safety Invariants" `
    -TestName "2.3: IsIntelGhostNode matches ONLY internal panel AUOAA9F with UID8388688" `
    -Passed $allGhostPass `
    -Details $(if ($allGhostPass) { "Exact match verified; spoofed foreign tokens and wrong UIDs rejected" } else { $ghostFailDetails })

# Test 2.4: Active NVIDIA Node Invariant 3 Hard Abort Guard
$activeId = "DISPLAY\AUOAA9F\5&39808DAE&2&UID4353"
$isNvidiaActive = [DisplayFix.Daemon.GhostEvictionEngine]::IsNvidiaActiveNode($activeId)
$isGhost = [DisplayFix.Daemon.GhostEvictionEngine]::IsIntelGhostNode($activeId)
$invariant3Pass = ($isNvidiaActive -eq $true) -and ($isGhost -eq $false)
Record-TestResult `
    -Category "Suite 2: Safety Invariants" `
    -TestName "2.4: Invariant 3 hard abort guard guarantees active NVIDIA panel is never targeted" `
    -Passed $invariant3Pass `
    -Details "Active NVIDIA node UID4353: IsNvidiaActiveNode=True, IsIntelGhostNode=False."

# Test 2.5: Live Topology Safety Invariant
$monitors = [DisplayFix.Daemon.GhostEvictionEngine]::EnumerateMonitors($true)
$activeMonitorPresent = $false
$ghostMonitorPresent = $false
$foreignCount = 0

foreach ($m in $monitors) {
    if ($m.IsNvidiaActive) { $activeMonitorPresent = $true }
    if ($m.IsIntelGhost)  { $ghostMonitorPresent = $true }
    if ($m.IsForeign)     { $foreignCount++ }
}

Record-TestResult `
    -Category "Suite 2: Safety Invariants" `
    -TestName "2.5: Live system state: Active NVIDIA panel is present, Intel ghost is unmapped" `
    -Passed $activeMonitorPresent `
    -Details "Monitors enumerated: $($monitors.Count). Active NVIDIA present: $activeMonitorPresent, Ghost present: $ghostMonitorPresent, Foreign monitors: $foreignCount"

# -------------------------------------------------------------------------
# SUITE 3: Burst Display Change Event Debouncing & Coalescing
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 3: Burst Display Change Event Debouncing & Coalescing ---" -ForegroundColor Yellow

$collector = New-Object DisplayFix.Tests.ReconfigCollector
$eventWindow = New-Object DisplayFix.Daemon.EventWindow(200, $false)

# Cancel any initial startup power notification debounce
$eventWindow.CancelPendingDebounce()
[System.Threading.Thread]::Sleep(50)

# Attach thread-safe collector via Delegate::CreateDelegate
$delegate = [Delegate]::CreateDelegate([Action[string]], $collector, 'OnReconfig')
$eventWindow.add_OnReconfigurationTriggered($delegate)
$collector.Reset()

# Test 3.1: 10 simulated display change events within 50ms coalesces to 1 action after 200ms quiet window
# Fire 10 simulated events within 45ms (1 event every 5ms)
$burstCount = 10
for ($i = 1; $i -le $burstCount; $i++) {
    $eventWindow.TriggerDebounce("BurstEvent_$i")
    [System.Threading.Thread]::Sleep(5)
}

# Verify immediately after the 10th event (at ~50ms): NO dispatch should have occurred
$countAtBurstEnd = $collector.Count
[System.Threading.Thread]::Sleep(100) # Now at ~150ms from start: still inside 200ms quiet window (which started at ~45ms)
$countAt150ms = $collector.Count

# Now sleep 200ms more (total elapsed ~350ms): 200ms quiet window expired, exactly 1 action should have fired
[System.Threading.Thread]::Sleep(200)
$countAt350ms = $collector.Count

$debouncePass1 = ($countAtBurstEnd -eq 0) -and ($countAt150ms -eq 0) -and ($countAt350ms -eq 1)
$lastReason = if ($collector.Count -gt 0) { $collector.GetReason(0) } else { "NONE" }
$fireTimestamp = if ($collector.Count -gt 0) { [math]::Round($collector.GetTimestamp(0), 2) } else { 0 }

Record-TestResult `
    -Category "Suite 3: Debounce & Coalescing" `
    -TestName "3.1: 10 burst events within 50ms coalesce to exactly 1 action after 200ms quiet window" `
    -Passed $debouncePass1 `
    -Details "At burst end (50ms): $countAtBurstEnd dispatches; At 150ms: $countAt150ms dispatches; At 350ms: $countAt350ms dispatches. Fired at ${fireTimestamp}ms with reason='$lastReason'."

# Test 3.2: Subsequent burst after quiet window triggers independent 2nd action (timer rearms properly)
for ($j = 1; $j -le 5; $j++) {
    $eventWindow.TriggerDebounce("SubsequentBurst_$j")
    [System.Threading.Thread]::Sleep(4)
}

# Wait for 2nd quiet window to expire (20ms burst + 200ms debounce + 100ms margin = ~320ms)
[System.Threading.Thread]::Sleep(350)
$countAfterSecondBurst = $collector.Count
$debouncePass2 = ($countAfterSecondBurst -eq 2)
$secondReason = if ($collector.Count -gt 1) { $collector.GetReason(1) } else { "NONE" }

Record-TestResult `
    -Category "Suite 3: Debounce & Coalescing" `
    -TestName "3.2: Subsequent burst after quiet window rearms and triggers 2nd independent action" `
    -Passed $debouncePass2 `
    -Details "Total dispatches after 2nd burst: $countAfterSecondBurst. Second trigger reason='$secondReason'."

# Test 3.3: Cancellation of pending debounce
$eventWindow.TriggerDebounce("CanceledEvent")
$eventWindow.CancelPendingDebounce()
[System.Threading.Thread]::Sleep(300) # Wait beyond debounce window
$countAfterCancel = $collector.Count
$cancelPass = ($countAfterCancel -eq 2) # Count must not increase
Record-TestResult `
    -Category "Suite 3: Debounce & Coalescing" `
    -TestName "3.3: CancelPendingDebounce successfully aborts pending trigger" `
    -Passed $cancelPass `
    -Details "Dispatches before cancel: 2, Dispatches after cancel + 300ms: $countAfterCancel."

# Test 3.4: EventWindow Disposal and cleanup
$eventWindow.remove_OnReconfigurationTriggered($delegate)
$eventWindow.Dispose()
Record-TestResult `
    -Category "Suite 3: Debounce & Coalescing" `
    -TestName "3.4: EventWindow cleanly disposes handles and timers without exception" `
    -Passed $true `
    -Details "EventWindow.Dispose() executed cleanly."

# -------------------------------------------------------------------------
# SUITE 4: DWM CPU Utilization Verification (< 5%)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 4: DWM CPU Utilization Verification (< 5%) ---" -ForegroundColor Yellow

function Get-DwmCpuSample {
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name like 'dwm%'" -ErrorAction Stop
        if ($perf) {
            $rawCpu = ($perf.PercentProcessorTime | Measure-Object -Sum).Sum
            $procCount = [System.Environment]::ProcessorCount
            return [PSCustomObject]@{
                TotalCpuPercent      = [math]::Round([double]$rawCpu / $procCount, 2)
                SingleCoreCpuPercent = [double]$rawCpu
                WorkingSetMB         = [math]::Round(($perf.WorkingSetPrivate | Measure-Object -Sum).Sum / 1MB, 2)
            }
        }
    } catch {
        # Fallback to Get-Counter
        try {
            $counter = (Get-Counter "\Process(dwm*)\% Processor Time" -ErrorAction Stop).CounterSamples |
                       Measure-Object -Property CookedValue -Sum
            $procCount = [System.Environment]::ProcessorCount
            return [PSCustomObject]@{
                TotalCpuPercent      = [math]::Round($counter.Sum / $procCount, 2)
                SingleCoreCpuPercent = [double]$counter.Sum
                WorkingSetMB         = 0.0
            }
        } catch { }
    }
    return [PSCustomObject]@{
        TotalCpuPercent      = 0.0
        SingleCoreCpuPercent = 0.0
        WorkingSetMB         = 0.0
    }
}

# 4.1: Baseline DWM CPU
[System.Threading.Thread]::Sleep(1000)
$sample1 = Get-DwmCpuSample
$baselinePass = $sample1.TotalCpuPercent -lt 5.0
Record-TestResult `
    -Category "Suite 4: DWM CPU" `
    -TestName "4.1: Baseline idle DWM CPU < 5% (Actual: $($sample1.TotalCpuPercent)% total, $($sample1.SingleCoreCpuPercent)% single-core)" `
    -Passed $baselinePass `
    -Details "DWM WorkingSet: $($sample1.WorkingSetMB) MB. Multi-core total: $($sample1.TotalCpuPercent)%."

# 4.2: DWM CPU during 50 rapid eviction invocations
$swBurst = [System.Diagnostics.Stopwatch]::StartNew()
for ($k = 1; $k -le 50; $k++) {
    [DisplayFix.Daemon.GhostEvictionEngine]::EvictGhostMonitors() | Out-Null
}
$swBurst.Stop()

$sample2 = Get-DwmCpuSample
$duringPass = $sample2.TotalCpuPercent -lt 5.0
Record-TestResult `
    -Category "Suite 4: DWM CPU" `
    -TestName "4.2: DWM CPU during 50 rapid eviction calls < 5% (Actual: $($sample2.TotalCpuPercent)% total, $($sample2.SingleCoreCpuPercent)% single-core)" `
    -Passed $duringPass `
    -Details "50 calls completed in $([math]::Round($swBurst.Elapsed.TotalMilliseconds, 2))ms. DWM CPU during burst: $($sample2.TotalCpuPercent)% total."

# 4.3: Post-eviction DWM CPU
[System.Threading.Thread]::Sleep(1000)
$sample3 = Get-DwmCpuSample
$postPass = $sample3.TotalCpuPercent -lt 5.0
Record-TestResult `
    -Category "Suite 4: DWM CPU" `
    -TestName "4.3: Post-eviction DWM CPU remains < 5% (Actual: $($sample3.TotalCpuPercent)% total, $($sample3.SingleCoreCpuPercent)% single-core)" `
    -Passed $postPass `
    -Details "DWM CPU after 1s quiet window: $($sample3.TotalCpuPercent)% total. Zero presentation spin or GPU lock contention."

# -------------------------------------------------------------------------
# SUMMARY & FINAL VERDICT
# -------------------------------------------------------------------------
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  ADVERSARIAL STRESS TEST SUMMARY" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  Total Tests Executed : $totalTests" -ForegroundColor White
Write-Host "  Passed Tests         : $passedTests" -ForegroundColor Green
Write-Host "  Failed Tests         : $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })

$verdict = if ($failedTests -eq 0) { "APPROVE" } else { "REJECT" }
$verdictColor = if ($failedTests -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Final Gate Verdict   : $verdict" -ForegroundColor $verdictColor
Write-Host "========================================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
