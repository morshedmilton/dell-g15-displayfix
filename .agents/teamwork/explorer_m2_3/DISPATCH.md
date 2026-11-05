## 2026-11-05T12:18:52Z
You are Explorer M2_3 investigating and designing the build system and lifecycle automation scripts for Milestone 2.

Working directory: .agents/teamwork/explorer_m2_3/
Workspace root: c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix

Mandatory files to read before beginning:
1. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\.agents\teamwork\ORIGINAL_REQUEST.md
2. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\PROJECT.md
3. c:\Users\morsh\AppData\Roaming\AutoClaw-oversea-official\accounts\98e17ebcdf311a8f97d63ba37e0764ae6703014cbe59f58a71e626853184e80c\projects\Default\dell-g15-displayfix\tests\e2e\tier1_features\test_f06_daemon_lifecycle.ps1
4. Existing scripts in `scripts/` or repository root.

Objectives:
1. Design `scripts/build.ps1`:
   - Locate 64-bit `csc.exe` in `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (or via .NET Framework registry path).
   - Gather all C# files under `src/` (recursively or explicitly).
   - Compile target: Windows executable (`/target:winexe`), x64 platform (`/platform:x64`), release optimization (`/optimize+`), high warning level (`/warn:4`), references to `System.dll`, `System.Core.dll`, `System.Drawing.dll`, `System.Windows.Forms.dll`, `System.Management.dll`.
   - Output binary path: `bin/DisplayFixDaemon.exe`.
   - Embed application manifest for per-monitor DPI awareness and elevation compatibility if appropriate.
   - Return clean exit code (0 on success, non-zero on failure).
2. Design `scripts/install.ps1` and project root `install.ps1`:
   - Verify administrative elevation. If not elevated, provide clean error or re-launch helper.
   - Stop any existing `DisplayFixDaemon.exe` process.
   - Register Windows Scheduled Task:
     - Task Name: `DisplayFixDaemon` (and alias/check `DisplayFixGuard`).
     - Principal: Current user, `RunLevel: HighestAvailable` (verified by test F06.2).
     - Trigger: `AtLogon` for the current interactive user (verified by test F06.3).
     - Action: Execute `bin/DisplayFixDaemon.exe --run` with WorkingDirectory set.
     - Settings: ExecutionTimeLimit 0 (indefinite), DisallowStartIfOnBatteries false, StopIfGoingOnBatteries false, RestartInterval 1 min, RestartCount 3.
   - Start the task / launch daemon in background.
   - Create and maintain root `install.ps1` forwarding or mirroring this logic.
3. Design `scripts/uninstall.ps1` and project root `uninstall.ps1`:
   - Must satisfy test F06.5 assertions:
     - Contains `Unregister-ScheduledTask` to cleanly remove scheduled tasks.
     - Contains `Stop-Process` to terminate active background processes (`DisplayFixDaemon`).
     - Remove created mutexes, runtime temp files, and clean up.
4. Verify conformance with test `tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1`.

Deliverables:
- Write comprehensive blueprint to `.agents/teamwork/explorer_m2_3/build_lifecycle_design.md`
- Write handoff to `.agents/teamwork/explorer_m2_3/handoff.md`
- Send completion message back via send_message.
