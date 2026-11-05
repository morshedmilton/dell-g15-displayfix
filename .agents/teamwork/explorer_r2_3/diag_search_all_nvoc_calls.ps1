Write-Host "=== SEARCHING ALL LOGS FOR ENABLEBACKGROUNDOCSCAN OR ENABLEAUTOTUNEOC ==="
$allLogs = Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation", "$env:LOCALAPPDATA\NVIDIA Corporation" -Recurse -Filter "*.log*" -ErrorAction SilentlyContinue
foreach ($l in $allLogs) {
    $found = Select-String -Path $l.FullName -Pattern "EnableBackgroundOcScan|EnableAutotuneOc|OcScan|OverClockingNvc" -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "--- Found in $($l.FullName) ($($found.Count) matches) ---"
        $found | Select-Object -Last 10 | ForEach-Object { $_.Line }
    }
}
