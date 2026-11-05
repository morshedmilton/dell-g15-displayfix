## 2026-11-05T12:18:35Z
You are Explorer M2_2 investigating and designing the native in-process CfgMgr32 / SetupAPI Ghost Eviction Engine for Milestone 2.

Working directory: .agents/teamwork/explorer_m2_2/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f04_ghost_eviction.ps1
4. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\common\SystemProbes.ps1

Objectives:
1. Design `src/Daemon/GhostEvictionEngine.cs` and `src/Daemon/Interop.cs`:
   - Exact P/Invoke declarations for `cfgmgr32.dll` (`CM_Locate_DevNodeW`, `CM_Get_DevNode_Status`, `CM_Disable_DevNode`, `CM_Enable_DevNode`, `CM_Reenumerate_DevNode`, etc.) and `setupapi.dll` (`SetupDiGetClassDevsW`, `SetupDiEnumDeviceInfo`, `SetupDiGetDeviceInstanceIdW`, `SetupDiDestroyDeviceInfoList`).
   - Device targeting and identification:
     - Must inspect monitor device nodes under GUID `{4d36e96e-e325-11ce-bfc1-08002be10318}` (Class `Monitor`).
     - Look for internal panel `AUOAA9F`.
     - Active NVIDIA dGPU node has hardware/instance pattern matching `UID4353` or parent `PCI\VEN_10DE&DEV_28E0`. It MUST NOT be touched.
     - Disconnected Intel ghost node has instance pattern `*AUOAA9F*UID8388688*` or parent `PCI\VEN_8086&DEV_A78B`.
     - Foreign/external monitors (Dell, Samsung, LG, HDMI, DisplayPort) MUST NOT be touched (verified by test F04.5).
   - In-process eviction algorithm:
     - Check if display is currently routed to NVIDIA dGPU.
     - Enumerate monitors; if the Intel `UID8388688` node is present or lingering, locate the devnode via `CM_Locate_DevNodeW`.
     - Recycle the node using `CM_Disable_DevNode` (or restart/reenumerate) so Windows removes the active DWM presentation surface for the phantom monitor.
     - Must execute completely in-process in < 500ms without spawning external processes (like `pnputil.exe` or `powershell.exe`).
     - Handle error codes gracefully (`CR_SUCCESS = 0x00`, `CR_INVALID_DEVNODE = 0x0D`, etc.).
2. Provide full, compilable C# source blueprints for `GhostEvictionEngine.cs` and `Interop.cs` targeting .NET Framework 4.8 x64 (zero external dependencies).

Deliverables:
- Write comprehensive blueprint to `.agents/teamwork/explorer_m2_2/ghost_eviction_design.md`
- Write handoff to `.agents/teamwork/explorer_m2_2/handoff.md`
- Send completion message back via send_message.
