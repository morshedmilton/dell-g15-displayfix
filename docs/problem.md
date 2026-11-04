# The defect

Everything here was measured on one machine. Numbers are from `dwm.exe` CPU time sampled
with `(Get-Process dwm).CPU` over fixed intervals, plus display-config and PnP queries.

**Machine:** Dell G15 5530 · Service Tag CYFY434 · System SKU 0BF7 · BIOS 1.36.0
**CPU / GPU:** i7-13650HX · RTX 4060 Laptop · Intel UHD · panel AUO AA9F 1920×1080 360 Hz

---

## 1. Symptom

Using **Advanced Optimus** (Dynamic Display Switching) as designed — letting the panel
mux to the dGPU — makes the machine feel broken:

- mouse and keyboard input stall for roughly one second at a time
- `dwm.exe` sits at 30–50 % of a core, even at idle on the desktop
- games stutter regardless of graphical settings

Switching back to **Optimus** makes all of it disappear immediately.

---

## 2. Measurement

Same machine, same session, seconds apart:

| Date | Scenario | `display_active` | Monitor devices | Brightness interfaces | `dwm` CPU |
|---|---|---|---|---|---|
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **34.9 %** |
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **38.5 %** |
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **42.7 %** |
| 3 Nov | after disabling/re-enabling Intel adapter | Enabled | 1 | **0** | 1.0 % |
| 3 Nov | after disabling/re-enabling Intel adapter | Enabled | 1 | **0** | 1.8 % |
| 4 Nov | Optimus | Disabled | 1 | 1 | 1.0–1.8 % |
| 4 Nov | Automatic, in game (54 samples) | Enabled | **2** | 1 | mean **19.2 %**, peak 37.0 % |
| 4 Nov | Automatic, fullscreen (54 samples) | Enabled | **2** | 1 | mean **33.5 %**, peak 54.0 % |
| 5 Nov | **after clean Dell driver A17 + NVPCF 615.34** | Enabled | **2** | 1 | **36.8 %** |
| 5 Nov | same | Enabled | **2** | 1 | **31.2 %** |
| 5 Nov | same | Enabled | **2** | 1 | **32.3 %** |
| 5 Nov | after clearing the duplicate | Enabled | 1 | 0 | **1.4 %** |

The 5 November rows matter: they were taken **after** a clean install of Dell's own
validated graphics package (A17, 32.0.16.1687) with the matching NVPCF 32.0.16.1534,
generic NVIDIA driver removed. The defect is identical. **It is not a driver-version
regression.**

---

## 3. Where the duplicate comes from

`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity` binds the one
physical panel to both GPU paths:

```
AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
  ^ AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050
  ^ 4F0EF7AAD61E67469C7D933F1D3082E8
```

- `10DE_28E0` = NVIDIA RTX 4060 Laptop
- `8086_A78B` = Intel UHD Graphics

When DDS muxes the panel to `10DE`, the Intel-side monitor instance
(`DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688`) is **not torn down**. It stays an active
display as far as Windows and DWM are concerned, so DWM composites a second, invisible
surface for it.

---

## 4. Why it cannot simply be cleared

That same Intel-side device is the only object exposing `WmiMonitorBrightness` and
`WmiMonitorBrightnessMethods`. Disabling it — the only known way to clear the duplicate —
drops the brightness interface count from 1 to 0.

Consequence: the brightness slider vanishes and the Fn brightness keys stop working
entirely, because Dell's ACPI hotkey path terminates at the Intel provider.

So the user must choose between two broken states. That is the defect.

---

## 5. What was ruled out

| Hypothesis | Test | Result |
|---|---|---|
| Faulty NVIDIA driver | Dell package A17, 32.0.16.1687, generic 621.01 removed | reproduces |
| Mismatched NVPCF | downgraded to Dell-paired 32.0.16.1534 | reproduces |
| Old BIOS | 1.36.0, newest in Dell's catalogue for 0BF7 | reproduces |
| Old Intel driver | Dell A00, 32.0.101.7088 | reproduces |
| Thermals / power limit | GPU 47–72 °C, no throttle events | not the cause |
| Rendering load | `dwm` stays at 31–54 % **idle on the desktop** | not the cause |
| Corrupt display state | clean reinstall of the whole graphics stack + reboot | reproduces |
| Just a stale registry entry | instant, repeatable clearing by adapter toggle | confirms stale enumeration, not load |

---

## 6. What a real fix would look like

A BIOS/EC + NVPCF + driver change such that, after a mux completes:

1. `Get-PnpDevice -Class Monitor` reports exactly **one** `OK` device for the internal panel, and
2. `WmiMonitorBrightness` remains available while the panel is on the dGPU.

Until then, the two tools in this repo make the machine usable without waiting for Dell.

---

## 7. Panel VRR note

The EDID extension block is **DisplayID 1.3**, containing only Padding and Display
Parameters — no Dynamic Video Timing Range Limits block. That is *not* evidence that the
panel lacks variable refresh: on eDP panels G-SYNC is applied through NVIDIA's own panel
tables rather than advertised in EDID.

Confirmed separately on this unit: NVIDIA Control Panel exposes a **Set up G-SYNC** page
for the internal panel, and Manage 3D Settings offers **Monitor Technology: G-SYNC**.
Both only appear when the driver detects a capable panel. G-SYNC is real here, and it is
unavailable while the panel is driven by the Intel iGPU under Optimus.
