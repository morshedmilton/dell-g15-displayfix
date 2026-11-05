# Milestone 3 Forensic Audit Report (`auditor_m3_1`)

**Auditor:** Forensic Auditor M3_1  
**Date:** 2026-11-05  
**Milestone:** M3 — 360Hz Refresh Rate Lock & Persistent 125% DPI Scaling  
**Audited Targets:**
- Source files: `src/Daemon/Interop.cs`, `src/Daemon/RefreshRateLock.cs`, `src/Daemon/ScalingSynchronizer.cs`, `src/Daemon/GhostEvictionEngine.cs`, `src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`
- Compiled binary: `bin\DisplayFixDaemon.exe`

**Final Audit Verdict:** **CLEAN**

---

## 1. Forensic Authenticity Inspection

### 1.1 Zero Hardcoded Fake Returns or Mock Objects
A line-by-line inspection of all 6 source files in `src/Daemon/` confirmed:
- **Zero mock objects, stubbed interfaces, or simulated hardware responses.**
- **100% genuine Win32 CCD P/Invoke execution (`user32.dll`)**:
  - `GetDisplayConfigBufferSizes` (`Interop.cs:576`)
  - `QueryDisplayConfig` (`Interop.cs:582`)
  - `SetDisplayConfig` (`Interop.cs:591`)
  - `DisplayConfigGetDeviceInfo` (`Interop.cs:599-612`)
  - `DisplayConfigSetDeviceInfo` (`Interop.cs:615`)
  - `EnumDisplaySettingsW` (`Interop.cs:619`) and `ChangeDisplaySettingsExW` (`Interop.cs:625`)
- **100% genuine SetupAPI & CfgMgr32 P/Invoke execution (`setupapi.dll`, `cfgmgr32.dll`)**:
  - `SetupDiGetClassDevsW`, `SetupDiEnumDeviceInfo`, `SetupDiGetDeviceInstanceIdW`, `SetupDiDestroyDeviceInfoList`
  - `CM_Locate_DevNodeW`, `CM_Get_DevNode_Status`, `CM_Get_Parent`, `CM_Get_Device_IDW`, `CM_Disable_DevNode`, `CM_Enable_DevNode`, `CM_Reenumerate_DevNode`
- **100% genuine Windows Registry operations (`Microsoft.Win32.Registry`)**:
  - Real reads and writes to `HKCU\Control Panel\Desktop\LogPixels` and `HKCU\Control Panel\Desktop\PerMonitorSettings\*AUOAA9F*\DpiValue` (plus loaded `HKEY_USERS\S-1-5-21-*` hives).

### 1.2 Live Reflection Verification of Unmanaged Struct Sizes
Executed live reflection against `bin\DisplayFixDaemon.exe` using `[System.Runtime.InteropServices.Marshal]::SizeOf([Type]$t)`:
```text
DISPLAYCONFIG_PATH_INFO = 72 bytes
DISPLAYCONFIG_MODE_INFO = 64 bytes
DISPLAYCONFIG_DEVICE_INFO_HEADER = 20 bytes
DISPLAYCONFIG_SOURCE_DPI_SCALE_GET = 32 bytes
DISPLAYCONFIG_SOURCE_DPI_SCALE_SET = 24 bytes
DEVMODEW = 220 bytes
```

---

## 2. Live CLI & Hardware Execution Evidence

### 2.1 Live Execution of `.\bin\DisplayFixDaemon.exe --status`
```text
2026-11-05 19:57:43.695 [INFO ] [CLI         ] Executing --status command.
==================================================================
 DisplayFixDaemon Status Telemetry
==================================================================
Mutex Active:        False (Global\DisplayFixDaemon_SingleInstanceMutex)
Process Running:     False (Count: 0)
Refresh Rate (Hz):   360 Hz
Display Scaling (%): 125%
Log File:            C:\ProgramData\DisplayFix\logs\daemon.log
Log Exists:          True
Current Elevation:   Non-Elevated (Limited)
==================================================================
ExitCode (--status): 0
```

### 2.2 Live Execution of `.\bin\DisplayFixDaemon.exe --lock-360hz`
```text
2026-11-05 19:57:43.737 [INFO ] [CLI         ] Executing --lock-360hz (one-shot 360Hz refresh rate enforcement).
Executing one-shot 360Hz refresh rate lock...
2026-11-05 19:57:43.744 [DEBUG] [RefreshLock ] Clean: Internal panel already locked at 360152/1000 (360.152Hz) on '\\.\DISPLAY5'.
One-shot 360Hz lock complete in 3.47ms. Success: True (Before: 360Hz -> After: 360Hz)
Details: Clean: Internal panel already locked at 360152/1000 (360.152Hz) on '\\.\DISPLAY5'.
2026-11-05 19:57:43.745 [INFO ] [CLI         ] One-shot 360Hz lock finished in 3.47ms. Success=True, Before=360Hz, After=360Hz, Details=Clean: Internal panel already locked at 360152/1000 (360.152Hz) on '\\.\DISPLAY5'.
ExitCode (--lock-360hz): 0
```

### 2.3 Live Execution of `.\bin\DisplayFixDaemon.exe --sync-dpi`
```text
2026-11-05 19:57:43.772 [INFO ] [CLI         ] Executing --sync-dpi (one-shot 125% DPI registry & CCD synchronization).
Executing one-shot 125% DPI scaling synchronization...
2026-11-05 19:57:43.813 [INFO ] [ScalingSync ] Enforced 125% DPI scaling (scaleRel=0) via CCD on Adapter=0x00000000:0x00013356, SourceId=0 (prevScaleRel=0).
2026-11-05 19:57:43.814 [INFO ] [ScalingSync ] ScalingSync complete in 38.93ms: Registry(Checked=4, Updated=0, LogPixels=120) | CCD(Enforced=True, Modified=True, Paths=1, ScaleRel=0, Err=0)
One-shot 125% DPI sync complete in 40.20ms. Success: True (Before: 125% -> After: 125%)
Details: ScalingSync complete in 38.93ms: Registry(Checked=4, Updated=0, LogPixels=120) | CCD(Enforced=True, Modified=True, Paths=1, ScaleRel=0, Err=0)
2026-11-05 19:57:43.814 [INFO ] [CLI         ] One-shot 125% DPI sync finished in 40.20ms. Success=True, Before=125%, After=125%, Details=ScalingSync complete in 38.93ms: Registry(Checked=4, Updated=0, LogPixels=120) | CCD(Enforced=True, Modified=True, Paths=1, ScaleRel=0, Err=0)
ExitCode (--sync-dpi): 0
```

### 2.4 Live Registry State Verification (`HKCU:\Control Panel\Desktop`)
```text
HKCU:\Control Panel\Desktop\LogPixels = 120
SubKey: AUOAA9F0_01_07E6_5E^6ABFF6B3F25020EA5A6C25291E1D582D -> DpiValue = 0
SubKey: AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101^FDE0356523D5B9A29A5941D074E48378 -> DpiValue = 0
SubKey: AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050^319ED67D37B9BF8FC2018AB04FBE8BBA -> DpiValue = 0
SubKey: MSNILAUOAA9F0_01_07E6_5E_1414_008D_FFFFFFFF_FFFFFFFF_0^2ECECAD59660E55B0C1038F3842E810F -> DpiValue = 0
```

### 2.5 Live Unified 3-Stage Pipeline Execution (`EventWindow.ExecuteReconfigurationPipeline`)
```text
2026-11-05 19:57:43.920 [DEBUG] [EvictionEngine] Clean: Intel ghost node UID8388688 is already evicted (non-present).
2026-11-05 19:57:43.925 [DEBUG] [RefreshLock ] Clean: Internal panel already locked at 360152/1000 (360.152Hz) on '\\.\DISPLAY5'.
2026-11-05 19:57:43.932 [DEBUG] [ScalingSync ] Active path [0] (SourceId=0) is already locked at 125% (curScaleRel=0, min=-2, max=1).
2026-11-05 19:57:43.932 [DEBUG] [ScalingSync ] ScalingSync complete in 5.67ms: Registry(Checked=4, Updated=0, LogPixels=120) | CCD(Enforced=True, Modified=False, Paths=1, ScaleRel=0, Err=0)
2026-11-05 19:57:43.933 [INFO ] [Pipeline    ] Unified pipeline completed within budget (24.43ms <= 100ms): Trigger='ForensicAudit_LiveCheck', Total=24.43ms [Step1_Evict=0 (12.29ms), Step2_360Hz=True (5.27ms), Step3_125Dpi=True (6.86ms)]
```

---

## 3. Final Forensic Verdict
**CLEAN** — Zero mocks, zero fake returns, 100% authentic Win32 CCD / CfgMgr32 / Registry operations verified on live hardware.
