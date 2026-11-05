Write-Host "=== NVIDIA APPS IN REGISTRY ==="
$paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'NVIDIA' } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, InstallDate |
    Format-Table -AutoSize

Write-Host "=== RUNNING NVIDIA PROCESSES ==="
Get-Process | Where-Object { $_.ProcessName -match 'nv|nvidia' } |
    Select-Object Id, ProcessName, Path, WorkingSet64 |
    Format-Table -AutoSize

Write-Host "=== NVIDIA WINDOWS SERVICES ==="
Get-Service | Where-Object { $_.Name -match 'nv|nvidia' -or $_.DisplayName -match 'nv|nvidia' } |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize
