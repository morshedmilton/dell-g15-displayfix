# tests/e2e/tier5_adversarial/adversarial_m3_refresh_dpi_test.ps1
# Tier 5 Adversarial Stress & Invariant Test Suite for Milestone 3
# 360Hz Refresh Rate Lock (F07), Multi-Topology Registry DPI Sync (F08),
# Dynamic CCD 125% DPI Enforcement (F09), & Unified 3-Stage Reconfiguration Pipeline

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

# Load the compiled assembly for in-process reflection, struct layout, and API testing
$assembly = [System.Reflection.Assembly]::LoadFrom($daemonExePath)
[DisplayFix.Common.Logger]::EchoToConsole = $false

# Helper C# harness for multi-threaded pipeline concurrency testing
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading.Tasks;

namespace DisplayFix.AdversarialTests
{
    public static class ParallelPipelineRunner
    {
        public static List<object> RunParallel(Type eventWindowType, int threadCount)
        {
            MethodInfo mi = eventWindowType.GetMethod("ExecuteReconfigurationPipeline", BindingFlags.Public | BindingFlags.Static);
            Task<object>[] tasks = new Task<object>[threadCount];
            for (int i = 0; i < threadCount; i++)
            {
                int idx = i + 1;
                tasks[i] = Task.Run(() => mi.Invoke(null, new object[] { "ParallelThread_" + idx }));
            }
            Task.WaitAll(tasks);
            List<object> results = new List<object>(threadCount);
            for (int i = 0; i < threadCount; i++)
            {
                results.Add(tasks[i].Result);
            }
            return results;
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
Write-Host "  MILESTONE 3: ADVERSARIAL REFRESH RATE & DPI SCALING TEST SUITE" -ForegroundColor White
Write-Host "  Target: RefreshRateLock, ScalingSynchronizer, EventWindow, Interop" -ForegroundColor DarkGray
Write-Host "  Timestamp: $(Get-Date -Format 'u')" -ForegroundColor DarkGray
Write-Host "========================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# SUITE 1: Struct Marshaling Byte Sizes & Field Offsets (x64 ABI Invariants)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 1: Struct Marshaling Byte Sizes & Field Offsets ---" -ForegroundColor Yellow

$interopType = $assembly.GetType('DisplayFix.Daemon.Interop')

function Get-NestedType {
    param([string]$Name)
    return $interopType.GetNestedType($Name)
}

function Get-StructSize {
    param([Type]$Type)
    return [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Type)
}

function Get-FieldOffset {
    param([Type]$Type, [string]$FieldName)
    return [System.Runtime.InteropServices.Marshal]::OffsetOf([Type]$Type, [string]$FieldName).ToInt32()
}

# Test 1.1: Core CCD Path & Mode Struct Byte Sizes
$tPathInfo      = Get-NestedType 'DISPLAYCONFIG_PATH_INFO'
$tPathSource    = Get-NestedType 'DISPLAYCONFIG_PATH_SOURCE_INFO'
$tPathTarget    = Get-NestedType 'DISPLAYCONFIG_PATH_TARGET_INFO'
$tModeInfo      = Get-NestedType 'DISPLAYCONFIG_MODE_INFO'
$tVideoSignal   = Get-NestedType 'DISPLAYCONFIG_VIDEO_SIGNAL_INFO'
$tHeader        = Get-NestedType 'DISPLAYCONFIG_DEVICE_INFO_HEADER'
$tDpiGet        = Get-NestedType 'DISPLAYCONFIG_SOURCE_DPI_SCALE_GET'
$tDpiSet        = Get-NestedType 'DISPLAYCONFIG_SOURCE_DPI_SCALE_SET'
$tSourceName    = Get-NestedType 'DISPLAYCONFIG_SOURCE_DEVICE_NAME'
$tTargetName    = Get-NestedType 'DISPLAYCONFIG_TARGET_DEVICE_NAME'
$tAdapterName   = Get-NestedType 'DISPLAYCONFIG_ADAPTER_NAME'
$tDevModeW      = Get-NestedType 'DEVMODEW'

$szPathInfo    = Get-StructSize $tPathInfo
$szPathSource  = Get-StructSize $tPathSource
$szPathTarget  = Get-StructSize $tPathTarget
$szModeInfo    = Get-StructSize $tModeInfo
$szVideoSignal = Get-StructSize $tVideoSignal
$szHeader      = Get-StructSize $tHeader
$szDpiGet      = Get-StructSize $tDpiGet
$szDpiSet      = Get-StructSize $tDpiSet
$szSourceName  = Get-StructSize $tSourceName
$szTargetName  = Get-StructSize $tTargetName
$szAdapterName = Get-StructSize $tAdapterName
$szDevModeW    = Get-StructSize $tDevModeW

$sizesPass = (
    $szPathInfo -eq 72 -and
    $szPathSource -eq 20 -and
    $szPathTarget -eq 48 -and
    $szModeInfo -eq 64 -and
    $szVideoSignal -eq 48 -and
    $szHeader -eq 20 -and
    $szDpiGet -eq 32 -and
    $szDpiSet -eq 24 -and
    $szSourceName -eq 84 -and
    $szTargetName -eq 420 -and
    $szAdapterName -eq 276 -and
    $szDevModeW -eq 220
)

Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.1: All 12 CCD & DEVMODEW struct byte sizes match exact Win32 x64 ABI layout" `
    -Passed $sizesPass `
    -Details "PATH_INFO=$szPathInfo(72), SOURCE_INFO=$szPathSource(20), TARGET_INFO=$szPathTarget(48), MODE_INFO=$szModeInfo(64), VIDEO_SIGNAL=$szVideoSignal(48), HEADER=$szHeader(20), DPI_GET=$szDpiGet(32), DPI_SET=$szDpiSet(24), SOURCE_NAME=$szSourceName(84), TARGET_NAME=$szTargetName(420), ADAPTER_NAME=$szAdapterName(276), DEVMODEW=$szDevModeW(220)"

# Test 1.2: DISPLAYCONFIG_PATH_INFO and DISPLAYCONFIG_PATH_TARGET_INFO Field Offsets
$offPathSource  = Get-FieldOffset $tPathInfo 'sourceInfo'
$offPathTarget  = Get-FieldOffset $tPathInfo 'targetInfo'
$offPathFlags   = Get-FieldOffset $tPathInfo 'flags'
$offTargetRate  = Get-FieldOffset $tPathTarget 'refreshRate'
$offTargetMode  = Get-FieldOffset $tPathTarget 'modeInfoIdx'
$offTargetAvail = Get-FieldOffset $tPathTarget 'targetAvailable'

$pathOffsetsPass = (
    $offPathSource -eq 0 -and
    $offPathTarget -eq 20 -and
    $offPathFlags -eq 68 -and
    $offTargetMode -eq 12 -and
    $offTargetRate -eq 28 -and
    $offTargetAvail -eq 40
)

Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.2: DISPLAYCONFIG_PATH_INFO & TARGET_INFO field offsets align with Windows CCD binary layout" `
    -Passed $pathOffsetsPass `
    -Details "sourceInfo@$offPathSource(0), targetInfo@$offPathTarget(20), flags@$offPathFlags(68), target.modeInfoIdx@$offTargetMode(12), target.refreshRate@$offTargetRate(28), target.targetAvailable@$offTargetAvail(40)"

# Test 1.3: DISPLAYCONFIG_MODE_INFO and DISPLAYCONFIG_VIDEO_SIGNAL_INFO Field Offsets
$offModeType    = Get-FieldOffset $tModeInfo 'infoType'
$offModeId      = Get-FieldOffset $tModeInfo 'id'
$offModeLuid    = Get-FieldOffset $tModeInfo 'adapterId'
$offModeUnion   = Get-FieldOffset $tModeInfo 'modeInfo'
$offSigPixel    = Get-FieldOffset $tVideoSignal 'pixelRate'
$offSigHSync    = Get-FieldOffset $tVideoSignal 'hSyncFreq'
$offSigVSync    = Get-FieldOffset $tVideoSignal 'vSyncFreq'
$offSigActive   = Get-FieldOffset $tVideoSignal 'activeSize'
$offSigTotal    = Get-FieldOffset $tVideoSignal 'totalSize'

$modeOffsetsPass = (
    $offModeType -eq 0 -and
    $offModeId -eq 4 -and
    $offModeLuid -eq 8 -and
    $offModeUnion -eq 16 -and
    $offSigPixel -eq 0 -and
    $offSigHSync -eq 8 -and
    $offSigVSync -eq 16 -and
    $offSigActive -eq 24 -and
    $offSigTotal -eq 32
)

Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.3: DISPLAYCONFIG_MODE_INFO & VIDEO_SIGNAL_INFO field offsets align with 8-byte union boundary" `
    -Passed $modeOffsetsPass `
    -Details "infoType@$offModeType(0), id@$offModeId(4), adapterId@$offModeLuid(8), modeInfo@$offModeUnion(16); pixelRate@$offSigPixel(0), hSyncFreq@$offSigHSync(8), vSyncFreq@$offSigVSync(16), activeSize@$offSigActive(24), totalSize@$offSigTotal(32)"

# Test 1.4: DPI Scale Request Packets & DEVMODEW Field Offsets
$offHdrType     = Get-FieldOffset $tHeader 'type'
$offHdrSize     = Get-FieldOffset $tHeader 'size'
$offHdrLuid     = Get-FieldOffset $tHeader 'adapterId'
$offHdrId       = Get-FieldOffset $tHeader 'id'
$offGetMin      = Get-FieldOffset $tDpiGet 'minScaleRel'
$offGetCur      = Get-FieldOffset $tDpiGet 'curScaleRel'
$offGetMax      = Get-FieldOffset $tDpiGet 'maxScaleRel'
$offSetRel      = Get-FieldOffset $tDpiSet 'scaleRel'
$offDmSize      = Get-FieldOffset $tDevModeW 'dmSize'
$offDmFields    = Get-FieldOffset $tDevModeW 'dmFields'
$offDmPelsW     = Get-FieldOffset $tDevModeW 'dmPelsWidth'
$offDmPelsH     = Get-FieldOffset $tDevModeW 'dmPelsHeight'
$offDmFreq      = Get-FieldOffset $tDevModeW 'dmDisplayFrequency'

$dpiOffsetsPass = (
    $offHdrType -eq 0 -and
    $offHdrSize -eq 4 -and
    $offHdrLuid -eq 8 -and
    $offHdrId -eq 16 -and
    $offGetMin -eq 20 -and
    $offGetCur -eq 24 -and
    $offGetMax -eq 28 -and
    $offSetRel -eq 20 -and
    $offDmSize -eq 68 -and
    $offDmFields -eq 72 -and
    $offDmPelsW -eq 172 -and
    $offDmPelsH -eq 176 -and
    $offDmFreq -eq 184
)

Record-TestResult `
    -Category "Suite 1: Struct Marshaling" `
    -TestName "1.4: DPI_SCALE_GET (-3), DPI_SCALE_SET (-4), and DEVMODEW field offsets match exact Win32 ABI" `
    -Passed $dpiOffsetsPass `
    -Details "Header(0,4,8,16), DPI_GET(min@$offGetMin, cur@$offGetCur, max@$offGetMax), DPI_SET(scaleRel@$offSetRel), DEVMODEW(dmSize@$offDmSize, dmFields@$offDmFields, Width@$offDmPelsW, Height@$offDmPelsH, Freq@$offDmFreq)"

# -------------------------------------------------------------------------
# SUITE 2: Adversarial Registry Corruption Recovery & Foreign Monitor Isolation
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 2: Registry Corruption Recovery & Foreign Monitor Isolation ---" -ForegroundColor Yellow

$pmRegPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
$desktopRegPath = "HKCU:\Control Panel\Desktop"
if (-not (Test-Path $pmRegPath)) {
    New-Item -Path $pmRegPath -Force | Out-Null
}

$advInternalKey1 = Join-Path $pmRegPath "AUOAA9F0_ADVERSARIAL_8086_A78B_TEST_CORRUPT_NEG1"
$advInternalKey2 = Join-Path $pmRegPath "AUOAA9F0_ADVERSARIAL_10DE_28E0_TEST_CORRUPT_99"
$advForeignKey1  = Join-Path $pmRegPath "DEL1234_TEST_FOREIGN_MONITOR"
$advForeignKey2  = Join-Path $pmRegPath "GSM5B7F_TEST_LG_EXTERNAL"

$origLogPixels = (Get-ItemProperty -Path $desktopRegPath -Name "LogPixels" -ErrorAction SilentlyContinue).LogPixels

try {
    # Create temporary adversarial keys:
    # 1. Internal panel key with -1 (0xFFFFFFFF / 100% desync)
    New-Item -Path $advInternalKey1 -Force | Out-Null
    Set-ItemProperty -Path $advInternalKey1 -Name "DpiValue" -Value ([uint32]::MaxValue) -Type DWord

    # 2. Internal panel key with 99 (out-of-bounds corruption)
    New-Item -Path $advInternalKey2 -Force | Out-Null
    Set-ItemProperty -Path $advInternalKey2 -Name "DpiValue" -Value 99 -Type DWord

    # 3. Foreign monitor keys with custom DpiValue (-1 and 2) that MUST NOT be touched
    New-Item -Path $advForeignKey1 -Force | Out-Null
    Set-ItemProperty -Path $advForeignKey1 -Name "DpiValue" -Value ([uint32]::MaxValue) -Type DWord

    New-Item -Path $advForeignKey2 -Force | Out-Null
    Set-ItemProperty -Path $advForeignKey2 -Name "DpiValue" -Value 2 -Type DWord

    # Also corrupt existing real *AUOAA9F* key (if present) temporarily to -1 (0xFFFFFFFF), saving original value
    $existingAuoKeys = @(Get-ChildItem -Path $pmRegPath -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match 'AUOAA9F' -and $_.PSChildName -notmatch 'ADVERSARIAL'
    })
    $savedExistingValues = @{}
    foreach ($k in $existingAuoKeys) {
        $val = (Get-ItemProperty -Path $k.PSPath -Name "DpiValue" -ErrorAction SilentlyContinue).DpiValue
        $savedExistingValues[$k.PSPath] = $val
        Set-ItemProperty -Path $k.PSPath -Name "DpiValue" -Value ([uint32]::MaxValue) -Type DWord
    }

    # Corrupt LogPixels to 96 (100% scale)
    Set-ItemProperty -Path $desktopRegPath -Name "LogPixels" -Value 96 -Type DWord

    # Invoke DisplayFixDaemon.exe --sync-dpi via CLI
    $swCli = [System.Diagnostics.Stopwatch]::StartNew()
    $cliOut = & $daemonExePath --sync-dpi | Out-String
    $cliExit = $LASTEXITCODE
    $swCli.Stop()

    # Check restoration of internal keys
    $valInternal1 = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
        (Get-ItemProperty -Path $advInternalKey1 -Name "DpiValue").DpiValue, -999)
    $valInternal2 = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
        (Get-ItemProperty -Path $advInternalKey2 -Name "DpiValue").DpiValue, -999)

    $allRealRestored = $true
    foreach ($k in $existingAuoKeys) {
        $rv = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
            (Get-ItemProperty -Path $k.PSPath -Name "DpiValue").DpiValue, -999)
        if ($rv -ne 0) { $allRealRestored = $false }
    }

    $restoredLogPixels = (Get-ItemProperty -Path $desktopRegPath -Name "LogPixels").LogPixels

    # Check value kind is REG_DWORD
    $regKeyObj = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Control Panel\Desktop\PerMonitorSettings\AUOAA9F0_ADVERSARIAL_8086_A78B_TEST_CORRUPT_NEG1", $false)
    $valueKind = $regKeyObj.GetValueKind("DpiValue")
    $regKeyObj.Close()

    # Check foreign keys remained completely untouched
    $valForeign1 = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
        (Get-ItemProperty -Path $advForeignKey1 -Name "DpiValue").DpiValue, 0)
    $valForeign2 = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
        (Get-ItemProperty -Path $advForeignKey2 -Name "DpiValue").DpiValue, 0)

    # Test 2.1: Corrupted -1 (0xFFFFFFFF) and 99 on *AUOAA9F* keys immediately restored to 0 (REG_DWORD)
    $corruptRecoverPass = (
        $cliExit -eq 0 -and
        $valInternal1 -eq 0 -and
        $valInternal2 -eq 0 -and
        $allRealRestored -and
        $valueKind -eq [Microsoft.Win32.RegistryValueKind]::DWord
    )
    Record-TestResult `
        -Category "Suite 2: Registry Recovery" `
        -TestName "2.1: DisplayFixDaemon.exe --sync-dpi restores corrupted -1 (0xFFFFFFFF) and 99 on *AUOAA9F* keys to 0 (DWORD)" `
        -Passed $corruptRecoverPass `
        -Details "CLI Exit=$cliExit ($([math]::Round($swCli.Elapsed.TotalMilliseconds, 2))ms), Internal(-1)->$valInternal1, Internal(99)->$valInternal2, RealKeysRestored=$allRealRestored ($($existingAuoKeys.Count) keys), ValueKind=$valueKind"

    # Test 2.2: Corrupted LogPixels (96) restored to 120 (125% system DPI base)
    $logPixelsPass = ($restoredLogPixels -eq 120)
    Record-TestResult `
        -Category "Suite 2: Registry Recovery" `
        -TestName "2.2: DisplayFixDaemon.exe --sync-dpi restores corrupted LogPixels=96 back to 120 (125% system DPI)" `
        -Passed $logPixelsPass `
        -Details "Injected LogPixels=96 -> Restored LogPixels=$restoredLogPixels"

    # Test 2.3: Foreign monitor keys (DEL1234_TEST, GSM5B7F_TEST) remain untouched
    $foreignUntouchedPass = ($valForeign1 -eq -1 -and $valForeign2 -eq 2)
    Record-TestResult `
        -Category "Suite 2: Registry Recovery" `
        -TestName "2.3: Foreign monitor PerMonitorSettings keys (DEL1234_TEST, GSM5B7F_TEST) remain strictly untouched" `
        -Passed $foreignUntouchedPass `
        -Details "DEL1234_TEST DpiValue=$valForeign1 (expected -1), GSM5B7F_TEST DpiValue=$valForeign2 (expected 2)"

    # Test 2.4: Missing DpiValue value on *AUOAA9F* key is created and set to 0
    Remove-ItemProperty -Path $advInternalKey1 -Name "DpiValue" -ErrorAction SilentlyContinue
    $syncRes = [DisplayFix.Daemon.ScalingSynchronizer]::CheckAndEnforce($false)
    $valAfterMissing = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32(
        (Get-ItemProperty -Path $advInternalKey1 -Name "DpiValue").DpiValue, -999)
    $missingRecoverPass = ($syncRes.Success -and $valAfterMissing -eq 0)
    Record-TestResult `
        -Category "Suite 2: Registry Recovery" `
        -TestName "2.4: Missing DpiValue property on *AUOAA9F* topology key is automatically created as DWORD 0" `
        -Passed $missingRecoverPass `
        -Details "Removed DpiValue -> CheckAndEnforce() -> DpiValue=$valAfterMissing, TopologiesUpdated=$($syncRes.TopologiesUpdated)"

    # Test 2.5: ParseRegistryDwordToSignedInt32 handles boxed int, uint, long, string, and null edge cases
    $pNeg1Int  = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32([int]-1, -999)
    $pNeg1UInt = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32([uint32]4294967295, -999)
    $pNeg1Long = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32([long]4294967295, -999)
    $pZero     = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32([int]0, -999)
    $pNull     = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32($null, -777)
    $pBadStr   = [DisplayFix.Daemon.ScalingSynchronizer]::ParseRegistryDwordToSignedInt32("NOT_A_NUMBER", -555)

    $parseEdgePass = (
        $pNeg1Int -eq -1 -and
        $pNeg1UInt -eq -1 -and
        $pNeg1Long -eq -1 -and
        $pZero -eq 0 -and
        $pNull -eq -777 -and
        $pBadStr -eq -555
    )
    Record-TestResult `
        -Category "Suite 2: Registry Recovery" `
        -TestName "2.5: ParseRegistryDwordToSignedInt32 safely handles int, uint32(0xFFFFFFFF), int64, null, and malformed strings" `
        -Passed $parseEdgePass `
        -Details "int(-1)->$pNeg1Int, uint(0xFFFFFFFF)->$pNeg1UInt, long(0xFFFFFFFF)->$pNeg1Long, 0->$pZero, null->$pNull, malformed->$pBadStr"
}
finally {
    # Clean up temporary adversarial registry keys
    if (Test-Path $advInternalKey1) { Remove-Item -Path $advInternalKey1 -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $advInternalKey2) { Remove-Item -Path $advInternalKey2 -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $advForeignKey1)  { Remove-Item -Path $advForeignKey1  -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $advForeignKey2)  { Remove-Item -Path $advForeignKey2  -Recurse -Force -ErrorAction SilentlyContinue }
    Set-ItemProperty -Path $desktopRegPath -Name "LogPixels" -Value 120 -Type DWord -ErrorAction SilentlyContinue
    [DisplayFix.Daemon.ScalingSynchronizer]::Enforce125($false) | Out-Null
}

# -------------------------------------------------------------------------
# SUITE 3: CCD Dynamic 125% DPI Scale Verification (curScaleRel == 0)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 3: CCD Dynamic 125% DPI Scale Verification ---" -ForegroundColor Yellow

# Test 3.1: Live CCD DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE (-3) reports curScaleRel == 0 (125%)
$syncCcdRes = [DisplayFix.Daemon.ScalingSynchronizer]::CheckAndEnforce($true)
$scalePct = [DisplayFix.Daemon.ScalingSynchronizer]::GetCurrentScalingPercent()
$ccdScalePass = (
    $syncCcdRes.Success -eq $true -and
    $syncCcdRes.CcdEnforced -eq $true -and
    $syncCcdRes.ActivePathsChecked -ge 1 -and
    $syncCcdRes.CurrentScaleRel -eq 0 -and
    $syncCcdRes.LastWin32Error -eq 0 -and
    $scalePct -eq 125
)
Record-TestResult `
    -Category "Suite 3: CCD DPI Scale" `
    -TestName "3.1: Live CCD DPI scale verification confirms curScaleRel == 0 (125% Recommended) with Win32 rc=0" `
    -Passed $ccdScalePass `
    -Details "ActivePaths=$($syncCcdRes.ActivePathsChecked), curScaleRel=$($syncCcdRes.CurrentScaleRel) (min=$($syncCcdRes.MinScaleRel), max=$($syncCcdRes.MaxScaleRel)), ScalePercent=${scalePct}%, Elapsed=$([math]::Round($syncCcdRes.ElapsedMilliseconds, 2))ms"

# Test 3.2: MapRelativeStepToPercent boundary mapping across all relative offsets
$m0    = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(0, -1)
$mNeg1 = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(-1, -1)
$mPos1 = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(1, -1)
$mPos2 = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(2, -1)
$mPos3 = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(3, -1)
$mOob  = [DisplayFix.Daemon.ScalingSynchronizer]::MapRelativeStepToPercent(-99, -1)

$mapPass = ($m0 -eq 125 -and $mNeg1 -eq 100 -and $mPos1 -eq 150 -and $mPos2 -eq 175 -and $mPos3 -eq 200 -and $mOob -eq 125)
Record-TestResult `
    -Category "Suite 3: CCD DPI Scale" `
    -TestName "3.2: MapRelativeStepToPercent accurately maps relative steps (-1..+3) and falls back to 125% on OOB" `
    -Passed $mapPass `
    -Details "step(0)->${m0}%, step(-1)->${mNeg1}%, step(+1)->${mPos1}%, step(+2)->${mPos2}%, step(+3)->${mPos3}%, step(-99)->${mOob}%"

# -------------------------------------------------------------------------
# SUITE 4: 360Hz Refresh Rate Lock Verification (360152/1000 Rational & Latency)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 4: 360Hz Refresh Rate Lock Verification ---" -ForegroundColor Yellow

# Warm up JIT
[DisplayFix.Daemon.RefreshRateLock]::CheckAndEnforce($null, $false) | Out-Null

# Test 4.1: Exact hardware rational 360152 / 1000 (360.152Hz) verified on active internal panel path
$activePaths = [DisplayFix.Daemon.RefreshRateLock]::QueryActiveDisplayPaths()
$internalPath = $activePaths | Where-Object { $_.IsInternalPanel } | Select-Object -First 1
if ($null -eq $internalPath -and $activePaths.Count -gt 0) {
    $internalPath = $activePaths[0]
}

$exactHz = [DisplayFix.Daemon.RefreshRateLock]::GetCurrentRefreshRateExactHz()
$nominalHz = [DisplayFix.Daemon.RefreshRateLock]::GetCurrentRefreshRateHz()

$rationalPass = (
    $null -ne $internalPath -and
    $internalPath.Numerator -eq 360152 -and
    $internalPath.Denominator -eq 1000 -and
    [math]::Abs($internalPath.FrequencyHz - 360.152) -lt 0.001 -and
    $nominalHz -eq 360
)
Record-TestResult `
    -Category "Suite 4: 360Hz Lock" `
    -TestName "4.1: Active AUOAA9F panel path reports exact rational 360152/1000 (360.152 Hz)" `
    -Passed $rationalPass `
    -Details "GDI='$($internalPath.GdiDeviceName)', Monitor='$($internalPath.MonitorDevicePath)', Rational=$($internalPath.Numerator)/$($internalPath.Denominator) ($($internalPath.FrequencyHz) Hz), Nominal=${nominalHz}Hz"

# Test 4.2: In-process steady-state CheckAndEnforce latency < 50ms
$swInProc = [System.Diagnostics.Stopwatch]::StartNew()
$lockRes = [DisplayFix.Daemon.RefreshRateLock]::CheckAndEnforce($null, $false)
$swInProc.Stop()

$inProcPass = (
    $lockRes.InternalPanelFound -eq $true -and
    ($lockRes.WasAlready360Hz -or $lockRes.EnforcementSucceeded) -and
    $lockRes.FinalNumerator -eq 360152 -and
    $lockRes.FinalDenominator -eq 1000 -and
    $swInProc.Elapsed.TotalMilliseconds -lt 50.0
)
Record-TestResult `
    -Category "Suite 4: 360Hz Lock" `
    -TestName "4.2: In-process RefreshRateLock.CheckAndEnforce steady-state latency < 50ms (Actual: $([math]::Round($swInProc.Elapsed.TotalMilliseconds, 2))ms)" `
    -Passed $inProcPass `
    -Details "WasAlready360Hz=$($lockRes.WasAlready360Hz), Final=$($lockRes.FinalNumerator)/$($lockRes.FinalDenominator), Msg='$($lockRes.Message)'"

# Test 4.3: Forced CheckAndEnforce (force=true) multi-tier fallback (CCD 0x000006A0 -> 0x000004A0 -> DEVMODEW)
$swForced = [System.Diagnostics.Stopwatch]::StartNew()
$forcedRes = [DisplayFix.Daemon.RefreshRateLock]::CheckAndEnforce($null, $true)
$swForced.Stop()

$forcedPass = (
    $forcedRes.EnforcementAttempted -eq $true -and
    $forcedRes.EnforcementSucceeded -eq $true -and
    ($forcedRes.CcdReturnCode -eq 0 -or ($forcedRes.CcdReturnCode -eq 5 -and $forcedRes.UsedDevModeFallback -eq $true)) -and
    $forcedRes.FinalNumerator -eq 360152 -and
    $forcedRes.FinalDenominator -eq 1000
)
Record-TestResult `
    -Category "Suite 4: 360Hz Lock" `
    -TestName "4.3: Forced CheckAndEnforce(force=true) succeeds via CCD or DEVMODEW fallback and locks 360152/1000" `
    -Passed $forcedPass `
    -Details "CcdReturnCode=$($forcedRes.CcdReturnCode), UsedFallback=$($forcedRes.UsedDevModeFallback), FallbackRet=$($forcedRes.FallbackReturnCode), Elapsed=$([math]::Round($swForced.Elapsed.TotalMilliseconds, 2))ms, Msg='$($forcedRes.Message)'"

# Test 4.4: CLI --lock-360hz internal execution latency < 50ms and exit code 0
$lockCliOut = & $daemonExePath --lock-360hz | Out-String
$lockCliExit = $LASTEXITCODE
$reportedMs = 999.0
if ($lockCliOut -match 'complete in ([0-9.]+)ms') {
    $reportedMs = [double]$Matches[1]
}
$cliLockPass = ($lockCliExit -eq 0 -and $reportedMs -lt 50.0 -and $lockCliOut -match '360Hz')
Record-TestResult `
    -Category "Suite 4: 360Hz Lock" `
    -TestName "4.4: CLI DisplayFixDaemon.exe --lock-360hz completes in < 50ms internal latency (Actual: ${reportedMs}ms)" `
    -Passed $cliLockPass `
    -Details "ExitCode=$lockCliExit, ReportedElapsed=${reportedMs}ms"

# Test 4.5: ShouldRestore360Hz threshold & non-existent target filter stand-down
$r60   = [DisplayFix.Daemon.RefreshRateLock]::ShouldRestore360Hz(60.0)
$r299  = [DisplayFix.Daemon.RefreshRateLock]::ShouldRestore360Hz(299.9)
$r300  = [DisplayFix.Daemon.RefreshRateLock]::ShouldRestore360Hz(300.0)
$r360  = [DisplayFix.Daemon.RefreshRateLock]::ShouldRestore360Hz(360.152)
$rZero = [DisplayFix.Daemon.RefreshRateLock]::ShouldRestore360Hz(0.0)
$nonExistRes = [DisplayFix.Daemon.RefreshRateLock]::CheckAndEnforce("NON_EXISTENT_PANEL_XYZ999", $false)

$edgeRatePass = (
    $r60 -eq $true -and
    $r299 -eq $true -and
    $r300 -eq $false -and
    $r360 -eq $false -and
    $rZero -eq $false -and
    $nonExistRes.InternalPanelFound -eq $false -and
    $nonExistRes.EnforcementAttempted -eq $false
)
Record-TestResult `
    -Category "Suite 4: 360Hz Lock" `
    -TestName "4.5: ShouldRestore360Hz boundary (<300Hz) and foreign target filter stand-down behave deterministically" `
    -Passed $edgeRatePass `
    -Details "60Hz->$r60, 299.9Hz->$r299, 300Hz->$r300, 360.152Hz->$r360, 0Hz->$rZero; NonExistentPanel Found=$($nonExistRes.InternalPanelFound)"

# -------------------------------------------------------------------------
# SUITE 5: Rapid 3-Stage Pipeline Burst Stress & Concurrency Test (< 100ms)
# -------------------------------------------------------------------------
Write-Host "`n--- SUITE 5: Rapid 3-Stage Pipeline Burst & Concurrency Stress ---" -ForegroundColor Yellow

# Warm up pipeline
[DisplayFix.Daemon.EventWindow]::ExecuteReconfigurationPipeline("Warmup") | Out-Null

$proc = [System.Diagnostics.Process]::GetCurrentProcess()
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()
$handlesBefore = $proc.HandleCount
$gcBefore = [System.GC]::GetTotalMemory($true)

# Test 5.1: 50 consecutive 3-stage pipeline invocations (latency < 100ms per call, P95 < 50ms)
$pipelineLatencies = [System.Collections.Generic.List[double]]::new()
$allStepsSucceeded = $true
$burstIterations = 50

$swBurstTotal = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 1; $i -le $burstIterations; $i++) {
    $res = [DisplayFix.Daemon.EventWindow]::ExecuteReconfigurationPipeline("AdversarialBurst_$i")
    $pipelineLatencies.Add($res.TotalElapsedMs)
    if (-not $res.RefreshRateEnforced -or -not $res.DpiScalingSynchronized) {
        $allStepsSucceeded = $false
    }
}
$swBurstTotal.Stop()

$proc.Refresh()
$handlesAfter = $proc.HandleCount
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()
$gcAfter = [System.GC]::GetTotalMemory($true)

$sortedPipe = [System.Collections.Generic.List[double]]::new($pipelineLatencies)
$sortedPipe.Sort()
$minPipe = $sortedPipe[0]
$maxPipe = $sortedPipe[$sortedPipe.Count - 1]
$sumPipe = 0.0
foreach ($v in $sortedPipe) { $sumPipe += $v }
$avgPipe = $sumPipe / $sortedPipe.Count
$p95Pipe = $sortedPipe[[int][math]::Floor($sortedPipe.Count * 0.95)]

$pipeLatencyPass = ($allStepsSucceeded -and $avgPipe -lt 50.0 -and $p95Pipe -lt 100.0 -and $maxPipe -lt 100.0)
Record-TestResult `
    -Category "Suite 5: Pipeline Stress" `
    -TestName "5.1: 50-burst ExecuteReconfigurationPipeline maintains < 100ms latency budget (Avg: $([math]::Round($avgPipe, 2))ms, P95: $([math]::Round($p95Pipe, 2))ms, Max: $([math]::Round($maxPipe, 2))ms)" `
    -Passed $pipeLatencyPass `
    -Details "50 full 3-stage runs completed in $([math]::Round($swBurstTotal.Elapsed.TotalMilliseconds, 2))ms. Min=$([math]::Round($minPipe, 2))ms, Avg=$([math]::Round($avgPipe, 2))ms, P95=$([math]::Round($p95Pipe, 2))ms, Max=$([math]::Round($maxPipe, 2))ms, AllStepsOK=$allStepsSucceeded"

# Test 5.2: Zero handle or memory leaks across 50 full 3-stage pipeline runs
$handleDeltaPipe = $handlesAfter - $handlesBefore
$gcDeltaKB = [math]::Round(($gcAfter - $gcBefore) / 1024.0, 2)
$leakPass = ([math]::Abs($handleDeltaPipe) -le 5 -and $gcDeltaKB -lt 1024.0)
Record-TestResult `
    -Category "Suite 5: Pipeline Stress" `
    -TestName "5.2: Zero handle or memory leaks across 50 full 3-stage pipeline invocations (Handle Delta: $handleDeltaPipe, GC Delta: ${gcDeltaKB} KB)" `
    -Passed $leakPass `
    -Details "Handles: $handlesBefore -> $handlesAfter (Delta: $handleDeltaPipe). GC Heap Delta: ${gcDeltaKB} KB."

# Test 5.3: Multi-threaded concurrent ExecuteReconfigurationPipeline stress (8 parallel threads)
$eventWindowType = $assembly.GetType('DisplayFix.Daemon.EventWindow')
$parallelResults = [DisplayFix.AdversarialTests.ParallelPipelineRunner]::RunParallel($eventWindowType, 8)

$parallelOk = ($parallelResults.Count -eq 8)
foreach ($r in $parallelResults) {
    if ($null -eq $r -or -not $r.RefreshRateEnforced -or -not $r.DpiScalingSynchronized) {
        $parallelOk = $false
    }
}
Record-TestResult `
    -Category "Suite 5: Pipeline Stress" `
    -TestName "5.3: 8 concurrent OS threads invoking ExecuteReconfigurationPipeline serialize safely via lock with 100% success" `
    -Passed $parallelOk `
    -Details "All $($parallelResults.Count) concurrent OS threads completed without race conditions or exceptions."

# Test 5.4: Concurrent CLI execution (--status, --lock-360hz, --sync-dpi) while daemon is running
Get-Process -Name DisplayFixDaemon -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

$bgDaemon = Start-Process -FilePath $daemonExePath -ArgumentList "--run" -PassThru
Start-Sleep -Seconds 1

try {
    $outStatus = & $daemonExePath --status | Out-String
    $exitStatus = $LASTEXITCODE

    $outLock = & $daemonExePath --lock-360hz | Out-String
    $exitLock = $LASTEXITCODE

    $outSync = & $daemonExePath --sync-dpi | Out-String
    $exitSync = $LASTEXITCODE

    $cliConcurrentPass = (
        $exitStatus -eq 0 -and
        $exitLock -eq 0 -and
        $exitSync -eq 0 -and
        $outStatus -match 'Mutex Active:\s+True' -and
        $outStatus -match 'Process Running:\s+True \(Count: 1\)' -and
        $outStatus -match 'Refresh Rate \(Hz\):\s+360 Hz' -and
        $outStatus -match 'Display Scaling \(%\):\s+125%'
    )

    Record-TestResult `
        -Category "Suite 5: Pipeline Stress" `
        -TestName "5.4: CLI --status, --lock-360hz, and --sync-dpi execute concurrently alongside resident daemon with accurate telemetry" `
        -Passed $cliConcurrentPass `
        -Details "StatusExit=$exitStatus (Count=1, 360Hz, 125%), LockExit=$exitLock, SyncExit=$exitSync"
}
finally {
    if ($null -ne $bgDaemon -and -not $bgDaemon.HasExited) {
        Stop-Process -Id $bgDaemon.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Process -Name DisplayFixDaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

# -------------------------------------------------------------------------
# SUMMARY & FINAL VERDICT
# -------------------------------------------------------------------------
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  MILESTONE 3 ADVERSARIAL TEST SUMMARY" -ForegroundColor White
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
