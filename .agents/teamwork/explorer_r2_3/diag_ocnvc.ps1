Write-Host "=== SEARCHING ALL LOGS FOR OVERCLOCKINGNVC ==="
$nvLogs = Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation", "$env:LOCALAPPDATA\NVIDIA Corporation" -Recurse -Filter "*.log*" -ErrorAction SilentlyContinue
foreach ($log in $nvLogs) {
    $matches = Select-String -Path $log.FullName -Pattern "OverClockingNvc" -ErrorAction SilentlyContinue
    if ($matches) {
        Write-Host "--- Found in $($log.FullName) ($($matches.Count) matches) ---"
        $matches | Select-Object -First 10 | ForEach-Object { $_.Line }
    }
}
