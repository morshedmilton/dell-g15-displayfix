Write-Host "=== CHECKING OTA-ARTIFACTS FILES ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts\grd" -Recurse |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "=== CHECKING LOG.NVIDIA APP.EXE.LOG (LAST 100 LINES) ==="
$nvAppLog = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\UXD\Log.NVIDIA App.exe.log"
if (Test-Path $nvAppLog) {
    Get-Content $nvAppLog -Tail 100
}
