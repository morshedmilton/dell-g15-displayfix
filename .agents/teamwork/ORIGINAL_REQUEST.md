# Original User Request

## Initial Request — 2026-11-05T15:41:11Z

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
