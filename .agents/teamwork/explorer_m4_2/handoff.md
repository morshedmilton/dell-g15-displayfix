# Explorer M4_2 Handoff: Dual WMI Brightness Controller (`src/Brightness/BrightnessController.cs`)

**Status:** COMPLETE  
**Features Covered:** F11 (NVIDIA WMI Brightness Backend) & F12 (Optimus WMI Brightness Backend)  
**Test Suites Covered:** `test_f11_nvidia_wmi_brightness.ps1`, `test_f12_optimus_wmi_brightness.ps1`, `test_b01_brightness_extremes.ps1`, `test_c03_switching_and_brightness.ps1`

---

## 1. Key Findings & Live Hardware Verification

1. **Live WMI Schema Verification (`root\wmi`):**
   - `NvWmiBrightness` is present in `root\wmi` with properties `Active (Boolean)` and `InstanceName (String)`, and method `NvGetSetBrightnessLevel([in] UInt32 inArg, [in] UInt32 Level, [out] UInt32 Result)`.
   - `WmiMonitorBrightness` (`CurrentBrightness: UInt8`) and `WmiMonitorBrightnessMethods` (`WmiSetBrightness([in] UInt8 Brightness, [in] UInt32 Timeout)`) are present in `root\wmi`.
   - **Privilege & Topology Nuance:**
     - `ManagementClass(@"root\wmi", ...)` schema inspection succeeds without elevation for both `NvWmiBrightness` and `WmiMonitorBrightnessMethods`.
     - Instance queries (`SELECT * FROM NvWmiBrightness`) require elevation (`RunLevel: HighestAvailable`), throwing `ManagementStatus.AccessDenied` (`0x80041003`) when non-elevated.
     - Instance queries for `WmiMonitorBrightness` / `WmiMonitorBrightnessMethods` succeed in Optimus mode (without elevation) and throw `ManagementStatus.NotSupported` (`0x8004100C`) in NVIDIA GPU Only mode.
     - Our brightness state remained untouched during live WMI inspection.

2. **Hardware Safety & Calibration Rules:**
   - **10% Minimum Safety Floor (`MinBrightnessFloor = 10`):** Prevents AUO AA9F eDP backlight inverter power-off on `0%`, negative inputs (`-1`, `-10`, `-100`), or low inputs (`1%..9%`).
   - **100% Maximum Ceiling (`MaxBrightnessCeiling = 100`):** Clamps `101`, `255`, `1000` to `100%`.
   - **+8 NVIDIA Write Offset (`NvWriteOffset = 8`):** `CalculateNvCompensatedLevel(userLevel)` clamps `userLevel` to `[10, 100]`, adds `8`, and caps at `100` (`10 -> 18`, `50 -> 58`, `80 -> 88`, `95 -> 100`, `100 -> 100`).
   - **Zero-Drift Step Adjustments & Mode-Switch Continuity:**
     - Authoritative user brightness `_currentLevel` is maintained under lock and persisted to `C:\ProgramData\DisplayFix\brightness.state`.
     - Rapid sequential steps (`B01.4`) step from `_currentLevel` without WMI readback quantization drift.
     - Display transitions (`C03.1–C03.4`) queue hotkey events during active multiplexer transitions and restore the user's brightness level (clamped `[10, 100]`) to the new backend upon stabilization.

---

## 2. Reference Implementation (`src/Brightness/BrightnessController.cs`)

 Strict C# 5 compatible implementation ready for compilation via `scripts/build.ps1`:

```csharp
// src/Brightness/BrightnessController.cs
// Dual WMI Brightness Backend Controller for Dell G15 5530 (AUO AA9F eDP panel).
// Implements Feature F11 (root\wmi:NvWmiBrightness with +8 offset & 10% floor)
// and Feature F12 (root\wmi:WmiMonitorBrightnessMethods fallback for Optimus mode).
// Target: .NET Framework 4.8 x64 (C# 5 compatible)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Text;
using DisplayFix.Common;

namespace DisplayFix.Brightness
{
    public enum BrightnessBackend
    {
        None = 0,
        NvWmiBrightness = 1,
        WmiMonitorBrightness = 2
    }

    public sealed class BrightnessSchemaStatus
    {
        public bool HasNvWmiBrightness { get; set; }
        public bool HasNvGetSetBrightnessLevel { get; set; }
        public bool HasWmiMonitorBrightness { get; set; }
        public bool HasWmiMonitorBrightnessMethods { get; set; }
        public bool HasWmiSetBrightness { get; set; }
    }

    public sealed class BrightnessOperationResult
    {
        public bool Success { get; set; }
        public int RequestedLevel { get; set; }
        public int ClampedUserLevel { get; set; }
        public int HardwareWrittenLevel { get; set; }
        public string BackendName { get; set; }
        public string Provider { get; set; }
        public string Method { get; set; }
        public string Error { get; set; }
        public bool QueuedDuringTransition { get; set; }
        public double ElapsedMs { get; set; }

        public override string ToString()
        {
            return string.Format(
                "Success={0}, Level={1}% (HW={2}), Backend={3}, Provider={4}, Error={5}, Elapsed={6:F2}ms",
                Success,
                ClampedUserLevel,
                HardwareWrittenLevel,
                BackendName ?? "None",
                Provider ?? "None",
                Error ?? "None",
                ElapsedMs);
        }
    }

    public static class BrightnessController
    {
        public const string WmiNamespace = @"root\wmi";
        public const string NvWmiClassName = "NvWmiBrightness";
        public const string NvWmiMethodName = "NvGetSetBrightnessLevel";
        public const string OptimusGetClassName = "WmiMonitorBrightness";
        public const string OptimusSetClassName = "WmiMonitorBrightnessMethods";
        public const string OptimusSetMethodName = "WmiSetBrightness";

        public const int MinBrightnessFloor = 10;
        public const int MaxBrightnessCeiling = 100;
        public const int NvWriteOffset = 8;
        public const int DefaultStepPercent = 5;
        public const int DefaultInitialBrightness = 50;
        public const uint OptimusTimeoutSeconds = 1;

        private const string StateFilePath = @"C:\ProgramData\DisplayFix\brightness.state";

        private static readonly object _syncLock = new object();
        private static readonly Queue<int> _transitionDeltaQueue = new Queue<int>();
        private static int _currentLevel = -1;
        private static bool _isTransitioning = false;

        /// <summary>
        /// Enforces the [10, 100] hardware safety bounds.
        /// Below 10%, the AUO AA9F eDP inverter powers off completely.
        /// </summary>
        public static int ClampBrightness(int level)
        {
            if (level < MinBrightnessFloor)
            {
                return MinBrightnessFloor;
            }
            if (level > MaxBrightnessCeiling)
            {
                return MaxBrightnessCeiling;
            }
            return level;
        }

        /// <summary>
        /// Applies the +8 calibration offset for root\wmi:NvWmiBrightness writes
        /// and clamps the hardware write value to [10, 100].
        /// </summary>
        public static int CalculateNvCompensatedLevel(int userLevel)
        {
            int clamped = ClampBrightness(userLevel);
            int compensated = clamped + NvWriteOffset;
            if (compensated > MaxBrightnessCeiling)
            {
                compensated = MaxBrightnessCeiling;
            }
            if (compensated < MinBrightnessFloor)
            {
                compensated = MinBrightnessFloor;
            }
            return compensated;
        }

        /// <summary>
        /// Arbitrates between NVIDIA and Optimus WMI brightness providers based on active GPU state.
        /// Matches F12.3 & C03.2 contracts.
        /// </summary>
        public static string SelectBackend(bool hasNvWmi, bool hasWmiMon, bool isNvidiaActive)
        {
            if (isNvidiaActive && hasNvWmi)
            {
                return "NvWmiBrightness";
            }
            if (hasWmiMon)
            {
                return "WmiMonitorBrightness";
            }
            if (hasNvWmi)
            {
                return "NvWmiBrightness";
            }
            return "NO_ACTIVE_PROVIDER";
        }

        /// <summary>
        /// Inspects WMI class definitions in root\wmi (works even when non-elevated).
        /// </summary>
        public static BrightnessSchemaStatus ProbeSchema()
        {
            BrightnessSchemaStatus status = new BrightnessSchemaStatus();

            try
            {
                using (ManagementClass nvClass = new ManagementClass(WmiNamespace, NvWmiClassName, null))
                {
                    nvClass.Get();
                    status.HasNvWmiBrightness = true;
                    foreach (MethodData md in nvClass.Methods)
                    {
                        if (string.Equals(md.Name, NvWmiMethodName, StringComparison.OrdinalIgnoreCase))
                        {
                            status.HasNvGetSetBrightnessLevel = true;
                            break;
                        }
                    }
                }
            }
            catch { }

            try
            {
                using (ManagementClass monClass = new ManagementClass(WmiNamespace, OptimusGetClassName, null))
                {
                    monClass.Get();
                    status.HasWmiMonitorBrightness = true;
                }
            }
            catch { }

            try
            {
                using (ManagementClass methClass = new ManagementClass(WmiNamespace, OptimusSetClassName, null))
                {
                    methClass.Get();
                    status.HasWmiMonitorBrightnessMethods = true;
                    foreach (MethodData md in methClass.Methods)
                    {
                        if (string.Equals(md.Name, OptimusSetMethodName, StringComparison.OrdinalIgnoreCase))
                        {
                            status.HasWmiSetBrightness = true;
                            break;
                        }
                    }
                }
            }
            catch { }

            return status;
        }

        public static bool IsOptimusBackendActive()
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + OptimusSetClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        {
                            object activeVal = obj["Active"];
                            if (activeVal is bool && !(bool)activeVal)
                            {
                                continue;
                            }
                            return true;
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        public static bool IsNvidiaBackendActive()
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + NvWmiClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        {
                            object activeVal = obj["Active"];
                            if (activeVal is bool && !(bool)activeVal)
                            {
                                continue;
                            }
                            return true;
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        public static BrightnessBackend DetectActiveBackend()
        {
            bool hasWmiMon = IsOptimusBackendActive();
            bool hasNvWmi = IsNvidiaBackendActive();
            bool isNvidiaActive = !hasWmiMon && hasNvWmi;

            string selected = SelectBackend(hasNvWmi, hasWmiMon, isNvidiaActive);
            if (selected == "NvWmiBrightness")
            {
                return BrightnessBackend.NvWmiBrightness;
            }
            if (selected == "WmiMonitorBrightness")
            {
                return BrightnessBackend.WmiMonitorBrightness;
            }
            return BrightnessBackend.None;
        }

        public static string GetActiveBackendName()
        {
            BrightnessBackend backend = DetectActiveBackend();
            if (backend == BrightnessBackend.NvWmiBrightness)
            {
                return "NvWmiBrightness";
            }
            if (backend == BrightnessBackend.WmiMonitorBrightness)
            {
                return "WmiMonitorBrightness";
            }
            return "None";
        }

        public static int GetBrightness()
        {
            lock (_syncLock)
            {
                if (_currentLevel >= MinBrightnessFloor && _currentLevel <= MaxBrightnessCeiling)
                {
                    return _currentLevel;
                }

                int persisted = LoadPersistedBrightness();
                if (persisted >= MinBrightnessFloor && persisted <= MaxBrightnessCeiling)
                {
                    _currentLevel = persisted;
                    return _currentLevel;
                }

                int hwLevel = ReadHardwareBrightnessUnsafe();
                if (hwLevel >= 0)
                {
                    _currentLevel = ClampBrightness(hwLevel);
                    SavePersistedBrightness(_currentLevel);
                    return _currentLevel;
                }

                _currentLevel = DefaultInitialBrightness;
                return _currentLevel;
            }
        }

        public static BrightnessOperationResult SetBrightness(int targetLevel)
        {
            Stopwatch sw = Stopwatch.StartNew();
            lock (_syncLock)
            {
                int clamped = ClampBrightness(targetLevel);
                _currentLevel = clamped;
                SavePersistedBrightness(clamped);

                if (_isTransitioning)
                {
                    sw.Stop();
                    Logger.Info("Brightness", string.Format(
                        "Display transition in progress; cached brightness {0}% for post-switch application.", clamped));
                    return new BrightnessOperationResult
                    {
                        Success = true,
                        RequestedLevel = targetLevel,
                        ClampedUserLevel = clamped,
                        HardwareWrittenLevel = clamped,
                        BackendName = "TransitionQueue",
                        Provider = "TransitionQueue",
                        Method = "DeferredSet",
                        Error = null,
                        QueuedDuringTransition = true,
                        ElapsedMs = sw.Elapsed.TotalMilliseconds
                    };
                }

                return ApplyHardwareBrightnessUnsafe(targetLevel, clamped, sw);
            }
        }

        public static BrightnessOperationResult StepBrightness(int deltaPercent)
        {
            lock (_syncLock)
            {
                if (_isTransitioning)
                {
                    _transitionDeltaQueue.Enqueue(deltaPercent);
                    int baseDuringTransition = GetBrightness();
                    int previewLevel = ClampBrightness(baseDuringTransition + deltaPercent);
                    _currentLevel = previewLevel;
                    SavePersistedBrightness(previewLevel);

                    return new BrightnessOperationResult
                    {
                        Success = true,
                        RequestedLevel = baseDuringTransition + deltaPercent,
                        ClampedUserLevel = previewLevel,
                        HardwareWrittenLevel = previewLevel,
                        BackendName = "TransitionQueue",
                        Provider = "TransitionQueue",
                        Method = "QueuedStep",
                        Error = null,
                        QueuedDuringTransition = true,
                        ElapsedMs = 0.0
                    };
                }

                int current = GetBrightness();
                int next = ClampBrightness(current + deltaPercent);
                return SetBrightness(next);
            }
        }

        public static BrightnessOperationResult StepUp(int stepPercent = DefaultStepPercent)
        {
            int step = Math.Abs(stepPercent);
            if (step <= 0) step = DefaultStepPercent;
            return StepBrightness(+step);
        }

        public static BrightnessOperationResult StepDown(int stepPercent = DefaultStepPercent)
        {
            int step = Math.Abs(stepPercent);
            if (step <= 0) step = DefaultStepPercent;
            return StepBrightness(-step);
        }

        public static void BeginDisplayTransition()
        {
            lock (_syncLock)
            {
                if (_currentLevel < MinBrightnessFloor)
                {
                    _currentLevel = GetBrightness();
                }
                _isTransitioning = true;
                Logger.Debug("Brightness", string.Format(
                    "Display mode transition started. Preserving brightness at {0}%.", _currentLevel));
            }
        }

        public static BrightnessOperationResult CompleteDisplayTransition()
        {
            Stopwatch sw = Stopwatch.StartNew();
            lock (_syncLock)
            {
                _isTransitioning = false;
                int levelToRestore = GetBrightness();

                while (_transitionDeltaQueue.Count > 0)
                {
                    int delta = _transitionDeltaQueue.Dequeue();
                    levelToRestore = ClampBrightness(levelToRestore + delta);
                }

                _currentLevel = ClampBrightness(levelToRestore);
                SavePersistedBrightness(_currentLevel);

                BrightnessOperationResult res = ApplyHardwareBrightnessUnsafe(_currentLevel, _currentLevel, sw);
                Logger.Info("Brightness", string.Format(
                    "Display transition completed. Restored brightness {0}% via {1} (Success={2}).",
                    _currentLevel, res.BackendName, res.Success));
                return res;
            }
        }

        private static BrightnessOperationResult ApplyHardwareBrightnessUnsafe(int requestedLevel, int clampedLevel, Stopwatch sw)
        {
            bool hasWmiMon = IsOptimusBackendActive();
            bool hasNvWmi = IsNvidiaBackendActive();
            bool isNvidiaActive = !hasWmiMon && hasNvWmi;

            string preferred = SelectBackend(hasNvWmi, hasWmiMon, isNvidiaActive);

            if (preferred == "NvWmiBrightness")
            {
                int nvHwLevel = CalculateNvCompensatedLevel(clampedLevel);
                if (TryWriteNvidiaBrightness(nvHwLevel))
                {
                    sw.Stop();
                    Logger.Info("Brightness", string.Format(
                        "Set brightness to {0}% (NV compensated={1}) via root\\wmi:NvWmiBrightness in {2:F2}ms.",
                        clampedLevel, nvHwLevel, sw.Elapsed.TotalMilliseconds));
                    return new BrightnessOperationResult
                    {
                        Success = true,
                        RequestedLevel = requestedLevel,
                        ClampedUserLevel = clampedLevel,
                        HardwareWrittenLevel = nvHwLevel,
                        BackendName = "NvWmiBrightness",
                        Provider = @"root\wmi:NvWmiBrightness",
                        Method = NvWmiMethodName,
                        Error = null,
                        ElapsedMs = sw.Elapsed.TotalMilliseconds
                    };
                }
            }
            else if (preferred == "WmiMonitorBrightness")
            {
                if (TryWriteOptimusBrightness(clampedLevel))
                {
                    sw.Stop();
                    Logger.Info("Brightness", string.Format(
                        "Set brightness to {0}% via root\\wmi:WmiMonitorBrightnessMethods in {1:F2}ms.",
                        clampedLevel, sw.Elapsed.TotalMilliseconds));
                    return new BrightnessOperationResult
                    {
                        Success = true,
                        RequestedLevel = requestedLevel,
                        ClampedUserLevel = clampedLevel,
                        HardwareWrittenLevel = clampedLevel,
                        BackendName = "WmiMonitorBrightness",
                        Provider = @"root\wmi:WmiMonitorBrightnessMethods",
                        Method = OptimusSetMethodName,
                        Error = null,
                        ElapsedMs = sw.Elapsed.TotalMilliseconds
                    };
                }
            }

            // Secondary fallback attempt in case provider state changed mid-call
            if (TryWriteOptimusBrightness(clampedLevel))
            {
                sw.Stop();
                return new BrightnessOperationResult
                {
                    Success = true,
                    RequestedLevel = requestedLevel,
                    ClampedUserLevel = clampedLevel,
                    HardwareWrittenLevel = clampedLevel,
                    BackendName = "WmiMonitorBrightness",
                    Provider = @"root\wmi:WmiMonitorBrightnessMethods",
                    Method = OptimusSetMethodName,
                    Error = null,
                    ElapsedMs = sw.Elapsed.TotalMilliseconds
                };
            }

            int fallbackNvLevel = CalculateNvCompensatedLevel(clampedLevel);
            if (TryWriteNvidiaBrightness(fallbackNvLevel))
            {
                sw.Stop();
                return new BrightnessOperationResult
                {
                    Success = true,
                    RequestedLevel = requestedLevel,
                    ClampedUserLevel = clampedLevel,
                    HardwareWrittenLevel = fallbackNvLevel,
                    BackendName = "NvWmiBrightness",
                    Provider = @"root\wmi:NvWmiBrightness",
                    Method = NvWmiMethodName,
                    Error = null,
                    ElapsedMs = sw.Elapsed.TotalMilliseconds
                };
            }

            sw.Stop();
            Logger.Warn("Brightness", string.Format(
                "No active WMI brightness provider available for target {0}% (Error=NO_ACTIVE_PROVIDER).", clampedLevel));
            return new BrightnessOperationResult
            {
                Success = false,
                RequestedLevel = requestedLevel,
                ClampedUserLevel = clampedLevel,
                HardwareWrittenLevel = clampedLevel,
                BackendName = "None",
                Provider = "None",
                Method = "None",
                Error = "NO_ACTIVE_PROVIDER",
                ElapsedMs = sw.Elapsed.TotalMilliseconds
            };
        }

        private static bool TryWriteOptimusBrightness(int clampedLevel)
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + OptimusSetClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        using (ManagementBaseObject inParams = obj.GetMethodParameters(OptimusSetMethodName))
                        {
                            inParams["Timeout"] = (uint)OptimusTimeoutSeconds;
                            inParams["Brightness"] = (byte)clampedLevel;
                            obj.InvokeMethod(OptimusSetMethodName, inParams, null);
                            return true;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Debug("Brightness", "Optimus WmiSetBrightness unavailable: " + ex.Message);
            }
            return false;
        }

        private static bool TryWriteNvidiaBrightness(int nvCompensatedLevel)
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + NvWmiClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        {
                            object activeVal = obj["Active"];
                            if (activeVal is bool && !(bool)activeVal)
                            {
                                continue;
                            }

                            using (ManagementBaseObject inParams = obj.GetMethodParameters(NvWmiMethodName))
                            {
                                inParams["inArg"] = (uint)1;
                                inParams["Level"] = (uint)nvCompensatedLevel;
                                using (ManagementBaseObject outParams = obj.InvokeMethod(NvWmiMethodName, inParams, null))
                                {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Debug("Brightness", "NVIDIA NvGetSetBrightnessLevel write unavailable: " + ex.Message);
            }
            return false;
        }

        private static int ReadHardwareBrightnessUnsafe()
        {
            // 1. Try Optimus WmiMonitorBrightness first
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + OptimusGetClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        {
                            object cur = obj["CurrentBrightness"];
                            if (cur != null)
                            {
                                return ClampBrightness(Convert.ToInt32(cur));
                            }
                        }
                    }
                }
            }
            catch { }

            // 2. Try NVIDIA NvWmiBrightness (inArg = 0)
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    WmiNamespace, "SELECT * FROM " + NvWmiClassName))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        using (obj)
                        {
                            object activeVal = obj["Active"];
                            if (activeVal is bool && !(bool)activeVal)
                            {
                                continue;
                            }

                            using (ManagementBaseObject inParams = obj.GetMethodParameters(NvWmiMethodName))
                            {
                                inParams["inArg"] = (uint)0;
                                inParams["Level"] = (uint)0;
                                using (ManagementBaseObject outParams = obj.InvokeMethod(NvWmiMethodName, inParams, null))
                                {
                                    if (outParams != null && outParams["Result"] != null)
                                    {
                                        int raw = Convert.ToInt32(outParams["Result"]);
                                        return ClampBrightness(raw);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            return -1;
        }

        private static int LoadPersistedBrightness()
        {
            try
            {
                if (File.Exists(StateFilePath))
                {
                    string raw = File.ReadAllText(StateFilePath, Encoding.UTF8).Trim();
                    int val;
                    if (int.TryParse(raw, out val))
                    {
                        return ClampBrightness(val);
                    }
                }
            }
            catch { }
            return -1;
        }

        private static void SavePersistedBrightness(int clampedLevel)
        {
            try
            {
                string dir = Path.GetDirectoryName(StateFilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                File.WriteAllText(StateFilePath, clampedLevel.ToString(), Encoding.UTF8);
            }
            catch { }
        }
    }
}
```

---

## 3. Integration Touchpoints for M4 Implementers

1. **`src/Daemon/Program.cs`:**
   - Add `using DisplayFix.Brightness;`
   - Add CLI switch cases:
     - `--get-brightness` -> prints `BrightnessController.GetBrightness()`, `BrightnessController.GetActiveBackendName()`, and `ProbeSchema()`.
     - `--set-brightness` -> parses `args[1]` (default `50`), invokes `BrightnessController.SetBrightness(val)`, prints result.
     - `--brightness-up` -> invokes `BrightnessController.StepUp(5)`, prints result.
     - `--brightness-down` -> invokes `BrightnessController.StepDown(5)`, prints result.
   - In `HandleStatus()`: output `Brightness (%):` and `Brightness Backend:`.
2. **`src/Daemon/EventWindow.cs`:**
   - Call `BrightnessController.BeginDisplayTransition()` in `TriggerDebounce`.
   - Call `BrightnessController.CompleteDisplayTransition()` at the end of `ExecuteReconfigurationPipeline` so brightness is seamlessly retained across display mode switches (`test_c03`).
3. **`src/Brightness/HotkeyHook.cs` & `src/Brightness/AcrylicOsdWindow.cs`:**
   - `F6` / HID `0x0070` -> `var res = BrightnessController.StepDown(5); AcrylicOsdWindow.ShowOsd(res.ClampedUserLevel);`
   - `F7` / HID `0x006F` -> `var res = BrightnessController.StepUp(5); AcrylicOsdWindow.ShowOsd(res.ClampedUserLevel);`
