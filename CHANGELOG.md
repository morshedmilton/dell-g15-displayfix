# Changelog

All notable changes to this project. Format loosely follows Keep a Changelog;
versions follow SemVer. **Every patch gets its own git tag and GitHub Release with
the rebuilt executables attached.**

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
