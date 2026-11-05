## 2026-11-05T13:03:27Z
You are Explorer M3_3 investigating and designing the Display Event Integration and Daemon Orchestration for Milestone 3.

Working directory: .agents/teamwork/explorer_m3_3/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. Reviewer findings from M2: .agents/teamwork/reviewer_m2_1/handoff.md and .agents/teamwork/reviewer_m2_2/handoff.md
4. Existing source code: `src/Daemon/EventWindow.cs`, `src/Daemon/Program.cs`, `src/Daemon/GhostEvictionEngine.cs`.

Objectives:
1. Design the unified event handling pipeline in `EventWindow.cs`:
   - When the debounced 200ms timer expires after `WM_DISPLAYCHANGE` (or device/power notification):
     Step 1: In-process ghost monitor eviction (`GhostEvictionEngine.CheckAndEvict()`).
     Step 2: 360Hz refresh rate lock enforcement (`RefreshRateLock.Enforce360Hz()`).
     Step 3: 125% DPI scaling synchronization (`ScalingSynchronizer.Enforce125()`).
   - Total pipeline latency budget: < 100ms total.
2. Review and incorporate edge case mitigations identified by M2 Reviewers:
   - In `GhostEvictionEngine.cs` line 224: ensure `m.IsInternalPanel` check is evaluated to prevent false eviction when external displays are connected to the dGPU in Optimus mode.
   - Secondary devnode fallback and clean error handling.
3. Design CLI commands in `Program.cs`:
   - `--lock-360hz`: Trigger one-shot refresh rate query and 360Hz enforcement.
   - `--sync-dpi`: Trigger one-shot registry synchronization and CCD 125% DPI scale enforcement.
   - Update `--status` output to report current Refresh Rate (Hz) and Scaling (%).
4. Ensure strict C# 5 syntax compatibility (no string interpolation) for native `csc.exe` on .NET 4.8 x64.

Deliverables:
- Write design blueprint to `.agents/teamwork/explorer_m3_3/event_integration_design.md`
- Write handoff to `.agents/teamwork/explorer_m3_3/handoff.md`
- Send completion message back via send_message.
