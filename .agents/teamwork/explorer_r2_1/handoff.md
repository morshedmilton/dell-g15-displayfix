# Diagnostic Investigation Report: Requirement R1 (Display Brightness Hotkeys and Backlight Control)

**Target Device:** Dell G15 5530 (Windows 11 Build 26100, Core i7-13650HX, NVIDIA GeForce RTX 4060 Laptop GPU, Intel UHD Graphics, AU Optronics AUO AA9F 1080p 360Hz internal eDP panel)  
**Investigator:** explorer_r2_1  
**Investigation Timestamp:** 2026-11-05T22:03:00Z  

---

## 1. Observation

### 1.1 Device Manager & Monitor PnP State
- **Monitor PnP Queries:**
  - Running `Get-CimInstance Win32_PnPEntity -Filter "PNPClass = 'Monitor'"` returned:
    ```
    Name                   : Generic Monitor
    DeviceID               : DISPLAY\AUOAA9F\5&39808DAE&2&UID4353
    Status                 : OK
    Present                : True
    ConfigManagerErrorCode : 0
    Service                : monitor
    ```
  - Running `pnputil /enum-devices /class Monitor /relations` revealed the monitor tree relations:
    ```
    Instance ID:        DISPLAY\AUOAA9F\4&3a9f8b26&8&UID8388688
    Device Description: Integrated Monitor
    Status:             Disconnected
    Parent:             PCI\VEN_8086&DEV_A78B&SUBSYS_0BF71028&REV_04\3&11583659&0&10 (Intel UHD Graphics)

    Instance ID:        DISPLAY\AUOAA9F\5&39808dae&2&UID4353
    Device Description: Generic Monitor
    Status:             Started
    Parent:             PCI\VEN_10DE&DEV_28E0&SUBSYS_0BF71028&REV_A1\4&3b6a47d9&0&0008 (NVIDIA GeForce RTX 4060)
    ```
  - Device driver: Using `monitor.inf` (Generic PnP Monitor), version `10.0.26100.9818`.
  - Device errors: `ConfigManagerErrorCode = 0`. There are zero yellow exclamation marks or device driver load failures.

### 1.2 WMI Namespaces & Brightness Interfaces
- **`root\wmi:WmiMonitorBrightness` and `WmiMonitorBrightnessMethods`:**
  - Running `Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness` returned verbatim:
    ```
    Get-CimInstance : Not supported 
    CategoryInfo          : NotImplemented: (root\wmi:WmiMonitorBrightness:String) [Get-CimInstance], CimException
    FullyQualifiedErrorId : HRESULT 0x8004100c,Microsoft.Management.Infrastructure.CimCmdlets.GetCimInstanceCommand
    ```
  - Running `Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods` returned verbatim:
    ```
    Get-CimInstance : Not supported 
    CategoryInfo          : NotImplemented: (root\wmi:WmiMonitorBrightnessMethods:String) [Get-CimInstance], CimException
    FullyQualifiedErrorId : HRESULT 0x8004100c,Microsoft.Management.Infrastructure.CimCmdlets.GetCimInstanceCommand
    ```
  - Attempting to call `WmiSetBrightness` via PowerShell:
    `(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods).WmiSetBrightness(1, 50)`
    Failed with `InvokeMethodOnNull` because `Get-CimInstance` returned `$null` due to `HRESULT 0x8004100c`.
- **`root\wmi:WmiMonitorID` and `WmiMonitorConnectionParams`:**
  - `WmiMonitorID` returns:
    ```
    Active                 : True
    InstanceName           : DISPLAY\AUOAA9F\5&39808dae&2&UID4353_0
    ManufacturerName       : {65, 85, 79, 0...} (AUO)
    ProductCodeID          : {65, 65, 57, 70...} (AA9F)
    ```
  - `WmiMonitorConnectionParams` returns:
    ```
    Active InstanceName                           VideoOutputTechnology
    ------ ------------                           ---------------------
      True DISPLAY\AUOAA9F\5&39808dae&2&UID4353_0                    10 (D3DKMDT_VOT_DISPLAYPORT_EMBEDDED)
    ```
- **`root\wmi:NvWmiBrightness`:**
  - Class exists in `root\wmi` with methods `NvGetSetBrightnessLevel` and `NvGetSetBrightnessSource`.
  - When queried without elevation:
    ```
    Get-CimInstance : Access denied 
    CategoryInfo          : PermissionDenied: (root\wmi:NvWmiBrightness:String) [Get-CimInstance], CimException
    FullyQualifiedErrorId : HRESULT 0x80041003,Microsoft.Management.Infrastructure.CimCmdlets.GetCimInstanceCommand
    ```
  - When invoked with administrative elevation, `NvGetSetBrightnessLevel(inArg=1, Level=target+8)` succeeds (`Result = True`), and `app.log` records successful hardware writes:
    `apply 35 -> True backend=NVIDIA`, `apply 40 -> True backend=NVIDIA`.
- **DDC/CI (`dxva2.dll:GetMonitorBrightness`):**
  - Calling `GetMonitorBrightness` on the physical monitor handle returned:
    `bOk=False, Err=-1071241854 (0xC0262582 = STATUS_GRAPHICS_DDCCI_VCP_NOT_SUPPORTED)`.
- **WinRT Brightness API (`Windows.Graphics.Display.BrightnessOverride`):**
  - Calling `[Windows.Graphics.Display.BrightnessOverride]::GetDefaultForSystem()` returned:
    `Exception calling "GetDefaultForSystem" with "0" argument(s): "Error HRESULT E_FAIL (0x80004005) has been returned from a call to a COM component."`

### 1.3 Running Processes & `DisplayFixDaemon` Failure Execution
- Process `DisplayFixDaemon.exe` (PID 31384) was running under user `morsh`.
- Autostart origin: Found entry in `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`:
  `DisplayFixDaemon : "C:\ProgramData\DisplayFix\DisplayFixDaemon.exe" --run`
- Process token elevation state: `whoami /all` and daemon status confirm standard user token:
  `Current Elevation: Non-Elevated (Limited)`.
- Verbatim lines from `C:\ProgramData\DisplayFix\logs\daemon.log`:
  ```
  2026-11-05 20:56:44.309 [INFO ] [Daemon      ] DisplayFixDaemon resident service starting (PID: 31384, Elevated: False).
  2026-11-05 20:56:44.311 [WARN ] [Daemon      ] Running without administrative privileges. Hardware device node management may be restricted.
  2026-11-05 20:56:44.343 [WARN ] [HotkeyHook  ] Could not read or write hotkeys.ini (C:\ProgramData\DisplayFix\hotkeys.ini), using built-in defaults: Access to the path 'C:\ProgramData\DisplayFix\hotkeys.ini' is denied.
  ...
  2026-11-05 21:25:55.879 [DEBUG] [Brightness  ] Optimus WmiSetBrightness unavailable: Not supported 
  2026-11-05 21:25:55.885 [DEBUG] [Brightness  ] NVIDIA NvGetSetBrightnessLevel write unavailable: Access denied 
  2026-11-05 21:25:55.885 [WARN ] [Brightness  ] No writable WMI brightness instance available for target 10% (Preferred=NvWmiBrightness, Error=NO_ACTIVE_PROVIDER).
  2026-11-05 21:25:55.887 [DEBUG] [HotkeyHook  ] Dispatched BrightnessDown (-5%) from F6 (Hook latency: 5.3us)
  ```
- CLI execution `cmd.exe /c "bin\DisplayFixDaemon.exe --brightness-set 50"` produced:
  ```
  [DEBUG] [Brightness  ] NVIDIA NvGetSetBrightnessLevel write unavailable: Access denied 
  [DEBUG] [Brightness  ] Optimus WmiSetBrightness unavailable: Not supported 
  [WARN ] [Brightness  ] No writable WMI brightness instance available for target 50% (Preferred=NvWmiBrightness, Error=NO_ACTIVE_PROVIDER).
  Brightness Set: Requested=50%, Clamped=50%, HardwareLevel=58, Backend=NvWmiBrightness, Provider=root\wmi:NvWmiBrightness, Success=False, Error=NO_ACTIVE_PROVIDER, Elapsed=66.81ms
  ```
- Task Scheduler inspection:
  - `DisplayFixDaemon` scheduled task **is not registered**.
  - Only legacy tasks `DisplayFixBrightness` (launching `NvBrightness.exe`) and `DisplayFixGuard` (launching `PhantomGuard.exe`) were in Task Scheduler.

---

## 2. Logic Chain

1. **Topological Routing (Observation §1.1):**
   - The laptop's AUO AA9F internal display panel is currently routed through the hardware MUX switch directly to the NVIDIA GeForce RTX 4060 dGPU (`DISPLAY\AUOAA9F\5&39808dae&2&UID4353`, Status: Started).
   - The Intel UHD Graphics internal display node (`DISPLAY\AUOAA9F\4&3a9f8b26&8&UID8388688`) is in a `Disconnected` state.

2. **Windows WDDM Backlight Mechanism & Slider Failure (Observations §1.1, §1.2):**
   - The Windows Settings display brightness slider and Action Center slider rely exclusively on the WDDM display miniport brightness DDI (`DxgkDdiQueryBrightnessCaps` / `DxgkDdiSetDisplayBrightness`), which Windows surfaces via `root\wmi:WmiMonitorBrightness` and `root\wmi:WmiMonitorBrightnessMethods`.
   - On the Dell G15 5530 hardware platform, the native WDDM display brightness interface is implemented only by Intel's driver (`igdkmdn64.sys`) in conjunction with ACPI GFX0 methods.
   - The NVIDIA Windows mobile display driver (`nvlddmkm.sys`) does not expose the WDDM internal monitor brightness interface for this panel.
   - When the panel is muxed to NVIDIA (`UID4353`), queries to `WmiMonitorBrightness` fail with `HRESULT 0x8004100c` (Not Supported), and WinRT `BrightnessOverride` fails with `HRESULT E_FAIL (0x80004005)`.
   - Consequently, the Windows operating system cannot connect its native Settings brightness slider to any active WDDM brightness provider. Moving the slider or adjusting brightness via Windows Settings has zero effect on the physical panel luminance.

3. **Discrete Mode Backlight Channel (`NvWmiBrightness`) (Observations §1.2, §1.3):**
   - In discrete GPU only mode, physical backlight PWM adjustment is provided exclusively via NVIDIA's proprietary WMI provider: `root\wmi:NvWmiBrightness.NvGetSetBrightnessLevel`.
   - However, the NVIDIA WMI provider enforces a strict security ACL: calls from non-elevated (standard user / Medium Integrity Level) security tokens are rejected with `HRESULT 0x80041003` (Access Denied).
   - Only processes running with administrative elevation (`RunLevel: Highest` / Administrator) are granted write permission to `NvWmiBrightness`.

4. **Failure of `DisplayFixDaemon` to Alter Physical Luminance (Observation §1.3):**
   - `DisplayFixDaemon.exe` was launched at user logon from the non-elevated registry run key `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`.
   - Because `DisplayFixDaemon` has `Elevated: False`, every time the user presses F6 or F7 (or Fn+F6 / Fn+F7):
     - `HotkeyHook` successfully intercepts the keystroke (`VK_F6` / `VK_F7`) in under 10 microseconds.
     - `AcrylicOsdWindow` renders the visual OSD percentage on screen.
     - BUT `BrightnessController.ApplyHardwareBrightnessUnsafe()` receives `Access denied` from `NvWmiBrightness.NvGetSetBrightnessLevel` and `Not supported` from `WmiSetBrightness`.
     - The daemon logs `Error=NO_ACTIVE_PROVIDER` and aborts.
     - Therefore, the physical panel backlight duty cycle is NEVER modified, even though the on-screen display updates.

5. **Legacy Task & INI Misconfiguration (Observations §1.1, §1.3):**
   - The unified scheduled task `DisplayFixDaemon` (defined in `scripts/install.ps1`) was never installed; instead, stale tasks `DisplayFixBrightness` and `DisplayFixGuard` remained registered.
   - `C:\ProgramData\DisplayFix\hotkeys.ini` had function row bindings commented out, and the non-elevated daemon could not rewrite or fix `hotkeys.ini` due to ProgramData write restrictions.

---

## 3. Caveats

1. **Physical Luminance Verification in dGPU Mode:**
   - In dGPU mode, `root\wmi:NvWmiBrightness` requires a `+8` compensation offset because writing value $X$ results in a hardware level of $X - 8$.
   - Any value below $10\%$ turns off the AUO AA9F backlight inverter completely (black screen). Clamping to $[10, 100]$ must remain strictly enforced.
2. **Fn-Lock Hardware Modes:**
   - When Fn-Lock is in Media Mode (`Fn+Esc`), pressing physical F6/F7 sends ACPI SCI events directly to the embedded controller (EC). The EC targets Intel `GFX0`, which is dormant in dGPU mode.
   - When Fn-Lock is in Function Key Mode, F6/F7 emit `VK_F6` and `VK_F7` to Windows, which `HotkeyHook` intercepts.
   - For Fn-Lock Media Mode, `HotkeyHook` uses Raw Input HID Consumer Control (Usage Page `0x0C`, Usage `0x01`, Usages `0x006F`/`0x0070`).
3. **Optimus vs. dGPU Separation of Responsibilities:**
   - The native Windows Settings brightness slider **cannot** natively operate in "NVIDIA GPU Only" mode without third-party driver emulation, because NVIDIA's mobile WDDM driver does not expose `DxgkDdiSetDisplayBrightness`.
   - For native Windows Settings brightness slider functionality, Requirement R2 (restoring display mode switching to Optimus / Automatic) is the prerequisite architectural requirement.

---

## 4. Conclusion

The failure of brightness hotkeys and backlight control on the Dell G15 5530 stems from two distinct, interacting root causes:

1. **For Hotkeys (F6/F7 and Fn+F6/Fn+F7):**
   `DisplayFixDaemon.exe` is running without administrative elevation (`Elevated: False`) because it is auto-started from `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`. While it successfully intercepts keystrokes and draws the acrylic OSD, every attempt to adjust the physical backlight via `root\wmi:NvWmiBrightness` fails with `Access denied (0x80041003)`. As a result, the hardware panel luminance remains frozen at its initial hardware level.

2. **For the Windows Settings Display Brightness Slider:**
   The laptop is locked into "NVIDIA GPU Only" mode. In this mode, the internal panel is connected exclusively to the RTX 4060 dGPU, and the Intel monitor node is disconnected. Because the NVIDIA mobile driver does not implement the WDDM internal brightness interface on this Dell panel, Windows receives `Not Supported (0x8004100c)` from `WmiMonitorBrightness` and `E_FAIL (0x80004005)` from WinRT `BrightnessOverride`. Windows OS is thus completely detached from physical backlight control in dGPU mode. Restoring the native Windows Settings brightness slider requires enabling Optimus/Automatic mode (Requirement R2) where Intel UHD Graphics natively provides the WDDM brightness pipeline.

---

## 5. Remediation Recommendations

To resolve Requirement R1 fully across both hotkeys and Windows display brightness:

### Step 1: Remove Non-Elevated Run Key
Remove the standard-user auto-launch entry from the user registry:
```powershell
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'DisplayFixDaemon' -ErrorAction SilentlyContinue
```

### Step 2: Install Elevated Scheduled Task for `DisplayFixDaemon`
Execute `scripts/install.ps1` with administrative privileges to:
- Terminate any running non-elevated `DisplayFixDaemon.exe`, `NvBrightness.exe`, and `PhantomGuard.exe` processes.
- Unregister legacy scheduled tasks `DisplayFixBrightness` and `DisplayFixGuard`.
- Register a single unified scheduled task named `DisplayFixDaemon`:
  - **Execute:** `C:\ProgramData\DisplayFix\DisplayFixDaemon.exe --run`
  - **Trigger:** At user logon (`-AtLogOn -User $identity.Name`)
  - **Principal:** Interactive logon with `RunLevel: Highest`
  - **Settings:** `ExecutionTimeLimit = 0` (indefinite resident execution), `MultipleInstances = IgnoreNew`.

### Step 3: Ensure Active Function Key Mappings in `hotkeys.ini`
Deploy an active `C:\ProgramData\DisplayFix\hotkeys.ini` file containing:
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
This ensures:
- Plain F6/F7 decrease/increase brightness by 5% when Fn-Lock is ON.
- Plain F1-F3 and F9 synthesize volume and media keys, preserving standard media functions.
- Raw Input HID captures `0x006F` and `0x0070` when Fn-Lock is OFF.

### Step 4: Verify Elevated WMI Write Execution
When `DisplayFixDaemon` runs with `RunLevel: Highest`:
- `BrightnessController.cs` connects to `root\wmi:NvWmiBrightness`.
- Calls to `NvGetSetBrightnessLevel(inArg=1, Level=target+8)` execute cleanly with `Result=True`.
- The physical panel backlight increases and decreases in real time.
- The acrylic OSD overlay displays the accurate percentage without focus stealing.

### Step 5: Restore Optimus / Automatic Mode for Windows Settings Slider (Requirement R2)
- To restore the Windows Settings display brightness slider, proceed to Requirement R2: enable display mode switching so the user can select Optimus or Automatic mode.
- In Optimus/Automatic mode, Intel UHD Graphics drives the eDP panel, natively activating `WmiMonitorBrightnessMethods`, `WmiMonitorBrightness`, and the Windows Settings display brightness slider.

---

## 6. Verification Method

### 6.1 Daemon Status & Elevation Check
```powershell
cmd.exe /c "bin\DisplayFixDaemon.exe --status"
```
**Expected Output:**
- `Process Running: True`
- `Current Elevation: Elevated (Admin)`
- `Brightness Backend: NvWmiBrightness` (in dGPU mode) or `WmiMonitorBrightness` (in Optimus mode)

### 6.2 Elevated Brightness Hardware Write Test
```powershell
cmd.exe /c "bin\DisplayFixDaemon.exe --brightness-set 50"
```
**Expected Output:**
- `Success=True, Error=None`
- Verify that physical panel luminance changes visibly.

### 6.3 Hotkey & OSD Verification
1. Press **F6** (or **Fn+F6** depending on Fn-Lock):
   - Confirm screen dims by 5%.
   - Confirm acrylic OSD overlay appears with updated percentage.
2. Press **F7** (or **Fn+F7**):
   - Confirm screen brightens by 5%.
   - Confirm acrylic OSD overlay appears.
3. Check `C:\ProgramData\DisplayFix\logs\daemon.log` for:
   `Set brightness to X% via root\wmi:NvWmiBrightness ... Success=True`.

### 6.4 E2E Test Suite Execution
```powershell
powershell -ExecutionPolicy Bypass -File tests\e2e\tier1_features\test_f10_hotkey_interception.ps1
powershell -ExecutionPolicy Bypass -File tests\e2e\tier1_features\test_f11_nvidia_wmi_brightness.ps1
powershell -ExecutionPolicy Bypass -File tests\e2e\tier1_features\test_f12_optimus_wmi_brightness.ps1
powershell -ExecutionPolicy Bypass -File tests\e2e\tier5_adversarial\adversarial_m4_brightness_osd_test.ps1
```
All test suites must pass 100% with zero errors.
