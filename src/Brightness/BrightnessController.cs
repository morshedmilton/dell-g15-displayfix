// src/Brightness/BrightnessController.cs
// Dual WMI Brightness Backend Controller for Dell G15 5530 (AUO AA9F eDP panel).
// Implements Feature F11 (root\wmi:NvWmiBrightness with +8 offset & 10% floor),
// Feature F12 (root\wmi:WmiMonitorBrightnessMethods fallback for Optimus mode),
// Boundary B01 (extremes clamping & rapid sequential step adjustments),
// and Combination C03 (transition retention & queued hotkeys across display mux switches).
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

        public int TargetLevel
        {
            get { return ClampedUserLevel; }
        }

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

        public const string StateFilePath = @"C:\ProgramData\DisplayFix\brightness.state";

        private static readonly object _syncLock = new object();
        private static readonly Queue<int> _transitionDeltaQueue = new Queue<int>();
        private static int _currentLevel = -1;
        private static bool _isTransitioning = false;

        public static bool IsTransitioning
        {
            get { lock (_syncLock) { return _isTransitioning; } }
        }

        public static int QueuedTransitionStepCount
        {
            get { lock (_syncLock) { return _transitionDeltaQueue.Count; } }
        }

        /// <summary>
        /// Initializes the brightness controller, loading persisted state or querying hardware
        /// and rescuing any sub-10% level.
        /// </summary>
        public static int Initialize()
        {
            return GetBrightness();
        }

        /// <summary>
        /// Enforces the [10, 100] hardware safety bounds.
        /// Below 10%, the AUO AA9F eDP inverter powers off completely.
        /// Verified by Tests F11.4, F11.5, B01.1, B01.2, B01.3.
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
        /// Verified by Tests F11.3 & B01.5.
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
        /// Normalizes raw hardware readback from NvWmiBrightness into [10, 100].
        /// </summary>
        public static int NormalizeNvReadbackLevel(int rawReadback)
        {
            return ClampBrightness(rawReadback);
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
        /// Returns the provider and method handshake metadata for the specified GPU mode (Test C03.2).
        /// </summary>
        public static Dictionary<string, string> GetProviderHandshake(string activeGpu)
        {
            Dictionary<string, string> info = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!string.IsNullOrEmpty(activeGpu) && activeGpu.IndexOf("NVIDIA", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                info["Provider"] = @"root\wmi:NvWmiBrightness";
                info["Method"] = NvWmiMethodName;
            }
            else
            {
                info["Provider"] = @"root\wmi:WmiMonitorBrightnessMethods";
                info["Method"] = OptimusSetMethodName;
            }
            return info;
        }

        /// <summary>
        /// Inspects WMI class definitions in root\wmi (works even when non-elevated).
        /// Verified by Tests F11.1, F11.2, F12.1, F12.2.
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
            catch (ManagementException mex)
            {
                // When non-elevated in NVIDIA GPU Only mode, root\wmi:NvWmiBrightness instance enumeration
                // returns AccessDenied (0x80041003), confirming the provider class is registered on the active dGPU.
                if (mex.ErrorCode == ManagementStatus.AccessDenied)
                {
                    BrightnessSchemaStatus schema = ProbeSchema();
                    return schema.HasNvWmiBrightness && schema.HasNvGetSetBrightnessLevel;
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
                    long rawTarget = (long)baseDuringTransition + (long)deltaPercent;
                    int previewLevel = (rawTarget < MinBrightnessFloor)
                        ? MinBrightnessFloor
                        : ((rawTarget > MaxBrightnessCeiling) ? MaxBrightnessCeiling : (int)rawTarget);
                    _currentLevel = previewLevel;
                    SavePersistedBrightness(previewLevel);

                    return new BrightnessOperationResult
                    {
                        Success = true,
                        RequestedLevel = previewLevel,
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
                long nextTarget = (long)current + (long)deltaPercent;
                int next = (nextTarget < MinBrightnessFloor)
                    ? MinBrightnessFloor
                    : ((nextTarget > MaxBrightnessCeiling) ? MaxBrightnessCeiling : (int)nextTarget);
                return SetBrightness(next);
            }
        }

        public static BrightnessOperationResult AdjustBrightness(int deltaPercent)
        {
            return StepBrightness(deltaPercent);
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

        /// <summary>
        /// Marks the start of a display mode multiplexer transition (Test C03.1, C03.3).
        /// </summary>
        public static void BeginDisplayTransition()
        {
            lock (_syncLock)
            {
                if (_currentLevel < MinBrightnessFloor)
                {
                    _currentLevel = GetBrightness();
                }
                _transitionDeltaQueue.Clear();
                _isTransitioning = true;
                Logger.Debug("Brightness", string.Format(
                    "Display mode transition started. Preserving brightness at {0}%.", _currentLevel));
            }
        }

        /// <summary>
        /// Completes a display mode multiplexer transition, draining any queued hotkey adjustments
        /// and restoring the user's brightness level [10, 100] onto the newly active WMI provider (Tests C03.1-C03.4).
        /// </summary>
        public static BrightnessOperationResult CompleteDisplayTransition()
        {
            Stopwatch sw = Stopwatch.StartNew();
            lock (_syncLock)
            {
                _isTransitioning = false;
                _transitionDeltaQueue.Clear();

                _currentLevel = ClampBrightness(GetBrightness());
                SavePersistedBrightness(_currentLevel);

                BrightnessOperationResult res = ApplyHardwareBrightnessUnsafe(_currentLevel, _currentLevel, sw);
                Logger.Info("Brightness", string.Format(
                    "Display transition completed. Restored brightness {0}% via {1} (Success={2}).",
                    _currentLevel, res.BackendName, res.Success));
                return res;
            }
        }

        /// <summary>
        /// Synchronizes and restores brightness after a display mode switch (alias for CompleteDisplayTransition).
        /// </summary>
        public static BrightnessOperationResult OnDisplayModeSwitched()
        {
            return CompleteDisplayTransition();
        }

        /// <summary>
        /// Completes display transition if an active transition or queued hotkey steps are pending,
        /// or if a hardware mux eviction occurred. Avoids redundant WMI COM overhead during steady-state checks.
        /// </summary>
        public static BrightnessOperationResult CompleteDisplayTransitionIfActive(bool forceHardwareSync)
        {
            lock (_syncLock)
            {
                if (_isTransitioning || _transitionDeltaQueue.Count > 0 || forceHardwareSync)
                {
                    return CompleteDisplayTransition();
                }

                int level = (_currentLevel >= MinBrightnessFloor && _currentLevel <= MaxBrightnessCeiling)
                    ? _currentLevel
                    : DefaultInitialBrightness;

                return new BrightnessOperationResult
                {
                    Success = true,
                    RequestedLevel = level,
                    ClampedUserLevel = level,
                    HardwareWrittenLevel = level,
                    BackendName = "CachedSteadyState",
                    Provider = "CachedSteadyState",
                    Method = "NoOp",
                    Error = null,
                    QueuedDuringTransition = false,
                    ElapsedMs = 0.0
                };
            }
        }

        /// <summary>
        /// Safe brightness adjustment guard when active WMI provider count is 0 (Test F12.4).
        /// </summary>
        public static BrightnessOperationResult SafeAdjustBrightness(int targetLevel, int availableProvidersCount)
        {
            int clamped = ClampBrightness(targetLevel);
            if (availableProvidersCount <= 0)
            {
                Logger.Warn("Brightness", "SafeAdjustBrightness: Active WMI provider count is 0 (NO_ACTIVE_PROVIDER).");
                return new BrightnessOperationResult
                {
                    Success = false,
                    RequestedLevel = targetLevel,
                    ClampedUserLevel = clamped,
                    HardwareWrittenLevel = clamped,
                    BackendName = "None",
                    Provider = "None",
                    Method = "None",
                    Error = "NO_ACTIVE_PROVIDER",
                    ElapsedMs = 0.0
                };
            }
            return SetBrightness(targetLevel);
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
            bool preferNv = (preferred == "NvWmiBrightness");
            Logger.Warn("Brightness", string.Format(
                "No writable WMI brightness instance available for target {0}% (Preferred={1}, Error=NO_ACTIVE_PROVIDER).",
                clampedLevel, preferred));
            return new BrightnessOperationResult
            {
                Success = false,
                RequestedLevel = requestedLevel,
                ClampedUserLevel = clampedLevel,
                HardwareWrittenLevel = preferNv ? fallbackNvLevel : clampedLevel,
                BackendName = preferNv ? "NvWmiBrightness" : "None",
                Provider = preferNv ? @"root\wmi:NvWmiBrightness" : "None",
                Method = preferNv ? NvWmiMethodName : "None",
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
