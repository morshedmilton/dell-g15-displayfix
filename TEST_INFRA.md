# TEST_INFRA — Dell G15 5530 DisplayFix E2E Test Infrastructure Specification

**Project**: Dell G15 5530 DisplayFix  
**Target Hardware**: Dell G15 5530 (Intel Core i7-13650HX, NVIDIA GeForce RTX 4060 Laptop GPU, AU Optronics AUO AA9F 1080p 360Hz internal eDP panel)  
**Operating System**: Windows 11 Home / Pro x64 (Build 26100+, WDDM 3.1+)  
**Test Framework**: Native Windows PowerShell 5.1+ Opaque-Box Test Harness (Zero External Dependencies)  
**Specification Reference**: `PROJECT.md` § Architecture & Feature Inventory (F01–F16), `ORIGINAL_REQUEST.md` (R1–R5)

---

## 1. Testing Philosophy & Architecture

### 1.1 Opaque-Box Behavioral Verification
The test suite operates strictly as an **opaque-box (black-box) validation harness**. Tests do not instrument or invoke private internal methods of the daemon. Instead, they interact with the system via standard public boundaries:
- **Windows Subsystem APIs**: Win32 CCD (`QueryDisplayConfig`, `SetDisplayConfig`, `DisplayConfigGetDeviceInfo`), GDI/USER APIs (`GetGuiResources`), SetupAPI / CfgMgr32 devnodes.
- **WMI / CIM Providers**: `root\wmi:NvWmiBrightness`, `root\wmi:WmiMonitorBrightnessMethods`, `root\cimv2:Win32_VideoController`.
- **System Event Logs**: System Log (Provider `Display` / `nvlddmkm`, Event ID 4101 TDR), Application Log (Source `Application Error`, Event ID 1000/1001 DWM crashes).
- **Process & Handle Telemetry**: Process working set, handle counts, thread counts, GDI/USER handle consumption.
- **Registry & Configuration**: `HKCU:\Control Panel\Desktop\PerMonitorSettings`, `HKCU:\Control Panel\Desktop\LogPixels`, `C:\ProgramData\DisplayFix\hotkeys.ini`.
- **Scheduled Tasks & Service Management**: Windows Task Scheduler registration, triggers, and execution principals.

### 1.2 Multi-Tier Hierarchical Structure
The test suite is organized into distinct functional tiers that progress from isolated feature verification to complex real-world stress scenarios:

```
tests/e2e/
├── test_runner.ps1                 # Master CLI Test Runner
├── common/
│   ├── TestFramework.ps1           # Assertion engine, context manager, JSON/console reporter
│   └── SystemProbes.ps1            # Win32 CCD, P/Invoke, and WMI query helpers
├── tier1_features/                 # Tier 1: Feature Coverage (F01 - F16, >=5 tests each)
│   ├── test_f01_telemetry_probe.ps1
│   ├── test_f02_dwm_health.ps1
│   ├── test_f03_stress_harness.ps1
│   ├── test_f04_ghost_eviction.ps1
│   ├── test_f05_display_change_listener.ps1
│   ├── test_f06_daemon_lifecycle.ps1
│   ├── test_f07_refresh_rate_360hz.ps1
│   ├── test_f08_registry_dpi_sync.ps1
│   ├── test_f09_ccd_dpi_enforcement.ps1
│   ├── test_f10_hotkey_interception.ps1
│   ├── test_f11_nvidia_wmi_brightness.ps1
│   ├── test_f12_optimus_wmi_brightness.ps1
│   ├── test_f13_media_key_preservation.ps1
│   ├── test_f14_acrylic_osd.ps1
│   ├── test_f15_verification_guide.ps1
│   └── test_f16_test_acceptance.ps1
├── tier2_boundaries/               # Tier 2: Boundary & Corner Conditions
│   ├── test_b01_brightness_extremes.ps1
│   ├── test_b02_dpi_registry_boundaries.ps1
│   ├── test_b03_rapid_display_events.ps1
│   └── test_b04_process_lifecycle_boundaries.ps1
├── tier3_combinations/             # Tier 3: Pairwise Cross-Feature Combinations
│   ├── test_c01_switching_and_360hz.ps1
│   ├── test_c02_switching_and_dpi_scale.ps1
│   ├── test_c03_switching_and_brightness.ps1
│   ├── test_c04_360hz_and_dpi_scale.ps1
│   └── test_c05_hotkeys_and_media_keys.ps1
└── tier4_scenarios/                # Tier 4: Real-World Workloads
    ├── test_s01_gaming_session.ps1
    ├── test_s02_lid_sleep_resume.ps1
    ├── test_s03_external_display.ps1
    └── test_s04_prolonged_video_playback.ps1
```

### 1.3 Progressive Testability Principle
During milestone development, tests give clear, actionable diagnostic signals at every stage:
- **Baseline System Invariants**: Hardware profiles, WMI provider existence, current CCD configurations, and registry trees are tested immediately on the live hardware.
- **Component Contracts**: If a milestone deliverable is under active implementation (e.g. `scripts/diagnostics/probe_system.ps1`), the test verifies both the underlying system capability and checks whether the scripted CLI contract is satisfied. Missing deliverables yield explicit, non-fatal contract gap alerts rather than catastrophic test crashes.

---

## 2. Test Runner Specification (`tests/e2e/test_runner.ps1`)

### 2.1 Command-Line Interface
The master test runner is invoked via PowerShell with standard switch parameters:

```powershell
powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 [-Tier <1|2|3|4|All>] [-Filter <String>] [-Json] [-Verbose]
```

#### Parameter Descriptions:
- **`-Tier <String>`**: Specifies which test tier to execute.
  - `1`: Tier 1 Feature Coverage (F01–F16).
  - `2`: Tier 2 Boundary & Corner Cases.
  - `3`: Tier 3 Cross-Feature Combinations.
  - `4`: Tier 4 Real-World Application Scenarios.
  - `All`: Full test suite across all 4 tiers (Default).
- **`-Filter <String>`**: Case-insensitive substring filter matching test file names or suite names (e.g., `-Filter "360hz"`, `-Filter "f01"`).
- **`-Json`**: Suppresses colored console formatting and outputs a pure, parseable JSON payload containing execution statistics and assertion outcomes.
- **`-Verbose`**: Emits detailed per-assertion tracing, P/Invoke return values, and timing telemetry.

### 2.2 Exit Codes
- **`0`**: All executed tests passed successfully.
- **`1`**: One or more test assertions failed.
- **`2`**: Invalid CLI parameters or test environment error (e.g. missing required Windows permissions).

### 2.3 JSON Result Schema
When `-Json` is passed, the runner outputs:
```json
{
  "Timestamp": "2026-11-05T11:00:00Z",
  "TargetSystem": {
    "Model": "Dell G15 5530",
    "Gpu": "NVIDIA GeForce RTX 4060 Laptop GPU",
    "Panel": "AU Optronics AUO AA9F",
    "OS": "Microsoft Windows 11 Build 26100"
  },
  "Summary": {
    "Tier": "All",
    "TotalSuites": 29,
    "TotalTests": 136,
    "Passed": 136,
    "Failed": 0,
    "Skipped": 0,
    "DurationMs": 4250,
    "Success": true
  },
  "Suites": [
    {
      "Suite": "F01 - Real-time System Telemetry Probe",
      "Tier": "Tier 1",
      "File": "tier1_features/test_f01_telemetry_probe.ps1",
      "Passed": 5,
      "Failed": 0,
      "Skipped": 0,
      "DurationMs": 180,
      "Tests": [
        { "Name": "Detects active GPU and driver version", "Status": "PASS", "DurationMs": 45 },
        { "Name": "Identifies internal AUO AA9F panel node", "Status": "PASS", "DurationMs": 30 },
        { "Name": "Captures exact 360Hz refresh rate", "Status": "PASS", "DurationMs": 25 },
        { "Name": "Captures 125% DPI scale and LogPixels", "Status": "PASS", "DurationMs": 35 },
        { "Name": "Validates JSON telemetry output contract", "Status": "PASS", "DurationMs": 45 }
      ]
    }
  ]
}
```

---

## 3. Feature Inventory & Coverage Mapping (F01–F16)

Every feature in `PROJECT.md` is guaranteed at least 5 dedicated opaque-box test cases in Tier 1:

| Feature ID | Feature Name | Test File | Test Case Count | Primary Verification Method |
|---|---|---|---|---|
| **F01** | Real-time System Telemetry Probe | `tests/e2e/tier1_features/test_f01_telemetry_probe.ps1` | 5 | WMI/CCD active GPU, resolution, 360Hz rational, DPI scale, JSON output |
| **F02** | DWM Health & Stability Monitor | `tests/e2e/tier1_features/test_f02_dwm_health.ps1` | 5 | `GetGuiResources` GDI/USER, memory bounds, Event Log 4101/1000 probes |
| **F03** | 100-Switch Stress Test Harness | `tests/e2e/tier1_features/test_f03_stress_harness.ps1` | 5 | Harness parameters, baseline sampling, leak math, abort triggers, ledger output |
| **F04** | Sub-second Ghost Monitor Eviction | `tests/e2e/tier1_features/test_f04_ghost_eviction.ps1` | 5 | PnP monitor enumeration, stale node detection, eviction latency, DWM CPU impact |
| **F05** | Zero-Lag Display Change Listener | `tests/e2e/tier1_features/test_f05_display_change_listener.ps1` | 5 | `WM_DISPLAYCHANGE` window pump, `RegisterDeviceNotification`, <100ms response |
| **F06** | Clean Lifecycle & Task Scheduler Setup | `tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1` | 5 | Task Scheduler `HighestAvailable`, logon trigger, mutex, clean uninstallation |
| **F07** | Native 360Hz Refresh Rate Lock | `tests/e2e/tier1_features/test_f07_refresh_rate_360hz.ps1` | 5 | AUO AA9F mode table, CCD rational 360152/1000, `SDC_SAVE_TO_DATABASE`, recovery |
| **F08** | Multi-Topology Registry DPI Sync | `tests/e2e/tier1_features/test_f08_registry_dpi_sync.ps1` | 5 | Intel `8086_A78B` & NVIDIA `10DE_28E0` `DpiValue = 0`, `LogPixels = 120` |
| **F09** | Dynamic CCD 125% DPI Enforcement | `tests/e2e/tier1_features/test_f09_ccd_dpi_enforcement.ps1` | 5 | CCD `GET_DPI_SCALE (-3)`, `SET_DPI_SCALE (-4)` with `scaleRel = 0`, no reboot required |
| **F10** | F6/F7 Hotkey Interception | `tests/e2e/tier1_features/test_f10_hotkey_interception.ps1` | 5 | Fn-lock detection, `WH_KEYBOARD_LL` capture of `VK_F6`/`VK_F7`, modifier bypass |
| **F11** | NVIDIA WMI Brightness Backend | `tests/e2e/tier1_features/test_f11_nvidia_wmi_brightness.ps1` | 5 | `root\wmi:NvWmiBrightness`, +8 offset write, 10% safety floor, 100% ceiling |
| **F12** | Optimus WMI Brightness Backend | `tests/e2e/tier1_features/test_f12_optimus_wmi_brightness.ps1` | 5 | `root\wmi:WmiMonitorBrightnessMethods`, dynamic backend switch, 0-provider safety |
| **F13** | Function Row Media Key Preservation | `tests/e2e/tier1_features/test_f13_media_key_preservation.ps1` | 5 | F1-F3 (Mute/Vol-/Vol+) & F9 (Play/Pause) `SendInput` synthesis and passthrough |
| **F14** | Non-Activating Acrylic OSD Overlay | `tests/e2e/tier1_features/test_f14_acrylic_osd.ps1` | 5 | `WS_EX_NOACTIVATE`, topmost acrylic window, percentage bar, auto-dismiss |
| **F15** | Physical Verification Guide | `tests/e2e/tier1_features/test_f15_verification_guide.ps1` | 5 | `docs/verification_guide.md` structure, switching, 360Hz, DPI, and Fn-lock steps |
| **F16** | 100% E2E Test Suite Acceptance | `tests/e2e/tier1_features/test_f16_test_acceptance.ps1` | 5 | Runner execution, CLI flags, full tier coverage, `TEST_READY.md` publication |

Total Tier 1 Test Cases: **80 tests**.

---

## 4. Higher-Tier Test Specifications (Tiers 2, 3, 4)

### 4.1 Tier 2: Boundary & Corner Cases (`tests/e2e/tier2_boundaries/`)
- `test_b01_brightness_extremes.ps1` (5 tests):
  1. Clamping brightness requested below 10% (0%, -5%) to safe 10% floor.
  2. Clamping brightness requested above 100% (105%, 255) to 100% ceiling.
  3. Handling rapid burst of 20 sequential F6/F7 adjustments in < 500ms.
  4. Handling corrupted or non-numeric brightness inputs in configuration files.
  5. Recovery when NVIDIA WMI returns transient RPC failure.
- `test_b02_dpi_registry_boundaries.ps1` (5 tests):
  1. Missing or deleted `PerMonitorSettings` registry key recovery.
  2. Corrupted `DpiValue` (e.g. `0xFFFFFFFF` / -1) detection and correction.
  3. Missing `LogPixels` value under `HKCU:\Control Panel\Desktop`.
  4. Foreign display topology keys preserved without cross-monitor corruption.
  5. User session switching without registry access violations.
- `test_b03_rapid_display_events.ps1` (5 tests):
  1. Rapid burst of 10 `WM_DISPLAYCHANGE` messages within 500ms without hang.
  2. Device arrival immediately followed by removal (`DBT_DEVICEARRIVAL` + `DBT_DEVICEREMOVECOMPLETE`).
  3. Handling display resolution change during console screen lock.
  4. Zero active CCD paths condition handling without null dereference.
  5. Handling monitor query timeout gracefully.
- `test_b04_process_lifecycle_boundaries.ps1` (5 tests):
  1. Missing `hotkeys.ini` file defaults to active F6/F7 interception.
  2. Missing log directory (`C:\ProgramData\DisplayFix\logs`) auto-created cleanly.
  3. Concurrent second daemon launch aborted via single-instance mutex.
  4. Non-elevated execution gracefully prompts or exits with informative code.
  5. Process kill during ghost eviction recovers cleanly on next cycle.

Total Tier 2 Test Cases: **20 tests**.

### 4.2 Tier 3: Pairwise Cross-Feature Combinations (`tests/e2e/tier3_combinations/`)
- `test_c01_switching_and_360hz.ps1` (4 tests):
  1. Optimus $\rightarrow$ NVIDIA GPU Only transition maintains 360152/1000 rational.
  2. NVIDIA GPU Only $\rightarrow$ Optimus transition preserves 360Hz refresh rate.
  3. Intel adapter bounce does not permanently reset display to 60Hz.
  4. Simultaneous ghost eviction and CCD refresh rate lock execution.
- `test_c02_switching_and_dpi_scale.ps1` (4 tests):
  1. Mux switch preserves 125% DPI scale across both Intel and NVIDIA topologies.
  2. System base DPI (`LogPixels = 120`) remains synchronized with monitor DPI.
  3. Win32 application windows maintain crisp text rendering after mux switch.
  4. CCD DPI call succeeds immediately after PnP device arrival.
- `test_c03_switching_and_brightness.ps1` (4 tests):
  1. F6/F7 keypress during active display mux switch is queued or executed cleanly.
  2. Brightness provider seamlessly switches between WmiMonitor and NvWmi.
  3. Brightness level is retained across display mode transitions (no sudden 100% blast).
  4. Safe 10% floor maintained during provider switch.
- `test_c04_360hz_and_dpi_scale.ps1` (4 tests):
  1. Concurrent CCD `SetDisplayConfig` and `DisplayConfigSetDeviceInfo` calls.
  2. Refresh rate lock does not reset scaling to 100%.
  3. Scaling enforcement does not reset refresh rate to 60Hz.
  4. Persistence flags `SDC_SAVE_TO_DATABASE` retain both attributes across reboots.
- `test_c05_hotkeys_and_media_keys.ps1` (4 tests):
  1. Interleaving F6/F7 brightness keys with F1-F3 volume keys.
  2. Interleaving F6/F7 brightness keys with F9 play/pause key.
  3. Fast double-tap F6 followed by F2 does not drop volume keystrokes.
  4. OSD displays brightness percentage without intercepting volume flyouts.

Total Tier 3 Test Cases: **20 tests**.

### 4.3 Tier 4: Real-World Application Scenarios (`tests/e2e/tier4_scenarios/`)
- `test_s01_gaming_session.ps1` (4 tests):
  1. Simulated high-workload gaming session: NVIDIA GPU active, full-screen context.
  2. DWM handle stability under 1000 rendered frames (no handle creep).
  3. Zero TDR events (Event ID 4101) during graphics workload.
  4. F6/F7 acrylic OSD appears topmost without deactivating or alt-tabbing full-screen game (`WS_EX_NOACTIVATE`).
- `test_s02_lid_sleep_resume.ps1` (4 tests):
  1. Power state notification handling (`GUID_CONSOLE_DISPLAY_STATE` 0 $\rightarrow$ 1).
  2. Refresh rate re-pinned to 360Hz within 1000ms after resume.
  3. Scaling verified at 125% immediately after wake.
  4. Brightness hotkeys operational immediately after unlock.
- `test_s03_external_display.ps1` (4 tests):
  1. External monitor plugged into HDMI or Type-C DP port detected.
  2. Ghost eviction engine identifies foreign monitor EDID and stands down.
  3. External monitor receives native resolution/refresh rate without disruption.
  4. Unplugging external display restores single-display internal 360Hz topology.
- `test_s04_prolonged_video_playback.ps1` (4 tests):
  1. Extended video playback simulation with continuous presentation.
  2. DWM private working set remains flat ($< 5\text{MB}$ drift over test window).
  3. Periodic background brightness adjustments cause zero frame presentation drops.
  4. Zero DWM crash events (Event ID 1000).

Total Tier 4 Test Cases: **16 tests**.

---

## 5. Execution & Verification Guide

### 5.1 Prerequisites
1. Open PowerShell 5.1+ as **Administrator** (required for PnP device inspection, WMI query/write, and scheduled task checks).
2. Set execution policy if restricted:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

### 5.2 Running Tests
- **Run Complete Test Suite**:
  ```powershell
  .\tests\e2e\test_runner.ps1
  ```
- **Run Tier 1 Only (Feature Coverage)**:
  ```powershell
  .\tests\e2e\test_runner.ps1 -Tier 1
  ```
- **Run Specific Feature (e.g. 360Hz)**:
  ```powershell
  .\tests\e2e\test_runner.ps1 -Filter "360hz"
  ```
- **Export Results to Machine-Readable JSON**:
  ```powershell
  .\tests\e2e\test_runner.ps1 -Json | Out-File -Encoding utf8 test_results.json
  ```
