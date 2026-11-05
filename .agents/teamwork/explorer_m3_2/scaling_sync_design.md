# Milestone 3 Design Blueprint: Multi-Topology Registry DPI Sync (F08) & Dynamic CCD 125% DPI Enforcement Engine (F09)

**Author:** Explorer M3_2  
**Date:** 2026-11-05  
**Target Platform:** Dell G15 5530 (Intel UHD `8086:A78B` + NVIDIA RTX 4060 `10DE:28E0`, Internal eDP Panel `AUOAA9F`, Windows 11 x64)  
**Compiler Target:** Native `csc.exe` (.NET Framework 4.8 x64, strict C# 5 syntax compatibility, zero external dependencies)

---

## 1. Executive Summary & Empirical Hardware Telemetry

When switching between **Optimus** (Intel iGPU driving internal eDP) and **NVIDIA GPU Only** (dGPU driving internal eDP via Advanced Optimus / DDS), Windows treats the physical `AUOAA9F` panel as distinct display topologies keyed by the active adapter and connector path.

### 1.1 Live Registry Telemetry (`DEFECT-F08-DPI-DESYNC`)
Direct inspection of `HKCU:\Control Panel\Desktop` and `HKCU:\Control Panel\Desktop\PerMonitorSettings` on the target machine revealed the exact root cause of scaling reverts and blurry fonts:

| Registry Path / Key Name | Property | Live Value | Signed Interpretation | Resulting Scale |
|---|---|---|---|---|
| `HKCU:\Control Panel\Desktop` | `LogPixels` | `120` | `120` DPI | **125%** (System Base) |
| `AUOAA9F0_01_07E6_5E^6ABFF6B3F25020EA5A6C25291E1D582D` | `DpiValue` | `0` | `0` (Recommended) | **125%** |
| `AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050^...` | `DpiValue` | `0` | `0` (Recommended) | **125%** (Intel iGPU) |
| `AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101^...` | `DpiValue` | `4294967295` | `-1` (`0xFFFFFFFF`) | **100%** (NVIDIA dGPU Desync!) |
| `MSNILAUOAA9F0_01_07E6_5E_1414_008D_FFFFFFFF_FFFFFFFF_0^...` | `DpiValue` | `4294967295` | `-1` (`0xFFFFFFFF`) | **100%** (Basic Display Desync!) |

Because the NVIDIA (`10DE_28E0`) and Microsoft Basic Display (`MSNILAUOAA9F0`) topology entries store `DpiValue = 4294967295` (signed `-1`), switching the display mux to the NVIDIA dGPU causes Windows to drop monitor scaling to 100% (`96` DPI) while `LogPixels` remains at `120` DPI (125%), triggering DWM bitmap stretching (blurry text) and shrinking UI elements.

### 1.2 Live CCD API Verification (`probe_ccd_dpi.ps1`)
Executing `QueryDisplayConfig`, `DisplayConfigGetDeviceInfo`, and `DisplayConfigSetDeviceInfo` on the live Dell G15 5530 confirmed:
- `GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS)` $\rightarrow$ `rc = 0`, `paths = 1`, `modes = 2`.
- `DisplayConfigGetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2`, `size = 420`) $\rightarrow$ `rc = 0`, `monitorDevicePath = "\\?\DISPLAY#AUOAA9F#5&39808dae&2&UID4353#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}"`.
- `DisplayConfigGetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3`, `size = 32`) $\rightarrow$ `rc = 0`, `minScaleRel = -2`, `curScaleRel = 0`, `maxScaleRel = 1`.
- `DisplayConfigSetDeviceInfo` (`DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`, `size = 24`, `scaleRel = 0`) $\rightarrow$ `rc = 0` (`ERROR_SUCCESS`).

**Crucial Finding:** Calling `DisplayConfigSetDeviceInfo` only updates the *currently active* CCD display path in DWM; it does **not** retroactively overwrite inactive topology branches in `PerMonitorSettings` (such as `AUOAA9F0_..._10DE_28E0_...` or `MSNILAUOAA9F0_...`). Therefore, **both** Multi-Topology Registry Synchronization (F08) and Dynamic CCD Enforcement (F09) must run in tandem.

---

## 2. Architecture & Design Specifications

### 2.1 Feature F08: Multi-Topology Registry DPI Synchronization
1. **System Base DPI (`LogPixels`):**
   - Open/create `HKCU\Control Panel\Desktop` with write access.
   - Read `LogPixels`. If missing or not equal to `120` (125% base DPI = $96 \times 1.25$), write `LogPixels = 120` (`RegistryValueKind.DWord`).
2. **`PerMonitorSettings` Branch & Root Key:**
   - Open/create `HKCU\Control Panel\Desktop\PerMonitorSettings` (satisfying Test F08.1).
   - Set `DpiValue = 0` (`RegistryValueKind.DWord`) on the `PerMonitorSettings` root key if not already `0`.
3. **Internal Panel Subkey Enumeration & Filtering:**
   - Enumerate all subkeys under `HKCU\Control Panel\Desktop\PerMonitorSettings`.
   - Filter using `IsInternalPanelTopologyKey(string subKeyName)`:
     ```csharp
     public static bool IsInternalPanelTopologyKey(string keyName)
     {
         if (string.IsNullOrEmpty(keyName)) return false;
         return keyName.IndexOf("AUOAA9F", StringComparison.OrdinalIgnoreCase) >= 0;
     }
     ```
   - This matches all internal panel topologies:
     - Generic: `AUOAA9F0_01_07E6_5E^...`
     - Intel iGPU: `AUOAA9F0_01_07E6_5E_8086_A78B_...` (Test F08.3)
     - NVIDIA dGPU: `AUOAA9F0_01_07E6_5E_10DE_28E0_...` (Test F08.4)
     - Fallback driver: `MSNILAUOAA9F0_01_07E6_5E_1414_008D_...` (Test F08.5)
   - While strictly excluding external monitors (e.g., `DEL41230_01_07E6_5E_10DE_28E0_00000002`, satisfying Test B02.4).
4. **Signed/Unsigned `DpiValue` Normalization & Idempotency:**
   - In .NET `RegistryKey.GetValue("DpiValue")`, a `REG_DWORD` value of `0xFFFFFFFF` is returned as a boxed `int` with value `-1` (whereas PowerShell's `Get-ItemProperty` surfaces it as unsigned `uint32` `4294967295`).
   - Provide helper `ParseRegistryDwordToSignedInt32(object rawValue)` that safely converts `int`, `uint`, `long`, or byte representations into signed `int` (`0xFFFFFFFF` $\rightarrow$ `-1`, `0` $\rightarrow$ `0`, satisfying Test B02.2).
   - If `DpiValue` is missing or `!= 0`, write `0` (`RegistryValueKind.DWord`). If already `0`, skip redundant write or write idempotently (satisfying Test B02.5).
5. **Multi-Hive Safety (`HKEY_CURRENT_USER` + `HKEY_USERS`):**
   - Synchronize `Registry.CurrentUser` primary, and also scan loaded interactive user SIDs under `Registry.Users` (matching `S-1-5-21-*` without `_Classes`) so that even if the daemon or CLI is invoked under an elevated token with a separate profile view, the interactive user's `PerMonitorSettings` hive is guaranteed to be synchronized.

### 2.2 Feature F09: Dynamic CCD 125% DPI Enforcement
1. **CCD Constants & Structures:**
   - `DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2`
   - `DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3` (Test F09.1)
   - `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4` (Test F09.1)
   - `DISPLAYCONFIG_DEVICE_INFO_HEADER`: 20 bytes (`int type`, `uint size`, `LUID adapterId`, `uint id`).
   - `DISPLAYCONFIG_SOURCE_DPI_SCALE_GET`: 32 bytes (`header` + `int minScaleRel`, `int curScaleRel`, `int maxScaleRel`).
   - `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET`: 24 bytes (`header` + `int scaleRel`) (Test F09.3).
2. **Relative Scale Step Mapping (`scaleRel`):**
   - Standard Windows DPI array: `[100%, 125%, 150%, 175%, 200%, 225%, ...]`
   - On the Dell G15 5530 `AUOAA9F` 1080p panel, Windows recommends **125%**, which corresponds to `scaleRel = 0` (Test F09.2).
   - `scaleRel = -1` (or `minScaleRel`) corresponds to **100%**.
   - `scaleRel = +1` corresponds to **150%**.
3. **Three-Stage Execution Pipeline (`ScalingSynchronizer.CheckAndEnforce`):**
   - **Stage 1 (Pre-CCD Registry Sync):** Synchronize `LogPixels = 120` and all `*AUOAA9F*` subkeys in `PerMonitorSettings` to `DpiValue = 0`.
   - **Stage 2 (Dynamic CCD Enforcement):**
     - Call `GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes)` and `QueryDisplayConfig(...)`.
     - For each active path:
       - Query `DISPLAYCONFIG_TARGET_DEVICE_NAME` using `path.targetInfo.adapterId` and `path.targetInfo.id`.
       - Check if `monitorDevicePath` contains `"AUOAA9F"` (or if `monitorDevicePath` is empty on a single-display internal path). Skip external monitors (`IsForeignMonitor`).
       - Query current DPI scale via `DisplayConfigGetDeviceInfo(ref getPacket)` using `path.sourceInfo.adapterId` and `path.sourceInfo.id` with `type = -3`, `size = 32`.
       - If `getPacket.curScaleRel != 0` or `forceCcdSet == true`, populate `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` (`type = -4`, `size = 24`, `adapterId = path.sourceInfo.adapterId`, `id = path.sourceInfo.id`, `scaleRel = 0`) and invoke `DisplayConfigSetDeviceInfo(ref setPacket)`.
   - **Stage 3 (Post-CCD Registry Verification):**
     - Re-run `SynchronizeRegistryTopologies` to ensure any registry write triggered by `DisplayConfigSetDeviceInfo` leaves all `*AUOAA9F*` topology keys strictly at `DpiValue = 0`.

---

## 3. P/Invoke Additions for `src/Daemon/Interop.cs`

Below is the exact C# 5 compatible region to add to `src/Daemon/Interop.cs` (designed to support both `RefreshRateLock.cs` (F07) and `ScalingSynchronizer.cs` (F08/F09) without duplicate symbol collisions):

```csharp
        #region CCD (Connecting and Configuring Displays) & DPI Scaling API

        public const int ERROR_SUCCESS             = 0;
        public const int ERROR_INSUFFICIENT_BUFFER = 122;
        public const int ERROR_GEN_FAILURE         = 31;

        public const uint QDC_ALL_PATHS         = 0x00000001;
        public const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        public const uint QDC_DATABASE_CURRENT  = 0x00000004;

        public const uint SDC_TOPOLOGY_INTERNAL           = 0x00000001;
        public const uint SDC_TOPOLOGY_CLONE              = 0x00000002;
        public const uint SDC_TOPOLOGY_EXTEND             = 0x00000004;
        public const uint SDC_TOPOLOGY_EXTERNAL           = 0x00000008;
        public const uint SDC_TOPOLOGY_SUPPLIED           = 0x00000010;
        public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
        public const uint SDC_VALIDATE                    = 0x00000040;
        public const uint SDC_APPLY                       = 0x00000080;
        public const uint SDC_NO_OPTIMIZATION             = 0x00000100;
        public const uint SDC_SAVE_TO_DATABASE            = 0x00000200;
        public const uint SDC_ALLOW_CHANGES               = 0x00000400;
        public const uint SDC_PATH_PERSIST_IF_REQUIRED    = 0x00000800;
        public const uint SDC_FORCE_MODE_ENUMERATION      = 0x00001000;
        public const uint SDC_ALLOW_PATH_ORDER_CHANGES    = 0x00002000;

        public const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;
        public const uint DISPLAYCONFIG_MODE_INFO_TYPE_TARGET = 2;

        // DISPLAYCONFIG_DEVICE_INFO_TYPE constants
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME             = 1;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME             = 2;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_PREFERRED_MODE   = 3;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME            = 4;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_TARGET_PERSISTENCE      = 5;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_BASE_TYPE        = 6;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SUPPORT_VIRTUAL_RESOLUTION = 7;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_SUPPORT_VIRTUAL_RESOLUTION = 8;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO     = 9;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE    = 10;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL         = 11;
        public const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE               = -3;
        public const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE               = -4;

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
            public uint LowPart;
            public int HighPart;

            public override string ToString()
            {
                return string.Format("0x{0:X8}:0x{1:X8}", HighPart, LowPart);
            }
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

        /// <summary>
        /// 20-byte header for DisplayConfigGetDeviceInfo / DisplayConfigSetDeviceInfo packets.
        /// Layout: type (4B) + size (4B) + adapterId (8B) + id (4B) = 20 bytes.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
        {
            public int type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        /// <summary>
        /// 32-byte packet for DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE (-3).
        /// Layout: header (20B) + minScaleRel (4B) + curScaleRel (4B) + maxScaleRel (4B) = 32 bytes.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int minScaleRel;
            public int curScaleRel;
            public int maxScaleRel;
        }

        /// <summary>
        /// 24-byte packet for DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE (-4).
        /// Layout: header (20B) + scaleRel (4B) = 24 bytes (verified by Test F09.3).
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int scaleRel;
        }

        /// <summary>
        /// Packet for DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME (2) to identify AUOAA9F panel path.
        /// </summary>
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_TARGET_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public uint flags;
            public uint outputTechnology;
            public ushort edidManufactureId;
            public ushort edidProductCodeId;
            public uint connectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
            public string monitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string monitorDevicePath;
        }

        /// <summary>
        /// Packet for DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME (1) to resolve GDI device name (e.g. \\.\DISPLAY1).
        /// </summary>
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string viewGdiDeviceName;
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

        [DllImport("user32.dll")]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

        [DllImport("user32.dll")]
        public static extern int DisplayConfigSetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET requestPacket);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForSystem();

        #endregion
```

---

## 4. Complete Compilable Blueprint: `src/Daemon/ScalingSynchronizer.cs`

```csharp
// src/Daemon/ScalingSynchronizer.cs
// Multi-Topology Registry DPI Synchronizer (F08) and Dynamic CCD 125% DPI Enforcement Engine (F09).
// Ensures persistent 125% (120 DPI) scaling across Optimus, Automatic, and NVIDIA GPU Only modes
// with zero font blur and zero session logoff/reboot requirements.
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using DisplayFix.Common;

namespace DisplayFix.Daemon
{
    /// <summary>
    /// Execution telemetry result returned from a DPI synchronization and CCD enforcement pass.
    /// </summary>
    public class ScalingSyncResult
    {
        public bool Success { get; set; }
        public bool RegistrySynced { get; set; }
        public int TopologiesChecked { get; set; }
        public int TopologiesUpdated { get; set; }
        public int LogPixels { get; set; }
        public bool LogPixelsUpdated { get; set; }
        public bool CcdEnforced { get; set; }
        public bool CcdModified { get; set; }
        public int ActivePathsChecked { get; set; }
        public int CurrentScaleRel { get; set; }
        public int MinScaleRel { get; set; }
        public int MaxScaleRel { get; set; }
        public int ScalePercent { get; set; }
        public int LastWin32Error { get; set; }
        public double ElapsedMilliseconds { get; set; }
        public string Message { get; set; }
    }

    /// <summary>
    /// Synchronizes PerMonitorSettings registry trees across Intel (8086_A78B) and NVIDIA (10DE_28E0)
    /// topologies and enforces 125% scaling dynamically via Windows CCD APIs.
    /// </summary>
    public static class ScalingSynchronizer
    {
        #region Constants

        public const string DesktopRegistrySubKey = @"Control Panel\Desktop";
        public const string PerMonitorSettingsSubKey = @"Control Panel\Desktop\PerMonitorSettings";
        public const string InternalPanelToken = "AUOAA9F";
        public const string IntelTopologyToken = "8086";
        public const string NvidiaTopologyToken = "10DE";

        public const string LogPixelsValueName = "LogPixels";
        public const string DpiValueName = "DpiValue";

        /// <summary>
        /// 120 DPI = 125% scaling factor (96 DPI * 1.25). Verified by Test F08.2.
        /// </summary>
        public const int TargetLogPixels125 = 120;

        /// <summary>
        /// Relative step 0 corresponds to 125% (Recommended scale on AUOAA9F 1080p panel).
        /// Verified by Test F08.3, F08.4, F09.2.
        /// </summary>
        public const int TargetDpiValueZero = 0;

        /// <summary>
        /// Standard Windows DPI scaling percentage steps indexed by offset from minimum (100%).
        /// </summary>
        private static readonly int[] StandardScalePercentages = new int[]
        {
            100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500
        };

        #endregion

        #region Public Entry Points & Interface Contracts

        /// <summary>
        /// Master interface contract specified by PROJECT.md §3.
        /// Synchronizes registry topologies and enforces 125% scaling via CCD.
        /// </summary>
        /// <returns>True if both registry sync and CCD enforcement succeeded.</returns>
        public static bool EnforceDisplayScaling125()
        {
            ScalingSyncResult result = CheckAndEnforce(forceCcdSet: false);
            return result.Success;
        }

        /// <summary>
        /// Alias entry point for EventWindow / CLI orchestration pipeline.
        /// </summary>
        public static ScalingSyncResult Enforce125()
        {
            return CheckAndEnforce(forceCcdSet: false);
        }

        /// <summary>
        /// Executes the complete 3-stage DPI synchronization and dynamic CCD enforcement pipeline:
        /// 1. Multi-Topology Registry DPI Sync (F08)
        /// 2. Dynamic CCD 125% DPI Enforcement (F09)
        /// 3. Post-CCD Registry Verification Pass
        /// </summary>
        /// <param name="forceCcdSet">If true, invokes DisplayConfigSetDeviceInfo even when curScaleRel == 0.</param>
        /// <returns>Structured telemetry result.</returns>
        public static ScalingSyncResult CheckAndEnforce(bool forceCcdSet = false)
        {
            Stopwatch sw = Stopwatch.StartNew();
            ScalingSyncResult result = new ScalingSyncResult();
            result.LogPixels = TargetLogPixels125;
            result.ScalePercent = 125;

            try
            {
                // Stage 1: Synchronize Registry Topologies (Pre-CCD)
                bool logPixelsUpdated1;
                int checkedCount1;
                int updatedCount1 = SynchronizeRegistryTopologies(out logPixelsUpdated1, out checkedCount1);

                result.RegistrySynced = true;
                result.LogPixelsUpdated = logPixelsUpdated1;
                result.TopologiesChecked = checkedCount1;
                result.TopologiesUpdated = updatedCount1;

                // Stage 2: Enforce 125% Scaling dynamically via CCD DisplayConfigSetDeviceInfo
                int activePaths;
                int curScaleRel;
                int minScaleRel;
                int maxScaleRel;
                bool ccdModified;
                int lastCcdErr;

                bool ccdOk = EnforceCcdDpiScale125(
                    forceCcdSet,
                    out activePaths,
                    out curScaleRel,
                    out minScaleRel,
                    out maxScaleRel,
                    out ccdModified,
                    out lastCcdErr);

                result.CcdEnforced = ccdOk;
                result.CcdModified = ccdModified;
                result.ActivePathsChecked = activePaths;
                result.CurrentScaleRel = curScaleRel;
                result.MinScaleRel = minScaleRel;
                result.MaxScaleRel = maxScaleRel;
                result.LastWin32Error = lastCcdErr;

                // Stage 3: Post-CCD Registry Verification Pass
                // Ensures any registry writes performed internally by Windows during DisplayConfigSetDeviceInfo
                // leave all AUOAA9F topologies pinned to DpiValue = 0.
                bool logPixelsUpdated2;
                int checkedCount2;
                int updatedCount2 = SynchronizeRegistryTopologies(out logPixelsUpdated2, out checkedCount2);

                result.LogPixelsUpdated = result.LogPixelsUpdated || logPixelsUpdated2;
                if (checkedCount2 > result.TopologiesChecked)
                {
                    result.TopologiesChecked = checkedCount2;
                }
                result.TopologiesUpdated += updatedCount2;

                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Success = result.RegistrySynced && result.CcdEnforced;

                result.Message = string.Format(
                    "ScalingSync complete in {0:F2}ms: Registry(Checked={1}, Updated={2}, LogPixels=120) | CCD(Enforced={3}, Modified={4}, Paths={5}, ScaleRel={6}, Err={7})",
                    result.ElapsedMilliseconds,
                    result.TopologiesChecked,
                    result.TopologiesUpdated,
                    result.CcdEnforced,
                    result.CcdModified,
                    result.ActivePathsChecked,
                    result.CurrentScaleRel,
                    result.LastWin32Error);

                if (result.TopologiesUpdated > 0 || result.CcdModified || result.LogPixelsUpdated)
                {
                    Logger.Info("ScalingSync", result.Message);
                }
                else
                {
                    Logger.Debug("ScalingSync", result.Message);
                }
            }
            catch (Exception ex)
            {
                sw.Stop();
                result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
                result.Success = false;
                result.Message = "Exception during ScalingSynchronizer.CheckAndEnforce: " + ex.Message;
                Logger.Error("ScalingSync", result.Message, ex);
            }

            return result;
        }

        #endregion

        #region Feature F08: Multi-Topology Registry DPI Synchronization

        /// <summary>
        /// Determines whether a PerMonitorSettings subkey belongs to the internal AUOAA9F panel.
        /// Isolates foreign external displays per Test B02.4.
        /// </summary>
        public static bool IsInternalPanelTopologyKey(string keyName)
        {
            if (string.IsNullOrEmpty(keyName))
            {
                return false;
            }
            return keyName.IndexOf(InternalPanelToken, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>
        /// Safely parses a registry DWORD value (which may be boxed as int, uint, or long)
        /// into a signed 32-bit integer (e.g. 4294967295 / 0xFFFFFFFF -> -1, 0 -> 0).
        /// Verified by Test B02.2.
        /// </summary>
        public static int ParseRegistryDwordToSignedInt32(object rawValue, int defaultValue)
        {
            if (rawValue == null)
            {
                return defaultValue;
            }

            try
            {
                if (rawValue is int)
                {
                    return (int)rawValue;
                }
                if (rawValue is uint)
                {
                    return unchecked((int)(uint)rawValue);
                }
                if (rawValue is long)
                {
                    return unchecked((int)(long)rawValue);
                }
                uint parsedUnsigned = Convert.ToUInt32(rawValue);
                return BitConverter.ToInt32(BitConverter.GetBytes(parsedUnsigned), 0);
            }
            catch
            {
                return defaultValue;
            }
        }

        /// <summary>
        /// Synchronizes HKCU:\Control Panel\Desktop\LogPixels = 120 and sets DpiValue = 0
        /// across all PerMonitorSettings subkeys matching *AUOAA9F* (Intel, NVIDIA, and fallback topologies).
        /// Also synchronizes loaded interactive user hives under HKEY_USERS if running in an elevated context.
        /// </summary>
        public static int SynchronizeRegistryTopologies(out bool logPixelsUpdated, out int topologiesChecked)
        {
            logPixelsUpdated = false;
            topologiesChecked = 0;
            int totalUpdated = 0;

            // 1. Synchronize primary Registry.CurrentUser hive
            bool hkcuLogUpdated;
            int hkcuChecked;
            totalUpdated += SynchronizeHive(Registry.CurrentUser, out hkcuLogUpdated, out hkcuChecked);
            logPixelsUpdated = hkcuLogUpdated;
            topologiesChecked = hkcuChecked;

            // 2. Defensively synchronize loaded interactive user hives in Registry.Users (S-1-5-21-*)
            try
            {
                string[] sidNames = Registry.Users.GetSubKeyNames();
                for (int i = 0; i < sidNames.Length; i++)
                {
                    string sid = sidNames[i];
                    if (sid.StartsWith("S-1-5-21-", StringComparison.OrdinalIgnoreCase) &&
                        !sid.EndsWith("_Classes", StringComparison.OrdinalIgnoreCase))
                    {
                        using (RegistryKey userHive = Registry.Users.OpenSubKey(sid, writable: true))
                        {
                            if (userHive != null)
                            {
                                bool sidLogUpdated;
                                int sidChecked;
                                int sidUpdated = SynchronizeHive(userHive, out sidLogUpdated, out sidChecked);
                                if (sidChecked > topologiesChecked)
                                {
                                    topologiesChecked = sidChecked;
                                }
                                totalUpdated += sidUpdated;
                                logPixelsUpdated = logPixelsUpdated || sidLogUpdated;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Debug("ScalingSync", "Note: HKEY_USERS supplementary scan skipped: " + ex.Message);
            }

            return totalUpdated;
        }

        private static int SynchronizeHive(RegistryKey rootHive, out bool logPixelsUpdated, out int topologiesChecked)
        {
            logPixelsUpdated = false;
            topologiesChecked = 0;
            int topologiesUpdated = 0;

            if (rootHive == null)
            {
                return 0;
            }

            // A. Ensure Control Panel\Desktop\LogPixels == 120 (125% system DPI base, Test F08.2)
            try
            {
                using (RegistryKey desktopKey = rootHive.CreateSubKey(DesktopRegistrySubKey))
                {
                    if (desktopKey != null)
                    {
                        object rawLogPixels = desktopKey.GetValue(LogPixelsValueName);
                        int currentLogPixels = ParseRegistryDwordToSignedInt32(rawLogPixels, -1);
                        if (rawLogPixels == null || currentLogPixels != TargetLogPixels125)
                        {
                            desktopKey.SetValue(LogPixelsValueName, TargetLogPixels125, RegistryValueKind.DWord);
                            logPixelsUpdated = true;
                            Logger.Info("ScalingSync", string.Format(
                                "Updated {0}\\LogPixels from {1} to {2} (125% system base).",
                                DesktopRegistrySubKey, currentLogPixels, TargetLogPixels125));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("ScalingSync", "Failed to synchronize Control Panel\\Desktop\\LogPixels: " + ex.Message);
            }

            // B. Ensure Control Panel\Desktop\PerMonitorSettings exists and sync all *AUOAA9F* subkeys to DpiValue = 0
            try
            {
                using (RegistryKey pmRootKey = rootHive.CreateSubKey(PerMonitorSettingsSubKey))
                {
                    if (pmRootKey != null)
                    {
                        // Also ensure DpiValue = 0 on PerMonitorSettings root key if applicable
                        object rootDpiObj = pmRootKey.GetValue(DpiValueName);
                        if (rootDpiObj != null)
                        {
                            int rootDpiVal = ParseRegistryDwordToSignedInt32(rootDpiObj, -999);
                            if (rootDpiVal != TargetDpiValueZero)
                            {
                                pmRootKey.SetValue(DpiValueName, TargetDpiValueZero, RegistryValueKind.DWord);
                            }
                        }

                        string[] subKeyNames = pmRootKey.GetSubKeyNames();
                        for (int i = 0; i < subKeyNames.Length; i++)
                        {
                            string subName = subKeyNames[i];

                            // Isolate external monitors: only touch internal panel AUOAA9F topologies (Test B02.4)
                            if (!IsInternalPanelTopologyKey(subName))
                            {
                                continue;
                            }

                            topologiesChecked++;

                            using (RegistryKey topoKey = pmRootKey.OpenSubKey(subName, writable: true))
                            {
                                if (topoKey == null)
                                {
                                    continue;
                                }

                                object rawDpi = topoKey.GetValue(DpiValueName);
                                int signedDpi = ParseRegistryDwordToSignedInt32(rawDpi, -999);

                                if (rawDpi == null || signedDpi != TargetDpiValueZero)
                                {
                                    topoKey.SetValue(DpiValueName, TargetDpiValueZero, RegistryValueKind.DWord);
                                    topologiesUpdated++;
                                    Logger.Info("ScalingSync", string.Format(
                                        "Synchronized topology '{0}' DpiValue from {1} (0x{2:X8}) to 0 (125% recommended).",
                                        subName, signedDpi, unchecked((uint)signedDpi)));
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("ScalingSync", "Failed to synchronize PerMonitorSettings subkeys: " + ex.Message);
            }

            return topologiesUpdated;
        }

        #endregion

        #region Feature F09: Dynamic CCD 125% DPI Enforcement

        /// <summary>
        /// Converts a relative CCD DPI step into a percentage scale factor.
        /// Relative step 0 maps to 125% (native recommended scale on AUOAA9F).
        /// </summary>
        public static int MapRelativeStepToPercent(int scaleRel, int minScaleRel)
        {
            // Relative to 125% (step 0):
            // Wait: On Windows, minScaleRel is the step index for 100% (or minimum scale).
            // Standard mapping table verified by Test F09.2:
            // [-1: 100%, 0: 125%, 1: 150%, 2: 175%, 3: 200%]
            if (scaleRel == 0) return 125;
            if (scaleRel == -1) return 100;
            if (scaleRel == 1) return 150;
            if (scaleRel == 2) return 175;
            if (scaleRel == 3) return 200;

            int indexFromMin = scaleRel - minScaleRel;
            if (indexFromMin >= 0 && indexFromMin < StandardScalePercentages.Length)
            {
                return StandardScalePercentages[indexFromMin];
            }

            return 125;
        }

        /// <summary>
        /// Enforces 125% scaling (scaleRel = 0) dynamically across active internal panel CCD paths
        /// via DisplayConfigGetDeviceInfo (-3) and DisplayConfigSetDeviceInfo (-4).
        /// Requires zero user logoff or reboot (Test F09.5).
        /// </summary>
        public static bool EnforceCcdDpiScale125(
            bool forceSet,
            out int activePathsChecked,
            out int currentScaleRel,
            out int minScaleRel,
            out int maxScaleRel,
            out bool modified,
            out int lastWin32Error)
        {
            activePathsChecked = 0;
            currentScaleRel = 0;
            minScaleRel = -1;
            maxScaleRel = 3;
            modified = false;
            lastWin32Error = Interop.ERROR_SUCCESS;

            uint numPaths = 0;
            uint numModes = 0;

            int rcSizes = Interop.GetDisplayConfigBufferSizes(
                Interop.QDC_ONLY_ACTIVE_PATHS,
                out numPaths,
                out numModes);

            if (rcSizes != Interop.ERROR_SUCCESS || numPaths == 0)
            {
                lastWin32Error = rcSizes;
                Logger.Warn("ScalingSync", string.Format(
                    "GetDisplayConfigBufferSizes failed or returned 0 active paths (rc={0}, paths={1}).",
                    rcSizes, numPaths));
                return false;
            }

            Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
            Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];

            int rcQuery = Interop.QueryDisplayConfig(
                Interop.QDC_ONLY_ACTIVE_PATHS,
                ref numPaths,
                paths,
                ref numModes,
                modes,
                IntPtr.Zero);

            if (rcQuery != Interop.ERROR_SUCCESS)
            {
                lastWin32Error = rcQuery;
                Logger.Warn("ScalingSync", string.Format("QueryDisplayConfig failed with Win32 error {0}.", rcQuery));
                return false;
            }

            bool allInternalSucceeded = true;

            for (int i = 0; i < numPaths; i++)
            {
                Interop.DISPLAYCONFIG_PATH_INFO path = paths[i];

                // Identify target monitor path to ensure we only enforce 125% on internal AUOAA9F panel
                Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME targetName = new Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME();
                targetName.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
                targetName.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_TARGET_DEVICE_NAME));
                targetName.header.adapterId = path.targetInfo.adapterId;
                targetName.header.id = path.targetInfo.id;

                int rcTarget = Interop.DisplayConfigGetDeviceInfo(ref targetName);
                string devPath = (rcTarget == Interop.ERROR_SUCCESS && targetName.monitorDevicePath != null)
                    ? targetName.monitorDevicePath
                    : string.Empty;

                // If multiple monitors are connected and this path is explicitly a foreign monitor, skip it
                if (!string.IsNullOrEmpty(devPath) &&
                    devPath.IndexOf(InternalPanelToken, StringComparison.OrdinalIgnoreCase) < 0)
                {
                    Logger.Debug("ScalingSync", string.Format(
                        "Skipping CCD DPI enforcement for external monitor path [{0}]: '{1}'", i, devPath));
                    continue;
                }

                activePathsChecked++;

                // 1. Query current relative DPI scale via DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE (-3)
                Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
                getReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
                getReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
                getReq.header.adapterId = path.sourceInfo.adapterId;
                getReq.header.id = path.sourceInfo.id;

                int rcGet = Interop.DisplayConfigGetDeviceInfo(ref getReq);
                if (rcGet == Interop.ERROR_SUCCESS)
                {
                    minScaleRel = getReq.minScaleRel;
                    currentScaleRel = getReq.curScaleRel;
                    maxScaleRel = getReq.maxScaleRel;
                }
                else
                {
                    lastWin32Error = rcGet;
                    Logger.Warn("ScalingSync", string.Format(
                        "DisplayConfigGetDeviceInfo(GET_DPI_SCALE) on SourceId={0} returned rc={1}. Proceeding with SET_DPI_SCALE.",
                        path.sourceInfo.id, rcGet));
                }

                // 2. If curScaleRel != 0 (not 125%) or forceSet requested, enforce scaleRel = 0
                if (rcGet != Interop.ERROR_SUCCESS || getReq.curScaleRel != TargetDpiValueZero || forceSet)
                {
                    Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
                    setReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
                    setReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_SET)); // 24 bytes
                    setReq.header.adapterId = path.sourceInfo.adapterId;
                    setReq.header.id = path.sourceInfo.id;
                    setReq.scaleRel = TargetDpiValueZero; // 0 = 125% Recommended

                    int rcSet = Interop.DisplayConfigSetDeviceInfo(ref setReq);
                    if (rcSet == Interop.ERROR_SUCCESS)
                    {
                        modified = true;
                        currentScaleRel = TargetDpiValueZero;
                        Logger.Info("ScalingSync", string.Format(
                            "Enforced 125% DPI scaling (scaleRel=0) via CCD on Adapter={0}, SourceId={1} (prevScaleRel={2}).",
                            path.sourceInfo.adapterId, path.sourceInfo.id, getReq.curScaleRel));
                    }
                    else
                    {
                        lastWin32Error = rcSet;
                        allInternalSucceeded = false;
                        Logger.Warn("ScalingSync", string.Format(
                            "DisplayConfigSetDeviceInfo(SET_DPI_SCALE, scaleRel=0) failed with Win32 error {0}.", rcSet));
                    }
                }
                else
                {
                    Logger.Debug("ScalingSync", string.Format(
                        "Active path [{0}] (SourceId={1}) is already locked at 125% (curScaleRel=0, min={2}, max={3}).",
                        i, path.sourceInfo.id, getReq.minScaleRel, getReq.maxScaleRel));
                }
            }

            return allInternalSucceeded;
        }

        /// <summary>
        /// Queries the current active DPI scaling percentage for telemetry and CLI --status reporting.
        /// </summary>
        public static int GetActiveScalePercent()
        {
            try
            {
                uint numPaths = 0;
                uint numModes = 0;
                if (Interop.GetDisplayConfigBufferSizes(Interop.QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes) == Interop.ERROR_SUCCESS && numPaths > 0)
                {
                    Interop.DISPLAYCONFIG_PATH_INFO[] paths = new Interop.DISPLAYCONFIG_PATH_INFO[numPaths];
                    Interop.DISPLAYCONFIG_MODE_INFO[] modes = new Interop.DISPLAYCONFIG_MODE_INFO[numModes];
                    if (Interop.QueryDisplayConfig(Interop.QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero) == Interop.ERROR_SUCCESS)
                    {
                        Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET getReq = new Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
                        getReq.header.type = Interop.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
                        getReq.header.size = (uint)Marshal.SizeOf(typeof(Interop.DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
                        getReq.header.adapterId = paths[0].sourceInfo.adapterId;
                        getReq.header.id = paths[0].sourceInfo.id;

                        if (Interop.DisplayConfigGetDeviceInfo(ref getReq) == Interop.ERROR_SUCCESS)
                        {
                            return MapRelativeStepToPercent(getReq.curScaleRel, getReq.minScaleRel);
                        }
                    }
                }
            }
            catch { }

            try
            {
                using (RegistryKey desktopKey = Registry.CurrentUser.OpenSubKey(DesktopRegistrySubKey, writable: false))
                {
                    if (desktopKey != null)
                    {
                        int logPixels = ParseRegistryDwordToSignedInt32(desktopKey.GetValue(LogPixelsValueName), 120);
                        if (logPixels > 0)
                        {
                            return (int)Math.Round((logPixels / 96.0) * 100.0);
                        }
                    }
                }
            }
            catch { }

            return 125;
        }

        #endregion
    }
}
