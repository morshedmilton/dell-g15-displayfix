# Scope: Round 2 — Three Interacting Display & GPU Driver Issues

## Architecture & Diagnosis Synthesis

From the Phase 0 Round 2 Survey (3 parallel Explorers `explorer_r2_1`, `explorer_r2_2`, `explorer_r2_3`), the three issues interact through hardware, firmware, driver, and user-space layers:

1. **R1 (Brightness & Backlight)**:
   - When in discrete GPU mode, physical backlight control requires administrative elevation for `root\wmi:NvWmiBrightness`. `DisplayFixDaemon` was running un-elevated from `HKCU:\...\Run`, causing WMI to reject calls with `Access denied (0x80041003)`.
   - Windows native brightness slider relies on the Intel WDDM DDI, which is detached while the system is locked in discrete GPU mode.
   - Restoring elevated task scheduler execution fixes hotkey backlight control; restoring Optimus/Automatic (R2) restores the Windows native slider.

2. **R2 (Optimus / Automatic Grayed Out)**:
   - The Intel UHD Graphics adapter is 100% operational in Windows (`Status: OK`, `ConfigManagerErrorCode: 0`).
   - The primary root cause is the Dell UEFI BIOS Setup toggle: **Display > "Hybrid Graphics / Advanced Optimus"** is turned **OFF** (Discrete GPU Only mode), hardware-locking the eDP multiplexer to the RTX 4060 dGPU and signaling ACPI that dynamic switching is unsupported.
   - Aggravated by `NvPciFilter` driver interface communication errors and non-auto 3D global settings.

3. **R3 (NVIDIA App Update Loop & Tuning Lockup)**:
   - Stale post-processing task `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\postprocessing.json` stuck in `"status": 1` continuously forces the UI into a download progress spinner, blocking initiation of driver updates.
   - Automatic Tuning lockup caused by stopped FrameView SDK service (`FvSvc`), AWCC (`AWPerformance.UCSubAgent.exe`) holding concurrent GPU clock domain locks, and stale scan completion status 34.

---

## Feature Inventory (Round 2)

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F17 | Elevated Scheduled Task & NvWmi Execution | Reconfigure `DisplayFixDaemon` as elevated Scheduled Task (`RunLevel: Highest`) and remove non-elevated HKCU Run entry | MR1 | explorer_r2_1 |
| F18 | Active Hotkey Configuration & Backlight Verification | Deploy verified `hotkeys.ini` bindings (F6/F7) and confirm physical luminance adjusts via `NvWmiBrightness` | MR1 | explorer_r2_1 |
| F19 | BIOS Hybrid Graphics Verification & Guidance | Verify firmware ACPI MHYB/OPTIMUS tables and document exact F2 BIOS setup steps for Hybrid Graphics toggle | MR2 | explorer_r2_2 |
| F20 | Global 3D Auto-Select & Driver Service Reset | Set NVIDIA 3D preference to Auto-Select and cleanly cycle `NVDisplay.ContainerLocalSystem` / `NvContainerLocalSystem` | MR2 | explorer_r2_2 |
| F21 | NVIDIA App Update Framework Postprocessing Reset | Purge stale `postprocessing.json` and downloader lockfiles to restore driver update download initiation | MR3 | explorer_r2_3 |
| F22 | Automatic Tuning Service & Scan State Unsticking | Enable and start `FvSvc`, resolve AWCC GPU clock locks, clear stale tuning scan cache, and verify toggle responsiveness | MR3 | explorer_r2_3 |
| F23 | Full Test Suite Execution & Acceptance Verification | Run `tests/e2e/test_runner.ps1` and `scripts/verify.ps1`, verify 9/9 gates, deliver physical verification guide | MR4 | explorer_r2_3 / acceptance |

---

## Milestones (Round 2)

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| MR1 | Restore Display Brightness Hotkey and Backlight Control | Elevated daemon installation, remove HKCU Run entry, activate hotkeys.ini, verify NvWmi writes change backlight | none | DONE |
| MR2 | Restore Display Mode Switching (Optimus / Automatic) | Configure Global 3D Auto-Select, reset display container services, verify Intel/NVIDIA PnP and ACPI switching readiness, provide BIOS toggle guide | MR1 | DONE |
| MR3 | Resolve NVIDIA App Driver Update Loop and Tuning Lockup | Clear stale postprocessing.json and downloader locks, start FvSvc, clear tuning scan cache, verify download & tuning toggle | MR2 | DONE |
| MR4 | Full Test Suite Execution & Acceptance Verification | Execute full E2E test suite (Tiers 1-4 + Tier 5), verify 9/9 gates, verify system integrity, compile comprehensive verification guide | MR1, MR2, MR3 | DONE |

---

## Interface Contracts (Round 2)

### Contract 1: `DisplayFixDaemon` ↔ Elevated Task Scheduler
- The daemon executable `DisplayFixDaemon.exe` MUST execute with administrative privileges (`RunLevel: HighestAvailable`) under the interactive user logon trigger.
- The `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` entry `DisplayFixDaemon` MUST NOT exist to prevent dual or un-elevated execution.

### Contract 2: `DisplayFixDaemon` ↔ `root\wmi:NvWmiBrightness`
- In discrete GPU mode, `NvWmiBrightness.NvGetSetBrightnessLevel` MUST return `Result=True`.
- Backlight values MUST be clamped between 10% and 100% with +8 offset calibration.

### Contract 3: NVIDIA App ↔ UpdateFramework & Downloader
- `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\status\grd\postprocessing.json` MUST NOT contain stuck `"status": 1` tasks when idle.
- Downloader directory `C:\ProgramData\NVIDIA Corporation\Downloader` MUST be free of orphaned lock files.

### Contract 4: Automatic Tuning ↔ FrameView SDK (`FvSvc`) & Session Container
- `FvSvc` service MUST have `StartType = Automatic` and `Status = Running`.
- NVIDIA Session container and `NvOc` plugin MUST receive valid OC scanner capabilities without hanging on stale scan results.
