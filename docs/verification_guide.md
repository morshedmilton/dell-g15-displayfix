# Dell G15 5530 DisplayFix — Physical & Automated Verification Guide

**Target Hardware:** Dell G15 5530 (Service Tag `CYFY434`, System SKU `0BF7`, BIOS `1.36.0`)  
**Processors & Graphics:** Intel Core i7-13650HX (`PCI\VEN_8086&DEV_A78B`) + NVIDIA GeForce RTX 4060 Laptop GPU (`PCI\VEN_10DE&DEV_28E0`)  
**Internal Display Panel:** AU Optronics `AUO AA9F` (1920×1080 @ 360.152Hz eDP panel)  
**Daemon Binary:** `C:\ProgramData\DisplayFix\DisplayFixDaemon.exe` (Scheduled Task: `DisplayFixDaemon`, `RunLevel: Highest`)

---

## 1. Overview & Prerequisites

This guide provides step-by-step physical verification procedures and automated diagnostic commands to confirm that all four Dell G15 5530 display subsystem defects are resolved across **Automatic**, **Optimus**, and **NVIDIA GPU Only** modes:

1. **Zero-Lag Display Mode Switching & Ghost Monitor Eviction**: Sub-second eviction of the unclocked Intel eDP ghost monitor (`UID8388688`), keeping `dwm.exe` CPU usage at `< 3%` at idle with zero input stalls or black screens.
2. **Native 360Hz Refresh Rate Lock**: Automatic enforcement of the native `360.152Hz` (`360152 / 1000`) refresh rate across display mux switches and sleep/wake cycles.
3. **Persistent 125% Display Scaling (`120 DPI`)**: Synchronized `PerMonitorSettings` registry keys (`DpiValue = 0`) and dynamic Windows CCD DPI scaling (`scaleRel = 0`) across both Intel and NVIDIA topologies with crisp, blur-free text and zero logoff/reboot required.
4. **F6 / F7 Brightness Hotkeys & Non-Activating Acrylic OSD**: Out-of-the-box `F6` (decrease brightness) and `F7` (increase brightness) hotkey control in both **NVIDIA GPU Only** and **Optimus** modes, with a `10%` minimum safety floor, `+8` NVIDIA WMI calibration offset, preserved media keys (`F1`–`F3`, `F9`), and a non-activating Windows 11 Acrylic OSD pill overlay.

### Prerequisites Before Testing
1. Open **Windows PowerShell as Administrator** (`Run as Administrator`).
2. Ensure `DisplayFixDaemon` is built and installed:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build.ps1
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
3. Confirm the daemon is active by running:
   ```powershell
   .\bin\DisplayFixDaemon.exe --status
   ```
   Verify the output reports `Mutex Active: True`, `Process Running: True`, `Refresh Rate (Hz): 360 Hz`, and `Display Scaling (%): 125%`.

---

## 2. Automated Verification Quick-Start

Before or after performing physical checks, run the master acceptance verification script from an elevated PowerShell prompt:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

To run individual diagnostic probes or the 29-suite (136-test) End-to-End test harness directly:

```powershell
# 1. Live System & Display Topology Telemetry Probe (Feature F01)
powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\probe_system.ps1

# 2. Desktop Window Manager (DWM) Health & Event Log Monitor (Feature F02)
powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\dwm_health.ps1

# 3. Display Switching Stress Test Harness (Feature F03 - 10-iteration smoke test or 100-iteration soak test)
powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\stress_test.ps1 -Iterations 10
powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\stress_test.ps1 -Iterations 100

# 4. Complete 29-Suite (136-Test) Opaque-Box E2E Test Runner (Feature F16)
powershell -ExecutionPolicy Bypass -File .\tests\e2e\test_runner.ps1

# 5. Display Mode Switching & MUX Diagnostic Prober (Milestone MR2)
powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\test_display_modes.ps1
```

---

## 3. Step-by-Step Physical Testing: Display Switching (`Automatic` / `Optimus` / `NVIDIA GPU Only`)

### 3.0 Restoring Display Mode Switching: Dell UEFI BIOS Setup (F2) & Hardware MUX Configuration
If **Optimus** and **Automatic Select** are grayed out or locked to **NVIDIA GPU only** in NVIDIA Control Panel, the laptop's hardware multiplexer has been locked to Discrete-Only mode at the firmware level. Follow these steps to restore dynamic switching:

1. **Reboot into Dell UEFI BIOS Setup**:
   - Restart the Dell G15 5530 laptop (`Start > Power > Restart`).
   - As soon as the computer restarts and the Dell logo appears, repeatedly tap the **F2** key until "Entering BIOS Setup" appears in the top-right corner.
2. **Navigate to the Display Settings Menu**:
   - In the left navigation menu, click to expand **Display** (or **Video**).
3. **Configure the Hybrid Graphics / Advanced Optimus Toggle**:
   - Locate the setting labeled **"Hybrid Graphics / Advanced Optimus"** (Default: Enabled/ON).
   - If this setting is set to **Disabled / OFF**, the firmware hardware-locks the eDP panel to the discrete RTX 4060 and disables the ACPI Dynamic Display Switching (DDS) methods, forcing Windows into Discrete GPU Only mode and permanently graying out Optimus and Automatic Select in NVIDIA Control Panel.
   - Toggle the switch to **Enabled / ON**.
4. **Save Configuration and Exit**:
   - Click **Apply Changes** at the bottom of the screen.
   - Click **Exit** (or press **F10**) to restart the laptop into Windows 11.
5. **Confirm Normal Thermal / G-Mode State**:
   - After Windows boots, verify that the **G-Key (F9)** Game Shift mode is not active (fans running at normal quiet speeds, not 100% emergency lock).
   - In **Alienware Command Center (AWCC)**, confirm the thermal profile is set to **Balanced** or **Performance** (not an override profile that locks dGPU).
6. **Verify Display Mode Switching Readiness via Diagnostic Script**:
   - Run the automated prober to verify adapter health, ACPI tables, and daemon stand-down readiness:
     ```powershell
     powershell -ExecutionPolicy Bypass -File .\scripts\diagnostics\test_display_modes.ps1
     ```
   - Verify that the prober reports `DIAGNOSTIC VERDICT: PASSED`.
7. **Verify Persistent Mode Switching in NVIDIA Control Panel**:
   - Open **NVIDIA Control Panel** -> **Manage Display Mode**.
   - Confirm that all three modes are now available and selectable:
     - [x] **Automatic Select**
     - [x] **Optimus**
     - [x] **NVIDIA GPU only**
   - Select **Optimus** and click **Apply** -> confirm the panel switches to Intel UHD Graphics and `DisplayFixDaemon` stands down.
   - Select **Automatic Select** and click **Apply** -> confirm dynamic switching on demand.
   - Settings persist cleanly across reboots.

### 3.1 Switching via NVIDIA Control Panel or NVIDIA App
1. Open **NVIDIA Control Panel** (or **NVIDIA App** -> **System** -> **Displays**).
2. In NVIDIA Control Panel, expand **3D Settings** in the left navigation pane and click **Manage Display mode** (Advanced Optimus / Dynamic Display Switching).
3. Observe the three available display mux modes:
   - **Automatic Select** (`Automatic`)
   - **Optimus** (Internal panel driven by Intel UHD Graphics; dGPU renders on demand)
   - **NVIDIA GPU only** (`NVIDIA GPU Only` — Internal panel physically muxed to the NVIDIA GeForce RTX 4060 Laptop GPU)
4. **Test Transition 1 (`Optimus` -> `NVIDIA GPU Only`)**:
   - Select **NVIDIA GPU only** and click **Apply**.
   - **Expected Physical Behavior**:
     - The hardware display multiplexer switches the eDP panel to the RTX 4060 within 1–2 seconds.
     - `DisplayFixDaemon` detects the `WM_DISPLAYCHANGE` / `WM_DEVICECHANGE` broadcast within `< 100ms`, coalesces burst notifications over a `200ms` quiet window, and evicts the stale Intel eDP ghost monitor (`DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688`) in-process via `CfgMgr32` (`CM_Disable_DevNode` / `CM_Enable_DevNode`) in `< 100ms`.
     - Move the mouse cursor continuously in circles and type in a text editor: there are **zero 1-second input stalls**, **zero black screens**, and **zero secondary screen blinks** 16 seconds later.
5. **Test Transition 2 (`NVIDIA GPU Only` -> `Optimus`)**:
   - Select **Optimus** and click **Apply**.
   - **Expected Physical Behavior**:
     - The panel cleanly routes back to Intel UHD Graphics (`UID8388688`).
     - `DisplayFixDaemon` stands down ghost eviction (since Intel is now the active primary display path) while maintaining **360Hz** refresh rate and **125%** scaling.
6. **Test Transition 3 (`Optimus` -> `Automatic` and Launching a 3D Game)**:
   - Select **Automatic Select** (`Automatic`) and click **Apply**.
   - Launch a DirectX 11/12 or Vulkan full-screen game so NVIDIA Advanced Optimus dynamically switches the panel to the RTX 4060, then exit the game to return to **Optimus**.
   - **Expected Physical Behavior**:
     - Both the game-launch mux transition and game-exit return transition complete smoothly without minimizing the game, crashing `dwm.exe`, or triggering a GPU TDR reset (`Event ID 4101`).

### 3.2 Verifying Single Active Display Topology & Low DWM CPU Load
After switching to **NVIDIA GPU Only** mode:
1. Right-click the Desktop and select **Display settings** (`Win + I` -> **System** -> **Display**).
2. Confirm that **only 1 display rectangle** is shown (no phantom Display 1 / Display 2 split boxes).
3. Open **Task Manager** (`Ctrl + Shift + Esc`) -> **Details** tab -> locate `dwm.exe`:
   - Confirm `dwm.exe` CPU utilization at desktop idle is **`0.5% – 2.5%`** (eliminating the `31% – 54%` V-Sync starvation stall).
   - Confirm `dwm.exe` Memory (Working Set) is **`< 250 MB`** and Handles are **`< 2500`**.
4. Inspect the daemon log to see the exact sub-second eviction telemetry:
   ```powershell
   Get-Content "C:\ProgramData\DisplayFix\logs\daemon.log" -Tail 25
   ```

---

## 4. Step-by-Step Physical Testing: 360Hz Refresh Rate Verification

Windows and GPU driver resets can occasionally drop high-refresh eDP panels from `360Hz` down to `60Hz` during a mux transition or lid sleep/resume cycle. `DisplayFixDaemon` locks the exact native rational timing (`360152 / 1000 = 360.152Hz`) via Windows CCD `SetDisplayConfig` (`SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_SAVE_TO_DATABASE | SDC_ALLOW_CHANGES`).

### 4.1 Verifying 360Hz in Windows Advanced Display Settings
1. Press `Win + I` to open **Windows Settings** -> **System** -> **Display**.
2. Scroll down and click **Advanced display**.
3. Locate **Choose a refresh rate** next to the internal display (`Internal Display` / `AUO AA9F`):
   - Confirm the dropdown displays **`360 Hz`** (or **`360.15 Hz`**) in **Optimus**, **Automatic**, and **NVIDIA GPU Only** modes.

### 4.2 Testing Automatic 60Hz -> 360Hz Self-Healing Recovery
1. In **Settings** -> **System** -> **Display** -> **Advanced display**, manually change the refresh rate dropdown from **360 Hz** to **60 Hz** (or trigger a mode switch).
2. Observe that `DisplayFixDaemon` immediately intercepts the resulting `WM_DISPLAYCHANGE` notification and automatically snaps the panel back to **360Hz** within `< 300ms` (200ms debounce + `< 35ms` CCD `SetDisplayConfig` execution).
3. You can also trigger one-shot 360Hz enforcement manually from the CLI at any time:
   ```powershell
   .\bin\DisplayFixDaemon.exe --lock-360hz
   ```

---

## 5. Step-by-Step Physical Testing: 125% DPI Scaling & Crisp Font Verification

On the Dell G15 5530, Windows creates separate `HKCU\Control Panel\Desktop\PerMonitorSettings` registry keys for the Intel (`8086_A78B`) and NVIDIA (`10DE_28E0`) topologies. Previously, the NVIDIA topology key defaulted to `DpiValue = 4294967295` (`-1`), dropping display scaling from **125%** to **100%** whenever the display muxed to the dGPU and causing blurry bitmap-stretched text in Win32 applications.

### 5.1 Verifying 125% Scaling in Windows Display Settings
1. Press `Win + I` to open **Windows Settings** -> **System** -> **Display**.
2. Under **Scale & layout**, inspect the **Scale** setting:
   - Confirm it reads **`125% (Recommended)`** while in **Optimus** mode.
3. Switch display mode to **NVIDIA GPU Only** in NVIDIA Control Panel.
4. Return to **Windows Settings** -> **System** -> **Display**:
   - Confirm **Scale** remains locked at **`125% (Recommended)`** immediately after the switch—without dropping to `100%` and without requiring a Windows sign-out or reboot.

### 5.2 Visual Crisp Font Verification (Zero Blur Check)
1. Open **Device Manager** (`devmgmt.msc`), **Task Manager**, and **Windows Notepad** side by side.
2. Perform a display switch from **Optimus** to **NVIDIA GPU Only** and back to **Optimus**.
3. Inspect the menu bars, tree views, and body text in all open windows:
   - Text must remain razor-sharp at native `120 DPI` (`125%`) with zero GDI bitmap scaling blur or layout jumping.
4. Verify multi-topology registry synchronization via CLI:
   ```powershell
   .\bin\DisplayFixDaemon.exe --sync-dpi
   Get-ChildItem "HKCU:\Control Panel\Desktop\PerMonitorSettings" | Where-Object { $_.PSChildName -like "*AUOAA9F*" } | ForEach-Object {
       [PSCustomObject]@{ TopologyKey = $_.PSChildName; DpiValue = (Get-ItemProperty $_.PSPath).DpiValue }
   }
   ```
   Confirm every `AUOAA9F` topology key reports `DpiValue = 0` and `HKCU:\Control Panel\Desktop\LogPixels` equals `120`.

---

## 6. Step-by-Step Physical Testing: F6 / F7 Brightness Keys, `Fn + Esc`, Media Keys & Acrylic OSD

When the internal panel is muxed to the RTX 4060 (`NVIDIA GPU Only` mode) and the stale Intel eDP node is evicted, Dell's EC/ACPI brightness events (`WmiMonitorBrightnessMethods`) are no longer routed by Windows. `DisplayFixDaemon` solves this by intercepting `F6` and `F7` via a low-level keyboard hook (`WH_KEYBOARD_LL`) and Raw Input (`HID 0x0C:0x006F / 0x0070`), routing adjustments dynamically to `root\wmi:NvWmiBrightness` in NVIDIA mode (with `+8` offset calibration and a hard `10%` floor) or `root\wmi:WmiMonitorBrightnessMethods` in Optimus mode.

### 6.1 Function Key Mode Setup (`Fn + Esc` Fn-Lock Check)
On the Dell G15 5530 keyboard, when Fn-lock is in media mode, the embedded controller (EC) swallows bare `F6`/`F7` presses in hardware when the Intel ACPI provider is offline. Putting the function row into **Function Key mode** (`Fn + Esc`) ensures bare `F6` and `F7` emit standard `VK_F6` (`0x75`) and `VK_F7` (`0x76`) keystrokes that `DisplayFixDaemon` intercepts globally:
1. Press **`Fn + Esc`** on the laptop keyboard to toggle Fn-lock so that pressing `F6` / `F7` directly (without holding `Fn`) sends `VK_F6` / `VK_F7`.
   - *(Tip: If pressing `F6` alone does not trigger the brightness OSD pill, press **`Fn + Esc`** once and try `F6` again.)*

### 6.2 Testing `F6` (Brightness Down) & `F7` (Brightness Up) in Both GPU Modes
1. **In `NVIDIA GPU Only` Mode**:
   - Press **`F6`** (without holding `Fn`):
     - Screen backlight smoothly decreases by `5%`.
     - The dark translucent **Windows 11 Acrylic OSD pill** (`260×56px`, rounded corners) appears near the bottom-center of the screen showing the sun icon, progress bar, percentage, and `NVIDIA` backend badge, then auto-dismisses after `1.5 seconds`.
   - Press **`F7`** (without holding `Fn`):
     - Screen backlight smoothly increases by `5%` up to `100%`.
   - Repeatedly press **`F6`** all the way down:
     - Confirm the brightness stops at the **`10%` safety floor** and **never turns the eDP backlight completely black (`0%`)**.
2. **In `Optimus` Mode**:
   - Switch to **Optimus** mode and press **`F6`** and **`F7`** (without holding `Fn`):
     - Backlight decreases and increases smoothly in `5%` steps via the `Optimus` (`WmiMonitorBrightnessMethods`) backend, displaying the Acrylic OSD overlay.
3. **Testing Brightness Persistence Across Display Switches**:
   - Set brightness to **`65%`** using `F6`/`F7`, then switch between **Optimus** and **NVIDIA GPU Only** modes.
   - Confirm the panel brightness remains at **`65%`** after the switch without blasting to `100%`.

### 6.3 Testing Modifier Bypass (`Ctrl`/`Alt`/`Shift` + `F6`/`F7`)
1. Open an IDE or browser and press **`Ctrl + F6`**, **`Alt + F7`**, or **`Shift + F6`**.
2. Confirm that `DisplayFixDaemon` **passes modified key chords straight through** to the foreground application without changing screen brightness.

### 6.4 Testing Preserved Function Row Media Keys (`F1`, `F2`, `F3`, `F9`)
With `Fn + Esc` in Function Key mode, `DisplayFixDaemon` automatically remaps the media keys printed on the Dell G15 5530 keycaps via 64-bit `SendInput` synthesis so you do not need to hold `Fn` for audio/media control:
1. Press **`F1`** -> Toggles system **Audio Mute** (`VK_VOLUME_MUTE`).
2. Press **`F2`** -> Decreases system **Volume Down** (`VK_VOLUME_DOWN`).
3. Press **`F3`** -> Increases system **Volume Up** (`VK_VOLUME_UP`).
4. Press **`F9`** -> Toggles **Media Play / Pause** (`VK_MEDIA_PLAY_PAUSE`).

### 6.5 Verifying Non-Activating OSD Behavior in Full-Screen Games
1. Launch a full-screen game or video player, or run the built-in OSD focus test:
   ```powershell
   .\bin\DisplayFixDaemon.exe --test-osd 65
   ```
2. Press **`F6`** or **`F7`** while typing in a window or playing a full-screen game:
   - Because the OSD window uses `WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW` (`0x080800A8`), the foreground window **never loses focus** and full-screen games **never minimize or alt-tab**.

---

## 7. CLI Reference & Troubleshooting

### 7.1 `DisplayFixDaemon.exe` Command-Line Switches
| Command | Description |
|---|---|
| `DisplayFixDaemon.exe --run` | Starts the resident background daemon (default when invoked with no arguments). |
| `DisplayFixDaemon.exe --status` | Prints live mutex state, daemon PID, refresh rate (Hz), DPI scaling (%), brightness (%), and log status. |
| `DisplayFixDaemon.exe --evict-now` | Executes an immediate one-shot ghost monitor eviction check (`< 100ms`). |
| `DisplayFixDaemon.exe --lock-360hz` | Executes an immediate one-shot `360.152Hz` (`360152/1000`) refresh rate lock. |
| `DisplayFixDaemon.exe --sync-dpi` | Synchronizes `PerMonitorSettings` registry keys (`DpiValue = 0`, `LogPixels = 120`) and enforces `125%` CCD DPI scaling. |
| `DisplayFixDaemon.exe --brightness-get` | Prints current brightness percentage, active WMI backend, and WMI schema availability. |
| `DisplayFixDaemon.exe --brightness-set <10..100>` | Sets panel brightness to `<level>%` (clamped to `[10, 100]`) and displays the Acrylic OSD. |
| `DisplayFixDaemon.exe --brightness-up` | Increases brightness by `5%` and displays the Acrylic OSD. |
| `DisplayFixDaemon.exe --brightness-down` | Decreases brightness by `5%` and displays the Acrylic OSD. |
| `DisplayFixDaemon.exe --test-osd [level]` | Renders the Acrylic OSD and verifies Win32 extended styles and foreground focus preservation. |
| `DisplayFixDaemon.exe --install` | Delegates to `scripts\install.ps1` to register the elevated logon scheduled task. |
| `DisplayFixDaemon.exe --uninstall` | Delegates to `scripts\uninstall.ps1` to stop the daemon, unregister tasks, and clean `C:\ProgramData\DisplayFix`. |

### 7.2 Customizing Function Row Keys (`C:\ProgramData\DisplayFix\hotkeys.ini`)
You can customize which function keys are intercepted by editing `C:\ProgramData\DisplayFix\hotkeys.ini`:
```ini
[Hotkeys]
BrightnessDown=F6
BrightnessUp=F7
Step=5
Mute=F1
VolumeDown=F2
VolumeUp=F3
PlayPause=F9
```
Restart the scheduled task (`Start-ScheduledTask -TaskName "DisplayFixDaemon"`) after editing `hotkeys.ini`.

### 7.3 Log Files & Diagnostic Artifacts
- **Daemon Runtime Log**: `C:\ProgramData\DisplayFix\logs\daemon.log` (5 MB automatic rotation).
- **Live Telemetry Snapshot**: `C:\ProgramData\DisplayFix\logs\telemetry.json` (generated by `probe_system.ps1`).
- **Stress Test Reports**: `C:\ProgramData\DisplayFix\logs\stress_test_report_*.json` and `.md` (generated by `stress_test.ps1`).

---

## 8. Milestone MR3: NVIDIA App Driver Download & Automatic Tuning

### 8.1 Root Cause of the Infinite Download Loop & Tuning Freeze
On Dell G15 5530 laptops, the NVIDIA App can enter an infinite downloading/loading loop due to orphaned post-processing tasks in `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework`:
1. **Stale OTA Artifacts**: An incomplete or interrupted download creates an 800+ MB payload locked in `updateState: 1` (post-processing extraction phase).
2. **Corrupted Status JSON**: `grd\download.json` reports completion (`state: 8`), while `grd\postprocessing.json` remains in a stalled extraction state (`status: 1`).
3. **CEF WebView Freeze**: The Chromium Embedded Framework web cache locks the Driver UI tab into an unrecoverable spinner.

### 8.2 Automated One-Click Remediation
The project provides an automated, idempotent remediation script:
```powershell
powershell -ExecutionPolicy Bypass -File "scripts\remedy_nvidia_app.ps1"
```
The script performs 7 non-destructive repair steps:
1. Closes stale NVIDIA App UI and overlay processes (`nvsphelper64`, `NVIDIA Overlay`).
2. Clears locked driver packages from `UpdateFramework\ota-artifacts`.
3. Resets `grd\download.json` and `grd\postprocessing.json` to idle states (`[]`).
4. Resets `nvapp\autoupdate.json` to idle (`updateState: 0, currentPhase: 0`).
5. Purges stale CEF webview caches in `%LOCALAPPDATA%`.
6. Validates and restarts `NVDisplay.ContainerLocalSystem` and `NvContainerLocalSystem`.
7. Checks and starts the NVIDIA FrameView SDK service.

### 8.3 Verifying Driver Download and Automatic Tuning
1. **Test Driver Download**:
   - Open **NVIDIA App** from the Start Menu or System Tray.
   - Click the **Drivers** tab on the left sidebar.
   - Click **Download** next to the latest GeForce Game Ready Driver.
   - Confirm the download starts cleanly with progress percentage and completes without looping.
2. **Test Automatic Tuning**:
   - In NVIDIA App, navigate to **System** -> **Performance**.
   - Toggle **Automatic Tuning** to **ON**.
   - Confirm the scan initiates or toggles cleanly without hanging or locking up.

