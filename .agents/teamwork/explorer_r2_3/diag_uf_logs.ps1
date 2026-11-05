Write-Host "=== SEARCHING FOR UPDATEFRAMEWORK LOGS ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation", "$env:LOCALAPPDATA\NVIDIA Corporation" -Recurse -Filter "*update*.log*" -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Host "=== SEARCHING FOR ALL .LOG FILES IN NVIDIA APP ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App", "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App" -Recurse -Filter "*.log*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
