# Technical notes — Dell G15 5530, service tag CYFY434

Facts and measurements only. No proposed fix.

Everything here was collected on one machine. `dwm.exe` CPU is sampled from
`(Get-Process dwm).CPU` over fixed 10-second windows.

---

## 1. What happens

Setting Display Mode to **NVIDIA GPU only**, or letting Advanced Optimus move the panel to
the RTX 4060, leaves Windows with **two monitor devices for the one internal panel**.
While that state persists `dwm.exe` holds 31–54 % of a single CPU core and input stalls for
roughly a second at a time.

Returning to Optimus, or disabling and re-enabling the Intel display adapter, removes the
second device and `dwm` falls to 0–2 %.

---

## 2. Measurements

| Date | Scenario | `display_active` | Monitor devices | Brightness interfaces | `dwm` CPU |
|---|---|---|---|---|---|
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **34.9 %** |
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **38.5 %** |
| 3 Nov | NVIDIA-only, duplicate present | Enabled | **2** | 1 | **42.7 %** |
| 3 Nov | after disabling/re-enabling Intel adapter | Enabled | 1 | **0** | 1.0 % |
| 3 Nov | after disabling/re-enabling Intel adapter | Enabled | 1 | **0** | 1.8 % |
| 4 Nov | Optimus | Disabled | 1 | 1 | 1.0–1.8 % |
| 4 Nov | Automatic, in game (54 samples) | Enabled | **2** | 1 | mean 19.2 %, peak 37.0 % |
| 4 Nov | Automatic, fullscreen (54 samples) | Enabled | **2** | 1 | mean 33.5 %, peak 54.0 % |
| 5 Nov | **Dell driver A17 + NVPCF 615.34, panel on NVIDIA** | Enabled | **2** | 1 | **36.8 %** |
| 5 Nov | same session | Enabled | **2** | 1 | **31.2 %** |
| 5 Nov | same session | Enabled | **2** | 1 | **32.3 %** |
| 5 Nov | duplicate cleared, same session | Enabled | 1 | 0 | **1.4 %** |
| 5 Nov | back to Optimus | Disabled | 1 | 1 | 0.0 % |

The 5 November rows were taken after a clean install of **Dell's own** graphics package
A17 (32.0.16.1687) together with the matching **NVPCF 32.0.16.1534**, with NVIDIA's newer
generic driver removed first.

---

## 3. The two devices

With the panel on the NVIDIA GPU, monitor enumeration returns two devices that are both
`OK`, for one physical panel:

```
Integrated Monitor   DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688
Generic Monitor      DISPLAY\AUOAA9F\5&39808DAE&2&UID4353
```

`nvidia-smi --query-gpu=display_active` reports `Enabled` at the same time, so the panel
itself is on the NVIDIA GPU. The first of the two entries is the leftover.

---

## 4. Registry evidence

`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity` contains a record
binding the internal panel to **both** GPU paths:

```
AUOAA9F0_01_07E6_5E_10DE_28E0_00000001_00000000_1101
  ^ AUOAA9F0_01_07E6_5E_8086_A78B_00000000_00020000_800050
  ^ 4F0EF7AAD61E67469C7D933F1D3082E8
```

- `10DE_28E0` — NVIDIA RTX 4060 Laptop
- `8086_A78B` — Intel UHD Graphics

Full export: `evidence/registry-connectivity.reg`.

---

## 5. Why it is hard to live with

The leftover device is also the only object exposing `WmiMonitorBrightness` and
`WmiMonitorBrightnessMethods`. Disabling it — the only thing that stops the stutter —
takes the brightness interface count from **1 to 0**. The Windows brightness slider
disappears and the Fn brightness keys stop responding.

So on this machine the two states are mutually exclusive: normal input, or working
brightness.

---

## 6. What has been ruled out on this unit

| Check | What was done | Result |
|---|---|---|
| Driver version | Dell package A17, 32.0.16.1687, generic 621.01 removed | reproduces |
| NVPCF version | matched to Dell 32.0.16.1534 | reproduces |
| BIOS | already 1.36.0, newest listed for SKU 0BF7 | reproduces |
| Intel graphics driver | Dell package A00, 32.0.101.7088 | reproduces |
| Heat / power limit | GPU 47–72 °C, no throttle events observed | not the cause |
| Rendering load | `dwm` stays at 31–54 % **idle on the desktop**, nothing running | not the cause |
| Corrupt display state | clean reinstall of the whole graphics stack, then reboot | reproduces |

---

## 7. What I would like to know

1. Is this a known issue on the G15 5530 (or the G16 7630, which shares this BIOS)?
2. Is any BIOS, EC, NVPCF or driver revision expected to change the behaviour where two
   monitor devices are present for one panel after the switch?
3. If it is useful, I can run any diagnostic you want on the machine and send the output.

I am not asking for a workaround. I already have one.

---

## 8. Attachment list

| File | Contents |
|---|---|
| `system-info.txt` | model, service tag, BIOS, driver versions, monitor enumeration |
| `measurements.csv` | every measurement above, machine readable |
| `phanomguard-log.txt` | timestamped log of the duplicate appearing and being cleared |
| `registry-connectivity.reg` | the dual-GPU connectivity records |
| `registry-display-enum.reg` | display device enumeration as exported from the registry |
