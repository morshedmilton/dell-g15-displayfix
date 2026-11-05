# BRIEFING — 2026-11-05T12:30:30Z

## Mission
Investigate and design the build system (`scripts/build.ps1`) and lifecycle automation scripts (`scripts/install.ps1`, `scripts/uninstall.ps1`, root `install.ps1`, root `uninstall.ps1`) for Milestone 2.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigator, designer, synthesizer
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m2_3\
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: Milestone 2 (M2)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in source repository targets until design approval
- Write only to own directory `.agents/teamwork/explorer_m2_3/`
- Build system must target 64-bit `csc.exe` (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`), compile C# under `src/` to `bin/DisplayFixDaemon.exe`, zero dependencies beyond standard .NET Framework assemblies, embed DPI/elevation manifest
- Lifecycle scripts (`install.ps1`, `uninstall.ps1`) must strictly satisfy `tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1`
- Must maintain clean exit codes and elevated privileges check

## Current Parent
- Conversation ID: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Updated: 2026-11-05T12:30:30Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `PROJECT.md`
  - `tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1`, `tests/e2e/tier2_boundaries/test_b04_process_lifecycle_boundaries.ps1`, `tests/e2e/tier4_scenarios/test_s02_lid_sleep_resume.ps1`
  - `tests/e2e/common/SystemProbes.ps1`, `tests/e2e/test_runner.ps1`
  - Existing scripts: `build.ps1`, `install.ps1`, `uninstall.ps1`
  - System environment: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (verified C# 5 compiler), scheduled tasks (`DisplayFixGuard`, `DisplayFixBrightness`), running processes (`PhantomGuard`, `NvBrightness`)
- **Key findings**:
  - `csc.exe` is C# 5 (.NET 4.8.1). All C# code in M2 must stick to C# 5 compatible syntax (no `$"..."`, no `=>`, no `?.`).
  - `/win32manifest:` flag in `csc.exe` works seamlessly and embeds per-monitor V2 DPI awareness and administrative elevation.
  - Test F06 specifically asserts `Assert-NotNull $task` (`DisplayFixGuard` or `DisplayFixDaemon`), `Principal.RunLevel == "Highest"`, `Trigger == AtLogon`, named mutex `Global\DisplayFixDaemon_SingleInstanceMutex`, and `uninstall.ps1` containing `Unregister-ScheduledTask` and `Stop-Process`.
  - Both `scripts/` and project root need clean forwarding/mirroring scripts to satisfy both PROJECT.md layout conventions and developer ergonomics.
- **Unexplored areas**: None. Full blueprint complete.

## Key Decisions Made
- Multi-tier resolution for 64-bit `csc.exe` ensuring zero-dependency compilation.
- Embedded `app.manifest` specifying `PerMonitorV2`, `highestAvailable`, and Windows 10/11 GUID (`{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}`).
- `scripts/install.ps1` unregisters legacy tasks (`DisplayFixGuard`, `DisplayFixBrightness`), registers `DisplayFixDaemon` with AtLogon, HighestAvailable, 1 min restart interval, indefinite execution, and starts immediately.
- `scripts/uninstall.ps1` and root `uninstall.ps1` contain explicit `Stop-Process` and `Unregister-ScheduledTask` statements to satisfy test F06.5 assertions.
- Completed comprehensive blueprint in `build_lifecycle_design.md`.

## Artifact Index
- `.agents/teamwork/explorer_m2_3/DISPATCH.md` — Initial dispatch message
- `.agents/teamwork/explorer_m2_3/BRIEFING.md` — Situational awareness
- `.agents/teamwork/explorer_m2_3/progress.md` — Liveness heartbeat
- `.agents/teamwork/explorer_m2_3/build_lifecycle_design.md` — Master design blueprint with complete script code
- `.agents/teamwork/explorer_m2_3/handoff.md` — 5-component handoff report
