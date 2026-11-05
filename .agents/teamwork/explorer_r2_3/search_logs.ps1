Write-Host "=== SEARCHING LOGS FOR ERRORS / DOWNLOAD ISSUES ==="

$logFiles = @(
    "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UXD\Log.nvcontainer.exe.log",
    "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UXD\Log.nvcontainer.exe.log1",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\UXD\Log.NVIDIA App.exe.log",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\UXD\Log.NVIDIA App.exe.log1",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\NvBackend\backend.log"
)

foreach ($f in $logFiles) {
    if (Test-Path $f) {
        Write-Host "`n----------------------------------------"
        Write-Host "File: $f (Size: $((Get-Item $f).Length) bytes, Modified: $((Get-Item $f).LastWriteTime))"
        Write-Host "----------------------------------------"
        # Search for errors or relevant keywords
        Select-String -Path $f -Pattern "(error|fail|exception|infinite|stuck|lock|grd|download|tuning|tune|NvPerf)" -CaseSensitive:$false |
            Select-Object -Last 25 |
            ForEach-Object { $_.Line }
    } else {
        Write-Host "File not found: $f"
    }
}
