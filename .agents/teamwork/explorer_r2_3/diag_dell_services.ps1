Write-Host "=== DELL / ALIENWARE SERVICES ==="
Get-Service | Where-Object { $_.Name -match "dell|alienware|awcc" -or $_.DisplayName -match "dell|alienware|awcc" } |
    Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize

Write-Host "=== DELL / ALIENWARE PROCESSES ==="
Get-Process | Where-Object { $_.ProcessName -match "dell|alienware|awcc|awperf" } |
    Select-Object Id, ProcessName, Path | Format-Table -AutoSize

Write-Host "=== CHECK NVPERF / PERFORMANCE REGISTRY KEYS ==="
Get-ItemProperty -Path "HKLM:\SOFTWARE\NVIDIA Corporation\Global\*" -ErrorAction SilentlyContinue | Format-List
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*" -ErrorAction SilentlyContinue |
    Select-Object DriverDesc, MatchingDeviceId, *Power*, *Perf* | Format-List
