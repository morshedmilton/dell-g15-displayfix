## 2026-11-05T10:37:09Z
Sender: 1fa2c640-1687-4d63-a802-a810e6d0f6c0 (orchestrator)
Content:
You are Explorer 3 (Brightness Hotkeys & Display Scaling Explorer).
Your working directory is:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_brightness_scaling\

MANDATORY FIRST STEP:
Read the verbatim user request in ORIGINAL_REQUEST.md at:
c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md

Your mission:
Investigate and document the technical mechanisms and solutions required for R2 (Brightness hotkey control) and R3 (Persistent 125% Display Scaling):
1. Dell G15 F6/F7 Brightness Hotkey Control:
   - Why do F6 and F7 brightness hotkeys stop working when switching to "NVIDIA GPU Only" mode?
   - What are the underlying subsystems for brightness control in Windows:
     * WmiMonitorBrightness / WmiMonitorBrightnessMethods (root\wmi)
     * DDC/CI (IOCTL_VIDEO_QUERY_SUPPORTED_BRIGHTNESS / Physical Monitor APIs via dxva2.dll / MonitorConfiguration API)
     * NVAPI (NvAPI_Disp_GetHdrCapabilities / NvAPI_GPU_GetUsages / NvAPI_Disp_ColorControl)
     * ACPI / Dell WMI interfaces (e.g. Dell Command | Configure, Dell BIOS WMI root\dcim\sysman)
     * Windows Display Enhancement / dxgi brightness
   - How can we intercept F6 and F7 keypresses directly (without requiring Fn key) and adjust brightness?
     * Low-level keyboard hook (WH_KEYBOARD_LL) or RegisterHotKey or Raw Input API
     * Differentiating Fn-lock state or direct F6/F7 vs media keys
     * How to safely and smoothly adjust brightness up/down by 5-10% steps and show a clean OSD or native Windows brightness slider
2. Persistent 125% Display Scaling:
   - Why does display scaling change, revert, or cause blurry font/UI rendering during or after display mode transitions?
   - How does Windows manage display scaling across multiple display topologies?
     * Per-monitor DPI awareness (DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
     * DisplayConfigSetDeviceInfo / DISPLAYCONFIG_SOURCE_DPI_SCALE_GET / SET
     * Registry keys: HKCU:\Control Panel\Desktop\LogPixels, HKCU:\Control Panel\Desktop\PerMonitorSettings
   - How can 125% scaling (120 DPI, scale factor 1.25) be permanently enforced and locked across display switches without causing blurriness or requiring a full user logoff/reboot?
3. Recommended System Architecture:
   - Concrete design for a background daemon/service (or resident lightweight tray app) that handles both hotkey routing and scaling persistence.
   - Exact APIs, structures, and fallback strategies.

Scope boundaries:
- You are strictly READ-ONLY. Do NOT implement product code or modify system configurations.
- Write your detailed findings to survey_brightness_scaling.md in your working directory.
- Write a complete handoff report to handoff.md in your working directory.
- Send a completion message to parent upon finishing with summary and artifact paths.
