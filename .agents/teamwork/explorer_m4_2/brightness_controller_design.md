# Milestone 4 Design Specification: Dual WMI Brightness Controller (`src/Brightness/BrightnessController.cs`)

**Explorer:** `explorer_m4_2`  
**Scope:** Feature F11 (NVIDIA WMI Brightness Backend) & Feature F12 (Optimus WMI Brightness Backend), plus Tier 2 Boundary Clamping (`B01`) and Tier 3 Mode-Switch Continuity (`C03`)  
**Target Runtime:** .NET Framework 4.8 x64, strict C# 5 syntax (`csc.exe /r:System.Management.dll`)

---

## 1. Live Hardware & WMI Schema Verification Summary

Live WMI queries executed against the Dell G15 5530 (`root\wmi`) confirmed the exact schema, parameter types, and runtime error codes across display topologies:

### 1.1 `root\wmi:NvWmiBrightness` (Feature F11 — NVIDIA GPU Only Backend)
- **Properties:**
  - `Active` (`Boolean`)
  - `InstanceName` (`String`, e.g., `ACPI\NVDA0820\...`)
- **Methods:**
  - `NvGetSetBrightnessLevel`:
    - `[in] uint32 inArg`: `0` = Query current brightness level; `1` = Set brightness level
    - `[in] uint32 Level`: Target brightness level (`0` when querying; `10..100` when writing)
    - `[out] uint32 Result`: Returned brightness percentage (`0..100`)
  - `NvGetSetBrightnessSource`:
    - `[in] uint32 inArg0`, `[in] uint32 inArg1`, `[out] uint32 Result`
- **Hardware Calibration & Security Behavior:**
  - **Write Offset (`+8`):** Writing `X` to `NvGetSetBrightnessLevel(1, X)` drives the AUO AA9F eDP backlight at `X - 8` on readback (`100 -> 92`, `50 -> 42`). Without compensation, requesting `10%` drives the panel at `2%`, shutting off the eDP backlight inverter completely.
  - **Compensated Write Formula:** `nvLevel = Math.Min(100, Clamp(userLevel, 10, 100) + 8)` (`10% -> 18`, `50% -> 58`, `80% -> 88`, `95% -> 100`, `100% -> 100`).
  - **Elevation Requirement:** Schema inspection (`ManagementClass("root\\wmi", "NvWmiBrightness", null)`) succeeds at any privilege level, whereas instance enumeration/invocation (`SELECT * FROM NvWmiBrightness`) requires `RunLevel: HighestAvailable` (throws `ManagementException` with `ManagementStatus.AccessDenied` / `0x80041003` when non-elevated).

### 1.2 `root\wmi:WmiMonitorBrightness` & `WmiMonitorBrightnessMethods` (Feature F12 — Optimus / iGPU Backend)
- **`WmiMonitorBrightness` Properties:**
  - `Active` (`Boolean`)
  - `CurrentBrightness` (`UInt8` / `byte`)
  - `InstanceName` (`String`)
  - `Level` (`UInt8[]`), `Levels` (`UInt32`)
- **`WmiMonitorBrightnessMethods` Methods:**
  - `WmiSetBrightness`:
    - `[in] uint32 Timeout`: `1` second (per `PROJECT.md` §4 & `test_f12_optimus_wmi_brightness.ps1` F12.5)
    - `[in] uint8 Brightness`: Clamped user level `(byte)Clamp(userLevel, 10, 100)` (1:1 round-trip, no offset needed)
- **Mode Behavior:**
  - In **Optimus** mode (Intel iGPU driving eDP panel), `WmiMonitorBrightness` and `WmiMonitorBrightnessMethods` return 1 active instance and adjust the physical backlight in ~5ms without requiring elevation.
  - In **NVIDIA GPU Only** mode (after `GhostEvictionEngine` disables the unclocked Intel eDP node), querying `WmiMonitorBrightness` or `WmiMonitorBrightnessMethods` throws `ManagementException` (`ManagementStatus.NotSupported` / `0x8004100C`).

---

## 2. Requirements & E2E Test Matrix Traceability

| Test ID | Requirement Assertion | Design Implementation in `BrightnessController` |
|---|---|---|
| **F11.1** | `root\wmi:NvWmiBrightness` class exists in WMI namespace | `ProbeWmiSchema()` verifies `ManagementClass(@"root\wmi", "NvWmiBrightness", null)` |
| **F11.2** | `NvGetSetBrightnessLevel` accepts `inArg` (`UInt32`) and `Level` (`UInt32`) | `SetNvidiaBrightness(int userLevel)` & `GetNvidiaBrightness()` bind `inParams["inArg"] = (uint)1` and `inParams["Level"] = (uint)nvLevel` |
| **F11.3** | Calibration write offset (`+8` compensation): `50->58`, `80->88`, `95->100` | `CalculateNvCompensatedLevel(int userLevel)` computes `Math.Min(100, ClampBrightness(userLevel) + 8)` |
| **F11.4** | Safety floor clamping (`0->10`, `5->10`, `-10->10`, `10->10`) | `ClampBrightness(int level)` enforces `MinSafeBrightness = 10` |
| **F11.5** | Safety ceiling clamping (`100->100`, `105->100`, `255->100`) | `ClampBrightness(int level)` enforces `MaxBrightness = 100` |
| **F12.1** | `WmiMonitorBrightnessMethods` schema & `WmiSetBrightness` method exist | `ProbeWmiSchema()` verifies `ManagementClass(@"root\wmi", "WmiMonitorBrightnessMethods", null)` |
| **F12.2** | `WmiSetBrightness` parameters (`Timeout: uint32`, `Brightness: uint8`) | `SetOptimusBrightness(int userLevel)` sets `inParams["Timeout"] = (uint)1` and `inParams["Brightness"] = (byte)clampedLevel` |
| **F12.3** | Dynamic backend selector arbitrator (`NvWmiBrightness` vs `WmiMonitorBrightness`) | `SelectBackend(bool hasNvWmi, bool hasWmiMon, bool isNvidiaActive)` prefers `NvWmiBrightness` when `isNvidiaActive && hasNvWmi`, else `WmiMonitorBrightness` when `hasWmiMon`, else fallback |
| **F12.4** | Safe handling when active WMI provider count drops to 0 (`NO_ACTIVE_PROVIDER`) | `SetBrightness` / `AdjustBrightness` catches `ManagementException`, logs warning, never throws unhandled exceptions, and returns `BrightnessResult { Success = false, Error = "NO_ACTIVE_PROVIDER" }` |
| **F12.5** | `WmiSetBrightness` timeout parameter contract (`Timeout = 1` sec) | `public const uint OptimusTimeoutSeconds = 1;` passed as `(uint)OptimusTimeoutSeconds` |
| **B01.1–B01.3** | Negative (`-100`, `-1`), zero (`0%`), and overflow (`101`, `255`, `1000`) clamped to `[10, 100]` | `ClampBrightness(int level)` handles all `int` extremes (`int.MinValue .. int.MaxValue`) |
| **B01.4** | 20 rapid sequential step adjustments in 100ms without quantization drift | Authoritative `_currentBrightness` state updated atomically under `_syncLock` (`_currentBrightness = ClampBrightness(_currentBrightness + delta)`) before dispatching WMI write |
| **B01.5** | `+8` write offset does not overflow 100 (`95->100`, `100->100`, `10->18`) | `CalculateNvCompensatedLevel(int target)` clamps `clampedTarget + 8` at `100` |
| **C03.1** | Brightness level retained across display mode transitions (no sudden 100% blast) | `_currentBrightness` persisted in memory and `C:\ProgramData\DisplayFix\brightness.state`; `SyncBrightnessAfterModeSwitch()` re-applies retained level |
| **C03.2** | Provider transitions cleanly between `WmiMonitorBrightnessMethods` and `NvWmiBrightness` | `GetProviderHandshake(string activeGpu)` and live re-detection on every operation |
| **C03.3** | Hotkey pressed during active multiplexer transition is queued and processed after stabilization | `BeginTransition()` / `EndTransition()` queues hotkey deltas (`_transitionQueue`) during DDS switch and flushes on stabilization |
| **C03.4** | Safe 10% floor preserved throughout backend handoff | `SyncBrightnessAfterModeSwitch()` clamps retained/restored brightness to `[10, 100]` |

---

## 3. Class & API Design (`src/Brightness/BrightnessController.cs`)

### 3.1 Data Structures

```csharp
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
        public bool HasNvWmiBrightnessClass { get; set; }
        public bool HasNvGetSetMethod { get; set; }
        public bool HasWmiMonitorBrightnessClass { get; set; }
        public bool HasWmiMonitorMethodsClass { get; set; }
        public bool HasWmiSetBrightnessMethod { get; set; }
    }

    public sealed class BrightnessOperationResult
    {
        public bool Success { get; set; }
        public int RequestedLevel { get; set; }
        public int ClampedUserLevel { get; set; }
        public int HardwareWrittenLevel { get; set; }
        public string BackendName { get; set; }
        public string ProviderPath { get; set; }
        public string MethodName { get; set; }
        public string Error { get; set; }
        public double ElapsedMs { get; set; }
    }
}
```

### 3.2 Core Methods in `BrightnessController`

1. **Clamping & Offset Pure Functions:**
   - `public static int ClampBrightness(int level)`:
     ```csharp
     if (level < MinBrightnessFloor) return MinBrightnessFloor; // 10
     if (level > MaxBrightnessCeiling) return MaxBrightnessCeiling; // 100
     return level;
     ```
   - `public static int CalculateNvCompensatedLevel(int userLevel)`:
     ```csharp
     int clamped = ClampBrightness(userLevel);
     int compensated = clamped + NvWriteOffset; // +8
     if (compensated > MaxBrightnessCeiling) compensated = MaxBrightnessCeiling;
     if (compensated < MinBrightnessFloor) compensated = MinBrightnessFloor;
     return compensated;
     ```
   - `public static int NormalizeNvReadbackLevel(int rawReadback)`:
     - When reading raw hardware level from `NvGetSetBrightnessLevel(0, 0)`, if we don't yet have a cached user target, maps raw readback `rawReadback` into `[10, 100]`. Once the controller sets a level, `_currentLevel` tracks the exact user percentage so `GetBrightness()` and sequential `StepBrightness()` calls never suffer from `-8` readback drift.

2. **Dynamic Backend Arbitrator (`SelectBackend` & Live Probe):**
   - `public static string SelectBackend(bool hasNvWmi, bool hasWmiMon, bool isNvidiaActive)`:
     - Matches `test_f12_optimus_wmi_brightness.ps1` (F12.3):
       ```csharp
       if (isNvidiaActive && hasNvWmi) return "NvWmiBrightness";
       if (hasWmiMon) return "WmiMonitorBrightness";
       if (hasNvWmi) return "NvWmiBrightness";
       return "NO_ACTIVE_PROVIDER";
       ```
   - Live detection (`DetectActiveBackend()`):
     - Checks if NVIDIA is driving the internal panel (or if `WmiMonitorBrightnessMethods` has 0 active instances) and probes `WmiMonitorBrightnessMethods` and `NvWmiBrightness` instances in `root\wmi`.
     - If `isNvidiaActive` and `NvWmiBrightness` has an active instance (`Active == true`), selects `BrightnessBackend.NvWmiBrightness`.
     - Else if `WmiMonitorBrightnessMethods` has an active instance, selects `BrightnessBackend.WmiMonitorBrightness`.
     - Else if `NvWmiBrightness` has an active instance, selects `BrightnessBackend.NvWmiBrightness`.
     - Otherwise returns `BrightnessBackend.None`.

3. **Hardware Read & Write Operations:**
   - `public static int GetBrightness()`:
     - Returns the authoritative clamped brightness `[10, 100]`.
     - On first call (when `_currentLevel < 0`), attempts to read from persisted state (`C:\ProgramData\DisplayFix\brightness.state`), then queries Optimus `WmiMonitorBrightness.CurrentBrightness` or NVIDIA `NvWmiBrightness.NvGetSetBrightnessLevel(0, 0)`, clamping any result to `[10, 100]` (defaulting to `50` if no provider is readable).
   - `public static BrightnessOperationResult SetBrightness(int targetLevel)`:
     - Clamps `targetLevel` to `[10, 100]`.
     - Updates `_currentLevel = clamped` and saves to `C:\ProgramData\DisplayFix\brightness.state`.
     - If `_isTransitioning` is true (during a display mux switch), enqueues the target brightness for post-stabilization flush and returns immediately so the UI/OSD never stalls.
     - Selects active backend:
       - **NVIDIA (`NvWmiBrightness`):** Invokes `NvGetSetBrightnessLevel` with `inArg = (uint)1`, `Level = (uint)CalculateNvCompensatedLevel(clamped)`.
       - **Optimus (`WmiMonitorBrightnessMethods`):** Invokes `WmiSetBrightness` with `Timeout = (uint)1`, `Brightness = (byte)clamped`.
       - **Fallback:** If the primary selected backend fails with a `ManagementException`, automatically tries the alternate backend before returning `Error = "NO_ACTIVE_PROVIDER"`.
   - `public static BrightnessOperationResult StepBrightness(int deltaPercent)`:
     - Thread-safe atomic step from `_currentLevel`:
       ```csharp
       int baseLevel = GetBrightness();
       int nextLevel = ClampBrightness(baseLevel + deltaPercent);
       return SetBrightness(nextLevel);
       ```
   - `public static BrightnessOperationResult StepUp(int step = DefaultStepPercent)` -> `StepBrightness(+Math.Abs(step))`
   - `public static BrightnessOperationResult StepDown(int step = DefaultStepPercent)` -> `StepBrightness(-Math.Abs(step))`

4. **Mode-Switch Continuity (`EventWindow` Integration for `C03`):**
   - `public static void NotifyTransitionStarted()`:
     - Sets `_isTransitioning = true`, snapshots `_currentLevel` (clamped `[10, 100]`).
   - `public static BrightnessOperationResult NotifyTransitionCompleted()`:
     - Sets `_isTransitioning = false`, drains any queued hotkey step events from `_transitionQueue`, and re-applies `_currentLevel` to the newly active WMI backend so switching between Optimus and NVIDIA GPU Only never resets brightness to 100% or drops below 10%.

---

## 4. CLI & Daemon Integration Contracts

### 4.1 `Program.cs` CLI Flags
`DisplayFixDaemon.exe` will support the following CLI commands for automated verification and user diagnostics:
- `--get-brightness`: Outputs current brightness (`10..100%`), active backend (`NvWmiBrightness` / `WmiMonitorBrightness` / `None`), and WMI class schema status.
- `--set-brightness <level>`: Sets brightness to `<level>` (clamped to `[10, 100]`), prints `ClampedUserLevel`, `HardwareWrittenLevel`, and `BackendName`.
- `--brightness-up [step]`: Increments brightness by `step` (default `5`), prints updated brightness.
- `--brightness-down [step]`: Decrements brightness by `step` (default `5`), prints updated brightness.
- `--status`: Includes `Brightness (%):` and `Brightness Backend:` lines in the status telemetry output.

### 4.2 Integration with `HotkeyHook.cs` (F10) and `AcrylicOsdWindow.cs` (F14)
- When `HotkeyHook` intercepts `VK_F6` (Brightness Down) or HID Consumer Usage `0x0070`:
  - Calls `BrightnessOperationResult res = BrightnessController.StepDown(5);`
  - Calls `AcrylicOsdWindow.ShowOsd(res.ClampedUserLevel, res.BackendName);`
- When `HotkeyHook` intercepts `VK_F7` (Brightness Up) or HID Consumer Usage `0x006F`:
  - Calls `BrightnessOperationResult res = BrightnessController.StepUp(5);`
  - Calls `AcrylicOsdWindow.ShowOsd(res.ClampedUserLevel, res.BackendName);`

### 4.3 Integration with `EventWindow.cs` Reconfiguration Pipeline
- In `EventWindow.TriggerDebounce`: calls `BrightnessController.NotifyTransitionStarted()`.
- At the end of `EventWindow.ExecuteReconfigurationPipeline`: calls `BrightnessController.NotifyTransitionCompleted()` as Step 4 (or post-pipeline hook) to ensure the user's brightness level is seamlessly transferred to the new GPU's WMI provider.
