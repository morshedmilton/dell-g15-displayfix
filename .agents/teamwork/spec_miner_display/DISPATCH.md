## 2026-11-05T10:36:58Z
You are Spec Miner (Display Switching & 360Hz & DWM Architecture).
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\spec_miner_display\

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Your mission:
Investigate and document the technical specifications, Windows Display Subsystem APIs, NVIDIA Dynamic Display Switching / Advanced Optimus mechanics, and stability controls required to satisfy R1 and R5:
1. Display Switching Architecture:
   - How does display switching between "Automatic", "Optimus" (MSHybrid), and "NVIDIA GPU Only" (Direct dGPU connection via multiplexer / muxless eDP routing) work under Windows 11/10?
   - How can display modes be queried and triggered programmatically (e.g. via NvAPI / DisplayConfig / CCD SetDisplayConfig / ChangeDisplaySettingsEx / NVIDIA NVWMI / CLI / devcon)?
   - How does the system signal a display mode switch event? (WM_DISPLAYCHANGE, GUID_DEVINTERFACE_MONITOR, GUID_VIDEO_ADAPTER_ARRIVAL, ETW, power broadcast)?
2. 360Hz Refresh Rate Enforcement:
   - What causes refresh rate to drop or reset to 60Hz or 120Hz during mode switches?
   - How to reliably query all supported modes via EnumDisplaySettingsEx / CCD QueryDisplayConfig and enforce 360Hz (or highest native refresh rate) programmatically?
   - How to prevent black screens, stutter, or mode transition lag?
3. DWM Stability & Leak Prevention:
   - Why do display topology changes cause DWM crashes, handles/memory leaks, or driver resets (TDR - Timeout Detection and Recovery)?
   - What APIs or event logs can monitor DWM process health (dwm.exe memory, handle count, crash logs in Application event log Event ID 1000/1001 or System event log Event ID 4101 Display driver nvlddmkm stopped responding)?
   - How to design a robust stress test simulating up to 100 switches safely with health metrics?
4. Concrete Interface and API Contracts:
   - Document the exact Win32/C++/.NET APIs, data structures, and CLI commands needed to detect and control display modes, refresh rate, and stability telemetry.

Scope boundaries:
- You are strictly READ-ONLY. Do NOT implement product code or modify system configurations.
- Write your detailed findings to survey_display_spec.md in your working directory.
- Write a complete handoff report to handoff.md in your working directory.
- Send a completion message to parent upon finishing with summary and artifact paths.


## 2026-11-05T10:47:52Z
**Context**: Monitoring Phase 0 Survey progress.
**Content**: Status check on Display & DWM Spec Mining. Please provide an update on your progress and estimated time to report completion.
**Action**: Please reply with your current status or finish writing survey_display_spec.md and handoff.md.
