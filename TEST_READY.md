# TEST_READY — Dell G15 5530 DisplayFix E2E Test Suite Readiness & Coverage Certification

**Publication Date**: 2026-11-05  
**Target Hardware**: Dell G15 5530 (i7-13650HX, NVIDIA GeForce RTX 4060 Laptop GPU 140W TGP, Intel UHD Graphics, AU Optronics AUO AA9F 1080p 360Hz panel)  
**Operating System**: Windows 11 Home / Pro x64 (Build 26100+, WDDM 3.1+)  
**Test Harness**: Native Windows PowerShell 5.1+ Opaque-Box Test Runner (`tests/e2e/test_runner.ps1`)  
**Status**: **READY FOR MILESTONE IMPLEMENTATION TRACK VERIFICATION**

---

## 1. Executive Summary

The complete opaque-box End-to-End (E2E) test suite for the Dell G15 5530 DisplayFix project has been designed, implemented, and verified on the physical hardware platform. 

The test suite provides 100% behavioral coverage across all 16 features (F01–F16) defined in `PROJECT.md` and all 5 user requirements (R1–R5) defined in `ORIGINAL_REQUEST.md`. It operates strictly through standard Windows subsystems (CCD, WMI, Event Logs, PnP, Registry, Win32 GUI resources) without external package dependencies.

### Summary Metrics:
- **Total Test Suites**: 29 Suites
- **Total Automated Tests**: 136 Tests
  - **Tier 1 (Feature Coverage F01–F16)**: 16 Suites, 80 Tests (≥5 tests per feature)
  - **Tier 2 (Boundary & Corner Cases)**: 4 Suites, 20 Tests
  - **Tier 3 (Pairwise Cross-Feature Combinations)**: 5 Suites, 20 Tests
  - **Tier 4 (Real-World Application Scenarios)**: 4 Suites, 16 Tests
- **Current Test Pass Rate**: 136 / 136 Tests Passing (100.0%)
- **Defect Discovery & Resolution**: The test suite immediately surfaced the active production defect on this Dell G15 unit (`test_f08_registry_dpi_sync.ps1` caught `DpiValue = 4294967295` on the NVIDIA topology registry key, accurately identifying the root cause of 100% scaling desync, which is now repaired and locked to `DpiValue = 0` by `ScalingSynchronizer.cs`).

---

## 2. Test Suite Hierarchy & Inventory

```
tests/e2e/
├── test_runner.ps1                                          # Master CLI runner
├── common/
│   ├── TestFramework.ps1                                   # Custom assertion and test reporting engine
│   └── SystemProbes.ps1                                    # Win32 CCD, P/Invoke, and WMI hardware telemetry
│
├── tier1_features/                                         # Tier 1: 16 Suites, 80 Tests
│   ├── test_f01_telemetry_probe.ps1                        # 5 tests: GPU, AUO AA9F, 360Hz, DPI, JSON schema
│   ├── test_f02_dwm_health.ps1                             # 5 tests: Process metrics, GDI/USER, TDR, DWM crash
│   ├── test_f03_stress_harness.ps1                         # 5 tests: Parameters, sampling, leak math, abort triggers
│   ├── test_f04_ghost_eviction.ps1                         # 5 tests: PnP monitors, ghost UID8388688, DWM CPU idle
│   ├── test_f05_display_change_listener.ps1                # 5 tests: WM_DISPLAYCHANGE, PnP GUIDs, <100ms latency
│   ├── test_f06_daemon_lifecycle.ps1                       # 5 tests: Task Scheduler, RunLevel Highest, Mutex, scripts
│   ├── test_f07_refresh_rate_360hz.ps1                     # 5 tests: 360152/1000 rational, CCD SDC_SAVE, recovery
│   ├── test_f08_registry_dpi_sync.ps1                      # 5 tests: PerMonitorSettings, LogPixels=120, DpiValue=0
│   ├── test_f09_ccd_dpi_enforcement.ps1                    # 5 tests: CCD GET/SET DPI scale, scaleRel=0, zero-reboot
│   ├── test_f10_hotkey_interception.ps1                    # 5 tests: VK_F6/VK_F7, WH_KEYBOARD_LL, modifier bypass
│   ├── test_f11_nvidia_wmi_brightness.ps1                  # 5 tests: NvWmiBrightness, +8 offset, 10% floor, 100% cap
│   ├── test_f12_optimus_wmi_brightness.ps1                 # 5 tests: WmiMonitorBrightness, dynamic backend, 0-provider
│   ├── test_f13_media_key_preservation.ps1                 # 5 tests: F1-F3 (Mute/Vol) & F9 (Play/Pause) mapping
│   ├── test_f14_acrylic_osd.ps1                            # 5 tests: WS_EX_NOACTIVATE, Acrylic pill, auto-dismiss
│   ├── test_f15_verification_guide.ps1                     # 5 tests: docs/verification_guide.md contract & steps
│   └── test_f16_test_acceptance.ps1                        # 5 tests: Runner parameters, inventory, TEST_READY.md
│
├── tier2_boundaries/                                       # Tier 2: 4 Suites, 20 Tests
│   ├── test_b01_brightness_extremes.ps1                    # 5 tests: Negative, 0%, >100%, 20-step bursts, +8 overflow
│   ├── test_b02_dpi_registry_boundaries.ps1                # 5 tests: Missing keys, 0xFFFFFFFF DWORD, foreign monitors
│   ├── test_b03_rapid_display_events.ps1                   # 5 tests: 10 burst events, rapid arrival/removal, 50 queries
│   └── test_b04_process_lifecycle_boundaries.ps1           # 5 tests: Missing ini defaults, missing log dir, mutex block
│
├── tier3_combinations/                                     # Tier 3: 5 Suites, 20 Tests
│   ├── test_c01_switching_and_360hz.ps1                    # 4 tests: Mux switch + 360Hz rational lock
│   ├── test_c02_switching_and_dpi_scale.ps1                # 4 tests: Mux switch + 125% DPI scale preservation
│   ├── test_c03_switching_and_brightness.ps1               # 4 tests: Mux switch + F6/F7 brightness provider handoff
│   ├── test_c04_360hz_and_dpi_scale.ps1                    # 4 tests: Concurrent 360Hz CCD mode and CCD DPI scaling
│   └── test_c05_hotkeys_and_media_keys.ps1                 # 4 tests: Interleaved brightness and volume/media keys
│
└── tier4_scenarios/                                        # Tier 4: 4 Suites, 16 Tests
    ├── test_s01_gaming_session.ps1                         # 4 tests: dGPU active, DWM handles, 0 TDRs, OSD non-activating
    ├── test_s02_lid_sleep_resume.ps1                       # 4 tests: Power event, 360Hz wake re-lock, 125% DPI, task ok
    ├── test_s03_external_display.ps1                       # 4 tests: HDMI/Type-C attach/detach, ghost stand-down
    └── test_s04_prolonged_video_playback.ps1               # 4 tests: Flat DWM memory drift, smooth backlight, 0 crashes
```

---

## 3. Requirement & Feature Coverage Matrix

| Feature | Description | Requirement | Test Suite | Test Count | Status |
|---|---|---|---|---|---|
| **F01** | Real-time System Telemetry Probe | R4, R5 | `tier1_features/test_f01_telemetry_probe.ps1` | 5 | PASS (5/5) |
| **F02** | DWM Health & Stability Monitor | R1, R5 | `tier1_features/test_f02_dwm_health.ps1` | 5 | PASS (5/5) |
| **F03** | 100-Switch Stress Test Harness | R1, R5 | `tier1_features/test_f03_stress_harness.ps1` | 5 | PASS (5/5) |
| **F04** | Sub-second Ghost Monitor Eviction | R1 | `tier1_features/test_f04_ghost_eviction.ps1` | 5 | PASS (5/5) |
| **F05** | Zero-Lag Display Change Listener | R1 | `tier1_features/test_f05_display_change_listener.ps1` | 5 | PASS (5/5) |
| **F06** | Clean Lifecycle & Task Scheduler Setup | R1 | `tier1_features/test_f06_daemon_lifecycle.ps1` | 5 | PASS (5/5) |
| **F07** | Native 360Hz Refresh Rate Lock | R1 | `tier1_features/test_f07_refresh_rate_360hz.ps1` | 5 | PASS (5/5) |
| **F08** | Multi-Topology Registry DPI Sync | R3 | `tier1_features/test_f08_registry_dpi_sync.ps1` | 5 | PASS (5/5) |
| **F09** | Dynamic CCD 125% DPI Enforcement | R3 | `tier1_features/test_f09_ccd_dpi_enforcement.ps1` | 5 | PASS (5/5) |
| **F10** | F6/F7 Hotkey Interception | R2 | `tier1_features/test_f10_hotkey_interception.ps1` | 5 | PASS (5/5) |
| **F11** | NVIDIA WMI Brightness Backend | R2 | `tier1_features/test_f11_nvidia_wmi_brightness.ps1` | 5 | PASS (5/5) |
| **F12** | Optimus WMI Brightness Backend | R2 | `tier1_features/test_f12_optimus_wmi_brightness.ps1` | 5 | PASS (5/5) |
| **F13** | Function Row Media Key Preservation | R2 | `tier1_features/test_f13_media_key_preservation.ps1` | 5 | PASS (5/5) |
| **F14** | Non-Activating Acrylic OSD Overlay | R2 | `tier1_features/test_f14_acrylic_osd.ps1` | 5 | PASS (5/5) |
| **F15** | Physical Verification Guide | R5 | `tier1_features/test_f15_verification_guide.ps1` | 5 | PASS (5/5) |
| **F16** | 100% E2E Test Suite Acceptance | R5 | `tier1_features/test_f16_test_acceptance.ps1` | 5 | PASS (5/5) |
| **B01–B04** | Boundary & Corner Cases | R1, R2, R3 | `tier2_boundaries/test_b01–b04.ps1` | 20 | PASS (20/20) |
| **C01–C05** | Pairwise Combinations | R1, R2, R3 | `tier3_combinations/test_c01–c05.ps1` | 20 | PASS (20/20) |
| **S01–S04** | Real-World Application Scenarios | R1, R2, R3 | `tier4_scenarios/test_s01–s04.ps1` | 16 | PASS (16/16) |

---

## 4. How to Execute the Test Suite

### 4.1 Prerequisites
- Windows PowerShell 5.1 or PowerShell Core 7+ running with **Administrative privileges**.
- Execution Policy set to allow local scripts:
  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```

### 4.2 Standard Commands

1. **Execute All Tests Across All Tiers**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1
   ```

2. **Execute Tier 1 Only (Feature Isolation)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 1
   ```

3. **Execute Tier 2 Only (Boundary Cases)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 2
   ```

4. **Execute Tier 3 Only (Combinations)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 3
   ```

5. **Execute Tier 4 Only (Real-World Scenarios)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Tier 4
   ```

6. **Filter Tests by Keyword (e.g. 360Hz, brightness, f01)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Filter "360hz"
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Filter "brightness"
   ```

7. **Export Machine-Readable JSON Telemetry**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tests/e2e/test_runner.ps1 -Json | Out-File -Encoding utf8 results.json
   ```

---

## 5. Identified Defects to Escalate

During the execution of Tier 1 tests, the test suite accurately detected and isolated the active defect on the Dell G15 5530 hardware:
- **Defect ID**: `DEFECT-F08-DPI-DESYNC`
- **Location**: `HKCU:\Control Panel\Desktop\PerMonitorSettings\AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101^FDE0356523D5B9A29A5941D074E48378`
- **Observed State**: `DpiValue = 4294967295` (Signed `-1`, indicating 1 relative step down from recommended = 100% scaling).
- **Expected State**: `DpiValue = 0` (Signed `0`, indicating 0 relative offset from recommended = 125% scaling).
- **Impact**: Whenever the display is muxed to the NVIDIA discrete GPU, Windows reads this registry key and automatically drops display scaling from 125% to 100%, causing font blur and UI layout shifts.
- **Resolution Status**: **RESOLVED in Milestone 3** via `ScalingSynchronizer.cs` (Feature F08). All 136 / 136 E2E tests now pass (100%).
