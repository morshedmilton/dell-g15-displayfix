Write-Host "=== OVERCLOCKINGNVC SYMLINK TARGET ==="
Get-Item "C:\Program Files\NVIDIA Corporation\NvContainer\Plugins\Session\OverClockingNvc" | Select-Object FullName, LinkType, Target

Write-Host "=== CONTENT OF TARGET ==="
Get-ChildItem -Path "C:\Program Files\NVIDIA Corporation\NvContainer\Plugins\Session\OverClockingNvc" | Format-Table -AutoSize

Write-Host "=== SEARCHING SESSION LOGS FOR OVERCLOCKING ==="
$sessionLogs = Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\NvContainer" -Filter "*Session*.log*"
foreach ($l in $sessionLogs) {
    Write-Host "`n--- Matches in $($l.FullName) ---"
    Select-String -Path $l.FullName -Pattern "OverClocking|NvOc|Plugin" -ErrorAction SilentlyContinue |
        Select-Object -First 20 | ForEach-Object { $_.Line }
}
