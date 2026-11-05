## 2026-11-05T10:35:03Z

Diagnose and resolve Dell G15 display switching issues across Automatic, Optimus, and NVIDIA GPU Only modes, ensuring 360Hz refresh rate, zero lag, crash-free transitions, functional F6/F7 brightness controls in NVIDIA mode, and persistent 125% display scaling.

Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix
Integrity mode: development

Existing repository: https://github.com/morshedmilton/dell-g15-displayfix

## Requirements

### R1. Display Mode Switching and Stability
Ensure switching between display modes ("Automatic", "Optimus", "NVIDIA GPU Only") via NVIDIA App or NVIDIA Control Panel functions with 0 issues, maintaining 360Hz refresh rate, zero lag, and smooth performance. Prevent DWM or display driver crashes, resets, or memory leaks even after repeated switches (up to 100 times).

### R2. Brightness Hotkey Control in NVIDIA GPU Only Mode
Ensure brightness adjustment hotkeys (F6 to decrease brightness, F7 to increase brightness, without requiring Fn key) function properly in all display modes, resolving the issue where brightness keys fail after switching to NVIDIA GPU Only mode.

### R3. Persistent 125% Display Scaling
Maintain 125% display scaling by default across all display modes and transitions without causing blurry text or rendering issues across applications and windows.

### R4. Evidence-Based Root Cause Diagnosis and Codebase Approach
Inspect and analyze the existing custom applications in the repository (https://github.com/morshedmilton/dell-g15-displayfix) and collect runtime logs, system telemetry, and concrete evidence before planning and implementing fixes. Replace or rebuild the applications with a new solution if needed.

### R5. Verification and Diagnostics Tooling
Provide automated diagnostic and validation scripts and logs to verify system and display state, along with clear step-by-step instructions for physical testing of display switching and brightness hotkeys.

## Acceptance Criteria

### Display Switching & Stability
- [ ] Switching between Automatic, Optimus, and NVIDIA GPU Only modes completes without crashes, black screens, or stuttering.
- [ ] Display refresh rate is preserved at 360Hz across all display modes.
- [ ] Repeated display mode changes (stress test) do not cause DWM memory leaks, crashes, or driver instability.

### Brightness Control
- [ ] Pressing F6 decreases brightness and pressing F7 increases brightness (without Fn key) in NVIDIA GPU Only mode and Optimus mode.

### Display Scaling
- [ ] Display scaling is set to 125% across all modes, with crisp text and window rendering without blurriness.

### Diagnostics & Verification
- [ ] Automated verification scripts capture and report display mode, refresh rate, scaling, and DWM stability metrics.
- [ ] A verification guide is provided detailing the exact steps to confirm physical hotkey and display mode switching behavior.


## 2026-11-05T15:42:12Z

Diagnose and resolve three interacting display and GPU software/driver issues on a Dell G15 5530 (Windows 11) systematically in order: restore display brightness hotkeys and backlight control, enable grayed-out display modes (Optimus and Automatic), and resolve NVIDIA App driver download and tuning lockups.

Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix
Integrity mode: development

## Requirements

### R1. Restore Display Brightness Hotkey and Backlight Control
Resolve the failure where brightness hotkeys do not alter panel luminance. Ensure that pressing brightness keys (Fn+F6/F7 or plain F6/F7 according to Fn-lock state) and adjusting the Windows display brightness slider visibly increases and decreases the physical display backlight.

### R2. Restore Display Mode Switching (Optimus / Automatic)
Resolve the issue where only NVIDIA GPU-only mode is selectable while Optimus and Automatic modes remain grayed out. Restore the ability in NVIDIA Control Panel and Windows display settings to select and switch between all supported display modes without crashing or display lockup.

### R3. Resolve NVIDIA App Driver Update Loop and Tuning Lockup
Resolve the issue in NVIDIA App where the Game Ready Driver download enters an infinite loading loop without initiating or completing. Ensure the driver update can be downloaded and installed, and restore the Automatic Tuning feature so its toggle and operation function without becoming stuck.

## Verification Resources
Run the existing repository test suite and diagnostic scripts (`tests/` directory) alongside live hardware verification on the laptop.

## Acceptance Criteria

### Brightness Functionality
- [ ] Brightness hotkey inputs (Fn+F6 and Fn+F7, or F6 and F7 depending on Fn-lock status) actively change the physical panel backlight level.
- [ ] Windows Settings display brightness slider adjusts the physical backlight across its full range.
- [ ] Hotkey OSD reflects the current brightness percentage accurately without hanging.

### Display Mode Switching
- [ ] In NVIDIA Control Panel "Manage Display Mode", Optimus and Automatic options are active and selectable, not grayed out.
- [ ] Switching display modes between NVIDIA GPU-only, Optimus, and Automatic completes cleanly and persists as selected.

### NVIDIA App Stability
- [ ] NVIDIA App Game Ready Driver download initiates and completes without an infinite loading loop.
- [ ] Automatic Tuning feature responds to toggle states (ON/OFF) and performs tuning without becoming stuck.

### Test Suite Execution
- [ ] Repository test suite and diagnostic scripts in `tests/` execute cleanly and verify system display configuration integrity.
