$log = "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App\console.log"
$lines = Get-Content $log
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match "OcScanStatusUpdatesNotifications|GetLastOcScanResults") {
        Write-Host "=== Line $i ==="
        for ($j = [Math]::Max(0, $i - 2); $j -lt [Math]::Min($lines.Length, $i + 20); $j++) {
            Write-Host $lines[$j]
        }
    }
}
