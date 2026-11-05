# Handoff Report: 100-Switch Stress Test Harness Architecture (Feature F03)

**Agent**: Explorer M1_3  
**Milestone**: M1 (Diagnostics, Telemetry & Stress Harness)  
**Deliverable**: Architecture & Implementation Specification for `scripts/diagnostics/stress_test.ps1`  
**Date**: 2026-11-05T17:05:00Z  
**Recipient**: Sub-Orchestrator M1 (`1fa2c640-1687-4d63-a802-a810e6d0f6c0`)  

---

## 1. Observation

Direct empirical observations collected on the target platform (Dell G15 5530):
- **Hardware Profile**:
  - Intel Core i7-13650HX with Intel UHD Graphics (Driver 32.0.101.7088).
  - NVIDIA GeForce RTX 4060 Laptop GPU (Driver 32.0.16.2101).
  - AU Optronics AUO AA9F internal 1080p eDP panel.
  - Active display configuration: 1920x1080 @ 360Hz (`dmDisplayFrequency = 360`), driven directly by NVIDIA dGPU (`PCI\VEN_10DE&DEV_28E0`).
- **DWM Baseline Telemetry**:
  - `dwm.exe` active PID: `2332`.
  - WorkingSet: ~116 MB to 121.6 MB (`WorkingSet64 = 121,638,912 bytes`).
  - PagedMemorySize: ~347 MB (`PagedMemorySize64 = 347,242,496 bytes`).
  - HandleCount: `1,846`.
  - Process ownership: Runs under `Window Manager\DWM-1` service account in Session 1.
- **Process Security Constraint**:
  - Non-elevated calls to `OpenProcess(0x0400, ...)` or `OpenProcess(0x1000, ...)` on `dwm.exe` return `0` with `LastError = 5` (`ERROR_ACCESS_DENIED`).
  - `GetGuiResources(hProc, GR_GDIOBJECTS)` and `GetGuiResources(hProc, GR_USEROBJECTS)` require an elevated administrator token.
  - In contrast, `Process.HandleCount`, `Process.WorkingSet64`, and `Process.PagedMemorySize64` are accessible without elevation via standard Windows performance counters and `NtQuerySystemInformation`.
- **Event Log Query Benchmarks**:
  - Querying System Log for Provider `Display`/`nvlddmkm` and `Id = 4101` with `StartTime` takes ~122ms.
  - Querying Application Log for Provider `Application Error` and `Id = 1000` with `StartTime` takes ~34ms.
  - Both queries return 0 events in the last 24h/7d on the clean machine.
- **Display Scaling & CCD Topology State**:
  - `EnumDisplaySettings` confirms `dmDisplayFrequency = 360`.
  - `GetDpiForSystem()` returns `96` (100% scale) when driven by NVIDIA GPU because `HKCU:\Control Panel\Desktop\PerMonitorSettings\AUOAA9F0_..._10DE_28E0_...` has `DpiValue = -1` (100%), while the Intel branch has `DpiValue = 0` (125%).
  - CCD buffer queries report `ActivePaths = 1` and `AllPaths = 44`.
- **DwmFlush API**:
  - `[DllImport("dwmapi.dll")] DwmFlush()` returns `0x00000000` (S_OK) in user mode without requiring elevation, providing an instant synchronous barrier for desktop swapchain presentation.

---

## 2. Logic Chain

1. **Defect Mechanism**:
   - Advanced Optimus display switches or Intel adapter re-enumerations destroy and re-create DXGI presentation swapchains.
   - If an application holds stale Device Contexts (`HDC`) or if DWM queues unpresented frames across disconnected display heads, handles and working set memory leak monotonically.
2. **Stress Harness Requirement**:
   - To validate R1 and R5, an automated test must support running up to 100 consecutive switches, tracking whether resource growth is bounded ($\le 50$ handles, $\le 30$ MB WS, 0 TDRs, 0 crashes) and verifying that 360Hz refresh rate and 125% DPI persist across every single switch.
3. **Execution Modes**:
   - To allow testing in both non-disruptive CI/headless environments and true hardware soak environments, the harness must support multiple switching modes:
     - `Simulated`: DwmFlush synchronization and benign setting refresh (zero screen flicker, safe for automated test runs).
     - `CcdCycle`: Win32 `SetDisplayConfig` with `SDC_TOPOLOGY_INTERNAL | SDC_APPLY` (exercises Windows CCD mode negotiation).
     - `DevNodeCycle`: CfgMgr32 cycling of the Intel adapter (simulates true Advanced Optimus ghost eviction).
     - `Passive`: Listens for user-initiated switches via NVIDIA App / Control Panel.
4. **Leak Evaluation Math**:
   - Simple delta ($\text{Final} - \text{Initial}$) is vulnerable to random OS memory fluctuations (GC/compaction noise), especially on short runs ($N = 10$).
   - Applying Ordinary Least Squares (OLS) linear regression calculates the true growth slope ($\beta$) and correlation coefficient ($R^2$). A genuine leak produces $\beta > 0$ with $R^2 \ge 0.70$, while harmless oscillation produces $\beta \approx 0$ or low $R^2$.
   - Combining pro-rated delta bounds ($\max(5.0, 30.0 \times N/100)$ MB) with projected 100-switch slope ($\beta \times 100 \le 30$ MB) provides an exact mathematical leak verdict.
5. **Safety Aborts (Circuit Breakers)**:
   - If `dwm.exe` terminates (PID changes), if a TDR occurs (Event ID 4101), if WorkingSet exceeds 500 MB, or if 3 consecutive iterations fail, the harness immediately breaks the loop to safeguard system stability.

---

## 3. Caveats

- **Elevation Boundary for GDI/USER Handles**:
  - Full GDI and USER handle extraction (`GetGuiResources`) requires running PowerShell as Administrator. When running as a standard user, the script gracefully falls back to `Process.HandleCount`, which is fully sufficient for leak slope detection.
- **Physical Mux Switching Automation**:
  - True hardware DDS multiplexer switching between Optimus and dGPU Only is governed by NVIDIA's proprietary driver layer (`nvlddmkm.sys` / `NVPCF`). No public Win32 API can programmatically force the physical multiplexer lines without interacting with the NVIDIA driver. Hence, `stress_test.ps1` supports `Passive` mode for physical soak validation, `DevNodeCycle` for Intel ghost recreation, and `CcdCycle`/`Simulated` for automated testing.
- **Background OS Workloads**:
  - Running heavy external applications (e.g., video editing or 3D games) during the stress test can introduce memory noise. The verification guide should instruct running the stress test on a quiescent desktop.

---

## 4. Conclusion

The technical architecture and complete implementation specification for `scripts/diagnostics/stress_test.ps1` (Feature F03) is fully established and documented in `analysis_stress_test.md`.

Key architectural specifications:
- **CLI Interface**: Parameterized with `-Iterations` (default 10, max 1000), `-Mode` (`Simulated`, `CcdCycle`, `DevNodeCycle`, `Passive`, `Auto`), `-SettleDelayMs` (default 1000ms), `-CooldownMs` (default 1500ms), `-MaxWorkingSetDeltaMB` (30.0), `-MaxHandleDelta` (50), `-OutputDir`, `-Json`, and `-PassThru`.
- **Safety**: 5 circuit breakers preventing runaway execution; non-disruptive `Simulated` mode for automated CI.
- **Leak Detection**: Dual-layer verification utilizing pro-rated Delta limits and OLS linear regression slope/determination math.
- **Audit Reporting**: Automated generation of machine-parseable JSON and human-readable Markdown reports containing timestamped per-iteration logs.
- **Integrations**: Seamlessly complements `probe_system.ps1` (F01) and `dwm_health.ps1` (F02), and directly serves Tier 5 E2E soak testing.

---

## 5. Verification Method

To independently verify the architecture and telemetry probes:

1. **Verify DWM Baseline Probing**:
   ```powershell
   Get-Process -Name dwm | Select-Object Id, WorkingSet64, PagedMemorySize64, HandleCount
   ```
2. **Verify Event Log Query Speed & Accuracy**:
   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue
   Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'dwm\.exe' }
   ```
3. **Verify Display Refresh Rate & Scaling Detection**:
   ```powershell
   Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class Dpi { [DllImport("user32.dll")] public static extern uint GetDpiForSystem(); }'
   [Dpi]::GetDpiForSystem() # Returns 96 (100%) or 120 (125%)
   ```
4. **Verify Linear Regression Slope Math**:
   ```powershell
   # Test script block defined in analysis_stress_test.md Section 10 verifies Get-LinearSlope with double[] array
   ```
5. **Inspect Artifacts**:
   - Architecture Report: `.agents/teamwork/explorer_m1_3/analysis_stress_test.md`
   - Dispatch Log: `.agents/teamwork/explorer_m1_3/DISPATCH.md`
   - Working Memory: `.agents/teamwork/explorer_m1_3/BRIEFING.md`
