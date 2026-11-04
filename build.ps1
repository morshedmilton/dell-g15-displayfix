# Builds NvBrightness.exe and PhantomGuard.exe with the .NET Framework compiler
# that ships with Windows (no SDK required).

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = Join-Path $root 'src'
$bin   = Join-Path $root 'bin'
$csc   = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path $csc)) { throw "csc.exe not found at $csc" }
New-Item -ItemType Directory -Path $bin -Force | Out-Null

$common = @(
    '/nologo'
    '/platform:x64'
    '/optimize+'
    '/warn:4'
    '/r:System.dll'
    '/r:System.Core.dll'
    '/r:System.Management.dll'
    '/r:System.Windows.Forms.dll'
    '/r:System.Drawing.dll'
)

Write-Host '--- PhantomGuard.exe'
& $csc @common '/target:winexe' "/out:$bin\PhantomGuard.exe" (Join-Path $src 'PhantomGuard.cs')
if ($LASTEXITCODE -ne 0) { throw "PhantomGuard build failed ($LASTEXITCODE)" }

Write-Host '--- NvBrightness.exe'
& $csc @common '/target:winexe' "/out:$bin\NvBrightness.exe" (Join-Path $src 'NvBrightness.cs')
if ($LASTEXITCODE -ne 0) { throw "NvBrightness build failed ($LASTEXITCODE)" }

Get-ChildItem $bin | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize
