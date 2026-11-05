# Handoff Report: Explorer M1_IT2_3 — Fix Formulation for Defects 3 & 4 (Concurrency & I/O)

**Agent**: Explorer M1_IT2_3  
**Target File**: `scripts/diagnostics/stress_test.ps1`  
**Milestone**: Milestone 1 (Diagnostics, Telemetry & Stress Harness) - Iteration 2  
**Date**: 2026-11-05T11:46:00Z  
**Type**: Hard Handoff  

---

## 1. Observation

Direct empirical observations from `scripts/diagnostics/stress_test.ps1` and Challenger M1_2's audit findings:

1. **Defect 3 (Concurrency Report Collision)**:
   - **File & Line**: `scripts/diagnostics/stress_test.ps1:504-506`:
     ```powershell
     # --- 6. Write JSON & Markdown Reports ---
     $timestampStr = $startTimeUtc.ToString("yyyyMMdd_HHmmss")
     $jsonReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.json"
     $mdReportPath = Join-Path $OutputDir "stress_test_report_${timestampStr}.md"
     ```
   - **Observation & Reproduction**: When two test processes run concurrently within the same second, both evaluate identical `$timestampStr` (e.g. `20261105_113407`).
   - Verbatim result from Challenger M1_2 reproduction:
     `GeneratedFilesCount: 2` (expected 4 files for 2 concurrent jobs).
     `GeneratedFilenames: stress_test_report_20261105_113407.json, stress_test_report_20261105_113407.md`.
     Job 2 silently overwrote Job 1's report without warning or error, destroying the audit record.

2. **Defect 4 (Missing Drive / OutputDir Failure)**:
   - **File & Line**: `scripts/diagnostics/stress_test.ps1:287-289`:
     ```powershell
     if (-not (Test-Path $OutputDir)) {
         New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
     }
     ```
   - **Observation & Reproduction**: Line 84 configures `$ErrorActionPreference = "Stop"`. When executed with an invalid drive letter (e.g. `-OutputDir "Z:\NonExistentDrive\logs"`), `New-Item` throws:
     `THREW: System.Management.Automation.DriveNotFoundException - Cannot find drive. A drive with the name 'Z' does not exist.`
   - Verbatim test output under `$ErrorActionPreference = "Stop"`:
     `CAUGHT TERMINATING: System.Management.Automation.DriveNotFoundException - Cannot find drive. A drive with the name 'Z' does not exist.`
   - The script terminates immediately before taking baseline measurements, executing test cycles, or generating any diagnostic artifact.

---

## 2. Logic Chain

1. **Step 1 (From Observation 1)**: The report filename generation uses `$startTimeUtc.ToString("yyyyMMdd_HHmmss")`. Because its resolution is limited to 1 second, any two processes executing or starting within the same clock second resolve to the identical file path on disk.
2. **Step 2 (From Observation 1)**: In CI/CD pipelines, parallel test runners, or multi-agent test environments, rapid consecutive or concurrent executions will overwrite prior report artifacts.
3. **Step 3 (Remediation for Defect 3)**: Incorporating the automatic variable `$PID` via `"$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"` provides guaranteed process-level uniqueness across Windows processes while retaining chronological sortability (`yyyyMMdd_HHmmss_PID`) and backward compatibility with `stress_test_report_*.json` wildcard queries.
4. **Step 4 (From Observation 2)**: In lines 287-289, `New-Item` is called outside any exception handler. When an invalid drive volume is passed, the filesystem provider throws a `DriveNotFoundException`.
5. **Step 5 (From Observation 2)**: Because `$ErrorActionPreference = "Stop"`, this unhandled exception crashes PowerShell immediately, preventing baseline metrics collection or graceful recovery.
6. **Step 6 (Remediation for Defect 4)**: Wrapping `Test-Path` and `New-Item` in a `try/catch` block allows the script to intercept drive or path errors, emit an informative `Write-Warning`, mutate `$OutputDir` to `$env:TEMP\DisplayFix\logs` (which is guaranteed to exist and be writable by both standard and elevated processes), and create the fallback directory safely. Downstream report writing automatically targets the updated `$OutputDir`.

---

## 3. Caveats

- **Scope Boundary**: This investigation is strictly read-only. No source files were modified. Proposed code changes and replacements are documented for the implementer agent.
- **Defect 1 & 2 Independence**: Explorer M1_IT2_1 is investigating Defect 1 (DWM process termination crash) and Explorer M1_IT2_2 is investigating Defect 2 (low-iteration false positive failure). The fixes for Defects 3 & 4 do not conflict with or depend on Defects 1 & 2; they operate on independent sections of the script (initialization lines 287-289 and report generation line 504).
- **Environment**: Tested on Windows 11 with PowerShell 5.1 / PowerShell 7.

---

## 4. Conclusion

The exact code replacements for Defects 3 and 4 in `scripts/diagnostics/stress_test.ps1` are formulated and ready for immediate implementation.

### Exact Code Replacement 1 (Defect 4 — Lines 287–289)

**Target**: `scripts/diagnostics/stress_test.ps1` lines 287–289

**Original Code**:
```powershell
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}
```

**Proposed Replacement**:
```powershell
try {
    if (-not (Test-Path -LiteralPath $OutputDir -ErrorAction Stop)) {
        New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $fallbackDir = Join-Path $env:TEMP "DisplayFix\logs"
    Write-Warning "Failed to create or access OutputDir '$OutputDir': $($_.Exception.Message). Falling back to '$fallbackDir'."
    $OutputDir = $fallbackDir
    try {
        if (-not (Test-Path -LiteralPath $OutputDir -ErrorAction Stop)) {
            New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Warning "Failed to create fallback directory '$OutputDir': $($_.Exception.Message)"
    }
}
```

### Exact Code Replacement 2 (Defect 3 — Line 504)

**Target**: `scripts/diagnostics/stress_test.ps1` line 504

**Original Code**:
```powershell
$timestampStr = $startTimeUtc.ToString("yyyyMMdd_HHmmss")
```

**Proposed Replacement**:
```powershell
$timestampStr = "$($startTimeUtc.ToString('yyyyMMdd_HHmmss'))_$($PID)"
```

---

## 5. Verification Method

To independently verify the implementation after code application:

### Test 1: Concurrency Collision Verification (Defect 3)
```powershell
$testDir = Join-Path $env:TEMP "test_concur_verify_$([Guid]::NewGuid().ToString('N'))"
New-Item -Path $testDir -ItemType Directory -Force | Out-Null
$scriptPath = (Resolve-Path "scripts\diagnostics\stress_test.ps1").Path

try {
    $j1 = Start-Job -ScriptBlock { param($s,$d) & $s -Iterations 1 -Mode Simulated -OutputDir $d -Json } -ArgumentList $scriptPath, $testDir
    $j2 = Start-Job -ScriptBlock { param($s,$d) & $s -Iterations 1 -Mode Simulated -OutputDir $d -Json } -ArgumentList $scriptPath, $testDir
    Wait-Job $j1, $j2 | Out-Null

    $jsonFiles = Get-ChildItem -Path $testDir -Filter "*.json"
    $mdFiles   = Get-ChildItem -Path $testDir -Filter "*.md"

    # Invalidation condition: jsonFiles.Count != 2 or filenames do not contain distinct PIDs
    if ($jsonFiles.Count -ne 2) { throw "Verification FAILED: Expected 2 JSON files, found $($jsonFiles.Count)" }
    Write-Host "PASS: 2 distinct JSON reports generated: $($jsonFiles.Name -join ', ')" -ForegroundColor Green
} finally {
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
```

### Test 2: Missing Drive Fallback Verification (Defect 4)
```powershell
$allDrives = [System.IO.DriveInfo]::GetDrives().Name | ForEach-Object { $_[0].ToString().ToUpper() }
$unusedDrive = ('Z','Y','X','W','V','U' | Where-Object { $_ -notin $allDrives })[0]
$bogusPath = "${unusedDrive}:\NonExistentDrive\logs"
$scriptPath = (Resolve-Path "scripts\diagnostics\stress_test.ps1").Path

$output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '$scriptPath' -Iterations 1 -Mode Simulated -OutputDir '$bogusPath' -Json }"
# Invalidation condition: Script throws unhandled DriveNotFoundException or fails to write to $env:TEMP\DisplayFix\logs
$fallbackDir = Join-Path $env:TEMP "DisplayFix\logs"
$reports = Get-ChildItem -Path $fallbackDir -Filter "stress_test_report_*.json"
if ($reports.Count -lt 1) { throw "Verification FAILED: Fallback report missing in $fallbackDir" }
Write-Host "PASS: Missing drive gracefully handled, report saved to $($reports[-1].FullName)" -ForegroundColor Green
```
