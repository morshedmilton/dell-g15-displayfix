Write-Host "=== RECENT LOG FILES IN PROGRAMDATA NVIDIA APP ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App" -Recurse -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 30 FullName, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "=== RECENT LOG FILES IN LOCALAPPDATA NVIDIA APP ==="
Get-ChildItem -Path "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA App" -Recurse -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 30 FullName, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "=== UPDATEFRAMEWORK CONTENTS ==="
Get-ChildItem -Path "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework" -Recurse |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize
