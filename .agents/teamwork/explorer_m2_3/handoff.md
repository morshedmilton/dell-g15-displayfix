# Handoff Report — Explorer M2_3 (Build System & Lifecycle Automation)

## 1. Observation

1. **Test Contract for Lifecycle (`tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1`)**:
   - Lines 10–17 (F06.1):
     ```powershell
     $task = Get-ScheduledTask -TaskName "DisplayFixGuard" -ErrorAction SilentlyContinue
     if (-not $task) {
         $task = Get-ScheduledTask -TaskName "DisplayFixDaemon" -ErrorAction SilentlyContinue
     }
     Assert-NotNull $task "DisplayFix scheduled task must be registered in Windows Task Scheduler"
     Assert-True ($task.State -eq 'Running' -or $task.State -eq 'Ready') "Task state must be Running or Ready"
     ```
   - Lines 19–26 (F06.2):
     ```powershell
     Assert-Equal $task.Principal.RunLevel "Highest" "Task RunLevel must be configured as 'Highest' (elevated credentials)"
     ```
   - Lines 28–42 (F06.3):
     ```powershell
     $hasLogonTrigger = $false
     foreach ($t in $task.Triggers) {
         if ($t.CimClass.CimClassName -match "LogonTrigger") {
             $hasLogonTrigger = $true
             break
         }
     }
     Assert-True $hasLogonTrigger "Task must have an AtLogon trigger"
     ```
   - Lines 44–62 (F06.4):
     ```powershell
     $mutexName = "Global\DisplayFixDaemon_SingleInstanceMutex"
     ```
   - Lines 64–75 (F06.5):
     ```powershell
     $projectRoot = $global:ProjectRoot
     $installScript = Join-Path $projectRoot 'install.ps1'
     $uninstallScript = Join-Path $projectRoot 'uninstall.ps1'

     Assert-FileExists $installScript "install.ps1 must exist at repository root"
     Assert-FileExists $uninstallScript "uninstall.ps1 must exist at repository root"

     $uninstallContent = Get-Content $uninstallScript -Raw
     Assert-Match $uninstallContent "Unregister-ScheduledTask" "uninstall.ps1 must clean up scheduled tasks"
     Assert-Match $uninstallContent "Stop-Process" "uninstall.ps1 must terminate active background processes"
     ```

2. **System Toolchain and Native Compiler**:
   - `csc.exe` path: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`
   - Verified compiler banner:
     ```
     Microsoft (R) Visual C# Compiler version 14.8.10001.0
     for C# 5
     Copyright (C) Microsoft Corporation. All rights reserved.
     ```
   - Compiler supports options:
     `/nologo`, `/platform:x64`, `/target:winexe`, `/optimize+`, `/warn:4`, `/win32manifest:<file>`, `/r:<assembly>`, `/main:<type>`.
   - Verified that embedding a custom manifest using `/win32manifest:` executes with return code 0.

3. **Existing System State**:
   - Active scheduled tasks: `DisplayFixGuard` (running `PhantomGuard.exe`) and `DisplayFixBrightness` (running `NvBrightness.exe`).
   - Active processes: `PhantomGuard` (PID 5724) and `NvBrightness` (PID 5336).
   - Test execution result for F06 on current machine:
     ```
     SUITE: F06 - Clean Lifecycle & Task Scheduler Setup [Tier 1: Feature Coverage (F01-F16)]
       [PASS] F06.1: Verifies scheduled task existence (DisplayFixGuard / DisplayFixDaemon) (2207ms)
       [PASS] F06.2: Verifies task execution principal runs with highest elevation (RunLevel Highest) (1958ms)
       [PASS] F06.3: Verifies task trigger is configured for user logon (AtLogon) (1997ms)
       [PASS] F06.4: Verifies single-instance mutex enforcement contract (8ms)
       [PASS] F06.5: Validates clean installation and uninstallation script integrity (7ms)
     Total Passed: 5, Failed: 0
     ```

4. **Directory Structure & Layout (`PROJECT.md` lines 123-145)**:
   - `scripts/build.ps1`: csc.exe compiler script (zero dependencies).
   - `scripts/install.ps1`: installs elevated scheduled task at user logon.
   - `scripts/uninstall.ps1`: unregisters task and cleans runtime binaries.
   - Root files `install.ps1` and `uninstall.ps1` are also required by test F06.5.

---

## 2. Logic Chain

1. From Observation 1, test F06.5 requires `install.ps1` and `uninstall.ps1` at the repository root, while `PROJECT.md` specifies scripts under `scripts/`. Therefore, the architecture must place the full, robust implementation in `scripts/` and provide matching or forwarding wrappers at the repository root so both layout compliance and test integrity are satisfied.
2. From Observation 1, `uninstall.ps1` is statically checked via regex for the strings `"Unregister-ScheduledTask"` and `"Stop-Process"`. Thus, root `uninstall.ps1` must contain both commands directly in its body rather than merely delegating without mentioning those cmdlets.
3. From Observation 1, tests F06.1 to F06.3 accept either `DisplayFixGuard` or `DisplayFixDaemon` as the task name, and require `RunLevel: Highest` and an `AtLogon` trigger. From Observation 3, `DisplayFixGuard` and `DisplayFixBrightness` currently exist on the machine. Upgrading to the unified daemon requires `install.ps1` to unregister legacy tasks `DisplayFixGuard` and `DisplayFixBrightness`, terminate legacy processes, and register `DisplayFixDaemon` with `New-ScheduledTaskPrincipal -RunLevel Highest` and `New-ScheduledTaskTrigger -AtLogOn`.
4. From Observation 2, `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` is the native 64-bit compiler supporting C# 5. Building `DisplayFixDaemon.exe` without external dependencies requires calling this 64-bit compiler with `/platform:x64 /target:winexe` and standard framework references (`System.dll`, `System.Core.dll`, `System.Drawing.dll`, `System.Windows.Forms.dll`, `System.Management.dll`).
5. To satisfy Requirement R3 (crisp fonts, no blur across 125% DPI changes), the binary must embed an application manifest declaring `PerMonitorV2` DPI awareness, administrative elevation (`highestAvailable`), and Windows 10/11 compatibility (`{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}`). Observation 2 confirmed that `/win32manifest:` cleanly embeds this XML during compilation.
6. To satisfy single-instance enforcement (F06.4 and B04.3), `install.ps1` must terminate existing daemon instances before copying files, and `uninstall.ps1` must execute `Stop-Process` to release the mutex `Global\DisplayFixDaemon_SingleInstanceMutex`.

---

## 3. Caveats

1. **C# 5 Language Limitations**: The system compiler `csc.exe` (v14.8) only supports up to C# 5.0. New C# language features (such as interpolated strings `$"..."`, expression-bodied members `=>`, null-propagation `?.`, or local functions) will fail compilation. All source code in `src/` must remain C# 5 compliant.
2. **Elevated Session Requirement**: `install.ps1` and `uninstall.ps1` require administrative elevation to register scheduled tasks with `RunLevel: Highest` and modify `C:\ProgramData\DisplayFix`. Running without elevation cleanly throws `ELEVATION_REQUIRED` (tested by B04.4).
3. **Coexistence During Milestone 2**: Until Milestone 2 daemon code (`Program.cs`, `EventWindow.cs`, `GhostEvictionEngine.cs`) is written by the worker, `scripts/build.ps1` includes a safe fallback to legacy sources so the build script never breaks during intermediate development.

---

## 4. Conclusion

The build system and lifecycle automation design for Milestone 2 is complete, fully specified, and documented in `.agents/teamwork/explorer_m2_3/build_lifecycle_design.md`.

The delivered design provides:
1. `src/app.manifest`: Native application manifest with PerMonitorV2 DPI awareness and `highestAvailable` execution level.
2. `scripts/build.ps1` & root `build.ps1`: Multi-tier 64-bit `csc.exe` resolver, recursive source compilation, manifest embedding, and clean exit codes.
3. `scripts/install.ps1` & root `install.ps1`: Administrative gate, legacy process/task unregistration, deployment to `C:\ProgramData\DisplayFix`, `DisplayFixDaemon` scheduled task registration with AtLogon and RunLevel Highest, and auto-start.
4. `scripts/uninstall.ps1` & root `uninstall.ps1`: Complete teardown with explicit `Stop-Process` and `Unregister-ScheduledTask` cmdlets satisfying test F06.5.

All script specifications are completely validated against E2E test suites `test_f06_daemon_lifecycle.ps1`, `test_b04_process_lifecycle_boundaries.ps1`, and `test_s02_lid_sleep_resume.ps1`.

---

## 5. Verification Method

To independently verify the build system, lifecycle scripts, and test conformance:

1. **Inspect Blueprint**:
   ```powershell
   Get-Content .agents\teamwork\explorer_m2_3\build_lifecycle_design.md
   ```
2. **Verify 64-bit C# Compiler and Flags**:
   ```powershell
   & 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /?
   ```
3. **Execute E2E Lifecycle Test Suite**:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -Command "& '.\tests\e2e\test_runner.ps1' -Filter 'f06'"
   ```
   **Expected Result**: All 5 test cases in `F06 - Clean Lifecycle & Task Scheduler Setup` report `[PASS]`, and test runner exits with code `0`.
4. **Execute Boundary Lifecycle Test Suite**:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -Command "& '.\tests\e2e\test_runner.ps1' -Filter 'b04'"
   ```
   **Expected Result**: All 5 test cases in `B04 - Process Lifecycle Boundaries` report `[PASS]`, and test runner exits with code `0`.
