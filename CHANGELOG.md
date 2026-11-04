# Changelog

All notable changes to this project. Format loosely follows Keep a Changelog;
versions follow SemVer. **Every patch gets its own git tag and GitHub Release with
the rebuilt executables attached.**

---

## [1.1.0] — 2026-11-05

### Added

- **`hotkeys.ini` — the function row becomes configurable.**
  Turning on Fn-lock to get plain-F6 brightness works, but Fn-lock is all-or-nothing:
  it also moves the media functions on every other key behind Fn. There is no per-key
  setting in the BIOS or the EC, so the app now does it.

  Each key listed in `C:\ProgramData\DisplayFix\hotkeys.ini` is claimed as a global
  hotkey and given an action. Defaults match the legends on this keyboard:

  ```
  F1=volume_mute
  F2=volume_down
  F3=volume_up
  F6=brightness_down
  F7=brightness_up
  F9=media_play
  ```

  Actions: `brightness_up`, `brightness_down`, `volume_up`, `volume_down`,
  `volume_mute`, `media_play`, `media_next`, `media_prev`, `media_stop`.
  Keys: `F1`–`F12`. Edit the file and restart the task to change it.

- `app.log` records which keys were bound at startup, so a silent failure is visible.

### Changed

- Brightness keys are no longer registered conditionally on the GPU backend. With
  Fn-lock in function mode the key is a plain keystroke in both modes, so the binding is
  unconditional and the backend is chosen per keystroke.

### Why not intercept the media code instead

Measured with a raw-input probe, and this is the important part: with Fn-lock in media
mode, pressing F6 produces **no Windows input event at all** — not a keystroke, not an
HID consumer usage, nothing. It is handled inside the embedded controller and never
reaches the OS. Only Fn+F6, which is a real F6 keystroke, is visible.

So catching the media code is impossible from user mode. Remapping in the other
Fn-lock direction is the only workable route.

---

## [1.0.3] — 2026-11-05

### Fixed

- **F6 / F7 only worked with Fn held.** The keyboard's dedicated brightness keys do not
  produce a keystroke at all — they emit an **HID Consumer Page usage**
  (`0x0C:0x006F` increment, `0x0C:0x0070` decrement). `RegisterHotKey` can only see
  keystrokes, so it never fired. Pressing Fn+F6 produced a literal `F6` keystroke, which
  is why that combination did work.

  The tray app now registers for **raw input** on the consumer-control device
  (`RegisterRawInputDevices` with `RIDEV_INPUTSINK`) and parses `WM_INPUT` reports for
  those two usages. Both paths are active, so the keys work whether the F-row is in
  media mode or function mode.

### Note

Raw input is enabled only while the NVIDIA backend is active, for the same reason the
plain F6/F7 hotkeys were: in Optimus the Intel path owns those keys.

---

## [1.0.2] — 2026-11-05

### Added

- **F6 / F7 now control brightness**, matching the legends printed on this keyboard
  (F6 down, F7 up). They are registered as global hotkeys **only while the NVIDIA
  backend is the active one** — in Optimus the Intel path already handles them, so
  taking them over there would double-fire.
- `Ctrl+Alt+↑ / ↓` still work as before, in both modes.

### Note

Because these are global hotkeys, F6 and F7 no longer reach the foreground application
while the panel is on the dGPU. That is the intended trade on a machine whose brightness
keys are otherwise dead in that state; the registration is dropped again the moment the
panel returns to the Intel GPU.

### Verified

Reinstalled locally on the test machine and confirmed both keys are claimed by the tray
app (`RegisterHotKey` on F6 and F7 from a second process fails).

---

## [1.0.1] — 2026-11-05

Field fixes found during the first real game session audit. Both are bugs in 1.0.0,
not cosmetic changes.

### Fixed

- **Brightness control silently stopped working after the first mux.**
  `root\wmi:NvWmiBrightness` starts refusing access to a non-elevated caller once the
  panel has been muxed and the duplicate cleared. The tray app ran from an `HKCU\...\Run`
  entry, so it could no longer read or write — it failed quietly and kept showing a stale
  value.
  *Changed:* the tray app now runs from scheduled task **`DisplayFixBrightness`**
  (at logon, `RunLevel Highest`). The old Run entry is removed on install.
  Verified: `set(50)=True elevated=True`.

- **The brightness floor was weaker than it looked.**
  The NVIDIA backend reports back **8 units lower** than the value written
  (write 100 → reads 92, write 50 → reads 42, measured across nine points).
  A floor of 10 therefore left the panel at an actual **2** — still close to a black
  screen.
  *Changed:* the NVIDIA write path adds the measured +8 offset before clamping, so the
  floor of 10 now lands at a real 10.

### Added

- `--set <n>` command line switch, so brightness can be driven and verified without
  clicking the tray icon.
- `--selftest` now also reports the detected backend and current level.

### Known limitation

- The NVIDIA backend's read-back is noisy and lags a step behind a write. The tray icon
  shows the last value *you* set rather than re-reading the device, which avoids the
  flicker; treat the tooltip as a request log, not a measurement.

---

## [1.0.0] — 2026-11-05

First public release. Two tools, both built from what was measured on the machine
(Service Tag CYFY434, BIOS 1.36.0, RTX 4060 Laptop + Intel UHD, AUO AA9F 360 Hz panel).

### Added

- **PhantomGuard** — background watcher that detects the stale duplicate display path
  left behind by Advanced Optimus / DDS and clears it by toggling the Intel display
  adapter. Runs as scheduled task `DisplayFixGuard` at logon with highest privileges.
- **NvBrightness** — tray brightness control with two backends. Uses the Intel
  `WmiMonitorBrightnessMethods` path when available, and falls back to NVIDIA's
  `NvWmiBrightness` when the panel is muxed to the dGPU. Global hotkeys
  `Ctrl+Alt+↑` / `Ctrl+Alt+↓`.
- `build.ps1` — compiles both tools with the `csc.exe` that ships with Windows
  (.NET Framework 4.8). No SDK, no NuGet, no runtime install.
- `install.ps1` / `uninstall.ps1` — deploy and complete removal.
- `docs/problem.md` — the full defect analysis with measured numbers and registry evidence.

### Safety

- **Brightness hard floor of 10 %.** Level 0 on this panel is indistinguishable from
  display-off — the screen goes black. The floor is applied on read, on write, and to
  the slider range, and the tool lifts a panel that it finds below the floor on startup.
- PhantomGuard requires **two consecutive confirmations** before acting, enforces a
  **120 s cooldown** and a ceiling of **3 repairs per hour**, never touches the NVIDIA
  adapter, and stands down entirely if any non-internal monitor is present.
- PhantomGuard uses **two independent detection signals** (active display path count and
  the set of present PnP monitors). Either one alone is enough to confirm the duplicate,
  because the two do not always agree at the same instant.

### Known limitations

- Does not repair Dell's underlying defect; the duplicate path is worked around, not fixed.
- Fn brightness keys do not work while the panel is on the dGPU — Dell's ACPI hotkey
  path terminates at the Intel provider.
- Windows' own brightness slider is absent in that state and returns by itself in Optimus.
- The repair toggles the Intel adapter, so the screen may blink for roughly half a second
  and a fullscreen application may lose focus once. The trigger fires ~16 s after the
  panel muxes, which in practice is during game loading.

---

## Release procedure (for future patches)

```powershell
# 1. bump the version in README badges and CHANGELOG, rebuild
.\build.ps1

# 2. commit
git add -A
git commit -m "bump to 1.0.1 and rebuild"

# 3. tag and publish
git tag -a v1.0.1 -m "1.0.1"
git push origin main --tags
gh release create v1.0.1 bin\PhantomGuard.exe bin\NvBrightness.exe --title "1.0.1" --notes-file notes.md
```
