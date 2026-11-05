Write-Host "=== ALL NVOC LOG ENTRIES IN CXNATIVE_NVIDIA APP.LOG ==="
$log = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.log"
if (Test-Path $log) {
    Get-Content $log | Where-Object { $_ -match "NvOc|scanner|tuning|overclock|ocscan" } |
        Format-Table -AutoSize
}

Write-Host "=== ALL NVOC LOG ENTRIES IN BACKUP CXNATIVE LOG ==="
$log1 = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.1.log"
if (Test-Path $log1) {
    Get-Content $log1 | Where-Object { $_ -match "NvOc|scanner|tuning|overclock|ocscan" } |
        Format-Table -AutoSize
}
