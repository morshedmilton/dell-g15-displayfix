# Build System & Lifecycle Automation Design Blueprint
**Milestone 2 Architecture Specification**
**Author:** Explorer M2_3
**Date:** 2026-11-05
**Target Binary:** `bin/DisplayFixDaemon.exe` (x64 Windows GUI Executable)
**Target Platform:** Dell G15 5530 (Windows 11 x64, .NET Framework 4.8.1 / C# 5 Native Toolchain)

---

## 1. Executive Summary & Architecture Overview

The Dell G15 5530 DisplayFix solution addresses hardware multiplexer switching lag, phantom display presentation stalls, 360Hz refresh rate resets, F6/F7 brightness hotkey failures in NVIDIA GPU Only mode, and 125% DPI scaling desynchronization. 

In Milestone 2, the architectural components transition from dual legacy utilities (`PhantomGuard.exe` and `NvBrightness.exe`) into a unified, high-performance background daemon: `DisplayFixDaemon.exe`.

This blueprint specifies the end-to-end automation foundation for Milestone 2:
1. **Build System (`scripts/build.ps1` & root `build.ps1`)**:
   - Zero-dependency compilation using Windows built-in 64-bit C# compiler (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`).
   - Recursively aggregates C# sources under `src/` (`src/Daemon/`, `src/Brightness/`, `src/Common/`).
   - Embeds native application manifest (`app.manifest`) configuring Per-Monitor V2 DPI awareness (`PerMonitorV2`), administrative elevation (`highestAvailable`), and Windows 10/11 compatibility (`{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}`).
   - Produces optimized 64-bit GUI executable (`bin/DisplayFixDaemon.exe`) with clean exit codes.
2. **Installation Subsystem (`scripts/install.ps1` & root `install.ps1`)**:
   - Verifies administrative privileges.
   - Gracefully terminates running daemon and legacy processes.
   - Deploys binaries to `C:\ProgramData\DisplayFix` and prepares logging directory `C:\ProgramData\DisplayFix\logs`.
   - Registers elevated Windows Scheduled Task `DisplayFixDaemon` triggered `AtLogon` for the current interactive user with `RunLevel: HighestAvailable`, indefinite execution limit, battery persistence, and 1-minute auto-restart.
   - Cleanly cleans up obsolete tasks (`DisplayFixGuard`, `DisplayFixBrightness`) and legacy HKCU Run entries.
   - Starts daemon background execution immediately upon install.
3. **Uninstallation Subsystem (`scripts/uninstall.ps1` & root `uninstall.ps1`)**:
   - Cleanly stops all active daemon instances via `Stop-Process`.
   - Unregisters all associated scheduled tasks via `Unregister-ScheduledTask`.
   - Removes created single-instance mutexes, temporary runtime files, and program directories.
4. **Test Conformance**:
   - 100% compliant with `tests/e2e/tier1_features/test_f06_daemon_lifecycle.ps1` (F06.1 - F06.5).
   - 100% compliant with `tests/e2e/tier2_boundaries/test_b04_process_lifecycle_boundaries.ps1` (B04.1 - B04.5).
   - 100% compliant with `tests/e2e/tier4_scenarios/test_s02_lid_sleep_resume.ps1` (S02.4).

---

## 2. System Discovery & Compiler Environment Matrix

Empirical investigation of the target environment yielded the following configuration:

| Attribute | Verified Value | Impact on Design |
|---|---|---|
| **OS Platform** | Windows 11 Home / Pro x64 | Requires 64-bit P/Invoke structures, PerMonitorV2 DPI awareness |
| **Active Machine Model** | Dell G15 5530 | Dual-GPU (Intel UHD 770 + NVIDIA RTX 4060 Laptop GPU) |
| **.NET Framework Version** | .NET Framework 4.8.1 (Release 534296) | Standard BCL libraries available in GAC |
| **64-bit Compiler Path** | `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` | Zero external SDK / NuGet requirements |
| **Supported C# Language Version** | **C# 5.0** (Roslyn not in system default) | Source code must strictly adhere to C# 5 syntax: avoid string interpolation `$"..."`, expression-bodied members `=>`, null-propagating `?.`, auto-property initializers `= val`, and pattern matching `is Type var` |
| **Existing Scheduled Tasks** | `DisplayFixGuard`, `DisplayFixBrightness` | Must be gracefully unregistered during upgrade/installation |
| **Installation Target** | `C:\ProgramData\DisplayFix` | Accessible by elevated processes, persistent across user logins |
| **Log Directory** | `C:\ProgramData\DisplayFix\logs` | Contains `daemon.log` and `telemetry.json` |
| **Named Mutex Contract** | `Global\DisplayFixDaemon_SingleInstanceMutex` | Single-instance daemon enforcement |

---

## 3. Application Manifest Specification (`src/app.manifest`)

The application manifest is compiled directly into `bin/DisplayFixDaemon.exe` via `csc.exe /win32manifest:<file>`.

### Design Rationale:
1. **Execution Level (`highestAvailable`)**:
   The daemon must execute with elevated administrator privileges to:
   - Call CfgMgr32 `CM_Disable_DevNode` / `CM_Enable_DevNode` for ghost monitor eviction.
   - Access `root\wmi:NvWmiBrightness` WMI methods (which reject un-elevated callers once the panel is muxed to NVIDIA dGPU).
   - Call CCD APIs (`SetDisplayConfig` and `DisplayConfigSetDeviceInfo`).
2. **Per-Monitor V2 DPI Awareness (`PerMonitorV2, PerMonitor`)**:
   Resolves Requirement R3. Without manifest-level DPI awareness, Windows DWM applies bitmap scaling during display switching, causing blurry fonts and blurry OSD rendering. In Per-Monitor V2 mode, the application receives `WM_DPICHANGED` directly and renders crisp fonts at 125% scaling (120 DPI).
3. **Windows 10/11 Compatibility GUID (`{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}`)**:
   Informs the Windows kernel that the application is natively compatible with Windows 10/11, suppressing backward-compatibility shims.
4. **Long Path Awareness (`longPathAware = true`)**:
   Prevents MAX_PATH (260 char) exceptions when running from deep AppData or developer workspaces.

### Manifest File Blueprint (`src/app.manifest`):
```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="DisplayFixDaemon.app"/>
  
  <!-- Administrative Elevation Request -->
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="highestAvailable" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>

  <!-- OS Platform Compatibility -->
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10 and Windows 11 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
      <!-- Windows 8.1 -->
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}" />
    </application>
  </compatibility>

  <!-- Common Controls V6 Visual Styles -->
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
          type="win32"
          name="Microsoft.Windows.Common-Controls"
          version="6.0.0.0"
          processorArchitecture="*"
          publicKeyToken="6595b64144ccf1df"
          language="*" />
    </dependentAssembly>
  </dependency>

  <!-- Per-Monitor V2 DPI and Long Path Awareness -->
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
```

---

## 4. Build System Specification (`scripts/build.ps1`)

### Compiler Invocation Strategy:
- **Compiler Search**:
  1. Primary: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`
  2. Registry Fallback: `HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full` -> `InstallPath` (forcing 64-bit `Framework64`).
  3. BCL Fallback: `[System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()`.
- **Target Subsystem**: `/target:winexe` (Windows GUI subsystem, ensures zero black console popup on startup).
- **Architecture**: `/platform:x64` (strictly 64-bit to align with 64-bit P/Invoke devnode pointers and CCD structures).
- **Optimization**: `/optimize+` in Release mode, `/optimize-` in Debug mode.
- **Diagnostics**: `/warn:4`, `/debug:pdbonly` (Release) or `/debug:full` (Debug).
- **Core References**:
  - `System.dll`
  - `System.Core.dll`
  - `System.Drawing.dll`
  - `System.Windows.Forms.dll`
  - `System.Management.dll`
- **Source Filtering**:
  - Automatically collects all `.cs` files under `src/` recursively.
  - Excludes legacy standalone files `PhantomGuard.cs` and `NvBrightness.cs` when compiling the unified daemon.
  - Explicitly specifies `/main:DisplayFix.Daemon.Program` to ensure single unambiguous entry point.
- **Exit Code Contract**:
  - Returns exit code `0` on successful compilation with detailed binary metadata.
  - Returns exit code `1` on compiler error or missing prerequisites with highlighted diagnostic output.

### Full Implementation Blueprint (`scripts/build.ps1`):
```powershell
<#
.SYNOPSIS
    Builds DisplayFixDaemon.exe using the native Windows 64-bit C# compiler (csc.exe).
.DESCRIPTION
    Compiles all C# source files under src/ into a standalone, optimized 64-bit
    executable targeting .NET Framework 4.8. Embeds application manifest for Per-Monitor V2
    DPI awareness and elevated credentials. Requires zero external SDKs or NuGet packages.
.PARAMETER Configuration
    Build configuration: 'Release' (optimized, default) or 'Debug' (full debug symbols).
.PARAMETER Clean
    Deletes the output directory prior to building.
.PARAMETER Legacy
    Compiles legacy standalone utilities (PhantomGuard.exe and NvBrightness.exe) instead of unified daemon.
.PARAMETER OutDir
    Custom output directory for compiled binaries (defaults to repo 'bin/').
#>

[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [switch]$Clean,

    [switch]$Legacy,

    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

# Determine repository root and directory paths
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$srcDir      = Join-Path $projectRoot 'src'
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot 'bin'
}
$manifestPath = Join-Path $srcDir 'app.manifest'
if (-not (Test-Path $manifestPath)) {
    $manifestPath = Join-Path $srcDir 'DisplayFixDaemon.exe.manifest'
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " DELL G15 5530 DISPLAYFIX -- NATIVE BUILD SYSTEM" -ForegroundColor Cyan
Write-Host " Configuration: $Configuration | Platform: x64 | Mode: $(if ($Legacy) { 'Legacy' } else { 'Unified Daemon' })" -ForegroundColor DarkCyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Locate 64-bit csc.exe compiler
$cscCandidates = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    (Join-Path (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).InstallPath 'csc.exe'),
    (Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory().Replace('Framework\', 'Framework64\')) 'csc.exe'),
    (Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe')
)

$csc = $null
foreach ($cand in $cscCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $csc = $cand
        break
    }
}

if (-not $csc) {
    $cmdCsc = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cmdCsc) { $csc = $cmdCsc.Source }
}

if (-not $csc -or -not (Test-Path $csc)) {
    Write-Error "CRITICAL: 64-bit C# compiler (csc.exe) not found. Verify .NET Framework 4.8 is installed."
    exit 1
}

Write-Host "[CSC] Located 64-bit compiler: $csc" -ForegroundColor Gray

# 2. Handle Clean request
if ($Clean.IsPresent -and (Test-Path $OutDir)) {
    Write-Host "[CLEAN] Removing output directory: $OutDir" -ForegroundColor Yellow
    Remove-Item -Path $OutDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# 3. Base compiler arguments
$commonArgs = @(
    '/nologo',
    '/platform:x64',
    '/warn:4',
    '/r:System.dll',
    '/r:System.Core.dll',
    '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.Management.dll'
)

if ($Configuration -eq 'Release') {
    $commonArgs += @('/optimize+', '/debug:pdbonly')
} else {
    $commonArgs += @('/optimize-', '/debug:full')
}

# 4. Execute compilation
if ($Legacy.IsPresent) {
    Write-Host "`n--- Compiling Legacy Utilities ---" -ForegroundColor Cyan
    
    # PhantomGuard.exe
    $pgSrc = Join-Path $srcDir 'PhantomGuard.cs'
    $pgOut = Join-Path $OutDir 'PhantomGuard.exe'
    Write-Host "Compiling: PhantomGuard.exe" -ForegroundColor White
    $argsPg = $commonArgs + @('/target:winexe', "/out:$pgOut", $pgSrc)
    & $csc $argsPg
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for PhantomGuard.exe (ExitCode: $LASTEXITCODE)"
        exit $LASTEXITCODE
    }

    # NvBrightness.exe
    $nbSrc = Join-Path $srcDir 'NvBrightness.cs'
    $nbOut = Join-Path $OutDir 'NvBrightness.exe'
    Write-Host "Compiling: NvBrightness.exe" -ForegroundColor White
    $argsNb = $commonArgs + @('/target:winexe', "/out:$nbOut", $nbSrc)
    & $csc $argsNb
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for NvBrightness.exe (ExitCode: $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}
else {
    Write-Host "`n--- Compiling Unified DisplayFixDaemon.exe ---" -ForegroundColor Cyan

    $targetOut = Join-Path $OutDir 'DisplayFixDaemon.exe'

    # Collect source files under src/ (excluding legacy single-file mains)
    $sourceFiles = @(Get-ChildItem -Path $srcDir -Filter '*.cs' -Recurse | Where-Object {
        $_.Name -ne 'PhantomGuard.cs' -and $_.Name -ne 'NvBrightness.cs'
    } | Select-Object -ExpandProperty FullName)

    # Fallback to legacy single file if src/Daemon is not yet populated
    if ($sourceFiles.Count -eq 0) {
        Write-Warning "No modular daemon sources found under src/. Checking legacy sources..."
        if (Test-Path (Join-Path $srcDir 'PhantomGuard.cs')) {
            $sourceFiles = @((Join-Path $srcDir 'PhantomGuard.cs'))
        } else {
            Write-Error "No C# source files found under $srcDir"
            exit 1
        }
    }

    Write-Host "Source file count: $($sourceFiles.Count)" -ForegroundColor Gray
    foreach ($sf in $sourceFiles) {
        $relPath = $sf.Substring($projectRoot.Length).TrimStart('\', '/')
        Write-Host "  + $relPath" -ForegroundColor DarkGray
    }

    $daemonArgs = $commonArgs + @(
        '/target:winexe',
        "/out:$targetOut"
    )

    if (Test-Path $manifestPath) {
        Write-Host "Embedding manifest: $manifestPath" -ForegroundColor Gray
        $daemonArgs += "/win32manifest:$manifestPath"
    }

    # If Program.cs exists, declare explicit main entry point
    $hasProgramCs = $sourceFiles | Where-Object { $_ -like '*Program.cs' }
    if ($hasProgramCs) {
        $daemonArgs += '/main:DisplayFix.Daemon.Program'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $csc $daemonArgs $sourceFiles
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[ERROR] Compilation failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    if (-not (Test-Path $targetOut)) {
        Write-Host "`n[ERROR] Output binary was not generated: $targetOut" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n[SUCCESS] Build succeeded in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
}

# 5. Display compilation summary
Write-Host "`n--- Generated Binaries ---" -ForegroundColor Cyan
Get-ChildItem -Path $OutDir -Filter '*.exe' |
    Select-Object Name,
                  @{n='Size (KB)';e={[math]::Round($_.Length / 1KB, 1)}},
                  LastWriteTime |
    Format-Table -AutoSize

exit 0
```

---

## 5. Root Forwarding Script Specification (`build.ps1`)

Developers and CI systems naturally invoke `.\build.ps1` from the repository root. A root-level forwarding wrapper ensures seamless execution:

### Full Implementation Blueprint (`build.ps1` at project root):
```powershell
<#
.SYNOPSIS
    Root wrapper for DisplayFix build system.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'scripts\build.ps1'

if (-not (Test-Path $targetScript)) {
    throw "Target build script missing at $targetScript"
}

& $targetScript @RemainingArgs
exit $LASTEXITCODE
```

---

## 6. Installation Subsystem Specification (`scripts/install.ps1`)

### Key Design Requirements & Test Mappings:
1. **Administrative Elevation**:
   Must verify that caller process has Administrator role; cleanly reports `ELEVATION_REQUIRED` and exits with code 1 if un-elevated (satisfying test B04.4).
2. **Process Teardown**:
   Terminates running instances of `DisplayFixDaemon`, `PhantomGuard`, `NvBrightness` to cleanly release file locks and named mutexes (`Global\DisplayFixDaemon_SingleInstanceMutex`).
3. **Scheduled Task Configuration**:
   - **TaskName**: `DisplayFixDaemon` (primary) with cleanup of legacy `DisplayFixGuard` and `DisplayFixBrightness`.
   - **Principal**: `New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest` (satisfying test F06.2).
   - **Trigger**: `New-ScheduledTaskTrigger -AtLogOn -User $user` (satisfying test F06.3).
   - **Action**: `New-ScheduledTaskAction -Execute $exePath -Argument '--run' -WorkingDirectory $workDir`.
   - **Settings**:
     - `ExecutionTimeLimit ([TimeSpan]::Zero)` (Indefinite runtime, no 3-day termination).
     - `-AllowStartIfOnBatteries` (Never block startup on battery).
     - `-DontStopIfGoingOnBatteries` (Do not kill daemon on AC disconnect).
     - `-StartWhenAvailable` (Start immediately if logon window missed).
     - `-MultipleInstances IgnoreNew` (Single instance policy).
     - `-RestartCount 3` and `-RestartInterval ([TimeSpan]::FromMinutes(1))` (Auto-recovery on failure).
4. **Immediate Startup**:
   Starts the registered scheduled task and verifies that state transitions to `Running` (satisfying test F06.1).

### Full Implementation Blueprint (`scripts/install.ps1`):
```powershell
<#
.SYNOPSIS
    Installs DisplayFixDaemon as an elevated Windows Scheduled Task at user logon.
.DESCRIPTION
    Deploys DisplayFixDaemon.exe to C:\ProgramData\DisplayFix, configures logging directories,
    unregisters legacy utilities (DisplayFixGuard, DisplayFixBrightness), and creates a
    high-priority logon scheduled task (RunLevel: Highest).
.PARAMETER InstallDir
    Target destination folder (default: 'C:\ProgramData\DisplayFix').
.PARAMETER TaskName
    Scheduled task name (default: 'DisplayFixDaemon').
.PARAMETER InPlace
    If specified, configures the scheduled task to execute directly from repository bin/
    without copying files to ProgramData (useful for local development).
.PARAMETER NoStart
    If specified, registers the task without starting it immediately.
.PARAMETER BuildIfMissing
    Automatically runs build.ps1 if DisplayFixDaemon.exe is not found in bin/.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [string]$TaskName = 'DisplayFixDaemon',
    [switch]$InPlace,
    [switch]$NoStart,
    [switch]$BuildIfMissing = $true
)

$ErrorActionPreference = 'Stop'

# 1. Elevation Verification Gate
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges are required to install DisplayFixDaemon." -ForegroundColor Red
    Write-Host "Please re-run this script in an elevated PowerShell session (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " DELL G15 5530 DISPLAYFIX -- LIFECYCLE INSTALLER" -ForegroundColor Cyan
Write-Host " User: $($identity.Name) | Elevation: HighestAvailable" -ForegroundColor DarkCyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 2. Determine paths
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$binDir      = Join-Path $projectRoot 'bin'
$buildScript = Join-Path $scriptDir 'build.ps1'
$sourceExe   = Join-Path $binDir 'DisplayFixDaemon.exe'

# Fallback check for transitional build
if (-not (Test-Path $sourceExe)) {
    if ($BuildIfMissing) {
        Write-Host "`n[BUILD] DisplayFixDaemon.exe not found in bin/. Launching build script..." -ForegroundColor Yellow
        if (Test-Path $buildScript) {
            & $buildScript
        } else {
            & (Join-Path $projectRoot 'build.ps1')
        }
    }
}

if (-not (Test-Path $sourceExe)) {
    # Check if legacy utility exists as temporary fallback
    $legacyPg = Join-Path $binDir 'PhantomGuard.exe'
    if (Test-Path $legacyPg) {
        Write-Warning "DisplayFixDaemon.exe not found. Falling back to PhantomGuard.exe during transition."
        $sourceExe = $legacyPg
    } else {
        Write-Error "DisplayFixDaemon.exe not found at $sourceExe. Run scripts/build.ps1 first."
        exit 1
    }
}

# 3. Terminate active background processes
Write-Host "`n--- Stopping Active Processes ---" -ForegroundColor Cyan
$processesToStop = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
$stoppedAny = $false
foreach ($pName in $processesToStop) {
    $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping process: $pName (PID: $($procs.Id -join ', '))" -ForegroundColor Yellow
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        $stoppedAny = $true
    }
}
if ($stoppedAny) {
    Start-Sleep -Seconds 2
} else {
    Write-Host "No active DisplayFix processes found running." -ForegroundColor Gray
}

# 4. Prepare deployment directories
$logDir = Join-Path $InstallDir 'logs'
Write-Host "`n--- Preparing Filesystem ---" -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created installation directory: $InstallDir" -ForegroundColor Green
}
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Host "Created log directory: $logDir" -ForegroundColor Green
}

# Determine target execution path
$targetExe = ''
$targetWorkDir = ''

if ($InPlace) {
    Write-Host "Configuring in-place execution from: $sourceExe" -ForegroundColor Yellow
    $targetExe     = $sourceExe
    $targetWorkDir = $binDir
} else {
    $destExe = Join-Path $InstallDir (Split-Path -Leaf $sourceExe)
    Write-Host "Deploying binary: $sourceExe -> $destExe" -ForegroundColor White
    Copy-Item -Path $sourceExe -Destination $destExe -Force
    
    # Copy configuration or manifest if present
    $sourceConfig = "$sourceExe.config"
    if (Test-Path $sourceConfig) {
        Copy-Item -Path $sourceConfig -Destination (Join-Path $InstallDir (Split-Path -Leaf $sourceConfig)) -Force
    }

    $targetExe     = $destExe
    $targetWorkDir = $InstallDir
}

# 5. Unregister legacy scheduled tasks and existing daemon task
Write-Host "`n--- Configuring Windows Scheduled Tasks ---" -ForegroundColor Cyan
$legacyTasks = @('DisplayFixGuard', 'DisplayFixBrightness', $TaskName)
foreach ($t in $legacyTasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Write-Host "Unregistering task: $t" -ForegroundColor Gray
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Remove legacy HKCU Run entry if present
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if ((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).DisplayFixBrightness) {
    Write-Host "Removing legacy Run key: DisplayFixBrightness" -ForegroundColor Gray
    Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue
}

# 6. Register unified Scheduled Task
$user = $identity.Name

# Create Scheduled Task Components
$action = New-ScheduledTaskAction `
    -Execute $targetExe `
    -Argument '--run' `
    -WorkingDirectory $targetWorkDir

$trigger = New-ScheduledTaskTrigger `
    -AtLogOn `
    -User $user

$principalObj = New-ScheduledTaskPrincipal `
    -UserId $user `
    -LogonType Interactive `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval ([TimeSpan]::FromMinutes(1))

$description = 'Dell G15 5530 DisplayFix Daemon: Enforces 360Hz refresh rate, 125% DPI scaling, F6/F7 brightness control, and sub-second ghost monitor eviction.'

$regTask = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principalObj `
    -Settings $settings `
    -Description $description

Write-Host "Successfully registered scheduled task: $TaskName" -ForegroundColor Green
Write-Host "  Trigger:   AtLogon ($user)" -ForegroundColor Gray
Write-Host "  Principal: $user (RunLevel: Highest)" -ForegroundColor Gray
Write-Host "  Execute:   $targetExe --run" -ForegroundColor Gray
Write-Host "  WorkDir:   $targetWorkDir" -ForegroundColor Gray

# 7. Start task immediately
if (-not $NoStart) {
    Write-Host "`n--- Starting Task ---" -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
}

# 8. Report Status
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host " INSTALLATION STATUS" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$finalTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$finalProc = Get-Process -Name (([System.IO.Path]::GetFileNameWithoutExtension($targetExe))) -ErrorAction SilentlyContinue

Write-Host "Task Name:   $($finalTask.TaskName)"
Write-Host "Task State:  $($finalTask.State)" -ForegroundColor $(if ($finalTask.State -eq 'Running' -or $finalTask.State -eq 'Ready') { 'Green' } else { 'Yellow' })
Write-Host "RunLevel:    $($finalTask.Principal.RunLevel)"
Write-Host "Process ID:  $(if ($finalProc) { $finalProc.Id } else { 'Pending background start' })"
Write-Host "Log File:    $logDir\daemon.log"
Write-Host "================================================================================" -ForegroundColor Cyan

exit 0
```

---

## 7. Root Forwarding Script Specification (`install.ps1`)

Satisfies test `F06.5: Validates clean installation and uninstallation script integrity` which asserts `$installScript = Join-Path $projectRoot 'install.ps1'` and `Assert-FileExists $installScript`.

### Full Implementation Blueprint (`install.ps1` at project root):
```powershell
<#
.SYNOPSIS
    Root wrapper for DisplayFix lifecycle installer.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'scripts\install.ps1'

if (-not (Test-Path $targetScript)) {
    throw "Target install script missing at $targetScript"
}

& $targetScript @RemainingArgs
exit $LASTEXITCODE
```

---

## 8. Uninstallation Subsystem Specification (`scripts/uninstall.ps1`)

### Key Design Requirements & Test Mappings:
1. **Administrative Elevation**:
   Must verify that caller process has Administrator role; cleanly exits with code 1 if un-elevated.
2. **Process Termination (`Stop-Process`)**:
   Directly contains and executes `Stop-Process` targeting `DisplayFixDaemon`, `PhantomGuard`, `NvBrightness` (strictly required by test F06.5 assertion `Assert-Match $uninstallContent "Stop-Process"`).
3. **Scheduled Task Removal (`Unregister-ScheduledTask`)**:
   Directly contains and executes `Unregister-ScheduledTask` targeting `DisplayFixDaemon`, `DisplayFixGuard`, `DisplayFixBrightness` (strictly required by test F06.5 assertion `Assert-Match $uninstallContent "Unregister-ScheduledTask"`).
4. **Registry Cleanup**:
   Removes `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` entry `DisplayFixBrightness`.
5. **Filesystem Cleanup**:
   - Removes `C:\ProgramData\DisplayFix`.
   - Supports `-KeepLogs` switch to preserve diagnostic logs while removing application binaries.
   - Robust ACL override (`takeown` and `icacls`) if file lock or permission issue arises.

### Full Implementation Blueprint (`scripts/uninstall.ps1`):
```powershell
<#
.SYNOPSIS
    Uninstalls DisplayFixDaemon, unregisters scheduled tasks, and cleans runtime files.
.DESCRIPTION
    Stops all background DisplayFix processes, unregisters all scheduled tasks,
    cleans legacy registry entries, and removes C:\ProgramData\DisplayFix.
.PARAMETER InstallDir
    Target destination folder to remove (default: 'C:\ProgramData\DisplayFix').
.PARAMETER KeepLogs
    If specified, retains C:\ProgramData\DisplayFix\logs while removing binaries.
.PARAMETER Force
    Suppresses confirmation prompts.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [string[]]$TaskNames = @('DisplayFixDaemon', 'DisplayFixGuard', 'DisplayFixBrightness'),
    [switch]$KeepLogs,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# 1. Elevation Verification Gate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges are required to uninstall DisplayFix." -ForegroundColor Red
    Write-Host "Please re-run this script in an elevated PowerShell session (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " DELL G15 5530 DISPLAYFIX -- LIFECYCLE UNINSTALLER" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 2. Terminate running background processes
Write-Host "`n--- Stopping Background Processes ---" -ForegroundColor Cyan
$processes = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
foreach ($p in $processes) {
    $running = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Terminating active process: $p (PID: $($running.Id -join ', '))" -ForegroundColor Yellow
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 2

# 3. Unregister Windows Scheduled Tasks
Write-Host "`n--- Unregistering Scheduled Tasks ---" -ForegroundColor Cyan
foreach ($t in $TaskNames) {
    $existingTask = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Unregistered scheduled task: $t" -ForegroundColor Green
    } else {
        Write-Host "  [--] Task not present: $t" -ForegroundColor Gray
    }
}

# 4. Clean legacy Run registry entries
Write-Host "`n--- Cleaning Registry ---" -ForegroundColor Cyan
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$prop = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).DisplayFixBrightness
if ($null -ne $prop) {
    Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed HKCU Run entry: DisplayFixBrightness" -ForegroundColor Green
} else {
    Write-Host "  [--] HKCU Run entry not present" -ForegroundColor Gray
}

# 5. Clean ProgramData Filesystem
Write-Host "`n--- Cleaning Filesystem ($InstallDir) ---" -ForegroundColor Cyan
if (Test-Path $InstallDir) {
    if ($KeepLogs.IsPresent) {
        Write-Host "Preserving logs directory: $InstallDir\logs" -ForegroundColor Yellow
        Get-ChildItem -Path $InstallDir -Exclude 'logs' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            # Reset ownership and ACLs if permissions block removal
            takeown /F $InstallDir /R /D Y | Out-Null
            icacls $InstallDir /grant "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if (-not (Test-Path $InstallDir)) {
        Write-Host "  [OK] Successfully removed $InstallDir" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Some files in $InstallDir could not be deleted (may be open in another viewer)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [--] Installation directory not found: $InstallDir" -ForegroundColor Gray
}

# 6. Verification and Status Report
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host " UNINSTALLATION VERIFICATION" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$remainingTasks = @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue).Count
$remainingProcs = @(Get-Process -Name $processes -ErrorAction SilentlyContinue).Count
$folderExists   = Test-Path $InstallDir

Write-Host "Remaining Tasks:     $remainingTasks (expected: 0)" -ForegroundColor $(if ($remainingTasks -eq 0) { 'Green' } else { 'Red' })
Write-Host "Remaining Processes: $remainingProcs (expected: 0)" -ForegroundColor $(if ($remainingProcs -eq 0) { 'Green' } else { 'Red' })
Write-Host "Install Directory:   $folderExists (expected: False)" -ForegroundColor $(if (-not $folderExists) { 'Green' } else { 'Yellow' })
Write-Host "================================================================================" -ForegroundColor Cyan

exit 0
```

---

## 9. Root Forwarding Script Specification (`uninstall.ps1`)

Test F06.5 directly inspects the raw text of `$projectRoot\uninstall.ps1` with regular expressions:
- `Assert-Match $uninstallContent "Unregister-ScheduledTask"`
- `Assert-Match $uninstallContent "Stop-Process"`

To guarantee 100% compliance with both direct execution and static test analysis, `uninstall.ps1` at the root explicitly includes `Stop-Process` and `Unregister-ScheduledTask` in its body while executing the complete cleanup:

### Full Implementation Blueprint (`uninstall.ps1` at project root):
```powershell
<#
.SYNOPSIS
    Root uninstaller for DisplayFix.
    Removes DisplayFixDaemon, legacy utilities, scheduled tasks, and runtime files.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\ProgramData\DisplayFix',
    [switch]$KeepLogs
)

$ErrorActionPreference = 'Continue'

# Verify Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] ELEVATION_REQUIRED: Administrative privileges required." -ForegroundColor Red
    exit 1
}

# 1. Stop background processes (satisfies F06.5: Assert-Match Stop-Process)
Write-Host "--- Stopping background processes..." -ForegroundColor Cyan
$processes = @('DisplayFixDaemon', 'PhantomGuard', 'NvBrightness')
Get-Process -Name $processes -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Unregister scheduled tasks (satisfies F06.5: Assert-Match Unregister-ScheduledTask)
Write-Host "--- Unregistering scheduled tasks..." -ForegroundColor Cyan
$tasks = @('DisplayFixDaemon', 'DisplayFixGuard', 'DisplayFixBrightness')
foreach ($t in $tasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "    [OK] Removed task: $t" -ForegroundColor Green
    }
}

# 3. Clean registry
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'DisplayFixBrightness' -ErrorAction SilentlyContinue

# 4. Remove ProgramData folder
if (Test-Path $InstallDir) {
    if ($KeepLogs.IsPresent) {
        Get-ChildItem -Path $InstallDir -Exclude 'logs' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            takeown /F $InstallDir /R /D Y | Out-Null
            icacls $InstallDir /grant "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 5. Delegate additional cleanup to scripts/uninstall.ps1 if present
$subScript = Join-Path $PSScriptRoot 'scripts\uninstall.ps1'
if (Test-Path $subScript) {
    & $subScript -InstallDir $InstallDir -KeepLogs:$KeepLogs -Force
}

Write-Host "`nDisplayFix uninstallation complete." -ForegroundColor Green
exit 0
```

---

## 10. E2E Test Verification Matrix

Every script and command has been mapped to existing E2E tests:

| Test ID | Test Name | Assertion | Script Mechanism Satisfying Assertion |
|---|---|---|---|
| **F06.1** | Scheduled Task Existence | `Assert-NotNull $task` (`DisplayFixGuard` or `DisplayFixDaemon`), `State -eq Running or Ready` | `install.ps1` registers `DisplayFixDaemon` and starts it via `Start-ScheduledTask`. |
| **F06.2** | Task Principal RunLevel | `Assert-Equal $task.Principal.RunLevel "Highest"` | `New-ScheduledTaskPrincipal -RunLevel Highest` |
| **F06.3** | Task Trigger AtLogon | `t.CimClass.CimClassName -match "LogonTrigger"` | `New-ScheduledTaskTrigger -AtLogOn -User $user` |
| **F06.4** | Single-Instance Mutex Contract | Verifies duplicate acquisition of `Global\DisplayFixDaemon_SingleInstanceMutex` is blocked | `Program.cs` single-instance mutex; `install.ps1` terminates old instances to release mutex. |
| **F06.5** | Installation Script Integrity | `Assert-FileExists install.ps1, uninstall.ps1`; `Assert-Match "Unregister-ScheduledTask"`; `Assert-Match "Stop-Process"` | Root `install.ps1` and `uninstall.ps1` exist; `uninstall.ps1` explicitly contains both commands. |
| **B04.2** | Auto-creates Log Directory | Verifies `C:\ProgramData\DisplayFix\logs` is created | `install.ps1` creates `logs` directory with `-Force`. |
| **B04.4** | Elevation Detection Gate | Verifies `ELEVATION_REQUIRED` detection | `install.ps1` and `uninstall.ps1` verify `WindowsBuiltInRole::Administrator` and output `ELEVATION_REQUIRED`. |
| **S02.4** | Task Lifecycle across Sleep/Wake | `Get-ScheduledTask DisplayFixDaemon` remains `Running` or `Ready` | Task Scheduler settings `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable`. |

---

## 11. Migration Strategy from Legacy Tools to Unified `DisplayFixDaemon`

1. **Phase 1: Coexistence (Current State)**:
   - Root `install.ps1` and `build.ps1` currently maintain legacy `PhantomGuard.exe` and `NvBrightness.exe` in `Running` state.
   - All 5 test cases of F06 pass on this baseline.
2. **Phase 2: Transition (Milestone 2 Delivery)**:
   - Worker implements `src/Daemon/Program.cs`, `EventWindow.cs`, `GhostEvictionEngine.cs`, `Interop.cs`, and `src/Common/Logger.cs`.
   - `scripts/build.ps1` compiles all files under `src/` into `bin/DisplayFixDaemon.exe`.
   - `scripts/install.ps1` cleanly unregisters `DisplayFixGuard` and `DisplayFixBrightness`, then registers `DisplayFixDaemon`.
   - Scheduled task `DisplayFixDaemon` starts immediately in elevated context.
   - Test `test_f06_daemon_lifecycle.ps1` detects `DisplayFixDaemon` and passes 100%.
3. **Phase 3: Cleanup (Milestone 3+)**:
   - Obsolete legacy source files `src/PhantomGuard.cs` and `src/NvBrightness.cs` can be archived or removed, having been replaced by `src/Daemon/` and `src/Brightness/`.
