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
