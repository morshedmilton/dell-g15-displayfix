# Forensic Integrity Audit Report: Milestone MR2

**Auditor:** Forensic Auditor 1 (`auditor_mr2_1`)  
**Target:** Milestone MR2 — Restore Display Mode Switching (Optimus / Automatic)  
**Date:** 2026-11-05T17:12:00Z  
**Integrity Mode:** Development Mode (as specified in `ORIGINAL_REQUEST.md`)  
**Project:** Dell G15 5530 DisplayFix  
**Working Directory:** `.agents/teamwork/auditor_mr2_1`  

---

## Audit Verdict: CLEAN

No integrity violations, facades, mocked returns, hardcoded test strings, or execution bypasses were detected. All work products for Milestone MR2 implement authentic, genuine, and verified functionality interacting directly with the Windows 11 kernel, WMI/CIM, PnP subsystem, ACPI registry tables, and running background daemon.

---

## 1. Observation

### 1.1 Static Analysis Results
1. **Inspection of `scripts/diagnostics/test_display_modes.ps1`**:
   - The script was reviewed in full (480 lines).
   - Lines 80-81: Directly queries `Get-CimInstance Win32_ComputerSystem` and `Win32_BIOS`.
   - Lines 104-105: Directly queries `Get-PnpDevice -Class Display` and `Get-CimInstance Win32_VideoController`.
   - Lines 108-111 & 138-141: Probes hardware device nodes for Intel UHD Graphics (`PCI\VEN_8086`) and NVIDIA GeForce RTX 4060 (`PCI\VEN_10DE`), evaluating PnP status (`OK`) and error codes (`CM_PROB_NONE`).
   - Lines 174-180: Directly probes active monitor devnodes using `Get-PnpDevice -Class Monitor`, verifying whether internal panel devnode `DISPLAY\AUOAA9F\5&39808DAE&2&UID4353` (dGPU) or `DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688` (iGPU) is `Present`.
   - Lines 226-258: Directly reads secondary ACPI tables from `HKLM:\HARDWARE\ACPI\SSDA\DELL\NvdTable\00001000`, extracts the raw binary payload, parses table header signature (`SSDT`), OEM ID (`DELL`), Table ID (`NvdTable`), and checks for genuine DSM methods (`MHYB`, `NVOP`, `NVJT`, `OPTF`, `NVBR`, `NVPW`, `OPTIMUS`).
   - Lines 285-325: Inspects `DisplayFixDaemon` running status via `Get-Process DisplayFixDaemon`, `Get-ScheduledTask -TaskName 'DisplayFixDaemon'`, and CLI invocation `--status`.
   - Lines 369-374: Directly inspects NVIDIA services `NVDisplay.ContainerLocalSystem` and `NvContainerLocalSystem` via `Get-Service`.
   - Lines 381-395: Dynamically inspects Alienware Command Center performance log (`C:\ProgramData\Dell\AWPerformance.SCSubAgent\AWPerformance.SCSubAgent.00.log`) for G-Mode state.
   - **Absence of Fakes/Mocks**: The script contains zero hardcoded PASS strings, zero mocked data tables, and zero bypassed assertions. The verdict is dynamically derived from live boolean evaluations (`$overallPassed = $intelOperational -and $nvidiaOperational -and $allTokensValid -and $standDownContractVerified`).

2. **Inspection of `src/Daemon/GhostEvictionEngine.cs` (Optimus Stand-down Invariant)**:
   - Lines 241-250:
     ```csharp
     // Invariant 1: If internal panel is NOT currently routed to NVIDIA dGPU, stand down immediately.
     // In Optimus mode, the Intel node is the primary display and must not be touched!
     if (!nvidiaActive && !force)
     {
         sw.Stop();
         result.ElapsedMilliseconds = sw.Elapsed.TotalMilliseconds;
         result.Message = "Stand down: Internal panel AUOAA9F not routed to NVIDIA dGPU (Optimus/iGPU mode active).";
         Logger.Info("EvictionEngine", result.Message);
         return result;
     }
     ```
   - Confirmed: The daemon strictly protects the Intel display path when Optimus mode is active.

3. **Inspection of Documentation (`docs/verification_guide.md`)**:
   - Section 3.0 provides complete step-by-step instructions for entering Dell UEFI BIOS (F2) and configuring **Display > "Hybrid Graphics / Advanced Optimus"** to **Enabled / ON**, explaining why firmware hardware-locking prevents user-mode switching when set to OFF.

---

### 1.2 Runtime Tracing Results
1. **Direct Hardware & Subsystem API Queries**:
   - `Get-PnpDevice -Class Display`:
     - Intel(R) UHD Graphics: `InstanceId = PCI\VEN_8086&DEV_A78B&SUBSYS_0BF71028&REV_04\3&11583659&0&10`, `Status = OK`, `ConfigManagerErrorCode = CM_PROB_NONE`.
     - NVIDIA GeForce RTX 4060 Laptop GPU: `InstanceId = PCI\VEN_10DE&DEV_28E0&SUBSYS_0BF71028&REV_A1\4&3B6A47D9&0&0008`, `Status = OK`, `ConfigManagerErrorCode = CM_PROB_NONE`.
   - `Get-CimInstance Win32_VideoController`:
     - Intel UHD: `DriverVersion = 32.0.101.7088`, `Status = OK`, `Availability = 8` (Offline / Standby rasterizer).
     - NVIDIA RTX 4060: `DriverVersion = 32.0.16.2101`, `Status = OK`, `Availability = 3` (Running / Full Power).
   - `Get-PnpDevice -Class Monitor`:
     - Active node: `DISPLAY\AUOAA9F\5&39808DAE&2&UID4353`, `Status = OK`, `Present = True`.
     - Inactive node: `DISPLAY\AUOAA9F\4&3A9F8B26&8&UID8388688`, `Status = Unknown`, `Present = False`.

2. **Registry ACPI Table Verification**:
   - Key: `HKLM:\HARDWARE\ACPI\SSDA\DELL\NvdTable\00001000`
   - Table Size: `41,660` bytes
   - Signature: `SSDT`
   - OEM ID: `DELL  `
   - Table ID: `NvdTable`
   - Optimus Tokens Verified in Registry Binary:
     - `MHYB` : `True`
     - `NVOP` : `True`
     - `NVJT` : `True`
     - `OPTF` : `True`
     - `NVBR` : `True`
     - `NVPW` : `True`
     - `OPTIMUS` : `True`

3. **Daemon Process Health & NVIDIA Services**:
   - `DisplayFixDaemon.exe`:
     - PID: `31392`
     - Status: `Responding = True`
     - Start Time: `11/5/2026 10:17:22 PM`
     - Handles: `380`
     - Working Set: `29.19 MB`
     - CLI `--status` execution:
       ```
       Mutex Active:        True (Global\DisplayFixDaemon_SingleInstanceMutex)
       Process Running:     True (Count: 1)
       Process PID:         31392
       Working Set (MB):    27.89
       Refresh Rate (Hz):   360 Hz
       Display Scaling (%): 125%
       Brightness (%):      25%
       Brightness Backend:  NvWmiBrightness
       ```
   - Scheduled Task `DisplayFixDaemon`:
     - State: `Running`
     - RunLevel: `Highest`
     - LogonType: `Interactive`
   - NVIDIA Container Services:
     - `NVDisplay.ContainerLocalSystem`: `Status = Running`, `StartType = Automatic`
     - `NvContainerLocalSystem`: `Status = Running`, `StartType = Automatic`

4. **Execution of `scripts/diagnostics/test_display_modes.ps1`**:
   - Console run completed in `4259 ms` with `DIAGNOSTIC VERDICT: PASSED`.
   - JSON mode run (`-Json -NoFile`) emitted structured telemetry matching live system state (`DurationMs: 3712`, `OverallVerdict: "PASSED"`).
   - Log file `C:\ProgramData\DisplayFix\logs\display_modes.json` was generated dynamically with UTC timestamp `2026-11-05T17:09:14.3230216Z`.

---

### 1.3 Event Log & Integrity Validation
1. **Windows Event Logs**:
   - Application Event Log: Zero crashes or Application Error events (Event ID 1000) recorded for `DisplayFixDaemon.exe`.
   - System Event Log: Zero Display driver reset / TDR events (Event ID 4101) recorded.
2. **Automated Test Suites Execution**:
   - `tests/e2e/test_runner.ps1 -Tier 1`:
     - Total Suites: 16 | Total Tests: 80 | Passed: 80 | Failed: 0 | Skipped: 0
     - Duration: 14.94s | Result: `ALL TESTS PASSED`
   - `scripts/verify.ps1 -Quick`:
     - Total Verification Gates: 9 | Gates Passed: 9 | Gates Failed: 0
     - E2E Test Suite Coverage: 136 / 136 Tests Passing (29 Suites)
     - Duration: 29.92s | Final Verdict: `PASSED`

---

## 2. Logic Chain

1. **Premise**: In an authentic implementation, diagnostic scripts must query live system APIs rather than returning hardcoded results, and background services must maintain actual process handles and responsiveness.
2. **Observation**: Code review of `test_display_modes.ps1` verified that all data structures are populated via CIM, PnP, and binary registry reads. Independent PowerShell queries directly confirmed the identical values (e.g., 41,660 bytes in `SSDA\DELL\NvdTable\00001000`, PID 31392 for `DisplayFixDaemon`, `Availability = 8` for Intel, `Availability = 3` for NVIDIA).
3. **Observation**: `DisplayFixDaemon.exe` (PID 31392) is running under Task Scheduler with `RunLevel: Highest`, holding 380 handles and ~28MB working set, responding cleanly to IPC `--status`.
4. **Observation**: Windows Event Logs contain zero crash events for the daemon and zero GPU TDR events.
5. **Observation**: Running both `tests/e2e/test_runner.ps1 -Tier 1` and `scripts/verify.ps1 -Quick` yielded 100% genuine test execution (136/136 tests passing) without bypassed assertions.
6. **Inference**: The implementation, diagnostic tooling, and documentation are authentic and fully functional.
7. **Conclusion**: The work product passes all forensic criteria. Final verdict is **CLEAN**.

---

## 3. Caveats

1. **UEFI BIOS Setup Access**:
   - Because Dell G15 5530 hardware locks the display multiplexer at the firmware level when "Hybrid Graphics / Advanced Optimus" is set to OFF in BIOS, toggling this setting requires a physical reboot into the F2 BIOS Setup menu. It cannot and should not be modified via user-mode software. The worker correctly diagnosed this root cause and provided complete instructions in `docs/verification_guide.md` §3.0.
2. **External Displays**:
   - As documented, external display ports (HDMI 2.1, USB-C DP Alt-Mode) are hard-wired to the RTX 4060 dGPU on this chassis. Advanced Optimus dynamic switching applies strictly to the internal 360Hz AUO AA9F eDP panel.

---

## 4. Conclusion

The Milestone MR2 work product is **CLEAN**. All components—including hardware probing, MUX topology discovery, ACPI table validation, daemon stand-down safety invariants, NVIDIA container health, and user documentation—are authentic, genuine, and free of defects, mocks, or shortcuts.

---

## 5. Verification Method

To independently reproduce the forensic verification:

1. **Verify Live ACPI Table & Optimus Tokens**:
   ```powershell
   powershell -NoProfile -Command "& { `$item = Get-ItemProperty 'HKLM:\HARDWARE\ACPI\SSDA\DELL\NvdTable\00001000'; `$b = `$item.'00000000'; Write-Host ('Length: ' + `$b.Length); Write-Host ('Sig: ' + [System.Text.Encoding]::ASCII.GetString(`$b[0..3])); `$str = [System.Text.Encoding]::ASCII.GetString(`$b); foreach (`$t in @('MHYB','NVOP','NVJT','OPTF','NVBR','NVPW','OPTIMUS')) { Write-Host (`$t + ': ' + `$str.Contains(`$t)) } }"
   ```
   *Expected*: Length = 41660, Sig = SSDT, all 7 tokens evaluate to `True`.

2. **Verify Daemon Health and Status Telemetry**:
   ```powershell
   cmd.exe /c "bin\DisplayFixDaemon.exe --status"
   ```
   *Expected*: Mutex Active = True, Process Running = True (PID 31392), Refresh Rate = 360 Hz.

3. **Run Display Mode Diagnostic Prober**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\diagnostics\test_display_modes.ps1
   ```
   *Expected*: DIAGNOSTIC VERDICT: PASSED.

4. **Run Master Verification Acceptance Suite**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify.ps1 -Quick
   ```
   *Expected*: 9/9 Gates Passed, 136/136 Tests Passing, Final Verdict: PASSED.
