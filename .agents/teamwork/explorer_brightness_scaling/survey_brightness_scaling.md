# Comprehensive Investigation Report: Brightness Hotkeys & Persistent Display Scaling (R2 & R3)
**Target Platform:** Dell G15 5530 (i7-13650HX, NVIDIA RTX 4060 Laptop GPU, Intel UHD Graphics, AUO AA9F 1080p 360Hz internal eDP panel, BIOS 1.36.0, Windows 11 Build 26300)  
**Author:** Explorer 3 (Brightness Hotkeys & Display Scaling Explorer)  
**Date:** 2026-11-05  

---

## Executive Summary

This report delivers the technical investigation and architectural blueprints for **Requirement R2 (F6/F7 Brightness Hotkey Control)** and **Requirement R3 (Persistent 125% Display Scaling)** on the Dell G15 5530 platform across all display modes ("Optimus", "Automatic", and "NVIDIA GPU Only").

### Core Findings:
1. **Brightness Hotkey Failure (R2):**
   - In Optimus mode, the AUO AA9F internal panel is attached to the Intel iGPU (`PCI\VEN_8086&DEV_A78B`). Intel's driver exposes `root\wmi:WmiMonitorBrightness` and `root\wmi:WmiMonitorBrightnessMethods`. Dell's ACPI Embedded Controller (EC) routes hardware brightness notifications to this Intel provider.
   - When switching to **NVIDIA GPU Only** mode via Advanced Optimus (Dynamic Display Switching / DDS), the panel is muxed to the dGPU (`PCI\VEN_10DE&DEV_28E0`). However:
     * NVIDIA's mobile driver under Windows **does not expose** `WmiMonitorBrightnessMethods` in `root\wmi`.
     * To prevent the 31–54% DWM CPU leak caused by the stale Intel display path, `PhantomGuard` resets the Intel adapter, which tears down the Intel monitor instance (`AUOAA9F/4&3A9F8B26&8&UID8388688`). This drops the system's `WmiMonitorBrightness` interface count from 1 to 0.
     * With no active `WmiMonitorBrightness` interface, Windows hides the native brightness slider entirely, and the EC's ACPI brightness events are discarded by the OS.
     * While physical backlight control is reachable through NVIDIA's proprietary WMI interface (`root\wmi:NvWmiBrightness`), it requires administrative elevation (`RunLevel Highest`), suffers from a measured +8 calibration offset on writes, and shuts the backlight completely off below 10%.
     * Crucially, when Dell G15 Fn-lock is in Media mode, pressing physical F6/F7 produces **no Windows input events at all** (it is swallowed by the EC). With Fn-lock in Function mode, F6/F7 emit standard `VK_F6` (0x75) and `VK_F7` (0x76) keystrokes, which must be actively claimed and routed by user-mode software. In the existing repository, function row interception is disabled by default in `hotkeys.ini`.

2. **Display Scaling Desync & Blurry Text (R3):**
   - Windows treats the internal panel on the Intel adapter and the exact same panel on the NVIDIA adapter as **two completely distinct display topologies**:
     * Intel path: `AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050`
     * NVIDIA path: `AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101`
   - Active telemetry collected from this system reveals that `HKCU:\Control Panel\Desktop\PerMonitorSettings` has `DpiValue = 0` (recommended / 125%) for the Intel topology, but `DpiValue = 4294967295` (-1, corresponding to 100% scale) for the NVIDIA topology.
   - When switching to NVIDIA GPU Only mode, Windows automatically applies the -1 relative step (100% scaling), reverting the user's 125% setting.
   - When scaling changes dynamically or mismatches the system base DPI (`LogPixels = 120`), DWM applies bitmap stretching to Win32/GDI/DirectWrite applications that lack Per-Monitor V2 awareness, producing blurry fonts and fuzzy UI rendering.
   - Enforcing 125% (120 DPI) across all display topologies programmatically via the Connecting and Configuring Displays (CCD) API (`DisplayConfigSetDeviceInfo` with `DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4`) eliminates scaling shifts and guarantees 100% crisp font rendering without logoff or reboot.

---

## Part 1: Dell G15 F6/F7 Brightness Control Deep-Dive

### 1.1 Root Cause: Why Brightness Hotkeys Break in NVIDIA GPU Only Mode

```
+----------------------------------------------------------------------------------------------------+
| OPTIMUS MODE (Functional Path)                                                                     |
| Keypress (F6/F7) -> EC -> ACPI SCI -> acpi.sys -> Intel igdkmdn64.sys -> WmiMonitorBrightnessMethods|
|                                                                       -> Backlight adjusted        |
|                                                                       -> Windows Slider updated    |
+----------------------------------------------------------------------------------------------------+

+----------------------------------------------------------------------------------------------------+
| NVIDIA GPU ONLY MODE (Broken Path)                                                                 |
| Keypress (F6/F7) -> EC -> ACPI SCI -> acpi.sys -> Target: GFX0 (Intel) -> Intel monitor absent     |
|                                                -> Event DROPPED                                    |
|                                                -> Windows Slider GONE                              |
|                                                -> Screen backlight UNTOUCHED                       |
|                                                                                                    |
| WORKING ALTERNATIVE:                                                                               |
| Physical F6/F7 -> VK_F6/VK_F7 -> Low-Level Hook / Hotkey -> root\wmi:NvWmiBrightness -> dGPU PWM   |
+----------------------------------------------------------------------------------------------------+
```

#### Detailed Breakdown:
1. **EC and ACPI Namespace Hardwiring:**
   - In Dell BIOS 1.36.0, the Embedded Controller's brightness event methods (e.g., `_Qxx`) fire ACPI notifications (`Notify (\_SB.PCI0.GFX0.DD02, 0x86)` / `0x87`) explicitly targeted at the integrated GPU (`GFX0`).
   - When DDS muxes the display to the dGPU (`PEG0` / `PEGP`), the ACPI tables do not dynamically re-route those notification targets to the NVIDIA PCIe device.
2. **Provider Absence:**
   - In Windows, the native brightness slider and keyboard hotkey dispatcher rely on WMI classes `WmiMonitorBrightness` and `WmiMonitorBrightnessMethods` in `root\wmi`.
   - The NVIDIA Windows display driver (`nvlddmkm.sys`) on Dell mobile architectures does not implement the Microsoft ACPI WMI monitor brightness provider.
   - When `PhantomGuard` clears the duplicate display path by toggling the Intel adapter (`PCI\VEN_8086&DEV_A78B`), the Intel driver's monitor devnode is unlinked, leaving 0 active `WmiMonitorBrightness` interfaces in the OS.
3. **The Fn-Lock Dilemma on Dell Laptops:**
   - On the Dell G15 keyboard, the function row has two modes toggled by `Fn + Esc` (Fn-Lock):
     * **Media Mode (Fn-Lock OFF):** Pressing F6/F7 signals the EC to handle brightness directly. The EC emits an internal ACPI event and **no Windows virtual keystroke or HID usage report is sent to the operating system**. In NVIDIA GPU Only mode, this drops into a black hole.
     * **Function Key Mode (Fn-Lock ON):** Pressing F6 emits `VK_F6` (scancode `0x40`) and pressing F7 emits `VK_F7` (scancode `0x41`). Because these are standard Windows keystrokes, user-mode software can intercept them.
   - In `NvBrightness.cs` (v1.1.0), the author added `hotkeys.ini` to intercept `VK_F6` and `VK_F7` in Function Mode, but left them **commented out by default**. Thus, out-of-the-box, F6 and F7 do nothing.

---

### 1.2 Windows Brightness Subsystems Analysis

| Subsystem / API | Namespace / DLL | Works in Optimus? | Works in NVIDIA Mode? | Backlight vs LUT | Latency / Behavior | Elevation Required? |
|---|---|---|---|---|---|---|
| **WmiMonitorBrightnessMethods** | `root\wmi` | **Yes** (Native) | **No** (Provider missing) | Physical Backlight | Instant (~5 ms) | No |
| **NvWmiBrightness** | `root\wmi` | Secondary | **Yes** (Primary) | Physical Backlight | ~10-25 ms; noisy readback | **Yes** (`RunLevel Highest`) |
| **DDC/CI (`dxva2.dll`)** | `dxva2.dll` | No | No | N/A (Fails on eDP) | Returns 0 physical monitors | No |
| **NVAPI ColorControl** | `nvapi64.dll` | No | Yes (Digital only) | Digital LUT (Crushes colors) | Instant, but burns backlight | No |
| **DXGI Output Brightness** | `dxgi.dll` | Yes (HDR only) | Yes (HDR only) | SDR White Level | Only works when HDR enabled | No |
| **Dell BIOS WMI** | `root\dcim\sysman` | Read-only | Read-only | N/A | BIOS SMBIOS tokens; no live PWM | Yes |

#### Deep-Dive into Subsystems:

#### 1. `root\wmi:WmiMonitorBrightnessMethods`
- **Method:** `WmiSetBrightness(uint32 Timeout, uint8 Brightness)`
- **Query:** `root\wmi:WmiMonitorBrightness.CurrentBrightness`
- **Behavior:** This is the standard WDDM OS path. When present, Windows updates its native Action Center / Quick Settings slider and OSD flyout automatically. It fails with HRESULT `0x8004100c` (Not Supported) when the display is driven by NVIDIA.

#### 2. `root\wmi:NvWmiBrightness`
- **Method:** `NvGetSetBrightnessLevel(uint32 inArg, uint32 Level, out uint32 Result)`
  * `inArg = 0`: Query current level (returns `Result` as integer 0–100).
  * `inArg = 1`: Set current level (`Level` = 0–100).
- **Security Constraint:** Calling this method without administrative elevation fails with HRESULT `0x80041003` (Access Denied). Any resident tool controlling brightness must run elevated via Task Scheduler (`RunLevel Highest`).
- **Hardware Calibration & Offset:**
  * On the AUO AA9F panel, the NVIDIA driver applies an internal attenuation offset of ~8 units. Writing `100` reads back `92`; writing `50` reads back `42`.
  * If a caller writes `10`, the panel is driven at `2%`, which turns off the eDP backlight inverter completely, appearing as a dead screen.
  * **Rule:** The driver MUST apply a write offset: `target = Clamp(level + 8, 10, 100)`. A hard minimum floor of `10%` must be enforced at all times.

#### 3. DDC/CI & Physical Monitor API (`dxva2.dll`)
- Desktop monitors communicate over I2C lines using MCCS VCP code `0x10`.
- Internal laptop panels connect via eDP (Embedded DisplayPort). The eDP specification controls backlight through DPCD registers (`0x00720` - `0x00728`) or dedicated PWM lines driven by the active display adapter.
- Standard Windows DDC/CI (`GetNumberOfPhysicalMonitorsFromHMONITOR`) fails on laptop internal panels because `monitor.sys` does not expose an I2C/DDC channel for eDP.

#### 4. NVAPI (`nvapi64.dll`)
- Functions `NvAPI_Disp_ColorControl` / `NvAPI_Disp_GetHdrCapabilities` adjust the GPU's digital output ramps (LUT).
- If brightness is lowered via NVAPI color control, the image is artificially dimmed digitally while the physical LED backlight remains at 100% duty cycle, consuming full battery power and washing out contrast. It does NOT replace hardware PWM backlight control.

---

### 1.3 Hotkey Interception & Routing Engineering

To meet Requirement R2: *"F6 to decrease brightness, F7 to increase brightness, without requiring Fn key"*:

#### The Architecture of Function-Row Preservation:
Because physical F6 and F7 emit `VK_F6` and `VK_F7` only when Fn-Lock is enabled, the laptop must operate with Fn-Lock active (Function Key Mode). However, in standard Function Key Mode, F1–F3 and F9 also become plain function keys, losing their printed media capabilities (Mute, Vol-, Vol+, Play/Pause).

The solution is an **Intelligent Hotkey Router**:
1. Claim `F6` and `F7` for brightness control.
2. Claim `F1`, `F2`, `F3`, and `F9` and synthesize standard media keystrokes via `SendInput`:
   * `F1` $\rightarrow$ `VK_VOLUME_MUTE` (`0xAD`)
   * `F2` $\rightarrow$ `VK_VOLUME_DOWN` (`0xAE`)
   * `F3` $\rightarrow$ `VK_VOLUME_UP` (`0xAF`)
   * `F9` $\rightarrow$ `VK_MEDIA_PLAY_PAUSE` (`0xB3`)
3. Concurrently register for **Raw Input HID Consumer Control** (`UsagePage 0x0C, Usage 0x01` with `RIDEV_INPUTSINK`). If the user toggles Fn-Lock off or presses Fn+F6/Fn+F7, the driver catches HID usages `0x006F` (Increment) and `0x0070` (Decrement).

#### Interception Mechanism Comparison:

| Criteria | `RegisterHotKey` | Low-Level Keyboard Hook (`WH_KEYBOARD_LL`) | Raw Input API (`WM_INPUT`) |
|---|---|---|---|
| **Mechanism** | Win32 OS registration table | Global hook on input thread | HID driver raw message sink |
| **Pass-through Control** | **No** (Swallows key 100%) | **Yes** (Passes if Ctrl/Alt/Shift held) | **Always passes** (Cannot swallow) |
| **Game Compatibility** | May conflict if game registers key | Can bypass for whitelisted game processes | Purely passive observer |
| **HID Usages (Media/Fn)** | No (Keystrokes only) | No (Keystrokes only) | **Yes** (Captures Usage 0x6F/0x70) |
| **Performance / Timeout** | Zero overhead; OS managed | Must return < 300 ms or hook drops | High performance; non-blocking |

#### Recommended Hybrid Implementation:
- Use **`RegisterHotKey`** (or `WH_KEYBOARD_LL` with modifier bypass) for plain `VK_F6` (down) and `VK_F7` (up) with 5% or 10% steps.
- Use **`Raw Input`** for consumer control usages `0x6F` and `0x70`.
- Provide global fallback keys: `Ctrl + Alt + Up` / `Ctrl + Alt + Down`.

---

### 1.4 Clean On-Screen Display (OSD) Architecture

In NVIDIA GPU Only mode, Windows disables its native shell brightness flyout because the Intel `WmiMonitorBrightness` provider is gone. When hotkeys are pressed without an OSD, the user has no visual feedback.

#### Modern Acrylic OSD Window Design:
- **Window Styles:** `WS_POPUP | WS_VISIBLE`, Extended Styles: `WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`.
  * `WS_EX_NOACTIVATE`: Ensures the OSD never steals focus or causes full-screen games to minimize/alt-tab.
  * `WS_EX_TRANSPARENT`: Clicks pass directly through to whatever window is beneath.
- **Visual Appearance:**
  * Windows 11 style centered pill: 260px wide, 56px high, 24px border radius.
  * Dark acrylic / semi-transparent backdrop (`Color.FromArgb(235, 32, 32, 36)`).
  * Smooth horizontal progress track (clamped 10% to 100%) with sun icon.
  * Text display: `Brightness: 55% (NVIDIA)`.
- **Animation Lifecycle:**
  * Appears in 120 ms (fade in).
  * Persists for 1200 ms. If another hotkey is pressed, the timer resets and updates the slider position immediately.
  * Fades out over 250 ms.

---

## Part 2: Persistent 125% Display Scaling Deep-Dive

### 2.1 Root Cause: Scaling Desync across Display Mode Transitions

On a 15.6" Full HD (1920x1080) panel, 100% scaling (96 DPI) renders text too small for comfort, while 125% scaling (120 DPI, scale factor 1.25) provides the ideal physical size.

#### The Dual-Topology Desync Mechanism:
When Windows switches display modes via Advanced Optimus, it queries the display configuration via Connecting and Configuring Displays (CCD).
Windows does not key user scaling preferences to the physical glass; it keys them to the **Display Path Source & Target identity**:

```
Path A (Optimus):
Adapter: PCI\VEN_8086&DEV_A78B (Intel UHD)
Target:  AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050
Registry Key: HKCU:\Control Panel\Desktop\PerMonitorSettings\AUOAA9F0_...8086...^...

Path B (NVIDIA GPU Only):
Adapter: PCI\VEN_10DE&DEV_28E0 (RTX 4060)
Target:  AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
Registry Key: HKCU:\Control Panel\Desktop\PerMonitorSettings\AUOAA9F0_...10DE...^...
```

#### Actual Registry State on User System:
Direct inspection of `HKCU:\Control Panel\Desktop` and `PerMonitorSettings` reveals:
1. `HKCU:\Control Panel\Desktop\LogPixels = 120` (125% legacy/system DPI).
2. `PerMonitorSettings\..._8086_...` $\rightarrow$ `DpiValue = 0` (0 relative offset from recommended = 125%).
3. `PerMonitorSettings\..._10DE_...` $\rightarrow$ `DpiValue = 4294967295` (signed `-1`, 1 relative step down = 100%).

**The Result:** When the mux switches to NVIDIA, Windows reads `DpiValue = -1` and switches the display to 100% scale!

#### The DPI Virtualization & Blurry Text Trap:
Why does text become blurry instead of just smaller?
- When an application launches while Windows is at 100% (96 DPI), its GDI and DirectWrite font engines cache rasterized font glyphs rendered for 96 DPI.
- When the display mode flips, DWM sends `WM_DPICHANGED`. Applications that lack `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2` do not re-render glyphs.
- Instead, DWM places them in bitmap virtualization mode, scaling up the 100% rendered buffer to 125% using bilinear filtering. This produces blurry fonts, fuzzy text, and distorted UI elements.
- Furthermore, because `LogPixels` is set to 120 while the monitor is set to 100% (-1), System DPI and Monitor DPI are out of sync, breaking Win32 dialogs and non-client areas.

---

### 2.2 Windows Display Scaling Architecture & CCD APIs

Display scaling in modern Windows is managed via the **Connecting and Configuring Displays (CCD)** API in `user32.dll`.

#### Undocumented / Private CCD DPI Structures:

```c
// Device info request flags for DisplayConfigGetDeviceInfo / DisplayConfigSetDeviceInfo
#define DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE ((DISPLAYCONFIG_DEVICE_INFO_TYPE)-3)
#define DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE ((DISPLAYCONFIG_DEVICE_INFO_TYPE)-4)

// Scaling query packet
typedef struct _DISPLAYCONFIG_SOURCE_DPI_SCALE_GET {
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    int32_t minScaleRel;  // Minimum supported relative step (e.g., -1 for 100%)
    int32_t curScaleRel;  // Current applied step (0 = recommended, -1 = one step below)
    int32_t maxScaleRel;  // Maximum supported relative step (e.g., +3 for 200%)
} DISPLAYCONFIG_SOURCE_DPI_SCALE_GET;

// Scaling modification packet
typedef struct _DISPLAYCONFIG_SOURCE_DPI_SCALE_SET {
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    int32_t scaleRel;     // Relative step to set
} DISPLAYCONFIG_SOURCE_DPI_SCALE_SET;
```

#### Relative Step Mapping:
Windows defines standard scaling levels as an ordered array:
`[ 100%, 125%, 150%, 175%, 200%, 225%, 250%, 300%, 350%, 400%, 450%, 500% ]`
On the AUO AA9F 1080p panel:
- **Recommended Scale:** 125% (Step `0`).
- **Step `-1`:** 100% (Minimum floor, `minScaleRel = -1`).
- **Step `0`:** 125% (Target).
- **Step `+1`:** 150%.

To enforce 125% scaling programmatically:
Populate `DISPLAYCONFIG_SOURCE_DPI_SCALE_SET` with `scaleRel = 0` (or the step corresponding to 125%) and call `DisplayConfigSetDeviceInfo`.
**This applies the scaling factor instantly across DWM without requiring a user logoff or reboot.**

---

### 2.3 Permanent 125% Scale Enforcement Protocol

To guarantee that 125% scaling is locked and persistent across all modes without blur:

```
+----------------------------------------------------------------------------------------------------+
| 1. SYNCHRONIZE REGISTRY TOPOLOGIES (Cold-Boot & Pre-Switch Safety)                                 |
| Set LogPixels = 120 in HKCU:\Control Panel\Desktop                                                 |
| For every key in HKCU:\Control Panel\Desktop\PerMonitorSettings: Set DpiValue = 0 (125%)           |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
| 2. RUNTIME EVENT-DRIVEN ENFORCEMENT (Zero-Latency Mux Handling)                                    |
| Daemon window receives WM_DISPLAYCHANGE message                                                    |
| Call QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS) to get active adapter & source ID                   |
| Call DisplayConfigGetDeviceInfo(DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE)                           |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
| 3. VERIFY & ENFORCE                                                                                |
| Is active scale == 125% (curScaleRel == 0)?                                                        |
|   YES -> Do nothing (Already perfect, zero DWM blit, crisp text maintained)                         |
|   NO  -> Call DisplayConfigSetDeviceInfo(scaleRel = 0)                                             |
|          Update PerMonitorSettings registry key for new topology                                   |
+----------------------------------------------------------------------------------------------------+
```

#### Why This Prevents Blurry Fonts:
Because both the Intel and NVIDIA paths are permanently pinned to 120 DPI (125%):
1. When the mux switches, DWM never transitions from 100% to 125%.
2. Applications never receive a `WM_DPICHANGED` shift that forces them into bitmap stretching.
3. Every Win32, WPF, and Chromium application continues rendering with crisp 120 DPI font glyphs natively.

---

## Part 3: Recommended Unified Daemon Architecture

Instead of running two disconnected binaries (`PhantomGuard.exe` polling every 8 s, and `NvBrightness.exe` polling every 10 s), the system should be unified into a single, high-performance, event-driven engine: **`DisplayFixDaemon.exe`**.

```
+----------------------------------------------------------------------------------------------------+
|                                    DisplayFixDaemon.exe                                            |
|                  (Single Interactive Process, Scheduled Task: RunLevel Highest)                     |
+----------------------------------------------------------------------------------------------------+
  |                                 |                               |                              |
  v                                 v                               v                              v
[Module 1: Topology Sentinel]   [Module 2: Scaling Enforcer]    [Module 3: Brightness]         [Module 4: Input Router]
- WM_DISPLAYCHANGE listener     - Intercepts display change     - WmiSetBrightness (Intel)     - Plain VK_F6/VK_F7 (Hotkey)
- Clears phantom duplicate      - Queries CCD DPI scale         - NvWmiBrightness (NVIDIA)     - Fn-row Remapper (F1-F3, F9)
- Safety rails (cooldown,       - Applies 125% via CCD Set      - Safe 10% floor, +8 offset    - Raw Input HID 0x6F/0x70
  confirmations, no ext. mon)   - Pins PerMonitorSettings       - Smooth 5-10% stepping        - Floats acrylic OSD pill
```

### 3.1 Architectural Principles
1. **Single Elevated Interactive Process:**
   - Runs as a scheduled task at logon (`RunLevel Highest`) in the user's interactive session.
   - Has necessary privileges to query/write `root\wmi:NvWmiBrightness` and invoke `pnputil`.
   - Has access to user desktop session to install hotkeys, process `WM_INPUT`, update `HKCU`, and render the OSD.
2. **Event-Driven over Heavy Polling:**
   - Uses a hidden message window to receive `WM_DISPLAYCHANGE`, `WM_INPUT`, and `WM_HOTKEY`.
   - Reduces polling from 8-second tight loops to a low-frequency 30-second heartbeat check.
3. **Hardware Safety Guards:**
   - 10% minimum brightness floor enforced in code.
   - 60 s cooldown between adapter resets; stops after 3 failed attempts per episode.
   - Stands down completely if an external HDMI/DisplayPort monitor is connected.

---

### 3.2 Concrete C# API Implementations for Key Functions

#### Function 1: Programmatic DPI Scaling Enforcement via CCD
```csharp
[StructLayout(LayoutKind.Sequential)]
public struct LUID { public uint LowPart; public int HighPart; }

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
    public int type;
    public uint size;
    public LUID adapterId;
    public uint id;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int minScaleRel;
    public int curScaleRel;
    public int maxScaleRel;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int scaleRel;
}

public static bool SetDpiScaleTo125(LUID adapterId, uint sourceId) {
    // 1. Query relative bounds
    var getReq = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
    getReq.header.type = -3; // DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    getReq.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
    getReq.header.adapterId = adapterId;
    getReq.header.id = sourceId;

    if (DisplayConfigGetDeviceInfo(ref getReq) != 0) return false;

    // On this panel: Recommended is 125% (step 0).
    // If curScaleRel == 0, it is already 125%.
    if (getReq.curScaleRel == 0) return true;

    // 2. Set scale to 125% (relative step 0)
    var setReq = new DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
    setReq.header.type = -4; // DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    setReq.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET));
    setReq.header.adapterId = adapterId;
    setReq.header.id = sourceId;
    setReq.scaleRel = 0; // Target 125%

    return DisplayConfigSetDeviceInfo(ref setReq) == 0;
}
```

#### Function 2: Universal Dual-Backend Brightness Controller
```csharp
public static class BrightnessManager {
    private const int MinFloor = 10;
    private const int MaxCeil = 100;
    private const int NvOffset = 8; // Calibration offset for AUO AA9F panel

    public static bool SetBrightness(int targetLevel) {
        int level = Math.Max(MinFloor, Math.Min(MaxCeil, targetLevel));

        // 1. Try Intel WDDM / ACPI path
        try {
            using (var searcher = new ManagementObjectSearcher("root\\wmi", "SELECT * FROM WmiMonitorBrightnessMethods")) {
                foreach (ManagementObject mo in searcher.Get()) {
                    using (var inParams = mo.GetMethodParameters("WmiSetBrightness")) {
                        inParams["Timeout"] = (uint)0;
                        inParams["Brightness"] = (byte)level;
                        mo.InvokeMethod("WmiSetBrightness", inParams, null);
                        return true;
                    }
                }
            }
        } catch { }

        // 2. Fall back to NVIDIA WMI path
        try {
            int nvLevel = Math.Min(MaxCeil, level + NvOffset);
            using (var searcher = new ManagementObjectSearcher("root\\wmi", "SELECT * FROM NvWmiBrightness")) {
                foreach (ManagementObject mo in searcher.Get()) {
                    using (var inParams = mo.GetMethodParameters("NvGetSetBrightnessLevel")) {
                        inParams["inArg"] = (uint)1;
                        inParams["Level"] = (uint)nvLevel;
                        mo.InvokeMethod("NvGetSetBrightnessLevel", inParams, null);
                        return true;
                    }
                }
            }
        } catch { }

        return false;
    }
}
```

---

## Part 4: Verification and Validation Guide

### 4.1 Automated Validation Commands (PowerShell)

Run the following checks from an elevated prompt to independently verify the subsystems:

```powershell
# 1. Verify Active Display Path & Monitor Count (Must be 1 path, 1 present monitor)
Write-Host "=== Active Monitor Devices ==="
Get-PnpDevice -Class Monitor | Where-Object { $_.Present -eq $true } | Format-Table InstanceId, Status

# 2. Check Brightness WMI Subsystems
Write-Host "=== Brightness WMI Availability ==="
$intel = (Get-CimClass -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue) -ne $null
$nvidia = (Get-CimClass -Namespace root\wmi -ClassName NvWmiBrightness -ErrorAction SilentlyContinue) -ne $null
Write-Host "Intel WDDM Provider: $intel"
Write-Host "NVIDIA WMI Provider: $nvidia"

# 3. Verify Registry DPI Scaling (Must show LogPixels 120 and DpiValue 0 across all topologies)
Write-Host "=== DPI Registry State ==="
Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name LogPixels | Select-Object LogPixels
Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop\PerMonitorSettings\*' | Select-Object PSChildName, DpiValue
```

### 4.2 Step-by-Step Physical Verification Protocol
1. **DDS Switch Verification:**
   - In NVIDIA Control Panel, switch display mode from "Optimus" to "NVIDIA GPU Only".
   - Confirm screen switches cleanly without black screen or DWM crash.
   - Confirm `dwm.exe` CPU utilization remains below 2% at idle (no phantom duplicate leak).
2. **Brightness Hotkey Verification:**
   - Ensure Fn-Lock is enabled (`Fn + Esc`).
   - Press **F6**: Screen brightness decreases cleanly by 5% and OSD appears displaying the new level.
   - Press **F7**: Screen brightness increases cleanly by 5% and OSD appears.
   - Press **F1 / F2 / F3**: Verify Windows volume mute, down, and up respond as expected (preserving media functions).
3. **Display Scaling Verification:**
   - Switch between Optimus, Automatic, and NVIDIA GPU Only modes.
   - Verify Windows Settings $\rightarrow$ System $\rightarrow$ Display shows **125%** in all modes.
   - Open File Explorer and browser windows; confirm text fonts remain crisp and free from DWM bitmap scaling blur.
