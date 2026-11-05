Write-Host "=== SEARCHING FOR OCSCAN / AUTOTUNE IN LOGS ==="
$logFiles = @(
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log.bak",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.log",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\CxNative_NVIDIA App.1.log"
)

foreach ($f in $logFiles) {
    if (Test-Path $f) {
        Write-Host "`n--- Matches in $f ---"
        Select-String -Path $f -Pattern "OcScan|AutoTune|StartOc|StopOc|Power Status|Tuning" -CaseSensitive:$false |
            Select-Object -First 40 |
            ForEach-Object { $_.Line }
    }
}
