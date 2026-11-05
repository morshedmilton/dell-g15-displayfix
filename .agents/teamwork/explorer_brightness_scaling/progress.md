# Progress: Brightness Hotkeys & Display Scaling Explorer

Last visited: 2026-11-05T10:48:00Z
Status: Completed

## Tasks
- [x] Initial setup (DISPATCH.md, BRIEFING.md, progress.md)
- [x] Inspect existing codebase for prior brightness & scaling attempts (`NvBrightness.cs`, `PhantomGuard.cs`, `docs/problem.md`, `CHANGELOG.md`)
- [x] Investigate Dell G15 F6/F7 brightness failure in NVIDIA GPU Only mode (ACPI EC event disconnection, WmiMonitorBrightness vs NvWmiBrightness)
- [x] Investigate Windows Brightness Control Subsystems (WMI, DDC/CI, NVAPI, ACPI)
- [x] Investigate F6/F7 keypress interception (Fn-lock, RawInput, WH_KEYBOARD_LL, RegisterHotKey, clean OSD)
- [x] Investigate Persistent 125% Display Scaling (DPI awareness V2, DisplayConfig APIs, registry mismatch LogPixels 120 vs PerMonitorSettings -1)
- [x] Synthesize findings into comprehensive `survey_brightness_scaling.md`
- [x] Compile 5-component `handoff.md`
- [x] Notify parent orchestrator via `send_message`
