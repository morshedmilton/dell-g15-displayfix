Write-Host "=== WINDOWS APPLICATION EVENT LOG (NVIDIA / CRASH / HANG) ==="
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=(Get-Date).AddDays(-3)} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "NVIDIA|nv|nvcontainer|Display|dwm|tuning|overclock" -or $_.ProviderName -match "NVIDIA|Application Error|Application Hang" } |
    Select-Object -First 30 TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Format-Table -AutoSize

Write-Host "=== WINDOWS SYSTEM EVENT LOG (DISPLAY / GPU / TDR) ==="
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date).AddDays(-3)} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "nv|display|gpu|4101" -or $_.ProviderName -match "nvlddmkm|Display" -or $_.Id -eq 4101 } |
    Select-Object -First 30 TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Format-Table -AutoSize
