# BRIEFING — 2026-11-05T12:30:00Z

## Mission
Investigate and design the native in-process CfgMgr32 / SetupAPI Ghost Eviction Engine for Milestone 2 (`GhostEvictionEngine.cs` and `Interop.cs`).

## 🔒 My Identity
- Archetype: explorer
- Roles: [investigator, synthesizer]
- Working directory: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\explorer_m2_2\
- Original parent: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Milestone: Milestone 2 (Ghost Eviction Engine)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in production source tree (`src/`) during this investigation phase; produce design documents and complete compilable blueprints in `.agents/teamwork/explorer_m2_2/`
- Target .NET Framework 4.8 x64 (zero external NuGet or third-party dependencies)
- Must execute completely in-process in < 500ms without spawning external processes (e.g. `pnputil.exe` or `powershell.exe`)
- Exact P/Invoke declarations for `cfgmgr32.dll` and `setupapi.dll`
- Must only target internal panel AUOAA9F disconnected ghost node (`UID8388688` / parent `PCI\VEN_8086&DEV_A78B`)
- Active NVIDIA dGPU node (`UID4353` / parent `PCI\VEN_10DE&DEV_28E0`) MUST NOT be touched
- Foreign/external monitors (Dell, Samsung, LG, HDMI, DisplayPort) MUST NOT be touched (verified by test F04.5)
- Handle error codes gracefully (`CR_SUCCESS = 0x00`, `CR_INVALID_DEVNODE = 0x0D`, etc.)

## Current Parent
- Conversation ID: 1fa2c640-1687-4d63-a802-a810e6d0f6c0
- Updated: 2026-11-05T12:30:00Z

## Investigation State
- **Explored paths**:
  - `tests/e2e/tier1_features/test_f04_ghost_eviction.ps1`
  - `tests/e2e/common/SystemProbes.ps1`
  - `src/PhantomGuard.cs`
  - Live Dell G15 5530 PnP monitor topology & CfgMgr32/SetupAPI behavior
- **Key findings**:
  - Direct P/Invoke to `SetupDiGetClassDevsW` with `GUID_DEVCLASS_MONITOR` (`{4d36e96e-e325-11ce-bfc1-08002be10318}`) takes 3.64ms.
  - Direct `CM_Locate_DevNodeW` takes 0.35ms.
  - Total eviction cycle completes in ~8.24ms (far below the 500ms budget).
  - Invariant safety checks successfully protect active NVIDIA node `UID4353` and all foreign monitors (`DEL*`, `SAM*`, HDMI/DP).
  - Both `GhostEvictionEngine.cs` and `Interop.cs` compile cleanly with `csc.exe /warn:4 /warnaserror` (0 warnings, 0 errors).
- **Unexplored areas**: None for M2_2 scope.

## Key Decisions Made
- Implemented `int EvictGhostMonitors()` as specified in `PROJECT.md` interface contract.
- Added structured telemetry method `GhostEvictionResult CheckAndEvict(bool force = false)`.
- Separated low-level P/Invoke declarations into `DisplayFix.Daemon.Interop` and high-level logic into `DisplayFix.Daemon.GhostEvictionEngine`.
- Verified 100% compliance against all F04 and related tests (C01.3, S03.1).

## Artifact Index
- `.agents/teamwork/explorer_m2_2/DISPATCH.md` — Initial dispatch message
- `.agents/teamwork/explorer_m2_2/BRIEFING.md` — Working memory
- `.agents/teamwork/explorer_m2_2/progress.md` — Liveness heartbeat
- `.agents/teamwork/explorer_m2_2/ghost_eviction_design.md` — Comprehensive design blueprint
- `.agents/teamwork/explorer_m2_2/GhostEvictionEngine.cs` — Compilable C# source blueprint
- `.agents/teamwork/explorer_m2_2/Interop.cs` — Compilable C# source blueprint
- `.agents/teamwork/explorer_m2_2/handoff.md` — 5-component handoff report
